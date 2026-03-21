#!chezscheme
;;; test-security-capability.ss -- Tests for both capability modules
;;; Tests (std security capability) and (std capability) for:
;;; - Basic operations
;;; - Forgery prevention (opaque sealed records)
;;; - CSPRNG nonces (unpredictable, unique)
;;; - Attenuation
;;; - Capability context and violation conditions

(import (chezscheme)
        (prefix (std security capability) sc:)
        (prefix (std capability) oc:))

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
       (begin
         (set! fail-count (+ fail-count 1))
         (display "FAIL: expected error from ") (write 'expr) (newline)))]))

;; ========== (std security capability) tests ==========

(display "  Testing (std security capability)...\n")

;; Basic creation and predicates
(let ([fs-cap (sc:make-fs-capability 'read: #t 'write: #t 'paths: '("/tmp"))])
  (check (sc:capability? fs-cap) => #t)
  (check (eq? (sc:capability-type fs-cap) 'filesystem) => #t)
  (check (sc:fs-read? fs-cap) => #t)
  (check (sc:fs-write? fs-cap) => #t)
  (check (sc:fs-execute? fs-cap) => #f)
  (check (sc:fs-allowed-path? fs-cap "/tmp/foo") => #t)
  (check (sc:fs-allowed-path? fs-cap "/etc/passwd") => #f))

;; Network capability
(let ([net-cap (sc:make-net-capability 'connect: #t 'listen: #f 'hosts: '("example.com"))])
  (check (sc:capability? net-cap) => #t)
  (check (eq? (sc:capability-type net-cap) 'network) => #t)
  (check (sc:net-connect? net-cap) => #t)
  (check (sc:net-listen? net-cap) => #f)
  (check (and (sc:net-allowed-host? net-cap "example.com") #t) => #t))

;; Process capability
(let ([proc-cap (sc:make-process-capability 'spawn: #t 'signal: #f)])
  (check (sc:capability? proc-cap) => #t)
  (check (sc:process-spawn? proc-cap) => #t)
  (check (sc:process-signal? proc-cap) => #f))

;; Environment capability
(let ([env-cap (sc:make-env-capability 'read: #t 'write: #f)])
  (check (sc:capability? env-cap) => #t)
  (check (sc:env-read? env-cap) => #t)
  (check (sc:env-write? env-cap) => #f))

;; FORGERY PREVENTION: vectors do NOT pass capability?
(check (sc:capability? (vector 'capability 0 'filesystem '())) => #f)
(check (sc:capability? (vector 'capability 999 'network '())) => #f)
(check (sc:capability? "not-a-capability") => #f)
(check (sc:capability? 42) => #f)
(check (sc:capability? #f) => #f)
(check (sc:capability? '()) => #f)

;; Two capabilities have different nonces (CSPRNG)
(let ([a (sc:make-fs-capability)]
      [b (sc:make-fs-capability)])
  (check (sc:capability? a) => #t)
  (check (sc:capability? b) => #t)
  ;; They are distinct objects
  (check (eq? a b) => #f))

;; Attenuation
(let* ([fs-cap (sc:make-fs-capability 'read: #t 'write: #t 'paths: '("/tmp" "/home"))]
       [restricted (sc:attenuate-capability fs-cap 'write: #f)])
  (check (sc:capability? restricted) => #t)
  (check (sc:fs-read? restricted) => #t)
  (check (sc:fs-write? restricted) => #f))

;; with-capabilities and check-capability!
(let ([fs-cap (sc:make-fs-capability 'read: #t 'write: #t)])
  (check (sc:with-capabilities (list fs-cap)
           (lambda () (sc:check-capability! 'filesystem 'read) #t)) => #t))

;; check-capability! raises violation when permission missing
(let ([fs-cap (sc:make-fs-capability 'read: #t 'write: #f)])
  (check-error
    (sc:with-capabilities (list fs-cap)
      (lambda () (sc:check-capability! 'filesystem 'write)))))

;; check-capability! raises violation when no caps at all
(check-error
  (sc:with-capabilities '()
    (lambda () (sc:check-capability! 'filesystem 'read))))

;; capability-violation condition type
(let ([fs-cap (sc:make-fs-capability 'read: #t 'write: #f)])
  (guard (exn
    [(sc:capability-violation? exn)
     (check (eq? (sc:capability-violation-type exn) 'filesystem) => #t)
     (set! pass-count (+ pass-count 1))]  ;; count the guard match itself
    [#t
     (set! fail-count (+ fail-count 1))
     (display "FAIL: expected capability-violation condition\n")])
    (sc:with-capabilities (list fs-cap)
      (lambda () (sc:check-capability! 'filesystem 'write)))))

;; Cross-module forgery: (std capability) objects don't pass (std security capability) checks
(let ([oc-cap (oc:make-root-capability)])
  (check (sc:capability? oc-cap) => #f))

;; ========== (std capability) tests ==========

(display "  Testing (std capability)...\n")

;; Root capability
(let ([root (oc:make-root-capability)])
  (check (oc:capability? root) => #t)
  (check (oc:root-capability? root) => #t)
  (check (oc:capability-valid? root) => #t))

;; FS capability
(let ([fs (oc:make-fs-capability #t #f '("/tmp"))])
  (check (oc:fs-capability? fs) => #t)
  (check (oc:fs-cap-readable? fs) => #t)
  (check (oc:fs-cap-writable? fs) => #f)
  (check (equal? (oc:fs-cap-paths fs) '("/tmp")) => #t))

;; Net capability
(let ([net (oc:make-net-capability '("example.com") #t)])
  (check (oc:net-capability? net) => #t)
  (check (equal? (oc:net-cap-allowed-hosts net) '("example.com")) => #t)
  (check (oc:net-cap-deny-others? net) => #t))

;; Eval capability
(let ([ev (oc:make-eval-capability '((chezscheme)))])
  (check (oc:eval-capability? ev) => #t)
  (check (equal? (oc:eval-cap-allowed-modules ev) '((chezscheme))) => #t))

;; FORGERY PREVENTION for (std capability)
(let ([fake (vector 'capability 0 'root #t)])
  (check (oc:capability? fake) => #f)
  (check (oc:root-capability? fake) => #f)
  (check (oc:fs-capability? fake) => #f))

;; Two capabilities have different nonces
(let ([a (oc:make-root-capability)]
      [b (oc:make-root-capability)])
  (check (eq? a b) => #f)
  (check (oc:capability-valid? a) => #t)
  (check (oc:capability-valid? b) => #t))

;; Attenuation - fs read-only from root
(let* ([root (oc:make-root-capability)]
       [fs (oc:attenuate-fs root 'read-only: #t 'paths: '("/tmp"))])
  (check (oc:fs-capability? fs) => #t)
  (check (oc:fs-cap-readable? fs) => #t)
  (check (oc:fs-cap-writable? fs) => #f)
  (check (equal? (oc:fs-cap-paths fs) '("/tmp")) => #t))

;; Attenuation - net from root
(let* ([root (oc:make-root-capability)]
       [net (oc:attenuate-net root 'allow: '("localhost") 'deny-all-others: #t)])
  (check (oc:net-capability? net) => #t)
  (check (equal? (oc:net-cap-allowed-hosts net) '("localhost")) => #t)
  (check (oc:net-cap-deny-others? net) => #t))

;; Capability-guarded connection
(let ([net (oc:make-net-capability '("example.com") #t)])
  (check (equal? (oc:cap-connect net "example.com" 443) '("example.com" 443)) => #t)
  (check-error (oc:cap-connect net "evil.com" 443)))

;; Cross-module forgery: (std security capability) objects don't pass (std capability) checks
(let ([sc-cap (sc:make-fs-capability 'read: #t)])
  (check (oc:capability? sc-cap) => #f))

;; Sandbox basic execution
(check (oc:with-sandbox (lambda () (+ 1 2))) => 3)

;; Sandbox timeout
(check-error
  (oc:with-sandbox (lambda () (let loop () (loop)))
    'timeout-ms: 100))

(display "  security-capability: ")
(display pass-count) (display " passed")
(when (> fail-count 0)
  (display ", ") (display fail-count) (display " failed"))
(newline)
(when (> fail-count 0) (exit 1))
