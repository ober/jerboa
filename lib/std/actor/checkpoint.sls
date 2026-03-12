#!chezscheme
;;; (std actor checkpoint) — Actor state and value checkpointing
;;;
;;; Serialize Scheme data (and actor mailbox contents) to files so that
;;; actor state can be checkpointed and restored after restarts.
;;;
;;; Serialization uses Chez Scheme's fasl-write/fasl-read for binary-safe
;;; roundtripping of basic Scheme values.  Procedures, ports, and continuations
;;; are NOT serializable — checkpoint-serializable? returns #f for them.

(library (std actor checkpoint)
  (export
    ;; Core value serialization
    checkpoint-value
    restore-value
    checkpoint-serializable?
    serialize-value
    deserialize-value

    ;; Actor mailbox checkpointing
    checkpoint-actor-mailbox
    restore-actor-mailbox

    ;; Periodic checkpoint manager
    make-checkpoint-manager
    checkpoint-manager?
    checkpoint-manager-start!
    checkpoint-manager-stop!
    checkpoint-manager-register!
    checkpoint-manager-restore
    checkpoint-manager-path

    ;; Utilities
    list-checkpoints
    checkpoint-age
    delete-old-checkpoints)

  (import (chezscheme)
          (std actor mpsc)
          (std actor core))

  ;; -------- Serializable? predicate --------
  ;;
  ;; Conservative check: only pure data values are checkpointable.
  ;; Procedures, ports, conditions, continuations are excluded.

  (define (checkpoint-serializable? val)
    (cond
      [(null? val)       #t]
      [(boolean? val)    #t]
      [(number? val)     #t]
      [(string? val)     #t]
      [(symbol? val)     #t]
      [(char? val)       #t]
      [(bytevector? val) #t]
      [(pair? val)
       (and (checkpoint-serializable? (car val))
            (checkpoint-serializable? (cdr val)))]
      [(vector? val)
       (let loop ([i 0])
         (or (= i (vector-length val))
             (and (checkpoint-serializable? (vector-ref val i))
                  (loop (+ i 1)))))]
      [else #f]))

  ;; -------- Core serialization --------
  ;;
  ;; serialize-value: any serializable value -> bytevector
  ;; deserialize-value: bytevector -> value

  (define (serialize-value val)
    (unless (checkpoint-serializable? val)
      (error 'serialize-value "value is not serializable" val))
    (let-values ([(port get-bytes) (open-bytevector-output-port)])
      (fasl-write val port)
      (get-bytes)))

  (define (deserialize-value bv)
    (let ([port (open-bytevector-input-port bv)])
      (fasl-read port)))

  ;; -------- File-based checkpointing --------

  (define (checkpoint-value val path)
    (unless (checkpoint-serializable? val)
      (error 'checkpoint-value "value is not serializable" val))
    (let ([bv (serialize-value val)])
      (call-with-port (open-file-output-port path
                        (file-options no-fail)
                        (buffer-mode block))
        (lambda (port)
          (put-bytevector port bv)))))

  (define (restore-value path)
    (let* ([bv (call-with-port (open-file-input-port path)
                 (lambda (port)
                   (get-bytevector-all port)))])
      (if (eof-object? bv)
        (error 'restore-value "checkpoint file is empty" path)
        (deserialize-value bv))))

  ;; -------- Actor mailbox checkpointing --------
  ;;
  ;; Drains all pending messages from the actor's MPSC queue and writes
  ;; only the serializable ones to the checkpoint file.
  ;;
  ;; NOTE: This destructively reads the mailbox.  Use only when the actor
  ;; is stopped or known to be idle.

  (define (checkpoint-actor-mailbox actor-ref path)
    (unless (actor-ref? actor-ref)
      (error 'checkpoint-actor-mailbox "not an actor-ref" actor-ref))
    (let ([mailbox (actor-ref-mailbox actor-ref)])
      (unless mailbox
        (error 'checkpoint-actor-mailbox "actor has no local mailbox (remote ref?)" actor-ref))
      ;; Drain all available messages
      (let loop ([msgs '()])
        (let-values ([(msg ok) (mpsc-try-dequeue! mailbox)])
          (if ok
            (loop (if (checkpoint-serializable? msg)
                    (cons msg msgs)
                    msgs))
            ;; Write the messages we collected (in original order)
            (checkpoint-value (reverse msgs) path))))))

  (define (restore-actor-mailbox path)
    ;; Returns a list of messages from the checkpoint
    (if (file-exists? path)
      (restore-value path)
      '()))

  ;; -------- Checkpoint manager record --------

  (define-record-type checkpoint-manager
    (fields
      (immutable path)            ;; checkpoint directory path
      (mutable   registry)        ;; alist of (key . thunk)
      (mutable   running?)        ;; #t while the background thread is running
      (immutable mutex)           ;; protects registry and running?
      (immutable cond-var))       ;; signaled to wake manager thread
    (protocol
      (lambda (new)
        (lambda (path)
          (new path '() #f (make-mutex) (make-condition)))))
    (sealed #t))

  ;; -------- checkpoint-manager-start! --------
  ;; Start a background thread that checkpoints registered values every
  ;; interval-ms milliseconds.

  (define (checkpoint-manager-start! mgr interval-ms)
    (unless (checkpoint-manager-running? mgr)
      (with-mutex (checkpoint-manager-mutex mgr)
        (checkpoint-manager-running?-set! mgr #t))
      (fork-thread
        (lambda ()
          (let loop ()
            (when (checkpoint-manager-running? mgr)
              ;; Sleep for interval-ms by waiting on the condition with a timeout.
              ;; condition-wait timeout must be a time-duration or time-utc record.
              (with-mutex (checkpoint-manager-mutex mgr)
                (let ([timeout (make-time 'time-duration
                                          ;; nanoseconds part (round to 0)
                                          0
                                          ;; seconds part
                                          (max 1 (inexact->exact (round (/ interval-ms 1000)))))])
                  (condition-wait
                    (checkpoint-manager-cond-var mgr)
                    (checkpoint-manager-mutex mgr)
                    timeout)))
              (when (checkpoint-manager-running? mgr)
                ;; Snapshot all registered thunks
                (let ([registry
                       (with-mutex (checkpoint-manager-mutex mgr)
                         (checkpoint-manager-registry mgr))])
                  (for-each
                    (lambda (entry)
                      (let ([key (car entry)]
                            [thunk (cdr entry)])
                        (guard (exn [#t (void)]) ; silently skip failures
                          (let ([val (thunk)])
                            (when (checkpoint-serializable? val)
                              (let ([file (checkpoint-file-for-key
                                            (checkpoint-manager-path mgr)
                                            key)])
                                (checkpoint-value val file)))))))
                    registry))
                (loop))))))))

  ;; -------- checkpoint-manager-stop! --------

  (define (checkpoint-manager-stop! mgr)
    (with-mutex (checkpoint-manager-mutex mgr)
      (checkpoint-manager-running?-set! mgr #f)
      (condition-broadcast (checkpoint-manager-cond-var mgr))))

  ;; -------- checkpoint-manager-register! --------

  (define (checkpoint-manager-register! mgr key thunk)
    (with-mutex (checkpoint-manager-mutex mgr)
      (let ([existing (assoc key (checkpoint-manager-registry mgr))])
        (if existing
          (set-cdr! existing thunk)
          (checkpoint-manager-registry-set!
            mgr
            (cons (cons key thunk) (checkpoint-manager-registry mgr)))))))

  ;; -------- checkpoint-manager-restore --------
  ;; Restores the most recent checkpoint for a key, or returns #f if none.

  (define (checkpoint-manager-restore mgr key)
    (let ([file (checkpoint-file-for-key (checkpoint-manager-path mgr) key)])
      (and (file-exists? file)
           (guard (exn [#t #f])
             (restore-value file)))))

  ;; -------- Internal helpers --------

  ;; Build a checkpoint file path: <dir>/<key>.chk
  ;; key may be any value; we use its string representation.
  (define (checkpoint-file-for-key dir key)
    (string-append dir "/"
                   (sanitize-key (format "~a" key))
                   ".chk"))

  ;; Replace characters that are unsafe in filenames with underscores.
  (define (sanitize-key s)
    (list->string
      (map (lambda (c)
             (if (or (char-alphabetic? c) (char-numeric? c)
                     (char=? c #\-) (char=? c #\_))
               c #\_))
           (string->list s))))

  ;; -------- list-checkpoints --------
  ;; Returns a list of .chk file paths in dir.

  (define (list-checkpoints dir)
    (if (file-directory? dir)
      (let ([entries (directory-list dir)])
        (filter (lambda (name) (string-suffix? ".chk" name))
                (map (lambda (name) (string-append dir "/" name))
                     entries)))
      '()))

  ;; -------- checkpoint-age --------
  ;; Returns the age in seconds of a checkpoint file, or +inf.0 if it doesn't exist.

  (define (checkpoint-age path)
    (if (file-exists? path)
      (let* ([mtime (file-modification-time path)]
             [now   (current-time 'time-utc)]
             ;; Both are time objects with time-second and time-nanosecond
             [delta (- (time-second now) (time-second mtime))])
        (max 0 delta))
      +inf.0))

  ;; -------- delete-old-checkpoints --------
  ;; Delete any .chk files in dir that are older than max-age-secs seconds.

  (define (delete-old-checkpoints dir max-age-secs)
    (let ([files (list-checkpoints dir)])
      (for-each
        (lambda (path)
          (when (> (checkpoint-age path) max-age-secs)
            (guard (exn [#t (void)])
              (delete-file path))))
        files)))

  ;; -------- string-suffix? --------

  (define (string-suffix? suffix str)
    (let ([slen (string-length suffix)]
          [len  (string-length str)])
      (and (>= len slen)
           (string=? suffix (substring str (- len slen) len)))))

) ;; end library
