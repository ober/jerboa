#!chezscheme
;;; Tests for (std health) -- Health check framework

(import (chezscheme)
        (std health))

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

(printf "--- Phase 3a: Health Checks ---~%~%")

;;; ======== Registry ========

(test "health-registry? true"
  (health-registry? (make-health-registry))
  #t)

(test "health-registry? false"
  (health-registry? 42)
  #f)

;;; ======== Registering and running checks ========

(let* ([reg (make-health-registry)])
  (register-check! reg "always-ok" (make-check (lambda () 'ok)))

  (let ([results (run-checks reg)])
    (test "run-checks returns list"
      (list? results)
      #t)

    (test "run-checks returns 1 result"
      (length results)
      1)

    (let ([r (car results)])
      (test "check-result-name"
        (check-result-name r)
        "always-ok")

      (test "check-result-status ok"
        (check-result-status r)
        'ok)

      (test "check-result-duration is number"
        (number? (check-result-duration r))
        #t)

      (test "check-result-duration non-negative"
        (>= (check-result-duration r) 0)
        #t)

      (test "check-result-message is string"
        (string? (check-result-message r))
        #t))))

;;; ======== Degraded check ========

(let* ([reg (make-health-registry)])
  (register-check! reg "degraded" (make-check (lambda () 'degraded)))

  (let* ([results (run-checks reg)]
         [r       (car results)])
    (test "degraded check status"
      (check-result-status r)
      'degraded)))

;;; ======== Failing check ========

(let* ([reg (make-health-registry)])
  (register-check! reg "failing" (make-check (lambda () 'failing)))

  (let* ([results (run-checks reg)]
         [r       (car results)])
    (test "failing check status"
      (check-result-status r)
      'failing)))

;;; ======== Check that throws → failing ========

(let* ([reg (make-health-registry)])
  (register-check! reg "throws"
    (make-check (lambda () (error "health-check" "simulated failure"))))

  (let* ([results (run-checks reg)]
         [r       (car results)])
    (test "throwing check returns failing"
      (check-result-status r)
      'failing)))

;;; ======== health-status ========

(let ([all-ok
        (list (check-result "a" 'ok "ok" 0)
              (check-result "b" 'ok "ok" 0))])
  (test "health-status all-ok → healthy"
    (health-status all-ok)
    'healthy))

(let ([with-degraded
        (list (check-result "a" 'ok       "ok"       0)
              (check-result "b" 'degraded "degraded" 0))])
  (test "health-status with-degraded → degraded"
    (health-status with-degraded)
    'degraded))

(let ([with-failing
        (list (check-result "a" 'ok      "ok"      0)
              (check-result "b" 'failing "failing" 0))])
  (test "health-status with-failing → failing"
    (health-status with-failing)
    'failing))

(let ([mixed
        (list (check-result "a" 'degraded "degraded" 0)
              (check-result "b" 'failing  "failing"  0))])
  (test "health-status failing beats degraded"
    (health-status mixed)
    'failing))

;;; ======== healthy? ========

(test "healthy? true"
  (healthy? (list (check-result "a" 'ok "ok" 0)))
  #t)

(test "healthy? false when degraded"
  (healthy? (list (check-result "a" 'degraded "degraded" 0)))
  #f)

(test "healthy? false when failing"
  (healthy? (list (check-result "a" 'failing "failing" 0)))
  #f)

;;; ======== Multiple checks ========

(let* ([reg (make-health-registry)])
  (register-check! reg "db"    (make-check (lambda () 'ok)))
  (register-check! reg "cache" (make-check (lambda () 'degraded)))
  (register-check! reg "queue" (make-check (lambda () 'ok)))

  (let ([results (run-checks reg)])
    (test "multiple checks: count"
      (length results)
      3)

    (test "multiple checks: overall degraded"
      (health-status results)
      'degraded)))

;;; ======== with-timeout-check ========

(let* ([reg (make-health-registry)]
       ;; A check that finishes instantly — should be ok with generous timeout
       [fast-check (with-timeout-check (lambda () 'ok) 10000)])
  (register-check! reg "fast" fast-check)
  (let* ([results (run-checks reg)]
         [r       (car results)])
    (test "fast check within timeout is ok"
      (check-result-status r)
      'ok)))

;;; Summary

(printf "~%Health tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
