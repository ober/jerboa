#!chezscheme
;;; (std security sandbox) — One-call sandbox entry point
;;;
;;; Combines Landlock (filesystem), seccomp (syscalls), capabilities
;;; (runtime enforcement), restricted evaluation, and timeouts into
;;; a single `run-safe` call.
;;;
;;; Usage:
;;;   ;; Run untrusted thunk with all protections (uses defaults):
;;;   (run-safe (lambda () (+ 1 2)))
;;;
;;;   ;; Run with custom config:
;;;   (run-safe (lambda () (+ 1 2))
;;;     (make-sandbox-config
;;;       'timeout 10
;;;       'seccomp 'io-only
;;;       'landlock (make-readonly-ruleset "/usr/lib" "/lib")))
;;;
;;;   ;; Evaluate a string in a fully sandboxed environment:
;;;   (run-safe-eval "(+ 1 2)")
;;;   (run-safe-eval "(+ 1 2)" (make-sandbox-config 'timeout 10))
;;;
;;; All kernel protections (Landlock, seccomp) are IRREVERSIBLE.
;;; run-safe forks a child process so the parent remains unrestricted.
;;; The child applies protections, runs the thunk, and sends the result
;;; back via a pipe.

(library (std security sandbox)
  (export
    run-safe
    run-safe-eval
    make-sandbox-config
    sandbox-config?
    *sandbox-timeout*
    *sandbox-seccomp*
    *sandbox-landlock*

    ;; Config accessors
    sandbox-config-timeout
    sandbox-config-seccomp
    sandbox-config-landlock
    sandbox-config-capabilities

    ;; Condition type
    &sandbox-error make-sandbox-error sandbox-error?
    sandbox-error-phase sandbox-error-detail)

  (import (chezscheme)
          (std security landlock)
          (std security seccomp)
          (std security capability)
          (std security restrict)
          (std safe-timeout)
          (std error conditions))

  ;; ========== Condition type ==========

  (define-condition-type &sandbox-error &jerboa
    make-sandbox-error sandbox-error?
    (phase sandbox-error-phase)      ;; 'landlock | 'seccomp | 'capability | 'timeout | 'eval | 'fork
    (detail sandbox-error-detail))   ;; string or condition

  ;; ========== Default parameters ==========

  ;; Default timeout for sandboxed execution (seconds). #f = no timeout.
  (define *sandbox-timeout* (make-parameter 30))

  ;; Default seccomp filter. Symbol or seccomp-filter object.
  ;; 'compute-only, 'io-only, 'network-server, or a custom filter, or #f for none.
  (define *sandbox-seccomp* (make-parameter 'compute-only))

  ;; Default Landlock ruleset, or #f for none.
  (define *sandbox-landlock* (make-parameter #f))

  ;; ========== Sandbox config record ==========

  (define-record-type (%sandbox-config %make-sandbox-config sandbox-config?)
    (fields
      (immutable timeout %sandbox-config-timeout)
      (immutable seccomp %sandbox-config-seccomp)
      (immutable landlock %sandbox-config-landlock)
      (immutable capabilities %sandbox-config-capabilities)))

  ;; Public accessors
  (define sandbox-config-timeout %sandbox-config-timeout)
  (define sandbox-config-seccomp %sandbox-config-seccomp)
  (define sandbox-config-landlock %sandbox-config-landlock)
  (define sandbox-config-capabilities %sandbox-config-capabilities)

  ;; make-sandbox-config: key-value pairs → sandbox-config record
  ;; (make-sandbox-config 'timeout 10 'seccomp 'io-only)
  (define (make-sandbox-config . args)
    (let loop ([rest args]
               [timeout (*sandbox-timeout*)]
               [seccomp (*sandbox-seccomp*)]
               [landlock (*sandbox-landlock*)]
               [caps '()])
      (if (null? rest)
        (%make-sandbox-config timeout seccomp landlock caps)
        (begin
          (when (null? (cdr rest))
            (error 'make-sandbox-config "key missing value" (car rest)))
          (let ([key (car rest)]
                [val (cadr rest)]
                [remaining (cddr rest)])
            (cond
              [(eq? key 'timeout)
               (loop remaining val seccomp landlock caps)]
              [(eq? key 'seccomp)
               (loop remaining timeout val landlock caps)]
              [(eq? key 'landlock)
               (loop remaining timeout seccomp val caps)]
              [(eq? key 'capabilities)
               (loop remaining timeout seccomp landlock val)]
              [else
               (error 'make-sandbox-config
                 "unknown key; expected timeout, seccomp, landlock, or capabilities"
                 key)]))))))

  ;; ========== Seccomp filter resolution ==========

  (define (resolve-seccomp-filter spec)
    (cond
      [(eq? spec #f) #f]
      [(seccomp-filter? spec) spec]
      [(eq? spec 'compute-only) (compute-only-filter)]
      [(eq? spec 'io-only) (io-only-filter)]
      [(eq? spec 'network-server) (network-server-filter)]
      [else (error 'run-safe
              "invalid seccomp spec; expected #f, 'compute-only, 'io-only, 'network-server, or seccomp-filter"
              spec)]))

  ;; ========== Core: fork-based sandbox ==========
  ;;
  ;; We fork a child process to apply irreversible kernel protections.
  ;; The child:
  ;;   1. Installs Landlock (if provided)
  ;;   2. Installs seccomp (if provided)
  ;;   3. Sets capabilities (if provided)
  ;;   4. Runs the thunk with timeout
  ;;   5. Writes the result to a pipe
  ;; The parent waits and reads the result.
  ;;
  ;; This design ensures the parent process is never restricted.

  (define default-config
    (lambda ()
      (make-sandbox-config)))

  (define (run-safe thunk . maybe-config)
    (let ([cfg (if (null? maybe-config) (default-config) (car maybe-config))])
      (unless (sandbox-config? cfg)
        (error 'run-safe "expected sandbox-config" cfg))
      (let ([seccomp-filter (resolve-seccomp-filter (%sandbox-config-seccomp cfg))])
        (run-safe-internal thunk
          (%sandbox-config-timeout cfg)
          seccomp-filter
          (%sandbox-config-landlock cfg)
          (%sandbox-config-capabilities cfg)))))

  ;; FFI pipe(2) — creates a pair of connected file descriptors
  (define c-pipe
    (guard (exn [#t #f])
      (foreign-procedure "pipe" (u8*) int)))

  (define c-read
    (guard (exn [#t #f])
      (foreign-procedure "read" (int u8* size_t) ssize_t)))

  (define c-write
    (guard (exn [#t #f])
      (foreign-procedure "write" (int u8* size_t) ssize_t)))

  (define c-close
    (guard (exn [#t #f])
      (foreign-procedure "close" (int) int)))

  (define (make-pipe)
    ;; Returns (values read-fd write-fd) or raises error
    (let ([buf (make-bytevector 8 0)])  ;; 2 ints
      (let ([rc (if c-pipe (c-pipe buf) -1)])
        (when (< rc 0)
          (error 'make-pipe "pipe(2) failed"))
        (values (bytevector-s32-native-ref buf 0)
                (bytevector-s32-native-ref buf 4)))))

  (define (fd-write-all fd bv)
    ;; Write entire bytevector to fd
    (let ([len (bytevector-length bv)])
      (let loop ([offset 0])
        (when (< offset len)
          (let ([n (c-write fd (subbytevector bv offset len) (- len offset))])
            (when (<= n 0)
              (error 'fd-write-all "write failed"))
            (loop (+ offset n)))))))

  (define (subbytevector bv start end)
    (let* ([len (- end start)]
           [result (make-bytevector len)])
      (bytevector-copy! bv start result 0 len)
      result))

  (define (fd-read-all fd max-size)
    ;; Read up to max-size bytes from fd until EOF
    (let ([buf (make-bytevector 4096)])
      (let loop ([chunks '()] [total 0])
        (let ([n (c-read fd buf 4096)])
          (cond
            [(<= n 0)
             ;; EOF or error — assemble result
             (let ([result (make-bytevector total)])
               (let copy-loop ([chunks (reverse chunks)] [offset 0])
                 (if (null? chunks) result
                   (let ([chunk (car chunks)])
                     (bytevector-copy! chunk 0 result offset (bytevector-length chunk))
                     (copy-loop (cdr chunks) (+ offset (bytevector-length chunk)))))))]
            [(> (+ total n) max-size)
             (error 'fd-read-all "data exceeds maximum size" max-size)]
            [else
             (let ([chunk (make-bytevector n)])
               (bytevector-copy! buf 0 chunk 0 n)
               (loop (cons chunk chunks) (+ total n)))])))))

  (define (run-safe-internal thunk timeout seccomp-filter landlock-rules capabilities)
    ;; Communication via pipe: child writes result, parent reads it.
    ;; HARDENED: Uses pipe(2) instead of temp files to prevent symlink attacks,
    ;; TOCTOU races, and read-eval injection.
    (let-values ([(read-fd write-fd) (make-pipe)])
      (let ([pid (fork-process)])
        (if (= pid 0)
          ;; === CHILD PROCESS ===
          (begin
            ;; Close read end — child only writes
            (c-close read-fd)
            (guard (exn
                     [#t
                      ;; Send error to parent via pipe
                      (guard (exn2 [#t (c-close write-fd) (exit 2)])
                        (let ([msg (cond
                                     [(sandbox-error? exn)
                                      (format "~a: ~a"
                                        (sandbox-error-phase exn)
                                        (sandbox-error-detail exn))]
                                     [(message-condition? exn)
                                      (condition-message exn)]
                                     [else "unknown sandbox error"])])
                          (let ([data (string->utf8 (format "(error ~s)" msg))])
                            (fd-write-all write-fd data)
                            (c-close write-fd))))
                      (exit 1)])

              ;; Step 1: Install Landlock
              (when (and landlock-rules (landlock-available?))
                (landlock-install! landlock-rules))

              ;; Step 2: Install seccomp AFTER setting up pipe
              ;; Pipe fd is already open, so even compute-only filter works
              (when (and seccomp-filter (seccomp-available?))
                (seccomp-install! seccomp-filter))

              ;; Step 3: Set capabilities
              (unless (null? capabilities)
                (current-capabilities capabilities))

              ;; Step 4: Run thunk with timeout
              (let ([result
                      (if timeout
                        (let ([completed #f]
                              [value (void)])
                          (let ([engine (make-engine (lambda () (thunk)))])
                            (engine (* timeout 10000000)
                              (lambda (ticks val)
                                (set! completed #t)
                                (set! value val))
                              (lambda (new-engine)
                                (set! completed #f))))
                          (unless completed
                            (raise (make-sandbox-error
                                     "sandbox"
                                     'timeout
                                     (format "execution exceeded ~a second timeout"
                                             timeout))))
                          value)
                        (thunk))])

                ;; Step 5: Send result to parent via pipe
                (let ([data (string->utf8 (format "(ok ~s)" result))])
                  (fd-write-all write-fd data)
                  (c-close write-fd)
                  (exit 0)))))

          ;; === PARENT PROCESS ===
          (begin
            ;; Close write end — parent only reads
            (c-close write-fd)
            (let-values ([(wpid status) (waitpid pid)])
              (let* ([raw-data (guard (exn [#t (make-bytevector 0)])
                                 (fd-read-all read-fd (* 1 1024 1024)))] ;; 1MB max
                     [_ (c-close read-fd)]
                     [result-sexp
                       (if (> (bytevector-length raw-data) 0)
                         (guard (exn [#t (list 'error "failed to parse child result")])
                           (let ([str (utf8->string raw-data)])
                             (read (open-input-string str))))
                         (list 'error (format "child exited with status ~a, no output"
                                              status)))])
                (cond
                  [(and (pair? result-sexp) (eq? (car result-sexp) 'ok))
                   (cadr result-sexp)]
                  [(and (pair? result-sexp) (eq? (car result-sexp) 'error))
                   (raise (make-sandbox-error
                            "sandbox"
                            'eval
                            (cadr result-sexp)))]
                  [else
                   (raise (make-sandbox-error
                            "sandbox"
                            'fork
                            (format "child exited with status ~a" status)))]))))))))

  ;; ========== FFI Initialization ==========

  (define _libc
    (guard (e [#t #f])
      (load-shared-object "libc.so.6")))
  (define _libc2
    (guard (e [#t #f])
      (load-shared-object "")))

  (define fork-process
    (guard (e [#t (lambda () (error 'run-safe "fork() not available on this platform"))])
      (foreign-procedure "fork" () int)))

  (define waitpid
    (let ([c-waitpid
            (guard (e [#t (lambda (pid buf flags) -1)])
              (foreign-procedure "waitpid" (int u8* int) int))])
      (lambda (pid)
        (let ([status-buf (make-bytevector 4 0)])
          (let ([result (c-waitpid pid status-buf 0)])
            (values result (bytevector-s32-native-ref status-buf 0)))))))

  ;; ========== run-safe-eval — string evaluation in full sandbox ==========

  (define (run-safe-eval expr-string . maybe-config)
    (let ([cfg (if (null? maybe-config) (default-config) (car maybe-config))])
      (unless (sandbox-config? cfg)
        (error 'run-safe-eval "expected sandbox-config" cfg))
      (let ([seccomp-filter (resolve-seccomp-filter (%sandbox-config-seccomp cfg))])
        (run-safe-internal
          (lambda ()
            (restricted-eval-string expr-string))
          (%sandbox-config-timeout cfg)
          seccomp-filter
          (%sandbox-config-landlock cfg)
          (%sandbox-config-capabilities cfg)))))

) ;; end library
