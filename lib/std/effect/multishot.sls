#!chezscheme
;;; (std effect multishot) — Multishot nondeterminism via choice sequences
;;;
;;; Because Chez Scheme's call/1cc continuations (used by (std effect)) are
;;; one-shot, true multishot resumption is achieved via a "choice sequence"
;;; strategy:
;;;
;;;   - all-solutions runs thunk multiple times.
;;;   - Each run follows a predetermined list of choices.
;;;   - When the thunk asks for a choice beyond the end of the list, we
;;;     fork: enqueue one run per option (each with the sequence extended
;;;     by that option), then abandon the current run.
;;;   - Failure (fail) abandons the current run immediately.
;;;
;;; This is equivalent to depth-first backtracking over a lazy search tree.
;;;
;;; The with-multishot-handler form wraps handlers around call/cc so that
;;; the wrapped k objects may be called more than once by user code.
;;;
;;; API:
;;;   (choose options)                  — pick one option (backtracking)
;;;   (fail)                            — backtrack (no result)
;;;   (all-solutions thunk)             — list of all results
;;;   (one-solution thunk)              — first result or #f
;;;   (sample choices weights)          — weighted random pick
;;;   (amb e ...)                       — any-of expression
;;;   (amb-all e ...)                   — all amb choices
;;;   (with-multishot-handler ...)      — like with-handler but wraps k
;;;   (resume/multi k val)              — resume a multishot k
;;;   multishot-continuation?
;;;   defeffect-nondet

