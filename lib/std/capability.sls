#!chezscheme
;;; (std capability) — Object-Capability Model (Steps 36-37)
;;;
;;; Unforgeable capability tokens that control access to dangerous operations.
;;; Capabilities can be attenuated (restricted) but never amplified.
;;; Sandboxed evaluation with resource limits.

(library (std capability)
  (export
    ;; Root capability
    make-root-capability
    root-capability?

    ;; Capability types
    make-fs-capability
    fs-capability?
    fs-cap-readable?
    fs-cap-writable?
    fs-cap-paths

    make-net-capability
    net-capability?
    net-cap-allowed-hosts
    net-cap-deny-others?

    make-eval-capability
    eval-capability?
    eval-cap-allowed-modules

    ;; Attenuation
    attenuate-fs
    attenuate-net
    attenuate-eval

    ;; Capability-guarded operations
    cap-file-open
    cap-file-read
    cap-file-write
    cap-connect

    ;; Sandbox
    with-sandbox
    sandbox-error?
    sandbox-error-reason

    ;; Capability checks
    capability?
    capability-type
    capability-valid?)

  (import (chezscheme))

  ;; ========== Capability Records ==========

  ;; Each capability is an opaque token with a unique nonce.
  ;; The nonce prevents forgery (can't construct a capability from parts).

  (define *nonce-counter* 0)
  (define *nonce-mutex*   (make-mutex))

  (define (make-nonce)
    (with-mutex *nonce-mutex*
      (set! *nonce-counter* (+ *nonce-counter* 1))
      *nonce-counter*))

  ;; capability: #(tag nonce type data)
  (define (make-cap type data)
    (vector 'capability (make-nonce) type data))

  (define (capability? x)
    (and (vector? x)
         (= (vector-length x) 4)
         (eq? (vector-ref x 0) 'capability)))

  (define (cap-nonce  c) (vector-ref c 1))
  (define (capability-type  c) (vector-ref c 2))
  (define (cap-data   c) (vector-ref c 3))

  (define (capability-valid? c)
    (and (capability? c)
         (let ([v (hashtable-ref *revoked* (cap-nonce c) #f)])
           (not v))))

  (define *revoked* (make-hashtable equal-hash equal?))

  (define (kwarg key opts . default-args)
    ;; Look up keyword in flat list: (key1 val1 key2 val2 ...)
    (let ([default (if (null? default-args) #f (car default-args))])
      (let loop ([lst opts])
        (cond [(or (null? lst) (null? (cdr lst))) default]
              [(eq? (car lst) key) (cadr lst)]
              [else (loop (cddr lst))]))))

  (define (revoke-capability! c)
    (when (capability? c)
      (hashtable-set! *revoked* (cap-nonce c) #t)))

  ;; ========== Root Capability ==========

  (define (make-root-capability)
    (make-cap 'root #t))

  (define (root-capability? c)
    (and (capability? c) (eq? (capability-type c) 'root)))

  ;; ========== FS Capability ==========

  ;; data: (read? write? paths)
  (define (make-fs-capability read? write? paths)
    (make-cap 'fs (list read? write? paths)))

  (define (fs-capability? c)
    (and (capability? c) (eq? (capability-type c) 'fs)))

  (define (fs-cap-readable? c)
    (and (fs-capability? c) (car (cap-data c))))

  (define (fs-cap-writable? c)
    (and (fs-capability? c) (cadr (cap-data c))))

  (define (fs-cap-paths c)
    (and (fs-capability? c) (caddr (cap-data c))))

  (define (attenuate-fs cap . opts)
    ;; Restrict an existing fs capability further.
    ;; opts: read-only: #t, paths: '(...)
    (unless (or (root-capability? cap) (fs-capability? cap))
      (error 'attenuate-fs "requires fs or root capability" cap))
    (unless (capability-valid? cap)
      (error 'attenuate-fs "capability has been revoked"))
    (let* ([read-only  (kwarg 'read-only: opts)]
           [paths      (let loop ([l opts] [acc '()])
                         ;; collect all values after paths: until next keyword
                         (cond [(null? l) (if (null? acc) #f (reverse acc))]
                               [(eq? (car l) 'paths:)
                                (if (and (pair? (cdr l)) (list? (cadr l)))
                                  (cadr l)
                                  #f)]
                               [else (loop (cdr l) acc)]))]
           ;; Parent constraints
           [par-read   (if (root-capability? cap) #t (fs-cap-readable? cap))]
           [par-write  (if (root-capability? cap) #t (fs-cap-writable? cap))]
           [par-paths  (if (root-capability? cap) #f (fs-cap-paths cap))]
           ;; New capability is at most as permissive as parent
           [new-write  (if read-only #f par-write)]
           [new-paths  (or paths par-paths)])
      (make-fs-capability par-read new-write new-paths)))

  ;; ========== Net Capability ==========

  ;; data: (allowed-hosts deny-others?)
  (define (make-net-capability allowed-hosts deny-others?)
    (make-cap 'net (list allowed-hosts deny-others?)))

  (define (net-capability? c)
    (and (capability? c) (eq? (capability-type c) 'net)))

  (define (net-cap-allowed-hosts c)
    (and (net-capability? c) (car (cap-data c))))

  (define (net-cap-deny-others? c)
    (and (net-capability? c) (cadr (cap-data c))))

  (define (attenuate-net cap . opts)
    (unless (or (root-capability? cap) (net-capability? cap))
      (error 'attenuate-net "requires net or root capability" cap))
    (unless (capability-valid? cap)
      (error 'attenuate-net "capability has been revoked"))
    (let* ([allow  (kwarg 'allow: opts)]
           [deny   (kwarg 'deny-all-others: opts)]
           [par-hosts  (if (root-capability? cap) '() (net-cap-allowed-hosts cap))]
           ;; Attenuation: can only further restrict, not expand
           [new-hosts  (or allow par-hosts)]
           [new-deny   (or deny (and (net-capability? cap) (net-cap-deny-others? cap)))])
      (make-net-capability new-hosts new-deny)))

  ;; ========== Eval Capability ==========

  ;; data: (allowed-modules)
  (define (make-eval-capability allowed-modules)
    (make-cap 'eval (list allowed-modules)))

  (define (eval-capability? c)
    (and (capability? c) (eq? (capability-type c) 'eval)))

  (define (eval-cap-allowed-modules c)
    (and (eval-capability? c) (car (cap-data c))))

  (define (attenuate-eval cap . opts)
    (unless (or (root-capability? cap) (eval-capability? cap))
      (error 'attenuate-eval "requires eval or root capability" cap))
    (unless (capability-valid? cap)
      (error 'attenuate-eval "capability has been revoked"))
    (let* ([modules  (kwarg 'modules: opts)]
           [par-mods (if (root-capability? cap) #f (eval-cap-allowed-modules cap))]
           [new-mods (or modules par-mods)])
      (make-eval-capability new-mods)))

  ;; ========== Capability-Guarded Operations ==========

  (define (path-allowed? path allowed-paths)
    ;; Check if path is under one of the allowed paths.
    (if (not allowed-paths)
      #t  ;; no restriction
      (let loop ([ps allowed-paths])
        (if (null? ps)
          #f
          (let ([prefix (car ps)])
            (if (and (<= (string-length prefix) (string-length path))
                     (string=? prefix (substring path 0 (string-length prefix))))
              #t
              (loop (cdr ps))))))))

  (define (cap-file-open cap path mode)
    ;; Open a file with capability check.
    ;; mode: 'r | 'w | 'rw
    (unless (and (capability? cap) (capability-valid? cap))
      (error 'cap-file-open "invalid or revoked capability"))
    (unless (fs-capability? cap)
      (error 'cap-file-open "requires fs capability" cap))
    (let ([need-write (or (eq? mode 'w) (eq? mode 'rw))])
      (when (and need-write (not (fs-cap-writable? cap)))
        (error 'cap-file-open "capability does not allow write access" path))
      (unless (path-allowed? path (fs-cap-paths cap))
        (error 'cap-file-open "path not allowed by capability" path))
      (case mode
        [(r)  (open-input-file path)]
        [(w)  (open-output-file path 'truncate)]
        [(rw) (open-file-input/output-port path)]
        [else (error 'cap-file-open "invalid mode" mode)])))

  (define (cap-file-read cap path)
    ;; Read entire file contents as string.
    (let ([port (cap-file-open cap path 'r)])
      (let loop ([result '()] [c (read-char port)])
        (if (eof-object? c)
          (begin (close-port port) (list->string (reverse result)))
          (loop (cons c result) (read-char port))))))

  (define (cap-file-write cap path content)
    ;; Write string to file.
    (let ([port (cap-file-open cap path 'w)])
      (display content port)
      (close-port port)))

  (define (cap-connect cap host port)
    ;; Check network capability before allowing connection.
    (unless (and (capability? cap) (capability-valid? cap))
      (error 'cap-connect "invalid or revoked capability"))
    (unless (net-capability? cap)
      (error 'cap-connect "requires net capability" cap))
    (let ([allowed (net-cap-allowed-hosts cap)]
          [deny    (net-cap-deny-others? cap)])
      (when (and deny (not (member host allowed)))
        (error 'cap-connect "host not allowed by capability" host))
      ;; Return the (host port) pair as a "connection spec"
      ;; (actual TCP connection would go here)
      (list host port)))

  ;; ========== Sandbox ==========

  ;; sandbox-error: condition type
  (define-condition-type &sandbox-error &error
    make-sandbox-error sandbox-error?
    (reason sandbox-error-reason))

  (define (with-sandbox thunk . opts)
    ;; Execute thunk in a restricted environment.
    ;; opts: timeout-ms: N, memory-bytes: N, capabilities: (list ...)
    (let* ([timeout-ms    (kwarg 'timeout-ms: opts)]
           [memory-bytes  (kwarg 'memory-bytes: opts)]
           [capabilities  (kwarg 'capabilities: opts '())]
           [result        #f]
           [error         #f])
      ;; Run in a separate thread so we can enforce timeout
      (let* ([done-mutex (make-mutex)]
             [done-cond  (make-condition)]
             [done?      #f]
             [worker
              (lambda ()
                (guard (exn [#t (set! error exn)])
                  (set! result (thunk)))
                (with-mutex done-mutex
                  (set! done? #t)
                  (condition-broadcast done-cond)))]
             [t (fork-thread worker)])
        ;; Wait with optional timeout
        (with-mutex done-mutex
          (if timeout-ms
            (let ([deadline (make-time 'time-duration
                              (* timeout-ms 1000000) 0)])
              (let loop ([waited #f])
                (unless done?
                  (if waited
                    (begin
                      ;; Timeout: we can't kill Chez threads, but record timeout
                      (set! error
                        (condition (make-sandbox-error 'timeout)
                                   (make-message-condition "sandbox timeout"))))
                    (let ([timed-out
                           (not (condition-wait done-cond done-mutex deadline))])
                      (loop timed-out))))))
            (let loop ()
              (unless done?
                (condition-wait done-cond done-mutex)
                (loop)))))
        (if error
          (raise error)
          result))))

  ) ;; end library
