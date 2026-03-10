#!chezscheme
;;; (std foreign) — Zero-overhead FFI DSL for Chez Scheme
;;;
;;; Eliminates boilerplate from chez-* FFI libraries with declarative macros:
;;;   define-ffi-library  — load shared objects + bind foreign procedures
;;;   define-foreign      — single foreign-procedure binding with type mapping
;;;   define-foreign/check — foreign-procedure + automatic error checking
;;;   define-const        — fetch C #define constants at load time
;;;   define-foreign-type — pointer type with GC-triggered destructor
;;;   with-foreign-resource — deterministic cleanup via dynamic-wind
;;;   define-callback     — Scheme→C callback with GC safety

(library (std foreign)
  (export
    define-ffi-library
    define-foreign
    define-foreign/check
    define-const
    define-foreign-type
    define-foreign-struct
    with-foreign-resource
    define-callback
    -> ;; auxiliary keyword for define-foreign syntax
    ;; Re-export essentials from Chez for convenience
    foreign-alloc foreign-free foreign-ref foreign-set!
    foreign-sizeof
    load-shared-object
    ;; Guardian-based cleanup
    start-guardian-thread! stop-guardian-thread!)
  (import (chezscheme))

  ;; Auxiliary keyword for arrow syntax in define-foreign
  (define-syntax -> (lambda (x) (syntax-violation '-> "misplaced auxiliary keyword" x)))

  ;; ========== Type Mapping ==========

  ;; Translate user-friendly types to Chez foreign types at expand time
  (meta define (translate-type type)
    (case type
      ;; Integer types
      [(int)                'int]
      [(unsigned-int uint)  'unsigned]
      [(int8)               'integer-8]
      [(uint8)              'unsigned-8]
      [(int16)              'integer-16]
      [(uint16)             'unsigned-16]
      [(int32)              'integer-32]
      [(uint32)             'unsigned-32]
      [(int64)              'integer-64]
      [(uint64)             'unsigned-64]
      [(size_t size-t)      'size_t]
      [(ssize_t ssize-t)    'ssize_t]
      [(short)              'short]
      [(unsigned-short)     'unsigned-short]
      [(long)               'long]
      [(unsigned-long)      'unsigned-long]
      ;; Float types
      [(float)              'float]
      [(double)             'double]
      [(double-float)       'double-float]
      ;; Other types
      [(char)               'char]
      [(wchar wchar_t)      'wchar]
      [(bool boolean)       'boolean]
      [(void)               'void]
      [(string char* nonnull-char-string char-string) 'string]
      [(u8* u8vector)       'u8*]
      [(void* ptr pointer)  'void*]
      [(scheme-object)      'scheme-object]
      [else
       ;; Pass through — may already be a Chez type
       type]))

  ;; ========== define-foreign ==========
  ;;
  ;; (define-foreign name c-name (arg-types ...) -> ret-type)
  ;; (define-foreign name (arg-types ...) -> ret-type)  ; c-name = scheme name
  ;;
  ;; Expands to: (define name (foreign-procedure "c_name" (chez-types ...) chez-ret))

  (define-syntax define-foreign
    (lambda (stx)
      (syntax-case stx (->)
        ;; With explicit C name
        [(k name c-name (arg-type ...) -> ret-type)
         (string? (syntax->datum #'c-name))
         (let ([chez-args (map (lambda (t) (translate-type (syntax->datum t)))
                               (syntax->list #'(arg-type ...)))]
               [chez-ret (translate-type (syntax->datum #'ret-type))])
           (with-syntax ([(ct ...) (datum->syntax #'k chez-args)]
                         [rt (datum->syntax #'k chez-ret)])
             #'(define name (foreign-procedure c-name (ct ...) rt))))]
        ;; No C name — derive from scheme name
        [(k name (arg-type ...) -> ret-type)
         (identifier? #'name)
         (let ([c-name (symbol->string (syntax->datum #'name))])
           (with-syntax ([cn (datum->syntax #'k c-name)])
             #'(define-foreign name cn (arg-type ...) -> ret-type)))])))

  ;; ========== define-foreign/check ==========
  ;;
  ;; (define-foreign/check name c-name (arg-types ...) -> ret-type
  ;;   (check: pred)
  ;;   (error: handler))
  ;;
  ;; Like define-foreign but wraps the call: if (pred result) is #f, call (handler result).
  ;; If no error: clause, raises a generic error.

  (define-syntax define-foreign/check
    (lambda (stx)
      (define (kw? stx sym)
        (and (identifier? stx)
             (eq? (syntax->datum stx) sym)))
      (syntax-case stx (->)
        ;; With both check and error
        [(k name c-name (arg-type ...) -> ret-type
            (check-kw check-pred)
            (error-kw error-handler))
         (and (string? (syntax->datum #'c-name))
              (kw? #'check-kw 'check:)
              (kw? #'error-kw 'error:))
         (let ([chez-args (map (lambda (t) (translate-type (syntax->datum t)))
                               (syntax->list #'(arg-type ...)))]
               [chez-ret (translate-type (syntax->datum #'ret-type))])
           (with-syntax ([(ct ...) (datum->syntax #'k chez-args)]
                         [rt (datum->syntax #'k chez-ret)]
                         [(param ...) (generate-temporaries #'(arg-type ...))])
             #'(define (name param ...)
                 (let ([rc ((foreign-procedure c-name (ct ...) rt) param ...)])
                   (if (check-pred rc)
                     rc
                     (error-handler rc))))))]
        ;; Check only, generic error
        [(k name c-name (arg-type ...) -> ret-type
            (check-kw check-pred))
         (and (string? (syntax->datum #'c-name))
              (kw? #'check-kw 'check:))
         (let ([chez-args (map (lambda (t) (translate-type (syntax->datum t)))
                               (syntax->list #'(arg-type ...)))]
               [chez-ret (translate-type (syntax->datum #'ret-type))]
               [who (syntax->datum #'name)]
               [cn (syntax->datum #'c-name)])
           (with-syntax ([(ct ...) (datum->syntax #'k chez-args)]
                         [rt (datum->syntax #'k chez-ret)]
                         [(param ...) (generate-temporaries #'(arg-type ...))]
                         [who-sym (datum->syntax #'k who)]
                         [msg (datum->syntax #'k (format "FFI call ~a failed" cn))])
             #'(define (name param ...)
                 (let ([rc ((foreign-procedure c-name (ct ...) rt) param ...)])
                   (if (check-pred rc)
                     rc
                     (error 'who-sym msg rc))))))])))

  ;; ========== define-const ==========
  ;;
  ;; (define-const NAME type)
  ;; (define-const NAME type c-name)
  ;;
  ;; Fetches a C constant at library load time via a zero-arg foreign-procedure.
  ;; The C shim must expose a `chez_CONSTNAME() -> type` function.

  (define-syntax define-const
    (lambda (stx)
      (syntax-case stx ()
        ;; Explicit C accessor name
        [(k name type c-name)
         (string? (syntax->datum #'c-name))
         (let ([chez-ret (translate-type (syntax->datum #'type))])
           (with-syntax ([rt (datum->syntax #'k chez-ret)])
             #'(define name ((foreign-procedure c-name () rt)))))]
        ;; Auto-derive: NAME -> "chez_NAME"
        [(k name type)
         (identifier? #'name)
         (let ([c-name (string-append "chez_" (symbol->string (syntax->datum #'name)))])
           (with-syntax ([cn (datum->syntax #'k c-name)])
             #'(define-const name type cn)))])))

  ;; ========== define-ffi-library ==========
  ;;
  ;; (define-ffi-library lib-name "shared-object.so"
  ;;   (define-const ...)
  ;;   (define-foreign ...)
  ;;   (define-foreign/check ...))
  ;;
  ;; Wraps shared-object loading around a body of FFI definitions.
  ;; Accepts one or more shared object paths.

  (define-syntax define-ffi-library
    (lambda (stx)
      (syntax-case stx ()
        ;; Single shared-object string
        [(k lib-name shared-obj body ...)
         (string? (syntax->datum #'shared-obj))
         #'(begin
             (define lib-name (load-shared-object shared-obj))
             body ...)]
        ;; Multiple shared-object strings in a list
        [(k lib-name (shared-obj ...) body ...)
         (for-all (lambda (s) (string? (syntax->datum s)))
                  (syntax->list #'(shared-obj ...)))
         (with-syntax ([(loader ...)
                        (map (lambda (s i)
                               (with-syntax ([s s]
                                             [id (datum->syntax #'k
                                                   (string->symbol
                                                     (format "_lib~a" i)))])
                                 #'(define id (load-shared-object s))))
                             (syntax->list #'(shared-obj ...))
                             (iota (length (syntax->list #'(shared-obj ...)))))])
           #'(begin
               loader ...
               (define lib-name (void))
               body ...))])))

  ;; ========== Resource Management ==========

  ;; Guardian for pointer types with destructors
  (define *ffi-guardian* (make-guardian))
  (define *guardian-thread* #f)
  (define *guardian-running* #f)

  ;; Register a pointer with its destructor
  (define (register-destructor! ptr destructor)
    (*ffi-guardian* (cons ptr destructor)))

  ;; Run the guardian, calling destructors for GC'd pointers
  (define (run-guardian!)
    (let loop ()
      (let ([entry (*ffi-guardian*)])
        (when entry
          (let ([ptr (car entry)]
                [dtor (cdr entry)])
            (guard (exn [#t (void)])  ;; don't crash on destructor errors
              (dtor ptr)))
          (loop)))))

  ;; Start a background thread that periodically runs the guardian
  (define (start-guardian-thread!)
    (unless *guardian-running*
      (set! *guardian-running* #t)
      (set! *guardian-thread*
        (fork-thread
          (lambda ()
            (let loop ()
              (sleep (make-time 'time-duration 0 1))  ;; every 1 second
              (run-guardian!)
              (when *guardian-running*
                (loop))))))))

  ;; Stop the guardian thread
  (define (stop-guardian-thread!)
    (set! *guardian-running* #f))

  ;; ========== define-foreign-type ==========
  ;;
  ;; (define-foreign-type type-name void*
  ;;   (destructor: cleanup-proc))
  ;;
  ;; Creates a wrapped pointer type. When the pointer becomes unreachable,
  ;; the destructor is called by the guardian thread.
  ;; Returns the raw pointer for FFI compatibility.

  (define-syntax define-foreign-type
    (lambda (stx)
      (syntax-case stx ()
        [(_ type-name base-type (dtor-kw dtor))
         (eq? (syntax->datum #'dtor-kw) 'destructor:)
         #'(begin
             (define (type-name ptr)
               (register-destructor! ptr dtor)
               ptr))]
        [(_ type-name base-type)
         #'(define (type-name ptr) ptr)])))

  ;; ========== with-foreign-resource ==========
  ;;
  ;; (with-foreign-resource (var expr cleanup-proc) body ...)
  ;;
  ;; Deterministic cleanup: runs cleanup-proc on scope exit (normal or exception).

  (define-syntax with-foreign-resource
    (syntax-rules ()
      [(_ (var expr cleanup) body ...)
       (let ([var expr])
         (dynamic-wind
           void
           (lambda () body ...)
           (lambda () (cleanup var))))]))

  ;; ========== define-callback ==========
  ;;
  ;; (define-callback name (arg-types ... -> ret-type) proc)
  ;;
  ;; Creates a GC-safe C-callable function pointer from a Scheme procedure.
  ;; The code address is locked so GC won't move it.

  (define-syntax define-callback
    (lambda (stx)
      (syntax-case stx (->)
        [(k name (arg-type ... -> ret-type) proc)
         (let ([chez-args (map (lambda (t) (translate-type (syntax->datum t)))
                               (syntax->list #'(arg-type ...)))]
               [chez-ret (translate-type (syntax->datum #'ret-type))])
           (with-syntax ([(ct ...) (datum->syntax #'k chez-args)]
                         [rt (datum->syntax #'k chez-ret)])
             #'(begin
                 (define name
                   (let ([cb (foreign-callable proc (ct ...) rt)])
                     (lock-object cb)
                     (foreign-callable-entry-point cb))))))])))

  ;; ========== define-foreign-struct ==========
  ;;
  ;; (define-foreign-struct name
  ;;   (field-name type offset: N) ...)
  ;;
  ;; Generates accessor and mutator procedures for C struct fields
  ;; at known byte offsets. Operates on raw void* pointers.

  (define-syntax define-foreign-struct
    (lambda (stx)
      (define (parse-field f)
        (syntax-case f ()
          [(name type offset-kw off)
           (eq? (syntax->datum #'offset-kw) 'offset:)
           (list #'name (translate-type (syntax->datum #'type)) #'off)]))
      (define (field-names f)
        (syntax-case f ()
          [(name type offset-kw off)
           (syntax->datum #'name)]))
      (syntax-case stx ()
        [(k struct-name field ...)
         (let ([parsed (map parse-field (syntax->list #'(field ...)))])
           (with-syntax ([((getter setter ftype-sym foffset) ...)
                          (map (lambda (f)
                                 (let ([sname (syntax->datum #'struct-name)]
                                       [fn (syntax->datum (car f))]
                                       [ft (cadr f)]
                                       [fo (caddr f)])
                                   (list (datum->syntax #'k
                                           (string->symbol (format "~a-~a" sname fn)))
                                         (datum->syntax #'k
                                           (string->symbol (format "~a-~a-set!" sname fn)))
                                         (datum->syntax #'k ft)
                                         fo)))
                               parsed)])
             #'(begin
                 (define (getter ptr) (foreign-ref 'ftype-sym ptr foffset)) ...
                 (define (setter ptr val) (foreign-set! 'ftype-sym ptr foffset val)) ...)))])))

  ) ;; end library
