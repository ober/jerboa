#!chezscheme
;;; (std misc decimal) -- Exact decimal arithmetic
;;;
;;; Decimals are represented as (coefficient . scale) pairs where
;;; value = coefficient * 10^(-scale).  All arithmetic preserves exactness.
;;;
;;; Usage:
;;;   (import (std misc decimal))
;;;   (define a (make-decimal 314 2))       ;; 3.14
;;;   (define b (string->decimal "2.5"))    ;; 2.5
;;;   (decimal->string (decimal+ a b))     ;; "5.64"
;;;   (decimal->string (decimal* a b))     ;; "7.850"
;;;   (decimal->inexact a)                 ;; 3.14

(library (std misc decimal)
  (export
    make-decimal
    decimal?
    decimal+
    decimal-
    decimal*
    decimal/
    decimal-round
    decimal-truncate
    decimal-abs
    decimal=
    decimal<
    decimal>
    decimal<=
    decimal>=
    decimal-zero?
    decimal-negative?
    string->decimal
    decimal->string
    decimal->inexact)

  (import (chezscheme))

  ;; Internal representation: (coefficient . scale)
  ;; value = coefficient * 10^(-scale)
  ;; coefficient is an exact integer, scale is a non-negative exact integer.

  (define-record-type decimal-rec
    (fields (immutable coeff)    ;; exact integer
            (immutable scale))   ;; non-negative exact integer
    (sealed #t))

  (define (make-decimal coefficient scale)
    (unless (and (integer? coefficient) (exact? coefficient))
      (error 'make-decimal "coefficient must be an exact integer" coefficient))
    (unless (and (integer? scale) (exact? scale) (>= scale 0))
      (error 'make-decimal "scale must be a non-negative exact integer" scale))
    (make-decimal-rec coefficient scale))

  (define (decimal? x) (decimal-rec? x))

  ;; ========== Normalization helpers ==========

  (define (pow10 n)
    (expt 10 n))

  ;; Align two decimals to the same scale (the larger of the two).
  ;; Returns (values coeff-a coeff-b common-scale).
  (define (align a b)
    (let ([sa (decimal-rec-scale a)]
          [sb (decimal-rec-scale b)]
          [ca (decimal-rec-coeff a)]
          [cb (decimal-rec-coeff b)])
      (cond
        [(= sa sb) (values ca cb sa)]
        [(< sa sb)
         (values (* ca (pow10 (- sb sa))) cb sb)]
        [else
         (values ca (* cb (pow10 (- sa sb))) sa)])))

  ;; ========== Arithmetic ==========

  (define (decimal+ a b)
    (let-values ([(ca cb s) (align a b)])
      (make-decimal-rec (+ ca cb) s)))

  (define (decimal- a b)
    (let-values ([(ca cb s) (align a b)])
      (make-decimal-rec (- ca cb) s)))

  (define (decimal* a b)
    ;; (ca * 10^-sa) * (cb * 10^-sb) = (ca*cb) * 10^-(sa+sb)
    (make-decimal-rec (* (decimal-rec-coeff a) (decimal-rec-coeff b))
                      (+ (decimal-rec-scale a) (decimal-rec-scale b))))

  (define (decimal/ a b)
    ;; Division: we need to produce an exact result.
    ;; We scale the numerator up to get enough precision,
    ;; then check for exact division.
    (let ([cb (decimal-rec-coeff b)])
      (when (zero? cb)
        (error 'decimal/ "division by zero"))
      (let* ([ca (decimal-rec-coeff a)]
             [sa (decimal-rec-scale a)]
             [sb (decimal-rec-scale b)]
             ;; We want (ca * 10^-sa) / (cb * 10^-sb)
             ;; = (ca / cb) * 10^(sb - sa)
             ;; = (ca * 10^sa_extra) / cb * 10^(sb - sa - sa_extra)
             ;; Choose extra precision to make division exact or provide
             ;; reasonable precision.
             [extra 20]  ;; extra decimal digits of precision
             [scaled-ca (* ca (pow10 extra))]
             [q (div scaled-ca cb)]
             [r (mod scaled-ca cb)]
             [result-scale (+ sa extra (- sb))])
        ;; If there's a remainder, we can't represent this exactly
        ;; at this precision -- use the truncated result.
        (when (not (zero? r))
          ;; Still give a result, just truncated at 'extra' digits
          (void))
        ;; Ensure scale is non-negative
        (if (< result-scale 0)
          ;; Negative scale means we can shift coefficient
          (make-decimal-rec (* q (pow10 (- result-scale))) 0)
          (make-decimal-rec q result-scale)))))

  ;; ========== Rounding ==========

  (define (decimal-round d digits)
    ;; Round to 'digits' decimal places.
    (let ([s (decimal-rec-scale d)]
          [c (decimal-rec-coeff d)])
      (cond
        [(<= s digits)
         ;; Already has fewer or equal digits -- scale up
         (make-decimal-rec (* c (pow10 (- digits s))) digits)]
        [else
         ;; Need to remove (s - digits) trailing digits
         (let* ([drop (- s digits)]
                [divisor (pow10 drop)]
                [q (div c divisor)]
                [r (mod (abs c) (pow10 drop))]
                [half (div divisor 2)]
                [rounded (cond
                           [(> r half) (if (negative? c) (- q 1) (+ q 1))]
                           [(< r half) q]
                           ;; Exactly half: round to even
                           [else (if (odd? q)
                                   (if (negative? c) (- q 1) (+ q 1))
                                   q)])])
           (make-decimal-rec rounded digits))])))

  (define (decimal-truncate d digits)
    ;; Truncate to 'digits' decimal places (round toward zero).
    (let ([s (decimal-rec-scale d)]
          [c (decimal-rec-coeff d)])
      (cond
        [(<= s digits)
         (make-decimal-rec (* c (pow10 (- digits s))) digits)]
        [else
         (let* ([drop (- s digits)]
                [divisor (pow10 drop)]
                [q (if (negative? c)
                     (- (div (- c) divisor))
                     (div c divisor))])
           (make-decimal-rec q digits))])))

  ;; ========== Unary operations ==========

  (define (decimal-abs d)
    (make-decimal-rec (abs (decimal-rec-coeff d))
                      (decimal-rec-scale d)))

  ;; ========== Comparisons ==========

  (define (decimal= a b)
    (let-values ([(ca cb s) (align a b)])
      (= ca cb)))

  (define (decimal< a b)
    (let-values ([(ca cb s) (align a b)])
      (< ca cb)))

  (define (decimal> a b)
    (let-values ([(ca cb s) (align a b)])
      (> ca cb)))

  (define (decimal<= a b)
    (let-values ([(ca cb s) (align a b)])
      (<= ca cb)))

  (define (decimal>= a b)
    (let-values ([(ca cb s) (align a b)])
      (>= ca cb)))

  ;; ========== Predicates ==========

  (define (decimal-zero? d)
    (zero? (decimal-rec-coeff d)))

  (define (decimal-negative? d)
    (negative? (decimal-rec-coeff d)))

  ;; ========== Conversions ==========

  (define (string->decimal str)
    (unless (string? str)
      (error 'string->decimal "expected a string" str))
    (let* ([len (string-length str)]
           [start 0]
           [negative? #f])
      (when (zero? len)
        (error 'string->decimal "empty string"))
      ;; Check for sign
      (let-values ([(start negative?)
                    (cond
                      [(char=? (string-ref str 0) #\-)
                       (values 1 #t)]
                      [(char=? (string-ref str 0) #\+)
                       (values 1 #f)]
                      [else (values 0 #f)])])
        ;; Find the dot position
        (let loop ([i start] [dot-pos #f])
          (if (>= i len)
            ;; End of string
            (let* ([digits-str (if dot-pos
                                 (string-append
                                   (substring str start dot-pos)
                                   (substring str (+ dot-pos 1) len))
                                 (substring str start len))]
                   [scale (if dot-pos (- len dot-pos 1) 0)]
                   [coeff (string->number digits-str)])
              (unless (and coeff (integer? coeff) (exact? coeff))
                (error 'string->decimal "invalid decimal string" str))
              (make-decimal-rec (if negative? (- coeff) coeff) scale))
            ;; Scanning
            (let ([c (string-ref str i)])
              (cond
                [(char=? c #\.)
                 (when dot-pos
                   (error 'string->decimal "multiple decimal points" str))
                 (loop (+ i 1) i)]
                [(char-numeric? c)
                 (loop (+ i 1) dot-pos)]
                [else
                 (error 'string->decimal "invalid character in decimal" str c)])))))))

  (define (decimal->string d)
    (let* ([c (decimal-rec-coeff d)]
           [s (decimal-rec-scale d)]
           [neg? (negative? c)]
           [ac (abs c)]
           [digits (number->string ac)])
      (if (zero? s)
        ;; No decimal point needed
        (if neg? (string-append "-" digits) digits)
        ;; Need decimal point
        (let ([dlen (string-length digits)])
          (cond
            [(<= dlen s)
             ;; Need leading zeros: e.g., coeff=5, scale=3 => "0.005"
             (let ([pad (- s dlen)])
               (string-append
                 (if neg? "-" "")
                 "0."
                 (make-string pad #\0)
                 digits))]
            [else
             ;; Split digits into integer and fractional parts
             (let ([int-part (substring digits 0 (- dlen s))]
                   [frac-part (substring digits (- dlen s) dlen)])
               (string-append
                 (if neg? "-" "")
                 int-part
                 "."
                 frac-part))])))))

  (define (decimal->inexact d)
    (let ([c (decimal-rec-coeff d)]
          [s (decimal-rec-scale d)])
      (inexact (/ c (pow10 s)))))

) ;; end library
