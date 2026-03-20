#!chezscheme
;;; :std/misc/number -- Number utilities

(library (std misc number)
  (export natural?
          positive-integer?
          negative?
          clamp
          divmod
          number->padded-string
          number->human-readable
          integer-length*
          fixnum->flonum)
  (import (chezscheme))

  (define (natural? x)
    (and (integer? x) (exact? x) (>= x 0)))

  (define (positive-integer? x)
    (and (integer? x) (exact? x) (> x 0)))

  (define (clamp x lo hi)
    (cond [(< x lo) lo]
          [(> x hi) hi]
          [else x]))

  (define (divmod n d)
    (values (quotient n d) (remainder n d)))

  (define number->padded-string
    (case-lambda
      ((n width) (number->padded-string n width 10))
      ((n width base)
       (let* ((s (string-downcase (number->string (abs n) base)))
              (len (string-length s))
              (prefix (if (negative? n) "-" ""))
              (pad-width (- width (string-length prefix) len)))
         (if (<= pad-width 0)
           (string-append prefix s)
           (string-append prefix (make-string pad-width #\0) s))))))

  (define (number->human-readable n)
    (let loop ([v (exact->inexact (abs n))]
               [suffixes '("" "K" "M" "G" "T" "P")])
      (cond
        [(or (null? (cdr suffixes)) (< v 1024.0))
         (let ([rounded (/ (round (* v 10.0)) 10.0)])
           (string-append
             (if (= rounded (floor rounded))
               (number->string (inexact->exact (floor rounded)))
               (number->string rounded))
             (car suffixes)))]
        [else
         (loop (/ v 1024.0) (cdr suffixes))])))

  (define (integer-length* n)
    (if (zero? n)
      0
      (bitwise-length (abs n))))

  ;; negative? and fixnum->flonum are re-exported from (chezscheme)

  ) ;; end library
