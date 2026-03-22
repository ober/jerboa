#!chezscheme
;;; :std/srfi/14 -- SRFI-14 Character Sets
;;; Character sets represented as 256-bit bytevector bitmaps (code points 0-255).

(library (std srfi srfi-14)
  (export
    ;; Predicates and constructors
    char-set? char-set char-set-copy
    list->char-set string->char-set char-set-filter
    ucs-range->char-set
    ;; Comparison
    char-set= char-set<= char-set-hash
    ;; Iteration / cursors
    char-set-cursor char-set-ref char-set-cursor-next end-of-char-set?
    char-set-fold char-set-for-each char-set-map
    ;; Queries
    char-set-size char-set-count
    char-set->list char-set->string
    char-set-contains? char-set-every char-set-any
    ;; Set algebra
    char-set-adjoin char-set-delete
    char-set-complement char-set-union char-set-intersection
    char-set-difference char-set-xor
    ;; Standard char sets
    char-set:lower-case char-set:upper-case char-set:title-case
    char-set:letter char-set:digit char-set:letter+digit
    char-set:graphic char-set:printing char-set:whitespace
    char-set:iso-control char-set:punctuation char-set:symbol
    char-set:hex-digit char-set:blank char-set:ascii
    char-set:empty char-set:full)
  (import (chezscheme))

  ;; Internal: bitmap is a 32-byte bytevector, one bit per code point 0-255.
  (define-record-type cs
    (fields (immutable bv))
    (nongenerative srfi-14-char-set))

  (define (char-set? x) (cs? x))

  (define (%make-empty) (make-cs (make-bytevector 32 0)))

  (define (%bv-set! bv cp)
    (let ([byte (fxsrl cp 3)]
          [bit  (fxand cp 7)])
      (bytevector-u8-set! bv byte
        (fxlogor (bytevector-u8-ref bv byte) (fxsll 1 bit)))))

  (define (%bv-clear! bv cp)
    (let ([byte (fxsrl cp 3)]
          [bit  (fxand cp 7)])
      (bytevector-u8-set! bv byte
        (fxlogand (bytevector-u8-ref bv byte) (fxlognot (fxsll 1 bit))))))

  (define (%bv-ref bv cp)
    (let ([byte (fxsrl cp 3)]
          [bit  (fxand cp 7)])
      (fxbit-set? (bytevector-u8-ref bv byte) bit)))

  (define (%bv-copy bv)
    (let ([new (make-bytevector 32)])
      (bytevector-copy! bv 0 new 0 32)
      new))

  ;; Constructors
  (define (char-set . chars)
    (let ([s (%make-empty)])
      (for-each (lambda (c)
                  (let ([cp (char->integer c)])
                    (when (fx< cp 256) (%bv-set! (cs-bv s) cp))))
                chars)
      s))

  (define (char-set-copy cs)
    (make-cs (%bv-copy (cs-bv cs))))

  (define (list->char-set chars . rest)
    (let ([base (if (pair? rest) (char-set-copy (car rest)) (%make-empty))])
      (for-each (lambda (c)
                  (let ([cp (char->integer c)])
                    (when (fx< cp 256) (%bv-set! (cs-bv base) cp))))
                chars)
      base))

  (define (string->char-set str . rest)
    (list->char-set (string->list str) (if (pair? rest) (car rest) (%make-empty))))

  (define (char-set-filter pred cs . rest)
    (let ([base (if (pair? rest) (char-set-copy (car rest)) (%make-empty))])
      (char-set-for-each
        (lambda (c) (when (pred c) (%bv-set! (cs-bv base) (char->integer c))))
        cs)
      base))

  (define (ucs-range->char-set lo hi . rest)
    (let ([base (if (pair? rest) (char-set-copy (car rest)) (%make-empty))])
      (do ([i lo (fx+ i 1)])
          ((fx>= i (fxmin hi 256)) base)
        (%bv-set! (cs-bv base) i))))

  ;; Comparison
  (define (char-set= . sets)
    (or (null? sets) (null? (cdr sets))
        (let ([bv0 (cs-bv (car sets))])
          (let loop ([rest (cdr sets)])
            (or (null? rest)
                (and (bytevector=? bv0 (cs-bv (car rest)))
                     (loop (cdr rest))))))))

  (define (char-set<= . sets)
    (or (null? sets) (null? (cdr sets))
        (let loop ([prev (car sets)] [rest (cdr sets)])
          (or (null? rest)
              (let ([a (cs-bv prev)] [b (cs-bv (car rest))])
                (and (let bloop ([i 0])
                       (or (fx= i 32)
                           (and (fx= 0 (fxlogand (bytevector-u8-ref a i)
                                                  (fxlognot (bytevector-u8-ref b i))))
                                (bloop (fx+ i 1)))))
                     (loop (car rest) (cdr rest))))))))

  (define (char-set-hash cs . rest)
    (let ([bound (if (pair? rest) (car rest) (greatest-fixnum))])
      (let loop ([i 0] [h 0])
        (if (fx= i 32)
            (fxmod (fxand h (greatest-fixnum)) bound)
            (loop (fx+ i 1)
                  (fx+ (fxsll h 1) (bytevector-u8-ref (cs-bv cs) i)))))))

  ;; Cursors — cursor is an integer code point, 256 = end
  (define (%next-set-bit bv from)
    (let loop ([i from])
      (cond [(fx>= i 256) 256]
            [(%bv-ref bv i) i]
            [else (loop (fx+ i 1))])))

  (define (char-set-cursor cs) (%next-set-bit (cs-bv cs) 0))
  (define (end-of-char-set? cur) (fx>= cur 256))
  (define (char-set-ref cs cur) (integer->char cur))
  (define (char-set-cursor-next cs cur) (%next-set-bit (cs-bv cs) (fx+ cur 1)))

  ;; Iteration
  (define (char-set-fold kons knil cs)
    (let ([bv (cs-bv cs)])
      (let loop ([i 0] [acc knil])
        (if (fx= i 256) acc
            (loop (fx+ i 1)
                  (if (%bv-ref bv i) (kons (integer->char i) acc) acc))))))

  (define (char-set-for-each proc cs)
    (let ([bv (cs-bv cs)])
      (do ([i 0 (fx+ i 1)]) ((fx= i 256))
        (when (%bv-ref bv i) (proc (integer->char i))))))

  (define (char-set-map proc cs)
    (let ([result (%make-empty)])
      (char-set-for-each
        (lambda (c)
          (let ([cp (char->integer (proc c))])
            (when (fx< cp 256) (%bv-set! (cs-bv result) cp))))
        cs)
      result))

  ;; Queries
  (define (char-set-size cs)
    (char-set-fold (lambda (c n) (fx+ n 1)) 0 cs))

  (define (char-set-count pred cs)
    (char-set-fold (lambda (c n) (if (pred c) (fx+ n 1) n)) 0 cs))

  (define (char-set->list cs)
    (char-set-fold cons '() cs))

  (define (char-set->string cs)
    (list->string (char-set->list cs)))

  (define (char-set-contains? cs ch)
    (let ([cp (char->integer ch)])
      (and (fx< cp 256) (%bv-ref (cs-bv cs) cp))))

  (define (char-set-every pred cs)
    (let ([bv (cs-bv cs)])
      (let loop ([i 0])
        (cond [(fx= i 256) #t]
              [(and (%bv-ref bv i) (not (pred (integer->char i)))) #f]
              [else (loop (fx+ i 1))]))))

  (define (char-set-any pred cs)
    (let ([bv (cs-bv cs)])
      (let loop ([i 0])
        (cond [(fx= i 256) #f]
              [(and (%bv-ref bv i) (pred (integer->char i))) => values]
              [else (loop (fx+ i 1))]))))

  ;; Set algebra
  (define (char-set-adjoin cs . chars)
    (let ([new (char-set-copy cs)])
      (for-each (lambda (c)
                  (let ([cp (char->integer c)])
                    (when (fx< cp 256) (%bv-set! (cs-bv new) cp))))
                chars)
      new))

  (define (char-set-delete cs . chars)
    (let ([new (char-set-copy cs)])
      (for-each (lambda (c)
                  (let ([cp (char->integer c)])
                    (when (fx< cp 256) (%bv-clear! (cs-bv new) cp))))
                chars)
      new))

  (define (%bv-op! op dst src)
    (do ([i 0 (fx+ i 1)]) ((fx= i 32))
      (bytevector-u8-set! dst i
        (fxlogand 255 (op (bytevector-u8-ref dst i) (bytevector-u8-ref src i))))))

  (define (char-set-complement cs)
    (let ([new (make-bytevector 32)])
      (do ([i 0 (fx+ i 1)]) ((fx= i 32) (make-cs new))
        (bytevector-u8-set! new i (fxlogand 255 (fxlognot (bytevector-u8-ref (cs-bv cs) i)))))))

  (define (%binary-op op)
    (lambda sets
      (if (null? sets) (%make-empty)
          (let ([result (char-set-copy (car sets))])
            (for-each (lambda (s) (%bv-op! op (cs-bv result) (cs-bv s)))
                      (cdr sets))
            result))))

  (define char-set-union        (%binary-op fxlogor))
  (define char-set-intersection (%binary-op fxlogand))
  (define char-set-xor          (%binary-op fxlogxor))

  (define (char-set-difference cs . rest)
    (let ([result (char-set-copy cs)])
      (for-each (lambda (s) (%bv-op! (lambda (a b) (fxlogand a (fxlognot b)))
                                     (cs-bv result) (cs-bv s)))
                rest)
      result))

  ;; Standard character sets
  (define (%cs-from-pred pred)
    (let ([s (%make-empty)])
      (do ([i 0 (fx+ i 1)]) ((fx= i 256) s)
        (when (pred (integer->char i)) (%bv-set! (cs-bv s) i)))))

  (define char-set:lower-case (%cs-from-pred char-lower-case?))
  (define char-set:upper-case (%cs-from-pred char-upper-case?))
  (define char-set:title-case (%make-empty))  ; no title-case in Latin-1
  (define char-set:letter     (%cs-from-pred char-alphabetic?))
  (define char-set:digit      (%cs-from-pred char-numeric?))
  (define char-set:letter+digit (char-set-union char-set:letter char-set:digit))
  (define char-set:whitespace (%cs-from-pred char-whitespace?))
  (define char-set:iso-control
    (let ([s (%make-empty)])
      (do ([i 0 (fx+ i 1)]) ((fx> i 31)) (%bv-set! (cs-bv s) i))
      (%bv-set! (cs-bv s) 127)
      (do ([i 128 (fx+ i 1)]) ((fx> i 159) s) (%bv-set! (cs-bv s) i))))
  (define char-set:punctuation
    (%cs-from-pred (lambda (c)
      (let ([cp (char->integer c)])
        (or (and (fx>= cp 33) (fx<= cp 47))
            (and (fx>= cp 58) (fx<= cp 64))
            (and (fx>= cp 91) (fx<= cp 96))
            (and (fx>= cp 123) (fx<= cp 126))
            (and (fx>= cp 161) (fx<= cp 191))
            (fx= cp 215) (fx= cp 247))))))
  (define char-set:symbol
    (%cs-from-pred (lambda (c)
      (let ([cp (char->integer c)])
        (or (fx= cp 36) (fx= cp 43)
            (and (fx>= cp 60) (fx<= cp 62))
            (fx= cp 94) (fx= cp 96) (fx= cp 124) (fx= cp 126)
            (fx= cp 162) (fx= cp 163) (fx= cp 164) (fx= cp 165)
            (fx= cp 166) (fx= cp 168) (fx= cp 169) (fx= cp 172)
            (fx= cp 174) (fx= cp 175) (fx= cp 176) (fx= cp 177)
            (fx= cp 180) (fx= cp 182) (fx= cp 184)
            (fx= cp 215) (fx= cp 247))))))
  (define char-set:graphic
    (char-set-union char-set:letter char-set:digit char-set:punctuation char-set:symbol))
  (define char-set:printing
    (char-set-union char-set:graphic char-set:whitespace))
  (define char-set:hex-digit
    (string->char-set "0123456789abcdefABCDEF"))
  (define char-set:blank
    (list->char-set (list #\space #\tab)))
  (define char-set:ascii (ucs-range->char-set 0 128))
  (define char-set:empty (%make-empty))
  (define char-set:full  (ucs-range->char-set 0 256))
)
