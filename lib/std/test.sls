#!chezscheme
;;; test.sls -- Compat shim for Gerbil's :std/test module
;;; Provides test-suite, test-case, check, run-tests! etc.

(library (std test)
  (export
    test-suite test-case
    check check-eq? check-not-eq?
    check-eqv? check-not-eqv?
    check-equal? check-not-equal?
    check-predicate check-exception
    check-output
    run-tests! run-test-suite!
    test-begin! test-result test-report-summary!)

  (import (chezscheme))

  ;; --- Internal state ---
  (define *test-verbose* #t)
  (define *test-suites* '())
  (define *current-suite* #f)
  (define *current-case* #f)
  (define *total-checks* 0)
  (define *total-failures* 0)
  (define *total-errors* 0)

  ;; --- Test suite record ---
  (define-record-type test-suite-rec
    (fields desc thunk (mutable cases) (mutable error))
    (protocol
      (lambda (new)
        (lambda (desc thunk)
          (new desc thunk '() #f)))))

  ;; --- Test case record ---
  (define-record-type test-case-rec
    (fields desc (mutable checks) (mutable fail) (mutable error))
    (protocol
      (lambda (new)
        (lambda (desc)
          (new desc 0 #f #f)))))

  ;; --- test-suite macro ---
  (define-syntax test-suite
    (syntax-rules ()
      [(_ desc body body* ...)
       (make-test-suite-rec desc (lambda () body body* ...))]))

  ;; --- test-case macro ---
  (define-syntax test-case
    (syntax-rules ()
      [(_ desc body body* ...)
       (run-test-case! desc (lambda () body body* ...))]))

  ;; --- check macro ---
  ;; Supports: (check expr => value)
  ;;           (check expr ? pred)
  (define-syntax check
    (syntax-rules (=> ?)
      [(_ expr => value)
       (check-equal? expr value)]
      [(_ expr ? pred)
       (check-predicate expr pred)]))

  ;; --- Check functions ---
  (define (check-eq? actual expected)
    (check-with eq? actual expected "check-eq?"))

  (define (check-not-eq? actual expected)
    (check-with (lambda (a b) (not (eq? a b))) actual expected "check-not-eq?"))

  (define (check-eqv? actual expected)
    (check-with eqv? actual expected "check-eqv?"))

  (define (check-not-eqv? actual expected)
    (check-with (lambda (a b) (not (eqv? a b))) actual expected "check-not-eqv?"))

  (define (check-equal? actual expected)
    (check-with equal? actual expected "check-equal?"))

  (define (check-not-equal? actual expected)
    (check-with (lambda (a b) (not (equal? a b))) actual expected "check-not-equal?"))

  (define (check-predicate actual pred)
    (set! *total-checks* (+ *total-checks* 1))
    (when *current-case*
      (test-case-rec-checks-set! *current-case*
        (+ (test-case-rec-checks *current-case*) 1)))
    (guard (exn
             [#t (set! *total-errors* (+ *total-errors* 1))
                 (when *current-case*
                   (test-case-rec-error-set! *current-case* exn))
                 (when *test-verbose*
                   (fprintf (current-error-port) "  ERROR: check-predicate: ~a~n" exn))])
      (let ((val actual))
        (unless (pred val)
          (set! *total-failures* (+ *total-failures* 1))
          (when *current-case*
            (test-case-rec-fail-set! *current-case*
              (format "predicate failed for value: ~s" val)))
          (when *test-verbose*
            (fprintf (current-error-port) "  FAIL: predicate failed for ~s~n" val))))))

  (define (check-exception thunk . pred)
    (set! *total-checks* (+ *total-checks* 1))
    (when *current-case*
      (test-case-rec-checks-set! *current-case*
        (+ (test-case-rec-checks *current-case*) 1)))
    (guard (exn
             [#t (if (and (pair? pred) ((car pred) exn))
                   (void) ;; expected exception matched
                   (if (null? pred)
                     (void) ;; any exception is fine
                     (begin
                       (set! *total-failures* (+ *total-failures* 1))
                       (when *current-case*
                         (test-case-rec-fail-set! *current-case*
                           (format "wrong exception type: ~s" exn))))))])
      (thunk)
      ;; If we get here, no exception was raised
      (set! *total-failures* (+ *total-failures* 1))
      (when *current-case*
        (test-case-rec-fail-set! *current-case* "expected exception, none raised"))
      (when *test-verbose*
        (fprintf (current-error-port) "  FAIL: expected exception~n"))))

  (define-syntax check-output
    (syntax-rules (=>)
      [(_ body ... => expected)
       (let ((actual (with-output-to-string (lambda () body ...))))
         (check-equal? actual expected))]))

  (define (check-with cmp actual expected label)
    (set! *total-checks* (+ *total-checks* 1))
    (when *current-case*
      (test-case-rec-checks-set! *current-case*
        (+ (test-case-rec-checks *current-case*) 1)))
    (guard (exn
             [#t (set! *total-errors* (+ *total-errors* 1))
                 (when *current-case*
                   (test-case-rec-error-set! *current-case* exn))
                 (when *test-verbose*
                   (fprintf (current-error-port) "  ERROR in ~a: ~a~n" label exn))])
      (unless (cmp actual expected)
        (set! *total-failures* (+ *total-failures* 1))
        (when *current-case*
          (test-case-rec-fail-set! *current-case*
            (format "expected ~s, got ~s" expected actual)))
        (when *test-verbose*
          (fprintf (current-error-port) "  FAIL ~a: expected ~s, got ~s~n"
                   label expected actual)))))

  ;; --- Test execution ---
  (define (run-test-case! desc thunk)
    (let ((tc (make-test-case-rec desc)))
      (when *current-suite*
        (test-suite-rec-cases-set! *current-suite*
          (append (test-suite-rec-cases *current-suite*) (list tc))))
      (let ((saved *current-case*))
        (set! *current-case* tc)
        (when *test-verbose*
          (fprintf (current-error-port) " ~a~n" desc))
        (guard (exn
                 [#t (set! *total-errors* (+ *total-errors* 1))
                     (test-case-rec-error-set! tc exn)
                     (when *test-verbose*
                       (fprintf (current-error-port) "  ERROR: ~a~n" exn))])
          (thunk))
        (set! *current-case* saved)
        ;; Print result
        (when *test-verbose*
          (cond
            ((test-case-rec-error tc)
             (fprintf (current-error-port) "  ... ~a ERROR~n" desc))
            ((test-case-rec-fail tc)
             (fprintf (current-error-port) "  ... ~a FAIL~n" desc))
            (else
             (fprintf (current-error-port) "  ... ~a OK (~a checks)~n"
                      desc (test-case-rec-checks tc))))))))

  (define (run-test-suite! suite)
    (let ((saved *current-suite*))
      (set! *current-suite* suite)
      (fprintf (current-error-port) "~n~a~n" (test-suite-rec-desc suite))
      (guard (exn
               [#t (set! *total-errors* (+ *total-errors* 1))
                   (test-suite-rec-error-set! suite exn)
                   (fprintf (current-error-port) "SUITE ERROR: ~a~n" exn)])
        ((test-suite-rec-thunk suite)))
      (set! *current-suite* saved)
      (set! *test-suites* (append *test-suites* (list suite)))
      ;; Return #t if no failures/errors
      (and (not (test-suite-rec-error suite))
           (for-all (lambda (tc)
                      (and (not (test-case-rec-fail tc))
                           (not (test-case-rec-error tc))))
                    (test-suite-rec-cases suite)))))

  (define (run-tests! suite . more)
    (test-begin!)
    (let ((all-ok (fold-left
                    (lambda (ok s)
                      (and (run-test-suite! s) ok))
                    #t (cons suite more))))
      (test-report-summary!)
      all-ok))

  (define (test-begin!)
    (set! *test-suites* '())
    (set! *total-checks* 0)
    (set! *total-failures* 0)
    (set! *total-errors* 0))

  (define (test-result)
    (if (and (= *total-failures* 0) (= *total-errors* 0))
      'OK
      'FAILURE))

  (define (test-report-summary!)
    (fprintf (current-error-port)
             "~n~a: ~a checks, ~a failures, ~a errors~n"
             (test-result) *total-checks* *total-failures* *total-errors*))

  ) ;; end library
