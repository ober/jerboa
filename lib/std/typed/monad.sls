#!chezscheme
;;; (std typed monad) — Monad utilities and concrete monad implementations
;;;
;;; Provides:
;;;   - Monad combinators (sequence, mapM, when, guard, join, etc.)
;;;   - State monad   : computation is (state -> (values result new-state))
;;;   - Reader monad  : computation is (env -> result)
;;;   - Writer monad  : computation is (cons result log-list)
;;;   - Maybe monad   : alias to Option from hkt
;;;   - lift          : transformer interface stub

(library (std typed monad)
  (export
    ;; Monad combinators
    monad-map
    monad-sequence
    monad-mapM
    monad-when
    monad-unless
    monad-void
    monad-guard
    monad-join

    ;; State monad
    make-state-monad
    run-state
    eval-state
    exec-state
    state-get
    state-put
    state-modify
    state-bind
    state-return

    ;; Reader monad
    make-reader-monad
    run-reader
    reader-ask
    reader-local
    reader-bind
    reader-return

    ;; Writer monad
    make-writer-monad
    run-writer
    writer-tell
    writer-listen
    writer-bind
    writer-return

    ;; Maybe monad (alias to Option)
    maybe-bind
    maybe-return
    from-maybe

    ;; Monad transformer interface
    lift)

  (import (chezscheme) (std typed hkt))

  ;; ========== Monad combinators ==========
  ;;
  ;; These are generic combinators parameterized by a type-tag (symbol).

  ;; monad-map: like fmap but via bind
  ;; (monad-map tag f ma) — apply f inside the monad
  (define (monad-map tag f ma)
    (hkt-dispatch 'Monad 'bind tag ma
      (lambda (a)
        (hkt-dispatch 'Monad 'return tag (f a)))))

  ;; monad-sequence: (list of monadic values) -> monadic (list of values)
  ;; e.g. (list (Some 1) (Some 2)) -> (Some (list 1 2))
  (define (monad-sequence tag lst)
    (if (null? lst)
      (hkt-dispatch 'Monad 'return tag '())
      (hkt-dispatch 'Monad 'bind tag (car lst)
        (lambda (x)
          (hkt-dispatch 'Monad 'bind tag (monad-sequence tag (cdr lst))
            (lambda (xs)
              (hkt-dispatch 'Monad 'return tag (cons x xs))))))))

  ;; monad-mapM: map a monadic function over a list, then sequence
  (define (monad-mapM tag f lst)
    (monad-sequence tag (map f lst)))

  ;; monad-when: conditional monad action; returns (return (void)) if false
  (define (monad-when tag condition action)
    (if condition
      action
      (hkt-dispatch 'Monad 'return tag (void))))

  ;; monad-unless: opposite of monad-when
  (define (monad-unless tag condition action)
    (monad-when tag (not condition) action))

  ;; monad-void: discard the result of a monadic action
  (define (monad-void tag ma)
    (hkt-dispatch 'Monad 'bind tag ma
      (lambda (_)
        (hkt-dispatch 'Monad 'return tag (void)))))

  ;; monad-guard: MonadPlus guard — for list monad, filters
  ;; Returns (return (void)) if condition is true, else mzero
  ;; For list: mzero = '(), for Option: mzero = None
  (define (monad-guard tag condition)
    (case tag
      [(List)
       (if condition (list (void)) '())]
      [(Option)
       (if condition (make-Some (void)) (make-None))]
      [else
       (if condition
         (hkt-dispatch 'Monad 'return tag (void))
         (error 'monad-guard "no mzero for type tag" tag))]))

  ;; monad-join: flatten m (m a) -> m a
  (define (monad-join tag mma)
    (hkt-dispatch 'Monad 'bind tag mma
      (lambda (ma) ma)))

  ;; ========== State monad ==========
  ;;
  ;; A stateful computation is a procedure: state -> (values result new-state)
  ;; Wrapped in a record for type safety.

  (define-record-type state-monad-val
    (fields (immutable proc))
    (sealed #t))

  ;; make-state-monad: wrap a procedure (state -> (values result state)) into a state monad value
  (define (make-state-monad proc)
    (make-state-monad-val proc))

  ;; run-state: execute the state computation with initial state
  ;; Returns (values result final-state)
  (define (run-state sm initial-state)
    ((state-monad-val-proc sm) initial-state))

  ;; eval-state: run and return only the result
  (define (eval-state sm initial-state)
    (call-with-values
      (lambda () (run-state sm initial-state))
      (lambda (result _state) result)))

  ;; exec-state: run and return only the final state
  (define (exec-state sm initial-state)
    (call-with-values
      (lambda () (run-state sm initial-state))
      (lambda (_result state) state)))

  ;; state-get: read the current state as the result
  (define state-get
    (make-state-monad
      (lambda (s) (values s s))))

  ;; state-put: replace the current state; result is (void)
  (define (state-put new-state)
    (make-state-monad
      (lambda (_s) (values (void) new-state))))

  ;; state-modify: apply a function to update the state
  (define (state-modify f)
    (make-state-monad
      (lambda (s) (values (void) (f s)))))

  ;; State monad bind: sequence two state computations
  ;; (sm >>= f) where f returns a new state monad
  (define (state-bind sm f)
    (make-state-monad
      (lambda (s)
        (call-with-values
          (lambda () (run-state sm s))
          (lambda (a s2)
            (run-state (f a) s2))))))

  ;; State monad return: lift a pure value into the state monad
  (define (state-return a)
    (make-state-monad
      (lambda (s) (values a s))))

  ;; ========== Reader monad ==========
  ;;
  ;; A reader computation is a procedure: env -> result

  (define-record-type reader-monad-val
    (fields (immutable proc))
    (sealed #t))

  (define (make-reader-monad proc)
    (make-reader-monad-val proc))

  ;; run-reader: execute with a given environment
  (define (run-reader rm env)
    ((reader-monad-val-proc rm) env))

  ;; reader-ask: returns the environment as the result
  (define reader-ask
    (make-reader-monad (lambda (env) env)))

  ;; reader-local: run a reader computation with a modified environment
  (define (reader-local f rm)
    (make-reader-monad
      (lambda (env)
        (run-reader rm (f env)))))

  ;; Reader monad bind
  (define (reader-bind rm f)
    (make-reader-monad
      (lambda (env)
        (run-reader (f (run-reader rm env)) env))))

  ;; Reader monad return
  (define (reader-return a)
    (make-reader-monad (lambda (_env) a)))

  ;; ========== Writer monad ==========
  ;;
  ;; A writer computation is a pair: (result . log-list)
  ;; The log is a list that accumulates written values.

  (define-record-type writer-monad-val
    (fields
      (immutable result)
      (immutable log))
    (sealed #t))

  (define (make-writer-monad result log)
    (make-writer-monad-val result log))

  ;; run-writer: extract (values result log) from a writer value
  (define (run-writer wm)
    (values (writer-monad-val-result wm)
            (writer-monad-val-log wm)))

  ;; writer-tell: append a value to the log; result is (void)
  (define (writer-tell msg)
    (make-writer-monad (void) (list msg)))

  ;; writer-listen: run a computation and return (values result log-so-far)
  (define (writer-listen wm)
    (call-with-values
      (lambda () (run-writer wm))
      (lambda (result log)
        (make-writer-monad (cons result log) log))))

  ;; Writer monad bind
  (define (writer-bind wm f)
    (call-with-values
      (lambda () (run-writer wm))
      (lambda (a log1)
        (call-with-values
          (lambda () (run-writer (f a)))
          (lambda (b log2)
            (make-writer-monad b (append log1 log2)))))))

  ;; Writer monad return
  (define (writer-return a)
    (make-writer-monad a '()))

  ;; ========== Maybe monad (alias to Option) ==========

  (define (maybe-bind opt f)
    (option-bind opt f))

  (define (maybe-return v)
    (option-return v))

  ;; from-maybe: extract value or return a default
  (define (from-maybe default opt)
    (if (Some? opt)
      (Some-val opt)
      default))

  ;; ========== Monad transformer interface ==========
  ;;
  ;; lift: lift a base monad action into a transformer monad.
  ;; Currently a stub that passes through the value.

  (define (lift m)
    ;; In a full implementation, this would wrap m in the transformer.
    ;; For now, return m unchanged as a minimal interface.
    m)

) ; end library
