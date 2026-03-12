#!chezscheme
;;; (std text json-schema) -- JSON Schema Validation

(library (std text json-schema)
  (export
    define-json-schema
    json-schema?
    validate-json
    schema-valid?
    make-schema
    ;; Schema types
    schema-type-string
    schema-type-number
    schema-type-boolean
    schema-type-null
    schema-type-array
    schema-type-object
    ;; Validation results
    validation-result?
    validation-valid?
    validation-errors)

  (import (chezscheme) (std pregexp))

  ;; ========== Schema Type Constants ==========

  (define schema-type-string  'string)
  (define schema-type-number  'number)
  (define schema-type-boolean 'boolean)
  (define schema-type-null    'null)
  (define schema-type-array   'array)
  (define schema-type-object  'object)

  ;; ========== Schema Storage Helpers ==========
  ;;
  ;; Schemas are stored as string-keyed hashtables.
  ;; Keyword symbols like #:type are converted to strings ("type")
  ;; so we don't have issues with Chez's uninterned #: symbols.

  (define (schema-key sym)
    ;; Convert a #:keyword or regular symbol to a string key
    (let ([s (symbol->string sym)])
      s))

  (define (schema-get ht key-sym)
    (hashtable-ref ht (schema-key key-sym) #f))

  ;; ========== Schema Record ==========
  ;; A schema is a string-keyed hashtable with a marker entry.

  (define (json-schema? x)
    (and (hashtable? x)
         (hashtable-ref x "__json-schema__" #f)))

  (define (make-schema . opts)
    ;; opts: keyword-value pairs for schema constraints
    ;; Supported: #:type #:required #:properties #:minimum #:maximum
    ;;            #:min-length #:max-length #:pattern #:items #:enum
    (let ([ht (make-hashtable string-hash string=?)])
      (hashtable-set! ht "__json-schema__" #t)
      (let loop ([o opts])
        (unless (null? o)
          (let ([key (car o)]
                [val (cadr o)])
            (hashtable-set! ht (schema-key key) val)
            (loop (cddr o)))))
      ht))

  ;; ========== Validation Result ==========

  (define-record-type validation-result-rec
    (fields (immutable valid?  validation-valid?)
            (immutable errors  validation-errors)))

  (define (validation-result? x) (validation-result-rec? x))

  (define (make-valid-result)
    (make-validation-result-rec #t '()))

  (define (make-invalid-result errors)
    (make-validation-result-rec #f errors))

  ;; ========== Type Checking ==========

  (define (json-type-of val)
    (cond
      [(string?  val) 'string]
      [(boolean? val) 'boolean]
      [(eq? val (void)) 'null]
      [(and (number? val) (integer? val)) 'integer]
      [(number?  val) 'number]
      [(list?    val) 'array]
      [(hashtable? val) 'object]
      [else 'unknown]))

  (define (type-matches? val type)
    (case type
      [(string)  (string? val)]
      [(number)  (number? val)]
      [(integer) (and (number? val) (integer? val))]
      [(boolean) (boolean? val)]
      [(null)    (eq? val (void))]
      [(array)   (list? val)]
      [(object)  (hashtable? val)]
      [else #f]))

  ;; ========== Pattern Matching ==========

  (define (string-matches-pattern? str pattern)
    ;; Use pregexp from (std pregexp) for pattern matching
    (guard (exn [#t #f])
      (if (pregexp-match (pregexp pattern) str) #t #f)))

  ;; ========== Core Validator ==========

  (define (validate-json value schema)
    (unless (json-schema? schema)
      (error 'validate-json "not a valid schema" schema))
    (let ([errors '()])
      (define (add-error! msg)
        (set! errors (cons msg errors)))

      ;; Check type constraint
      (let ([type (hashtable-ref schema "type" #f)])
        (when type
          (unless (type-matches? value type)
            (add-error!
              (format #f "expected type ~a, got ~a"
                type (json-type-of value))))))

      ;; Check enum constraint
      (let ([enum (hashtable-ref schema "enum" #f)])
        (when enum
          (unless (member value enum)
            (add-error!
              (format #f "value ~s not in enum ~s" value enum)))))

      ;; String constraints
      (when (string? value)
        (let ([min-len (hashtable-ref schema "min-length" #f)])
          (when min-len
            (when (< (string-length value) min-len)
              (add-error!
                (format #f "string length ~a < minimum ~a"
                  (string-length value) min-len)))))
        (let ([max-len (hashtable-ref schema "max-length" #f)])
          (when max-len
            (when (> (string-length value) max-len)
              (add-error!
                (format #f "string length ~a > maximum ~a"
                  (string-length value) max-len)))))
        (let ([pattern (hashtable-ref schema "pattern" #f)])
          (when pattern
            (unless (string-matches-pattern? value pattern)
              (add-error!
                (format #f "string ~s does not match pattern ~s"
                  value pattern))))))

      ;; Numeric constraints
      (when (number? value)
        (let ([minimum (hashtable-ref schema "minimum" #f)])
          (when minimum
            (when (< value minimum)
              (add-error!
                (format #f "value ~a < minimum ~a" value minimum)))))
        (let ([maximum (hashtable-ref schema "maximum" #f)])
          (when maximum
            (when (> value maximum)
              (add-error!
                (format #f "value ~a > maximum ~a" value maximum))))))

      ;; Array constraints
      (when (list? value)
        (let ([items-schema (hashtable-ref schema "items" #f)])
          (when items-schema
            (let loop ([items value] [idx 0])
              (unless (null? items)
                (let ([item-result (validate-json (car items) items-schema)])
                  (unless (validation-valid? item-result)
                    (for-each
                      (lambda (e)
                        (add-error! (format #f "item[~a]: ~a" idx e)))
                      (validation-errors item-result))))
                (loop (cdr items) (+ idx 1)))))))

      ;; Object constraints
      (when (hashtable? value)
        ;; Check required fields
        (let ([required (hashtable-ref schema "required" #f)])
          (when required
            (for-each
              (lambda (field)
                (let ([field-str (if (symbol? field) (symbol->string field) field)])
                  (unless (hashtable-ref value field-str #f)
                    (add-error!
                      (format #f "required field ~s is missing" field-str)))))
              required)))
        ;; Validate properties
        (let ([props (hashtable-ref schema "properties" #f)])
          (when props
            (let-values ([(ks vs) (hashtable-entries props)])
              (vector-for-each
                (lambda (prop-name prop-schema)
                  (let* ([key (if (symbol? prop-name)
                                  (symbol->string prop-name)
                                  prop-name)]
                         [prop-val (hashtable-ref value key #f)])
                    (when prop-val
                      (let ([prop-result (validate-json prop-val prop-schema)])
                        (unless (validation-valid? prop-result)
                          (for-each
                            (lambda (e)
                              (add-error! (format #f "~a: ~a" key e)))
                            (validation-errors prop-result)))))))
                ks vs)))))

      (if (null? errors)
          (make-valid-result)
          (make-invalid-result (reverse errors)))))

  (define (schema-valid? value schema)
    (validation-valid? (validate-json value schema)))

  ;; ========== Macros ==========

  (define-syntax define-json-schema
    (syntax-rules ()
      [(_ name constraint ...)
       (define name (make-schema constraint ...))]))

) ;; end library
