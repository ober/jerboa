#!chezscheme
;;; (std security sandbox) — One-call sandbox entry point
;;;
;;; Combines platform-specific kernel protections, capabilities
;;; (runtime enforcement), restricted evaluation, and timeouts into
;;; a single `run-safe` call.
;;;
;;; Platform protections:
;;;   Linux:   Landlock (filesystem) + seccomp (syscall filtering)
;;;   macOS:   Seatbelt (sandbox_init profiles)
;;;   FreeBSD: Capsicum (capability mode)
;;;
;;; Usage:
;;;   ;; Run untrusted thunk with all protections (uses defaults):
;;;   (run-safe (lambda () (+ 1 2)))
;;;
;;;   ;; Run with custom config (platform-specific keys):
;;;   ;; Linux:
;;;   (run-safe (lambda () (+ 1 2))
;;;     (make-sandbox-config
;;;       'timeout 10
;;;       'seccomp 'io-only
;;;       'landlock (make-readonly-ruleset "/usr/lib" "/lib")))
;;;   ;; macOS:
;;;   (run-safe (lambda () (+ 1 2))
;;;     (make-sandbox-config
;;;       'timeout 10
;;;       'seatbelt 'pure-computation))
;;;   ;; FreeBSD:
;;;   (run-safe (lambda () (+ 1 2))
;;;     (make-sandbox-config
;;;       'timeout 10
;;;       'capsicum #t))
;;;
;;;   ;; Evaluate a string in a fully sandboxed environment:
;;;   (run-safe-eval "(+ 1 2)")
;;;   (run-safe-eval "(+ 1 2)" (make-sandbox-config 'timeout 10))
;;;
;;; All kernel protections are IRREVERSIBLE.
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
    *sandbox-seatbelt*
    *sandbox-capsicum*

    ;; Config accessors
    sandbox-config-timeout
    sandbox-config-seccomp
    sandbox-config-landlock
    sandbox-config-seatbelt
    sandbox-config-capsicum
    sandbox-config-capabilities
    sandbox-config-max-output-size

    ;; Condition type
    &sandbox-error make-sandbox-error sandbox-error?
    sandbox-error-phase sandbox-error-detail)

  (import (chezscheme)
          (std security landlock)
          (std security seccomp)
          (std security seatbelt)
          (std security capsicum)
          (std security capability)
          (std security restrict)
          (std safe-timeout)
          (std error conditions))

  ;; ========== Platform detection ==========

  (define (detect-platform)
    (let ([mt (symbol->string (machine-type))])
      (cond
        [(string-contains-ci mt "osx") 'macos]
        [(string-contains-ci mt "fb")  'freebsd]
        [(string-contains-ci mt "le")  'linux]
        [else                          'unknown])))

  (define (string-contains-ci str sub)
    (let ([slen (string-length str)]
          [sublen (string-length sub)])
      (let lp ([i 0])
        (cond
          [(> (+ i sublen) slen) #f]
          [(string=? (substring str i (+ i sublen)) sub) #t]
          [else (lp (+ i 1))]))))

  (define *current-platform* (detect-platform))

  ;; ========== Condition type ==========

  (define-condition-type &sandbox-error &jerboa
    make-sandbox-error sandbox-error?
    (phase sandbox-error-phase)      ;; 'landlock | 'seccomp | 'seatbelt | 'capsicum | 'capability | 'timeout | 'eval | 'fork
    (detail sandbox-error-detail))   ;; string or condition

  ;; ========== Default parameters ==========

  ;; Default timeout for sandboxed execution (seconds). #f = no timeout.
  (define *sandbox-timeout* (make-parameter 30))

  ;; Default seccomp filter (Linux). Symbol or seccomp-filter object.
  ;; 'compute-only, 'io-only, 'network-server, or a custom filter, or #f for none.
  (define *sandbox-seccomp* (make-parameter 'compute-only))

  ;; Default Landlock ruleset (Linux), or #f for none.
  (define *sandbox-landlock* (make-parameter #f))

  ;; Default Seatbelt profile (macOS).
  ;; Symbol ('pure-computation, 'no-write, 'no-network, etc.),
  ;; SBPL string, or #f for none.
  ;; Default: 'pure-computation on macOS, #f elsewhere.
  (define *sandbox-seatbelt*
    (make-parameter
      (if (eq? *current-platform* 'macos) 'pure-computation #f)))

  ;; Default Capsicum mode (FreeBSD).
  ;; #f to skip, #t for bare cap_enter(), or a preset symbol:
  ;;   'compute-only — restrict stdio fds + cap_enter (analogous to seccomp compute-only)
  ;;   'io-only      — like compute-only but allows pre-opened fds
  ;; Default: 'compute-only on FreeBSD, #f elsewhere.
  (define *sandbox-capsicum*
    (make-parameter
      (if (eq? *current-platform* 'freebsd) 'compute-only #f)))

  ;; ========== Sandbox config record ==========

  (define-record-type (%sandbox-config %make-sandbox-config sandbox-config?)
    (fields
      (immutable timeout   %sandbox-config-timeout)
      (immutable seccomp   %sandbox-config-seccomp)
      (immutable landlock  %sandbox-config-landlock)
      (immutable seatbelt  %sandbox-config-seatbelt)
      (immutable capsicum  %sandbox-config-capsicum)
      (immutable capabilities %sandbox-config-capabilities)
      (immutable max-output-size %sandbox-config-max-output-size)))

  ;; Public accessors
  (define sandbox-config-timeout      %sandbox-config-timeout)
  (define sandbox-config-seccomp      %sandbox-config-seccomp)
  (define sandbox-config-landlock     %sandbox-config-landlock)
  (define sandbox-config-seatbelt     %sandbox-config-seatbelt)
  (define sandbox-config-capsicum     %sandbox-config-capsicum)
  (define sandbox-config-capabilities %sandbox-config-capabilities)
  (define sandbox-config-max-output-size %sandbox-config-max-output-size)

  ;; make-sandbox-config: key-value pairs → sandbox-config record
  ;; (make-sandbox-config 'timeout 10 'seccomp 'io-only)
  ;; (make-sandbox-config 'timeout 10 'seatbelt 'no-write)
  ;; (make-sandbox-config 'timeout 10 'capsicum #t)
  ;; Default max output size: 1 MB
  (define *sandbox-max-output-size* (make-parameter (* 1 1024 1024)))

  (define (make-sandbox-config . args)
    (let loop ([rest args]
               [timeout  (*sandbox-timeout*)]
               [seccomp  (*sandbox-seccomp*)]
               [landlock (*sandbox-landlock*)]
               [seatbelt (*sandbox-seatbelt*)]
               [capsicum (*sandbox-capsicum*)]
               [caps '()]
               [max-output (*sandbox-max-output-size*)])
      (if (null? rest)
        (%make-sandbox-config timeout seccomp landlock seatbelt capsicum caps max-output)
        (begin
          (when (null? (cdr rest))
            (error 'make-sandbox-config "key missing value" (car rest)))
          (let ([key (car rest)]
                [val (cadr rest)]
                [remaining (cddr rest)])
            (cond
              [(eq? key 'timeout)
               (loop remaining val seccomp landlock seatbelt capsicum caps max-output)]
              [(eq? key 'seccomp)
               (loop remaining timeout val landlock seatbelt capsicum caps max-output)]
              [(eq? key 'landlock)
               (loop remaining timeout seccomp val seatbelt capsicum caps max-output)]
              [(eq? key 'seatbelt)
               (loop remaining timeout seccomp landlock val capsicum caps max-output)]
              [(eq? key 'capsicum)
               (loop remaining timeout seccomp landlock seatbelt val caps max-output)]
              [(eq? key 'capabilities)
               (loop remaining timeout seccomp landlock seatbelt capsicum val max-output)]
              [(eq? key 'max-output-size)
               (loop remaining timeout seccomp landlock seatbelt capsicum caps val)]
              [else
               (error 'make-sandbox-config
                 "unknown key; expected timeout, seccomp, landlock, seatbelt, capsicum, capabilities, or max-output-size"
                 key)]))))))

  ;; ========== Seccomp filter resolution (Linux) ==========

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

  ;; ========== Seatbelt profile resolution (macOS) ==========

  (define (resolve-seatbelt-profile spec)
    ;; Returns: #f, a named profile symbol, or a raw SBPL string.
    (cond
      [(eq? spec #f) #f]
      [(string? spec) spec]  ;; raw SBPL string
      [(memq spec '(pure-computation no-write no-write-except-temporary
                    no-internet no-network))
       spec]
      [else (error 'run-safe
              "invalid seatbelt spec; expected #f, a profile symbol, or an SBPL string"
              spec)]))

  ;; ========== Capsicum mode resolution (FreeBSD) ==========

  (define (resolve-capsicum-mode spec pipe-fd)
    ;; Resolve capsicum config to an actionable value.
    ;; Returns: #f, 'bare, or a preset alist.
    (cond
      [(eq? spec #f) #f]
      [(eq? spec #t) 'bare]                                ;; backward compat
      [(eq? spec 'compute-only)
       (capsicum-compute-only-preset pipe-fd)]
      [(eq? spec 'io-only)
       (capsicum-io-only-preset pipe-fd '())]
      [(and (list? spec) (pair? spec)
            (pair? (car spec)) (integer? (caar spec)))
       spec]                                                ;; raw preset alist
      [else (error 'run-safe
              "invalid capsicum spec; expected #f, #t, 'compute-only, 'io-only, or preset alist"
              spec)]))

  ;; ========== Core: fork-based sandbox ==========
  ;;
  ;; We fork a child process to apply irreversible kernel protections.
  ;; The child:
  ;;   1. Installs platform-specific protections
  ;;   2. Sets capabilities (if provided)
  ;;   3. Runs the thunk with timeout
  ;;   4. Writes the result to a pipe
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
      (let ([seccomp-filter (resolve-seccomp-filter (%sandbox-config-seccomp cfg))]
            [seatbelt-profile (resolve-seatbelt-profile (%sandbox-config-seatbelt cfg))]
            [capsicum-mode (%sandbox-config-capsicum cfg)])
        (run-safe-internal thunk
          (%sandbox-config-timeout cfg)
          seccomp-filter
          (%sandbox-config-landlock cfg)
          seatbelt-profile
          capsicum-mode
          (%sandbox-config-capabilities cfg)
          (%sandbox-config-max-output-size cfg)))))

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

  ;; ========== Platform-specific protection installation ==========

  (define (install-linux-protections! landlock-rules seccomp-filter)
    ;; Step 1: Install Landlock filesystem restrictions
    (when (and landlock-rules (landlock-available?))
      (landlock-install! landlock-rules))
    ;; Step 2: Install seccomp syscall filter
    (when (and seccomp-filter (seccomp-available?))
      (seccomp-install! seccomp-filter)))

  (define (install-macos-protections! seatbelt-profile)
    ;; Install Seatbelt sandbox profile
    (when seatbelt-profile
      (if (seatbelt-available?)
        (if (string? seatbelt-profile)
          ;; Raw SBPL string
          (seatbelt-install-profile! seatbelt-profile)
          ;; Named profile symbol
          (seatbelt-install! seatbelt-profile))
        ;; Seatbelt not available — warn but don't fail
        ;; (could be running on a very old macOS or in a container)
        (void))))

  (define (install-freebsd-protections! resolved-capsicum)
    ;; Apply Capsicum protections based on resolved mode:
    ;;   #f     — skip
    ;;   'bare  — just cap_enter() (backward compat with 'capsicum #t)
    ;;   alist  — restrict fds per preset, then cap_enter()
    (when resolved-capsicum
      (if (capsicum-available?)
        (cond
          [(eq? resolved-capsicum 'bare)
           (capsicum-enter!)]
          [(list? resolved-capsicum)
           (capsicum-apply-preset! resolved-capsicum)])
        ;; Capsicum not available — warn but don't fail
        (void))))

  ;; ========== Core sandbox implementation ==========

  (define (run-safe-internal thunk timeout seccomp-filter landlock-rules
                             seatbelt-profile capsicum-mode capabilities
                             max-output-size)
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

              ;; Install platform-specific protections
              (case *current-platform*
                [(linux)
                 (install-linux-protections! landlock-rules seccomp-filter)]
                [(macos)
                 (install-macos-protections! seatbelt-profile)]
                [(freebsd)
                 ;; Resolve capsicum mode here in the child, where we know the pipe fd
                 (let ([resolved (resolve-capsicum-mode capsicum-mode write-fd)])
                   (install-freebsd-protections! resolved))]
                [else (void)])  ;; Unknown platform — run without kernel protections

              ;; Set capabilities (cross-platform runtime enforcement)
              (unless (null? capabilities)
                (current-capabilities capabilities))

              ;; Run thunk with timeout
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

                ;; Send result to parent via pipe
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
                                 (fd-read-all read-fd max-output-size))]
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

  ;; Load libc — platform-specific library names
  (define _libc
    (or (guard (e [#t #f]) (load-shared-object "libc.so.6"))       ;; Linux
        (guard (e [#t #f]) (load-shared-object "libc.dylib"))      ;; macOS
        (guard (e [#t #f]) (load-shared-object "libc.so.7"))       ;; FreeBSD
        (guard (e [#t #f]) (load-shared-object "libc.so"))         ;; generic
        (guard (e [#t #f]) (load-shared-object ""))))              ;; default

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
      (let ([seccomp-filter (resolve-seccomp-filter (%sandbox-config-seccomp cfg))]
            [seatbelt-profile (resolve-seatbelt-profile (%sandbox-config-seatbelt cfg))]
            [capsicum-mode (%sandbox-config-capsicum cfg)])
        (run-safe-internal
          (lambda ()
            (restricted-eval-string expr-string))
          (%sandbox-config-timeout cfg)
          seccomp-filter
          (%sandbox-config-landlock cfg)
          seatbelt-profile
          capsicum-mode
          (%sandbox-config-capabilities cfg)
          (%sandbox-config-max-output-size cfg)))))

) ;; end library
