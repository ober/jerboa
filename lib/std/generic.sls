#!chezscheme
;;; :std/generic -- Generic functions with type-based dispatch

(library (std generic)
  (export defgeneric defspecific generic-dispatch)
  (import (chezscheme))

  ;; Return a type key for dispatch
  (define (type-of obj)
    (cond
      ((and (record? obj) (record-rtd obj)) => (lambda (rtd) rtd))
      ((string? obj)      'string)
      ((number? obj)      'number)
      ((pair? obj)        'pair)
      ((vector? obj)      'vector)
      ((symbol? obj)      'symbol)
      ((boolean? obj)     'boolean)
      ((char? obj)        'char)
      ((bytevector? obj)  'bytevector)
      ((port? obj)        'port)
      ((procedure? obj)   'procedure)
      ((null? obj)        'null)
      (else               'other)))

  (define (generic-dispatch table name-str obj rest)
    (let ((impl (hashtable-ref table (type-of obj) #f)))
      (if impl
          (apply impl obj rest)
          (error name-str "no method for type" (type-of obj) obj))))

  ;; (defgeneric name (first-arg rest-arg ...))
  ;; Defines name as a generic function and name-table as its dispatch table.
  (define-syntax defgeneric
    (lambda (stx)
      (syntax-case stx ()
        [(_ name (first-arg rest-arg ...))
         (with-syntax ([tbl (datum->syntax #'name
                              (string->symbol
                                (string-append (symbol->string (syntax->datum #'name))
                                               "-table")))])
           #'(begin
               (define tbl (make-eq-hashtable))
               (define (name first-arg rest-arg ...)
                 (generic-dispatch tbl
                                   (symbol->string 'name)
                                   first-arg
                                   (list rest-arg ...)))))])))

  ;; (defspecific (name (first-arg type-expr) rest-arg ...) body ...)
  (define-syntax defspecific
    (lambda (stx)
      (syntax-case stx ()
        [(_ (name (first-arg type-expr) rest-arg ...) body ...)
         (with-syntax ([tbl (datum->syntax #'name
                              (string->symbol
                                (string-append (symbol->string (syntax->datum #'name))
                                               "-table")))])
           #'(hashtable-set! tbl
                             type-expr
                             (lambda (first-arg rest-arg ...) body ...)))])))

) ;; end library
