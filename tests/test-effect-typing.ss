#!chezscheme
;;; Tests for (std typed effect-typing) — Effect type signatures

(import (chezscheme) (std typed effect-typing) (std effect))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(printf "--- Phase 2c: Effect Typing ---~%~%")

;; ========== define-effect-signature ==========

(define-effect-signature NoEffects
  handles: ()
  returns: any)

(define-effect-signature StateOnly
  handles: (State)
  returns: integer)

(define-effect-signature MultiEffect
  handles: (State Reader Writer)
  returns: any)

(test "effect-sig? on sig"
  (effect-sig? StateOnly)
  #t)

(test "effect-sig? on non-sig"
  (effect-sig? 42)
  #f)

(test "effect-sig? on #f"
  (effect-sig? #f)
  #f)

(test "effect-sig-handles/empty"
  (effect-sig-handles NoEffects)
  '())

(test "effect-sig-handles/single"
  (effect-sig-handles StateOnly)
  '(State))

(test "effect-sig-handles/multiple"
  (effect-sig-handles MultiEffect)
  '(State Reader Writer))

(test "effect-sig-returns/any"
  (effect-sig-returns StateOnly)
  'integer)

(test "effect-sig-returns/multi"
  (effect-sig-returns MultiEffect)
  'any)

;; ========== Signature registry ==========
;; Each define-effect-signature registers by name

(define-effect-signature Registered
  handles: (MyEff)
  returns: string)

;; We can look it up by introspecting through a re-check
(test "signature accessible via variable"
  (effect-sig? Registered)
  #t)

;; ========== check-effect-signature ==========

(test "check-effect-sig/exact match"
  (check-effect-signature StateOnly '(State))
  #t)

(test "check-effect-sig/superset ok"
  (check-effect-signature StateOnly '(State Reader))
  #t)

(test "check-effect-sig/empty handles ok"
  (check-effect-signature NoEffects '())
  #t)

(test "check-effect-sig/empty handles any actual ok"
  (check-effect-signature NoEffects '(State))
  #t)

(test "check-effect-sig/missing effect errors"
  (guard (exn [#t (condition-message exn)])
    (check-effect-signature StateOnly '()))
  "handler does not handle declared effects")

(test "check-effect-sig/partial miss errors"
  (guard (exn [#t (condition-message exn)])
    (check-effect-signature MultiEffect '(State Reader)))
  "handler does not handle declared effects")

(test "check-effect-sig/non-sig errors"
  (guard (exn [#t (condition-message exn)])
    (check-effect-signature 'not-a-sig '(State)))
  "not an effect signature")

;; ========== infer-handler-effects ==========

(test "infer-handler-effects/list passthrough"
  (infer-handler-effects '(State Reader))
  '(State Reader))

(test "infer-handler-effects/empty list"
  (infer-handler-effects '())
  '())

(test "infer-handler-effects/hashtable"
  ;; Build a hashtable like what (std effect) uses:
  ;; keys are effect descriptors (records with 'name field)
  (let ([ht (make-eq-hashtable)])
    ;; We put symbols as keys (since we don't have real effect-descriptors here)
    ;; infer-handler-effects falls back to the key itself if no 'name field
    (hashtable-set! ht 'State '())
    (hashtable-set! ht 'Reader '())
    (let ([effects (infer-handler-effects ht)])
      (and (memq 'State effects) (memq 'Reader effects) #t)))
  #t)

;; ========== typed-with-handler integration ==========

(defeffect State (get) (put val))

(define-effect-signature StateHandler
  handles: (State)
  returns: integer)

(test "typed-with-handler/basic"
  (let ([st 0])
    (typed-with-handler StateHandler
      ([State
        (get (k) (resume k st))
        (put (k v) (set! st v) (resume k (void)))])
      (State put 42)
      (State get)))
  42)

(test "typed-with-handler/computation"
  (let ([st 10])
    (typed-with-handler StateHandler
      ([State
        (get (k) (resume k st))
        (put (k v) (set! st v) (resume k (void)))])
      (State put (+ (State get) 5))
      (State get)))
  15)

(test "typed-with-handler/missing effect errors"
  (guard (exn [#t (condition-message exn)])
    (define-effect-signature TwoEffects
      handles: (State Reader)
      returns: any)
    (typed-with-handler TwoEffects
      ([State
        (get (k) (resume k 0))])
      'ok))
  "handler missing declared effects")

(test "typed-with-handler/non-sig errors"
  (guard (exn [#t (condition-message exn)])
    (typed-with-handler 'not-a-sig
      ([State (get (k) (resume k 0))])
      'ok))
  "not an effect signature")

;; ========== Multiple effects ==========

(defeffect Log (emit msg))

(define-effect-signature StateLogHandler
  handles: (State Log)
  returns: any)

(test "typed-with-handler/two effects"
  (let ([st 0] [log '()])
    (typed-with-handler StateLogHandler
      ([State
        (get (k) (resume k st))
        (put (k v) (set! st v) (resume k (void)))]
       [Log
        (emit (k msg) (set! log (append log (list msg))) (resume k (void)))])
      (State put 99)
      (Log emit "done")
      (list (State get) log)))
  '(99 ("done")))

;; ========== Signature with no effects ==========

(define-effect-signature PureHandler
  handles: ()
  returns: any)

(test "typed-with-handler/pure"
  (typed-with-handler PureHandler
    ()
    (+ 1 2))
  3)

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
