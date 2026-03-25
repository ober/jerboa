#!chezscheme
;;; (std debug pp) — Pretty printer for data structures
;;;
;;; Extends Chez's pretty-print to handle hash tables, alists, records,
;;; and nested data structures with proper indentation.

(library (std debug pp)
  (export pp pp-to-string pprint
          pretty-print-columns
          ;; Data-aware pretty printing
          ppd ppd-to-string)

  (import (chezscheme))

  ;; pp: pretty-print to current output or specified port (S-expressions)
  (define pp
    (case-lambda
      [(obj) (pretty-print obj)]
      [(obj port) (pretty-print obj port)]))

  ;; pp-to-string: pretty-print to string
  (define (pp-to-string obj)
    (let ([port (open-output-string)])
      (pretty-print obj port)
      (get-output-string port)))

  ;; pprint: Gerbil-style alias
  (define pprint pp)

  ;; pretty-print-columns: re-export Chez parameter
  (define pretty-print-columns pretty-line-length)

  ;; --- Data-aware pretty printing ---
  ;; Handles: hash tables, alists, vectors, records, nested structures

  (define ppd
    (case-lambda
      [(obj) (ppd-print obj (current-output-port) 0) (newline)]
      [(obj port) (ppd-print obj port 0) (newline port)]))

  (define (ppd-to-string obj)
    (let ([port (open-output-string)])
      (ppd-print obj port 0)
      (get-output-string port)))

  ;; Max depth to prevent infinite recursion on cyclic structures
  (define *max-depth* 20)

  (define (ppd-print obj port indent)
    (cond
      ;; Hash table
      [(hashtable? obj)
       (ppd-hashtable obj port indent)]
      ;; Association list (list of pairs with symbol/string keys)
      [(alist? obj)
       (ppd-alist obj port indent)]
      ;; Vector
      [(vector? obj)
       (ppd-vector obj port indent)]
      ;; List (non-alist)
      [(and (pair? obj) (list? obj))
       (ppd-list obj port indent)]
      ;; Everything else: use write
      [else
       (write obj port)]))

  ;; Detect alist: non-empty list of pairs with symbol or string keys
  (define (alist? obj)
    (and (pair? obj)
         (list? obj)
         (not (null? obj))
         (for-all (lambda (entry)
                    (and (pair? entry)
                         (or (symbol? (car entry))
                             (string? (car entry)))))
                  obj)))

  ;; Pretty-print hash table
  (define (ppd-hashtable ht port indent)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let ([n (vector-length keys)])
        (if (= n 0)
          (display "{}" port)
          (begin
            (display "{" port)
            (let loop ([i 0])
              (when (< i n)
                (when (> i 0)
                  (display "," port)
                  (newline port)
                  (indent! port (+ indent 1)))
                (when (= i 0)
                  (newline port)
                  (indent! port (+ indent 1)))
                (write (vector-ref keys i) port)
                (display ": " port)
                (ppd-print (vector-ref vals i) port (+ indent 1))
                (loop (+ i 1))))
            (newline port)
            (indent! port indent)
            (display "}" port))))))

  ;; Pretty-print alist
  (define (ppd-alist lst port indent)
    (if (null? lst)
      (display "{}" port)
      (let ([compact? (and (<= (length lst) 4)
                           (for-all (lambda (e) (simple-value? (cdr e))) lst))])
        (if compact?
          ;; Single-line for small, simple alists
          (begin
            (display "{" port)
            (let loop ([rest lst] [first? #t])
              (unless (null? rest)
                (unless first? (display ", " port))
                (write (caar rest) port)
                (display ": " port)
                (write (cdar rest) port)
                (loop (cdr rest) #f)))
            (display "}" port))
          ;; Multi-line
          (begin
            (display "{" port)
            (let loop ([rest lst] [first? #t])
              (unless (null? rest)
                (if first?
                  (begin (newline port) (indent! port (+ indent 1)))
                  (begin (display "," port) (newline port) (indent! port (+ indent 1))))
                (write (caar rest) port)
                (display ": " port)
                (ppd-print (cdar rest) port (+ indent 1))
                (loop (cdr rest) #f)))
            (newline port)
            (indent! port indent)
            (display "}" port))))))

  ;; Pretty-print vector
  (define (ppd-vector vec port indent)
    (let ([n (vector-length vec)])
      (if (and (<= n 8) (vector-all-simple? vec))
        ;; Compact single-line for small simple vectors
        (begin
          (display "#(" port)
          (let loop ([i 0])
            (when (< i n)
              (when (> i 0) (display " " port))
              (write (vector-ref vec i) port)
              (loop (+ i 1))))
          (display ")" port))
        ;; Multi-line
        (begin
          (display "#(" port)
          (let loop ([i 0])
            (when (< i n)
              (when (> i 0)
                (newline port)
                (indent! port (+ indent 2)))
              (when (= i 0)
                (newline port)
                (indent! port (+ indent 2)))
              (ppd-print (vector-ref vec i) port (+ indent 2))
              (loop (+ i 1))))
          (display ")" port)))))

  ;; Pretty-print list
  (define (ppd-list lst port indent)
    (if (and (<= (length lst) 8) (for-all simple-value? lst))
      ;; Compact
      (write lst port)
      ;; Multi-line
      (begin
        (display "(" port)
        (let loop ([rest lst] [first? #t])
          (unless (null? rest)
            (if first?
              (ppd-print (car rest) port (+ indent 1))
              (begin
                (newline port)
                (indent! port (+ indent 1))
                (ppd-print (car rest) port (+ indent 1))))
            (loop (cdr rest) #f)))
        (display ")" port))))

  ;; --- Helpers ---

  (define (indent! port n)
    (let loop ([i 0])
      (when (< i (* n 2))
        (display #\space port)
        (loop (+ i 1)))))

  (define (simple-value? v)
    (or (number? v) (string? v) (symbol? v) (boolean? v)
        (null? v) (char? v) (eq? v (void))))

  (define (vector-all-simple? vec)
    (let loop ([i 0])
      (or (= i (vector-length vec))
          (and (simple-value? (vector-ref vec i))
               (loop (+ i 1))))))

) ;; end library
