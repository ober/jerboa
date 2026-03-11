#!chezscheme
;;; (std typed linear) — Linear types: values used exactly once
;;;
;;; Linear types ensure that a value is consumed exactly once.
;;; This is enforced dynamically at runtime (static enforcement is aspirational).
;;;
;;; A linear value wraps a payload with a use-count cell.
;;; Consuming it (via linear-use) marks it as consumed; subsequent attempts error.
;;; linear-split allows splitting into N independent single-use tokens.
;;;
;;; API:
;;;   (make-linear val)              — wrap val in a linear container
;;;   (define-linear name expr)      — bind name to a fresh linear value
;;;   (linear? v)                    — #t iff v is a linear value
;;;   (linear-consumed? v)           — #t iff the linear value has been consumed
;;;   (linear-use lv proc)           — consume lv, call (proc payload), return result
;;;   (linear-split lv n)            — split lv into n linear values of the same payload
;;;   (with-linear ((name expr) ...) body ...)
;;;                                  — bind linear values, auto-check consumption
;;;   (linear-value lv)              — peek at the payload WITHOUT consuming (use sparingly)

(library (std typed linear)
  (export
    make-linear
    define-linear
    linear?
    linear-consumed?
    linear-use
    linear-split
    with-linear
    linear-value)
  (import (chezscheme))

  ;; ========== Runtime representation ==========
  ;;
  ;; A linear value is a mutable vector:
  ;;   #(linear-box <payload> <consumed?> <name-hint>)
  ;; where consumed? starts as #f and is set to #t on first use.

  (define (make-linear val)
    (vector 'linear-box val #f #f))

  (define (make-linear/named val name)
    (vector 'linear-box val #f name))

  (define (linear? v)
    (and (vector? v)
         (= (vector-length v) 4)
         (eq? (vector-ref v 0) 'linear-box)))

  (define (linear-consumed? v)
    (if (linear? v)
      (vector-ref v 2)
      (error 'linear-consumed? "not a linear value" v)))

  ;; Access the payload without consuming — intended for inspection only.
  (define (linear-value v)
    (if (linear? v)
      (begin
        (when (vector-ref v 2)
          (error 'linear-value "linear value already consumed"
                 (or (vector-ref v 3) v)))
        (vector-ref v 1))
      (error 'linear-value "not a linear value" v)))

  ;; ========== linear-use ==========
  ;;
  ;; Consume the linear value: mark as consumed, call (proc payload).
  ;; Errors if already consumed.

  (define (linear-use lv proc)
    (unless (linear? lv)
      (error 'linear-use "not a linear value" lv))
    (when (vector-ref lv 2)
      (error 'linear-use "linear value already consumed"
             (or (vector-ref lv 3) lv)))
    (vector-set! lv 2 #t)
    (proc (vector-ref lv 1)))

  ;; ========== linear-split ==========
  ;;
  ;; Consume the original linear value and produce n new linear values,
  ;; each wrapping the same payload. This allows patterns like read-only
  ;; sharing or multi-step consumption.

  (define (linear-split lv n)
    (unless (linear? lv)
      (error 'linear-split "not a linear value" lv))
    (unless (and (integer? n) (positive? n))
      (error 'linear-split "n must be a positive integer" n))
    (when (vector-ref lv 2)
      (error 'linear-split "linear value already consumed"
             (or (vector-ref lv 3) lv)))
    (vector-set! lv 2 #t)
    (let ([payload (vector-ref lv 1)])
      (let loop ([i 0] [acc '()])
        (if (= i n)
          (reverse acc)
          (loop (+ i 1) (cons (make-linear payload) acc))))))

  ;; ========== define-linear ==========
  ;;
  ;; (define-linear name expr)
  ;; Evaluates expr and wraps it in a linear value bound to name.

  (define-syntax define-linear
    (lambda (stx)
      (syntax-case stx ()
        [(_ name expr)
         (with-syntax ([name-sym (datum->syntax #'name (syntax->datum #'name))])
           #'(define name
               (make-linear/named expr 'name-sym)))])))

  ;; ========== with-linear ==========
  ;;
  ;; (with-linear ((name expr) ...) body ...)
  ;;
  ;; Binds each name to a fresh linear value wrapping expr.
  ;; After body executes, checks that all linear bindings were consumed.
  ;; Raises an error if any value remains unconsumed at scope exit.
  ;;
  ;; Note: does NOT auto-consume — it only warns/errors about leaks.

  (define-syntax with-linear
    (lambda (stx)
      (syntax-case stx ()
        [(_ ((name expr) ...) body ...)
         (with-syntax ([(nname ...) #'(name ...)]
                       [(nsym ...)  (map (lambda (n)
                                           (datum->syntax n (syntax->datum n)))
                                         (syntax->list #'(name ...)))])
           #'(let ([name (make-linear/named expr 'nsym)] ...)
               (let ([result (begin body ...)])
                 ;; Check for unconsumed linear values
                 (for-each
                   (lambda (lv sym)
                     (unless (linear-consumed? lv)
                       (error 'with-linear
                              "linear value was not consumed" sym)))
                   (list name ...)
                   '(nsym ...))
                 result)))])))

  ) ; end library
