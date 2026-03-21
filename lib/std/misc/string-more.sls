#!chezscheme
;;; (std misc string-more) — Extended string operations
;;;
;;; String operations from Gerbil's :std/misc/string not yet in jerboa.

(library (std misc string-more)
  (export string-prefix? string-suffix?
          string-contains? string-trim-both
          string-join string-repeat
          string-index string-index-right
          string-pad-left string-pad-right
          string-count string-take-while string-drop-while)

  (import (chezscheme))

  ;; Test if str starts with prefix
  (define (string-prefix? prefix str)
    (let ([plen (string-length prefix)]
          [slen (string-length str)])
      (and (<= plen slen)
           (string=? (substring str 0 plen) prefix))))

  ;; Test if str ends with suffix
  (define (string-suffix? suffix str)
    (let ([suflen (string-length suffix)]
          [slen (string-length str)])
      (and (<= suflen slen)
           (string=? (substring str (- slen suflen) slen) suffix))))

  ;; Test if str contains substring
  (define (string-contains? needle str)
    (let ([nlen (string-length needle)]
          [slen (string-length str)])
      (if (> nlen slen)
          #f
          (let loop ([i 0])
            (cond
              [(> (+ i nlen) slen) #f]
              [(string=? (substring str i (+ i nlen)) needle) #t]
              [else (loop (+ i 1))])))))

  ;; Trim whitespace from both ends
  (define (string-trim-both str)
    (let* ([len (string-length str)]
           [start (let loop ([i 0])
                    (if (and (< i len) (char-whitespace? (string-ref str i)))
                        (loop (+ i 1))
                        i))]
           [end (let loop ([i len])
                  (if (and (> i start) (char-whitespace? (string-ref str (- i 1))))
                      (loop (- i 1))
                      i))])
      (substring str start end)))

  ;; Join list of strings with separator
  (define (string-join strs sep)
    (if (null? strs)
        ""
        (let loop ([rest (cdr strs)] [acc (car strs)])
          (if (null? rest)
              acc
              (loop (cdr rest)
                    (string-append acc sep (car rest)))))))

  ;; Repeat string N times
  (define (string-repeat str n)
    (let loop ([i 0] [acc ""])
      (if (>= i n)
          acc
          (loop (+ i 1) (string-append acc str)))))

  ;; Find first index where char/pred matches (or #f)
  (define (string-index str pred/char)
    (let ([pred (if (char? pred/char)
                    (lambda (c) (char=? c pred/char))
                    pred/char)]
          [len (string-length str)])
      (let loop ([i 0])
        (cond
          [(= i len) #f]
          [(pred (string-ref str i)) i]
          [else (loop (+ i 1))]))))

  ;; Find last index where char/pred matches (or #f)
  (define (string-index-right str pred/char)
    (let ([pred (if (char? pred/char)
                    (lambda (c) (char=? c pred/char))
                    pred/char)]
          [len (string-length str)])
      (let loop ([i (- len 1)])
        (cond
          [(< i 0) #f]
          [(pred (string-ref str i)) i]
          [else (loop (- i 1))]))))

  ;; Pad string on the left to width
  (define string-pad-left
    (case-lambda
      [(str width) (string-pad-left str width #\space)]
      [(str width char)
       (let ([len (string-length str)])
         (if (>= len width)
             str
             (string-append (make-string (- width len) char) str)))]))

  ;; Pad string on the right to width
  (define string-pad-right
    (case-lambda
      [(str width) (string-pad-right str width #\space)]
      [(str width char)
       (let ([len (string-length str)])
         (if (>= len width)
             str
             (string-append str (make-string (- width len) char))))]))

  ;; Count occurrences of char/pred in string
  (define (string-count str pred/char)
    (let ([pred (if (char? pred/char)
                    (lambda (c) (char=? c pred/char))
                    pred/char)]
          [len (string-length str)])
      (let loop ([i 0] [n 0])
        (if (= i len) n
            (loop (+ i 1) (if (pred (string-ref str i)) (+ n 1) n))))))

  ;; Take characters while predicate is true
  (define (string-take-while str pred)
    (let ([len (string-length str)])
      (let loop ([i 0])
        (if (and (< i len) (pred (string-ref str i)))
            (loop (+ i 1))
            (substring str 0 i)))))

  ;; Drop characters while predicate is true
  (define (string-drop-while str pred)
    (let ([len (string-length str)])
      (let loop ([i 0])
        (if (and (< i len) (pred (string-ref str i)))
            (loop (+ i 1))
            (substring str i len)))))

) ;; end library
