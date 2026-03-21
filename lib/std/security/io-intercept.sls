#!chezscheme
;;; (std security io-intercept) — Effect-based I/O interception
;;;
;;; Uses the effect system to create auditable I/O layers where every
;;; filesystem, network, and process operation can be intercepted,
;;; logged, and policy-checked.
;;;
;;; All I/O is mediated by effect handlers. Testing can install mock
;;; handlers. Production installs audit + policy handlers.

(library (std security io-intercept)
  (export
    ;; I/O effect types (macros from defeffect)
    FileIO
    NetIO
    ProcessIO

    ;; Intercepted I/O operations
    io/read-file
    io/write-file
    io/delete-file
    io/net-connect
    io/net-listen
    io/process-exec

    ;; Pre-built handler sets
    make-audit-io-handler
    make-deny-all-io-handler
    make-allow-io-handler
    with-io-policy)

  (import (chezscheme)
          (std effect))

  ;; ========== Define I/O Effects ==========

  (defeffect FileIO
    (file-read path)
    (file-write path data)
    (file-delete path))

  (defeffect NetIO
    (net-connect host port)
    (net-listen address port))

  (defeffect ProcessIO
    (process-exec command args))

  ;; ========== Intercepted I/O Operations ==========
  ;; These perform effects instead of doing I/O directly.

  (define (io/read-file path)
    (perform (FileIO file-read path)))

  (define (io/write-file path data)
    (perform (FileIO file-write path data)))

  (define (io/delete-file path)
    (perform (FileIO file-delete path)))

  (define (io/net-connect host port)
    (perform (NetIO net-connect host port)))

  (define (io/net-listen address port)
    (perform (NetIO net-listen address port)))

  (define (io/process-exec command args)
    (perform (ProcessIO process-exec command args)))

  ;; ========== Pre-built Handler Sets ==========

  (define (make-audit-io-handler audit-fn real-io-fn)
    ;; Create a handler that logs then delegates to real I/O.
    ;; audit-fn: (lambda (operation args) ...) — called before I/O
    ;; real-io-fn: (lambda (operation args) -> result) — does the actual I/O
    (lambda (k . args)
      (let ([op-name (car args)]
            [op-args (cdr args)])
        (audit-fn op-name op-args)
        (resume k (real-io-fn op-name op-args)))))

  (define (make-deny-all-io-handler)
    ;; Handler that denies all I/O operations.
    (lambda (operations)
      (with-handler
        ([FileIO
          (file-read (k path)
            (error 'io-policy "file read denied" path))
          (file-write (k path data)
            (error 'io-policy "file write denied" path))
          (file-delete (k path)
            (error 'io-policy "file delete denied" path))]
         [NetIO
          (net-connect (k host port)
            (error 'io-policy "network connect denied" host port))
          (net-listen (k address port)
            (error 'io-policy "network listen denied" address port))]
         [ProcessIO
          (process-exec (k command args)
            (error 'io-policy "process exec denied" command))])
        (operations))))

  (define (make-allow-io-handler)
    ;; Handler that allows all I/O using standard Chez procedures.
    (lambda (operations)
      (with-handler
        ([FileIO
          (file-read (k path)
            (resume k (call-with-input-file path get-string-all)))
          (file-write (k path data)
            (call-with-output-file path
              (lambda (p) (put-string p data))
              'replace)
            (resume k (void)))
          (file-delete (k path)
            (delete-file path)
            (resume k (void)))]
         [NetIO
          (net-connect (k host port)
            (resume k (list 'connection host port)))
          (net-listen (k address port)
            (resume k (list 'listener address port)))]
         [ProcessIO
          (process-exec (k command args)
            (resume k (list 'process command args)))])
        (operations))))

  (define-syntax with-io-policy
    ;; (with-io-policy handler body ...)
    ;; handler: one of make-deny-all-io-handler, make-allow-io-handler, or custom
    (syntax-rules ()
      [(_ handler body ...)
       (handler (lambda () body ...))]))

  ) ;; end library
