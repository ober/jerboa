#!chezscheme
;;; :std/iter -- Gerbil-compatible iterator macros
;;;
;;; Provides for, for/collect, for/fold, for/or, for/and
;;; with iterator constructors: in-list, in-vector, in-range,
;;; in-string, in-hash-keys, in-hash-values, in-hash-pairs,
;;; in-naturals, in-indexed
;;;
;;; Clause extensions (Clojure-style):
;;;   :when expr   — skip iteration when expr is #f
;;;   :while expr  — stop iteration when expr is #f
;;;   :let ((var expr) ...) — bind intermediate values

(library (std iter)
  (export
    for for/collect for/fold for/or for/and
    in-list in-vector in-range in-string
    in-hash-keys in-hash-values in-hash-pairs
    in-naturals in-indexed
    ;; better2 #7: I/O iterators
    in-port in-lines in-chars in-bytes in-producer)

  (import (except (chezscheme)
            make-hash-table hash-table? iota 1+ 1-)
          (jerboa runtime))

  ;; Iterator constructors — return plain lists for simplicity

  (define (in-list lst) lst)

  (define (in-vector vec)
    (vector->list vec))

  (define in-range
    (case-lambda
      ((end) (in-range 0 end 1))
      ((start end) (in-range start end 1))
      ((start end step)
       (let loop ([i start] [acc '()])
         (if (if (positive? step) (>= i end) (<= i end))
           (reverse acc)
           (loop (+ i step) (cons i acc)))))))

  (define (in-string str)
    (string->list str))

  (define (in-hash-keys ht)
    (hash-keys ht))

  (define (in-hash-values ht)
    (hash-values ht))

  (define (in-hash-pairs ht)
    (hash->list ht))

  (define in-naturals
    (case-lambda
      (() (in-naturals 0))
      ((start)
       (let loop ([i start] [acc '()] [n 0])
         (if (>= n 100000) (reverse acc)
           (loop (+ i 1) (cons i acc) (+ n 1)))))))

  (define (in-indexed lst)
    (let loop ([rest lst] [i 0] [acc '()])
      (if (null? rest) (reverse acc)
        (loop (cdr rest) (+ i 1) (cons (cons i (car rest)) acc)))))

  ;; =========================================================================
  ;; Clause-aware for macros
  ;; =========================================================================

  ;; Shared expand-time helpers, duplicated in each macro's (let ...)
  ;; to ensure they're at the correct phase.
  ;;
  ;; kw?: check if syntax s is a Jerboa keyword with given name
  ;;   e.g., (kw? #'x "when") checks if x is the keyword when:
  ;;   At syntax level, when: has datum symbol "when:" (NOT "#:when")
  ;;
  ;; binding-id?: check if syntax is a non-keyword identifier

  ;; Internal helper macro for general clause expansion.
  ;; Used by for/collect, for, for/fold, for/or, for/and.
  (define-syntax %clause-expand
    (let ()
      (define (kw? s name)
        (and (identifier? s)
             (let ([d (syntax->datum s)])
               (and (symbol? d)
                    (string=? (symbol->string d)
                              (string-append name ":"))))))

      (define (binding-id? s)
        (and (identifier? s)
             (let ([d (syntax->datum s)])
               (or (not (symbol? d))
                   (let ([str (symbol->string d)])
                     (or (= (string-length str) 0)
                         (not (char=? (string-ref str (- (string-length str) 1)) #\:))))))))

      (define (split-mods clauses)
        (syntax-case clauses ()
          [() (values '() #'())]
          [(k expr . rest)
           (or (kw? #'k "when") (kw? #'k "while"))
           (let-values ([(ms remaining) (split-mods #'rest)])
             (values (cons (list #'k #'expr) ms) remaining))]
          [(k binds . rest)
           (kw? #'k "let")
           (let-values ([(ms remaining) (split-mods #'rest)])
             (values (cons (list #'k #'binds) ms) remaining))]
          [other (values '() #'other)]))

      (define (any-while? mods)
        (and (pair? mods)
             (or (kw? (caar mods) "while")
                 (any-while? (cdr mods)))))

      (define (wrap-mods mods inner stop-sym)
        (if (null? mods) inner
          (let ([k (caar mods)] [arg (cadar mods)] [rest (cdr mods)])
            (cond
              [(kw? k "when")
               (with-syntax ([w (wrap-mods rest inner stop-sym)] [e arg])
                 #'(when e w))]
              [(kw? k "while")
               (with-syntax ([w (wrap-mods rest inner stop-sym)]
                             [e arg] [stop stop-sym])
                 #'(if e w (set! stop #t)))]
              [(kw? k "let")
               (with-syntax ([w (wrap-mods rest inner stop-sym)] [b arg])
                 #'(let b w))]))))

      (define (expand-clauses clauses leaf)
        (syntax-case clauses ()
          [() leaf]
          [((var iter-expr) . after)
           (binding-id? #'var)
           (let-values ([(mods remaining) (split-mods #'after)])
             (let ([inner (expand-clauses remaining leaf)])
               (if (any-while? mods)
                 (with-syntax ([wrapped (wrap-mods mods inner
                                          (datum->syntax #'var '%stop?))]
                               [%stop? (datum->syntax #'var '%stop?)])
                   #'(let loop ([lst iter-expr])
                       (when (pair? lst)
                         (let ([var (car lst)] [%stop? #f])
                           wrapped
                           (unless %stop? (loop (cdr lst)))))))
                 (with-syntax ([wrapped (wrap-mods mods inner #f)])
                   #'(let loop ([lst iter-expr])
                       (when (pair? lst)
                         (let ([var (car lst)])
                           wrapped)
                         (loop (cdr lst))))))))]))

      (lambda (stx)
        (syntax-case stx ()
          [(_ (clause ...) leaf-expr)
           (expand-clauses #'(clause ...) #'leaf-expr)]))))

  ;; for — side-effecting iteration
  (define-syntax for
    (let ()
      (define (binding-id? s)
        (and (identifier? s)
             (let ([d (syntax->datum s)])
               (or (not (symbol? d))
                   (let ([str (symbol->string d)])
                     (or (= (string-length str) 0)
                         (not (char=? (string-ref str (- (string-length str) 1)) #\:))))))))
      (lambda (stx)
        (syntax-case stx ()
          [(_ ((var iter-expr)) body ...)
           (binding-id? #'var)
           #'(for-each (lambda (var) body ...) iter-expr)]
          [(_ ((var1 iter1) (var2 iter2)) body ...)
           (and (binding-id? #'var1) (binding-id? #'var2))
           #'(let loop ([l1 iter1] [l2 iter2])
               (when (and (pair? l1) (pair? l2))
                 (let ([var1 (car l1)] [var2 (car l2)])
                   body ...
                   (loop (cdr l1) (cdr l2)))))]
          [(_ ((var1 iter1) (var2 iter2) (var3 iter3)) body ...)
           (and (binding-id? #'var1) (binding-id? #'var2) (binding-id? #'var3))
           #'(let loop ([l1 iter1] [l2 iter2] [l3 iter3])
               (when (and (pair? l1) (pair? l2) (pair? l3))
                 (let ([var1 (car l1)] [var2 (car l2)] [var3 (car l3)])
                   body ...
                   (loop (cdr l1) (cdr l2) (cdr l3)))))]
          [(_ (clause ...) body ...)
           #'(%clause-expand (clause ...) (begin body ...))]))))

  ;; for/collect — collect results into a list
  (define-syntax for/collect
    (let ()
      (define (binding-id? s)
        (and (identifier? s)
             (let ([d (syntax->datum s)])
               (or (not (symbol? d))
                   (let ([str (symbol->string d)])
                     (or (= (string-length str) 0)
                         (not (char=? (string-ref str (- (string-length str) 1)) #\:))))))))
      (lambda (stx)
        (syntax-case stx ()
          [(_ ((var iter-expr)) body ...)
           (binding-id? #'var)
           #'(map (lambda (var) body ...) iter-expr)]
          [(_ ((var1 iter1) (var2 iter2)) body ...)
           (and (binding-id? #'var1) (binding-id? #'var2))
           #'(let loop ([l1 iter1] [l2 iter2] [acc '()])
               (if (or (null? l1) (null? l2))
                 (reverse acc)
                 (let ([var1 (car l1)] [var2 (car l2)])
                   (loop (cdr l1) (cdr l2) (cons (begin body ...) acc)))))]
          [(_ (clause ...) body ...)
           (with-syntax ([%acc (datum->syntax (car (syntax->list stx)) '%acc)])
             #`(let ([%acc '()])
                 (%clause-expand (clause ...) (set! %acc (cons (begin body ...) %acc)))
                 (reverse %acc)))]))))

  ;; for/fold — fold with accumulator
  (define-syntax for/fold
    (let ()
      (define (binding-id? s)
        (and (identifier? s)
             (let ([d (syntax->datum s)])
               (or (not (symbol? d))
                   (let ([str (symbol->string d)])
                     (or (= (string-length str) 0)
                         (not (char=? (string-ref str (- (string-length str) 1)) #\:))))))))
      (lambda (stx)
        (syntax-case stx ()
          [(_ ((acc init)) ((var iter-expr)) body ...)
           (binding-id? #'var)
           #'(let loop ([rest iter-expr] [acc init])
               (if (null? rest) acc
                 (let ([var (car rest)])
                   (loop (cdr rest) (begin body ...)))))]
          [(_ ((acc init)) ((var1 iter1) (var2 iter2)) body ...)
           (and (binding-id? #'var1) (binding-id? #'var2))
           #'(let loop ([l1 iter1] [l2 iter2] [acc init])
               (if (or (null? l1) (null? l2)) acc
                 (let ([var1 (car l1)] [var2 (car l2)])
                   (loop (cdr l1) (cdr l2) (begin body ...)))))]
          [(_ ((acc init)) (clause ...) body ...)
           #`(let ([acc init])
               (%clause-expand (clause ...) (set! acc (begin body ...)))
               acc)]))))

  ;; for/or — return first truthy result
  (define-syntax for/or
    (let ()
      (define (binding-id? s)
        (and (identifier? s)
             (let ([d (syntax->datum s)])
               (or (not (symbol? d))
                   (let ([str (symbol->string d)])
                     (or (= (string-length str) 0)
                         (not (char=? (string-ref str (- (string-length str) 1)) #\:))))))))
      (lambda (stx)
        (syntax-case stx ()
          [(_ ((var iter-expr)) body ...)
           (binding-id? #'var)
           #'(let loop ([rest iter-expr])
               (if (null? rest) #f
                 (let ([var (car rest)])
                   (or (begin body ...) (loop (cdr rest))))))]
          [(_ (clause ...) body ...)
           #'(call/cc (lambda (return)
               (%clause-expand (clause ...)
                 (let ([%result (begin body ...)])
                   (when %result (return %result))))
               #f))]))))

  ;; for/and — return #f if any result is #f
  (define-syntax for/and
    (let ()
      (define (binding-id? s)
        (and (identifier? s)
             (let ([d (syntax->datum s)])
               (or (not (symbol? d))
                   (let ([str (symbol->string d)])
                     (or (= (string-length str) 0)
                         (not (char=? (string-ref str (- (string-length str) 1)) #\:))))))))
      (lambda (stx)
        (syntax-case stx ()
          [(_ ((var iter-expr)) body ...)
           (binding-id? #'var)
           #'(let loop ([rest iter-expr])
               (if (null? rest) #t
                 (let ([var (car rest)])
                   (and (begin body ...) (loop (cdr rest))))))]
          [(_ (clause ...) body ...)
           #'(call/cc (lambda (return)
               (%clause-expand (clause ...)
                 (unless (begin body ...) (return #f)))
               #t))]))))

  ;; ========== better2 #7: I/O iterators ==========

  (define in-port
    (case-lambda
      [() (in-port (current-input-port))]
      [(port) (in-port port read)]
      [(port reader)
       (let loop ([acc '()])
         (let ([datum (reader port)])
           (if (eof-object? datum)
               (reverse acc)
               (loop (cons datum acc)))))]))

  (define in-lines
    (case-lambda
      [() (in-lines (current-input-port))]
      [(port)
       (let loop ([acc '()])
         (let ([line (get-line port)])
           (if (eof-object? line)
               (reverse acc)
               (loop (cons line acc)))))]))

  (define in-chars
    (case-lambda
      [() (in-chars (current-input-port))]
      [(port)
       (let loop ([acc '()])
         (let ([ch (get-char port)])
           (if (eof-object? ch)
               (reverse acc)
               (loop (cons ch acc)))))]))

  (define in-bytes
    (case-lambda
      [() (in-bytes (current-input-port))]
      [(port)
       (let loop ([acc '()])
         (let ([b (get-u8 port)])
           (if (eof-object? b)
               (reverse acc)
               (loop (cons b acc)))))]))

  (define (in-producer thunk . sentinel)
    (let ([stop? (if (null? sentinel)
                     eof-object?
                     (let ([s (car sentinel)])
                       (lambda (x) (equal? x s))))])
      (let loop ([acc '()])
        (let ([val (thunk)])
          (if (stop? val)
              (reverse acc)
              (loop (cons val acc)))))))

) ;; end library
