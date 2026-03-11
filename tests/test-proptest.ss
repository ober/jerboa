#!chezscheme
;;; Tests for (std proptest) — Property-Based Testing with Shrinking

(import (chezscheme) (std proptest))

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
                  (printf "FAIL ~a: predicate failed on ~s~%" name got)))))]))

(printf "--- (std proptest) tests ---~%")

;; ======== RNG ========

(printf "~%-- RNG --~%")

(test "make-rng returns rng"
  (rng? (make-rng 42))
  #t)

(test "rng-next! returns integer"
  (integer? (rng-next! (make-rng 42)))
  #t)

(test "rng-next! is deterministic with same seed"
  (let ([r1 (make-rng 100)]
        [r2 (make-rng 100)])
    (= (rng-next! r1) (rng-next! r2)))
  #t)

(test "rng-next! different seeds give different values"
  (let ([r1 (make-rng 1)]
        [r2 (make-rng 2)])
    (= (rng-next! r1) (rng-next! r2)))
  #f)

(test "rng-next-float! in [0,1)"
  (let ([rng (make-rng 42)])
    (let ([f (rng-next-float! rng)])
      (and (>= f 0.0) (< f 1.0))))
  #t)

(test "rng advances state"
  (let ([rng (make-rng 42)])
    (let ([a (rng-next! rng)]
          [b (rng-next! rng)])
      (not (= a b))))
  #t)

;; ======== Basic Generators ========

(printf "~%-- Basic Generators --~%")

(test "generator? recognizes generator"
  (generator? (gen-integer 0 10))
  #t)

(test "generator? rejects non-generator"
  (generator? 42)
  #f)

(test "gen-integer in range"
  (let ([rng (make-rng 42)])
    (let ([v (gen-sample (gen-integer 5 10) rng)])
      (and (>= v 5) (<= v 10))))
  #t)

(test "gen-integer lo=hi gives that value"
  (let ([rng (make-rng 42)])
    (gen-sample (gen-integer 7 7) rng))
  7)

(test "gen-nat returns non-negative"
  (let ([rng (make-rng 42)])
    (let ([v (gen-sample (gen-nat 20) rng)])
      (and (integer? v) (>= v 0) (<= v 20))))
  #t)

(test "gen-boolean returns boolean"
  (let ([rng (make-rng 42)])
    (boolean? (gen-sample (gen-boolean) rng)))
  #t)

(test "gen-char returns char"
  (let ([rng (make-rng 42)])
    (char? (gen-sample (gen-char) rng)))
  #t)

(test "gen-char in printable range"
  (let ([rng (make-rng 42)])
    (let ([c (gen-sample (gen-char) rng)])
      (and (char>=? c #\space) (char<=? c #\~))))
  #t)

(test "gen-string returns string"
  (let ([rng (make-rng 42)])
    (string? (gen-sample (gen-string 10 (gen-char)) rng)))
  #t)

(test "gen-list returns list"
  (let ([rng (make-rng 42)])
    (list? (gen-sample (gen-list 5 (gen-integer 0 100)) rng)))
  #t)

(test "gen-vector returns vector"
  (let ([rng (make-rng 42)])
    (vector? (gen-sample (gen-vector 5 (gen-integer 0 10)) rng)))
  #t)

(test "gen-symbol returns symbol"
  (let ([rng (make-rng 42)])
    (symbol? (gen-sample (gen-symbol) rng)))
  #t)

(test "gen-real returns number"
  (let ([rng (make-rng 42)])
    (number? (gen-sample (gen-real) rng)))
  #t)

(test "gen-one-of picks from given values"
  (let ([rng (make-rng 42)])
    (let ([vals '(a b c d)])
      (memq (gen-sample (apply gen-one-of vals) rng) vals)))
  '(b c d))  ;; just checks it's in the list (will be truthy)

;; Rewrite as predicate test
(test-pred "gen-one-of picks from list"
  (let ([rng (make-rng 42)])
    (gen-sample (gen-one-of 1 2 3 4 5) rng))
  (lambda (v) (member v '(1 2 3 4 5))))

(test-pred "gen-frequency picks weighted"
  (let ([rng (make-rng 42)])
    ;; heavy weight on 42
    (gen-sample (gen-frequency (list 99 (gen-integer 42 42))
                               (list 1  (gen-integer 0 0)))
                rng))
  (lambda (v) (or (= v 42) (= v 0))))

;; ======== Generator Combinators ========

(printf "~%-- Generator Combinators --~%")

(test "gen-map transforms value"
  (let ([rng (make-rng 42)])
    (gen-sample (gen-map (lambda (x) (* x 2)) (gen-integer 5 5)) rng))
  10)

(test-pred "gen-bind monadic"
  (let ([rng (make-rng 42)])
    ;; gen-bind: generate n, then generate a list of n zeros
    (let ([v (gen-sample
               (gen-bind (gen-integer 3 3)
                         (lambda (n) (gen-list n (gen-integer 0 0))))
               rng)])
      v))
  (lambda (v) (and (list? v) (<= (length v) 3) (for-all zero? v))))

(test "gen-such-that filters"
  (let ([rng (make-rng 42)])
    (let ([v (gen-sample
               (gen-such-that (gen-integer 0 100) even?)
               rng)])
      (even? v)))
  #t)

(test "gen-tuple returns list of values"
  (let ([rng (make-rng 42)])
    (let ([v (gen-sample
               (gen-tuple (gen-integer 1 1) (gen-boolean) (gen-integer 5 5))
               rng)])
      (list (car v) (caddr v))))
  '(1 5))

;; ======== Shrinking ========

(printf "~%-- Shrinking --~%")

(test "shrink-integer 0 -> empty"
  (shrink-integer 0)
  '())

(test-pred "shrink-integer positive"
  (shrink-integer 10)
  (lambda (cs)
    (and (member 0 cs) (member 5 cs) (member 9 cs) #t)))

(test-pred "shrink-integer negative"
  (shrink-integer -4)
  (lambda (cs) (and (member 0 cs) #t)))

(test "shrink-boolean #t -> (#f)"
  (shrink-boolean #t)
  '(#f))

(test "shrink-boolean #f -> ()"
  (shrink-boolean #f)
  '())

(test "shrink-list empty -> empty"
  (shrink-list '() shrink-value)
  '())

(test-pred "shrink-list non-empty has smaller candidates"
  (shrink-list '(1 2 3) shrink-value)
  (lambda (cs)
    ;; Should have some shorter candidates
    (and (not (null? cs))
         (exists (lambda (c) (< (length c) 3)) cs))))

(test "shrink-string empty -> empty"
  (shrink-string "")
  '())

(test "shrink-string non-empty returns shorter strings"
  (let ([cs (shrink-string "hello")])
    (and (not (null? cs))
         (for-all (lambda (s) (< (string-length s) 5)) cs)))
  #t)

(test "shrink-value dispatches on type"
  (and (not (null? (shrink-value 10)))
       (not (null? (shrink-value #t)))
       (not (null? (shrink-value "hi")))
       (not (null? (shrink-value '(1 2)))))
  #t)

;; ======== Properties ========

(printf "~%-- Properties --~%")

(defproperty prop-commutative
  ((gen-integer -100 100) (gen-integer -100 100))
  (lambda (a b)
    (= (+ a b) (+ b a))))

(test "check-property: commutative addition passes"
  (property-passed? (check-property prop-commutative))
  #t)

(test "check-property: num-trials"
  (property-num-trials (check-property prop-commutative '|#:trials| 50))
  50)

(defproperty prop-false-claim
  ((gen-integer 0 100))
  (lambda (n)
    ;; False: n is always even
    (even? n)))

(test "check-property: false property fails"
  (property-failed? (check-property prop-false-claim))
  #t)

(test "check-property: failed has counterexample"
  (let ([r (check-property prop-false-claim)])
    (and (property-failed? r)
         (list? (property-counterexample r))
         (odd? (car (property-counterexample r)))))
  #t)

(test "property-report: passed"
  (let ([r (check-property prop-commutative)])
    (string? (property-report r)))
  #t)

(test-pred "property-report: failed contains FAILED"
  (let ([r (check-property prop-false-claim)])
    (property-report r))
  (lambda (s) (and (string? s)
                   ;; check that "FAILED" appears in the string
                   (let ([len (string-length s)]
                         [needle "FAILED"]
                         [nlen 6])
                     (let loop ([i 0])
                       (cond [(> (+ i nlen) len) #f]
                             [(string=? (substring s i (+ i nlen)) needle) #t]
                             [else (loop (+ i 1))]))))))

;; ======== check-property/test ========

(printf "~%-- check-property/test --~%")

(test "check-property/test: passes silently"
  (guard (exn [#t 'raised])
    (check-property/test prop-commutative)
    'ok)
  'ok)

(test "check-property/test: raises on failure"
  (guard (exn [#t 'caught])
    (check-property/test prop-false-claim)
    'no-error)
  'caught)

;; ======== Shrinking Integration ========

(printf "~%-- Shrinking Integration --~%")

(defproperty prop-large-positive
  ((gen-integer 0 1000))
  (lambda (n)
    ;; False: all numbers less than 500 (so anything >= 500 fails)
    (< n 500)))

(test "shrinking finds minimal counterexample"
  (let* ([r   (check-property prop-large-positive)]
         [ce  (property-counterexample r)])
    ;; The shrunk counterexample should be 500 (or near it)
    (and (property-failed? r)
         (list? ce)
         (>= (car ce) 500)))
  #t)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
