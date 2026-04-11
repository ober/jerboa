#!chezscheme
;;; Tests for (std misc meta) — Clojure-style metadata wrappers.

(import (except (jerboa prelude) hash-map)
        (std clojure))

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

(printf "--- std/misc/meta ---~%~%")

;;; ---- Basic with-meta / meta / strip-meta ------------------------

(test "meta returns #f for unwrapped value"
  (meta 42)
  #f)

(test "meta returns #f for string"
  (meta "hello")
  #f)

(test "meta returns #f for list"
  (meta '(1 2 3))
  #f)

(test "strip-meta passthrough for unwrapped value"
  (strip-meta 42)
  42)

(test "strip-meta passthrough for list"
  (strip-meta '(1 2 3))
  '(1 2 3))

(let ([m (with-meta '(1 2 3) '((source . "input")))])
  (test "with-meta wraps and meta retrieves"
    (meta m)
    '((source . "input")))

  (test "strip-meta unwraps to original value"
    (strip-meta m)
    '(1 2 3))

  (test "meta-wrapped? true for wrapped value"
    (meta-wrapped? m)
    #t))

(test "meta-wrapped? false for plain value"
  (meta-wrapped? '(1 2 3))
  #f)

(test "meta-wrapped? false for numbers"
  (meta-wrapped? 42)
  #f)

;;; ---- Re-wrapping is single-layer --------------------------------

(let* ([m1 (with-meta '(1 2 3) '((a . 1)))]
       [m2 (with-meta m1      '((b . 2)))])
  (test "re-wrapping replaces, not nests — meta returns new"
    (meta m2)
    '((b . 2)))

  (test "re-wrapping replaces, not nests — strip-meta single step"
    (strip-meta m2)
    '(1 2 3)))

;;; ---- vary-meta --------------------------------------------------

(let* ([m1 (with-meta '(x y z) '((line . 1)))]
       [m2 (vary-meta m1 (lambda (m k v) (cons (cons k v) m)) 'col 5)])
  (test "vary-meta applies f to current meta with extra args"
    (meta m2)
    '((col . 5) (line . 1)))

  (test "vary-meta preserves value"
    (strip-meta m2)
    '(x y z)))

(test "vary-meta on unwrapped value passes #f to f"
  (let ([m (vary-meta 42 (lambda (old) (or old '((fresh . #t)))))])
    (meta m))
  '((fresh . #t)))

;;; ---- =? strips metadata on both sides ---------------------------

(test "=? treats wrapped and raw as equal (both sides)"
  (=? (with-meta '(1 2 3) '((k . 1))) '(1 2 3))
  #t)

(test "=? treats raw and wrapped as equal (flipped)"
  (=? '(1 2 3) (with-meta '(1 2 3) '((k . 1))))
  #t)

(test "=? treats two wrapped values with different meta as equal"
  (=? (with-meta '(1 2 3) '((a . 1)))
      (with-meta '(1 2 3) '((b . 2))))
  #t)

(test "=? distinguishes different values even when both wrapped"
  (=? (with-meta '(1 2 3) '((a . 1)))
      (with-meta '(1 2 4) '((a . 1))))
  #f)

;;; ---- Works on persistent maps and sets --------------------------

(let ([pm (with-meta (hash-map "x" 1 "y" 2) '((tag . mymap)))])
  (test "with-meta works on persistent-map"
    (meta pm)
    '((tag . mymap)))

  (test "=? treats wrapped pmap as equal to unwrapped"
    (=? pm (hash-map "x" 1 "y" 2))
    #t))

(let ([ps (with-meta (hash-set 1 2 3) '((origin . seed)))])
  (test "with-meta works on persistent-set"
    (meta ps)
    '((origin . seed)))

  (test "=? treats wrapped pset as equal to unwrapped"
    (=? ps (hash-set 1 2 3))
    #t))

;;; ---- Multiple wraps with vary-meta chain ------------------------

(let* ([v  (with-meta "hello" '((line . 1)))]
       [v2 (vary-meta v (lambda (m) (cons '(col . 10) m)))]
       [v3 (vary-meta v2 (lambda (m) (cons '(file . "a.ss") m)))])
  (test "vary-meta chain accumulates metadata"
    (meta v3)
    '((file . "a.ss") (col . 10) (line . 1)))

  (test "value remains unchanged through vary-meta chain"
    (strip-meta v3)
    "hello"))

;;; ---- Summary ---------------------------------------------------
(printf "~%std/misc/meta: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
