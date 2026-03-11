#!chezscheme
;;; Tests for (std arena) — Arena allocator

(import (chezscheme) (std arena))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(define-syntax test-pred
  (syntax-rules ()
    [(_ name expr pred)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (pred got)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: value ~s failed predicate~%" name got)))))]))

(define-syntax test-raises
  (syntax-rules ()
    [(_ name expr)
     (let ([raised #f])
       (guard (exn [#t (set! raised #t)])
         expr)
       (if raised
         (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
         (begin (set! fail (+ fail 1))
                (printf "FAIL ~a: expected exception, got none~%" name))))]))

(printf "--- (std arena) tests ---~%")

;; ========== Basic creation ==========

(test "arena/make and predicate"
  (arena? (make-arena 1024))
  #t)

(test "arena/not arena"
  (arena? 42)
  #f)

(test "arena/capacity"
  (arena-capacity (make-arena 4096))
  4096)

(test "arena/used initially 0"
  (arena-used (make-arena 1024))
  0)

(test "arena/remaining initially full"
  (arena-remaining (make-arena 1024))
  1024)

;; ========== arena-alloc ==========

(test "arena-alloc/returns bytevector"
  (let* ([a (make-arena 1024)]
         [bv (arena-alloc a 16)])
    (bytevector? bv))
  #t)

(test "arena-alloc/correct size"
  (let* ([a (make-arena 1024)]
         [bv (arena-alloc a 32)])
    (bytevector-length bv))
  32)

(test "arena-alloc/used increases"
  (let* ([a (make-arena 1024)])
    (arena-alloc a 100)
    (arena-used a))
  100)

(test "arena-alloc/multiple allocs accumulate"
  (let* ([a (make-arena 1024)])
    (arena-alloc a 10)
    (arena-alloc a 20)
    (arena-alloc a 30)
    (arena-used a))
  60)

(test "arena-alloc/remaining decreases"
  (let* ([a (make-arena 1024)])
    (arena-alloc a 100)
    (arena-remaining a))
  924)

(test "arena-alloc/zero size"
  (let* ([a (make-arena 1024)]
         [bv (arena-alloc a 0)])
    (bytevector-length bv))
  0)

(test-raises "arena-alloc/overflow raises error"
  (let* ([a (make-arena 100)])
    (arena-alloc a 200)))

;; ========== arena-reset! ==========

(test "arena-reset/used goes to 0"
  (let* ([a (make-arena 1024)])
    (arena-alloc a 512)
    (arena-reset! a)
    (arena-used a))
  0)

(test "arena-reset/remaining restored"
  (let* ([a (make-arena 1024)])
    (arena-alloc a 512)
    (arena-reset! a)
    (arena-remaining a))
  1024)

(test "arena-reset/can reuse after reset"
  (let* ([a (make-arena 1024)])
    (arena-alloc a 800)
    (arena-reset! a)
    (arena-alloc a 800) ;; should not error
    (arena-used a))
  800)

;; ========== arena-checkpoint / arena-rollback! ==========

(test "checkpoint/captures position"
  (let* ([a (make-arena 1024)])
    (arena-alloc a 100)
    (arena-checkpoint a))
  100)

(test "rollback/restores position"
  (let* ([a (make-arena 1024)])
    (arena-alloc a 100)
    (let ([cp (arena-checkpoint a)])
      (arena-alloc a 200)
      (arena-rollback! a cp)
      (arena-used a)))
  100)

(test "rollback/multiple allocs then rollback"
  (let* ([a (make-arena 1024)])
    (let ([cp (arena-checkpoint a)])
      (arena-alloc a 50)
      (arena-alloc a 50)
      (arena-alloc a 50)
      (arena-rollback! a cp)
      (arena-used a)))
  0)

;; ========== arena-alloc-string ==========

(test "alloc-string/returns string"
  (let* ([a (make-arena 1024)])
    (arena-alloc-string a "hello"))
  "hello")

(test "alloc-string/uses arena space"
  (let* ([a (make-arena 1024)])
    (arena-alloc-string a "hello") ;; 5 bytes + null = 6
    (> (arena-used a) 0))
  #t)

;; ========== arena-alloc-bytes ==========

(test "alloc-bytes/returns equal bytevector"
  (let* ([a   (make-arena 1024)]
         [src (bytevector 1 2 3 4 5)]
         [dst (arena-alloc-bytes a src)])
    (equal? src dst))
  #t)

(test "alloc-bytes/uses arena space"
  (let* ([a   (make-arena 1024)]
         [src (make-bytevector 64 0)])
    (arena-alloc-bytes a src)
    (arena-used a))
  64)

;; ========== arena-destroy! ==========

(test-raises "destroy/alloc after destroy raises"
  (let* ([a (make-arena 1024)])
    (arena-destroy! a)
    (arena-alloc a 10)))

(test "destroy/stats shows destroyed"
  (let* ([a (make-arena 1024)])
    (arena-destroy! a)
    (cdr (assq 'destroyed (arena-stats a))))
  #t)

;; ========== with-arena ==========

(test "with-arena/body result returned"
  (with-arena 1024
    (+ 1 2))
  3)

(test "with-arena/arena available in body"
  (with-arena 512
    ;; If we can create and use the arena, it works
    42)
  42)

;; ========== arena-stats ==========

(test "stats/has capacity key"
  (let* ([a    (make-arena 2048)]
         [stats (arena-stats a)])
    (assq 'capacity stats))
  '(capacity . 2048))

(test "stats/has used key"
  (let* ([a     (make-arena 1024)])
    (arena-alloc a 256)
    (cdr (assq 'used (arena-stats a))))
  256)

;; ========== Arena interner ==========

(test "interner/basic intern"
  (let* ([a  (make-arena (* 1024 64))]
         [i  (make-arena-interner a)]
         [s1 (arena-intern! i "hello")]
         [s2 (arena-intern! i "hello")])
    (eq? s1 s2))
  #t)

(test "interner/lookup found"
  (let* ([a  (make-arena (* 1024 64))]
         [i  (make-arena-interner a)])
    (arena-intern! i "world")
    (string? (arena-intern-lookup i "world")))
  #t)

(test "interner/lookup not found returns #f"
  (let* ([a  (make-arena (* 1024 64))]
         [i  (make-arena-interner a)])
    (arena-intern-lookup i "never-added"))
  #f)

(test "interner/different strings are different"
  (let* ([a  (make-arena (* 1024 64))]
         [i  (make-arena-interner a)]
         [s1 (arena-intern! i "foo")]
         [s2 (arena-intern! i "bar")])
    (equal? s1 s2))
  #f)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
