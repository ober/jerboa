#!chezscheme
;;; test-gaps.ss — Tests for safety gap implementations
;;;
;;; Tests: error/conditions, resource, error/context, safe-fasl,
;;;        safe-timeout, safe (contract wrappers), immutable

(import (chezscheme))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr]
           [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (display "FAIL: ")
           (write 'expr)
           (display " => ")
           (write result)
           (display " expected ")
           (write exp)
           (newline))))]))

(define-syntax check-true
  (syntax-rules ()
    [(_ expr)
     (check expr => #t)]))

(define-syntax check-false
  (syntax-rules ()
    [(_ expr)
     (check expr => #f)]))

(define-syntax check-error
  (syntax-rules ()
    [(_ expr)
     (let ([raised #f])
       (guard (exn [#t (set! raised #t)])
         expr)
       (if raised
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (display "FAIL (expected error): ")
           (write 'expr)
           (newline))))]))

;; =========================================================================
;; 1. Error Conditions
;; =========================================================================

(display "--- Error Conditions ---\n")

(import (std error conditions))

;; Root condition
(let ([c (make-jerboa-condition 'network)])
  (check-true (jerboa-condition? c))
  (check (jerboa-condition-subsystem c) => 'network))

;; Network conditions
(let ([c (make-network-error 'network "localhost" 8080)])
  (check-true (network-error? c))
  (check (network-error-address c) => "localhost")
  (check (network-error-port-number c) => 8080))

(let ([c (make-connection-refused 'network "10.0.0.1" 443)])
  (check-true (connection-refused? c))
  (check-true (network-error? c))
  (check-true (jerboa-condition? c)))

(let ([c (make-connection-timeout 'network "10.0.0.1" 443 30)])
  (check-true (connection-timeout? c))
  (check (connection-timeout-seconds c) => 30))

(let ([c (make-dns-failure 'network #f #f "nonexistent.example")])
  (check-true (dns-failure? c))
  (check (dns-failure-hostname c) => "nonexistent.example"))

(let ([c (make-tls-error 'network "host" 443 "certificate expired")])
  (check-true (tls-error? c))
  (check (tls-error-reason c) => "certificate expired"))

;; Database conditions
(let ([c (make-db-error 'db 'sqlite)])
  (check-true (db-error? c))
  (check (db-error-backend c) => 'sqlite))

(let ([c (make-db-query-error 'db 'sqlite "SELECT * FROM bad")])
  (check-true (db-query-error? c))
  (check-true (db-error? c))
  (check (db-query-error-sql c) => "SELECT * FROM bad"))

(let ([c (make-db-constraint-violation 'db 'postgresql "unique_email")])
  (check-true (db-constraint-violation? c))
  (check (db-constraint-violation-constraint c) => "unique_email"))

;; Actor conditions
(let ([c (make-actor-dead 'actor 42)])
  (check-true (actor-dead? c))
  (check-true (actor-error? c))
  (check (actor-error-actor-id c) => 42))

(let ([c (make-mailbox-full 'actor 7 10000)])
  (check-true (mailbox-full? c))
  (check (mailbox-full-capacity c) => 10000))

;; Resource conditions
(let ([c (make-resource-already-closed 'resource 'file)])
  (check-true (resource-already-closed? c))
  (check-true (resource-error? c))
  (check (resource-error-resource-type c) => 'file))

(let ([c (make-resource-exhausted 'resource 'socket 1024)])
  (check-true (resource-exhausted? c))
  (check (resource-exhausted-limit c) => 1024))

;; Timeout conditions
(let ([c (make-timeout-error 'timeout 30 'tcp-read)])
  (check-true (timeout-error? c))
  (check (timeout-error-seconds c) => 30)
  (check (timeout-error-operation c) => 'tcp-read))

;; Parse conditions
(let ([c (make-parse-depth-exceeded 'parse 'json 1000 512)])
  (check-true (parse-depth-exceeded? c))
  (check-true (parse-error? c))
  (check (parse-depth-exceeded-limit c) => 1000)
  (check (parse-depth-exceeded-actual c) => 512))

;; Serialization conditions
(let ([c (make-unsafe-deserialize 'serialization "procedure")])
  (check-true (unsafe-deserialize? c))
  (check-true (serialization-error? c))
  (check (unsafe-deserialize-type-name c) => "procedure"))

;; Hierarchy: subtypes are supertypes
(let ([c (make-connection-refused 'network "host" 80)])
  (check-true (connection-refused? c))
  (check-true (network-error? c))
  (check-true (jerboa-condition? c))
  (check-false (db-error? c))
  (check-false (actor-error? c)))

;; Convenience raisers
(check-error (raise-network-error void "connection failed to ~a" "host"))
(check-error (raise-db-error 'sqlite "query failed: ~a" "bad SQL"))
(check-error (raise-timeout-error 30 'tcp-read "timed out after ~a seconds" 30))
(check-error (raise-parse-error 'json "invalid JSON at position ~a" 42))


;; =========================================================================
;; 2. Resource Management
;; =========================================================================

(display "--- Resource Management ---\n")

(import (std resource))

;; with-resource1: auto-close port
(let ([closed? #f])
  (let ([p (with-resource1 (port (open-input-string "hello"))
             (read-char port))])
    ;; Port should have been closed by dynamic-wind cleanup
    (check p => #\h)))

;; with-resource: multiple resources, cleanup order
(let ([order '()])
  (with-resource ([a 'resource-a (lambda (x) (set! order (cons 'a order)))]
                  [b 'resource-b (lambda (x) (set! order (cons 'b order)))])
    (check a => 'resource-a)
    (check b => 'resource-b))
  ;; Cleanup should happen right-to-left (b then a)
  (check order => '(a b)))

;; with-resource: cleanup on exception
(let ([cleaned? #f])
  (guard (exn [#t (void)])
    (with-resource ([r 'res (lambda (x) (set! cleaned? #t))])
      (error 'test "intentional")))
  (check-true cleaned?))

;; register-resource-cleanup!
(let ([cleaned? #f])
  ;; Register cleanup for vectors (silly example)
  (register-resource-cleanup!
   vector?
   (lambda (v) (set! cleaned? #t)))
  (with-resource ([v (vector 1 2 3)])
    (check (vector-ref v 0) => 1))
  (check-true cleaned?))


;; =========================================================================
;; 3. Error Context
;; =========================================================================

(display "--- Error Context ---\n")

;; Helper: string-contains
(define (string-contains haystack needle)
  (let ([hlen (string-length haystack)]
        [nlen (string-length needle)])
    (let loop ([i 0])
      (cond
        [(> (+ i nlen) hlen) #f]
        [(string=? (substring haystack i (+ i nlen)) needle) #t]
        [else (loop (+ i 1))]))))

(import (std error context))

;; Basic context accumulation
(let ([msg #f])
  (guard (exn
          [(message-condition? exn)
           (set! msg (condition-message exn))])
    (with-context "processing request"
      (with-context "validating input"
        (error 'test "bad input"))))
  ;; Message should contain the context chain
  (check-true (and (string? msg)
                   (string-contains msg "processing request")))
  (check-true (and (string? msg)
                   (string-contains msg "validating input"))))

;; context->string outside with-context is empty
(check (context->string) => "")

;; context->list outside is empty
(check (context->list) => '())

;; raise-in-context
(let ([msg #f])
  (guard (exn
          [(message-condition? exn)
           (set! msg (condition-message exn))])
    (with-context "outer"
      (raise-in-context 'test "inner error: ~a" 42)))
  (check-true (and (string? msg)
                   (string-contains msg "outer")))
  (check-true (and (string? msg)
                   (string-contains msg "inner error: 42"))))

;; Nested context
(let ([msg #f])
  (guard (exn
          [(message-condition? exn)
           (set! msg (condition-message exn))])
    (with-context "a"
      (with-context "b"
        (with-context "c"
          (raise-in-context 'test "boom")))))
  (check-true (and (string? msg)
                   (string-contains msg "a > b > c > boom"))))

;; =========================================================================
;; 4. Safe FASL
;; =========================================================================

(display "--- Safe FASL ---\n")

(import (std safe-fasl))

;; Safe write/read of plain data
(let ([data (list 1 "hello" #t (vector 'a 'b 'c) '((key . val)))])
  (let-values ([(port extract) (open-bytevector-output-port)])
    (safe-fasl-write data port)
    (let* ([bv (extract)]
           [result (safe-fasl-read (open-bytevector-input-port bv))])
      (check result => data))))

;; Reject procedures
(check-error (safe-fasl-write-bytevector (lambda () 42)))
(check-error (safe-fasl-write-bytevector (list 1 2 (lambda () 3))))

;; Allow procedures when opted in — but note Chez FASL itself may
;; reject procedures; our check is that safe-fasl-write doesn't
;; raise *our* error first
(check-error
 ;; With allow=false, our check fires first
 (safe-fasl-write-bytevector (list (lambda () 42))))
;; With allow=true, Chez's own fasl-write may still reject it
;; (that's fine — we just skip our pre-check)

;; Object count limit
(check-error
 (parameterize ([*fasl-max-object-count* 5])
   (safe-fasl-write-bytevector '(1 2 3 4 5 6 7 8 9 10))))

;; Byte size limit
(check-error
 (parameterize ([*fasl-max-byte-size* 10])
   (safe-fasl-write-bytevector (make-string 1000 #\x))))

;; Bytevector round-trip
(let* ([data (list 42 "test" (vector 1 2 3))]
       [bv (safe-fasl-write-bytevector data)]
       [result (safe-fasl-read-bytevector bv)])
  (check result => data))


;; =========================================================================
;; 5. Safe Timeout
;; =========================================================================

(display "--- Safe Timeout ---\n")

(import (std safe-timeout))

;; Successful completion within timeout
(let ([result (with-timeout 5 (+ 1 2))])
  (check result => 3))

;; Timeout fires on slow operation
(check-error
 (with-timeout 0.01
   (let loop () (loop))))  ;; infinite loop, should be interrupted

;; No timeout when #f
(let ([result (with-timeout #f (+ 3 4))])
  (check result => 7))


;; =========================================================================
;; 6. Immutable Data Structures
;; =========================================================================

(display "--- Immutable Data Structures ---\n")

(import (std immutable))

;; imap construction
(let ([m (imap "a" 1 "b" 2 "c" 3)])
  (check-true (imap? m))
  (check (imap-ref m "a") => 1)
  (check (imap-ref m "b") => 2)
  (check (imap-ref m "c") => 3)
  (check (imap-size m) => 3)
  (check-true (imap-has? m "a"))
  (check-false (imap-has? m "z")))

;; imap functional update — original unchanged
(let* ([m1 (imap "x" 10)]
       [m2 (imap-set m1 "y" 20)])
  (check (imap-ref m1 "x") => 10)
  (check-false (imap-has? m1 "y"))  ;; m1 unchanged
  (check (imap-ref m2 "x") => 10)
  (check (imap-ref m2 "y") => 20)
  (check (imap-size m1) => 1)
  (check (imap-size m2) => 2))

;; imap delete — original unchanged
(let* ([m1 (imap "a" 1 "b" 2)]
       [m2 (imap-delete m1 "a")])
  (check (imap-size m1) => 2)
  (check (imap-size m2) => 1)
  (check-true (imap-has? m1 "a"))
  (check-false (imap-has? m2 "a")))

;; imap odd args error
(check-error (imap "a" 1 "b"))

;; imap empty
(check (imap-size imap-empty) => 0)

;; hashtable->imap
(let ([ht (make-hashtable string-hash string=?)])
  (hashtable-set! ht "k" "v")
  (let ([m (hashtable->imap ht)])
    (check-true (imap? m))
    (check (imap-ref m "k") => "v")))

;; ivec construction
(let ([v (ivec 10 20 30)])
  (check-true (ivec? v))
  (check (ivec-length v) => 3)
  (check (ivec-ref v 0) => 10)
  (check (ivec-ref v 1) => 20)
  (check (ivec-ref v 2) => 30))

;; ivec functional update — original unchanged
(let* ([v1 (ivec 1 2 3)]
       [v2 (ivec-set v1 0 99)])
  (check (ivec-ref v1 0) => 1)   ;; unchanged
  (check (ivec-ref v2 0) => 99)
  (check (ivec-length v1) => 3)
  (check (ivec-length v2) => 3))

;; ivec append — original unchanged
(let* ([v1 (ivec 1 2)]
       [v2 (ivec-append v1 3)])
  (check (ivec-length v1) => 2)
  (check (ivec-length v2) => 3)
  (check (ivec-ref v2 2) => 3))

;; ivec->list
(check (ivec->list (ivec 1 2 3)) => '(1 2 3))

;; list->ivec
(let ([v (list->ivec '(4 5 6))])
  (check (ivec-ref v 0) => 4)
  (check (ivec-length v) => 3))

;; vector->ivec
(let ([v (vector->ivec (vector 7 8 9))])
  (check (ivec-ref v 0) => 7)
  (check (ivec-length v) => 3))

;; ivec empty
(check (ivec-length ivec-empty) => 0)

;; ivec-filter
(let ([v (ivec-filter odd? (ivec 1 2 3 4 5))])
  (check (ivec->list v) => '(1 3 5)))

;; ivec-map
(let ([v (ivec-map (lambda (x) (* x 2)) (ivec 1 2 3))])
  (check (ivec->list v) => '(2 4 6)))


;; =========================================================================
;; 7. Contract-checked safe wrappers (basic checks, no FFI needed)
;; =========================================================================

(display "--- Safe Wrappers ---\n")

(import (std safe))

;; File I/O contracts
(check-error (safe-open-input-file 42))         ;; not a string
(check-error (safe-open-input-file "/nonexistent/path/to/file.txt"))  ;; not found

;; Port cleanup via with-resource
(let ([content
       (with-resource ([p (safe-open-input-file
                           ;; Use this test file itself as input
                           "tests/test-gaps.ss")])
         (read-char p))])
  (check content => #\#))

;; TCP contract checks (type validation, no actual connection)
(check-error (safe-tcp-connect 42 80))           ;; address not string
(check-error (safe-tcp-connect "host" "80"))      ;; port not fixnum
(check-error (safe-tcp-connect "host" 99999))     ;; port out of range

;; SQLite contract checks (type validation only)
(check-error (safe-sqlite-exec "not-a-handle" "SELECT 1"))  ;; db not fixnum
(check-error (safe-sqlite-exec 1 42))                       ;; sql not string
(check-error (safe-sqlite-query "bad" "SELECT 1"))           ;; db not fixnum


;; =========================================================================
;; Summary
;; =========================================================================

(newline)
(display "========================================\n")
(display (format "Results: ~a passed, ~a failed\n" pass-count fail-count))
(display "========================================\n")
(when (> fail-count 0) (exit 1))
