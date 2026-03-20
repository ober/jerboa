#!chezscheme
;;; (std misc result) -- Result/Either Monad for Composable Error Handling
;;;
;;; A Result is either (ok value) or (err error-value).
;;; Enables railway-oriented programming without exceptions.
;;;
;;; Usage:
;;;   (import (std misc result))
;;;   (define r (ok 42))
;;;   (result-map r add1)         ; => (ok 43)
;;;   (result-bind r (lambda (x)
;;;     (if (> x 0) (ok (* x 2)) (err "negative"))))
;;;
;;;   (try->result (lambda () (/ 1 0)))  ; => (err <condition>)
;;;
;;;   ;; Pipeline
;;;   (result-> (ok "42")
;;;     (result-map string->number)
;;;     (result-bind (lambda (n) (if (> n 0) (ok n) (err "non-positive"))))
;;;     (result-map add1))
;;;   ; => (ok 43)

(library (std misc result)
  (export
    ok ok?
    err err?
    result? result-ok? result-err?
    ok-value err-value

    result-map
    result-bind
    result-and-then
    result-or-else
    result-unwrap
    result-unwrap-or
    result-fold
    result-map-err

    try->result
    result->
    results-collect
    result-guard)

  (import (chezscheme))

  ;; ========== Result Type ==========
  (define-record-type ok-rec
    (fields (immutable value))
    (sealed #t))

  (define-record-type err-rec
    (fields (immutable value))
    (sealed #t))

  (define (ok v) (make-ok-rec v))
  (define (err e) (make-err-rec e))
  (define (ok? r) (ok-rec? r))
  (define (err? r) (err-rec? r))
  (define (result? r) (or (ok-rec? r) (err-rec? r)))
  (define (result-ok? r) (ok-rec? r))
  (define (result-err? r) (err-rec? r))
  (define (ok-value r) (ok-rec-value r))
  (define (err-value r) (err-rec-value r))

  ;; ========== Combinators ==========
  (define (result-map r f)
    ;; Apply f to ok value, pass through err
    (if (ok? r)
      (ok (f (ok-value r)))
      r))

  (define (result-map-err r f)
    ;; Apply f to err value, pass through ok
    (if (err? r)
      (err (f (err-value r)))
      r))

  (define (result-bind r f)
    ;; f must return a result; flatmap/chain
    (if (ok? r)
      (f (ok-value r))
      r))

  (define (result-and-then r f)
    ;; Alias for result-bind
    (result-bind r f))

  (define (result-or-else r f)
    ;; If err, apply f to error value (f should return a result)
    (if (err? r)
      (f (err-value r))
      r))

  (define (result-unwrap r)
    ;; Extract ok value or raise error
    (if (ok? r)
      (ok-value r)
      (error 'result-unwrap "attempted to unwrap an err" (err-value r))))

  (define (result-unwrap-or r default)
    ;; Extract ok value or return default
    (if (ok? r) (ok-value r) default))

  (define (result-fold r on-ok on-err)
    ;; Pattern match on result
    (if (ok? r)
      (on-ok (ok-value r))
      (on-err (err-value r))))

  ;; ========== Conversion ==========
  (define (try->result thunk)
    ;; Run thunk, catching any exception into err
    (guard (exn [#t (err exn)])
      (ok (thunk))))

  ;; ========== Pipeline ==========
  (define-syntax result->
    (syntax-rules ()
      [(_ expr) expr]
      [(_ expr (f arg ...) rest ...)
       (result-> (f expr arg ...) rest ...)]
      [(_ expr f rest ...)
       (result-> (f expr) rest ...)]))

  ;; ========== Collection ==========
  (define (results-collect results)
    ;; List of results -> result of list
    ;; If all ok, returns (ok (list ...))
    ;; If any err, returns first err
    (let loop ([rs results] [acc '()])
      (cond
        [(null? rs) (ok (reverse acc))]
        [(err? (car rs)) (car rs)]
        [else (loop (cdr rs) (cons (ok-value (car rs)) acc))])))

  ;; ========== Guard ==========
  (define-syntax result-guard
    ;; Like guard but returns result
    (syntax-rules ()
      [(_ body ...)
       (guard (exn [#t (err exn)])
         (ok (begin body ...)))]))

) ;; end library
