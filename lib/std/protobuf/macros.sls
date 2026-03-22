#!chezscheme
;;; (std protobuf macros) — defmessage macro for proto3
;;;
;;; Generates record types with protobuf serialization/deserialization
;;; from a declarative field specification.

(library (std protobuf macros)
  (export defmessage message->protobuf protobuf->message)

  (import (chezscheme) (std protobuf))

  ;; ========== Wire format helpers for deserialization ==========

  ;; Map field type symbol to the wire type number used in protobuf encoding.
  (define (field-type->wire-type ft)
    (case ft
      [(int32 int64 uint32 uint64 sint32 sint64 bool) 0]
      [(double) 1]
      [(string bytes) 2]
      [(float) 5]
      [else (error 'field-type->wire-type "unknown field type" ft)]))

  ;; Decode a raw wire value into the appropriate Scheme value given field type.
  (define (decode-wire-value wire-type raw-value field-type)
    (case field-type
      [(int32)
       ;; Interpret as signed 32-bit
       (let ([v (bitwise-and raw-value #xFFFFFFFF)])
         (if (> v #x7FFFFFFF) (- v #x100000000) v))]
      [(int64)
       ;; Interpret as signed 64-bit
       (let ([v (bitwise-and raw-value #xFFFFFFFFFFFFFFFF)])
         (if (> v #x7FFFFFFFFFFFFFFF) (- v #x10000000000000000) v))]
      [(uint32)
       (bitwise-and raw-value #xFFFFFFFF)]
      [(uint64)
       (bitwise-and raw-value #xFFFFFFFFFFFFFFFF)]
      [(sint32)
       ;; ZigZag decode
       (let ([v (bitwise-and raw-value #xFFFFFFFF)])
         (bitwise-xor (bitwise-arithmetic-shift-right v 1)
                      (- (bitwise-and v 1))))]
      [(sint64)
       (let ([v (bitwise-and raw-value #xFFFFFFFFFFFFFFFF)])
         (bitwise-xor (bitwise-arithmetic-shift-right v 1)
                      (- (bitwise-and v 1))))]
      [(bool)
       (not (zero? raw-value))]
      [(string)
       ;; raw-value is a bytevector from wire type 2
       (utf8->string raw-value)]
      [(bytes)
       ;; raw-value is a bytevector
       raw-value]
      [(float)
       ;; raw-value is u32 from wire type 5
       (let ([bv (make-bytevector 4)])
         (bytevector-u32-set! bv 0 raw-value (endianness little))
         (bytevector-ieee-single-ref bv 0 (endianness little)))]
      [(double)
       ;; raw-value is u64 from wire type 1
       (let ([bv (make-bytevector 8)])
         (bytevector-u64-set! bv 0 raw-value (endianness little))
         (bytevector-ieee-double-ref bv 0 (endianness little)))]
      [else (error 'decode-wire-value "unknown field type" field-type)]))

  ;; Default value for a proto3 field type.
  (define (default-for-type ft)
    (case ft
      [(int32 int64 uint32 uint64 sint32 sint64) 0]
      [(bool) #f]
      [(string) ""]
      [(bytes) (make-bytevector 0)]
      [(float double) 0.0]
      [else (error 'default-for-type "unknown field type" ft)]))

  ;; ========== Generic serialization ==========

  ;; Serialize a record to protobuf bytes given field descriptors.
  ;; field-descs: list of (field-name field-number field-type accessor)
  (define (message->protobuf field-descs record)
    (protobuf-encode
      (filter-map
        (lambda (fd)
          (let ([accessor (cadddr fd)]
                [fnum (cadr fd)]
                [ftype (caddr fd)])
            (let ([val (accessor record)])
              ;; Proto3: skip default values
              (if (default-value? ftype val)
                  #f
                  (make-field fnum ftype val)))))
        field-descs)))

  ;; Deserialize protobuf bytes into field values given field descriptors.
  ;; Returns a list of values in field-descriptor order.
  (define (protobuf->message field-descs bv)
    (let ([decoded (protobuf-decode bv)]
          [defaults (map (lambda (fd) (default-for-type (caddr fd)))
                         field-descs)])
      ;; Build result: for each field descriptor, find matching decoded entry.
      (map (lambda (fd default)
             (let ([fnum (cadr fd)]
                   [ftype (caddr fd)])
               (let ([entry (find-first (lambda (e) (= (car e) fnum)) decoded)])
                 (if entry
                     (decode-wire-value (cadr entry) (caddr entry) ftype)
                     default))))
           field-descs defaults)))

  (define (default-value? ftype val)
    (case ftype
      [(int32 int64 uint32 uint64 sint32 sint64)
       (and (number? val) (zero? val))]
      [(bool) (not val)]
      [(string) (and (string? val) (zero? (string-length val)))]
      [(bytes) (and (bytevector? val) (zero? (bytevector-length val)))]
      [(float double) (and (number? val) (zero? val))]
      [else #f]))

  (define (filter-map f lst)
    (let loop ([lst lst] [acc '()])
      (if (null? lst)
          (reverse acc)
          (let ([v (f (car lst))])
            (loop (cdr lst) (if v (cons v acc) acc))))))

  (define (find-first pred lst)
    (let loop ([lst lst])
      (cond
        [(null? lst) #f]
        [(pred (car lst)) (car lst)]
        [else (loop (cdr lst))])))

  ;; ========== defmessage macro ==========

  (define-syntax defmessage
    (lambda (stx)
      (syntax-case stx ()
        [(_ name (field-name field-number field-type) ...)
         (with-syntax
           ([(accessor ...)
             (map (lambda (fn)
                    (datum->syntax #'name
                      (string->symbol
                        (string-append
                          (symbol->string (syntax->datum #'name))
                          "-"
                          (symbol->string (syntax->datum fn))))))
                  #'(field-name ...))]
            [constructor
             (datum->syntax #'name
               (string->symbol
                 (string-append "make-" (symbol->string (syntax->datum #'name)))))]
            [predicate
             (datum->syntax #'name
               (string->symbol
                 (string-append (symbol->string (syntax->datum #'name)) "?")))]
            [serializer
             (datum->syntax #'name
               (string->symbol
                 (string-append (symbol->string (syntax->datum #'name))
                                "->protobuf")))]
            [deserializer
             (datum->syntax #'name
               (string->symbol
                 (string-append "protobuf->"
                                (symbol->string (syntax->datum #'name)))))])
           #'(begin
               ;; Define the record type
               (define-record-type name
                 (fields
                   (immutable field-name accessor) ...)
                 (protocol
                   (lambda (new)
                     (lambda (field-name ...)
                       (new field-name ...)))))

               ;; Field descriptor table (runtime)
               (define field-descriptors
                 (list (list 'field-name field-number 'field-type accessor) ...))

               ;; Serializer
               (define (serializer record)
                 (message->protobuf field-descriptors record))

               ;; Deserializer
               (define (deserializer bv)
                 (apply constructor
                        (protobuf->message field-descriptors bv)))))])))

) ;; end library
