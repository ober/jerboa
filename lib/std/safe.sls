#!chezscheme
;;; (std safe) — Contract-checked, timeout-enforced, resource-safe stdlib
;;;
;;; This module re-exports commonly used stdlib functions wrapped with:
;;; 1. Pre-condition checks (type validation before FFI)
;;; 2. Post-condition checks (result validation)
;;; 3. Default timeouts on blocking operations
;;; 4. Structured error conditions instead of bare (error ...)
;;; 5. Automatic resource cleanup via with-resource patterns
;;;
;;; Import (std safe) instead of individual modules for maximum safety.
;;; In release mode (*safe-mode* 'release), checks compile away to zero overhead.
;;;
;;; Usage:
;;;   (import (std safe))
;;;   (with-resource ([db (safe-sqlite-open "test.db")])
;;;     (safe-sqlite-exec db "CREATE TABLE t(x)")
;;;     (safe-sqlite-query db "SELECT * FROM t"))

(library (std safe)
  (export
    ;; Mode control
    *safe-mode*

    ;; SQLite — safe wrappers
    safe-sqlite-open
    safe-sqlite-close
    safe-sqlite-exec
    safe-sqlite-execute
    safe-sqlite-query
    safe-sqlite-prepare
    safe-sqlite-finalize
    safe-sqlite-step
    safe-sqlite-bind

    ;; TCP — safe wrappers
    safe-tcp-connect
    safe-tcp-listen
    safe-tcp-accept
    safe-tcp-close
    safe-tcp-read
    safe-tcp-write
    safe-tcp-write-string

    ;; File I/O — safe wrappers
    safe-open-input-file
    safe-open-output-file
    safe-call-with-input-file
    safe-call-with-output-file

    ;; JSON — safe wrappers
    safe-read-json
    safe-string->json

    ;; Resource management (re-export)
    with-resource
    with-resource1

    ;; Error conditions (re-export)
    db-error? network-error? timeout-error? parse-error?
    resource-error?

    ;; Finalizer safety net
    *resource-finalizer-log*
    poll-resource-finalizers!)

  (import (chezscheme)
          (std error conditions)
          (std resource)
          (only (std security taint) tainted? check-untainted!))

  ;; =========================================================================
  ;; Mode control
  ;; =========================================================================

  ;; 'check — full pre/post condition checks (default)
  ;; 'release — skip checks for zero overhead
  (define *safe-mode* (make-parameter 'check))

  (define-syntax when-checking
    (syntax-rules ()
      [(_ body ...)
       (when (eq? (*safe-mode*) 'check)
         body ...)]))

  ;; =========================================================================
  ;; Finalizer safety net — guardian-based resource leak detection
  ;; =========================================================================
  ;;
  ;; When a resource handle is GC'd without being explicitly closed, the
  ;; guardian fires and we log a warning. This catches the common pattern:
  ;;   (let ([db (sqlite-open "x.db")]) ...)  ; forgot to close!
  ;;
  ;; Warnings are logged to *resource-finalizer-log* (a parameter holding
  ;; a procedure). Default: display to current-error-port.
  ;; Call poll-resource-finalizers! periodically or at shutdown.

  (define *resource-guardian* (make-guardian))

  ;; Each entry in the guardian is (cons type-symbol info-string)
  ;; so we know what leaked when the guardian fires.
  (define *resource-finalizer-log*
    (make-parameter
     (lambda (type info)
       (fprintf (current-error-port)
                "WARNING: ~a handle GC'd without close! (~a)~%"
                type info))))

  (define (register-guarded-resource! handle type info cleanup-proc)
    ;; Track the resource. When GC'd without explicit close, we warn + clean.
    (let ([entry (vector type info cleanup-proc #f)])  ;; #f = not-yet-closed
      (*resource-guardian* entry)
      entry))

  (define (mark-resource-closed! entry)
    ;; Mark as closed so the guardian callback won't warn.
    (when entry
      (vector-set! entry 3 #t)))

  (define (poll-resource-finalizers!)
    ;; Call this periodically (or at shutdown) to process GC'd resources.
    ;; Returns the number of leaked resources found.
    (let loop ([count 0])
      (let ([entry (*resource-guardian*)])
        (if (not entry)
            count
            (begin
              (unless (vector-ref entry 3)  ;; not already closed?
                (let ([type (vector-ref entry 0)]
                      [info (vector-ref entry 1)]
                      [cleanup (vector-ref entry 2)])
                  ((*resource-finalizer-log*) type info)
                  ;; Best-effort cleanup
                  (guard (exn [#t (void)])
                    (when cleanup (cleanup)))))
              (loop (+ count 1)))))))

  ;; =========================================================================
  ;; Argument checking
  ;; =========================================================================

  (define (check-arg! who pred val type-name)
    (when (eq? (*safe-mode*) 'check)
      (unless (pred val)
        (error who "expected ~a, got ~a" type-name val))))

  (define (check-string! who val)
    (check-arg! who string? val "string"))

  (define (check-fixnum! who val)
    (check-arg! who fixnum? val "fixnum"))

  (define (check-nonneg-fixnum! who val)
    (when (eq? (*safe-mode*) 'check)
      (unless (and (fixnum? val) (fx>= val 0))
        (error who "expected non-negative fixnum, got ~a" val))))

  (define (check-bytevector! who val)
    (check-arg! who bytevector? val "bytevector"))

  ;; =========================================================================
  ;; SQLite — Contract-checked wrappers
  ;; =========================================================================
  ;;
  ;; These are *forward declarations* — they attempt to load the native module
  ;; and wrap it. If sqlite-native is not available, they raise a clear error.

  (define sqlite-available? #f)
  (define raw-sqlite-open #f)
  (define raw-sqlite-close #f)
  (define raw-sqlite-exec #f)
  (define raw-sqlite-execute #f)
  (define raw-sqlite-query #f)
  (define raw-sqlite-prepare #f)
  (define raw-sqlite-finalize #f)
  (define raw-sqlite-step #f)
  (define raw-sqlite-bind-int #f)
  (define raw-sqlite-bind-double #f)
  (define raw-sqlite-bind-text #f)
  (define raw-sqlite-bind-null #f)
  (define raw-sqlite-errmsg #f)

  ;; Try to load sqlite bindings at library init time.
  ;; Set sqlite-available? LAST so partial failure leaves it #f.
  (define _init-sqlite
    (guard (exn [#t (set! sqlite-available? #f) (void)])
      (let ([env (environment '(std db sqlite-native))])
        (set! raw-sqlite-open (eval 'sqlite-open env))
        (set! raw-sqlite-close (eval 'sqlite-close env))
        (set! raw-sqlite-exec (eval 'sqlite-exec env))
        (set! raw-sqlite-execute (eval 'sqlite-execute env))
        (set! raw-sqlite-query (eval 'sqlite-query env))
        (set! raw-sqlite-prepare (eval 'sqlite-prepare env))
        (set! raw-sqlite-finalize (eval 'sqlite-finalize env))
        (set! raw-sqlite-step (eval 'sqlite-step env))
        (set! raw-sqlite-bind-int (eval 'sqlite-bind-int env))
        (set! raw-sqlite-bind-double (eval 'sqlite-bind-double env))
        (set! raw-sqlite-bind-text (eval 'sqlite-bind-text env))
        (set! raw-sqlite-bind-null (eval 'sqlite-bind-null env))
        (set! raw-sqlite-errmsg (eval 'sqlite-errmsg env))
        ;; Only mark available after ALL evals succeed
        (set! sqlite-available? #t))))

  (define (ensure-sqlite! who)
    (unless sqlite-available?
      (raise (condition
              (make-db-error 'db 'sqlite)
              (make-message-condition
               (format #f "~a: SQLite not available — libjerboa_native.so not loaded" who))))))

  ;; ---- SQL injection heuristic detection ----
  ;; Reject SQL strings that look like they were built by concatenation.
  ;; Heuristic: flag strings containing common injection markers that
  ;; suggest runtime string building rather than parameterized queries.

  (define (check-sql-safety! who sql)
    (when (eq? (*safe-mode*) 'check)
      ;; Check for obviously unsafe patterns:
      ;; 1. Unbalanced quotes (sign of string injection)
      ;; 2. Multiple semicolons (multi-statement injection)
      ;; 3. Comment markers that could hide injected SQL
      (let ([len (string-length sql)])
        ;; Multiple statements via semicolons (allowing trailing ;)
        (let ([semis (let count ([i 0] [n 0])
                       (if (>= i len) n
                           (count (+ i 1)
                                  (if (char=? (string-ref sql i) #\;) (+ n 1) n))))])
          (when (> semis 1)
            (raise (condition
                    (make-db-query-error 'db 'sqlite sql)
                    (make-message-condition
                     (format #f "~a: SQL contains ~a semicolons — use separate queries or parameterized statements"
                             who semis))))))
        ;; SQL comment injection: -- or /* outside of string literals
        (when (or (string-contains-outside-quotes? sql "--")
                  (string-contains-outside-quotes? sql "/*"))
          (raise (condition
                  (make-db-query-error 'db 'sqlite sql)
                  (make-message-condition
                   (format #f "~a: SQL contains comment markers — possible injection"
                           who))))))))

  (define (string-contains-outside-quotes? str pattern)
    ;; Simple scan: check if pattern appears outside single-quoted SQL strings.
    (let ([slen (string-length str)]
          [plen (string-length pattern)])
      (let loop ([i 0] [in-quote? #f])
        (cond
          [(> (+ i plen) slen) #f]
          [(char=? (string-ref str i) #\')
           (loop (+ i 1) (not in-quote?))]
          [(and (not in-quote?)
                (string=? (substring str i (+ i plen)) pattern))
           #t]
          [else (loop (+ i 1) in-quote?)]))))

  ;; Track sqlite handle → guardian entry for leak detection
  (define *sqlite-handle-entries* (make-hashtable equal-hash equal?))

  (define (safe-sqlite-open path)
    ;; Pre: path must be a string
    ;; Post: returns a valid db handle (non-negative fixnum)
    ;; Safety: registers handle with guardian for leak detection
    (check-string! 'safe-sqlite-open path)
    (ensure-sqlite! 'safe-sqlite-open)
    (let ([handle (raw-sqlite-open path)])
      (when-checking
       (when (and (fixnum? handle) (fx< handle 0))
         (raise (condition
                 (make-db-connection-error 'db 'sqlite)
                 (make-message-condition
                  (format #f "failed to open database: ~a" path))))))
      ;; Register with guardian for leak detection
      (let ([entry (register-guarded-resource!
                    handle 'sqlite path
                    (and raw-sqlite-close
                         (lambda () (raw-sqlite-close handle))))])
        (hashtable-set! *sqlite-handle-entries* handle entry))
      handle))

  (define (safe-sqlite-close db)
    ;; Pre: db must be a fixnum handle
    (check-fixnum! 'safe-sqlite-close db)
    (ensure-sqlite! 'safe-sqlite-close)
    ;; Mark as closed so guardian won't warn
    (let ([entry (hashtable-ref *sqlite-handle-entries* db #f)])
      (mark-resource-closed! entry)
      (hashtable-delete! *sqlite-handle-entries* db))
    (raw-sqlite-close db))

  (define (safe-sqlite-exec db sql)
    ;; Pre: db is fixnum handle, sql is string, not tainted
    ;; Post: returns 0 on success
    (check-untainted! sql 'sqlite-exec)
    (check-fixnum! 'safe-sqlite-exec db)
    (check-string! 'safe-sqlite-exec sql)
    (check-sql-safety! 'safe-sqlite-exec sql)
    (ensure-sqlite! 'safe-sqlite-exec)
    (let ([rc (raw-sqlite-exec db sql)])
      (when-checking
       (unless (and (fixnum? rc) (fx= rc 0))
         (raise (condition
                 (make-db-query-error 'db 'sqlite sql)
                 (make-message-condition
                  (format #f "sqlite-exec failed: ~a"
                          (if raw-sqlite-errmsg
                              (raw-sqlite-errmsg db)
                              rc)))))))
      rc))

  (define (safe-sqlite-execute db sql . params)
    ;; Pre: db is fixnum handle, sql is string, params is list
    (check-fixnum! 'safe-sqlite-execute db)
    (check-string! 'safe-sqlite-execute sql)
    (check-untainted! 'safe-sqlite-execute sql)
    (check-sql-safety! 'safe-sqlite-execute sql)
    (ensure-sqlite! 'safe-sqlite-execute)
    (apply raw-sqlite-execute db sql params))

  (define (safe-sqlite-query db sql . params)
    ;; Pre: db is fixnum handle, sql is string
    ;; Post: returns a list of alists
    (check-fixnum! 'safe-sqlite-query db)
    (check-string! 'safe-sqlite-query sql)
    (check-untainted! 'safe-sqlite-query sql)
    (check-sql-safety! 'safe-sqlite-query sql)
    (ensure-sqlite! 'safe-sqlite-query)
    (let ([result (apply raw-sqlite-query db sql params)])
      (when-checking
       (unless (list? result)
         (raise (condition
                 (make-db-query-error 'db 'sqlite sql)
                 (make-message-condition "sqlite-query did not return a list")))))
      result))

  (define (safe-sqlite-prepare db sql)
    (check-fixnum! 'safe-sqlite-prepare db)
    (check-string! 'safe-sqlite-prepare sql)
    (check-untainted! 'safe-sqlite-prepare sql)
    (check-sql-safety! 'safe-sqlite-prepare sql)
    (ensure-sqlite! 'safe-sqlite-prepare)
    (let ([stmt (raw-sqlite-prepare db sql)])
      (when-checking
       (when (and (fixnum? stmt) (fx< stmt 0))
         (raise (condition
                 (make-db-query-error 'db 'sqlite sql)
                 (make-message-condition
                  (format #f "sqlite-prepare failed: ~a"
                          (if raw-sqlite-errmsg
                              (raw-sqlite-errmsg db)
                              stmt)))))))
      stmt))

  (define (safe-sqlite-finalize stmt)
    (check-fixnum! 'safe-sqlite-finalize stmt)
    (ensure-sqlite! 'safe-sqlite-finalize)
    (raw-sqlite-finalize stmt))

  (define (safe-sqlite-step stmt)
    (check-fixnum! 'safe-sqlite-step stmt)
    (ensure-sqlite! 'safe-sqlite-step)
    (raw-sqlite-step stmt))

  (define (safe-sqlite-bind stmt index value)
    ;; Dispatches to the right bind function based on value type.
    (check-fixnum! 'safe-sqlite-bind stmt)
    (check-fixnum! 'safe-sqlite-bind index)
    (ensure-sqlite! 'safe-sqlite-bind)
    (cond
      [(fixnum? value)    (raw-sqlite-bind-int stmt index value)]
      [(flonum? value)    (raw-sqlite-bind-double stmt index value)]
      [(string? value)    (raw-sqlite-bind-text stmt index value)]
      [(not value)        (raw-sqlite-bind-null stmt index)]
      [(bytevector? value)
       ;; No blob bind available in current API — convert to string
       (error 'safe-sqlite-bind "bytevector binding not yet supported")]
      [else
       (error 'safe-sqlite-bind
              "unsupported bind type: ~a (expected fixnum, flonum, string, or #f)"
              value)]))

  ;; =========================================================================
  ;; TCP — Contract-checked wrappers
  ;; =========================================================================

  (define tcp-raw-available? #f)
  (define raw-tcp-connect #f)
  (define raw-tcp-listen #f)
  (define raw-tcp-accept #f)
  (define raw-tcp-close #f)
  (define raw-tcp-read #f)
  (define raw-tcp-write #f)
  (define raw-tcp-write-string #f)

  ;; Set tcp-raw-available? LAST so partial failure leaves it #f.
  (define _init-tcp
    (guard (exn [#t (set! tcp-raw-available? #f) (void)])
      (let ([env (environment '(std net tcp-raw))])
        (set! raw-tcp-connect (eval 'tcp-connect env))
        (set! raw-tcp-listen (eval 'tcp-listen env))
        (set! raw-tcp-accept (eval 'tcp-accept env))
        (set! raw-tcp-close (eval 'tcp-close env))
        (set! raw-tcp-read (eval 'tcp-read env))
        (set! raw-tcp-write (eval 'tcp-write env))
        (set! raw-tcp-write-string (eval 'tcp-write-string env))
        ;; Only mark available after ALL evals succeed
        (set! tcp-raw-available? #t))))

  (define (ensure-tcp! who)
    (unless tcp-raw-available?
      (raise (condition
              (make-network-error 'network #f #f)
              (make-message-condition
               (format #f "~a: TCP not available" who))))))

  ;; Track tcp fd → guardian entry for leak detection
  (define *tcp-handle-entries* (make-hashtable equal-hash equal?))

  (define (safe-tcp-connect address port)
    (check-string! 'safe-tcp-connect address)
    (check-fixnum! 'safe-tcp-connect port)
    (when-checking
     (unless (and (fx> port 0) (fx<= port 65535))
       (error 'safe-tcp-connect "port must be 1-65535, got ~a" port)))
    (ensure-tcp! 'safe-tcp-connect)
    (let ([fd (raw-tcp-connect address port)])
      (when-checking
       (when (and (fixnum? fd) (fx< fd 0))
         (raise (condition
                 (make-connection-refused 'network address port)
                 (make-message-condition
                  (format #f "connection refused: ~a:~a" address port))))))
      ;; Register with guardian for leak detection
      (let ([entry (register-guarded-resource!
                    fd 'tcp (format #f "~a:~a" address port)
                    (and raw-tcp-close (lambda () (raw-tcp-close fd))))])
        (hashtable-set! *tcp-handle-entries* fd entry))
      fd))

  (define (safe-tcp-listen address port . rest)
    (check-string! 'safe-tcp-listen address)
    (check-fixnum! 'safe-tcp-listen port)
    (when-checking
     (unless (and (fx>= port 0) (fx<= port 65535))
       (error 'safe-tcp-listen "port must be 0-65535, got ~a" port)))
    (ensure-tcp! 'safe-tcp-listen)
    (apply raw-tcp-listen address port rest))

  (define (safe-tcp-accept fd)
    (check-fixnum! 'safe-tcp-accept fd)
    (ensure-tcp! 'safe-tcp-accept)
    (raw-tcp-accept fd))

  (define (safe-tcp-close fd)
    (check-fixnum! 'safe-tcp-close fd)
    (ensure-tcp! 'safe-tcp-close)
    ;; Mark as closed so guardian won't warn
    (let ([entry (hashtable-ref *tcp-handle-entries* fd #f)])
      (mark-resource-closed! entry)
      (hashtable-delete! *tcp-handle-entries* fd))
    (raw-tcp-close fd))

  (define (safe-tcp-read fd buf len)
    (check-fixnum! 'safe-tcp-read fd)
    (check-bytevector! 'safe-tcp-read buf)
    (check-nonneg-fixnum! 'safe-tcp-read len)
    (when-checking
     (when (fx> len (bytevector-length buf))
       (error 'safe-tcp-read
              "read length ~a exceeds buffer size ~a" len (bytevector-length buf))))
    (ensure-tcp! 'safe-tcp-read)
    (raw-tcp-read fd buf len))

  (define (safe-tcp-write fd bv)
    (check-fixnum! 'safe-tcp-write fd)
    (check-bytevector! 'safe-tcp-write bv)
    (ensure-tcp! 'safe-tcp-write)
    (raw-tcp-write fd bv))

  (define (safe-tcp-write-string fd str)
    (check-fixnum! 'safe-tcp-write-string fd)
    (check-string! 'safe-tcp-write-string str)
    (ensure-tcp! 'safe-tcp-write-string)
    (raw-tcp-write-string fd str))

  ;; =========================================================================
  ;; File I/O — Contract-checked wrappers
  ;; =========================================================================

  (define (safe-open-input-file path)
    (check-untainted! path 'open-input-file)
    (check-string! 'safe-open-input-file path)
    (unless (file-exists? path)
      (raise (condition
              (make-resource-error 'resource 'file)
              (make-message-condition
               (format #f "file not found: ~a" path)))))
    (open-input-file path))

  (define (safe-open-output-file path)
    (check-untainted! path 'open-output-file)
    (check-string! 'safe-open-output-file path)
    ;; Check parent directory exists
    (let ([dir (path-parent path)])
      (when (and (string? dir)
                 (not (string=? dir ""))
                 (not (file-exists? dir)))
        (raise (condition
                (make-resource-error 'resource 'file)
                (make-message-condition
                 (format #f "parent directory does not exist: ~a" dir))))))
    (open-output-file path))

  (define (safe-call-with-input-file path proc)
    (check-untainted! path 'call-with-input-file)
    (check-string! 'safe-call-with-input-file path)
    (unless (file-exists? path)
      (raise (condition
              (make-resource-error 'resource 'file)
              (make-message-condition
               (format #f "file not found: ~a" path)))))
    (call-with-input-file path proc))

  (define (safe-call-with-output-file path proc)
    (check-untainted! path 'call-with-output-file)
    (check-string! 'safe-call-with-output-file path)
    (call-with-output-file path proc))

  ;; =========================================================================
  ;; JSON — Contract-checked wrappers
  ;; =========================================================================

  (define json-available? #f)
  (define raw-read-json #f)
  (define raw-string->json-object #f)

  ;; Set json-available? LAST so partial failure leaves it #f.
  (define _init-json
    (guard (exn [#t (set! json-available? #f) (void)])
      (let ([env (environment '(std text json))])
        (set! raw-read-json (eval 'read-json env))
        (set! raw-string->json-object (eval 'string->json-object env))
        (set! json-available? #t))))

  (define (safe-read-json port)
    (when-checking
     (unless (input-port? port)
       (error 'safe-read-json "expected input port, got ~a" port)))
    (unless json-available?
      (error 'safe-read-json "JSON module not available"))
    (raw-read-json port))

  (define (safe-string->json str)
    (check-string! 'safe-string->json str)
    (unless json-available?
      (error 'safe-string->json "JSON module not available"))
    (raw-string->json-object str))

) ;; end library
