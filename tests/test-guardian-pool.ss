#!/usr/bin/env scheme-script
#!chezscheme
(import (chezscheme)
        (std misc guardian-pool))

(define test-count 0)
(define pass-count 0)

(define (test name thunk)
  (set! test-count (+ test-count 1))
  (guard (e [#t (display "FAIL: ") (display name) (newline)
              (display "  Error: ") (display (condition-message e)) (newline)])
    (thunk)
    (set! pass-count (+ pass-count 1))
    (display "PASS: ") (display name) (newline)))

(define (assert-equal actual expected msg)
  (unless (equal? actual expected)
    (error 'assert-equal
           (string-append msg ": expected " (format "~s" expected)
                          " got " (format "~s" actual)))))

(define (assert-true val msg)
  (unless val
    (error 'assert-true (string-append msg ": expected #t"))))

;; Test 1: basic pool creation and resource registration
(test "make-guardian-pool and register"
  (lambda ()
    (let* ([freed '()]
           [pool (make-guardian-pool (lambda (r) (set! freed (cons r freed))))])
      (assert-true (guardian-pool? pool) "pool is a guardian-pool")
      (let ([r1 (list 'resource-1)]
            [r2 (list 'resource-2)])
        (guardian-pool-register pool r1)
        (guardian-pool-register pool r2)
        ;; Resources exist and are tracked (not yet freed)
        (assert-equal freed '() "nothing freed yet")))))

;; Test 2: manual drain clears all resources and calls cleanup
(test "guardian-pool-drain! cleans all resources"
  (lambda ()
    (let* ([freed '()]
           [pool (make-guardian-pool (lambda (r) (set! freed (cons r freed))))]
           [r1 (list 'a)]
           [r2 (list 'b)]
           [r3 (list 'c)])
      (guardian-pool-register pool r1)
      (guardian-pool-register pool r2)
      (guardian-pool-register pool r3)
      (let ([n (guardian-pool-drain! pool)])
        ;; All 3 should be cleaned up
        (assert-equal n 3 "drain count")
        (assert-equal (length freed) 3 "freed count")
        ;; Each resource should appear exactly once
        (assert-true (memq r1 freed) "r1 freed")
        (assert-true (memq r2 freed) "r2 freed")
        (assert-true (memq r3 freed) "r3 freed")))))

;; Test 3: drain after some are already manually removed
(test "drain after partial cleanup"
  (lambda ()
    (let* ([freed '()]
           [pool (make-guardian-pool (lambda (r) (set! freed (cons r freed))))]
           [r1 (list 'x)]
           [r2 (list 'y)])
      (guardian-pool-register pool r1)
      (guardian-pool-register pool r2)
      ;; Drain should get both
      (guardian-pool-drain! pool)
      (assert-equal (length freed) 2 "both freed")
      ;; Second drain should find nothing
      (let ([n2 (guardian-pool-drain! pool)])
        (assert-equal n2 0 "second drain finds nothing")
        (assert-equal (length freed) 2 "still just 2")))))

;; Test 4: with-guarded-resource ensures cleanup on normal exit
(test "with-guarded-resource normal exit"
  (lambda ()
    (let* ([freed '()]
           [pool (make-guardian-pool (lambda (r) (set! freed (cons r freed))))]
           [resource (list 'guarded)])
      (let ([result
             (with-guarded-resource (h resource pool)
               (assert-equal h resource "bound correctly")
               'ok)])
        (assert-equal result 'ok "body returns value")
        (assert-true (memq resource freed) "resource was freed on exit")))))

;; Test 5: with-guarded-resource ensures cleanup on exception
(test "with-guarded-resource exception exit"
  (lambda ()
    (let* ([freed '()]
           [pool (make-guardian-pool (lambda (r) (set! freed (cons r freed))))]
           [resource (list 'guarded-err)])
      (guard (e [#t (void)])  ;; catch the error
        (with-guarded-resource (h resource pool)
          (error 'test "deliberate error")))
      (assert-true (memq resource freed) "resource freed despite exception"))))

;; Test 6: pointerlike creation and value access
(test "make-pointerlike and pointerlike-value"
  (lambda ()
    (let* ([freed '()]
           [pool (make-guardian-pool (lambda (r) (set! freed (cons r freed))))])
      (let ([p (make-pointerlike pool 42)])
        (assert-true (pointerlike? p) "is pointerlike")
        (assert-equal (pointerlike-value p) 42 "value is 42")))))

;; Test 7: pointerlike manual free
(test "pointerlike-free! manual cleanup"
  (lambda ()
    (let* ([freed '()]
           [pool (make-guardian-pool (lambda (r) (set! freed (cons r freed))))])
      (let ([p (make-pointerlike pool 99)])
        (assert-equal (pointerlike-value p) 99 "value before free")
        (pointerlike-free! p)
        ;; After free, value access should error
        (assert-true (memq p freed) "cleanup proc was called")
        (let ([got-error #f])
          (guard (e [#t (set! got-error #t)])
            (pointerlike-value p))
          (assert-true got-error "accessing freed pointerlike raises error"))
        ;; Double free should be a no-op
        (let ([count-before (length freed)])
          (pointerlike-free! p)
          (assert-equal (length freed) count-before "double free is no-op"))))))

;; Test 8: pointerlike freed by drain
(test "pointerlike freed by drain"
  (lambda ()
    (let* ([freed '()]
           [pool (make-guardian-pool (lambda (r) (set! freed (cons r freed))))])
      (let ([p (make-pointerlike pool 77)])
        (assert-equal (pointerlike-value p) 77 "value ok")
        (guardian-pool-drain! pool)
        (assert-true (memq p freed) "pointerlike in freed list")))))

;; Test 9: collect! returns 0 when nothing has been GC'd
(test "collect! returns 0 with live references"
  (lambda ()
    (let* ([freed '()]
           [pool (make-guardian-pool (lambda (r) (set! freed (cons r freed))))]
           [r1 (list 'alive)])
      (guardian-pool-register pool r1)
      ;; r1 is still referenced, so GC won't reclaim it
      (collect (collect-maximum-generation))
      (let ([n (guardian-pool-collect! pool)])
        ;; r1 is live, so guardian should not have returned it
        (assert-equal n 0 "nothing collected while live")
        (assert-equal freed '() "nothing freed while live")
        ;; Keep r1 alive past the collect call
        (assert-true (pair? r1) "r1 still alive")))))

;; Test 10: error in cleanup proc does not prevent other cleanups
(test "cleanup errors are swallowed in drain"
  (lambda ()
    (let* ([cleaned '()]
           [pool (make-guardian-pool
                   (lambda (r)
                     (when (equal? r 'bomb)
                       (error 'cleanup "boom"))
                     (set! cleaned (cons r cleaned))))])
      (guardian-pool-register pool 'ok-1)
      (guardian-pool-register pool 'bomb)
      (guardian-pool-register pool 'ok-2)
      (guardian-pool-drain! pool)
      ;; Both ok-1 and ok-2 should be cleaned despite 'bomb erroring
      (assert-true (memv 'ok-1 cleaned) "ok-1 cleaned")
      (assert-true (memv 'ok-2 cleaned) "ok-2 cleaned"))))

;; Test 11: guardian-pool? predicate
(test "guardian-pool? predicate"
  (lambda ()
    (let ([pool (make-guardian-pool void)])
      (assert-true (guardian-pool? pool) "pool is guardian-pool")
      (assert-true (not (guardian-pool? 42)) "42 is not")
      (assert-true (not (guardian-pool? '())) "list is not"))))

;; Test 12: with-guarded-resource returns body value
(test "with-guarded-resource returns body result"
  (lambda ()
    (let ([pool (make-guardian-pool void)])
      (let ([v (with-guarded-resource (h (list 1 2 3) pool)
                 (apply + h))])
        (assert-equal v 6 "body returns sum")))))

(newline)
(display "=========================================") (newline)
(display (format "Results: ~a/~a passed" pass-count test-count)) (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
