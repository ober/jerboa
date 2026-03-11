#!chezscheme
;;; (std effect) — Algebraic effects using one-shot continuations
;;;
;;; API:
;;;   (defeffect Name (op1 arg ...) ...)    — define an effect with operations
;;;   (perform (Name op-name arg ...))       — perform an effect operation
;;;   (with-handler ([Name (op (k arg ...) body ...) ...] ...) body ...)
;;;   (resume k val)                         — resume a captured continuation
;;;
;;; Implementation uses call/1cc (one-shot continuations) for efficiency.
;;; Effect dispatch is O(1) via eq-hashtable on effect descriptors.

(library (std effect)
  (export
    defeffect
    with-handler
    perform
    resume
    effect-not-handled?
    effect-perform)

  (import (chezscheme))

  ;; ========== Effect descriptor ==========

  (define-record-type effect-descriptor
    (fields (immutable name))
    (sealed #t))

  ;; ========== Handler stack ==========
  ;; Thread-local stack of frames.
  ;; Each frame: eq-hashtable mapping effect-descriptor -> ((op-sym . proc) ...)
  ;; proc :: (k arg ...) -> any,  k = one-shot continuation

  (define *effect-handlers* (make-thread-parameter '()))

  (define (find-handler descriptor op-sym)
    (let loop ([stack (*effect-handlers*)])
      (cond
        [(null? stack) #f]
        [else
         (let ([ops (hashtable-ref (car stack) descriptor #f)])
           (if ops
             (let ([entry (assq op-sym ops)])
               (if entry (cdr entry) (loop (cdr stack))))
             (loop (cdr stack))))])))

  ;; ========== Unhandled effect condition ==========

  (define-condition-type &effect-not-handled &serious
    make-effect-not-handled effect-not-handled?
    (descriptor effect-not-handled-descriptor)
    (operation  effect-not-handled-operation))

  ;; ========== Runtime: perform an effect ==========

  (define (effect-perform descriptor op-sym args)
    (let ([handler (find-handler descriptor op-sym)])
      (if handler
        (call/1cc
          (lambda (k)
            (apply handler k args)))
        (raise
          (condition
            (make-message-condition
              (string-append "effect not handled: "
                (symbol->string (effect-descriptor-name descriptor))
                "/"
                (symbol->string op-sym)))
            (make-effect-not-handled descriptor op-sym)
            (make-irritants-condition (cons op-sym args)))))))

  ;; ========== resume ==========

  (define (resume k val) (k val))

  ;; ========== perform (alias for user convenience) ==========
  ;; (perform (EffectName op arg ...)) expands via defeffect.
  ;; This is just a syntax marker — actual expansion is in defeffect.
  (define-syntax perform
    (lambda (stx)
      (syntax-case stx ()
        [(_ expr) #'expr])))

  ;; ========== with-handler (runtime helper) ==========

  (define (run-with-handler frame thunk)
    (parameterize ([*effect-handlers* (cons frame (*effect-handlers*))])
      (thunk)))

  ;; ========== defeffect macro ==========
  ;;
  ;; (defeffect Async
  ;;   (await promise)
  ;;   (spawn thunk))
  ;;
  ;; Generates:
  ;;   Async::descriptor — unique effect-descriptor instance
  ;;   (Async await arg ...)  — performs the Async/await operation

  (define-syntax defeffect
    (lambda (stx)
      (syntax-case stx ()
        [(_ eff-name (op-sym op-arg ...) ...)
         (identifier? #'eff-name)
         (with-syntax ([desc-id
                        (datum->syntax #'eff-name
                          (string->symbol
                            (string-append
                              (symbol->string (syntax->datum #'eff-name))
                              "::descriptor")))])
           #'(begin
               (define desc-id
                 (make-effect-descriptor 'eff-name))
               (define-syntax eff-name
                 (lambda (inner)
                   (syntax-case inner ()
                     [(_ op arg (... ...))
                      #`(effect-perform desc-id 'op (list arg (... ...)))])))))])))

  ;; ========== with-handler macro ==========
  ;;
  ;; (with-handler
  ;;   ([Async
  ;;     (await (k promise) expr ...)
  ;;     (spawn (k thunk)  expr ...)]
  ;;    [State
  ;;     (get  (k)    expr ...)
  ;;     (put  (k v)  expr ...)])
  ;;   body ...)
  ;;
  ;; Handler proc receives k (continuation) as first arg, then operation args.

  (define-syntax with-handler
    (lambda (stx)
      (define (effect-desc-id eff-name-stx)
        (datum->syntax eff-name-stx
          (string->symbol
            (string-append
              (symbol->string (syntax->datum eff-name-stx))
              "::descriptor"))))

      (define (build-op-pair op-clause)
        ;; op-clause: (op-sym (k arg ...) body ...)
        ;; produces:  (cons 'op-sym (lambda (k arg ...) body ...))
        (syntax-case op-clause ()
          [(op-sym (k arg ...) body ...)
           #'(cons 'op-sym (lambda (k arg ...) body ...))]))

      (define (build-effect-entry eff-clause)
        ;; eff-clause: [eff-name op-clause ...]
        ;; produces:  (list desc-id (cons 'op ...) ...)
        (syntax-case eff-clause ()
          [(eff-name op-clause ...)
           (with-syntax ([desc-id (effect-desc-id #'eff-name)]
                         [(op-pair ...) (map build-op-pair
                                             (syntax->list #'(op-clause ...)))])
             #'(list desc-id op-pair ...))]))

      (syntax-case stx ()
        [(_ (eff-clause ...) body ...)
         (with-syntax ([(entry ...) (map build-effect-entry
                                         (syntax->list #'(eff-clause ...)))]
                       [frame-id (datum->syntax #'with-handler (gensym "hframe"))])
           #'(let ([frame-id (make-eq-hashtable)])
               (let ([e entry])
                 (hashtable-set! frame-id (car e) (cdr e)))
               ...
               (run-with-handler frame-id (lambda () body ...))))])))

  ) ;; end library
