#!/usr/bin/env scheme-script
;;; Tests for User-Defined cp0 Optimization Passes

(import 
  (rnrs)
  (std compiler passes)
  (std match2)
  (std misc list)
  (std typed)
  (only (chezscheme) printf))

;; Test framework
(define test-count 0)
(define pass-count 0)
(define fail-count 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (begin
       (set! test-count (+ test-count 1))
       (let ([result expr])
         (if (equal? result expected)
           (begin
             (printf "PASS: ~a~n" name)
             (set! pass-count (+ pass-count 1)))
           (begin
             (printf "FAIL: ~a~n" name)
             (printf "  Expected: ~s~n" expected)
             (printf "  Got:      ~s~n" result)
             (set! fail-count (+ fail-count 1))))))]))

(define-syntax test-true
  (syntax-rules ()
    [(_ name expr)
     (test name expr #t)]))

(define-syntax test-false
  (syntax-rules ()
    [(_ name expr)
     (test name expr #f)]))

(printf "Testing User-Defined cp0 Optimization Passes~n")
(printf "===========================================~n~n")

;; Test built-in constant folding pass
(printf "--- Constant Folding Pass ---~n")
(let ([transformer (cp0-pass-transformer pass:constant-fold)])
  (test "fold addition" (transformer '(+ 2 3)) 5)
  (test "fold subtraction" (transformer '(- 5 2)) 3)
  (test "fold multiplication" (transformer '(* 3 4)) 12)
  (test "fold string-append" 
        (transformer '(string-append "hello" " world"))
        "hello world")
  (test "no fold with variables" (transformer '(+ x 3)) #f))

;; Test dead code elimination pass  
(printf "~n--- Dead Code Elimination Pass ---~n")
(let ([transformer (cp0-pass-transformer pass:dead-code-eliminate)])
  (test "eliminate if true" (transformer '(if #t then else)) 'then)
  (test "eliminate if false" (transformer '(if #f then else)) 'else)
  (test "eliminate when false" (transformer '(when #f body)) '(void))
  (test "eliminate unless true" (transformer '(unless #t body)) '(void))
  (test "eliminate and with false" (transformer '(and #f x y)) #f)
  (test "eliminate or with true" (transformer '(or #t x y)) #t))

;; Test pass registration and management
(printf "~n--- Pass Registration ---~n")

;; Create a custom pass for testing
(define test-pass
  (make-cp0-pass
    'test-pass
    "A test optimization pass"
    (lambda (expr)
      (if (equal? expr '(test-transform))
        '(transformed)
        #f))
    100
    #t))

(register-optimization-pass! test-pass 99)

(test "pass registered" 
      (member 'test-pass (map car (list-optimization-passes)))
      '(test-pass))

;; Test pass execution
(printf "~n--- Custom Pass Execution ---~n")
(let ([transformer (cp0-pass-transformer test-pass)])
  (test "custom transform" (transformer '(test-transform)) '(transformed))
  (test "no transform" (transformer '(other-expr)) #f))

;; Test pass composition
(printf "~n--- Pass Composition ---~n")
(let ([composed (compose-passes pass:constant-fold pass:dead-code-eliminate)])
  (test "composed passes work" 
        (composed '(+ 2 3))
        5))  ; Should first try constant folding

;; Create domain-specific passes
(printf "~n--- Domain-Specific Passes ---~n")

;; Matrix fusion pass using simplified syntax
(define-cp0-pass matrix-fusion
  "Fuse consecutive matrix operations to avoid intermediate allocations"
  (lambda (expr)
    (match expr
      [(list 'matrix-* (list 'matrix-* a b) c)
       (list 'matrix-*-fused a b c)]
      [_ #f]))
  50)

(register-optimization-pass! matrix-fusion 50)

(let ([transformer (cp0-pass-transformer matrix-fusion)])
  (test "matrix fusion" 
        (transformer '(matrix-* (matrix-* A B) C))
        '(matrix-*-fused A B C)))

;; SQL query fusion pass
(define-cp0-pass sql-query-fusion
  "Combine consecutive SQL operations into single query"
  (lambda (expr)
    (match expr
      [(list 'sql-filter pred (list 'sql-map fn table))
       (list 'sql-filter-map pred fn table)]
      [_ #f]))
  45)

(register-optimization-pass! sql-query-fusion 45)

(let ([transformer (cp0-pass-transformer sql-query-fusion)])
  (test "sql fusion"
        (transformer '(sql-filter even? (sql-map square users)))
        '(sql-filter-map even? square users)))

;; Test debugging functionality
(printf "~n--- Debugging Features ---~n")
(enable-pass-debug!)
(test-true "debug enabled" (pass-debug-enabled?))
(disable-pass-debug!)
(test-false "debug disabled" (pass-debug-enabled?))

;; Test pass priority ordering
(printf "~n--- Pass Priority Ordering ---~n")
(let ([passes (list-optimization-passes)])
  (test-true "passes sorted by priority"
    (let loop ([p passes])
      (cond
        [(<= (length p) 1) #t]
        [(<= (caddr (car p)) (caddr (cadr p))) (loop (cdr p))]
        [else #f]))))

;; Test unregistration
(printf "~n--- Pass Unregistration ---~n")
(unregister-optimization-pass! 'test-pass)
(test "pass unregistered"
      (if (member 'test-pass (map car (list-optimization-passes))) #t #f)
      #f)

;; Test apply-optimization-passes 
(printf "~n--- Apply All Passes ---~n")
(test "apply passes to expression"
      (apply-optimization-passes '(+ 1 2))
      3)  ; Should be folded by constant-fold pass

;; Performance test - create many passes
(printf "~n--- Performance Tests ---~n")
(let ([start-time (current-time)])
  (for-each (lambda (i)
              (let ([pass (make-cp0-pass
                            (string->symbol (format "perf-pass-~a" i))
                            "Performance test pass"
                            (lambda (x) #f)
                            i
                            #t)])
                (register-optimization-pass! pass i)))
            (iota 50))
  (let ([end-time (current-time)]
        [num-passes (length (list-optimization-passes))])
    (test-true "performance test completed" (>= num-passes 50))
    (printf "Registered 50 passes in ~a seconds~n" 
            (time-second (time-difference end-time start-time)))))

;; Final results
(printf "~n===========================================~n")
(printf "Tests completed: ~a~n" test-count)
(printf "Passed: ~a~n" pass-count)
(printf "Failed: ~a~n" fail-count)
(printf "Success rate: ~a%~n" 
        (exact->inexact (/ (* pass-count 100) test-count)))

(when (> fail-count 0)
  (printf "~nSome tests failed!~n")
  (exit 1))

(printf "~nAll tests passed!~n")