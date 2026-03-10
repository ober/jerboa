#!chezscheme
;;; jerboa/ffi -- FFI translation macros
;;;
;;; Translates Gerbil/Gambit FFI forms to Chez Scheme equivalents:
;;;   c-lambda      → foreign-procedure
;;;   c-declare     → load-shared-object + foreign-procedure
;;;   define-c-lambda → named foreign-procedure binding
;;;   begin-ffi     → begin with FFI body
;;;
;;; Type mapping: Gambit FFI types → Chez foreign types

(library (jerboa ffi)
  (export c-lambda define-c-lambda
          begin-ffi c-declare
          ffi-type-map
          load-shared-object*)
  (import (chezscheme))

  ;; FFI type translation: Gambit/Gerbil type → Chez type
  ;; Used at expand time by macros
  (meta define (translate-ffi-type type)
    (case type
      [(int) 'int]
      [(unsigned-int unsigned) 'unsigned]
      [(int8) 'integer-8]
      [(unsigned-int8 uint8) 'unsigned-8]
      [(int16) 'integer-16]
      [(unsigned-int16 uint16) 'unsigned-16]
      [(int32) 'integer-32]
      [(unsigned-int32 uint32) 'unsigned-32]
      [(int64) 'integer-64]
      [(unsigned-int64 uint64) 'unsigned-64]
      [(float) 'float]
      [(double) 'double]
      [(char) 'char]
      [(bool boolean) 'boolean]
      [(void) 'void]
      [(char-string nonnull-char-string char* nonnull-char*) 'string]
      [(scheme-object) 'scheme-object]
      [(size-t) 'size_t]
      [(ssize-t) 'ssize_t]
      [(short) 'short]
      [(unsigned-short) 'unsigned-short]
      [(long) 'long]
      [(unsigned-long) 'unsigned-long]
      [else
       ;; Handle pointer types
       (if (and (pair? type) (eq? (car type) 'pointer))
         'void*
         (if (and (pair? type) (eq? (car type) 'nonnull-pointer))
           'void*
           ;; Pass through — may be a Chez type already
           type))]))

  ;; Runtime helper: load-shared-object with search
  (define (load-shared-object* name)
    (load-shared-object name))

  ;; Type mapping table for runtime use
  (define ffi-type-map
    '((int . int)
      (unsigned-int . unsigned)
      (int64 . integer-64)
      (uint64 . unsigned-64)
      (double . double)
      (float . float)
      (bool . boolean)
      (char-string . string)
      (nonnull-char-string . string)
      (void . void)
      (scheme-object . scheme-object)
      (size-t . size_t)))

  ;; c-lambda: inline FFI call
  ;; (c-lambda (arg-types ...) ret-type "c_function_name")
  ;; → (foreign-procedure "c_function_name" (chez-types ...) chez-ret-type)
  (define-syntax c-lambda
    (lambda (stx)
      (syntax-case stx ()
        [(k (arg-type ...) ret-type c-name)
         (string? (syntax->datum #'c-name))
         (let ([chez-arg-types (map (lambda (t) (translate-ffi-type (syntax->datum t)))
                                    (syntax->list #'(arg-type ...)))]
               [chez-ret-type (translate-ffi-type (syntax->datum #'ret-type))])
           (with-syntax ([(ct ...) (datum->syntax #'k chez-arg-types)]
                         [rt (datum->syntax #'k chez-ret-type)])
             #'(foreign-procedure c-name (ct ...) rt)))])))

  ;; define-c-lambda: named FFI binding
  ;; (define-c-lambda name (arg-types ...) ret-type "c_func")
  ;; → (define name (foreign-procedure "c_func" ...))
  (define-syntax define-c-lambda
    (lambda (stx)
      (syntax-case stx ()
        [(k name (arg-type ...) ret-type c-name)
         #'(define name (c-lambda (arg-type ...) ret-type c-name))]
        ;; Shorthand: use the scheme name as the C name
        [(k name (arg-type ...) ret-type)
         (identifier? #'name)
         (let ([c-name-str (symbol->string (syntax->datum #'name))])
           (with-syntax ([cn (datum->syntax #'k c-name-str)])
             #'(define name (c-lambda (arg-type ...) ret-type cn))))])))

  ;; begin-ffi: wrapper for FFI declarations
  ;; (begin-ffi (exported-names ...) body ...)
  ;; → (begin body ...)
  ;; In Gerbil, begin-ffi compiles C code; in Chez we rely on
  ;; pre-compiled shared objects loaded via load-shared-object
  (define-syntax begin-ffi
    (syntax-rules ()
      [(_ (export-name ...) body ...)
       (begin body ...)]
      [(_ body ...)
       (begin body ...)]))

  ;; c-declare: C code declarations
  ;; In Gerbil/Gambit, this embeds C code. In Chez, C code must be
  ;; pre-compiled to a shared library. This macro is a no-op but
  ;; serves as documentation of what C code is expected.
  (define-syntax c-declare
    (syntax-rules ()
      [(_ c-code)
       (void)]))

  ) ;; end library
