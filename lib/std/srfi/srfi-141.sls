#!chezscheme
;;; :std/srfi/141 -- Integer Division (SRFI-141)
;;; Chez Scheme provides most of these operations natively.

(library (std srfi srfi-141)
  (export
    floor/
    floor-quotient floor-remainder
    truncate/
    truncate-quotient truncate-remainder
    ceiling/
    ceiling-quotient ceiling-remainder
    round/
    round-quotient round-remainder
    euclidean/
    euclidean-quotient euclidean-remainder
    balanced/
    balanced-quotient balanced-remainder)

  (import (chezscheme))

  ;; Floor division (like Python's //)
  (define (floor/ n d)
    (values (floor-quotient n d) (floor-remainder n d)))
  (define (floor-quotient n d)
    (floor (/ n d)))
  (define (floor-remainder n d)
    (- n (* d (floor-quotient n d))))

  ;; Truncate division (like C's /)
  (define (truncate/ n d)
    (values (truncate-quotient n d) (truncate-remainder n d)))
  (define (truncate-quotient n d)
    (truncate (/ n d)))
  (define (truncate-remainder n d)
    (- n (* d (truncate-quotient n d))))

  ;; Ceiling division
  (define (ceiling/ n d)
    (values (ceiling-quotient n d) (ceiling-remainder n d)))
  (define (ceiling-quotient n d)
    (ceiling (/ n d)))
  (define (ceiling-remainder n d)
    (- n (* d (ceiling-quotient n d))))

  ;; Round division
  (define (round/ n d)
    (values (round-quotient n d) (round-remainder n d)))
  (define (round-quotient n d)
    (round (/ n d)))
  (define (round-remainder n d)
    (- n (* d (round-quotient n d))))

  ;; Euclidean division (remainder always non-negative)
  (define (euclidean/ n d)
    (values (euclidean-quotient n d) (euclidean-remainder n d)))
  (define (euclidean-quotient n d)
    (let ([q (floor-quotient n d)]
          [r (floor-remainder n d)])
      (if (negative? r)
        (if (positive? d) (+ q 1) (- q 1))
        q)))
  (define (euclidean-remainder n d)
    (let ([r (floor-remainder n d)])
      (if (negative? r) (+ r (abs d)) r)))

  ;; Balanced division (remainder in [-|d/2|, |d/2|))
  (define (balanced/ n d)
    (values (balanced-quotient n d) (balanced-remainder n d)))
  (define (balanced-quotient n d)
    (round-quotient n d))
  (define (balanced-remainder n d)
    (round-remainder n d))

) ;; end library
