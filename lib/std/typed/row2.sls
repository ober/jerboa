#!chezscheme
;;; (std typed row2) — Enhanced row polymorphism (Phase 4b)
;;;
;;; Open records: runtime extensible/restrictable records based on alists.
;;; Row types: structural type descriptors with rest-row variables.
;;; Row combinators: map/filter/fold over open records.

(library (std typed row2)
  (export
    ;; Open record operations
    make-open-record
    open-record?
    open-record-get
    open-record-set
    open-record-has?
    open-record-fields
    open-record-alist
    record-extend
    record-restrict
    record-merge
    ;; Row type checking
    row-type?
    make-row-type
    row-type-fields
    row-type-rest
    check-row-type!
    Row
    ;; Row polymorphic define
    define/row
    ;; Standard row combinators
    row-map
    row-filter
    row-fold
    row-keys
    row-values)

  (import (chezscheme))

  ;; ========== Open Record Implementation ==========
  ;;
  ;; An open-record wraps an immutable association list mapping field
  ;; symbols to values. We use a record type to make open-record?
  ;; a fast predicate test.

  (define-record-type open-record-type
    (fields (immutable data))  ;; association list: ((field . value) ...)
    (nongenerative open-record-type-uid)
    (sealed #t))

  (define (open-record? x)
    (open-record-type? x))

  ;; (make-open-record alist) — create from association list
  ;; alist: ((field-symbol . value) ...) — standard dotted-pair alist
  ;;   or   ((field-symbol value) ...) — two-element list alist
  (define (make-open-record alist)
    (unless (list? alist)
      (error 'make-open-record "expected alist" alist))
    ;; Normalize: accept both (k . v) and (k v) forms
    (let ([normalized
           (map (lambda (pair)
                  (unless (pair? pair)
                    (error 'make-open-record "invalid alist entry" pair))
                  (unless (symbol? (car pair))
                    (error 'make-open-record "field name must be a symbol" pair))
                  (cond
                    ;; Dotted pair: (sym . val) — pair? but not proper list pair
                    [(not (list? pair))
                     ;; (sym . val) where val is not a list
                     pair]
                    ;; Two-element proper list: (sym val)
                    [(and (pair? (cdr pair)) (null? (cddr pair)))
                     (cons (car pair) (cadr pair))]
                    ;; Single-element: (sym) — value is #f
                    [(null? (cdr pair))
                     (cons (car pair) #f)]
                    [else
                     (error 'make-open-record "invalid alist entry" pair)]))
                alist)])
      (make-open-record-type normalized)))

  ;; (open-record-get rec field) -> value or #f
  (define (open-record-get rec field)
    (unless (open-record? rec)
      (error 'open-record-get "not an open-record" rec))
    (let ([pair (assq field (open-record-type-data rec))])
      (if pair (cdr pair) #f)))

  ;; (open-record-set rec field val) -> new-rec (immutable structural copy)
  (define (open-record-set rec field val)
    (unless (open-record? rec)
      (error 'open-record-set "not an open-record" rec))
    (unless (symbol? field)
      (error 'open-record-set "field must be a symbol" field))
    (let* ([data (open-record-type-data rec)]
           [new-data
            (let loop ([rest data] [acc '()])
              (cond
                [(null? rest)
                 ;; Field not found; add it
                 (reverse (cons (cons field val) acc))]
                [(eq? (caar rest) field)
                 ;; Found; replace
                 (append (reverse (cons (cons field val) acc)) (cdr rest))]
                [else
                 (loop (cdr rest) (cons (car rest) acc))]))])
      (make-open-record-type new-data)))

  ;; (open-record-has? rec field) -> boolean
  (define (open-record-has? rec field)
    (and (open-record? rec)
         (symbol? field)
         (if (assq field (open-record-type-data rec)) #t #f)))

  ;; (open-record-fields rec) -> list of field symbols
  (define (open-record-fields rec)
    (unless (open-record? rec)
      (error 'open-record-fields "not an open-record" rec))
    (map car (open-record-type-data rec)))

  ;; (open-record-alist rec) -> alist of (field . value)
  (define (open-record-alist rec)
    (unless (open-record? rec)
      (error 'open-record-alist "not an open-record" rec))
    (open-record-type-data rec))

  ;; (record-extend rec field val) -> new open-record with field added/replaced
  (define (record-extend rec field val)
    (open-record-set rec field val))

  ;; (record-restrict rec field) -> new open-record without the named field
  (define (record-restrict rec field)
    (unless (open-record? rec)
      (error 'record-restrict "not an open-record" rec))
    (unless (symbol? field)
      (error 'record-restrict "field must be a symbol" field))
    (make-open-record-type
      (filter (lambda (pair) (not (eq? (car pair) field)))
              (open-record-type-data rec))))

  ;; (record-merge rec1 rec2) -> new open-record; right (rec2) wins on conflict
  (define (record-merge rec1 rec2)
    (unless (open-record? rec1)
      (error 'record-merge "first arg not an open-record" rec1))
    (unless (open-record? rec2)
      (error 'record-merge "second arg not an open-record" rec2))
    ;; Start with rec1 fields, then add rec2 fields (overriding duplicates)
    (let* ([data1 (open-record-type-data rec1)]
           [data2 (open-record-type-data rec2)]
           ;; Keep rec1 fields not in rec2
           [kept1 (filter (lambda (pair)
                            (not (assq (car pair) data2)))
                          data1)])
      (make-open-record-type (append kept1 data2))))

  ;; ========== Row Type Descriptors ==========
  ;;
  ;; A row type says: "this open-record must have at least these fields,
  ;; with these types. It may have additional fields captured by rest."
  ;;
  ;; #(row-type-tag fields rest)
  ;;   fields: alist of (field-symbol . type-spec)
  ;;   rest:   symbol (row variable) or #f

  (define (make-row-type fields . rest-args)
    (let ([rest (if (null? rest-args) #f (car rest-args))])
      (unless (list? fields)
        (error 'make-row-type "fields must be a list" fields))
      (vector 'row-type fields rest)))

  (define (row-type? x)
    (and (vector? x)
         (= (vector-length x) 3)
         (eq? (vector-ref x 0) 'row-type)))

  (define (row-type-fields rt)
    (if (row-type? rt)
      (vector-ref rt 1)
      (error 'row-type-fields "not a row-type" rt)))

  (define (row-type-rest rt)
    (if (row-type? rt)
      (vector-ref rt 2)
      (error 'row-type-rest "not a row-type" rt)))

  ;; (check-row-type! who rec row-type) — verify rec satisfies row-type
  ;; Raises an error if any required field is missing.
  (define (check-row-type! who rec rt)
    (unless (row-type? rt)
      (error who "not a row-type" rt))
    (unless (open-record? rec)
      (error who "not an open-record" rec))
    (for-each
      (lambda (field-spec)
        (let ([fname (car field-spec)])
          (unless (open-record-has? rec fname)
            (error who
              (string-append "open-record missing required field: "
                             (symbol->string fname))
              rec))))
      (row-type-fields rt)))

  ;; Row syntax:
  ;;   (Row name: string age: fixnum)         — closed row type
  ;;   (Row name: string age: fixnum rest: r) — open row type with rest variable r
  ;;
  ;; Each field is specified as "name: Type" (colon attached to field name).
  ;; Optional rest: sym at the end gives the rest variable.
  ;; Expands to (make-row-type '((name . string) (age . fixnum)) 'r)
  (define-syntax Row
    (lambda (stx)
      (define (parse-row-fields lst)
        ;; lst is a list of syntax objects after Row
        ;; Returns (values fields rest-var) where fields is an alist datum
        (let loop ([items lst] [fields '()] [rest-var #f])
          (cond
            [(null? items)
             (values (reverse fields) rest-var)]
            ;; Check for rest: rest-var at the end
            [(and (>= (length items) 2)
                  (let ([d (syntax->datum (car items))])
                    (and (symbol? d) (eq? d 'rest:))))
             (values (reverse fields) (syntax->datum (cadr items)))]
            ;; Expect keyword: field-name: type
            ;; Field name is a symbol ending in ':'
            [(and (>= (length items) 2)
                  (let ([d (syntax->datum (car items))])
                    (and (symbol? d)
                         (let ([s (symbol->string d)])
                           (and (> (string-length s) 0)
                                (char=? (string-ref s (- (string-length s) 1)) #\:))))))
             (let* ([kw-datum (syntax->datum (car items))]
                    [kw-str   (symbol->string kw-datum)]
                    [fname    (string->symbol
                                (substring kw-str 0 (- (string-length kw-str) 1)))]
                    [ftype    (syntax->datum (cadr items))])
               (loop (cddr items)
                     (cons (cons fname ftype) fields)
                     rest-var))]
            [else
             (syntax-violation 'Row "invalid row field spec" stx (car items))])))
      (syntax-case stx ()
        [(kw . rest-forms)
         (let-values ([(fields rest-var)
                       (parse-row-fields (syntax->list #'rest-forms))])
           ;; Use datum->syntax with the keyword identifier as context
           (if rest-var
             (with-syntax ([qfields (datum->syntax #'kw `(quote ,fields))]
                           [qrest   (datum->syntax #'kw `(quote ,rest-var))])
               #'(make-row-type qfields qrest))
             (with-syntax ([qfields (datum->syntax #'kw `(quote ,fields))])
               #'(make-row-type qfields))))])))

  ;; ========== define/row ==========
  ;;
  ;; (define/row (name [arg : (Row field: type ...)] ...) body ...)
  ;;
  ;; Like define but understands row-type annotations.
  ;; At runtime in debug mode, checks that row-typed args satisfy their row types.

  (define-syntax define/row
    (lambda (stx)
      (define (meta-filter-map f lst)
        (let loop ([rest lst] [acc '()])
          (if (null? rest)
            (reverse acc)
            (let ([r (f (car rest))])
              (if r
                (loop (cdr rest) (cons r acc))
                (loop (cdr rest) acc))))))
      (define (parse-args arg-list)
        (map (lambda (arg-stx)
               (syntax-case arg-stx ()
                 [(aname : type-expr)
                  (eq? (syntax->datum #':) ':)
                  (list #'aname #'type-expr #t)]
                 [aname
                  (identifier? #'aname)
                  (list #'aname #f #f)]))
             (syntax->list arg-list)))
      (syntax-case stx ()
        [(_ (name arg ...) body ...)
         (let ([parsed (parse-args #'(arg ...))])
           (with-syntax
             ([(aname ...) (map car parsed)]
              [(check ...)
               (meta-filter-map
                 (lambda (p)
                   (if (caddr p)
                     (let ([aname (car p)]
                           [atype (cadr p)])
                       #`(when (row-type? #,atype)
                           (check-row-type! 'name #,aname #,atype)))
                     #f))
                 parsed)])
             #'(define (name aname ...)
                 check ...
                 body ...)))])))

  ;; ========== Row Combinators ==========

  ;; (row-map f rec) -> new open-record with f applied to each value
  (define (row-map f rec)
    (unless (open-record? rec)
      (error 'row-map "not an open-record" rec))
    (make-open-record-type
      (map (lambda (pair) (cons (car pair) (f (cdr pair))))
           (open-record-type-data rec))))

  ;; (row-filter pred rec) -> new open-record keeping fields where pred holds
  ;; pred receives (field-symbol value)
  (define (row-filter pred rec)
    (unless (open-record? rec)
      (error 'row-filter "not an open-record" rec))
    (make-open-record-type
      (filter (lambda (pair) (pred (car pair) (cdr pair)))
              (open-record-type-data rec))))

  ;; (row-fold f init rec) -> fold over fields (f acc field-sym value)
  (define (row-fold f init rec)
    (unless (open-record? rec)
      (error 'row-fold "not an open-record" rec))
    (fold-left (lambda (acc pair) (f acc (car pair) (cdr pair)))
               init
               (open-record-type-data rec)))

  ;; (row-keys rec) -> list of field symbols
  (define (row-keys rec)
    (open-record-fields rec))

  ;; (row-values rec) -> list of values in field order
  (define (row-values rec)
    (unless (open-record? rec)
      (error 'row-values "not an open-record" rec))
    (map cdr (open-record-type-data rec)))

  ;; Helper: filter-map
  (define (filter-map f lst)
    (let loop ([rest lst] [acc '()])
      (if (null? rest)
        (reverse acc)
        (let ([r (f (car rest))])
          (if r
            (loop (cdr rest) (cons r acc))
            (loop (cdr rest) acc))))))

  ) ;; end library
