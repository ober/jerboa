#!chezscheme
;;; (std contract) — Design by contract
;;;
;;; Pre/post-condition checking for defensive programming.
;;;
;;; (check-argument string? name 'my-func)
;;; (define/contract (add x y)
;;;   (pre: (number? x) (number? y))
;;;   (post: number?)
;;;   (+ x y))

(library (std contract)
  (export check-argument check-result
          contract-violation? contract-violation-who
          contract-violation-message
          define/contract pre: post:
          -> assert-contract)

  (import (chezscheme))

  ;; Condition type for contract violations
  (define-condition-type &contract-violation &violation
    make-contract-violation contract-violation?
    (who contract-violation-who)
    (msg contract-violation-message))

  (define (raise-contract-violation who msg . irritants)
    (raise (condition
            (make-contract-violation who msg)
            (make-message-condition
             (apply format #f msg irritants))
            (make-irritants-condition irritants))))

  ;; Check a function argument satisfies a predicate
  (define (check-argument pred val who)
    (unless (pred val)
      (raise-contract-violation who
        "argument failed predicate ~a: ~s" pred val)))

  ;; Check a function result satisfies a predicate
  (define (check-result pred val who)
    (unless (pred val)
      (raise-contract-violation who
        "result failed predicate ~a: ~s" pred val))
    val)

  ;; Function contract: (-> domain ... range)
  ;; Returns a wrapper that checks arguments and result
  (define (-> . preds)
    (let ([arg-preds (reverse (cdr (reverse preds)))]
          [result-pred (car (reverse preds))])
      (lambda (f)
        (lambda args
          (for-each (lambda (pred val)
                      (check-argument pred val 'contract))
                    arg-preds args)
          (let ([result (apply f args)])
            (check-result result-pred result 'contract)
            result)))))

  ;; Assert a contract inline
  (define-syntax assert-contract
    (syntax-rules ()
      [(_ pred expr)
       (let ([v expr])
         (unless (pred v)
           (error 'assert-contract
                  (format "contract ~a violated by ~s" 'pred v)))
         v)]))

  ;; Auxiliary keywords
  (define-syntax pre: (lambda (x) (syntax-violation 'pre: "misplaced" x)))
  (define-syntax post: (lambda (x) (syntax-violation 'post: "misplaced" x)))

  ;; define/contract: define with pre/post conditions
  ;; (define/contract (name args ...) (pre: checks ...) (post: pred) body ...)
  (define-syntax define/contract
    (lambda (stx)
      (syntax-case stx (pre: post:)
        [(_ (name arg ...) (pre: pre-check ...) (post: post-pred) body ...)
         #'(define (name arg ...)
             (begin
               (unless pre-check
                 (error 'name (format "precondition failed: ~a" 'pre-check)))
               ...
               (let ([result (begin body ...)])
                 (unless (post-pred result)
                   (error 'name (format "postcondition ~a failed for result: ~s"
                                        'post-pred result)))
                 result)))]
        [(_ (name arg ...) (pre: pre-check ...) body ...)
         #'(define (name arg ...)
             (begin
               (unless pre-check
                 (error 'name (format "precondition failed: ~a" 'pre-check)))
               ...
               body ...))]
        [(_ (name arg ...) (post: post-pred) body ...)
         #'(define (name arg ...)
             (let ([result (begin body ...)])
               (unless (post-pred result)
                 (error 'name (format "postcondition ~a failed for result: ~s"
                                      'post-pred result)))
               result))]
        [(_ (name arg ...) body ...)
         #'(define (name arg ...) body ...)])))

) ;; end library
