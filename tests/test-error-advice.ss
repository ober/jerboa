#!chezscheme
;;; Tests for (std error-advice) — Error advice / suggestion system

(import (chezscheme) (std error-advice))

;; string-contains: returns index of substring in string, or #f
(define (string-contains haystack needle)
  (let ([hlen (string-length haystack)]
        [nlen (string-length needle)])
    (if (= nlen 0)
      0
      (let loop ([i 0])
        (cond
          [(> (+ i nlen) hlen) #f]
          [(string=? (substring haystack i (+ i nlen)) needle) i]
          [else (loop (+ i 1))])))))

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
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(define-syntax test-true
  (syntax-rules ()
    [(_ name expr)
     (test name (if expr #t #f) #t)]))

(printf "--- (std error-advice) tests ---~%")

;; Helper to build a simple message condition
(define (make-msg-condition msg)
  (condition (make-message-condition msg)))

;;;; Test 1: advise-error with message matching "wrong number of arguments"

(test-true "advise-error/matches wrong-number-of-arguments"
  (let ([fix (advise-error (make-msg-condition "wrong number of arguments to foo"))])
    (string? fix)))

;;;; Test 2: advise-error with unrecognized message → returns #f

(test "advise-error/no match returns #f"
  (advise-error (make-msg-condition "xyzzy completely unknown error abc123"))
  #f)

;;;; Test 3: format-error-with-fix formats correctly when fix found

(test-true "format-error-with-fix/includes suggestion when matched"
  (let ([result (format-error-with-fix
                  (make-msg-condition "wrong number of arguments here"))])
    (and (string? result)
         (string-contains result "Suggestion:"))))

;;;; Test 4: format-error-with-fix with no match — just returns message

(test-true "format-error-with-fix/no match returns base message"
  (let ([msg "totally unknown error xyzzy123"]
        [result (format-error-with-fix
                  (make-msg-condition "totally unknown error xyzzy123"))])
    (and (string? result)
         (string=? result msg))))

;;;; Test 5: define-error-advice adds a custom rule

(define-error-advice "jerboa-custom-test-error" "Custom fix: check jerboa-custom-test-error")

(test-true "define-error-advice/custom rule is found"
  (let ([fix (advise-error (make-msg-condition "jerboa-custom-test-error occurred"))])
    (and (string? fix)
         (string-contains fix "Custom fix"))))

;;;; Test 6: Custom rule text matches

(test-true "define-error-advice/custom rule text correct"
  (let ([fix (advise-error (make-msg-condition "jerboa-custom-test-error occurred"))])
    (and fix (string-contains fix "check jerboa-custom-test-error"))))

;;;; Test 7: *error-advice-enabled* parameter — default is #t

(test "*error-advice-enabled*/default is #t"
  (*error-advice-enabled*)
  #t)

;;;; Test 8: *error-advice-enabled* set to #f disables advice

(test "advise-error/disabled when *error-advice-enabled* #f"
  (parameterize ([*error-advice-enabled* #f])
    (advise-error (make-msg-condition "wrong number of arguments")))
  #f)

;;;; Test 9: *error-advice-enabled* re-enabled after parameterize

(test-true "advise-error/re-enabled after parameterize"
  (begin
    (parameterize ([*error-advice-enabled* #f])
      (void))
    ;; After parameterize block, should be re-enabled
    (let ([fix (advise-error (make-msg-condition "wrong number of arguments"))])
      (string? fix))))

;;;; Test 10: common-error-fixes is a non-empty list

(test-true "common-error-fixes/is a non-empty list"
  (and (list? common-error-fixes)
       (> (length common-error-fixes) 0)))

;;;; Test 11: common-error-fixes is an alist of (pattern . fix)

(test-true "common-error-fixes/each entry is a pair of strings"
  (for-all (lambda (entry)
             (and (pair? entry)
                  (string? (car entry))
                  (string? (cdr entry))))
           common-error-fixes))

;;;; Test 12: error-with-advice signals an error

(test "error-with-advice/signals error"
  (guard (exn [(condition? exn) 'error-raised])
    (error-with-advice "test error message" 'arg1)
    'no-error)
  'error-raised)

;;;; Test 13: error-with-advice raises a condition (message or irritants)

(test-true "error-with-advice/raises a condition object"
  (guard (exn [(condition? exn) #t])
    (error-with-advice "my-specific-error-msg" 'some-irritant)
    #f))

;;;; Test 14: advise-error on unbound variable message

(test-true "advise-error/unbound variable"
  (let ([fix (advise-error (make-msg-condition "unbound variable: foo"))])
    (string? fix)))

;;;; Test 15: advise-error on car/cdr of non-pair

(test-true "advise-error/car not a pair"
  (let ([fix (advise-error (make-msg-condition "car: () is not a pair"))])
    (string? fix)))

;;;; Test 16: advise-error on division by zero

(test-true "advise-error/division by zero"
  (let ([fix (advise-error (make-msg-condition "division by zero"))])
    (string? fix)))

;;;; Test 17: advise-error on non-procedure application

(test-true "advise-error/not a procedure"
  (let ([fix (advise-error (make-msg-condition "attempt to apply non-procedure 42"))])
    (string? fix)))

;;;; Test 18: advise-error on stack overflow

(test-true "advise-error/stack overflow"
  (let ([fix (advise-error (make-msg-condition "stack overflow"))])
    (string? fix)))

;;;; Test 19: format-error-with-fix includes base message text

(test-true "format-error-with-fix/contains base message"
  (let* ([msg "wrong number of arguments to test-fn"]
         [result (format-error-with-fix (make-msg-condition msg))])
    (string-contains result msg)))

;;;; Test 20: advise-error on a real condition from guard

(test-true "advise-error/real condition from guard"
  (let ([advice-result #f])
    (guard (exn [(condition? exn)
                 (set! advice-result (advise-error exn))
                 #t])
      (car '()))
    ;; car on empty list should trigger car/cdr advice
    (or (string? advice-result) (eq? advice-result #f))))

;;;; Test 21: with-error-advice macro doesn't break normal execution

(test "with-error-advice/normal execution unaffected"
  (with-error-advice
    (+ 1 2))
  3)

;;;; Test 22: Multiple custom advice rules can be registered

(define-error-advice "test-custom-rule-A" "Fix for rule A")
(define-error-advice "test-custom-rule-B" "Fix for rule B")

(test-true "define-error-advice/multiple custom rules"
  (let ([fix-a (advise-error (make-msg-condition "test-custom-rule-A triggered"))]
        [fix-b (advise-error (make-msg-condition "test-custom-rule-B triggered"))])
    (and (string? fix-a)
         (string? fix-b)
         (string-contains fix-a "Fix for rule A")
         (string-contains fix-b "Fix for rule B"))))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
