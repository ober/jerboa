#!chezscheme
;;; :std/srfi/13 -- String operations (SRFI-13 subset)

(library (std srfi srfi-13)
  (export
    string-index
    string-index-right
    string-contains
    string-prefix?
    string-suffix?
    string-trim
    string-trim-right
    string-trim-both
    string-pad
    string-pad-right
    string-join
    string-concatenate
    string-take
    string-take-right
    string-drop
    string-drop-right
    string-count
    string-filter
    string-delete
    string-reverse
    string-null?
    string-every
    string-any
    string-fold
    string-fold-right
    string-for-each-index
    string-map!
    string-tokenize
    string-replace)

  (import (chezscheme))

  (define (string-index str pred . rest)
    (let* ((start (if (pair? rest) (car rest) 0))
           (end (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) (string-length str)))
           (pred (if (char? pred) (lambda (c) (char=? c pred)) pred)))
      (let lp ((i start))
        (cond
          ((>= i end) #f)
          ((pred (string-ref str i)) i)
          (else (lp (+ i 1)))))))

  (define (string-index-right str pred . rest)
    (let* ((start (if (pair? rest) (car rest) 0))
           (end (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) (string-length str)))
           (pred (if (char? pred) (lambda (c) (char=? c pred)) pred)))
      (let lp ((i (- end 1)))
        (cond
          ((< i start) #f)
          ((pred (string-ref str i)) i)
          (else (lp (- i 1)))))))

  (define (string-contains s1 s2 . rest)
    (let* ((start1 (if (pair? rest) (car rest) 0))
           (end1 (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) (string-length s1)))
           (len2 (string-length s2)))
      (if (= len2 0)
        start1
        (let lp ((i start1))
          (cond
            ((> (+ i len2) end1) #f)
            ((string=? (substring s1 i (+ i len2)) s2) i)
            (else (lp (+ i 1))))))))

  (define (string-prefix? prefix str . rest)
    (let* ((start (if (pair? rest) (car rest) 0))
           (plen (string-length prefix))
           (slen (string-length str)))
      (and (<= (+ start plen) slen)
           (string=? prefix (substring str start (+ start plen))))))

  (define (string-suffix? suffix str . rest)
    (let* ((slen (string-length str))
           (end (if (pair? rest) (car rest) slen))
           (suflen (string-length suffix)))
      (and (<= suflen end)
           (string=? suffix (substring str (- end suflen) end)))))

  (define (string-trim str . rest)
    (let ((pred (if (pair? rest) (car rest) char-whitespace?)))
      (let ((len (string-length str)))
        (let lp ((i 0))
          (cond
            ((>= i len) "")
            ((pred (string-ref str i)) (lp (+ i 1)))
            (else (substring str i len)))))))

  (define (string-trim-right str . rest)
    (let ((pred (if (pair? rest) (car rest) char-whitespace?)))
      (let lp ((i (- (string-length str) 1)))
        (cond
          ((< i 0) "")
          ((pred (string-ref str i)) (lp (- i 1)))
          (else (substring str 0 (+ i 1)))))))

  (define (string-trim-both str . rest)
    (let ((pred (if (pair? rest) (car rest) char-whitespace?)))
      (string-trim (string-trim-right str pred) pred)))

  (define (string-pad str len . rest)
    (let ((ch (if (pair? rest) (car rest) #\space))
          (slen (string-length str)))
      (if (>= slen len)
        (substring str (- slen len) slen)
        (string-append (make-string (- len slen) ch) str))))

  (define (string-pad-right str len . rest)
    (let ((ch (if (pair? rest) (car rest) #\space))
          (slen (string-length str)))
      (if (>= slen len)
        (substring str 0 len)
        (string-append str (make-string (- len slen) ch)))))

  ;; Chez already has string-upcase, string-downcase, string-titlecase

  (define (string-join lst . rest)
    (let ((sep (if (pair? rest) (car rest) " ")))
      (cond
        ((null? lst) "")
        ((null? (cdr lst)) (car lst))
        (else
         (let lp ((rest (cdr lst)) (acc (car lst)))
           (if (null? rest)
             acc
             (lp (cdr rest) (string-append acc sep (car rest)))))))))

  (define (string-concatenate lst)
    (apply string-append lst))

  (define (string-take str n)
    (substring str 0 (min n (string-length str))))

  (define (string-take-right str n)
    (let ((len (string-length str)))
      (substring str (max 0 (- len n)) len)))

  (define (string-drop str n)
    (substring str (min n (string-length str)) (string-length str)))

  (define (string-drop-right str n)
    (let ((len (string-length str)))
      (substring str 0 (max 0 (- len n)))))

  (define (string-count str pred . rest)
    (let* ((start (if (pair? rest) (car rest) 0))
           (end (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) (string-length str)))
           (pred (if (char? pred) (lambda (c) (char=? c pred)) pred)))
      (let lp ((i start) (count 0))
        (if (>= i end) count
          (lp (+ i 1) (if (pred (string-ref str i)) (+ count 1) count))))))

  (define (string-filter pred str . rest)
    (let* ((start (if (pair? rest) (car rest) 0))
           (end (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) (string-length str)))
           (pred (if (char? pred) (lambda (c) (char=? c pred)) pred)))
      (let lp ((i start) (chars '()))
        (if (>= i end)
          (list->string (reverse chars))
          (lp (+ i 1)
              (if (pred (string-ref str i))
                (cons (string-ref str i) chars)
                chars))))))

  (define (string-delete pred str . rest)
    (let* ((start (if (pair? rest) (car rest) 0))
           (end (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) (string-length str)))
           (pred (if (char? pred) (lambda (c) (char=? c pred)) pred)))
      (apply string-filter (lambda (c) (not (pred c))) str rest)))

  (define (string-reverse str . rest)
    (let* ((start (if (pair? rest) (car rest) 0))
           (end (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) (string-length str))))
      (list->string (reverse (string->list (substring str start end))))))

  (define (string-null? str) (= (string-length str) 0))

  (define (string-every pred str . rest)
    (let* ((start (if (pair? rest) (car rest) 0))
           (end (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) (string-length str)))
           (pred (if (char? pred) (lambda (c) (char=? c pred)) pred)))
      (let lp ((i start))
        (cond
          ((>= i end) #t)
          ((pred (string-ref str i)) (lp (+ i 1)))
          (else #f)))))

  (define (string-any pred str . rest)
    (let* ((start (if (pair? rest) (car rest) 0))
           (end (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) (string-length str)))
           (pred (if (char? pred) (lambda (c) (char=? c pred)) pred)))
      (let lp ((i start))
        (cond
          ((>= i end) #f)
          ((pred (string-ref str i)) #t)
          (else (lp (+ i 1)))))))

  (define (string-fold kons knil str . rest)
    (let* ((start (if (pair? rest) (car rest) 0))
           (end (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) (string-length str))))
      (let lp ((i start) (acc knil))
        (if (>= i end) acc
          (lp (+ i 1) (kons (string-ref str i) acc))))))

  (define (string-fold-right kons knil str . rest)
    (let* ((start (if (pair? rest) (car rest) 0))
           (end (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) (string-length str))))
      (let lp ((i (- end 1)) (acc knil))
        (if (< i start) acc
          (lp (- i 1) (kons (string-ref str i) acc))))))

  (define (string-for-each-index proc str . rest)
    (let* ((start (if (pair? rest) (car rest) 0))
           (end (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) (string-length str))))
      (let lp ((i start))
        (when (< i end)
          (proc i)
          (lp (+ i 1))))))

  (define (string-map! proc str . rest)
    (let* ((start (if (pair? rest) (car rest) 0))
           (end (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) (string-length str))))
      (let lp ((i start))
        (when (< i end)
          (string-set! str i (proc (string-ref str i)))
          (lp (+ i 1))))))

  (define (string-tokenize str . rest)
    (let ((pred (if (pair? rest) (car rest) (lambda (c) (not (char-whitespace? c))))))
      (let lp ((i 0) (tokens '()) (len (string-length str)))
        (cond
          ((>= i len) (reverse tokens))
          ((pred (string-ref str i))
           ;; Start of token
           (let lp2 ((j (+ i 1)))
             (cond
               ((or (>= j len) (not (pred (string-ref str j))))
                (lp j (cons (substring str i j) tokens) len))
               (else (lp2 (+ j 1))))))
          (else (lp (+ i 1) tokens len))))))

  (define (string-replace str1 str2 start end)
    (string-append
      (substring str1 0 start)
      str2
      (substring str1 end (string-length str1))))

  ) ;; end library
