#!chezscheme
;;; :std/sugar -- Gerbil sugar forms

(library (std sugar)
  (export
    try catch finally
    while until
    unwind-protect
    hash-literal hash-eq-literal
    let-hash
    defrule defrules
    chain chain-and with-id
    assert!
    with-lock
    with-catch
    cut cute)
  (import (except (chezscheme)
            make-hash-table hash-table? iota 1+ 1-)
          (jerboa core))

  ;; chain: thread a value through a series of expressions
  ;; (chain val (f _ arg) (g arg _)) → (g arg (f val arg))
  (define-syntax chain
    (lambda (stx)
      (syntax-case stx ()
        [(_ val) #'val]
        [(_ val (f args ...) rest ...)
         #'(chain (chain-apply f val args ...) rest ...)]
        [(_ val f rest ...)
         (identifier? #'f)
         #'(chain (f val) rest ...)])))

  (define-syntax chain-apply
    (lambda (stx)
      (syntax-case stx ()
        [(_ f val) #'(f val)]
        [(_ f val placeholder arg ...)
         (and (identifier? #'placeholder) (eq? (syntax->datum #'placeholder) '_))
         #'(f val arg ...)]
        [(_ f val arg1 rest ...)
         #'(chain-apply-tail f val (arg1) rest ...)])))

  (define-syntax chain-apply-tail
    (lambda (stx)
      (syntax-case stx ()
        [(_ f val (args ...) placeholder)
         (and (identifier? #'placeholder) (eq? (syntax->datum #'placeholder) '_))
         #'(f args ... val)]
        [(_ f val (args ...) placeholder rest ...)
         (and (identifier? #'placeholder) (eq? (syntax->datum #'placeholder) '_))
         #'(chain-apply-tail f val (args ... val) rest ...)]
        [(_ f val (args ...) arg rest ...)
         #'(chain-apply-tail f val (args ... arg) rest ...)]
        [(_ f val (args ...)) #'(f args ...)])))

  ;; chain-and: like chain but short-circuits on #f
  (define-syntax chain-and
    (syntax-rules ()
      [(_ val) val]
      [(_ val step rest ...)
       (let ([v val])
         (and v (chain-and (chain v step) rest ...)))]))

  ;; with-id: generate identifiers from a name
  (define-syntax with-id
    (lambda (stx)
      (syntax-case stx ()
        [(_ name ((var fmt) ...) body ...)
         (with-syntax ([(gen ...) (map (lambda (f)
                                         (datum->syntax #'name
                                           (string->symbol
                                             (format (syntax->datum f)
                                                     (syntax->datum #'name)))))
                                       (syntax->list #'(fmt ...)))])
           #'(let-syntax ([helper
                           (lambda (stx2)
                             (syntax-case stx2 ()
                               [(_)
                                (with-syntax ([var (datum->syntax #'name 'gen)] ...)
                                  #'(begin body ...))]))])
               (helper)))])))

  ;; assert!
  (define-syntax assert!
    (syntax-rules ()
      [(_ expr)
       (unless expr
         (error 'assert! "assertion failed" 'expr))]
      [(_ expr message)
       (unless expr
         (error 'assert! message 'expr))]))

  ;; unwind-protect — like Java's try/finally, guarantee cleanup runs
  (define-syntax unwind-protect
    (syntax-rules ()
      [(_ body cleanup ...)
       (dynamic-wind
         (lambda () (void))
         (lambda () body)
         (lambda () cleanup ...))]))

  ;; with-lock — acquire Chez mutex, run body, release even on exception
  (define-syntax with-lock
    (syntax-rules ()
      [(_ mutex-expr body body* ...)
       (let ([m mutex-expr])
         (dynamic-wind
           (lambda () (mutex-acquire m))
           (lambda () body body* ...)
           (lambda () (mutex-release m))))]))

  ;; with-catch — Gerbil's 2-arg exception handler shorthand
  ;; (with-catch handler thunk)
  ;; handler: (lambda (exn) fallback-value)
  ;; thunk:   (lambda () guarded-expression)
  (define (with-catch handler thunk)
    (guard (e [#t (handler e)])
      (thunk)))

  ;; cut / cute — SRFI-26 partial application
  ;; (cut f <> y) → (lambda (x) (f x y))
  ;; (cute f <> y) → (let ([t y]) (lambda (x) (f x t)))

  (define-syntax cut
    (syntax-rules ()
      [(_ . slots-or-exprs)
       (cut-aux () () . slots-or-exprs)]))

  (define-syntax cute
    (syntax-rules ()
      [(_ . slots-or-exprs)
       (cute-aux () () () . slots-or-exprs)]))

  (define-syntax cut-aux
    (syntax-rules (<> <...>)
      ;; No more args — build lambda
      [(_ (params ...) (args ...))
       (lambda (params ...) (args ...))]
      ;; Slot <> — add parameter
      [(_ (params ...) (args ...) <> . rest)
       (cut-aux (params ... x) (args ... x) . rest)]
      ;; Rest slot <...> — must be last
      [(_ (params ...) (args ...) <...>)
       (lambda (params ... . xs) (apply args ... xs))]
      ;; Normal expression — pass through
      [(_ (params ...) (args ...) expr . rest)
       (cut-aux (params ...) (args ... expr) . rest)]))

  (define-syntax cute-aux
    (syntax-rules (<> <...>)
      ;; No more args — build let + lambda
      [(_ (binds ...) (params ...) (args ...))
       (let (binds ...) (lambda (params ...) (args ...)))]
      ;; Slot <>
      [(_ (binds ...) (params ...) (args ...) <> . rest)
       (cute-aux (binds ...) (params ... x) (args ... x) . rest)]
      ;; Rest slot <...>
      [(_ (binds ...) (params ...) (args ...) <...>)
       (let (binds ...) (lambda (params ... . xs) (apply args ... xs)))]
      ;; Normal expression — evaluate once via let
      [(_ (binds ...) (params ...) (args ...) expr . rest)
       (cute-aux (binds ... (t expr)) (params ...) (args ... t) . rest)]))

  ) ;; end library
