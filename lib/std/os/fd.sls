#!chezscheme
;;; (std os fd) — Structured FD and process lifecycle manager
;;;
;;; Track 24: Guaranteed fd cleanup via dynamic-wind, ownership tracking,
;;; pipe abstractions, and pipeline combinators.

(library (std os fd)
  (export
    ;; FD objects
    make-fd fd? fd-num fd-open? fd-close!
    fd-dup fd-dup2 fd-pipe fd-redirect!
    fd-read fd-write
    with-fds
    pipe-read pipe-write

    ;; Process spawning
    spawn-process
    process? process-pid process-status process-wait
    process-exited? process-exit-code process-signaled? process-signal

    ;; Pipeline
    run-pipeline

    ;; FD constants
    STDIN_FILENO STDOUT_FILENO STDERR_FILENO)

  (import (chezscheme))

  ;; ========== Constants ==========
  (define STDIN_FILENO  0)
  (define STDOUT_FILENO 1)
  (define STDERR_FILENO 2)

  ;; ========== Low-level FFI ==========
  (define c-dup    (foreign-procedure "dup" (int) int))
  (define c-dup2   (foreign-procedure "dup2" (int int) int))
  (define c-close  (foreign-procedure "close" (int) int))
  (define c-pipe   (foreign-procedure "pipe" (void*) int))
  (define c-read   (foreign-procedure "read" (int u8* size_t) ssize_t))
  (define c-write  (foreign-procedure "write" (int u8* size_t) ssize_t))
  (define c-fork   (foreign-procedure "fork" () int))
  (define c-exit   (foreign-procedure "_exit" (int) void))
  (define c-execvp (foreign-procedure "execvp" (string void*) int))
  (define c-waitpid (foreign-procedure "waitpid" (int void* int) int))

  ;; ========== FD Objects ==========

  (define-record-type fd-obj
    (fields
      (immutable num)       ;; raw fd number
      (mutable open?)       ;; #t if still open
      (immutable owner?))   ;; #t if we own this fd (should close it)
    (protocol
      (lambda (new)
        (case-lambda
          [(num) (new num #t #t)]
          [(num owner?) (new num #t owner?)]))))

  (define (make-fd num . rest)
    (let ([owner? (if (pair? rest) (car rest) #t)])
      (make-fd-obj num owner?)))

  (define (fd? x) (fd-obj? x))
  (define (fd-num fd) (fd-obj-num fd))
  (define (fd-open? fd) (fd-obj-open? fd))

  (define (fd-close! fd)
    (when (and (fd-obj-open? fd) (fd-obj-owner? fd))
      (c-close (fd-obj-num fd))
      (fd-obj-open?-set! fd #f)))

  ;; ========== FD Operations ==========

  (define (fd-dup source-fd)
    (let ([n (if (fd? source-fd) (fd-num source-fd) source-fd)])
      (let ([new-fd (c-dup n)])
        (if (= new-fd -1)
          (error 'fd-dup "dup failed" n)
          (make-fd new-fd)))))

  (define (fd-dup2 old-fd new-fd-num)
    (let ([o (if (fd? old-fd) (fd-num old-fd) old-fd)])
      (let ([rc (c-dup2 o new-fd-num)])
        (if (= rc -1)
          (error 'fd-dup2 "dup2 failed" o new-fd-num)
          rc))))

  (define (fd-redirect! source target-fd-num)
    ;; dup2 source onto target, then close source
    (let ([src-num (if (fd? source) (fd-num source) source)])
      (fd-dup2 src-num target-fd-num)
      (when (fd? source) (fd-close! source))))

  (define (fd-pipe)
    ;; Returns (values read-fd write-fd) as fd objects
    (let ([buf (foreign-alloc 8)])
      (dynamic-wind
        void
        (lambda ()
          (let ([rc (c-pipe buf)])
            (if (= rc -1)
              (error 'fd-pipe "pipe failed")
              (values (make-fd (foreign-ref 'int buf 0))
                      (make-fd (foreign-ref 'int buf 4))))))
        (lambda () (foreign-free buf)))))

  (define (pipe-read pair)
    ;; For compatibility, extract from a pipe pair
    (if (fd? pair) pair (car pair)))

  (define (pipe-write pair)
    (if (fd? pair) pair (cdr pair)))

  (define (fd-read fd count)
    (let ([n (if (fd? fd) (fd-num fd) fd)]
          [buf (make-bytevector count)])
      (let ([rc (c-read n buf count)])
        (cond
          [(< rc 0) (error 'fd-read "read failed" n)]
          [(= rc 0) (make-bytevector 0)]
          [(= rc count) buf]
          [else
           (let ([result (make-bytevector rc)])
             (bytevector-copy! buf 0 result 0 rc)
             result)]))))

  (define (fd-write fd bv)
    (let ([n (if (fd? fd) (fd-num fd) fd)])
      (let ([rc (c-write n bv (bytevector-length bv))])
        (if (< rc 0)
          (error 'fd-write "write failed" n)
          rc))))

  ;; ========== with-fds Macro ==========
  ;; Guarantees cleanup of all fds on exit (normal or exception)

  (define-syntax with-fds
    (syntax-rules ()
      [(_ () body ...)
       (begin body ...)]
      [(_ ([var expr] rest ...) body ...)
       (let ([var expr])
         (dynamic-wind
           void
           (lambda ()
             (with-fds (rest ...) body ...))
           (lambda ()
             (when (fd? var) (fd-close! var)))))]))

  ;; ========== Process Records ==========

  (define-record-type process-rec
    (fields
      (immutable pid)
      (mutable status)
      (mutable waited?))
    (protocol
      (lambda (new)
        (lambda (pid)
          (new pid #f #f)))))

  (define (process? x) (process-rec? x))
  (define (process-pid p) (process-rec-pid p))
  (define (process-status p) (process-rec-status p))

  (define (process-wait p . opts)
    ;; Wait for process to exit, return status
    (unless (process-rec-waited? p)
      (let ([flags (if (and (pair? opts) (car opts)) 1 0)]  ;; WNOHANG = 1
            [status-buf (foreign-alloc 4)])
        (dynamic-wind
          void
          (lambda ()
            (let ([rc (c-waitpid (process-rec-pid p) status-buf flags)])
              (when (> rc 0)
                (process-rec-status-set! p (foreign-ref 'int status-buf 0))
                (process-rec-waited?-set! p #t))))
          (lambda () (foreign-free status-buf)))))
    (process-rec-status p))

  (define (process-exited? p)
    (and (process-rec-status p)
         (= (bitwise-and (process-rec-status p) #x7f) 0)))

  (define (process-exit-code p)
    (and (process-exited? p)
         (bitwise-arithmetic-shift-right
           (bitwise-and (process-rec-status p) #xff00) 8)))

  (define (process-signaled? p)
    (let ([s (process-rec-status p)])
      (and s
           (let ([lo (bitwise-and s #x7f)])
             (and (not (= lo 0)) (not (= lo #x7f)))))))

  (define (process-signal p)
    (and (process-signaled? p)
         (bitwise-and (process-rec-status p) #x7f)))

  ;; ========== Process Spawning ==========

  (define (spawn-process cmd-list . options)
    ;; Fork and exec a command. Returns a process object.
    ;; cmd-list: list of strings (command + args)
    ;; Options: stdin: fd, stdout: fd, stderr: fd
    (let ([stdin-fd  (extract-kw options 'stdin: #f)]
          [stdout-fd (extract-kw options 'stdout: #f)]
          [stderr-fd (extract-kw options 'stderr: #f)])
      (let ([pid (c-fork)])
        (cond
          [(< pid 0) (error 'spawn-process "fork failed")]
          [(= pid 0)
           ;; Child process
           (guard (e [#t (c-exit 127)])
             (when stdin-fd
               (c-dup2 (if (fd? stdin-fd) (fd-num stdin-fd) stdin-fd) 0))
             (when stdout-fd
               (c-dup2 (if (fd? stdout-fd) (fd-num stdout-fd) stdout-fd) 1))
             (when stderr-fd
               (c-dup2 (if (fd? stderr-fd) (fd-num stderr-fd) stderr-fd) 2))
             ;; Build argv as a packed null-terminated array
             (exec-with-argv (car cmd-list) cmd-list))
           (c-exit 127)]
          [else
           ;; Parent process
           (make-process-rec pid)]))))

  (define (exec-with-argv path args)
    ;; Build a NULL-terminated array of C strings for execvp
    (let* ([n (length args)]
           [ptrs (foreign-alloc (* (+ n 1) 8))])  ;; (n+1) pointers
      ;; Set each pointer to a copy of the argument string
      (let lp ([i 0] [args args])
        (if (null? args)
          (begin
            (foreign-set! 'void* ptrs (* i 8) 0)  ;; NULL terminator
            (c-execvp path ptrs)
            ;; If we get here, exec failed
            (c-exit 127))
          (let* ([s (car args)]
                 [bv (string->utf8 s)]
                 [len (bytevector-length bv)]
                 [buf (foreign-alloc (+ len 1))])
            ;; Copy string bytes
            (do ([j 0 (+ j 1)])
                ((= j len))
              (foreign-set! 'unsigned-8 buf j (bytevector-u8-ref bv j)))
            (foreign-set! 'unsigned-8 buf len 0)  ;; null terminate
            (foreign-set! 'void* ptrs (* i 8) buf)
            (lp (+ i 1) (cdr args)))))))

  ;; ========== Pipeline ==========

  (define (run-pipeline commands . options)
    ;; Run N commands connected by pipes.
    ;; commands: list of lists of strings
    ;; Options: input: fd, output: fd
    ;; Returns list of process objects
    (let ([input-fd  (extract-kw options 'input: #f)]
          [output-fd (extract-kw options 'output: #f)])
      (let ([n (length commands)])
        (if (= n 1)
          ;; Single command
          (list (spawn-process (car commands)
                  'stdin: input-fd
                  'stdout: output-fd))
          ;; Multi-command pipeline
          (let lp ([cmds commands] [i 0] [prev-read-fd input-fd] [procs '()])
            (if (null? cmds)
              (reverse procs)
              (if (null? (cdr cmds))
                ;; Last command
                (let ([proc (spawn-process (car cmds)
                              'stdin: prev-read-fd
                              'stdout: output-fd)])
                  (when (and prev-read-fd (fd? prev-read-fd))
                    (fd-close! prev-read-fd))
                  (reverse (cons proc procs)))
                ;; Intermediate command
                (let-values ([(rfd wfd) (fd-pipe)])
                  (let ([proc (spawn-process (car cmds)
                                'stdin: prev-read-fd
                                'stdout: wfd)])
                    (fd-close! wfd)
                    (when (and prev-read-fd (fd? prev-read-fd))
                      (fd-close! prev-read-fd))
                    (lp (cdr cmds) (+ i 1) rfd (cons proc procs)))))))))))

  (define (extract-kw opts key default)
    (let lp ([opts opts])
      (cond
        [(null? opts) default]
        [(and (pair? opts) (pair? (cdr opts))
              (eq? (car opts) key))
         (cadr opts)]
        [(pair? opts) (lp (cdr opts))]
        [else default])))

  ) ;; end library
