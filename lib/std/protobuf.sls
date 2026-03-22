#!chezscheme
;;; (std protobuf) — Protocol Buffers wire format encoding/decoding
;;;
;;; Pure Scheme implementation of proto3 wire format.
;;; Wire types: 0=varint, 1=64-bit, 2=length-delimited, 5=32-bit.

(library (std protobuf)
  (export
    ;; Wire format encoding
    protobuf-encode protobuf-decode
    ;; Field helpers
    make-field field? field-number field-value field-type
    ;; Type constructors for encoding
    pb-varint pb-fixed64 pb-fixed32
    pb-bytes pb-string pb-bool
    pb-int32 pb-int64 pb-uint32 pb-uint64
    pb-sint32 pb-sint64
    pb-float pb-double
    pb-repeated pb-embedded
    ;; Decoding helpers
    protobuf->alist
    alist->protobuf)

  (import (chezscheme))

  ;; ========== Field record ==========

  (define-record-type (pb-field make-field field?)
    (fields
      (immutable number field-number)
      (immutable type field-type)
      (immutable value field-value))
    (protocol
      (lambda (new)
        (lambda (number type value)
          (new number type value)))))

  ;; ========== Varint encoding (LEB128) ==========

  (define (encode-varint n)
    ;; Encode unsigned integer as LEB128 bytes, return list of bytes.
    (let loop ([n (if (< n 0)
                      (bitwise-and n #xFFFFFFFFFFFFFFFF)
                      n)]
               [acc '()])
      (let ([lo (bitwise-and n #x7F)]
            [hi (bitwise-arithmetic-shift-right n 7)])
        (if (zero? hi)
            (reverse (cons lo acc))
            (loop hi (cons (bitwise-ior lo #x80) acc))))))

  (define (decode-varint bv pos)
    ;; Returns (values decoded-value new-pos).
    (let loop ([shift 0] [result 0] [i pos])
      (when (>= i (bytevector-length bv))
        (error 'decode-varint "unexpected end of input"))
      (let ([byte (bytevector-u8-ref bv i)])
        (let ([result (bitwise-ior result
                        (bitwise-arithmetic-shift-left
                          (bitwise-and byte #x7F) shift))])
          (if (zero? (bitwise-and byte #x80))
              (values result (+ i 1))
              (loop (+ shift 7) result (+ i 1)))))))

  ;; ========== ZigZag encoding for signed integers ==========

  (define (zigzag-encode n bits)
    (bitwise-xor (bitwise-arithmetic-shift-left n 1)
                 (bitwise-arithmetic-shift-right n (- bits 1))))

  (define (zigzag-decode n)
    (bitwise-xor (bitwise-arithmetic-shift-right n 1)
                 (- (bitwise-and n 1))))

  ;; ========== Fixed-width encoding ==========

  (define (encode-fixed32 n)
    (let ([bv (make-bytevector 4)])
      (bytevector-u32-set! bv 0 (bitwise-and n #xFFFFFFFF) (endianness little))
      bv))

  (define (encode-fixed64 n)
    (let ([bv (make-bytevector 8)])
      (bytevector-u64-set! bv 0 (bitwise-and n #xFFFFFFFFFFFFFFFF) (endianness little))
      bv))

  (define (encode-float val)
    (let ([bv (make-bytevector 4)])
      (bytevector-ieee-single-set! bv 0 val (endianness little))
      bv))

  (define (encode-double val)
    (let ([bv (make-bytevector 8)])
      (bytevector-ieee-double-set! bv 0 val (endianness little))
      bv))

  ;; ========== Field tag encoding ==========

  (define (wire-type-for type)
    (case type
      [(varint int32 int64 uint32 uint64 sint32 sint64 bool) 0]
      [(fixed64 sfixed64 double) 1]
      [(bytes string embedded packed) 2]
      [(fixed32 sfixed32 float) 5]
      [else (error 'wire-type-for "unknown field type" type)]))

  (define (encode-tag field-num wire-type)
    (encode-varint (bitwise-ior (bitwise-arithmetic-shift-left field-num 3)
                                wire-type)))

  ;; ========== Encode a single field's value ==========

  (define (encode-field-value type value)
    (case type
      [(varint uint32 uint64)
       (encode-varint value)]
      [(int32)
       (encode-varint (bitwise-and value #xFFFFFFFF))]
      [(int64)
       (encode-varint (bitwise-and value #xFFFFFFFFFFFFFFFF))]
      [(sint32)
       (encode-varint (zigzag-encode value 32))]
      [(sint64)
       (encode-varint (zigzag-encode value 64))]
      [(bool)
       (encode-varint (if value 1 0))]
      [(fixed32 sfixed32)
       (bytevector->u8-list (encode-fixed32 value))]
      [(fixed64 sfixed64)
       (bytevector->u8-list (encode-fixed64 value))]
      [(float)
       (bytevector->u8-list (encode-float value))]
      [(double)
       (bytevector->u8-list (encode-double value))]
      [(string)
       (let ([bv (string->utf8 value)])
         (append (encode-varint (bytevector-length bv))
                 (bytevector->u8-list bv)))]
      [(bytes)
       (append (encode-varint (bytevector-length value))
               (bytevector->u8-list value))]
      [(embedded)
       ;; value is a list of fields; encode recursively
       (let ([inner (protobuf-encode value)])
         (append (encode-varint (bytevector-length inner))
                 (bytevector->u8-list inner)))]
      [(packed)
       ;; value is (type . values-list)
       (let* ([inner-type (car value)]
              [vals (cdr value)]
              [bytes (apply append
                       (map (lambda (v) (encode-field-value inner-type v))
                            vals))]
              [inner-bv (u8-list->bytevector bytes)])
         (append (encode-varint (bytevector-length inner-bv))
                 bytes))]
      [else (error 'encode-field-value "unknown type" type)]))

  ;; ========== Top-level encoder ==========

  (define (protobuf-encode fields)
    ;; fields: list of field records
    (let ([bytes (apply append
                   (map (lambda (f)
                          (let ([wt (wire-type-for (field-type f))])
                            (append (encode-tag (field-number f) wt)
                                    (encode-field-value (field-type f)
                                                        (field-value f)))))
                        fields))])
      (u8-list->bytevector bytes)))

  ;; ========== Top-level decoder ==========

  (define (protobuf-decode bv)
    ;; Returns list of (field-number wire-type value).
    (let loop ([pos 0] [acc '()])
      (if (>= pos (bytevector-length bv))
          (reverse acc)
          (let-values ([(tag new-pos) (decode-varint bv pos)])
            (let ([field-num (bitwise-arithmetic-shift-right tag 3)]
                  [wire-type (bitwise-and tag #x07)])
              (case wire-type
                [(0) ;; varint
                 (let-values ([(val p2) (decode-varint bv new-pos)])
                   (loop p2 (cons (list field-num wire-type val) acc)))]
                [(1) ;; 64-bit
                 (when (> (+ new-pos 8) (bytevector-length bv))
                   (error 'protobuf-decode "unexpected end of input (64-bit)"))
                 (let ([val (bytevector-u64-ref bv new-pos (endianness little))])
                   (loop (+ new-pos 8) (cons (list field-num wire-type val) acc)))]
                [(2) ;; length-delimited
                 (let-values ([(len p2) (decode-varint bv new-pos)])
                   (when (> (+ p2 len) (bytevector-length bv))
                     (error 'protobuf-decode "unexpected end of input (length-delimited)"))
                   (let ([data (make-bytevector len)])
                     (bytevector-copy! bv p2 data 0 len)
                     (loop (+ p2 len)
                           (cons (list field-num wire-type data) acc))))]
                [(5) ;; 32-bit
                 (when (> (+ new-pos 4) (bytevector-length bv))
                   (error 'protobuf-decode "unexpected end of input (32-bit)"))
                 (let ([val (bytevector-u32-ref bv new-pos (endianness little))])
                   (loop (+ new-pos 4) (cons (list field-num wire-type val) acc)))]
                [else
                 (error 'protobuf-decode "unsupported wire type" wire-type)]))))))

  ;; ========== Field constructors ==========

  (define (pb-varint n v)  (make-field n 'varint v))
  (define (pb-fixed64 n v) (make-field n 'fixed64 v))
  (define (pb-fixed32 n v) (make-field n 'fixed32 v))
  (define (pb-bytes n v)   (make-field n 'bytes v))
  (define (pb-string n v)  (make-field n 'string v))
  (define (pb-bool n v)    (make-field n 'bool v))
  (define (pb-int32 n v)   (make-field n 'int32 v))
  (define (pb-int64 n v)   (make-field n 'int64 v))
  (define (pb-uint32 n v)  (make-field n 'uint32 v))
  (define (pb-uint64 n v)  (make-field n 'uint64 v))
  (define (pb-sint32 n v)  (make-field n 'sint32 v))
  (define (pb-sint64 n v)  (make-field n 'sint64 v))
  (define (pb-float n v)   (make-field n 'float v))
  (define (pb-double n v)  (make-field n 'double v))
  ;; Packed repeated: encodes all values as a single length-delimited chunk.
  (define (pb-repeated n type values) (make-field n 'packed (cons type values)))
  ;; Embedded message: fields is a list of field records.
  (define (pb-embedded n fields) (make-field n 'embedded fields))

  ;; ========== Convenience: alist interface ==========

  (define (protobuf->alist bv)
    ;; Decode and return as ((field-number . value) ...).
    ;; Wire type 2 values remain as bytevectors (caller interprets).
    (map (lambda (entry)
           (cons (car entry) (caddr entry)))
         (protobuf-decode bv)))

  (define (alist->protobuf alist)
    ;; Encode from ((field-number type . value) ...).
    ;; Each entry is (field-number type value).
    (protobuf-encode
      (map (lambda (entry)
             (make-field (car entry) (cadr entry) (caddr entry)))
           alist)))

) ;; end library
