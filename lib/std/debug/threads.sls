#!chezscheme
;;; (std debug threads) — Thread inspection and debugging
;;;
;;; Maintains a global thread registry for monitoring thread lifecycle
;;; and state.  Threads must opt in via `with-thread-monitor` or manual
;;; registration.  Uses Chez's fork-thread, mutexes, and get-thread-id.

(library (std debug threads)
  (export thread-list thread-count thread-name thread-state
          thread-report with-thread-monitor)

  (import (chezscheme))

  ;; -----------------------------------------------------------------
  ;; Thread info record
  ;; -----------------------------------------------------------------

  (define-record-type thread-info
    (fields (immutable id     thread-info-id)
            (immutable name   thread-info-name)
            (mutable   state  thread-info-state thread-info-state-set!)
            (immutable start  thread-info-start))
    (protocol (lambda (new)
                (lambda (id name)
                  (new id name 'running (current-time 'time-monotonic))))))

  ;; -----------------------------------------------------------------
  ;; Global registry
  ;; -----------------------------------------------------------------

  ;; Registry: eq-hashtable keyed by thread-id (fixnum)
  (define *registry* (make-eq-hashtable))
  (define *registry-mutex* (make-mutex))

  ;; Register a thread in the registry.
  (define (register-thread! id name)
    (with-mutex *registry-mutex*
      (let ([info (make-thread-info id name)])
        (hashtable-set! *registry* id info)
        info)))

  ;; Unregister a thread from the registry.
  (define (unregister-thread! id)
    (with-mutex *registry-mutex*
      (let ([info (hashtable-ref *registry* id #f)])
        (when info
          (thread-info-state-set! info 'finished)))))

  ;; Update thread state.
  (define (update-thread-state! id state)
    (with-mutex *registry-mutex*
      (let ([info (hashtable-ref *registry* id #f)])
        (when info
          (thread-info-state-set! info state)))))

  ;; -----------------------------------------------------------------
  ;; Public API
  ;; -----------------------------------------------------------------

  ;; Return list of all known thread-info records.
  (define (thread-list)
    (with-mutex *registry-mutex*
      (let-values ([(keys vals) (hashtable-entries *registry*)])
        (vector->list vals))))

  ;; Return count of registered threads.
  (define (thread-count)
    (with-mutex *registry-mutex*
      (hashtable-size *registry*)))

  ;; Look up the name of a thread by id, or #f if not registered.
  (define (thread-name id)
    (with-mutex *registry-mutex*
      (let ([info (hashtable-ref *registry* id #f)])
        (and info (thread-info-name info)))))

  ;; Look up the state of a thread by id.
  ;; Returns one of: running, sleeping, blocked, finished, or #f if unknown.
  (define (thread-state id)
    (with-mutex *registry-mutex*
      (let ([info (hashtable-ref *registry* id #f)])
        (and info (thread-info-state info)))))

  ;; Print a formatted table of all registered threads.
  (define (thread-report)
    (let ([threads (thread-list)])
      (display "=== Thread Report ===\n")
      (display (format "  Total registered: ~a\n" (length threads)))
      (display "  ID        Name                State       Uptime(s)\n")
      (display "  --------- ------------------- ----------- ---------\n")
      (let ([now (current-time 'time-monotonic)])
        (for-each
          (lambda (info)
            (let* ([elapsed-sec
                    (let ([dt (time-difference now (thread-info-start info))])
                      (+ (time-second dt)
                         (/ (time-nanosecond dt) 1000000000.0)))]
                   [id-str (format "~a" (thread-info-id info))]
                   [name-str (format "~a" (thread-info-name info))]
                   [state-str (format "~a" (thread-info-state info))])
              (display (format "  ~9a ~19a ~11a ~8,1f\n"
                               id-str name-str state-str elapsed-sec))))
          threads))
      (display "=====================\n")))

  ;; Wrap a thunk so the current thread is automatically registered
  ;; and unregistered.  The thread is registered with the given name.
  ;; Returns a thunk suitable for fork-thread or direct invocation.
  ;;
  ;; Usage:
  ;;   (fork-thread (with-thread-monitor "worker-1" (lambda () ...)))
  ;;   or
  ;;   ((with-thread-monitor "main" (lambda () ...)))
  (define (with-thread-monitor name thunk)
    (lambda ()
      (let ([id (get-thread-id)])
        (register-thread! id name)
        (guard (exn
                [else
                 (update-thread-state! id 'finished)
                 (raise exn)])
          (let ([result (thunk)])
            (update-thread-state! id 'finished)
            result)))))

) ;; end library
