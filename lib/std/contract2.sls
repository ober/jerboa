#!chezscheme
;;; (std contract2) — Temporal contracts (history-sensitive)
;;;
;;; Contracts that reason about sequences of operations, not just single calls.
;;; Encode protocol state machines and check transitions at runtime.
;;;
;;; API:
;;;   (make-temporal-contract name states transitions) — create contract
;;;   (tc-state tc)                    — current state
;;;   (tc-check! tc operation)         — check and transition
;;;   (tc-reset! tc)                   — reset to initial state
;;;   (tc-history tc)                  — get transition history
;;;   (with-temporal-contract tc body ...) — body with active contract
;;;   (define-protocol/tc name clauses) — define protocol as temporal contract

(library (std contract2)
  (export make-temporal-contract tc-state tc-check! tc-reset!
          tc-history tc-valid-operations with-temporal-contract
          define-protocol/tc tc-name tc-violated?)

  (import (chezscheme))

  ;; ========== Temporal contract record ==========

  (define-record-type temporal-contract
    (fields
      (immutable name)
      (immutable initial-state)
      (immutable transitions)    ;; hashtable: (state . op) -> new-state
      (mutable current-state)
      (mutable history)          ;; list of (state op new-state)
      (mutable violated?))
    (protocol
      (lambda (new)
        (lambda (name initial-state transition-list)
          (let ([ht (make-hashtable
                      (lambda (k) (fxlogxor (symbol-hash (car k))
                                             (symbol-hash (cdr k))))
                      (lambda (a b)
                        (and (eq? (car a) (car b))
                             (eq? (cdr a) (cdr b)))))])
            (for-each
              (lambda (t)
                ;; t = (from-state operation to-state)
                (hashtable-set! ht
                  (cons (car t) (cadr t))
                  (caddr t)))
              transition-list)
            (new name initial-state ht initial-state '() #f))))))

  (define (tc-state tc) (temporal-contract-current-state tc))
  (define (tc-name tc) (temporal-contract-name tc))
  (define (tc-history tc) (reverse (temporal-contract-history tc)))
  (define (tc-violated? tc) (temporal-contract-violated? tc))

  (define (tc-valid-operations tc)
    (let ([state (temporal-contract-current-state tc)]
          [ht (temporal-contract-transitions tc)]
          [ops '()])
      (let-values ([(keys vals) (hashtable-entries ht)])
        (vector-for-each
          (lambda (key val)
            (when (eq? (car key) state)
              (set! ops (cons (cdr key) ops))))
          keys vals))
      ops))

  (define (tc-check! tc operation)
    (let* ([state (temporal-contract-current-state tc)]
           [ht (temporal-contract-transitions tc)]
           [key (cons state operation)]
           [new-state (hashtable-ref ht key #f)])
      (unless new-state
        (temporal-contract-violated?-set! tc #t)
        (error 'tc-check!
          (format "temporal contract ~a violated: ~a not allowed in state ~a (allowed: ~a)"
                  (temporal-contract-name tc)
                  operation state
                  (tc-valid-operations tc))))
      (temporal-contract-history-set! tc
        (cons (list state operation new-state)
              (temporal-contract-history tc)))
      (temporal-contract-current-state-set! tc new-state)
      new-state))

  (define (tc-reset! tc)
    (temporal-contract-current-state-set! tc
      (temporal-contract-initial-state tc))
    (temporal-contract-history-set! tc '())
    (temporal-contract-violated?-set! tc #f))

  ;; ========== with-temporal-contract ==========

  (define *active-contract* (make-thread-parameter #f))

  (define-syntax with-temporal-contract
    (syntax-rules ()
      [(_ tc body ...)
       (parameterize ([*active-contract* tc])
         body ...)]))

  ;; ========== define-protocol/tc ==========

  (define-syntax define-protocol/tc
    (syntax-rules (-> initial)
      [(_ name
          (initial init-state)
          (from -> to : op) ...)
       (define name
         (make-temporal-contract 'name 'init-state
           '((from op to) ...)))]))

) ;; end library
