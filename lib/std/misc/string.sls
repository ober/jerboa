#!chezscheme
;;; :std/misc/string -- String utilities
;;;
;;; NOTE: This module exports several symbols that overlap with (std srfi srfi-13):
;;;   string-join, string-trim, string-prefix?, string-suffix?, string-contains, string-index
;;; If you need both modules, use (only (std misc string) string-split string-empty?)
;;; to import only the unique symbols from this module.
;;;
;;; Semantic differences from srfi-13:
;;;   - string-trim: trims BOTH sides (srfi-13 trims leading only; use string-trim-both there)
;;;   - string-index: takes a char (srfi-13 takes a predicate or char)

(library (std misc string)
  (export string-split string-join string-trim
          string-prefix? string-suffix?
          string-contains string-index
          string-empty? string-trim-eol
          ;; Regex convenience
          string-match? string-find string-find-all)
  (import (chezscheme)
          (std pregexp))

  (define string-split
    (case-lambda
      ((str) (string-split str #\space))
      ((str sep)
       (cond
         [(char? sep) (string-split-char str sep)]
         [(string? sep) (string-split-string str sep)]
         [else (error 'string-split "separator must be char or string" sep)]))))

  (define (string-split-char str ch)
    (let ([len (string-length str)])
      (let loop ([i 0] [start 0] [acc '()])
        (cond
          [(= i len)
           (reverse (cons (substring str start len) acc))]
          [(char=? (string-ref str i) ch)
           (loop (+ i 1) (+ i 1) (cons (substring str start i) acc))]
          [else (loop (+ i 1) start acc)]))))

  (define (string-split-string str sep)
    (let ([slen (string-length sep)]
          [len (string-length str)])
      (if (zero? slen)
        (map string (string->list str))
        (let loop ([i 0] [start 0] [acc '()])
          (cond
            [(> (+ i slen) len)
             (reverse (cons (substring str start len) acc))]
            [(string=? (substring str i (+ i slen)) sep)
             (loop (+ i slen) (+ i slen)
                   (cons (substring str start i) acc))]
            [else (loop (+ i 1) start acc)])))))

  (define string-join
    (case-lambda
      ((lst) (string-join lst " "))
      ((lst sep)
       (if (null? lst) ""
         (let loop ([rest (cdr lst)] [acc (car lst)])
           (if (null? rest) acc
             (loop (cdr rest) (string-append acc sep (car rest)))))))))

  (define (string-trim str)
    (let* ([len (string-length str)]
           [start (let loop ([i 0])
                    (if (and (< i len) (char-whitespace? (string-ref str i)))
                      (loop (+ i 1)) i))]
           [end (let loop ([i (- len 1)])
                  (if (and (>= i start) (char-whitespace? (string-ref str i)))
                    (loop (- i 1)) (+ i 1)))])
      (substring str start end)))

  (define (string-prefix? prefix str)
    (and (<= (string-length prefix) (string-length str))
         (string=? prefix (substring str 0 (string-length prefix)))))

  (define (string-suffix? suffix str)
    (let ([slen (string-length suffix)]
          [len (string-length str)])
      (and (<= slen len)
           (string=? suffix (substring str (- len slen) len)))))

  (define (string-contains str sub)
    (let ([slen (string-length sub)]
          [len (string-length str)])
      (let loop ([i 0])
        (cond
          [(> (+ i slen) len) #f]
          [(string=? (substring str i (+ i slen)) sub) i]
          [else (loop (+ i 1))]))))

  (define string-index
    (case-lambda
      [(str ch)
       (let ([len (string-length str)])
         (let loop ([i 0])
           (cond
             [(= i len) #f]
             [(char=? (string-ref str i) ch) i]
             [else (loop (+ i 1))])))]
      [(str ch start)
       (let ([len (string-length str)])
         (let loop ([i start])
           (cond
             [(= i len) #f]
             [(char=? (string-ref str i) ch) i]
             [else (loop (+ i 1))])))]))

  (define (string-empty? str)
    (zero? (string-length str)))

  (define (string-trim-eol str)
    ;; Trim trailing CR, LF, or CRLF from string.
    ;; Tries CRLF first (longer suffix), then LF, then CR.
    (let* ([len (string-length str)]
           [try-suffix
            (lambda (suffix)
              (let ([slen (string-length suffix)])
                (and (<= slen len)
                     (string=? suffix (substring str (- len slen) len))
                     (substring str 0 (- len slen)))))])
      (or (try-suffix "\r\n")
          (try-suffix "\n")
          (try-suffix "\r")
          str)))

  ;; --- Regex convenience wrappers ---

  ;; string-match?: does the string match the pattern?
  ;; (string-match? "^[0-9]+$" "12345") => #t
  (define (string-match? pattern str)
    (and (pregexp-match pattern str) #t))

  ;; string-find: return first match or #f
  ;; (string-find "[0-9]+" "abc 123 def") => "123"
  ;; With groups: returns list of match + groups
  (define (string-find pattern str)
    (let ([m (pregexp-match pattern str)])
      (and m
           (if (null? (cdr m))
             (car m)        ;; no groups: return match string
             m))))          ;; groups: return full match list

  ;; string-find-all: return all non-overlapping matches
  ;; (string-find-all "[0-9]+" "a1b22c333") => ("1" "22" "333")
  (define (string-find-all pattern str)
    (let ([rx (pregexp pattern)])
      (let loop ([s str] [acc '()])
        (let ([m (pregexp-match-positions rx s)])
          (if (not m)
            (reverse acc)
            (let* ([start (caar m)]
                   [end (cdar m)]
                   [matched (substring s start end)]
                   [rest (substring s (max end (+ start 1)) (string-length s))])
              (loop rest (cons matched acc))))))))

  ) ;; end library
