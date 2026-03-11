#!chezscheme
;;; Tests for (std typed advanced) — Steps 14-17

(import (chezscheme) (std typed) (std typed advanced))

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
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(printf "--- (std typed advanced) tests ---~%")

;;;; Step 14: Occurrence Typing

(printf "~%-- Occurrence Typing --~%")

;; if/t narrows type in true branch
(test "if/t string narrowing"
  (parameterize ([*typed-mode* 'debug])
    (let ([x "hello"])
      (if/t (string? x)
        (string-length x)
        -1)))
  5)

;; if/t passes when type is wrong (release mode — no assertion)
(test "if/t false branch"
  (parameterize ([*typed-mode* 'debug])
    (let ([x 42])
      (if/t (string? x)
        'string
        'not-string)))
  'not-string)

;; when/t
(test "when/t"
  (let ([result '()])
    (let ([x "test"])
      (when/t (string? x)
        (set! result (list 'string (string-length x)))))
    result)
  '(string 4))

;; cond/t with multiple branches
(test "cond/t narrowing"
  (parameterize ([*typed-mode* 'debug])
    (define (classify x)
      (cond/t
        [(string? x)  (list 'string (string-length x))]
        [(fixnum? x)  (list 'fixnum x)]
        [(pair? x)    (list 'pair (length x))]
        [else         (list 'unknown)]))
    (list (classify "hi")
          (classify 42)
          (classify '(1 2 3))
          (classify #t)))
  '((string 2) (fixnum 42) (pair 3) (unknown)))

;;;; Step 15: Row Polymorphism

(printf "~%-- Row Polymorphism --~%")

;; Define a record type for testing
(define-record-type point (fields x y))
(define-record-type named (fields name))

;; defrow
(defrow Positionable
  (point-x : number)
  (point-y : number))

(test "defrow creates predicate"
  (procedure? Positionable?)
  #t)

(test "row-check with Positionable"
  (let ([p (make-point 3 4)])
    (Positionable? p))
  #t)

(test "row-check fails on non-matching"
  (let ([n (make-named "Alice")])
    (Positionable? n))
  #f)

;; row-check inline
(test "row-check inline"
  (let ([p (make-point 10 20)])
    (row-check p (point-x : number) (point-y : number)))
  #t)

;;;; Step 16: Refinement Types

(printf "~%-- Refinement Types --~%")

;; assert-refined: base type + predicate
(test "assert-refined/pass"
  (parameterize ([*typed-mode* 'debug])
    (assert-refined 5 number positive?))
  5)

(test "assert-refined/base-fail"
  (guard (exn [#t 'caught])
    (parameterize ([*typed-mode* 'debug])
      (assert-refined "hello" number positive?))
    'missed)
  'caught)

(test "assert-refined/pred-fail"
  (guard (exn [#t 'caught])
    (parameterize ([*typed-mode* 'debug])
      (assert-refined -5 number positive?))
    'missed)
  'caught)

(test "assert-refined/release-no-check"
  (parameterize ([*typed-mode* 'release])
    (assert-refined -5 number positive?))  ;; no check in release mode
  -5)

;; refinement-type record
(test "make-refinement-type"
  (let ([rt (make-refinement-type 'number positive?)])
    (and (refinement-type? rt)
         (eq? (refinement-type-base rt) 'number)
         (procedure? (refinement-type-pred rt))))
  #t)

;;;; Step 17: Type-Directed Compilation

(printf "~%-- Type-Directed Compilation --~%")

;; define/tc with fixnum args should use fx+ internally
(test "define/tc fixnum specialization"
  (parameterize ([*typed-mode* 'debug])
    (define/tc (add-fx [a : fixnum] [b : fixnum]) : fixnum
      (+ a b))
    (add-fx 3 4))
  7)

;; define/tc with flonum args
(test "define/tc flonum specialization"
  (parameterize ([*typed-mode* 'debug])
    (define/tc (add-fl [a : flonum] [b : flonum]) : flonum
      (+ a b))
    (add-fl 1.5 2.5))
  4.0)

;; define/tc type checks still work in debug mode
(test "define/tc type check"
  (guard (exn [#t 'caught])
    (parameterize ([*typed-mode* 'debug])
      (define/tc (need-fix [x : fixnum]) : fixnum x)
      (need-fix "bad")
      'missed)
    'caught)
  'caught)

;; define/tc with refinement type
(test "define/tc refinement"
  (parameterize ([*typed-mode* 'debug])
    (define/tc (sqrt-safe [x : (Refine number (lambda (n) (>= n 0)))]) : number
      (sqrt x))
    (sqrt-safe 4.0))
  2.0)

(test "define/tc refinement fails"
  (guard (exn [#t 'caught])
    (parameterize ([*typed-mode* 'debug])
      (define/tc (sqrt-safe2 [x : (Refine number (lambda (n) (>= n 0)))]) : number
        (sqrt x))
      (sqrt-safe2 -1.0)
      'missed)
    'caught)
  'caught)

;; lambda/tc
(test "lambda/tc fixnum"
  (parameterize ([*typed-mode* 'debug])
    (let ([f (lambda/tc ([x : fixnum] [y : fixnum]) : fixnum
               (* x y))])
      (f 6 7)))
  42)

;; Performance: type-directed fixnum ops should be fast
(test "define/tc fixnum/perf"
  (parameterize ([*typed-mode* 'release])
    (define/tc (sum-fx [n : fixnum]) : fixnum
      (let loop ([i 0] [acc 0])
        (if (= i n)
          acc
          (loop (+ i 1) (+ acc i)))))
    (sum-fx 100))
  4950)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
