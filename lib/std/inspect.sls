#!chezscheme
;;; (std inspect) — Runtime inspection utilities
;;;
;;; Wraps Chez's inspector API for debugging.
;;;
;;; (inspect-object '(1 2 3)) => ((type . pair) (length . 3) ...)
;;; (inspect-procedure car) => ((arity . 1) (name . "car") ...)
;;; (live-object-counts) => ((pair . 12345) (vector . 678) ...)

(library (std inspect)
  (export inspect-object inspect-procedure inspect-condition
          object-type-name object-size
          live-object-counts procedure-arity
          inspect-record)

  (import (chezscheme))

  ;; Get a descriptive type name for any object
  (define (object-type-name obj)
    (cond
      [(pair? obj) 'pair]
      [(null? obj) 'null]
      [(vector? obj) 'vector]
      [(string? obj) 'string]
      [(symbol? obj) 'symbol]
      [(number? obj) (cond
                       [(fixnum? obj) 'fixnum]
                       [(flonum? obj) 'flonum]
                       [(bignum? obj) 'bignum]
                       [(ratnum? obj) 'ratnum]
                       [else 'number])]
      [(char? obj) 'char]
      [(boolean? obj) 'boolean]
      [(bytevector? obj) 'bytevector]
      [(port? obj) 'port]
      [(procedure? obj) 'procedure]
      [(hashtable? obj) 'hashtable]
      [(record? obj) (record-type-name (record-rtd obj))]
      [(box? obj) 'box]
      [(condition? obj) 'condition]
      [(eq? obj (void)) 'void]
      [(eof-object? obj) 'eof-object]
      [else 'unknown]))

  ;; Inspect any object — returns alist of properties
  (define (inspect-object obj)
    (let ([type (object-type-name obj)])
      (cons `(type . ,type)
            (case type
              [(pair)
               `((length . ,(let loop ([x obj] [n 0])
                              (if (pair? x) (loop (cdr x) (+ n 1)) n)))
                 (proper? . ,(list? obj))
                 (car . ,(car obj))
                 (cdr . ,(cdr obj)))]
              [(vector)
               `((length . ,(vector-length obj))
                 (elements . ,(if (<= (vector-length obj) 10)
                                  (vector->list obj)
                                  (append (vector->list (vector-copy obj 0 10))
                                          '(...)))))]
              [(string)
               `((length . ,(string-length obj))
                 (value . ,obj))]
              [(bytevector)
               `((length . ,(bytevector-length obj)))]
              [(hashtable)
               `((size . ,(hashtable-size obj))
                 (keys . ,(vector->list (hashtable-keys obj))))]
              [(procedure)
               (inspect-procedure obj)]
              [else '()]))))

  ;; Inspect a procedure
  (define (inspect-procedure proc)
    (unless (procedure? proc)
      (error 'inspect-procedure "not a procedure" proc))
    (let ([info (procedure-arity-mask proc)])
      `((name . ,(or (let ([s (format "~a" proc)])
                       (and (> (string-length s) 2) s))
                     "anonymous"))
        (arity-mask . ,info))))

  ;; Get simplified arity from a procedure
  (define (procedure-arity proc)
    (let ([mask (procedure-arity-mask proc)])
      (cond
        [(= mask -1) 'variadic]
        [else
         (let loop ([m mask] [n 0] [acc '()])
           (if (= m 0)
               (reverse acc)
               (loop (ash m -1) (+ n 1)
                     (if (odd? m) (cons n acc) acc))))])))

  ;; Inspect a condition
  (define (inspect-condition c)
    (unless (condition? c)
      (error 'inspect-condition "not a condition" c))
    (let ([components (simple-conditions c)])
      (map (lambda (sc)
             (let ([rtd (record-rtd sc)])
               `(,(record-type-name rtd)
                 ,@(let loop ([flds (csv7:record-type-field-names rtd)]
                              [i 0]
                              [acc '()])
                     (if (null? flds)
                         (reverse acc)
                         (loop (cdr flds) (+ i 1)
                               (cons (cons (car flds)
                                           ((csv7:record-field-accessor rtd i) sc))
                                     acc)))))))
           components)))

  ;; Inspect a record
  (define (inspect-record rec)
    (unless (record? rec)
      (error 'inspect-record "not a record" rec))
    (let ([rtd (record-rtd rec)])
      `((type . ,(record-type-name rtd))
        (fields . ,(let loop ([flds (csv7:record-type-field-names rtd)]
                              [i 0]
                              [acc '()])
                     (if (null? flds)
                         (reverse acc)
                         (loop (cdr flds) (+ i 1)
                               (cons (cons (car flds)
                                           ((csv7:record-field-accessor rtd i) rec))
                                     acc))))))))

  ;; Object size in bytes (approximate)
  (define (object-size obj)
    (cond
      [(fixnum? obj) 0]  ;; immediate
      [(pair? obj) (* 2 (fixnum-width))]
      [(vector? obj) (* (+ 1 (vector-length obj)) (fixnum-width))]
      [(string? obj) (+ (fixnum-width) (* 4 (string-length obj)))]
      [(bytevector? obj) (+ (fixnum-width) (bytevector-length obj))]
      [else (fixnum-width)]))

  ;; Count live objects by type (wraps Chez's object-counts)
  (define (live-object-counts)
    (guard (exn [else '()])
      (object-counts)))

) ;; end library
