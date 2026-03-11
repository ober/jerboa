#!chezscheme
;;; (std foreign bind) — Fearless FFI: organized C bindings with safety
;;;
;;; Step 19: define-c-library — organize C FFI bindings under a namespace,
;;;          optionally load a shared library, map C types to Chez types.
;;;          load-c-header — parse a simple C header and extract signatures.
;;;
;;; Step 20: defstruct/foreign — ownership-tracked foreign pointer structs.
;;;          Guardian-based GC cleanup, use-after-free detection.
;;;
;;; Step 21: define-foreign/async — run blocking FFI calls on a thread pool,
;;;          suspending the calling thread non-destructively.
;;;
;;; API:
;;;   ;; Step 19
;;;   (define-c-library name
;;;     [(shared-lib "name.so")]
;;;     (bind sym (c-type ...) -> c-type) ...)
;;;
;;;   (load-c-header "file.h")  ; parse simple C function decls
;;;   (c-type->ffi-type sym)    ; map C type name to Chez FFI type
;;;
;;;   ;; Step 20
;;;   (defstruct/foreign name
;;;     (field ...)
;;;     (destructor proc))
;;;   (with-foreign ([var init]) body ...)
;;;   (foreign-ptr-valid? fp)
;;;   (foreign-ptr-free! fp)
;;;
;;;   ;; Step 21
;;;   (define-foreign/async name (c-lambda ...) [#:blocking #t])
;;;   (make-ffi-thread-pool [n-workers])

(library (std foreign bind)
  (export
    ;; Step 19: C Library organization
    define-c-library
    c-type->ffi-type
    parse-c-signature
    load-c-header

    ;; Step 20: Ownership tracking
    make-managed-ptr
    defstruct/foreign
    foreign-ptr?
    foreign-ptr-value
    foreign-ptr-valid?
    foreign-ptr-free!
    with-foreign

    ;; Step 21: Async FFI
    define-foreign/async
    make-ffi-thread-pool
    ffi-thread-pool-call
    ffi-thread-pool-shutdown!)

  (import (chezscheme))

  ;; ========== Step 19: C Library Organization ==========
  ;;
  ;; (define-c-library name
  ;;   [(shared-lib "libname.so")]
  ;;   (bind scheme-name (c-arg-type ...) -> c-ret-type) ...)
  ;;
  ;; Expands to:
  ;;   - Optionally loads the shared library
  ;;   - Defines each binding as a `foreign-procedure` call
  ;;
  ;; C type name → Chez FFI type mapping:

  ;; Runtime c-type->ffi-type (exported for user code).
  ;; The macro uses an inlined version to avoid phase issues.
  (define *c-type-map-runtime*
    '((int       . int)
      (long      . long)
      (unsigned  . unsigned-int)
      (size_t    . size_t)
      (ssize_t   . ssize_t)
      (uint8_t   . unsigned-8)
      (uint16_t  . unsigned-16)
      (uint32_t  . unsigned-32)
      (uint64_t  . unsigned-64)
      (int8_t    . integer-8)
      (int16_t   . integer-16)
      (int32_t   . integer-32)
      (int64_t   . integer-64)
      (float     . float)
      (double    . double)
      (char*     . string)
      (string    . string)
      (void*     . uptr)
      (uptr      . uptr)
      (pointer   . uptr)
      (bool      . boolean)
      (void      . void)))

  (define (c-type->ffi-type sym)
    (let ([entry (assq sym *c-type-map-runtime*)])
      (if entry (cdr entry) sym)))

  ;; (define-c-library name clause ...)
  (define-syntax define-c-library
    (lambda (stx)
      ;; Inline type mapping so no external phase-1 references needed.
      (define local-c-map
        '((int       . int)
          (long      . long)
          (unsigned  . unsigned-int)
          (size_t    . size_t)
          (ssize_t   . ssize_t)
          (uint8_t   . unsigned-8)
          (uint16_t  . unsigned-16)
          (uint32_t  . unsigned-32)
          (uint64_t  . unsigned-64)
          (int8_t    . integer-8)
          (int16_t   . integer-16)
          (int32_t   . integer-32)
          (int64_t   . integer-64)
          (float     . float)
          (double    . double)
          (char*     . string)
          (string    . string)
          (void*     . uptr)
          (uptr      . uptr)
          (pointer   . uptr)
          (bool      . boolean)
          (void      . void)))
      (define (local-map-type sym)
        (let ([e (assq sym local-c-map)])
          (if e (cdr e) sym)))
      (syntax-case stx (shared-lib)
        [(_ lib-name clause ...)
         (let* ([clauses (syntax->list #'(clause ...))]
                [shared-lib-clause
                 (let loop ([cs clauses])
                   (if (null? cs) #f
                     (syntax-case (car cs) (shared-lib)
                       [(shared-lib name) (car cs)]
                       [_ (loop (cdr cs))])))]
                [bind-clauses
                 (filter
                   (lambda (c)
                     (let ([d (syntax->datum c)])
                       (and (pair? d) (eq? (car d) 'bind))))
                   clauses)])
           (with-syntax
             ([lib-load
               (if shared-lib-clause
                 (syntax-case shared-lib-clause (shared-lib)
                   [(shared-lib so-name)
                    #'(guard (exn [#t (void)])
                        (load-shared-object so-name))])
                 ;; No shared-lib: load process symbols (gives access to libc etc.)
                 #'(guard (exn [#t (void)])
                     (load-shared-object #f)))]
              [(binding ...)
               (map (lambda (c)
                      ;; Pre-filtered to bind clauses; use wildcards to avoid
                      ;; free-identifier=? mismatches across library boundaries.
                      (syntax-case c ()
                        [(_ scm-name (arg-type ...) _arrow ret-type)
                         (let ([c-name  (symbol->string (syntax->datum #'scm-name))]
                               [ffi-args (map (lambda (t)
                                               (local-map-type (syntax->datum t)))
                                             (syntax->list #'(arg-type ...)))]
                               [ffi-ret  (local-map-type (syntax->datum #'ret-type))])
                           (with-syntax
                             ([c-name-str c-name]
                              [(ffi-arg ...) (map (lambda (t)
                                                    (datum->syntax #'scm-name t))
                                                  ffi-args)]
                              [ffi-ret-stx  (datum->syntax #'scm-name ffi-ret)])
                             #'(define scm-name
                                 (foreign-procedure c-name-str (ffi-arg ...) ffi-ret-stx))))]))
                    bind-clauses)])
             #'(begin
                 lib-load
                 binding ...)))])))

  ;; ========== load-c-header: simple C header parsing ==========
  ;;
  ;; Parses a C header file for simple function declarations.
  ;; Returns a list of (name arg-types ret-type) triples.
  ;; Handles: "ret_type name(arg_type arg, ...)"
  ;; Limitations: no preprocessor, no complex types, no function pointers.

  ;; Helpers (defined first to avoid forward-reference issues in Chez)
  (define (%str-contains haystack needle)
    (let ([hlen (string-length haystack)]
          [nlen (string-length needle)])
      (let loop ([i 0])
        (cond
          [(> (+ i nlen) hlen) #f]
          [(string=? (substring haystack i (+ i nlen)) needle) i]
          [else (loop (+ i 1))]))))

  (define (%str-trim s)
    (let* ([n (string-length s)]
           [start (let loop ([i 0])
                    (if (or (= i n) (not (char-whitespace? (string-ref s i))))
                      i (loop (+ i 1))))]
           [end (let loop ([i (- n 1)])
                  (if (or (< i start) (not (char-whitespace? (string-ref s i))))
                    (+ i 1) (loop (- i 1))))])
      (substring s start end)))

  (define (%str-split str delim)
    (let ([dlen (string-length delim)]
          [slen (string-length str)])
      (let loop ([start 0] [result '()])
        (let ([pos (let inner ([i start])
                     (if (> (+ i dlen) slen)
                       #f
                       (if (string=? (substring str i (+ i dlen)) delim)
                         i
                         (inner (+ i 1)))))])
          (if pos
            (loop (+ pos dlen) (cons (substring str start pos) result))
            (reverse (cons (substring str start slen) result)))))))

  (define (%str-join strs sep)
    (if (null? strs) ""
      (let loop ([rest (cdr strs)] [acc (car strs)])
        (if (null? rest) acc
          (loop (cdr rest) (string-append acc sep (car rest)))))))

  (define (parse-c-signature line)
    ;; Parse a single C function declaration line.
    ;; Returns (name arg-types ret-type) or #f.
    (let* ([line      (%str-trim line)]
           [semi-pos  (%str-contains line ";")]
           [line      (if semi-pos (substring line 0 semi-pos) line)]
           [po        (%str-contains line "(")]
           [pc        (%str-contains line ")")])
      (and po pc (> pc po)
           (let* ([before  (%str-trim (substring line 0 po))]
                  [args-s  (%str-trim (substring line (+ po 1) pc))]
                  [parts   (filter (lambda (s) (> (string-length s) 0))
                                   (%str-split before " "))])
             (and (>= (length parts) 2)
                  (let* ([name      (list-ref parts (- (length parts) 1))]
                         [ret-parts (list-head parts (- (length parts) 1))]
                         [ret-type  (string->symbol (%str-join ret-parts " "))]
                         [arg-types (cond
                                      [(string=? args-s "") '()]
                                      [(string=? args-s "void") '(void)]
                                      [else
                                       (map (lambda (arg)
                                              (let ([toks (filter
                                                            (lambda (s) (> (string-length s) 0))
                                                            (%str-split (%str-trim arg) " "))])
                                                (if (null? toks) 'void
                                                    (string->symbol (car toks)))))
                                            (%str-split args-s ","))])])
                    (list (string->symbol name) arg-types ret-type)))))))

  ;; Read a C header file and return list of parsed signatures.
  ;; Returns a list of (name arg-types ret-type).
  (define (load-c-header path)
    (if (file-exists? path)
      (let ([lines (call-with-input-file path
                     (lambda (p)
                       (let loop ([result '()])
                         (let ([line (get-line p)])
                           (if (eof-object? line)
                             (reverse result)
                             (loop (cons line result)))))))])
        (filter values
                (map parse-c-signature lines)))
      '()))

  ;; ========== Step 20: Ownership-Tracked Foreign Pointers ==========
  ;;
  ;; (defstruct/foreign name (field ...) (destructor proc))
  ;;
  ;; Creates a record type with:
  ;;   - (name-ptr fp)         — access the raw pointer
  ;;   - (name-valid? fp)      — check if not yet freed
  ;;   - (name-free! fp)       — explicitly free
  ;;   - (make-name ptr ...)   — constructor (registers guardian)
  ;;   - Guardian for GC-triggered cleanup

  ;; A foreign-pointer wrapper: pairs a value with a valid? flag.
  (define-record-type (foreign-ptr %make-foreign-ptr foreign-ptr?)
    (fields
      (mutable fp-value)    ; the raw pointer (uptr or any foreign value)
      (mutable fp-valid?)   ; #t until freed
      (immutable fp-dtor))  ; destructor procedure or #f
    (sealed #t))

  ;; Create a foreign pointer with optional destructor.
  ;; Registers with a guardian so GC calls the destructor if not freed.
  (define *foreign-guardian* (make-guardian))

  (define (make-managed-ptr value destructor)
    (let ([fp (%make-foreign-ptr value #t destructor)])
      (when destructor
        (*foreign-guardian* fp))
      fp))

  ;; GC cleanup thread: runs destructors for collected foreign-ptrs
  (define *guardian-thread*
    (fork-thread
      (lambda ()
        (let loop ()
          (let ([fp (*foreign-guardian*)])
            (when fp
              (when (and (foreign-ptr-fp-valid? fp) (foreign-ptr-fp-dtor fp))
                (guard (exn [#t (void)])
                  ((foreign-ptr-fp-dtor fp) (foreign-ptr-fp-value fp))))
              (foreign-ptr-fp-valid?-set! fp #f)))
          (sleep (make-time 'time-duration 100000000 0))  ; 100ms
          (loop)))))

  (define (foreign-ptr-value fp)
    (unless (foreign-ptr-fp-valid? fp)
      (error 'foreign-ptr-value "use-after-free: foreign pointer has been freed" fp))
    (foreign-ptr-fp-value fp))

  (define (foreign-ptr-valid? fp)
    (and (foreign-ptr? fp) (foreign-ptr-fp-valid? fp)))

  (define (foreign-ptr-free! fp)
    (when (foreign-ptr-fp-valid? fp)
      (let ([dtor (foreign-ptr-fp-dtor fp)]
            [val  (foreign-ptr-fp-value fp)])
        (foreign-ptr-fp-valid?-set! fp #f)
        (foreign-ptr-fp-value-set! fp 0)
        (when dtor
          (guard (exn [#t (void)])
            (dtor val))))))

  ;; (defstruct/foreign Name (fields ...) [(destructor proc)])
  ;; Defines:
  ;;   make-Name — constructor that wraps pointer
  ;;   Name?     — predicate
  ;;   Name-free! — explicit free
  ;;   Name-valid? — validity check
  ;;   Name-<field> — accessors (return foreign-ptr-value for the ptr field)
  (define-syntax defstruct/foreign
    (lambda (stx)
      (syntax-case stx ()
        [(_ name (field ...) (_ dtor-expr))
         (with-syntax
           ([make-name   (datum->syntax #'name
                           (string->symbol (string-append "make-"
                             (symbol->string (syntax->datum #'name)))))]
            [name-free!  (datum->syntax #'name
                           (string->symbol (string-append
                             (symbol->string (syntax->datum #'name)) "-free!")))]
            [name-valid? (datum->syntax #'name
                           (string->symbol (string-append
                             (symbol->string (syntax->datum #'name)) "-valid?")))]
            [name-ptr    (datum->syntax #'name
                           (string->symbol (string-append
                             (symbol->string (syntax->datum #'name)) "-ptr")))]
            [name?       (datum->syntax #'name
                           (string->symbol (string-append
                             (symbol->string (syntax->datum #'name)) "?")))])
           #'(begin
               (define (make-name ptr field ...)
                 (make-managed-ptr ptr dtor-expr))
               (define (name? x)
                 (foreign-ptr? x))
               (define (name-ptr fp)
                 (foreign-ptr-value fp))
               (define (name-valid? fp)
                 (foreign-ptr-valid? fp))
               (define (name-free! fp)
                 (foreign-ptr-free! fp))))]
        [(_ name (field ...))
         #'(defstruct/foreign name (field ...) (destructor #f))])))

  ;; (with-foreign ([var init-expr] ...) body ...)
  ;; Automatically frees foreign pointers on exit.
  (define-syntax with-foreign
    (syntax-rules ()
      [(_ ([var init] ...) body ...)
       (let ([var init] ...)
         (guard (exn [#t
                      (for-each (lambda (fp)
                                  (when (foreign-ptr? fp) (foreign-ptr-free! fp)))
                                (list var ...))
                      (raise exn)])
           (let ([result (begin body ...)])
             (for-each (lambda (fp)
                          (when (foreign-ptr? fp) (foreign-ptr-free! fp)))
                        (list var ...))
             result)))]))

  ;; ========== Step 21: Async Foreign Calls ==========
  ;;
  ;; Problem: foreign-procedure calls block the OS thread.
  ;; Solution: run them on a dedicated FFI thread pool, returning
  ;;           a promise that resolves when the call completes.
  ;;
  ;; (make-ffi-thread-pool [n]) — create pool with n workers (default 4)
  ;; (ffi-thread-pool-call pool thunk) — run thunk on pool, return result
  ;; (define-foreign/async name proc) — like define but runs on default pool

  ;; FFI thread pool and queue implemented as plain vectors for simplicity.
  ;; queue = #(items-list mutex condition)
  ;; pool  = #(n-workers queue running?)

  (define (make-ffi-queue!)
    (let ([mutex (make-mutex)]
          [cond  (make-condition)])
      (vector '() mutex cond)))

  (define (ffi-queue-enqueue! q item)
    (with-mutex (vector-ref q 1)
      (vector-set! q 0 (append (vector-ref q 0) (list item)))
      (condition-signal (vector-ref q 2))))

  (define (ffi-queue-dequeue! q)
    (with-mutex (vector-ref q 1)
      (let loop ()
        (if (null? (vector-ref q 0))
          (begin
            (condition-wait (vector-ref q 2) (vector-ref q 1))
            (loop))
          (let ([item (car (vector-ref q 0))])
            (vector-set! q 0 (cdr (vector-ref q 0)))
            item)))))

  ;; Promise: mutex+condition+result
  (define (make-ffi-promise)
    (vector #f #f (make-mutex) (make-condition)))

  (define (ffi-promise-resolve! p val)
    (with-mutex (vector-ref p 2)
      (vector-set! p 0 #t)   ; resolved?
      (vector-set! p 1 val)  ; value
      (condition-broadcast (vector-ref p 3))))

  (define (ffi-promise-wait p)
    (with-mutex (vector-ref p 2)
      (let loop ()
        (if (vector-ref p 0)
          (vector-ref p 1)
          (begin
            (condition-wait (vector-ref p 3) (vector-ref p 2))
            (loop))))))

  ;; Default FFI thread pool (lazy init)
  (define *default-ffi-pool* #f)
  (define *default-ffi-pool-mutex* (make-mutex))

  (define (make-ffi-thread-pool . args)
    (let* ([n-workers (if (null? args) 4 (car args))]
           [queue (make-ffi-queue!)])
      (let ([pool-vec (vector n-workers queue #t)])
        ;; Start workers
        (let loop ([i 0])
          (when (< i n-workers)
            (fork-thread
              (lambda ()
                (let worker-loop ()
                  (when (vector-ref pool-vec 2) ; running?
                    (let ([work-item (ffi-queue-dequeue! queue)])
                      (cond
                        [(eq? work-item 'shutdown)
                         ;; Re-enqueue for other workers
                         (ffi-queue-enqueue! queue 'shutdown)]
                        [else
                         (let ([thunk   (vector-ref work-item 0)]
                               [promise (vector-ref work-item 1)])
                           (guard (exn [#t (ffi-promise-resolve! promise exn)])
                             (ffi-promise-resolve! promise (thunk))))]))
                    (worker-loop)))))
            (loop (+ i 1))))
        pool-vec)))

  (define (ffi-thread-pool-call pool thunk)
    (let* ([queue   (vector-ref pool 1)]
           [promise (make-ffi-promise)]
           [item    (vector thunk promise)])
      (ffi-queue-enqueue! queue item)
      (let ([result (ffi-promise-wait promise)])
        ;; Re-raise if the worker caught an exception
        (if (condition? result)
          (raise result)
          result))))

  (define (ffi-thread-pool-shutdown! pool)
    (vector-set! pool 2 #f)
    (let ([n (vector-ref pool 0)]
          [queue (vector-ref pool 1)])
      (let loop ([i 0])
        (when (< i n)
          (ffi-queue-enqueue! queue 'shutdown)
          (loop (+ i 1))))))

  (define (get-default-ffi-pool)
    (with-mutex *default-ffi-pool-mutex*
      (when (not *default-ffi-pool*)
        (set! *default-ffi-pool* (make-ffi-thread-pool 4)))
      *default-ffi-pool*))

  ;; (define-foreign/async name proc)
  ;; Wraps proc so calls run on the default FFI thread pool.
  ;; The caller blocks until the result is available.
  (define-syntax define-foreign/async
    (syntax-rules ()
      [(_ name proc-expr)
       (define (name . args)
         (ffi-thread-pool-call
           (get-default-ffi-pool)
           (lambda () (apply proc-expr args))))]))

  ) ;; end library