(library (std effect multishot)
  (export
    with-multishot-handler
    resume/multi
    defeffect-nondet
    choose
    fail
    all-solutions
    one-solution
    sample
    amb
    amb-all
    multishot-handler?
    multishot-continuation?)

  (import (chezscheme) (std effect))

  ;; ========== Multishot continuation record ==========

  (define-record-type %multishot-continuation
    (fields (immutable proc))
    (sealed #t))

  (define (multishot-continuation? x) (%multishot-continuation? x))
  (define (multishot-handler? x) #f)  ;; frames are just eq-hashtables

  ;; ========== resume/multi ==========

  (define (resume/multi k val)
    (if (%multishot-continuation? k)
      ((%multishot-continuation-proc k) val)
      (k val)))

  ;; ========== with-multishot-handler ==========
  ;;
  ;; Installs handlers in the regular *effect-handlers* stack, but wraps
  ;; each captured continuation in a %multishot-continuation so user code
  ;; can identify and potentially store/replay it.
  ;; (True multi-invocation still requires call/cc at the site of capture.)

  (define-syntax with-multishot-handler
    (lambda (stx)
      (define (effect-desc-id eff-name-stx)
        (datum->syntax eff-name-stx
          (string->symbol
            (string-append
              (symbol->string (syntax->datum eff-name-stx))
              "::descriptor"))))

      (define (build-op-pair op-clause)
        (syntax-case op-clause ()
          [(op-sym (k arg ...) body ...)
           (with-syntax ([k-raw (datum->syntax #'k (gensym "k-raw"))])
             #'(cons 'op-sym
                     (lambda (k-raw arg ...)
                       (let ([k (make-%multishot-continuation k-raw)])
                         body ...))))]))

      (define (build-effect-entry eff-clause)
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
                       [frame-id (datum->syntax #'with-multishot-handler
                                                (gensym "mhframe"))])
           #'(let ([frame-id (make-eq-hashtable)])
               (let ([e entry])
                 (hashtable-set! frame-id (car e) (cdr e)))
               ...
               (run-with-handler frame-id (lambda () body ...))))])))

  ;; ========== Nondeterminism via choice-sequence strategy ==========

  ;; Thread-local hooks installed by all-solutions.
  (define *pick-fn* (make-thread-parameter #f))
  (define *fail-fn* (make-thread-parameter #f))

  ;; Sentinel condition used to abort the current run.
  (define-condition-type &ms-exhausted &condition
    make-ms-exhausted ms-exhausted?)

  ;; choose: pick one item from options (backtracking if needed).
  (define (choose options)
    (let ([fn (*pick-fn*)])
      (if fn
        (fn options)
        ;; Outside all-solutions: just return first option or error
        (if (null? options)
          (error 'choose "no options available")
          (car options)))))

  ;; fail: abandon this branch.
  (define fail
    (lambda ()
      (let ([fn (*fail-fn*)])
        (if fn
          (fn)
          (error 'fail "no backtracking context")))))

  ;; ========== all-solutions ==========
  ;;
  ;; Runs thunk with a fresh choice-sequence engine.

  (define (all-solutions thunk)
    (let ([pending '()]   ;; queue of choice sequences to try
          [results '()])

      ;; Run thunk using a predetermined choices list.
      (define (run-with-choices choices)
        (let ([idx 0])

          ;; pick-fn: return the idx-th pre-decided choice, or branch.
          (define (pick-fn options)
            (if (null? options)
              ;; fail immediately
              (raise (make-ms-exhausted))
              (let ([my-idx idx])
                (set! idx (+ idx 1))
                (if (>= my-idx (length choices))
                  ;; Need to branch: enqueue a run for each option
                  (begin
                    (for-each
                      (lambda (opt)
                        (set! pending
                          (append pending
                            (list (append choices (list opt))))))
                      options)
                    (raise (make-ms-exhausted)))
                  ;; Use pre-decided choice
                  (list-ref choices my-idx)))))

          ;; fail-fn: abandon this run.
          (define (fail-fn)
            (raise (make-ms-exhausted)))

          (parameterize ([*pick-fn* pick-fn]
                         [*fail-fn* fail-fn])
            (guard (exn [(ms-exhausted? exn) (void)])
              (let ([result (thunk)])
                (set! results (cons result results)))))))

      ;; Seed: one run with empty choice sequence.
      (set! pending (list '()))
      (let loop ()
        (unless (null? pending)
          (let ([seq (car pending)])
            (set! pending (cdr pending))
            (run-with-choices seq))
          (loop)))
      (reverse results)))

  ;; ========== one-solution ==========
  ;;
  ;; Short-circuits: returns as soon as the first result is found.
  ;; Uses an escape continuation to abandon remaining branches.

  (define (one-solution thunk)
    (call/cc
      (lambda (escape)
        (let ([pending '()])

          (define (run-with-choices choices)
            (let ([idx 0])

              (define (pick-fn options)
                (if (null? options)
                  (raise (make-ms-exhausted))
                  (let ([my-idx idx])
                    (set! idx (+ idx 1))
                    (if (>= my-idx (length choices))
                      (begin
                        ;; Only enqueue; take first immediately
                        (for-each
                          (lambda (opt)
                            (set! pending
                              (append pending
                                (list (append choices (list opt))))))
                          options)
                        (raise (make-ms-exhausted)))
                      (list-ref choices my-idx)))))

              (define (fail-fn)
                (raise (make-ms-exhausted)))

              (parameterize ([*pick-fn* pick-fn]
                             [*fail-fn* fail-fn])
                (guard (exn [(ms-exhausted? exn) (void)])
                  (let ([result (thunk)])
                    (escape result))))))

          (set! pending (list '()))
          (let loop ()
            (unless (null? pending)
              (let ([seq (car pending)])
                (set! pending (cdr pending))
                (run-with-choices seq))
              (loop)))
          #f))))

  ;; ========== sample ==========
  ;;
  ;; Weighted random sampling. Weights need not sum to 1.

  (define (sample choices weights)
    (when (null? choices)
      (error 'sample "empty choices list"))
    (let* ([total  (apply + weights)]
           [target (* (/ (random 1000000) 1000000.0) total)])
      (let loop ([cs choices] [ws weights] [acc 0.0])
        (if (or (null? (cdr cs))
                (< target (+ acc (car ws))))
          (car cs)
          (loop (cdr cs) (cdr ws) (+ acc (car ws)))))))

  ;; ========== amb / amb-all macros ==========

  (define-syntax amb
    (syntax-rules ()
      [(_ e ...)
       (choose (list e ...))]))

  (define-syntax amb-all
    (syntax-rules ()
      [(_ e ...)
       (all-solutions (lambda () (choose (list e ...))))]))

  ;; ========== defeffect-nondet ==========

  (define-syntax defeffect-nondet
    (syntax-rules ()
      [(_ Name)
       (defeffect Name
         (choose options)
         (fail))]))

  ) ;; end library
