#!chezscheme
;;; (std binary) — Structured binary data: packed C-struct-like layouts
;;;
;;; Define packed binary data layouts and read/write them from bytevectors.
;;; Field types: u8 u16 u32 u64 s8 s16 s32 s64 f32 f64 (bytes n) (cstring n)
;;; Byte order: controlled by *byte-order* parameter ('little or 'big).

(library (std binary)
  (export
    ;; Struct definition macro
    define-binary-struct
    binary-struct?
    binary-struct-name
    binary-struct-size
    binary-struct-fields
    ;; Reading/writing
    binary-read
    binary-write!
    binary-pack
    binary-unpack
    ;; Field type tags (for use in define-binary-struct)
    u8 u16 u32 u64
    s8 s16 s32 s64
    f32 f64
    ;; Byte order
    *byte-order*
    with-byte-order
    ;; Low-level bytevector accessors
    bv-u8-ref  bv-u8-set!
    bv-u16-ref bv-u16-set!
    bv-u32-ref bv-u32-set!
    bv-u64-ref bv-u64-set!
    bv-s8-ref  bv-s8-set!
    bv-s16-ref bv-s16-set!
    bv-s32-ref bv-s32-set!
    bv-s64-ref bv-s64-set!
    bv-f32-ref bv-f32-set!
    bv-f64-ref bv-f64-set!)

  (import (chezscheme))

  ;; ========== Byte order parameter ==========

  (define *byte-order* (make-parameter 'little))

  (define-syntax with-byte-order
    (syntax-rules ()
      [(_ order body ...)
       (parameterize ([*byte-order* order])
         body ...)]))

  ;; ========== Field type descriptors ==========
  ;; Each field type is a symbol or a tagged list.

  ;; Built-in type tags (exported as values so users can reference them)
  (define u8  'u8)
  (define u16 'u16)
  (define u32 'u32)
  (define u64 'u64)
  (define s8  's8)
  (define s16 's16)
  (define s32 's32)
  (define s64 's64)
  (define f32 'f32)
  (define f64 'f64)

  ;; Compute size in bytes for a field type
  (define (field-type-size ft)
    (cond
      [(eq? ft 'u8)  1]
      [(eq? ft 'u16) 2]
      [(eq? ft 'u32) 4]
      [(eq? ft 'u64) 8]
      [(eq? ft 's8)  1]
      [(eq? ft 's16) 2]
      [(eq? ft 's32) 4]
      [(eq? ft 's64) 8]
      [(eq? ft 'f32) 4]
      [(eq? ft 'f64) 8]
      [(and (pair? ft) (eq? (car ft) 'bytes))
       (cadr ft)]
      [(and (pair? ft) (eq? (car ft) 'cstring))
       (cadr ft)]
      [else (error 'field-type-size "unknown field type" ft)]))

  ;; ========== Binary struct registry ==========
  ;; Maps struct name (symbol) -> struct-descriptor

  (define *binary-struct-registry* (make-eq-hashtable))

  (define-record-type %binary-struct-desc
    (fields
      (immutable name)
      (immutable size)
      (immutable fields)  ;; list of (field-name field-type offset)
      (immutable reader)  ;; (bv offset) -> record
      (immutable writer)) ;; (bv offset record) -> void
    (protocol
      (lambda (new)
        (lambda (name size fields reader writer)
          (new name size fields reader writer)))))

  (define (binary-struct? x) (%binary-struct-desc? x))
  (define (binary-struct-name sd) (%binary-struct-desc-name sd))
  (define (binary-struct-size sd) (%binary-struct-desc-size sd))
  (define (binary-struct-fields sd) (%binary-struct-desc-fields sd))

  ;; Register a struct descriptor under its name
  (define (register-binary-struct! name desc)
    (hashtable-set! *binary-struct-registry* name desc))

  ;; Look up by name
  (define (lookup-binary-struct name)
    (hashtable-ref *binary-struct-registry* name #f))

  ;; ========== Low-level bytevector accessors ==========

  (define (endian) (*byte-order*))

  ;; --- u8 / s8 ---
  (define (bv-u8-ref bv offset)
    (bytevector-u8-ref bv offset))
  (define (bv-u8-set! bv offset val)
    (bytevector-u8-set! bv offset val))

  (define (bv-s8-ref bv offset)
    (bytevector-s8-ref bv offset))
  (define (bv-s8-set! bv offset val)
    (bytevector-s8-set! bv offset val))

  ;; --- u16 / s16 ---
  (define (bv-u16-ref bv offset)
    (bytevector-u16-ref bv offset (endian)))
  (define (bv-u16-set! bv offset val)
    (bytevector-u16-set! bv offset val (endian)))

  (define (bv-s16-ref bv offset)
    (bytevector-s16-ref bv offset (endian)))
  (define (bv-s16-set! bv offset val)
    (bytevector-s16-set! bv offset val (endian)))

  ;; --- u32 / s32 ---
  (define (bv-u32-ref bv offset)
    (bytevector-u32-ref bv offset (endian)))
  (define (bv-u32-set! bv offset val)
    (bytevector-u32-set! bv offset val (endian)))

  (define (bv-s32-ref bv offset)
    (bytevector-s32-ref bv offset (endian)))
  (define (bv-s32-set! bv offset val)
    (bytevector-s32-set! bv offset val (endian)))

  ;; --- u64 / s64 ---
  (define (bv-u64-ref bv offset)
    (bytevector-u64-ref bv offset (endian)))
  (define (bv-u64-set! bv offset val)
    (bytevector-u64-set! bv offset val (endian)))

  (define (bv-s64-ref bv offset)
    (bytevector-s64-ref bv offset (endian)))
  (define (bv-s64-set! bv offset val)
    (bytevector-s64-set! bv offset val (endian)))

  ;; --- f32 / f64 ---
  (define (bv-f32-ref bv offset)
    (bytevector-ieee-single-ref bv offset (endian)))
  (define (bv-f32-set! bv offset val)
    (bytevector-ieee-single-set! bv offset val (endian)))

  (define (bv-f64-ref bv offset)
    (bytevector-ieee-double-ref bv offset (endian)))
  (define (bv-f64-set! bv offset val)
    (bytevector-ieee-double-set! bv offset val (endian)))

  ;; ========== Low-level field read/write ==========

  (define (read-field bv offset ft)
    (cond
      [(eq? ft 'u8)  (bv-u8-ref  bv offset)]
      [(eq? ft 'u16) (bv-u16-ref bv offset)]
      [(eq? ft 'u32) (bv-u32-ref bv offset)]
      [(eq? ft 'u64) (bv-u64-ref bv offset)]
      [(eq? ft 's8)  (bv-s8-ref  bv offset)]
      [(eq? ft 's16) (bv-s16-ref bv offset)]
      [(eq? ft 's32) (bv-s32-ref bv offset)]
      [(eq? ft 's64) (bv-s64-ref bv offset)]
      [(eq? ft 'f32) (bv-f32-ref bv offset)]
      [(eq? ft 'f64) (bv-f64-ref bv offset)]
      [(and (pair? ft) (eq? (car ft) 'bytes))
       (let ([n (cadr ft)])
         (let ([result (make-bytevector n)])
           (bytevector-copy! bv offset result 0 n)
           result))]
      [(and (pair? ft) (eq? (car ft) 'cstring))
       (let ([max-n (cadr ft)])
         ;; Read until null byte or max-n bytes
         (let loop ([i 0] [chars '()])
           (if (or (= i max-n)
                   (= (bytevector-u8-ref bv (+ offset i)) 0))
             (list->string (reverse chars))
             (loop (+ i 1)
                   (cons (integer->char (bytevector-u8-ref bv (+ offset i)))
                         chars)))))]
      [else (error 'read-field "unknown field type" ft)]))

  (define (write-field! bv offset ft val)
    (cond
      [(eq? ft 'u8)  (bv-u8-set!  bv offset val)]
      [(eq? ft 'u16) (bv-u16-set! bv offset val)]
      [(eq? ft 'u32) (bv-u32-set! bv offset val)]
      [(eq? ft 'u64) (bv-u64-set! bv offset val)]
      [(eq? ft 's8)  (bv-s8-set!  bv offset val)]
      [(eq? ft 's16) (bv-s16-set! bv offset val)]
      [(eq? ft 's32) (bv-s32-set! bv offset val)]
      [(eq? ft 's64) (bv-s64-set! bv offset val)]
      [(eq? ft 'f32) (bv-f32-set! bv offset val)]
      [(eq? ft 'f64) (bv-f64-set! bv offset val)]
      [(and (pair? ft) (eq? (car ft) 'bytes))
       (let ([n (cadr ft)])
         (bytevector-copy! val 0 bv offset (min n (bytevector-length val))))]
      [(and (pair? ft) (eq? (car ft) 'cstring))
       (let* ([max-n (cadr ft)]
              [s     (if (string? val) val (error 'write-field! "expected string for cstring" val))]
              [bvs   (string->utf8 s)]
              [len   (min (bytevector-length bvs) (- max-n 1))])
         (bytevector-copy! bvs 0 bv offset len)
         ;; null-terminate
         (bytevector-u8-set! bv (+ offset len) 0)
         ;; zero remaining bytes
         (let loop ([i (+ len 1)])
           (when (< i max-n)
             (bytevector-u8-set! bv (+ offset i) 0)
             (loop (+ i 1)))))]
      [else (error 'write-field! "unknown field type" ft)]))

  ;; ========== binary-read / binary-write! ==========

  ;; (binary-read bv offset struct-type) -> record (association list)
  (define (binary-read bv offset struct-type)
    (let ([desc (cond
                  [(symbol? struct-type)
                   (or (lookup-binary-struct struct-type)
                       (error 'binary-read "unknown struct type" struct-type))]
                  [(%binary-struct-desc? struct-type) struct-type]
                  [else (error 'binary-read "expected struct name or descriptor" struct-type)])])
      ((%binary-struct-desc-reader desc) bv offset)))

  ;; (binary-write! bv offset record)
  ;; record must be an alist (as returned by binary-read), tagged with struct name
  (define (binary-write! bv offset record)
    (unless (and (pair? record) (symbol? (car record)))
      (error 'binary-write! "expected a tagged record alist" record))
    (let* ([sname (car record)]
           [desc  (or (lookup-binary-struct sname)
                      (error 'binary-write! "unknown struct type" sname))])
      ((%binary-struct-desc-writer desc) bv offset record)))

  ;; ========== binary-pack ==========
  ;; Pack field values into a fresh bytevector.
  ;; (binary-pack struct-type field-val ...) -> bytevector
  (define (binary-pack struct-type . field-vals)
    (let* ([desc (cond
                   [(symbol? struct-type)
                    (or (lookup-binary-struct struct-type)
                        (error 'binary-pack "unknown struct type" struct-type))]
                   [(%binary-struct-desc? struct-type) struct-type]
                   [else (error 'binary-pack "expected struct name or descriptor" struct-type)])]
           [size (%binary-struct-desc-size desc)]
           [fields (%binary-struct-desc-fields desc)]
           [bv   (make-bytevector size 0)])
      (let loop ([flds fields] [vals field-vals])
        (when (pair? flds)
          (let* ([fld    (car flds)]
                 [fname  (car fld)]
                 [ftype  (cadr fld)]
                 [foff   (caddr fld)]
                 [val    (if (pair? vals) (car vals)
                             (error 'binary-pack "not enough field values"))])
            (write-field! bv foff ftype val)
            (loop (cdr flds) (if (pair? vals) (cdr vals) '())))))
      bv))

  ;; ========== binary-unpack ==========
  ;; Read each field from bytevector, return as multiple values.
  ;; (binary-unpack struct-type bv [offset]) -> values
  (define (binary-unpack struct-type bv . offset-opt)
    (let* ([offset (if (pair? offset-opt) (car offset-opt) 0)]
           [desc (cond
                   [(symbol? struct-type)
                    (or (lookup-binary-struct struct-type)
                        (error 'binary-unpack "unknown struct type" struct-type))]
                   [(%binary-struct-desc? struct-type) struct-type]
                   [else (error 'binary-unpack "expected struct name or descriptor" struct-type)])]
           [fields (%binary-struct-desc-fields desc)])
      (apply values
             (map (lambda (fld)
                    (read-field bv (+ offset (caddr fld)) (cadr fld)))
                  fields))))

  ;; ========== define-binary-struct macro ==========
  ;;
  ;; (define-binary-struct Point
  ;;   (x f32)
  ;;   (y f32))
  ;;
  ;; Generates:
  ;;   - A descriptor registered in *binary-struct-registry*
  ;;   - read-Point  : (bv offset) -> tagged alist
  ;;   - write-Point! : (bv offset record) -> void
  ;;   - pack-Point  : (field-vals ...) -> bv
  ;;   - unpack-Point: (bv [offset]) -> values

  (define-syntax define-binary-struct
    (lambda (stx)
      (syntax-case stx ()
        [(_ Name (field-name field-type) ...)
         (identifier? #'Name)
         (with-syntax
           ([read-Name    (datum->syntax #'Name
                            (string->symbol (string-append "read-"
                              (symbol->string (syntax->datum #'Name)))))]
            [write-Name!  (datum->syntax #'Name
                            (string->symbol (string-append "write-"
                              (symbol->string (syntax->datum #'Name)) "!")))]
            [pack-Name    (datum->syntax #'Name
                            (string->symbol (string-append "pack-"
                              (symbol->string (syntax->datum #'Name)))))]
            [unpack-Name  (datum->syntax #'Name
                            (string->symbol (string-append "unpack-"
                              (symbol->string (syntax->datum #'Name)))))])
           #'(begin
               ;; Compute offsets at macro-expansion time via runtime helper
               (define %name-sym 'Name)

               (define %fields-info
                 ;; Build list of (field-name field-type offset) at runtime
                 (let loop ([fnames '(field-name ...)]
                             [ftypes '(field-type ...)]
                             [offset 0]
                             [acc    '()])
                   (if (null? fnames)
                     (reverse acc)
                     (let* ([ft   (car ftypes)]
                            [sz   (field-type-size ft)]
                            [next (+ offset sz)])
                       (loop (cdr fnames)
                             (cdr ftypes)
                             next
                             (cons (list (car fnames) ft offset) acc))))))

               (define %total-size
                 (apply + (map field-type-size '(field-type ...))))

               ;; Reader: returns tagged alist (Name (field-name . val) ...)
               (define (read-Name bv offset)
                 (cons %name-sym
                       (map (lambda (fld)
                              (cons (car fld)
                                    (read-field bv (+ offset (caddr fld)) (cadr fld))))
                            %fields-info)))

               ;; Writer: takes tagged alist, writes fields
               (define (write-Name! bv offset record)
                 (for-each
                   (lambda (fld)
                     (let ([val (cdr (assq (car fld) (cdr record)))])
                       (write-field! bv (+ offset (caddr fld)) (cadr fld) val)))
                   %fields-info))

               ;; Pack: positional field values -> bytevector
               (define (pack-Name . vals)
                 (let ([bv (make-bytevector %total-size 0)])
                   (let loop ([flds %fields-info] [vs vals])
                     (when (pair? flds)
                       (write-field! bv (caddr (car flds)) (cadr (car flds)) (car vs))
                       (loop (cdr flds) (cdr vs))))
                   bv))

               ;; Unpack: bytevector [offset] -> multiple values
               (define (unpack-Name bv . off-opt)
                 (let ([base (if (pair? off-opt) (car off-opt) 0)])
                   (apply values
                          (map (lambda (fld)
                                 (read-field bv (+ base (caddr fld)) (cadr fld)))
                               %fields-info))))

               ;; Register struct descriptor
               (register-binary-struct!
                 %name-sym
                 (make-%binary-struct-desc
                   %name-sym
                   %total-size
                   %fields-info
                   read-Name
                   (lambda (bv offset record) (write-Name! bv offset record))))))])))

) ;; end library
