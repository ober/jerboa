#!chezscheme
;;; :std/misc/string -- String utilities

(library (std misc string)
  (export string-split string-join string-trim
          string-prefix? string-suffix?
          string-contains string-index
          string-empty?)
  (import (chezscheme))

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

  (define (string-index str ch)
    (let ([len (string-length str)])
      (let loop ([i 0])
        (cond
          [(= i len) #f]
          [(char=? (string-ref str i) ch) i]
          [else (loop (+ i 1))]))))

  (define (string-empty? str)
    (zero? (string-length str)))

  ) ;; end library
