#!chezscheme
;;; Test: variant — exhaustive variant matching

(import (std variant))

(define pass 0)
(define fail 0)

(define-syntax chk
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([r expr] [e expected])
       (if (equal? r e)
         (set! pass (+ pass 1))
         (begin
           (set! fail (+ fail 1))
           (display "FAIL: ") (write 'expr)
           (display " => ") (write r)
           (display " expected ") (write e) (newline))))]))

;; --- Define a simple variant type ---
(defvariant shape
  (circle radius)
  (rect width height)
  (triangle base height))

;; --- Test 1: Constructors work ---
(let ([c (shape/circle 5)])
  (chk (shape/circle? c) => #t)
  (chk (shape/rect? c) => #f)
  (chk (shape? c) => #t))

(let ([r (shape/rect 10 20)])
  (chk (shape/rect? r) => #t)
  (chk (shape/circle? r) => #f)
  (chk (shape? r) => #t))

(let ([t (shape/triangle 6 8)])
  (chk (shape/triangle? t) => #t)
  (chk (shape? t) => #t))

;; --- Test 2: Accessors work ---
(let ([c (shape/circle 7)])
  (chk (shape/circle-radius c) => 7))

(let ([r (shape/rect 3 4)])
  (chk (shape/rect-width r) => 3)
  (chk (shape/rect-height r) => 4))

(let ([t (shape/triangle 5 12)])
  (chk (shape/triangle-base t) => 5)
  (chk (shape/triangle-height t) => 12))

;; --- Test 3: variant-tags returns the tag list ---
(chk (variant-tags 'shape) => '(circle rect triangle))

;; --- Test 4: shape/variants binding ---
(chk shape/variants => '(circle rect triangle))

;; --- Test 5: match-variant with exhaustive coverage ---
(define (area s)
  (match-variant shape s
    [(circle r) (* 3.14159 r r)]
    [(rect w h) (* w h)]
    [(triangle b h) (* 0.5 b h)]))

(chk (area (shape/circle 10)) => 314.159)
(chk (area (shape/rect 3 4)) => 12)
(chk (area (shape/triangle 6 8)) => 24.0)

;; --- Test 6: match-variant with wildcard (suppresses exhaustiveness) ---
(define (describe s)
  (match-variant shape s
    [(circle r) "a circle"]
    [_ "not a circle"]))

(chk (describe (shape/circle 1)) => "a circle")
(chk (describe (shape/rect 2 3)) => "not a circle")
(chk (describe (shape/triangle 4 5)) => "not a circle")

;; --- Test 7: match-variant with else (also suppresses exhaustiveness) ---
(define (is-rect? s)
  (match-variant shape s
    [(rect w h) #t]
    [else #f]))

(chk (is-rect? (shape/rect 1 2)) => #t)
(chk (is-rect? (shape/circle 1)) => #f)

;; --- Test 8: Multiple variant types ---
(defvariant result
  (ok value)
  (err message code))

(let ([success (result/ok 42)])
  (chk (result/ok? success) => #t)
  (chk (result/ok-value success) => 42))

(let ([failure (result/err "oops" 500)])
  (chk (result/err? failure) => #t)
  (chk (result/err-message failure) => "oops")
  (chk (result/err-code failure) => 500))

(define (unwrap-result r)
  (match-variant result r
    [(ok v) v]
    [(err msg code) (error 'unwrap msg code)]))

(chk (unwrap-result (result/ok 100)) => 100)

;; --- Test 9: Zero-field variants ---
(defvariant option
  (some value)
  (none))

(let ([n (option/none)])
  (chk (option/none? n) => #t)
  (chk (option? n) => #t))

(let ([s (option/some 42)])
  (chk (option/some? s) => #t)
  (chk (option/some-value s) => 42))

(define (option-or opt default)
  (match-variant option opt
    [(some v) v]
    [(none) default]))

(chk (option-or (option/some 10) 0) => 10)
(chk (option-or (option/none) 0) => 0)

;; --- Test 10: Nested variant matching ---
(define (map-option f opt)
  (match-variant option opt
    [(some v) (option/some (f v))]
    [(none) (option/none)]))

(let ([doubled (map-option (lambda (x) (* x 2)) (option/some 21))])
  (chk (option/some? doubled) => #t)
  (chk (option/some-value doubled) => 42))

(let ([mapped-none (map-option (lambda (x) (* x 2)) (option/none))])
  (chk (option/none? mapped-none) => #t))

;; --- Test 11: variant? runtime check ---
(chk (variant? 'shape (shape/circle 1)) => #t)
(chk (variant? 'shape (shape/rect 2 3)) => #t)
(chk (variant? 'option (option/some 1)) => #t)
(chk (variant? 'option (option/none)) => #t)

;; --- Summary ---
(newline)
(display "variant: ")
(display pass) (display " passed, ")
(display fail) (display " failed") (newline)
(when (> fail 0) (exit 1))
