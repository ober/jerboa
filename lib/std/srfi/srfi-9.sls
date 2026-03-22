#!chezscheme
;;; :std/srfi/9 -- SRFI-9 Defining Record Types
;;; Provides the SRFI-9 define-record-type form on top of R6RS records.
;;; SRFI-9 form:
;;;   (define-record-type <name>
;;;     (make-name field1 field2)
;;;     name?
;;;     (field1 get-field1)
;;;     (field2 get-field2 set-field2!))

(library (std srfi srfi-9)
  (export define-record-type)

  (import (except (chezscheme) define-record-type))

  (define-syntax define-record-type
    (lambda (stx)
      (syntax-case stx ()
        [(_ type-name (constructor-name constructor-field ...)
            predicate-name
            field-spec ...)
         (let ()
           ;; Extract info from field specs at compile time
           (define all-field-names
             (map (lambda (fs)
                    (syntax->datum
                      (syntax-case fs ()
                        [(name getter) #'name]
                        [(name getter setter) #'name])))
                  #'(field-spec ...)))

           (define ctor-field-names
             (map syntax->datum #'(constructor-field ...)))

           ;; For each constructor arg, find its index in all-field-names
           (define (ctor-field-index name)
             (let loop ([fns all-field-names] [i 0])
               (cond
                 [(null? fns)
                  (syntax-violation 'define-record-type
                    "constructor field not in field list" stx name)]
                 [(eq? name (car fns)) i]
                 [else (loop (cdr fns) (+ i 1))])))

           (define ctor-indices
             (map ctor-field-index ctor-field-names))

           (define n-fields (length all-field-names))

           ;; Build field descriptors for RTD
           (define field-descriptors
             (list->vector
               (map (lambda (fn) (list 'mutable fn)) all-field-names)))

           ;; Build getter definitions
           (define (make-getter-def fs idx rtd-id)
             (syntax-case fs ()
               [(name getter)
                #`(define getter (record-accessor #,rtd-id #,idx))]
               [(name getter setter)
                #`(define getter (record-accessor #,rtd-id #,idx))]))

           ;; Build setter definitions
           (define (make-setter-defs fs idx rtd-id)
             (syntax-case fs ()
               [(name getter) '()]
               [(name getter setter)
                (list #`(define setter (record-mutator #,rtd-id #,idx)))]))

           (with-syntax
             ([rtd (datum->syntax #'type-name (gensym "rtd"))]
              [field-desc (datum->syntax #'type-name field-descriptors)]
              [n n-fields]
              [(ctor-idx ...) (map (lambda (i) (datum->syntax #'type-name i))
                                  ctor-indices)])
             #`(begin
                 (define rtd
                   (make-record-type-descriptor
                     'type-name #f #f #f #f 'field-desc))
                 (define constructor-name
                   (let ([rcd (make-record-constructor-descriptor rtd #f #f)])
                     (let ([ctor (record-constructor rcd)])
                       (lambda (constructor-field ...)
                         (let ([vals (make-vector n (void))])
                           (vector-set! vals ctor-idx constructor-field) ...
                           (apply ctor (vector->list vals)))))))
                 (define predicate-name (record-predicate rtd))
                 #,@(let loop ([specs #'(field-spec ...)] [i 0] [acc '()])
                      (if (null? specs) (reverse acc)
                        (let ([idx (datum->syntax #'type-name i)])
                          (loop (cdr specs) (+ i 1)
                                (append
                                  (make-setter-defs (car specs) idx #'rtd)
                                  (cons (make-getter-def (car specs) idx #'rtd)
                                        acc)))))))))])))

) ;; end library
