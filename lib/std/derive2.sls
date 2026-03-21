#!chezscheme
;;; (std derive2) — Auto-derive v2: extensible protocol implementations
;;;
;;; Extends std/derive with more derivation strategies and user-defined protocols.
;;;
;;; API:
;;;   (define-protocol name (method ...) ...) — define a derivable protocol
;;;   (auto-equal rtd)                        — derive equal? for record type
;;;   (auto-hash rtd)                         — derive hash for record type
;;;   (auto-display rtd)                      — derive display for record type
;;;   (auto-compare rtd)                      — derive comparison for record type
;;;   (auto-clone rtd)                        — derive deep copy for record type
;;;   (auto-serialize rtd)                    — derive serialize/deserialize
;;;   (auto-json rtd)                         — derive ->json / json->
;;;   (derive-all rtd protocols)              — derive multiple protocols

(library (std derive2)
  (export define-protocol auto-equal auto-hash auto-display
          auto-compare auto-clone auto-serialize auto-json
          derive-all protocol-registry register-protocol!
          record-field-values record-field-names-of)

  (import (chezscheme))

  ;; ========== Protocol registry ==========

  (define *protocols* (make-eq-hashtable))

  (define (register-protocol! name deriver)
    (hashtable-set! *protocols* name deriver))

  (define (protocol-registry) *protocols*)

  ;; ========== Record introspection helpers ==========

  (define (record-field-names-of rtd)
    (let loop ([r rtd] [fields '()])
      (if (not r)
        fields
        (loop (record-type-parent r)
              (append (vector->list (record-type-field-names r)) fields)))))

  (define (record-field-values obj)
    (let* ([rtd (record-rtd obj)]
           [names (record-field-names-of rtd)])
      (map (lambda (name)
             (let ([acc (record-accessor rtd (field-index rtd name))])
               (acc obj)))
           (vector->list (record-type-field-names rtd)))))

  (define (field-index rtd name)
    (let ([names (vector->list (record-type-field-names rtd))])
      (let loop ([ns names] [i 0])
        (cond
          [(null? ns) (error 'field-index "field not found" name)]
          [(eq? (car ns) name) i]
          [else (loop (cdr ns) (+ i 1))]))))

  (define (all-field-accessors rtd)
    (let ([names (vector->list (record-type-field-names rtd))])
      (map (lambda (name)
             (record-accessor rtd (field-index rtd name)))
           names)))

  ;; ========== auto-equal ==========

  (define (auto-equal rtd)
    (let ([accessors (all-field-accessors rtd)]
          [pred (record-predicate rtd)])
      (lambda (a b)
        (and (pred a) (pred b)
             (let loop ([accs accessors])
               (or (null? accs)
                   (and (equal? ((car accs) a) ((car accs) b))
                        (loop (cdr accs)))))))))

  ;; ========== auto-hash ==========

  (define (auto-hash rtd)
    (let ([accessors (all-field-accessors rtd)])
      (lambda (obj)
        (let loop ([accs accessors] [h 0])
          (if (null? accs)
            h
            (loop (cdr accs)
                  (fxlogxor (fxarithmetic-shift-left h 5)
                            (equal-hash ((car accs) obj)))))))))

  ;; ========== auto-display ==========

  (define (auto-display rtd)
    (let ([accessors (all-field-accessors rtd)]
          [names (vector->list (record-type-field-names rtd))]
          [type-name (record-type-name rtd)])
      (lambda (obj port)
        (display "#<" port)
        (display type-name port)
        (for-each
          (lambda (name acc)
            (display " " port)
            (display name port)
            (display "=" port)
            (write (acc obj) port))
          names accessors)
        (display ">" port))))

  ;; ========== auto-compare ==========

  (define (auto-compare rtd)
    (let ([accessors (all-field-accessors rtd)])
      (lambda (a b)
        (let loop ([accs accessors])
          (if (null? accs)
            0  ;; equal
            (let ([va ((car accs) a)]
                  [vb ((car accs) b)])
              (cond
                [(and (number? va) (number? vb))
                 (cond [(< va vb) -1]
                       [(> va vb) 1]
                       [else (loop (cdr accs))])]
                [(and (string? va) (string? vb))
                 (cond [(string<? va vb) -1]
                       [(string>? va vb) 1]
                       [else (loop (cdr accs))])]
                [(and (symbol? va) (symbol? vb))
                 (cond [(string<? (symbol->string va) (symbol->string vb)) -1]
                       [(string>? (symbol->string va) (symbol->string vb)) 1]
                       [else (loop (cdr accs))])]
                [else (loop (cdr accs))])))))))

  ;; ========== auto-clone ==========

  (define (auto-clone rtd)
    (let ([accessors (all-field-accessors rtd)]
          [constructor (record-constructor
                         (make-record-constructor-descriptor rtd #f #f))])
      (lambda (obj)
        (apply constructor (map (lambda (acc) (acc obj)) accessors)))))

  ;; ========== auto-serialize ==========

  (define (auto-serialize rtd)
    (let ([accessors (all-field-accessors rtd)]
          [names (vector->list (record-type-field-names rtd))]
          [type-name (record-type-name rtd)]
          [constructor (record-constructor
                         (make-record-constructor-descriptor rtd #f #f))])
      (cons
        ;; serializer
        (lambda (obj)
          (cons type-name
                (map (lambda (name acc) (cons name (acc obj)))
                     names accessors)))
        ;; deserializer
        (lambda (alist)
          (apply constructor
            (map (lambda (name)
                   (cdr (assq name (cdr alist))))
                 names))))))

  ;; ========== auto-json ==========

  (define (auto-json rtd)
    (let ([accessors (all-field-accessors rtd)]
          [names (vector->list (record-type-field-names rtd))]
          [constructor (record-constructor
                         (make-record-constructor-descriptor rtd #f #f))])
      (cons
        ;; ->json (to alist)
        (lambda (obj)
          (map (lambda (name acc)
                 (cons (symbol->string name) (acc obj)))
               names accessors))
        ;; json-> (from alist)
        (lambda (alist)
          (apply constructor
            (map (lambda (name)
                   (cdr (or (assoc (symbol->string name) alist)
                            (cons "" #f))))
                 names))))))

  ;; ========== derive-all ==========

  (define (derive-all rtd protocols)
    (map (lambda (proto)
           (let ([deriver (hashtable-ref *protocols* proto #f)])
             (if deriver
               (cons proto (deriver rtd))
               (cons proto
                 (case proto
                   [(equal) (auto-equal rtd)]
                   [(hash) (auto-hash rtd)]
                   [(display) (auto-display rtd)]
                   [(compare) (auto-compare rtd)]
                   [(clone) (auto-clone rtd)]
                   [(serialize) (auto-serialize rtd)]
                   [(json) (auto-json rtd)]
                   [else (error 'derive-all "unknown protocol" proto)])))))
         protocols))

  ;; ========== define-protocol macro ==========

  (define-syntax define-protocol
    (syntax-rules ()
      [(_ name deriver-expr)
       (register-protocol! 'name deriver-expr)]))

) ;; end library
