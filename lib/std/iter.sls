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

  ;; Fusion helpers: return the raw vector from (hashtable-entries ht)
  ;; without the (let-values ...) → call-with-values overhead that
  ;; inlining hashtable-entries into each macro expansion would force
  ;; on every enclosing call.  `(hashtable-keys ht)` already returns a
  ;; single vector, so we only need a helper for values.
  (define (%ht-values-vec ht)
    (call-with-values (lambda () (hashtable-entries ht))
      (lambda (_keys vals) vals)))

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

  ;; for — side-effecting iteration. Fuses in-range/in-vector/in-string.
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
        (syntax-case stx (in-range in-vector in-string in-list)
          ;; --- Fused iterators ---
          [(_ ((var (in-range end))) body ...)
           (binding-id? #'var)
           #'(let ([n end])
               (let loop ([i 0])
                 (when (< i n)
                   (let ([var i]) body ...)
                   (loop (+ i 1)))))]
          [(_ ((var (in-range start end))) body ...)
           (binding-id? #'var)
           #'(let ([s start] [e end])
               (let loop ([i s])
                 (when (< i e)
                   (let ([var i]) body ...)
                   (loop (+ i 1)))))]
          [(_ ((var (in-range start end step))) body ...)
           (binding-id? #'var)
           #'(let ([s start] [e end] [stp step])
               (let loop ([i s])
                 (unless (if (positive? stp) (>= i e) (<= i e))
                   (let ([var i]) body ...)
                   (loop (+ i stp)))))]
          [(_ ((var (in-vector vec-expr))) body ...)
           (binding-id? #'var)
           #'(let ([v vec-expr])
               (let ([n (vector-length v)])
                 (let loop ([i 0])
                   (when (fx< i n)
                     (let ([var (vector-ref v i)]) body ...)
                     (loop (fx+ i 1))))))]
          [(_ ((var (in-string str-expr))) body ...)
           (binding-id? #'var)
           #'(let ([s str-expr])
               (let ([n (string-length s)])
                 (let loop ([i 0])
                   (when (fx< i n)
                     (let ([var (string-ref s i)]) body ...)
                     (loop (fx+ i 1))))))]
          [(_ ((var (in-list lst-expr))) body ...)
           (binding-id? #'var)
           #'(for-each (lambda (var) body ...) lst-expr)]
          ;; --- Unfused fallbacks ---
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

  ;; for/collect — collect results into a list.
  ;; Iterator fusion: when the iter-expr is syntactically (in-range ...),
  ;; (in-vector ...), or (in-string ...), skip the materialize-list step
  ;; and emit a direct index loop. Saves O(n) cons cells per fused iter.
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
        (syntax-case stx (in-range in-vector in-string in-list
                          in-hash-keys in-hash-values)
          ;; --- Fused iterators (single-clause) ---
          [(_ ((var (in-range end))) body ...)
           (binding-id? #'var)
           #'(let ([n end])
               (let loop ([i 0] [acc '()])
                 (if (>= i n) (reverse acc)
                   (let ([var i])
                     (loop (+ i 1) (cons (begin body ...) acc))))))]
          [(_ ((var (in-range start end))) body ...)
           (binding-id? #'var)
           #'(let ([s start] [e end])
               (let loop ([i s] [acc '()])
                 (if (>= i e) (reverse acc)
                   (let ([var i])
                     (loop (+ i 1) (cons (begin body ...) acc))))))]
          [(_ ((var (in-range start end step))) body ...)
           (binding-id? #'var)
           #'(let ([s start] [e end] [stp step])
               (let loop ([i s] [acc '()])
                 (if (if (positive? stp) (>= i e) (<= i e))
                   (reverse acc)
                   (let ([var i])
                     (loop (+ i stp) (cons (begin body ...) acc))))))]
          [(_ ((var (in-vector vec-expr))) body ...)
           (binding-id? #'var)
           #'(let ([v vec-expr])
               (let ([n (vector-length v)])
                 (let loop ([i 0] [acc '()])
                   (if (fx>= i n) (reverse acc)
                     (let ([var (vector-ref v i)])
                       (loop (fx+ i 1) (cons (begin body ...) acc)))))))]
          [(_ ((var (in-string str-expr))) body ...)
           (binding-id? #'var)
           #'(let ([s str-expr])
               (let ([n (string-length s)])
                 (let loop ([i 0] [acc '()])
                   (if (fx>= i n) (reverse acc)
                     (let ([var (string-ref s i)])
                       (loop (fx+ i 1) (cons (begin body ...) acc)))))))]
          [(_ ((var (in-list lst-expr))) body ...)
           (binding-id? #'var)
           #'(map (lambda (var) body ...) lst-expr)]
          [(_ ((var (in-hash-keys ht-expr))) body ...)
           (binding-id? #'var)
           #'(let ([ks (hashtable-keys ht-expr)])
               (let ([n (vector-length ks)])
                 (let loop ([i 0] [acc '()])
                   (if (fx>= i n) (reverse acc)
                     (let ([var (vector-ref ks i)])
                       (loop (fx+ i 1) (cons (begin body ...) acc)))))))]
          [(_ ((var (in-hash-values ht-expr))) body ...)
           (binding-id? #'var)
           #'(let ([vs (%ht-values-vec ht-expr)])
               (let ([n (vector-length vs)])
                 (let loop ([i 0] [acc '()])
                   (if (fx>= i n) (reverse acc)
                     (let ([var (vector-ref vs i)])
                       (loop (fx+ i 1) (cons (begin body ...) acc)))))))]
          ;; --- Unfused fallback ---
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

  ;; for/fold — fold with accumulator. Fuses in-range/in-vector/in-string.
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
        (syntax-case stx (in-range in-vector in-string in-list)
          ;; --- Fused iterators ---
          [(_ ((acc init)) ((var (in-range end))) body ...)
           (binding-id? #'var)
           #'(let ([n end])
               (let loop ([i 0] [acc init])
                 (if (>= i n) acc
                   (let ([var i])
                     (loop (+ i 1) (begin body ...))))))]
          [(_ ((acc init)) ((var (in-range start end))) body ...)
           (binding-id? #'var)
           #'(let ([s start] [e end])
               (let loop ([i s] [acc init])
                 (if (>= i e) acc
                   (let ([var i])
                     (loop (+ i 1) (begin body ...))))))]
          [(_ ((acc init)) ((var (in-range start end step))) body ...)
           (binding-id? #'var)
           #'(let ([s start] [e end] [stp step])
               (let loop ([i s] [acc init])
                 (if (if (positive? stp) (>= i e) (<= i e)) acc
                   (let ([var i])
                     (loop (+ i stp) (begin body ...))))))]
          [(_ ((acc init)) ((var (in-vector vec-expr))) body ...)
           (binding-id? #'var)
           #'(let ([v vec-expr])
               (let ([n (vector-length v)])
                 (let loop ([i 0] [acc init])
                   (if (fx>= i n) acc
                     (let ([var (vector-ref v i)])
                       (loop (fx+ i 1) (begin body ...)))))))]
          [(_ ((acc init)) ((var (in-string str-expr))) body ...)
           (binding-id? #'var)
           #'(let ([s str-expr])
               (let ([n (string-length s)])
                 (let loop ([i 0] [acc init])
                   (if (fx>= i n) acc
                     (let ([var (string-ref s i)])
                       (loop (fx+ i 1) (begin body ...)))))))]
          [(_ ((acc init)) ((var (in-list lst-expr))) body ...)
           (binding-id? #'var)
           #'(let loop ([rest lst-expr] [acc init])
               (if (null? rest) acc
                 (let ([var (car rest)])
                   (loop (cdr rest) (begin body ...)))))]
          ;; --- Unfused fallbacks ---
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

  ;; for/or — return first truthy result.  Fuses in-range/in-vector/
  ;; in-string/in-list parallel to for/fold so the iterator list
  ;; never gets materialised.
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
        (syntax-case stx (in-range in-vector in-string in-list)
          ;; --- Fused iterators ---
          [(_ ((var (in-range end))) body ...)
           (binding-id? #'var)
           #'(let ([n end])
               (let loop ([i 0])
                 (if (>= i n) #f
                   (let ([var i])
                     (or (begin body ...) (loop (+ i 1)))))))]
          [(_ ((var (in-range start end))) body ...)
           (binding-id? #'var)
           #'(let ([s start] [e end])
               (let loop ([i s])
                 (if (>= i e) #f
                   (let ([var i])
                     (or (begin body ...) (loop (+ i 1)))))))]
          [(_ ((var (in-range start end step))) body ...)
           (binding-id? #'var)
           #'(let ([s start] [e end] [stp step])
               (let loop ([i s])
                 (if (if (positive? stp) (>= i e) (<= i e)) #f
                   (let ([var i])
                     (or (begin body ...) (loop (+ i stp)))))))]
          [(_ ((var (in-vector vec-expr))) body ...)
           (binding-id? #'var)
           #'(let ([v vec-expr])
               (let ([n (vector-length v)])
                 (let loop ([i 0])
                   (if (fx>= i n) #f
                     (let ([var (vector-ref v i)])
                       (or (begin body ...) (loop (fx+ i 1))))))))]
          [(_ ((var (in-string str-expr))) body ...)
           (binding-id? #'var)
           #'(let ([s str-expr])
               (let ([n (string-length s)])
                 (let loop ([i 0])
                   (if (fx>= i n) #f
                     (let ([var (string-ref s i)])
                       (or (begin body ...) (loop (fx+ i 1))))))))]
          [(_ ((var (in-list lst-expr))) body ...)
           (binding-id? #'var)
           #'(let loop ([rest lst-expr])
               (if (null? rest) #f
                 (let ([var (car rest)])
                   (or (begin body ...) (loop (cdr rest))))))]
          ;; --- Unfused fallback (single clause, list) ---
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

  ;; for/and — return #f if any result is #f.  Fuses same iterators
  ;; as for/or.
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
        (syntax-case stx (in-range in-vector in-string in-list)
          ;; --- Fused iterators ---
          [(_ ((var (in-range end))) body ...)
           (binding-id? #'var)
           #'(let ([n end])
               (let loop ([i 0] [last #t])
                 (if (>= i n) last
                   (let ([var i])
                     (let ([%r (begin body ...)])
                       (if %r (loop (+ i 1) %r) #f))))))]
          [(_ ((var (in-range start end))) body ...)
           (binding-id? #'var)
           #'(let ([s start] [e end])
               (let loop ([i s] [last #t])
                 (if (>= i e) last
                   (let ([var i])
                     (let ([%r (begin body ...)])
                       (if %r (loop (+ i 1) %r) #f))))))]
          [(_ ((var (in-range start end step))) body ...)
           (binding-id? #'var)
           #'(let ([s start] [e end] [stp step])
               (let loop ([i s] [last #t])
                 (if (if (positive? stp) (>= i e) (<= i e)) last
                   (let ([var i])
                     (let ([%r (begin body ...)])
                       (if %r (loop (+ i stp) %r) #f))))))]
          [(_ ((var (in-vector vec-expr))) body ...)
           (binding-id? #'var)
           #'(let ([v vec-expr])
               (let ([n (vector-length v)])
                 (let loop ([i 0] [last #t])
                   (if (fx>= i n) last
                     (let ([var (vector-ref v i)])
                       (let ([%r (begin body ...)])
                         (if %r (loop (fx+ i 1) %r) #f)))))))]
          [(_ ((var (in-string str-expr))) body ...)
           (binding-id? #'var)
           #'(let ([s str-expr])
               (let ([n (string-length s)])
                 (let loop ([i 0] [last #t])
                   (if (fx>= i n) last
                     (let ([var (string-ref s i)])
                       (let ([%r (begin body ...)])
                         (if %r (loop (fx+ i 1) %r) #f)))))))]
          [(_ ((var (in-list lst-expr))) body ...)
           (binding-id? #'var)
           #'(let loop ([rest lst-expr] [last #t])
               (if (null? rest) last
                 (let ([var (car rest)])
                   (let ([%r (begin body ...)])
                     (if %r (loop (cdr rest) %r) #f)))))]
          ;; --- Unfused fallback (single clause, list) ---
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
