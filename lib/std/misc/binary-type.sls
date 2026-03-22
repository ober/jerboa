#!chezscheme
;;; (std misc binary-type) — Syntax-driven binary protocol framework
;;;
;;; Define binary types with automatic reader/writer generation.
;;; Supports primitive types, composite records, fixed-length arrays,
;;; and nested structures.
;;;
;;; (define-binary-type uint8
;;;   (reader (lambda (port) (get-u8 port)))
;;;   (writer (lambda (port val) (put-u8 port val))))
;;;
;;; (define-binary-record point
;;;   (x uint16-be)
;;;   (y uint16-be))
;;;
;;; (define-binary-array triple-byte uint8 3)

(library (std misc binary-type)
  (export
    ;; Core type definition
    define-binary-type
    ;; Composite records
    define-binary-record
    ;; Fixed-length arrays
    define-binary-array
    ;; Generic read/write dispatch
    binary-read
    binary-write
    ;; Type registry
    register-binary-type!
    ;; Built-in primitive types
    uint8 uint16-be uint16-le uint32-be uint32-le
    int8 int16-be int16-le int32-be int32-le
    float32-be float64-be)

  (import (chezscheme))

  ;; ========== Type registry ==========
  ;; Maps type name (symbol) -> (reader . writer)

  (define *binary-type-registry* (make-hashtable symbol-hash eq?))

  (define (register-binary-type! name reader writer)
    (hashtable-set! *binary-type-registry* name (cons reader writer)))

  (define (lookup-binary-type name)
    (let ([entry (hashtable-ref *binary-type-registry* name #f)])
      (unless entry
        (error 'lookup-binary-type
               (string-append "unknown binary type: " (symbol->string name))))
      entry))

  ;; ========== Generic read/write ==========

  (define (binary-read type-name port)
    (let ([entry (lookup-binary-type type-name)])
      ((car entry) port)))

  (define (binary-write type-name port val)
    (let ([entry (lookup-binary-type type-name)])
      ((cdr entry) port val)))

  ;; ========== Helper: read/write via bytevector buffer ==========

  (define (read-bv-value port size ref-proc endian)
    (let ([bv (get-bytevector-n port size)])
      (when (or (eof-object? bv) (< (bytevector-length bv) size))
        (error 'binary-read "unexpected end of input"))
      (ref-proc bv 0 endian)))

  (define (write-bv-value port val size set-proc! endian)
    (let ([bv (make-bytevector size)])
      (set-proc! bv 0 val endian)
      (put-bytevector port bv)))

  ;; ========== define-binary-type macro ==========

  (define-syntax define-binary-type
    (syntax-rules (reader writer)
      [(_ name (reader reader-expr) (writer writer-expr))
       (define name
         (let ([r reader-expr] [w writer-expr])
           (register-binary-type! 'name r w)
           'name))]))

  ;; ========== Built-in primitive types ==========

  ;; unsigned integers
  (define-binary-type uint8
    (reader (lambda (port)
              (let ([b (get-u8 port)])
                (when (eof-object? b)
                  (error 'binary-read "unexpected end of input"))
                b)))
    (writer (lambda (port val)
              (put-u8 port val))))

  (define-binary-type uint16-be
    (reader (lambda (port) (read-bv-value port 2 bytevector-u16-ref 'big)))
    (writer (lambda (port val) (write-bv-value port val 2 bytevector-u16-set! 'big))))

  (define-binary-type uint16-le
    (reader (lambda (port) (read-bv-value port 2 bytevector-u16-ref 'little)))
    (writer (lambda (port val) (write-bv-value port val 2 bytevector-u16-set! 'little))))

  (define-binary-type uint32-be
    (reader (lambda (port) (read-bv-value port 4 bytevector-u32-ref 'big)))
    (writer (lambda (port val) (write-bv-value port val 4 bytevector-u32-set! 'big))))

  (define-binary-type uint32-le
    (reader (lambda (port) (read-bv-value port 4 bytevector-u32-ref 'little)))
    (writer (lambda (port val) (write-bv-value port val 4 bytevector-u32-set! 'little))))

  ;; signed integers
  (define-binary-type int8
    (reader (lambda (port)
              (let ([b (get-u8 port)])
                (when (eof-object? b)
                  (error 'binary-read "unexpected end of input"))
                (if (> b 127) (- b 256) b))))
    (writer (lambda (port val)
              (put-u8 port (if (< val 0) (+ val 256) val)))))

  (define-binary-type int16-be
    (reader (lambda (port) (read-bv-value port 2 bytevector-s16-ref 'big)))
    (writer (lambda (port val) (write-bv-value port val 2 bytevector-s16-set! 'big))))

  (define-binary-type int16-le
    (reader (lambda (port) (read-bv-value port 2 bytevector-s16-ref 'little)))
    (writer (lambda (port val) (write-bv-value port val 2 bytevector-s16-set! 'little))))

  (define-binary-type int32-be
    (reader (lambda (port) (read-bv-value port 4 bytevector-s32-ref 'big)))
    (writer (lambda (port val) (write-bv-value port val 4 bytevector-s32-set! 'big))))

  (define-binary-type int32-le
    (reader (lambda (port) (read-bv-value port 4 bytevector-s32-ref 'little)))
    (writer (lambda (port val) (write-bv-value port val 4 bytevector-s32-set! 'little))))

  ;; floating point
  (define-binary-type float32-be
    (reader (lambda (port)
              (read-bv-value port 4 bytevector-ieee-single-ref 'big)))
    (writer (lambda (port val)
              (write-bv-value port val 4 bytevector-ieee-single-set! 'big))))

  (define-binary-type float64-be
    (reader (lambda (port)
              (read-bv-value port 8 bytevector-ieee-double-ref 'big)))
    (writer (lambda (port val)
              (write-bv-value port val 8 bytevector-ieee-double-set! 'big))))

  ;; ========== define-binary-record macro ==========
  ;;
  ;; (define-binary-record point
  ;;   (x uint16-be)
  ;;   (y uint16-be))
  ;;
  ;; Generates:
  ;;   make-point, point-x, point-y, read-point, write-point
  ;;   Registers 'point in the binary type registry.

  (define-syntax define-binary-record
    (lambda (stx)
      (syntax-case stx ()
        [(_ rec-name (field-name field-type) ...)
         (with-syntax
           ([make-rec (datum->syntax #'rec-name
                        (string->symbol
                          (string-append "make-" (symbol->string (syntax->datum #'rec-name)))))]
            [read-rec (datum->syntax #'rec-name
                        (string->symbol
                          (string-append "read-" (symbol->string (syntax->datum #'rec-name)))))]
            [write-rec (datum->syntax #'rec-name
                         (string->symbol
                           (string-append "write-" (symbol->string (syntax->datum #'rec-name)))))]
            [(accessor ...)
             (map (lambda (fn)
                    (datum->syntax #'rec-name
                      (string->symbol
                        (string-append (symbol->string (syntax->datum #'rec-name))
                                       "-"
                                       (symbol->string (syntax->datum fn))))))
                  #'(field-name ...))]
            [(idx ...)
             (let loop ([i 0] [fields #'(field-name ...)])
               (if (null? fields) '()
                   (cons (datum->syntax #'rec-name i)
                         (loop (+ i 1) (cdr fields)))))])
           #'(begin
               ;; Record type as a simple vector: #(rec-name field-val ...)
               (define (make-rec field-name ...)
                 (vector 'rec-name field-name ...))

               (define (accessor rec) (vector-ref rec (+ 1 idx))) ...

               (define (read-rec port)
                 (let* ([field-name (binary-read 'field-type port)] ...)
                   (make-rec field-name ...)))

               (define (write-rec port rec)
                 (binary-write 'field-type port (accessor rec)) ...)

               ;; Register in the type registry
               (register-binary-type! 'rec-name read-rec
                 (lambda (port val) (write-rec port val)))))])))

  ;; ========== define-binary-array macro ==========
  ;;
  ;; (define-binary-array triple-byte uint8 3)
  ;;
  ;; Generates:
  ;;   read-triple-byte, write-triple-byte
  ;;   Registers 'triple-byte in the binary type registry.
  ;;   Values are represented as vectors.

  (define-syntax define-binary-array
    (lambda (stx)
      (syntax-case stx ()
        [(_ arr-name elem-type count)
         (with-syntax
           ([read-arr (datum->syntax #'arr-name
                        (string->symbol
                          (string-append "read-" (symbol->string (syntax->datum #'arr-name)))))]
            [write-arr (datum->syntax #'arr-name
                         (string->symbol
                           (string-append "write-" (symbol->string (syntax->datum #'arr-name)))))])
           #'(begin
               (define (read-arr port)
                 (let ([n count])
                   (let ([v (make-vector n)])
                     (let loop ([i 0])
                       (when (< i n)
                         (vector-set! v i (binary-read 'elem-type port))
                         (loop (+ i 1))))
                     v)))

               (define (write-arr port vec)
                 (let ([n count])
                   (let loop ([i 0])
                     (when (< i n)
                       (binary-write 'elem-type port (vector-ref vec i))
                       (loop (+ i 1))))))

               (register-binary-type! 'arr-name read-arr
                 (lambda (port val) (write-arr port val)))))])))

) ;; end library
