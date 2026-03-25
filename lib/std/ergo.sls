#!chezscheme
;;; (std ergo) — Ergonomic typing layer
;;;
;;; Gerbil-inspired type annotations with minimal friction.
;;;
;;; Type cast:
;;;   (: expr type)  — checked cast (raises in debug mode if wrong type)
;;;
;;; Typed scopes with dot-access:
;;;   (using (var expr : type) var.field ...)    — checked type + dot-access
;;;   (using (var expr as type) var.field ...)   — unchecked, dot-access only
;;;   (using ((v1 e1 : t1) (v2 e2 as t2)) ...)  — multiple bindings
;;;
;;; Contract predicates:
;;;   (maybe pred)     — returns predicate: #f or satisfies pred
;;;   (list-of? pred)  — returns predicate: list where all elements satisfy pred

(library (std ergo)
  (export using : maybe list-of?)
  (import (chezscheme)
          (std typed))

  ;; ========== Type Cast ==========

  ;; (: expr type) — checked cast, raises on failure in debug mode
  (define-syntax :
    (lambda (stx)
      (syntax-case stx ()
        [(kw expr type-name)
         (identifier? #'type-name)
         #'(let ([v expr])
             (check-type! ': 'expr v 'type-name)
             v)])))

  ;; ========== Contract Predicates ==========

  (define (maybe pred)
    (lambda (v) (or (not v) (pred v))))

  (define (list-of? pred)
    (lambda (v) (and (list? v) (for-all pred v))))

  ;; ========== using Macro ==========

  (define-syntax using
    (lambda (stx)

      ;; Find index of first #\. in a string, or #f
      (define (dot-index str)
        (let loop ([i 0])
          (cond
            [(= i (string-length str)) #f]
            [(char=? (string-ref str i) #\.) i]
            [else (loop (+ i 1))])))

      ;; Split "var.field" -> (values "var" "field"), or (values #f #f)
      (define (split-dot str)
        (let ([idx (dot-index str)])
          (if idx
            (values (substring str 0 idx)
                    (substring str (+ idx 1) (string-length str)))
            (values #f #f))))

      ;; Check if a symbol contains a dot matching a var in var-map
      (define (dotted-var? d var-map)
        (and (symbol? d)
             (let-values ([(prefix suffix) (split-dot (symbol->string d))])
               (and prefix suffix (assoc prefix var-map)))))

      ;; Walk syntax tree, replacing var.field with (type-field var).
      ;; var-map: alist of (var-name-string . type-name-string)
      ;; ctx: syntax object for lexical context
      (define (transform s var-map ctx)
        (let ([d (syntax->datum s)])
          (cond
            [(dotted-var? d var-map)
             (let-values ([(prefix suffix) (split-dot (symbol->string d))])
               (let* ([type-str (cdr (assoc prefix var-map))]
                      [accessor (string->symbol
                                  (string-append type-str "-" suffix))]
                      [var (string->symbol prefix)])
                 (datum->syntax ctx (list accessor var))))]
            [(not (pair? d)) s]
            [(eq? (car d) 'quote) s]
            [else
             (let ([lst (syntax->list s)])
               (if lst
                 (datum->syntax ctx
                   (map (lambda (x)
                          (syntax->datum (transform x var-map ctx)))
                        lst))
                 s))])))

      (define (make-var-entry var-stx type-stx)
        (cons (symbol->string (syntax->datum var-stx))
              (symbol->string (syntax->datum type-stx))))

      (define (transform-body body-stx var-map ctx)
        (map (lambda (b)
               (datum->syntax ctx (syntax->datum (transform b var-map ctx))))
             (syntax->list body-stx)))

      ;; Detect binding operator: : or as
      (define (binding-op? stx)
        (let ([d (syntax->datum stx)])
          (or (eq? d ':) (eq? d 'as))))

      (define (checked-op? stx)
        (eq? (syntax->datum stx) ':))

      (syntax-case stx ()
        ;; Single binding: (using (var expr :/as type) body ...)
        [(_ (var expr op type) body ...)
         (and (identifier? #'var)
              (identifier? #'type)
              (binding-op? #'op))
         (let ([var-map (list (make-var-entry #'var #'type))])
           (with-syntax ([(tbody ...) (transform-body #'(body ...) var-map #'var)])
             (if (checked-op? #'op)
               #'(let ([var expr])
                   (check-type! 'using 'var var 'type)
                   tbody ...)
               #'(let ([var expr])
                   tbody ...))))]

        ;; Multiple bindings: expand into nested using
        [(_ (first-binding rest-binding ...) body ...)
         (let ()
           (syntax-case #'first-binding ()
             [(var expr op type)
              (and (identifier? #'var)
                   (identifier? #'type)
                   (binding-op? #'op))
              #'(using (var expr op type)
                  (using (rest-binding ...) body ...))]))]

        ;; Base case: empty binding list
        [(_ () body ...)
         #'(begin body ...)])))

) ;; end library
