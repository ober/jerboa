#!chezscheme
;;; (std schema) -- Data schema validation

(library (std schema)
  (export
    make-schema schema? schema-validate schema-valid? schema-errors schema-type
    *schema-max-depth*
    s:string s:integer s:number s:boolean s:null s:any
    s:list s:hash s:optional s:required s:enum s:union
    s:pattern s:min-length s:max-length s:min s:max s:keys
    validation-error? validation-error-path
    validation-error-message validation-error-value)

  (import (chezscheme) (std pregexp))

  (define *schema-max-depth* (make-parameter 128))

  ;;; ---- Validation error ----

  (define-record-type %validation-error
    (fields path message value)
    (protocol (lambda (new)
      (lambda (path msg val) (new path msg val)))))

  (define (validation-error? x) (%validation-error? x))
  (define (validation-error-path e) (%validation-error-path e))
  (define (validation-error-message e) (%validation-error-message e))
  (define (validation-error-value e) (%validation-error-value e))

  (define (%make-verror path msg val)
    (make-%validation-error path msg val))

  ;;; ---- Schema record ----

  (define-record-type %schema
    (fields type validator)
    (protocol (lambda (new)
      (lambda (type validator) (new type validator)))))

  (define (make-schema type validator)
    (make-%schema type validator))

  (define (schema? x) (%schema? x))
  (define (schema-type s) (%schema-type s))

  ;; Run schema on value, return list of errors
  (define (schema-validate schema value)
    (define (validate-with-depth schema value path)
      (when (> (length path) (*schema-max-depth*))
        (error 'schema-validate "maximum validation depth exceeded"
               (length path) (*schema-max-depth*)))
      ((%schema-validator schema) value path))
    (validate-with-depth schema value '()))

  (define (schema-valid? schema value)
    (null? (schema-validate schema value)))

  (define (schema-errors schema value)
    (schema-validate schema value))

  ;;; ---- Type validators ----

  (define s:string
    (make-schema 'string
      (lambda (val path)
        (if (string? val)
          '()
          (list (%make-verror path "expected string" val))))))

  (define s:integer
    (make-schema 'integer
      (lambda (val path)
        (if (and (integer? val) (exact? val))
          '()
          (list (%make-verror path "expected integer" val))))))

  (define s:number
    (make-schema 'number
      (lambda (val path)
        (if (number? val)
          '()
          (list (%make-verror path "expected number" val))))))

  (define s:boolean
    (make-schema 'boolean
      (lambda (val path)
        (if (boolean? val)
          '()
          (list (%make-verror path "expected boolean" val))))))

  (define s:null
    (make-schema 'null
      (lambda (val path)
        (if (eq? val #f)
          '()
          (list (%make-verror path "expected null (#f)" val))))))

  (define s:any
    (make-schema 'any
      (lambda (val path) '())))

  ;;; ---- Combinators ----

  (define (s:list element-schema)
    (make-schema 'list
      (lambda (val path)
        (if (not (list? val))
          (list (%make-verror path "expected list" val))
          (let loop ([items val] [i 0] [errors '()])
            (if (null? items)
              (reverse errors)
              (loop (cdr items) (+ i 1)
                    (append (reverse (schema-validate element-schema (car items)))
                            errors))))))))

  (define (s:hash key-schemas)
    ;; key-schemas: alist of (key . schema) or (key schema)
    (make-schema 'hash
      (lambda (val path)
        (if (not (hashtable? val))
          (list (%make-verror path "expected hash table" val))
          (let loop ([ks key-schemas] [errors '()])
            (if (null? ks)
              (reverse errors)
              (let* ([entry (car ks)]
                     [key (if (pair? entry) (car entry) entry)]
                     [sub-schema (if (pair? entry) (cdr entry) s:any)]
                     [sub-schema (if (and (pair? sub-schema) (null? (cdr sub-schema)))
                                   (car sub-schema)
                                   sub-schema)]
                     [field-val (hashtable-ref val key
                                  (hashtable-ref val (symbol->string key) #f))]
                     [sub-errors (schema-validate sub-schema field-val)])
                (loop (cdr ks)
                      (append (reverse
                                (map (lambda (e)
                                       (%make-verror
                                         (append path (list key))
                                         (validation-error-message e)
                                         (validation-error-value e)))
                                     sub-errors))
                              errors)))))))))

  (define (s:optional schema)
    (make-schema 'optional
      (lambda (val path)
        (if (or (eq? val #f) (eq? val (if #f #f)))
          '()
          (schema-validate schema val)))))

  (define (s:required schema)
    (make-schema 'required
      (lambda (val path)
        (if (eq? val #f)
          (list (%make-verror path "required field is missing or null" val))
          (schema-validate schema val)))))

  (define (s:enum . values)
    (make-schema 'enum
      (lambda (val path)
        (if (member val values)
          '()
          (list (%make-verror path
                  (string-append "expected one of: "
                    (apply string-append
                      (let loop ([vs values] [first? #t])
                        (if (null? vs) '()
                          (cons (if first? "" ", ")
                                (cons (format "~s" (car vs))
                                      (loop (cdr vs) #f)))))))
                  val))))))

  (define (s:union . schemas)
    (make-schema 'union
      (lambda (val path)
        (if (exists (lambda (s) (null? (schema-validate s val))) schemas)
          '()
          (list (%make-verror path "value does not match any schema in union" val))))))

  (define (s:pattern regex-string)
    (make-schema 'pattern
      (lambda (val path)
        (if (not (string? val))
          (list (%make-verror path "expected string for pattern match" val))
          (let ([m (pregexp-match regex-string val)])
            (if (and m (string=? (car m) val))
              '()
              (list (%make-verror path
                      (string-append "string does not match pattern: " regex-string)
                      val))))))))

  (define (s:min-length n)
    (make-schema 'min-length
      (lambda (val path)
        (let ([len (cond [(string? val) (string-length val)]
                         [(list? val) (length val)]
                         [else #f])])
          (cond
            [(not len)
             (list (%make-verror path "expected string or list for min-length" val))]
            [(< len n)
             (list (%make-verror path
                     (format "length ~a is less than minimum ~a" len n) val))]
            [else '()])))))

  (define (s:max-length n)
    (make-schema 'max-length
      (lambda (val path)
        (let ([len (cond [(string? val) (string-length val)]
                         [(list? val) (length val)]
                         [else #f])])
          (cond
            [(not len)
             (list (%make-verror path "expected string or list for max-length" val))]
            [(> len n)
             (list (%make-verror path
                     (format "length ~a exceeds maximum ~a" len n) val))]
            [else '()])))))

  (define (s:min n)
    (make-schema 'min
      (lambda (val path)
        (if (not (number? val))
          (list (%make-verror path "expected number for min constraint" val))
          (if (< val n)
            (list (%make-verror path (format "~a is less than minimum ~a" val n) val))
            '())))))

  (define (s:max n)
    (make-schema 'max
      (lambda (val path)
        (if (not (number? val))
          (list (%make-verror path "expected number for max constraint" val))
          (if (> val n)
            (list (%make-verror path (format "~a exceeds maximum ~a" val n) val))
            '())))))

  (define (s:keys required-keys)
    (make-schema 'keys
      (lambda (val path)
        (if (not (hashtable? val))
          (list (%make-verror path "expected hash table for s:keys" val))
          (let loop ([keys required-keys] [errors '()])
            (if (null? keys)
              (reverse errors)
              (let* ([k (car keys)]
                     [present? (or (hashtable-contains? val k)
                                   (hashtable-contains? val (symbol->string k)))])
                (loop (cdr keys)
                      (if present? errors
                        (cons (%make-verror (append path (list k))
                                (format "required key '~a' is missing" k) val)
                              errors))))))))))

) ;; end library
