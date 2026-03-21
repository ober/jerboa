#!chezscheme
;;; (std effect state) — Pure state via algebraic effects
;;;
;;; Mutable state without mutation — state changes are effects
;;; threaded through the handler via continuations.
;;;
;;; API:
;;;   (with-state initial thunk)    — run thunk with state effect
;;;   (state-get)                    — get current state
;;;   (state-put val)                — set state to val
;;;   (state-modify proc)            — apply proc to current state
;;;   (run-state initial thunk)      — returns (values result final-state)

(library (std effect state)
  (export with-state state-get state-put state-modify run-state)

  (import (chezscheme))

  ;; State is thread-local via parameter
  (define *current-state* (make-thread-parameter 'no-state))

  (define (state-get)
    (let ([s (*current-state*)])
      (when (eq? s 'no-state)
        (error 'state-get "not inside with-state"))
      s))

  (define (state-put val)
    (*current-state* val)
    (void))

  (define (state-modify proc)
    (state-put (proc (state-get))))

  (define (with-state initial thunk)
    (parameterize ([*current-state* initial])
      (let ([result (thunk)])
        result)))

  (define (run-state initial thunk)
    (parameterize ([*current-state* initial])
      (let ([result (thunk)])
        (values result (*current-state*)))))

) ;; end library
