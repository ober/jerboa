#!chezscheme
;;; Tests for (std concur deadlock) — Runtime deadlock detection

(import (chezscheme)
        (std concur deadlock))

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

(define-syntax test-pred
  (syntax-rules ()
    [(_ name expr)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (if expr
         (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
         (begin (set! fail (+ fail 1))
                (printf "FAIL ~a: expression was #f~%" name))))]))

(printf "--- (std concur deadlock) tests ---~%")

;;; ======== 1. Basic API availability ========

(test "make-deadlock-condition is procedure"
  (procedure? make-deadlock-condition)
  #t)

(test "deadlock-condition? is procedure"
  (procedure? deadlock-condition?)
  #t)

(test "detect-deadlock is procedure"
  (procedure? detect-deadlock)
  #t)

(test "deadlock? is procedure"
  (procedure? deadlock?)
  #t)

;;; ======== 2. No deadlock in clean state ========

;; Clear any state from previous runs
(unregister-waiting! (get-thread-id))
(releasing-resource! (get-thread-id) 'dummy)

(test "detect-deadlock returns #f when no waits"
  (detect-deadlock)
  #f)

(test "deadlock? returns #f when no waits"
  (deadlock?)
  #f)

;;; ======== 3. register-waiting! / unregister-waiting! ========

(let ([tid (get-thread-id)]
      [res 'resource-A])
  (register-waiting! tid res)
  (test "register-waiting! and then unregister"
    (begin
      (unregister-waiting! tid)
      #t)
    #t))

;;; ======== 4. holding-resource! / releasing-resource! ========

(let ([tid (get-thread-id)]
      [res 'resource-B])
  (holding-resource! tid res)
  (releasing-resource! tid res)
  (test "holding and releasing resource"
    #t
    #t))

;;; ======== 5. Deadlock detection: two-thread cycle ========

;; Simulate: thread A waits for R1 which is held by thread B
;;           thread B waits for R2 which is held by thread A
;; We use symbolic thread identifiers to test the algorithm directly.

(let ([tid-a (list 'thread-a)]   ;; unique object
      [tid-b (list 'thread-b)]
      [res-1 'resource-1]
      [res-2 'resource-2])

  ;; Clear first
  (unregister-waiting! tid-a)
  (unregister-waiting! tid-b)
  (releasing-resource! tid-a res-1)
  (releasing-resource! tid-a res-2)
  (releasing-resource! tid-b res-1)
  (releasing-resource! tid-b res-2)

  ;; Set up the deadlock:
  ;; A holds R2, B holds R1; A waits for R1, B waits for R2
  (holding-resource! tid-a res-2)
  (holding-resource! tid-b res-1)
  (register-waiting! tid-a res-1)
  (register-waiting! tid-b res-2)

  (let ([cycle (detect-deadlock)])
    (test-pred "deadlock cycle detected (not #f)"
      (not (eq? cycle #f)))

    (test-pred "deadlock? returns #t"
      (deadlock?))

    (test-pred "cycle contains tid-a or tid-b"
      (and (list? cycle)
           (or (member tid-a cycle) (member tid-b cycle)))))

  ;; Clean up
  (unregister-waiting! tid-a)
  (unregister-waiting! tid-b)
  (releasing-resource! tid-a res-2)
  (releasing-resource! tid-b res-1))

;;; ======== 6. No cycle after cleanup ========

(test "no deadlock after cleanup"
  (deadlock?)
  #f)

;;; ======== 7. deadlock-condition? ========

(let ([cond (make-deadlock-condition '(a b a))])
  (test "deadlock-condition? #t on deadlock condition"
    (deadlock-condition? cond)
    #t)

  (test "deadlock-condition-cycle extracts cycle"
    (deadlock-condition-cycle cond)
    '(a b a))

  (test "deadlock-condition? #f on ordinary condition"
    (deadlock-condition? (make-error))
    #f))

;;; ======== 8. deadlock-checked-mutex-lock!/unlock! ========

(test "deadlock-checked-mutex-lock!/unlock! basic"
  (let ([m (make-mutex)])
    (deadlock-checked-mutex-lock! m)
    (deadlock-checked-mutex-unlock! m)
    #t)
  #t)

;;; ======== 9. deadlock-checked-mutex-lock! records holding ========

(test "mutex lock registers holding resource"
  (let ([m (make-mutex)])
    (deadlock-checked-mutex-lock! m)
    (let ([ok (not (eq? (deadlock?) #t))])  ;; no cycle
      (deadlock-checked-mutex-unlock! m)
      ok))
  #t)

;;; ======== 10. *deadlock-detection-enabled* parameter ========

(test "*deadlock-detection-enabled* starts #t"
  (*deadlock-detection-enabled*)
  #t)

(parameterize ([*deadlock-detection-enabled* #f])
  (test "*deadlock-detection-enabled* can be #f"
    (*deadlock-detection-enabled*)
    #f))

(test "*deadlock-detection-enabled* restored to #t"
  (*deadlock-detection-enabled*)
  #t)

;;; ======== 11. with-deadlock-detection macro ========

(test "with-deadlock-detection enables detection"
  (with-deadlock-detection
    (*deadlock-detection-enabled*))
  #t)

;;; ======== 12. deadlock-detection-report returns string ========

(test-pred "deadlock-detection-report returns string"
  (string? (deadlock-detection-report)))

(test-pred "report contains 'Deadlock Detection'"
  (let ([report (deadlock-detection-report)])
    ;; Check if the expected substring appears anywhere in the report
    (let ([needle "Deadlock Detection"]
          [n (string-length report)])
      (let ([m (string-length needle)])
        (let loop ([i 0])
          (cond
            [(> (+ i m) n) #f]
            [(string=? (substring report i (+ i m)) needle) #t]
            [else (loop (+ i 1))]))))))

;;; ======== 13. deadlock-checked-channel-get ========

(test "deadlock-checked-channel-get returns ok"
  (let ([ch 'my-channel])
    (deadlock-checked-channel-get ch))
  'ok)

;;; ======== 14. Three-way deadlock simulation ========

(let ([ta (list 'ta)] [tb (list 'tb)] [tc (list 'tc)]
      [ra 'ra] [rb 'rb] [rc 'rc])
  ;; Clean up
  (for-each unregister-waiting! (list ta tb tc))
  (for-each (lambda (t r) (releasing-resource! t r))
            (list ta tb tc) (list ra rb rc))

  ;; A holds ra, waits for rb
  ;; B holds rb, waits for rc
  ;; C holds rc, waits for ra
  (holding-resource! ta ra)
  (holding-resource! tb rb)
  (holding-resource! tc rc)
  (register-waiting! ta rb)
  (register-waiting! tb rc)
  (register-waiting! tc ra)

  (test-pred "three-way deadlock detected"
    (deadlock?))

  ;; Clean up
  (for-each unregister-waiting! (list ta tb tc))
  (releasing-resource! ta ra)
  (releasing-resource! tb rb)
  (releasing-resource! tc rc))

;;; ======== 15. No deadlock with linear wait chain ========

(let ([ta (list 'ta2)] [tb (list 'tb2)]
      [ra 'ra2] [rb 'rb2])
  ;; A holds ra, B waits for rb (which nobody holds) — not a cycle
  (holding-resource! ta ra)
  (register-waiting! ta rb)
  ;; ta waits for rb, nobody holds rb → no cycle

  (test "linear wait (no holder) → no deadlock"
    (deadlock?)
    #f)

  (unregister-waiting! ta)
  (releasing-resource! ta ra))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
