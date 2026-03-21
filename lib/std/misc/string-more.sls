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
          string-count string-take-while string-drop-while
          ;; better2 #24 additions
          string-split string-replace string-filter
          string-reverse string-empty?
          string-trim-left string-trim-right)

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

  ;; ========== better2 #24 additions ==========

  ;; Split string by delimiter (string or char)
  (define string-split
    (case-lambda
      [(str) (string-split str #\space)]
      [(str delim)
       (if (char? delim)
           ;; Split by character
           (let ([len (string-length str)])
             (let loop ([i 0] [start 0] [acc '()])
               (cond
                 [(= i len)
                  (reverse (cons (substring str start i) acc))]
                 [(char=? (string-ref str i) delim)
                  (loop (+ i 1) (+ i 1)
                        (cons (substring str start i) acc))]
                 [else (loop (+ i 1) start acc)])))
           ;; Split by string delimiter
           (let ([slen (string-length str)]
                 [dlen (string-length delim)])
             (if (= dlen 0) (list str)
                 (let loop ([i 0] [start 0] [acc '()])
                   (cond
                     [(> (+ i dlen) slen)
                      (reverse (cons (substring str start slen) acc))]
                     [(string=? (substring str i (+ i dlen)) delim)
                      (loop (+ i dlen) (+ i dlen)
                            (cons (substring str start i) acc))]
                     [else (loop (+ i 1) start acc)])))))]))

  ;; Replace all occurrences of old with new in string
  (define (string-replace str old new)
    (let ([slen (string-length str)]
          [olen (string-length old)])
      (if (= olen 0) str
          (let loop ([i 0] [acc '()])
            (cond
              [(> (+ i olen) slen)
               (apply string-append
                      (reverse (cons (substring str i slen) acc)))]
              [(string=? (substring str i (+ i olen)) old)
               (loop (+ i olen) (cons new acc))]
              [else
               (loop (+ i 1)
                     (cons (string (string-ref str i)) acc))])))))

  ;; Filter characters by predicate
  (define (string-filter pred str)
    (list->string
      (filter pred (string->list str))))

  ;; Reverse a string
  (define (string-reverse str)
    (list->string (reverse (string->list str))))

  ;; Check if string is empty
  (define (string-empty? str)
    (= (string-length str) 0))

  ;; Trim whitespace from left
  (define (string-trim-left str)
    (let ([len (string-length str)])
      (let loop ([i 0])
        (if (and (< i len) (char-whitespace? (string-ref str i)))
            (loop (+ i 1))
            (substring str i len)))))

  ;; Trim whitespace from right
  (define (string-trim-right str)
    (let ([len (string-length str)])
      (let loop ([i len])
        (if (and (> i 0) (char-whitespace? (string-ref str (- i 1))))
            (loop (- i 1))
            (substring str 0 i)))))

) ;; end library
