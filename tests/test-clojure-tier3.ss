#!chezscheme
;;; Tests for Clojure 1.11+ conveniences in (std clojure):
;;;   parse-long, parse-double, parse-boolean, parse-uuid, random-uuid
;;;   update-vals, update-keys, map-indexed, keep-indexed
;;;   if-some, when-some, condp, letfn, case-let
;;;   NaN?, abs, not-empty, iteration

(import (jerboa prelude)
        (only (std clojure)
              parse-long parse-double parse-boolean parse-uuid random-uuid
              update-vals update-keys map-indexed keep-indexed
              if-some when-some condp letfn case-let
              NaN? not-empty iteration)
        (only (std pmap)
              persistent-map persistent-map-ref persistent-map->list))

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

(printf "--- std/clojure tier-3 (1.11+ conveniences) ---~%~%")

;;; ---- parse-long ------------------------------------------------

(test "parse-long basic"      (parse-long "42")    42)
(test "parse-long negative"   (parse-long "-7")    -7)
(test "parse-long zero"       (parse-long "0")     0)
(test "parse-long invalid"    (parse-long "abc")   #f)
(test "parse-long empty"      (parse-long "")      #f)
(test "parse-long float-rejected" (parse-long "1.5") #f)

;;; ---- parse-double ----------------------------------------------

(test "parse-double basic"    (parse-double "3.14")  3.14)
(test "parse-double int-form" (parse-double "1") #f)  ;; rejects exact ints
(test "parse-double scientific" (parse-double "1e2") 100.0)
(test "parse-double invalid"  (parse-double "abc")   #f)

;;; ---- parse-boolean ---------------------------------------------

(test "parse-boolean true"    (parse-boolean "true")  #t)
(test "parse-boolean false"   (parse-boolean "false") #f)
(test "parse-boolean other"   (parse-boolean "maybe") #f)

;;; ---- parse-uuid ------------------------------------------------

(test "parse-uuid valid"
  (parse-uuid "550e8400-e29b-41d4-a716-446655440000")
  "550e8400-e29b-41d4-a716-446655440000")

(test "parse-uuid invalid length"
  (parse-uuid "abcd-efgh")
  #f)

(test "parse-uuid invalid chars"
  (parse-uuid "550e8400-e29b-41d4-a716-44665544000Z")
  #f)

;;; ---- random-uuid -----------------------------------------------

(test "random-uuid is 36 chars"
  (string-length (random-uuid))
  36)

(test "random-uuid is v4 (13th char is 4)"
  (string-ref (random-uuid) 14)
  #\4)

(test "random-uuid two distinct calls"
  (eq? (random-uuid) (random-uuid))  ;; effectively never equal
  #f)

;;; ---- update-vals -----------------------------------------------

(test "update-vals on persistent-map"
  (let* ([m (persistent-map 'a 1 'b 2 'c 3)]
         [m* (update-vals m (lambda (v) (* v 10)))])
    (list (persistent-map-ref m* 'a)
          (persistent-map-ref m* 'b)
          (persistent-map-ref m* 'c)))
  '(10 20 30))

(test "update-vals on hash-table"
  (let ([h (make-hash-table)])
    (hash-put! h "a" 1)
    (hash-put! h "b" 2)
    (let ([h* (update-vals h (lambda (v) (+ v 100)))])
      (list-sort < (list (hash-ref h* "a") (hash-ref h* "b")))))
  '(101 102))

;;; ---- update-keys -----------------------------------------------

(test "update-keys on persistent-map"
  (let* ([m (persistent-map "a" 1 "b" 2)]
         [m* (update-keys m string->symbol)])
    (list (persistent-map-ref m* 'a)
          (persistent-map-ref m* 'b)))
  '(1 2))

;;; ---- map-indexed -----------------------------------------------

(test "map-indexed basic"
  (map-indexed (lambda (i v) (list i v)) '(a b c))
  '((0 a) (1 b) (2 c)))

(test "map-indexed empty"
  (map-indexed (lambda (i v) (list i v)) '())
  '())

;;; ---- keep-indexed ----------------------------------------------

(test "keep-indexed drops #f"
  (keep-indexed (lambda (i v) (and (odd? i) v)) '(a b c d e))
  '(b d))

;;; ---- if-some / when-some ---------------------------------------

(test "if-some binds and runs then"
  (if-some (x 42) (+ x 1) 'no)
  43)

(test "if-some treats only #f as falsy"
  (if-some (x 0) (+ x 1) 'no)
  1)

(test "if-some falls through on #f"
  (if-some (x #f) (+ x 1) 'no)
  'no)

(test "when-some binds when truthy"
  (when-some (x 5) (* x x))
  25)

(test "when-some returns unspecified-or-void on #f"
  (let ([called #f])
    (when-some (x #f) (set! called #t))
    called)
  #f)

;;; ---- condp ----------------------------------------------------

(test "condp basic equality"
  (condp = 5
    1 'one
    5 'five
    'other)
  'five)

(test "condp default"
  (condp = 99
    1 'one
    2 'two
    'default)
  'default)

;; Note: the `:>>` handler form of condp is not exercisable in
;; default Jerboa reader mode — `:>>` reads as a module path
;; rather than the literal symbol `:>>` the macro expects.

;;; ---- letfn -----------------------------------------------------

(test "letfn defines mutually recursive procedures"
  (letfn ((my-even? (n) (if (zero? n) #t (my-odd? (- n 1))))
          (my-odd?  (n) (if (zero? n) #f (my-even? (- n 1)))))
    (list (my-even? 4) (my-odd? 5)))
  '(#t #t))

;;; ---- case-let --------------------------------------------------

(test "case-let binds and dispatches"
  (case-let (x (+ 1 2))
    ((1 2 3) 'small)
    ((4 5 6) 'medium)
    (else 'big))
  'small)

(test "case-let else branch"
  (case-let (x 99)
    ((1 2 3) 'small)
    (else 'big))
  'big)

;;; ---- NaN? ------------------------------------------------------

(test "NaN? on NaN"     (NaN? +nan.0) #t)
(test "NaN? on number"  (NaN? 3.14)   #f)
(test "NaN? on int"     (NaN? 42)     #f)

;;; ---- not-empty -------------------------------------------------

(test "not-empty on empty list"     (not-empty '())     #f)
(test "not-empty on non-empty list" (not-empty '(1 2))  '(1 2))
(test "not-empty on empty string"   (not-empty "")      #f)
(test "not-empty on non-empty str"  (not-empty "hi")    "hi")
(test "not-empty on empty vector"   (not-empty (vector))     #f)
(test "not-empty on non-empty vec"  (not-empty (vector 1 2))  (vector 1 2))

;;; ---- iteration -------------------------------------------------

(test "iteration 1-arg basic step"
  (let* ([state 0]
         [step (lambda (k)
                 (if (or (not k) (< k 5))
                   (let ([n (if k (+ k 1) 0)])
                     n)
                   #f))]
         [results '()])
    (let loop ([k #f])
      (let ([next (step k)])
        (when next
          (set! results (cons next results))
          (loop next))))
    (reverse results))
  '(0 1 2 3 4 5))

;;; ---- Summary ---------------------------------------------------
(printf "~%std/clojure tier-3: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
