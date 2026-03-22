#!chezscheme
;;; :std/srfi/160 -- Homogeneous Numeric Vectors (SRFI-160)
;;; Typed vector types implemented as wrappers over bytevectors.
;;; Supports: u8, s8, u16, s16, u32, s32, u64, s64, f32, f64.

(library (std srfi srfi-160)
  (export
    ;; u8
    make-u8vector u8vector u8vector? u8vector-length
    u8vector-ref u8vector-set! u8vector->list list->u8vector
    u8vector-copy u8vector-append
    ;; s8
    make-s8vector s8vector s8vector? s8vector-length
    s8vector-ref s8vector-set! s8vector->list list->s8vector
    s8vector-copy s8vector-append
    ;; u16
    make-u16vector u16vector u16vector? u16vector-length
    u16vector-ref u16vector-set! u16vector->list list->u16vector
    u16vector-copy u16vector-append
    ;; s16
    make-s16vector s16vector s16vector? s16vector-length
    s16vector-ref s16vector-set! s16vector->list list->s16vector
    s16vector-copy s16vector-append
    ;; u32
    make-u32vector u32vector u32vector? u32vector-length
    u32vector-ref u32vector-set! u32vector->list list->u32vector
    u32vector-copy u32vector-append
    ;; s32
    make-s32vector s32vector s32vector? s32vector-length
    s32vector-ref s32vector-set! s32vector->list list->s32vector
    s32vector-copy s32vector-append
    ;; u64
    make-u64vector u64vector u64vector? u64vector-length
    u64vector-ref u64vector-set! u64vector->list list->u64vector
    u64vector-copy u64vector-append
    ;; s64
    make-s64vector s64vector s64vector? s64vector-length
    s64vector-ref s64vector-set! s64vector->list list->s64vector
    s64vector-copy s64vector-append
    ;; f32
    make-f32vector f32vector f32vector? f32vector-length
    f32vector-ref f32vector-set! f32vector->list list->f32vector
    f32vector-copy f32vector-append
    ;; f64
    make-f64vector f64vector f64vector? f64vector-length
    f64vector-ref f64vector-set! f64vector->list list->f64vector
    f64vector-copy f64vector-append)

  (import (chezscheme))

  ;; Helper: default fill value for numeric vectors
  (define (default-fill) 0)

  ;; Macro to define all operations for one homogeneous vector type.
  ;; TAG: symbol like u8, s16, f64, etc.
  ;; BYTES: bytes per element
  ;; BV-REF: bytevector accessor (e.g., bytevector-u8-ref)
  ;; BV-SET: bytevector mutator (e.g., bytevector-u8-set!)
  ;; ENDIAN?: #t if the accessor/mutator takes an endianness argument
  (define-syntax define-homogeneous-vector-type
    (lambda (stx)
      (syntax-case stx ()
        [(_ tag bytes bv-ref bv-set endian?)
         (let* ([tag-str (symbol->string (syntax->datum #'tag))]
                [mk (lambda (prefix suffix)
                      (datum->syntax #'tag
                        (string->symbol
                          (string-append prefix tag-str suffix))))])
           (with-syntax ([rec-type    (mk "" "vector-rec")]
                         [make-rec    (mk "make-" "vector-rec")]
                         [rec?        (mk "" "vector-rec?")]
                         [rec-bv      (mk "" "vector-rec-bv")]
                         [make-tv     (mk "make-" "vector")]
                         [tv          (mk "" "vector")]
                         [tv?         (mk "" "vector?")]
                         [tv-length   (mk "" "vector-length")]
                         [tv-ref      (mk "" "vector-ref")]
                         [tv-set!     (mk "" "vector-set!")]
                         [tv->list    (mk "" "vector->list")]
                         [list->tv    (mk "list->" "vector")]
                         [tv-copy     (mk "" "vector-copy")]
                         [tv-append   (mk "" "vector-append")])
             #'(begin
                 ;; Record type wrapping a bytevector
                 (define-record-type rec-type
                   (fields (immutable bv))
                   (sealed #t)
                   (opaque #t))

                 (define (tv? x) (rec? x))

                 ;; Internal: read element from bytevector
                 (define bv-get
                   (if endian?
                     (lambda (bv idx) (bv-ref bv (* idx bytes) (native-endianness)))
                     (lambda (bv idx) (bv-ref bv (* idx bytes)))))

                 ;; Internal: write element to bytevector
                 (define bv-put!
                   (if endian?
                     (lambda (bv idx val) (bv-set bv (* idx bytes) val (native-endianness)))
                     (lambda (bv idx val) (bv-set bv (* idx bytes) val))))

                 ;; make-TAGvector: create with length and optional fill
                 (define make-tv
                   (case-lambda
                     [(len)
                      (make-tv len (default-fill))]
                     [(len fill)
                      (let ([bv (make-bytevector (* len bytes))])
                        (do ([i 0 (fx+ i 1)])
                            ((fx= i len))
                          (bv-put! bv i fill))
                        (make-rec bv))]))

                 ;; TAGvector: create from elements
                 (define (tv . elems)
                   (let* ([len (length elems)]
                          [bv (make-bytevector (* len bytes))])
                     (let loop ([i 0] [es elems])
                       (unless (null? es)
                         (bv-put! bv i (car es))
                         (loop (fx+ i 1) (cdr es))))
                     (make-rec bv)))

                 ;; TAGvector-length
                 (define (tv-length v)
                   (fx/ (bytevector-length (rec-bv v)) bytes))

                 ;; TAGvector-ref
                 (define (tv-ref v i)
                   (bv-get (rec-bv v) i))

                 ;; TAGvector-set!
                 (define (tv-set! v i val)
                   (bv-put! (rec-bv v) i val))

                 ;; TAGvector->list
                 (define tv->list
                   (case-lambda
                     [(v) (tv->list v 0 (tv-length v))]
                     [(v start) (tv->list v start (tv-length v))]
                     [(v start end)
                      (let loop ([i (fx- end 1)] [acc '()])
                        (if (fx< i start)
                          acc
                          (loop (fx- i 1) (cons (tv-ref v i) acc))))]))

                 ;; list->TAGvector
                 (define (list->tv lst)
                   (apply tv lst))

                 ;; TAGvector-copy
                 (define tv-copy
                   (case-lambda
                     [(v) (tv-copy v 0 (tv-length v))]
                     [(v start) (tv-copy v start (tv-length v))]
                     [(v start end)
                      (let* ([len (fx- end start)]
                             [bv (make-bytevector (* len bytes))])
                        (bytevector-copy! (rec-bv v) (* start bytes)
                                          bv 0
                                          (* len bytes))
                        (make-rec bv))]))

                 ;; TAGvector-append
                 (define (tv-append . vecs)
                   (let* ([lengths (map tv-length vecs)]
                          [total (apply + lengths)]
                          [bv (make-bytevector (* total bytes))])
                     (let loop ([vs vecs] [offset 0])
                       (unless (null? vs)
                         (let ([src (rec-bv (car vs))]
                               [n (bytevector-length (rec-bv (car vs)))])
                           (bytevector-copy! src 0 bv offset n)
                           (loop (cdr vs) (+ offset n)))))
                     (make-rec bv))))))])))

  ;; Integer types (no endianness argument for u8/s8)
  (define-homogeneous-vector-type u8  1 bytevector-u8-ref  bytevector-u8-set!  #f)
  (define-homogeneous-vector-type s8  1 bytevector-s8-ref  bytevector-s8-set!  #f)

  ;; Integer types with endianness
  (define-homogeneous-vector-type u16 2 bytevector-u16-ref bytevector-u16-set! #t)
  (define-homogeneous-vector-type s16 2 bytevector-s16-ref bytevector-s16-set! #t)
  (define-homogeneous-vector-type u32 4 bytevector-u32-ref bytevector-u32-set! #t)
  (define-homogeneous-vector-type s32 4 bytevector-s32-ref bytevector-s32-set! #t)
  (define-homogeneous-vector-type u64 8 bytevector-u64-ref bytevector-u64-set! #t)
  (define-homogeneous-vector-type s64 8 bytevector-s64-ref bytevector-s64-set! #t)

  ;; Floating-point types with endianness
  (define-homogeneous-vector-type f32 4 bytevector-ieee-single-ref bytevector-ieee-single-set! #t)
  (define-homogeneous-vector-type f64 8 bytevector-ieee-double-ref bytevector-ieee-double-set! #t)

) ;; end library
