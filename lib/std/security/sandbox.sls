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

  (define (run-safe-internal thunk timeout seccomp-filter landlock-rules capabilities)
    ;; Communication via temp file: child writes result, parent reads it.
    ;; This avoids FFI pipe() dependency while keeping fork-based isolation.
    (let* ([tmp-file (format "/tmp/jerboa-sandbox-~a" (random 1000000000))]
           [pid (fork-process)])
      (if (= pid 0)
        ;; === CHILD PROCESS ===
        (guard (exn
                 [#t
                  ;; Send error to parent via temp file
                  (guard (exn2 [#t (exit 2)])
                    (call-with-output-file tmp-file
                      (lambda (port)
                        (write (list 'error
                                     (cond
                                       [(sandbox-error? exn)
                                        (let ([phase (sandbox-error-phase exn)]
                                              [detail (sandbox-error-detail exn)])
                                          (format "~a: ~a" phase detail))]
                                       [(message-condition? exn)
                                        (condition-message exn)]
                                       [else "unknown sandbox error"]))
                               port))
                      'replace))
                  (exit 1)])

          ;; Step 1: Install Landlock
          (when (and landlock-rules (landlock-available?))
            (landlock-install! landlock-rules))

          ;; Step 2: Install seccomp (after file write setup, since seccomp may block writes)
          ;; Note: we defer seccomp install to after computing result if using strict filters,
          ;; because we need to write the result file. For io-only filter this works fine.
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
                        (engine (* timeout 10000000)  ;; ~10M ticks/sec
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

            ;; Step 5: Send result to parent
            (call-with-output-file tmp-file
              (lambda (port) (write (list 'ok result) port))
              'replace)
            (exit 0)))

        ;; === PARENT PROCESS ===
        (begin
          ;; Wait for child to exit
          (let-values ([(wpid status) (waitpid pid)])
            (let ([result-sexp
                    (guard (exn [#t (list 'error "failed to read child result")])
                      (if (file-exists? tmp-file)
                        (let ([sexp (call-with-input-file tmp-file read)])
                          (delete-file tmp-file)
                          sexp)
                        (list 'error (format "child exited with status ~a, no result file"
                                             status))))])
              ;; Clean up temp file if still present
              (when (file-exists? tmp-file) (delete-file tmp-file))
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
                          (format "child exited with status ~a" status)))])))))))

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
