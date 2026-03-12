#!/usr/bin/env scheme-script
;;; Tests for Record Introspection (Phase 5c — Track 14.3)

(import (chezscheme) (std debug record-inspect))

(define test-count 0)
(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ name expr => expected)
     (begin
       (set! test-count (+ test-count 1))
       (let ([result expr])
         (if (equal? result expected)
             (begin (printf "  PASS: ~a~n" name)
                    (set! pass-count (+ pass-count 1)))
             (begin (printf "  FAIL: ~a~n" name)
                    (printf "    expected: ~s~n" expected)
                    (printf "    got:      ~s~n" result)
                    (set! fail-count (+ fail-count 1))))))]))

(define-syntax check-true
  (syntax-rules ()
    [(_ name e) (check name e => #t)]))

;; Define test record types
(define-record-type point
  (fields (immutable x point-x)
          (immutable y point-y))
  (protocol (lambda (new) (lambda (x y) (new x y)))))

(define-record-type rect
  (fields (immutable top-left  rect-tl)
          (mutable   width     rect-width  set-rect-width!)
          (mutable   height    rect-height set-rect-height!))
  (protocol (lambda (new) (lambda (tl w h) (new tl w h)))))

;; --------------------------------------------------------------------------
;; 1. Type metadata
;; --------------------------------------------------------------------------

(printf "~n--- Type Metadata ---~n")

(let ([p (make-point 3 4)])
  (check "record-type-name point"
         (record-type-name (record-rtd p))
         => 'point)
  (check "record-type-field-names point"
         (vector->list (record-type-field-names (record-rtd p)))
         => '(x y))
  (check "record-field-count point"
         (record-field-count p)
         => 2))

(let ([r (make-rect (make-point 0 0) 10 20)])
  (check "record-type-name rect"
         (record-type-name (record-rtd r))
         => 'rect)
  (check "record-field-count rect"
         (record-field-count r)
         => 3))

;; --------------------------------------------------------------------------
;; 2. Field access by index
;; --------------------------------------------------------------------------

(printf "~n--- Field Access by Index ---~n")

(let ([p (make-point 7 9)])
  (check "record-ref index 0" (record-ref p 0) => 7)
  (check "record-ref index 1" (record-ref p 1) => 9))

;; --------------------------------------------------------------------------
;; 3. Field access by name
;; --------------------------------------------------------------------------

(printf "~n--- Field Access by Name ---~n")

(let ([p (make-point 5 8)])
  (check "record-ref by name x" (record-ref p 'x) => 5)
  (check "record-ref by name y" (record-ref p 'y) => 8))

(let ([r (make-rect (make-point 1 2) 30 40)])
  (check "record-ref by name width"  (record-ref r 'width)  => 30)
  (check "record-ref by name height" (record-ref r 'height) => 40))

;; --------------------------------------------------------------------------
;; 4. Mutation
;; --------------------------------------------------------------------------

(printf "~n--- Mutation ---~n")

(let ([r (make-rect (make-point 0 0) 100 200)])
  (record-set! r 'width 55)
  (check "record-set! by name" (rect-width r) => 55)
  (record-set! r 1 75)
  (check "record-set! by index" (rect-width r) => 75))

;; --------------------------------------------------------------------------
;; 5. record->alist
;; --------------------------------------------------------------------------

(printf "~n--- record->alist ---~n")

(let ([p (make-point 3 4)])
  (check "record->alist point"
         (record->alist p)
         => '((x . 3) (y . 4))))

(let ([r (make-rect (make-point 0 0) 10 20)])
  (check "record->alist rect fields"
         (map car (record->alist r))
         => '(top-left width height)))

;; --------------------------------------------------------------------------
;; 6. record-copy
;; --------------------------------------------------------------------------

(printf "~n--- record-copy ---~n")

(let* ([p1 (make-point 3 4)]
       [p2 (record-copy p1)])
  (check "record-copy equal"      (equal? (record->alist p1) (record->alist p2)) => #t)
  (check-true "record-copy fresh" (not (eq? p1 p2))))

;; --------------------------------------------------------------------------
;; 7. record-type-parent*
;; --------------------------------------------------------------------------

(printf "~n--- record-type-parent* ---~n")

(let ([p (make-point 1 2)])
  (check "root type has no parent"
         (record-type-parent* (record-rtd p))
         => #f))

;; --------------------------------------------------------------------------
;; Summary
;; --------------------------------------------------------------------------

(printf "~n===========================================~n")
(printf "Tests: ~a  |  Passed: ~a  |  Failed: ~a~n"
        test-count pass-count fail-count)
(printf "===========================================~n")
(when (> fail-count 0)
  (printf "~nFAILED~n")
  (exit 1))
(printf "~nAll tests passed!~n")
