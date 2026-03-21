#!chezscheme
;;; test-phase4-safety.ss -- Tests for Phase 4: Language-Level Safety

(import (chezscheme)
        (std security taint)
        (std security flow)
        (std security capability)
        (std security capability-typed)
        (std security secret)
        (std security io-intercept)
        (std actor core)
        (std actor bounded))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr] [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (display "FAIL: ") (write 'expr)
           (display " => ") (write result)
           (display " expected ") (write exp) (newline))))]))

(define-syntax check-error
  (syntax-rules ()
    [(_ expr)
     (guard (exn [#t (set! pass-count (+ pass-count 1))])
       expr
       (set! fail-count (+ fail-count 1))
       (display "FAIL: expected error from ") (write 'expr) (newline))]))

;; ========== L1: Taint Tracking ==========
(display "  Testing taint tracking (L1)...\n")

;; Basic taint
(let ([t (taint 'http-input "user data")])
  (check (tainted? t) => #t)
  (check (taint-class t) => 'http-input)
  (check (taint-value t) => "user data"))

;; Convenience constructors
(check (taint-class (taint-http "x")) => 'http-input)
(check (taint-class (taint-env "x")) => 'env-input)
(check (taint-class (taint-file "x")) => 'file-input)
(check (taint-class (taint-net "x")) => 'net-input)
(check (taint-class (taint-deser "x")) => 'deser-input)

;; Untaint
(check (untaint (taint-http "clean")) => "clean")
(check (untaint "already clean") => "already clean")

;; Taint checking — untainted passes
(check (guard (exn [#t #f])
         (check-untainted! "clean" 'sql) #t) => #t)

;; Taint checking — tainted raises
(check (guard (exn [(taint-violation? exn)
                    (taint-violation-sink exn)])
         (check-untainted! (taint-http "evil") 'sql)
         #f) => 'sql)

;; assert-untainted macro
(check (guard (exn [(taint-violation? exn) 'caught])
         (assert-untainted (taint-net "x") sql)
         #f) => 'caught)

;; Taint propagation through string ops
(let ([t1 (taint-http "hello ")]
      [clean "world"])
  ;; tainted + clean = tainted
  (let ([result (tainted-string-append t1 clean)])
    (check (tainted? result) => #t)
    (check (taint-value result) => "hello world")))

;; All clean stays clean
(check (tainted? (tainted-string-append "a" "b")) => #f)

;; tainted-substring propagates
(let ([t (taint-http "hello world")])
  (let ([sub (tainted-substring t 0 5)])
    (check (tainted? sub) => #t)
    (check (taint-value sub) => "hello")))

;; tainted-string-length works
(check (tainted-string-length (taint-http "abc")) => 3)
(check (tainted-string-length "abc") => 3)

;; Opaque record — can't forge
(check (tainted? (vector 'tainted 'http-input "x")) => #f)

;; ========== L2: Information Flow Control ==========
(display "  Testing information flow (L2)...\n")

;; Security levels
(check (security-level? level-public) => #t)
(check (security-level-name level-secret) => 'secret)

;; Level ordering
(check (security-level<=? level-public level-secret) => #t)   ;; up OK
(check (security-level<=? level-secret level-public) => #f)   ;; down blocked
(check (security-level<=? level-secret level-secret) => #t)   ;; same OK
(check (security-level<=? level-internal level-top-secret) => #t)

;; Classify values
(let ([val (classify level-secret "my-api-key")])
  (check (classified? val) => #t)
  (check (classified-level val) => level-secret)
  (check (classified-value val) => "my-api-key"))

;; Flow check — up OK
(check (guard (exn [#t #f])
         (check-flow! (classify level-public "x") level-secret 'db) #t) => #t)

;; Flow check — down blocked
(check (guard (exn [(flow-violation? exn)
                    (security-level-name (flow-violation-from exn))])
         (check-flow! (classify level-secret "key") level-public 'log)
         #f) => 'secret)

;; Unclassified values pass flow checks
(check (guard (exn [#t #f])
         (check-flow! "not classified" level-public 'log) #t) => #t)

;; Declassification
(let ([secret-val (classify level-secret "sensitive")])
  ;; Capture declassification log
  (let ([logged #f])
    (parameterize ([current-declassify-handler
                     (lambda (val from to reason)
                       (set! logged (list (security-level-name from)
                                          (security-level-name to)
                                          reason)))])
      (let ([result (declassify secret-val level-public "authorized by admin")])
        ;; Result is unwrapped (public = rank 0)
        (check (classified? result) => #f)
        (check result => "sensitive")
        ;; Audit was called
        (check (car logged) => 'secret)
        (check (cadr logged) => 'public)
        (check (caddr logged) => "authorized by admin")))))

;; Opaque — can't forge
(check (classified? (vector 'classified level-secret "x")) => #f)

;; ========== L3: Capability-Typed Functions ==========
(display "  Testing capability-typed functions (L3)...\n")

;; define/cap — no capability context raises error
(define/cap (test-read-file path)
  (requires: filesystem)
  (string-append "reading: " path))

(check (guard (exn [#t 'denied])
         (test-read-file "/etc/passwd")
         'allowed) => 'denied)

;; With the right capability context, it works
(check (with-capabilities
         (list (make-fs-capability 'read: #t))
         (lambda () (test-read-file "/etc/passwd")))
       => "reading: /etc/passwd")

;; capability-requirements registry
(check (capability-requirements 'test-read-file) => '(filesystem))

;; ========== L5: Lifetime-Scoped Secrets ==========
(display "  Testing lifetime-scoped secrets (L5)...\n")

;; Basic secret
(let ([s (make-secret #vu8(1 2 3 4))])
  (check (secret? s) => #t)
  (check (secret-consumed? s) => #f)
  ;; Peek without consuming
  (check (bytevector-length (secret-peek s)) => 4)
  (check (secret-consumed? s) => #f))

;; Consume secret — wipes original
(let* ([original #vu8(65 66 67 68)]
       [copy (let ([bv (make-bytevector 4)])
               (bytevector-copy! original 0 bv 0 4) bv)]
       [s (make-secret copy)])
  (let ([val (secret-use s)])
    ;; Got the value
    (check (equal? val original) => #t)
    ;; Original is wiped
    (check (equal? copy #vu8(0 0 0 0)) => #t)
    ;; Secret is consumed
    (check (secret-consumed? s) => #t)))

;; Double use raises error
(let ([s (make-secret #vu8(1 2 3))])
  (secret-use s)
  (check-error (secret-use s)))

;; with-secret auto-wipes on scope exit
(let ([key-bv (make-bytevector 32 42)])
  (let ([result (with-secret ([key key-bv])
                  ;; Use the secret inside scope
                  (bytevector-length (secret-peek key)))])
    ;; Result returned
    (check result => 32)
    ;; Key is wiped
    (check (bytevector-u8-ref key-bv 0) => 0)
    (check (bytevector-u8-ref key-bv 31) => 0)))

;; with-secret wipes even on exception
(let ([key-bv (make-bytevector 16 99)])
  (guard (exn [#t (void)])
    (with-secret ([key key-bv])
      (error 'test "boom")))
  (check (bytevector-u8-ref key-bv 0) => 0))

;; wipe-bytevector! utility
(let ([bv (bytevector-copy #vu8(1 2 3 4 5))])
  (wipe-bytevector! bv)
  (check (equal? bv #vu8(0 0 0 0 0)) => #t))

;; Not a bytevector — error
(check-error (make-secret "not bytes"))

;; ========== L7: Effect-Based I/O Interception ==========
(display "  Testing effect-based I/O (L7)...\n")

;; Deny-all handler blocks all I/O
(let ([handler (make-deny-all-io-handler)])
  (check (guard (exn [#t 'denied])
           (with-io-policy handler
             (io/read-file "/etc/passwd"))
           'allowed) => 'denied)
  (check (guard (exn [#t 'denied])
           (with-io-policy handler
             (io/net-connect "evil.com" 80))
           'allowed) => 'denied)
  (check (guard (exn [#t 'denied])
           (with-io-policy handler
             (io/process-exec "rm" '("-rf" "/")))
           'allowed) => 'denied))

;; Allow handler permits all I/O (returns result from real I/O)
;; /dev/null returns EOF, which proves the real I/O was performed
(let ([handler (make-allow-io-handler)])
  (let ([result (with-io-policy handler
                  (io/read-file "/dev/null"))])
    (check (eof-object? result) => #t)))

;; ========== V10: Bounded Actor Mailboxes ==========
(display "  Testing bounded mailboxes (V10)...\n")

;; Config creation
(let ([cfg (make-mailbox-config 100)])
  (check (mailbox-config? cfg) => #t)
  (check (mailbox-config-capacity cfg) => 100)
  (check (mailbox-config-strategy cfg) => 'block))  ;; default

(let ([cfg (make-mailbox-config 50 'strategy: 'drop)])
  (check (mailbox-config-capacity cfg) => 50)
  (check (mailbox-config-strategy cfg) => 'drop))

;; Invalid config
(check-error (make-mailbox-config -1))
(check-error (make-mailbox-config 100 'strategy: 'invalid))

;; Default config
(check (mailbox-config-capacity default-mailbox-config) => 10000)

;; Spawn bounded actor with 'error strategy
(let* ([received '()]
       [cfg (make-mailbox-config 3 'strategy: 'error)]
       [actor (spawn-bounded-actor
                (lambda (msg)
                  (set! received (cons msg received))
                  ;; Slow consumer
                  (sleep (make-time 'time-duration 50000000 0)))
                cfg
                'test-bounded)])
  ;; Send 3 messages (within capacity)
  (bounded-send actor 'msg1)
  (bounded-send actor 'msg2)
  (bounded-send actor 'msg3)
  ;; 4th should raise &mailbox-full
  (check (guard (exn [(mailbox-full-condition? exn) 'full])
           (bounded-send actor 'msg4)
           'ok) => 'full)
  ;; Check status
  (check (mailbox-full? actor) => #t)
  ;; Wait for some processing
  (sleep (make-time 'time-duration 200000000 0))
  ;; After processing, should accept again
  (check (mailbox-full? actor) => #f)
  (actor-kill! actor))

;; Spawn bounded actor with 'drop strategy
(let* ([cfg (make-mailbox-config 2 'strategy: 'drop)]
       [actor (spawn-bounded-actor
                (lambda (msg)
                  (sleep (make-time 'time-duration 100000000 0)))
                cfg)])
  ;; Fill up
  (bounded-send actor 'msg1)
  (bounded-send actor 'msg2)
  ;; This is silently dropped (no error)
  (check (guard (exn [#t 'error])
           (bounded-send actor 'msg3)
           'ok) => 'ok)
  (actor-kill! actor))

;; Regular send to bounded actor (bypasses bounds - for backward compat)
(let* ([cfg (make-mailbox-config 1 'strategy: 'error)]
       [actor (spawn-bounded-actor
                (lambda (msg)
                  (sleep (make-time 'time-duration 100000000 0)))
                cfg)])
  (send actor 'msg1)  ;; regular send always works
  (send actor 'msg2)
  (actor-kill! actor))

;; ========== Summary ==========
(display "  phase4-safety: ")
(display pass-count) (display " passed")
(when (> fail-count 0)
  (display ", ") (display fail-count) (display " failed"))
(newline)
(when (> fail-count 0) (exit 1))
