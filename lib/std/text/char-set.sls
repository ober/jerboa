#!chezscheme
;;; (std text char-set) — Character set operations
;;;
;;; Provides character set type and operations for text processing,
;;; parsing, and validation.

(library (std text char-set)
  (export make-char-set char-set char-set?
          char-set-contains? char-set-size
          char-set-union char-set-intersection char-set-complement
          char-set-difference
          char-set->list string->char-set char-set->string
          char-set:letter char-set:digit char-set:whitespace
          char-set:upper char-set:lower char-set:punctuation
          char-set:hex-digit char-set:alphanumeric)

  (import (chezscheme))

  ;; Internal: char-set is a sorted list of characters (simple but correct)
  (define-record-type char-set-type
    (fields chars)  ;; sorted vector of chars
    (protocol
      (lambda (new)
        (lambda (chars)
          (new (list->vector
                 (list-sort char<? (delete-duplicates chars char=?))))))))

  ;; Remove duplicate characters
  (define (delete-duplicates lst eq)
    (let loop ([rest lst] [acc '()])
      (cond
        [(null? rest) (reverse acc)]
        [(memp (lambda (x) (eq x (car rest))) acc)
         (loop (cdr rest) acc)]
        [else (loop (cdr rest) (cons (car rest) acc))])))

  ;; Constructor aliases
  (define (make-char-set chars) (make-char-set-type chars))
  (define (char-set . chars) (make-char-set chars))
  (define (char-set? x) (char-set-type? x))

  ;; Membership test
  (define (char-set-contains? cs ch)
    (let ([v (char-set-type-chars cs)])
      (let loop ([lo 0] [hi (- (vector-length v) 1)])
        (if (> lo hi) #f
            (let* ([mid (quotient (+ lo hi) 2)]
                   [c (vector-ref v mid)])
              (cond
                [(char=? ch c) #t]
                [(char<? ch c) (loop lo (- mid 1))]
                [else (loop (+ mid 1) hi)]))))))

  (define (char-set-size cs)
    (vector-length (char-set-type-chars cs)))

  ;; Set operations
  (define (char-set-union . sets)
    (make-char-set
      (apply append (map (lambda (cs) (vector->list (char-set-type-chars cs))) sets))))

  (define (char-set-intersection cs1 cs2)
    (make-char-set
      (filter (lambda (ch) (char-set-contains? cs2 ch))
              (vector->list (char-set-type-chars cs1)))))

  (define (char-set-complement cs)
    (let ([v (char-set-type-chars cs)])
      (make-char-set
        (let loop ([i 0] [acc '()])
          (if (> i 127) acc  ;; ASCII range
              (let ([ch (integer->char i)])
                (if (char-set-contains? cs ch)
                    (loop (+ i 1) acc)
                    (loop (+ i 1) (cons ch acc)))))))))

  (define (char-set-difference cs1 cs2)
    (make-char-set
      (filter (lambda (ch) (not (char-set-contains? cs2 ch)))
              (vector->list (char-set-type-chars cs1)))))

  ;; Conversion
  (define (char-set->list cs)
    (vector->list (char-set-type-chars cs)))

  (define (string->char-set str)
    (make-char-set (string->list str)))

  (define (char-set->string cs)
    (list->string (vector->list (char-set-type-chars cs))))

  ;; Predefined sets
  (define char-set:letter
    (make-char-set
      (append (let loop ([i (char->integer #\a)] [acc '()])
                (if (> i (char->integer #\z)) acc
                    (loop (+ i 1) (cons (integer->char i) acc))))
              (let loop ([i (char->integer #\A)] [acc '()])
                (if (> i (char->integer #\Z)) acc
                    (loop (+ i 1) (cons (integer->char i) acc)))))))

  (define char-set:digit
    (make-char-set
      (let loop ([i (char->integer #\0)] [acc '()])
        (if (> i (char->integer #\9)) acc
            (loop (+ i 1) (cons (integer->char i) acc))))))

  (define char-set:whitespace
    (make-char-set '(#\space #\tab #\newline #\return #\page #\vtab)))

  (define char-set:upper
    (make-char-set
      (let loop ([i (char->integer #\A)] [acc '()])
        (if (> i (char->integer #\Z)) acc
            (loop (+ i 1) (cons (integer->char i) acc))))))

  (define char-set:lower
    (make-char-set
      (let loop ([i (char->integer #\a)] [acc '()])
        (if (> i (char->integer #\z)) acc
            (loop (+ i 1) (cons (integer->char i) acc))))))

  (define char-set:punctuation
    (string->char-set "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"))

  (define char-set:hex-digit
    (string->char-set "0123456789abcdefABCDEF"))

  (define char-set:alphanumeric
    (char-set-union char-set:letter char-set:digit))

) ;; end library
