#!chezscheme
;;; std/test/framework.sls -- Extended test framework with QuickCheck-style property testing

(library (std test framework)
  (export
    ;; Test suites
    define-test-suite run-suite run-all-suites
    suite-results suite-passed suite-failed suite-name
    ;; Property testing
    check-property for-all prop-for-all
    arbitrary-integer arbitrary-string arbitrary-list arbitrary-boolean
    ;; Test assertions
    test-case test-equal test-not-equal test-true test-false test-error
    ;; Quick-check assertions (minimal boilerplate)
    check= check-true check-false check-pred check-error
    ;; State/config
    *test-suites* with-test-output)

  (import (except (chezscheme) for-all))

  ;; ---- Internal state ----

  (define *registered-suites* '())
  (define *test-output-port* (current-output-port))
  (define *random-seed* 42)

  ;; Public getter for *test-suites* (mutable vars can't be exported directly)
  (define (*test-suites*) *registered-suites*)

  ;; ---- Simple LCG random number generator ----

  (define (next-random!)
    (set! *random-seed* (modulo (+ (* *random-seed* 1664525) 1013904223) (expt 2 32)))
    *random-seed*)

  (define (random-integer lo hi)
    ;; Returns integer in [lo, hi)
    (+ lo (modulo (next-random!) (- hi lo))))

  (define (random-boolean)
    (= (modulo (next-random!) 2) 0))

  ;; ---- Result record ----

  (define-record-type suite-result
    (fields name passed failed errors)
    (protocol
      (lambda (new)
        (lambda (name passed failed errors)
          (new name passed failed errors)))))

  ;; ---- Suite record ----

  (define-record-type suite-rec
    (fields name (mutable thunk))
    (protocol
      (lambda (new)
        (lambda (name thunk)
          (new name thunk)))))

  ;; ---- Test execution state ----

  (define *current-passed* 0)
  (define *current-failed* 0)
  (define *current-errors* 0)

  (define (reset-counts!)
    (set! *current-passed* 0)
    (set! *current-failed* 0)
    (set! *current-errors* 0))

  ;; ---- Output helpers ----

  (define (test-printf fmt . args)
    (apply fprintf *test-output-port* fmt args))

  (define (record-pass! name)
    (set! *current-passed* (+ *current-passed* 1))
    (test-printf "  ok ~a~%" name))

  (define (record-fail! name msg)
    (set! *current-failed* (+ *current-failed* 1))
    (test-printf "  FAIL ~a: ~a~%" name msg))

  (define (record-error! name exn)
    (set! *current-errors* (+ *current-errors* 1))
    (test-printf "  ERROR ~a: ~a~%" name
      (if (message-condition? exn)
          (condition-message exn)
          (format "~s" exn))))

  ;; ---- with-test-output ----

  (define-syntax with-test-output
    (syntax-rules ()
      [(_ port body ...)
       (let ([saved (get-test-output-port)])
         (set-test-output-port! port)
         (let ([result (begin body ...)])
           (set-test-output-port! saved)
           result))]))

  ;; ---- Test assertions ----

  (define-syntax test-case
    (syntax-rules ()
      [(_ name body ...)
       (guard (exn [#t (record-error! name exn)])
         body ...)]))

  (define-syntax test-equal
    (syntax-rules ()
      [(_ name actual expected)
       (guard (exn [#t (record-error! name exn)])
         (let ([got actual] [exp expected])
           (if (equal? got exp)
               (record-pass! name)
               (record-fail! name (format "got ~s, expected ~s" got exp)))))]))

  (define-syntax test-not-equal
    (syntax-rules ()
      [(_ name actual expected)
       (guard (exn [#t (record-error! name exn)])
         (let ([got actual] [exp expected])
           (if (not (equal? got exp))
               (record-pass! name)
               (record-fail! name (format "expected ~s to differ from ~s" got exp)))))]))

  (define-syntax test-true
    (syntax-rules ()
      [(_ name expr)
       (guard (exn [#t (record-error! name exn)])
         (let ([v expr])
           (if v
               (record-pass! name)
               (record-fail! name (format "expected truthy, got ~s" v)))))]))

  (define-syntax test-false
    (syntax-rules ()
      [(_ name expr)
       (guard (exn [#t (record-error! name exn)])
         (let ([v expr])
           (if (not v)
               (record-pass! name)
               (record-fail! name (format "expected #f, got ~s" v)))))]))

  (define-syntax test-error
    (syntax-rules ()
      [(_ name expr)
       (let ([raised? #f])
         (guard (exn [#t (set! raised? #t)])
           expr)
         (if raised?
             (record-pass! name)
             (record-fail! name "expected an error, none raised")))]))

  ;; ---- Suite registration helper (callable from macro expansion) ----

  (define (register-suite! s)
    (set! *registered-suites* (append *registered-suites* (list s)))
    s)

  ;; ---- Suite definition ----

  (define-syntax define-test-suite
    (syntax-rules ()
      [(_ name body ...)
       (define name
         (register-suite!
           (make-suite-rec (symbol->string 'name) (lambda () body ...))))]))

  ;; ---- Suite execution ----

  (define (run-suite suite)
    (reset-counts!)
    (test-printf "~%--- ~a ---~%" (suite-rec-name suite))
    (guard (exn [#t (record-error! (suite-rec-name suite) exn)])
      ((suite-rec-thunk suite)))
    (let ([result (make-suite-result
                    (suite-rec-name suite)
                    *current-passed*
                    *current-failed*
                    *current-errors*)])
      (test-printf "Results: ~a passed, ~a failed~%"
                   *current-passed*
                   (+ *current-failed* *current-errors*))
      result))

  (define (run-all-suites)
    (map run-suite *registered-suites*))

  ;; ---- suite-results accessors ----

  (define (suite-results result) result)
  (define suite-passed suite-result-passed)
  (define suite-failed suite-result-failed)
  (define suite-name   suite-result-name)

  ;; ---- Arbitrary generators ----

  (define (arbitrary-integer)
    (- (random-integer 0 201) 100))  ; [-100, 100]

  (define (arbitrary-boolean)
    (random-boolean))

  (define (arbitrary-string)
    (let ([len (random-integer 0 20)])
      (list->string
        (let loop ([n len] [acc '()])
          (if (= n 0)
              acc
              (loop (- n 1)
                    (cons (integer->char (+ 97 (random-integer 0 26))) acc)))))))

  (define (arbitrary-list gen)
    (let ([len (random-integer 0 10)])
      (let loop ([n len] [acc '()])
        (if (= n 0)
            acc
            (loop (- n 1) (cons (gen) acc))))))

  ;; ---- Property testing ----

  ;; Shrink an integer toward 0
  (define (shrink-integer v)
    (cond
      [(= v 0) '()]
      [(> v 0) (list 0 (quotient v 2))]
      [else    (list 0 (quotient v 2))]))

  ;; Shrink a list: try empty list, then progressively shorter
  (define (shrink-list lst)
    (if (null? lst)
        '()
        (list '() (cdr lst))))

  ;; for-all / prop-for-all: run property over N random trials
  ;; prop-for-all avoids collision with chezscheme's for-all (every/andmap)
  (define-syntax prop-for-all
    (syntax-rules ()
      [(_ ([var gen] ...) prop)
       (let loop ([n 100])
         (if (= n 0)
             #t
             (let ([var (gen)] ...)
               (if prop
                   (loop (- n 1))
                   (list var ...)))))]))

  ;; for-all is an alias - users who don't import chezscheme's for-all can use this
  (define-syntax for-all
    (syntax-rules ()
      [(_ args ...) (prop-for-all args ...)]))

  ;; ---- Output port setter (needed by with-test-output macro) ----

  (define (set-test-output-port! p)
    (set! *test-output-port* p))

  (define (get-test-output-port)
    *test-output-port*)

  ;; check-property: run property and report
  (define-syntax check-property
    (syntax-rules ()
      [(_ name prop-expr)
       (guard (exn [#t (record-error! name exn)])
         (let ([result prop-expr])
           (if (eq? result #t)
               (record-pass! name)
               (record-fail! name (format "falsified with values: ~s" result)))))]))

  ;; --- Quick-check assertions (auto-named from expression) ---
  ;; These eliminate the need for explicit test names.
  ;; (check= (+ 1 2) 3)  instead of  (test-equal "add" (+ 1 2) 3)

  (define-syntax check=
    (syntax-rules ()
      [(_ actual expected)
       (guard (exn [#t (record-error! (format "~s" 'actual) exn)])
         (let ([got actual] [exp expected])
           (if (equal? got exp)
               (record-pass! (format "~s" 'actual))
               (record-fail! (format "~s" 'actual)
                             (format "got ~s, expected ~s" got exp)))))]))

  (define-syntax check-true
    (syntax-rules ()
      [(_ expr)
       (guard (exn [#t (record-error! (format "~s" 'expr) exn)])
         (let ([v expr])
           (if v
               (record-pass! (format "~s" 'expr))
               (record-fail! (format "~s" 'expr)
                             (format "expected truthy, got ~s" v)))))]))

  (define-syntax check-false
    (syntax-rules ()
      [(_ expr)
       (guard (exn [#t (record-error! (format "~s" 'expr) exn)])
         (let ([v expr])
           (if (not v)
               (record-pass! (format "~s" 'expr))
               (record-fail! (format "~s" 'expr)
                             (format "expected #f, got ~s" v)))))]))

  (define-syntax check-pred
    (syntax-rules ()
      [(_ pred expr)
       (guard (exn [#t (record-error! (format "~s" 'expr) exn)])
         (let ([v expr])
           (if (pred v)
               (record-pass! (format "~s" 'expr))
               (record-fail! (format "~s" 'expr)
                             (format "~s did not satisfy ~s" v 'pred)))))]))

  (define-syntax check-error
    (syntax-rules ()
      [(_ expr)
       (let ([raised? #f])
         (guard (exn [#t (set! raised? #t)])
           expr)
         (if raised?
             (record-pass! (format "~s" 'expr))
             (record-fail! (format "~s" 'expr)
                           "expected an error, none raised")))]))

  ) ;; end library
