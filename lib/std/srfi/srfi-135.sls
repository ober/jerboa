#!chezscheme
;;; :std/srfi/135 -- Immutable Texts (SRFI-135)
;;; Immutable text objects backed by Scheme strings.
;;; Wrapped in a record type to distinguish from mutable strings.

(library (std srfi srfi-135)
  (export
    text text? text-length text-ref
    text-tabulate text->string string->text
    text->list list->text
    text-append text-concatenate
    text-map text-for-each text-fold text-fold-right
    text-filter text-remove
    text-take text-drop text-count
    text-index text-contains subtext
    textual? textual-null?)

  (import (chezscheme))

  (define-record-type text-rec
    (fields (immutable str))
    (sealed #t))

  (define (text? x) (text-rec? x))

  (define (text . chars)
    (make-text-rec (list->string chars)))

  (define (text-length t)
    (string-length (text-rec-str t)))

  (define (text-ref t i)
    (string-ref (text-rec-str t) i))

  (define (text-tabulate proc len)
    (let ([s (make-string len)])
      (do ([i 0 (+ i 1)])
          ((= i len) (make-text-rec s))
        (string-set! s i (proc i)))))

  (define (text->string t)
    (string-copy (text-rec-str t)))

  (define (string->text s)
    (make-text-rec (string-copy s)))

  (define (text->list t)
    (string->list (text-rec-str t)))

  (define (list->text lst)
    (make-text-rec (list->string lst)))

  (define (text-append . texts)
    (make-text-rec
      (apply string-append (map text-rec-str texts))))

  (define (text-concatenate texts)
    (apply text-append texts))

  (define (text-map f t)
    (let* ([s (text-rec-str t)]
           [len (string-length s)]
           [result (make-string len)])
      (do ([i 0 (+ i 1)])
          ((= i len) (make-text-rec result))
        (string-set! result i (f (string-ref s i))))))

  (define (text-for-each f t)
    (let ([s (text-rec-str t)]
          [len (text-length t)])
      (do ([i 0 (+ i 1)])
          ((= i len))
        (f (string-ref s i)))))

  (define (text-fold f seed t)
    (let ([s (text-rec-str t)]
          [len (text-length t)])
      (let loop ([i 0] [acc seed])
        (if (= i len) acc
            (loop (+ i 1) (f (string-ref s i) acc))))))

  (define (text-fold-right f seed t)
    (let ([s (text-rec-str t)])
      (let loop ([i (- (string-length s) 1)] [acc seed])
        (if (< i 0) acc
            (loop (- i 1) (f (string-ref s i) acc))))))

  (define (text-filter pred t)
    (let ([chars (filter pred (text->list t))])
      (make-text-rec (list->string chars))))

  (define (text-remove pred t)
    (text-filter (lambda (c) (not (pred c))) t))

  (define (text-take t n)
    (make-text-rec (substring (text-rec-str t) 0 n)))

  (define (text-drop t n)
    (let ([s (text-rec-str t)])
      (make-text-rec (substring s n (string-length s)))))

  (define (text-count pred t)
    (text-fold (lambda (c n) (if (pred c) (+ n 1) n)) 0 t))

  (define (text-index pred t . maybe-start)
    (let ([s (text-rec-str t)]
          [start (if (null? maybe-start) 0 (car maybe-start))]
          [len (text-length t)])
      (let loop ([i start])
        (cond
          [(= i len) #f]
          [(pred (string-ref s i)) i]
          [else (loop (+ i 1))]))))

  (define (text-contains t pattern)
    (let ([s (text-rec-str t)]
          [p (text-rec-str pattern)]
          [slen (text-length t)]
          [plen (text-length pattern)])
      (if (> plen slen) #f
          (let loop ([i 0])
            (cond
              [(> (+ i plen) slen) #f]
              [(string=? (substring s i (+ i plen)) p) i]
              [else (loop (+ i 1))])))))

  (define (subtext t start end)
    (make-text-rec (substring (text-rec-str t) start end)))

  (define (textual? x)
    (or (text? x) (string? x) (char? x)))

  (define (textual-null? x)
    (cond
      [(text? x) (zero? (text-length x))]
      [(string? x) (zero? (string-length x))]
      [else #f]))
)
