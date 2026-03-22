#!chezscheme
;;; :std/srfi/144 -- Flonums (SRFI-144)
;;; Flonum-specific arithmetic and constants.

(library (std srfi srfi-144)
  (export
    fl+ fl- fl* fl/ flabs flsqrt
    flexp fllog flsin flcos fltan
    flasin flacos flatan
    flfloor flceiling flround fltruncate
    fl= fl< fl> fl<= fl>=
    flzero? flpositive? flnegative? flinteger?
    flnan? flinfinite? flfinite?
    flmin flmax
    fl-e fl-pi fl-epsilon fl-greatest fl-least)

  (import (chezscheme))

  ;; ---- Constants ----
  (define fl-e 2.718281828459045)
  (define fl-pi 3.141592653589793)
  ;; Machine epsilon: smallest x such that (fl+ 1.0 x) != 1.0
  (define fl-epsilon 2.220446049250313e-16) ;; DBL_EPSILON
  (define fl-greatest 1.7976931348623157e+308) ;; DBL_MAX
  (define fl-least 5e-324) ;; DBL_TRUE_MIN (smallest positive subnormal)

  ;; ---- Type checking ----
  (define-syntax check-flonum
    (syntax-rules ()
      [(_ who x)
       (unless (flonum? x)
         (error who "not a flonum" x))]
      [(_ who x y)
       (begin
         (unless (flonum? x)
           (error who "not a flonum" x))
         (unless (flonum? y)
           (error who "not a flonum" y)))]))

  ;; ---- Arithmetic ----
  (define (fl+ a b)
    (check-flonum 'fl+ a b)
    (+ a b))

  (define (fl- a . rest)
    (check-flonum 'fl- a)
    (if (null? rest)
      (- a)
      (begin
        (check-flonum 'fl- (car rest))
        (- a (car rest)))))

  (define (fl* a b)
    (check-flonum 'fl* a b)
    (* a b))

  (define (fl/ a . rest)
    (check-flonum 'fl/ a)
    (if (null? rest)
      (/ 1.0 a)
      (begin
        (check-flonum 'fl/ (car rest))
        (/ a (car rest)))))

  (define (flabs x)
    (check-flonum 'flabs x)
    (abs x))

  (define (flsqrt x)
    (check-flonum 'flsqrt x)
    (sqrt x))

  (define (flexp x)
    (check-flonum 'flexp x)
    (exp x))

  (define (fllog x . rest)
    (check-flonum 'fllog x)
    (if (null? rest)
      (log x)
      (begin
        (check-flonum 'fllog (car rest))
        (/ (log x) (log (car rest))))))

  (define (flsin x) (check-flonum 'flsin x) (sin x))
  (define (flcos x) (check-flonum 'flcos x) (cos x))
  (define (fltan x) (check-flonum 'fltan x) (tan x))
  (define (flasin x) (check-flonum 'flasin x) (asin x))
  (define (flacos x) (check-flonum 'flacos x) (acos x))

  (define (flatan x . rest)
    (check-flonum 'flatan x)
    (if (null? rest)
      (atan x)
      (begin
        (check-flonum 'flatan (car rest))
        (atan x (car rest)))))

  (define (flfloor x) (check-flonum 'flfloor x) (floor x))
  (define (flceiling x) (check-flonum 'flceiling x) (ceiling x))
  (define (flround x) (check-flonum 'flround x) (round x))
  (define (fltruncate x) (check-flonum 'fltruncate x) (truncate x))

  ;; ---- Comparisons ----
  (define (fl= a b) (check-flonum 'fl= a b) (= a b))
  (define (fl< a b) (check-flonum 'fl< a b) (< a b))
  (define (fl> a b) (check-flonum 'fl> a b) (> a b))
  (define (fl<= a b) (check-flonum 'fl<= a b) (<= a b))
  (define (fl>= a b) (check-flonum 'fl>= a b) (>= a b))

  ;; ---- Predicates ----
  (define (flzero? x) (check-flonum 'flzero? x) (zero? x))
  (define (flpositive? x) (check-flonum 'flpositive? x) (positive? x))
  (define (flnegative? x) (check-flonum 'flnegative? x) (negative? x))
  (define (flinteger? x) (check-flonum 'flinteger? x) (integer? x))
  (define (flnan? x) (check-flonum 'flnan? x) (nan? x))
  (define (flinfinite? x) (check-flonum 'flinfinite? x) (infinite? x))
  (define (flfinite? x) (check-flonum 'flfinite? x) (finite? x))

  ;; ---- Min/Max ----
  (define (flmin a b) (check-flonum 'flmin a b) (min a b))
  (define (flmax a b) (check-flonum 'flmax a b) (max a b))

) ;; end library
