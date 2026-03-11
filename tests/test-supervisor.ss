#!chezscheme
(import (chezscheme) (std proc supervisor))

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

(printf "--- Phase 2d: Process Supervisor ---~%~%")

;; Test 1: strategy constants
(test "one-for-one-value" one-for-one 'one-for-one)
(test "one-for-all-value" one-for-all 'one-for-all)
(test "rest-for-one-value" rest-for-one 'rest-for-one)

;; Test 2: child-spec creation
(let ([spec (child-spec 'worker (lambda () (void)))])
  (test "child-spec-id"
    (child-spec-id spec)
    'worker)
  (test "child-spec-restart-type"
    (child-spec-restart-type spec)
    'permanent)
  (test "child-spec-max-restarts"
    (child-spec-max-restarts spec)
    3))

;; Test 3: child-spec with custom restart type
(let ([spec (child-spec 'tmp (lambda () (void)) 'temporary)])
  (test "child-spec-temporary"
    (child-spec-restart-type spec)
    'temporary))

;; Test 4: make-supervisor
(let ([sup (make-supervisor one-for-one)])
  (test "supervisor-initially-no-children"
    (length (supervisor-children sup))
    0))

;; Test 5: supervisor-start-child! adds a child
(let ([sup (make-supervisor one-for-one)])
  (let ([spec (child-spec 'w1
                (lambda ()
                  (sleep (make-time 'time-duration 500000000 0))))])
    (supervisor-start-child! sup spec)
    (test "supervisor-has-one-child"
      (length (supervisor-children sup))
      1)))

;; Test 6: supervisor-run! starts monitor loop
(let ([sup (make-supervisor one-for-one)])
  (supervisor-run! sup)
  (test "supervisor-running"
    (supervisor-running? sup)
    #t)
  (supervisor-stop! sup))

;; Test 7: child runs its thunk
(let ([sup (make-supervisor one-for-one)]
      [done (make-vector 1 #f)])
  (supervisor-run! sup)
  (let ([spec (child-spec 'worker
                (lambda ()
                  (vector-set! done 0 #t))
                'temporary)])  ;; temporary: don't restart
    (supervisor-start-child! sup spec)
    (sleep (make-time 'time-duration 100000000 0))
    (test "child-ran-thunk"
      (vector-ref done 0)
      #t))
  (supervisor-stop! sup))

;; Test 8: supervisor-stop! stops all
(let ([sup (make-supervisor one-for-one)])
  (supervisor-run! sup)
  (supervisor-stop! sup)
  (test "supervisor-stopped"
    (supervisor-running? sup)
    #f))

;; Test 9: one-for-one restart — failed child restarts, others unaffected
(let ([sup (make-supervisor one-for-one)]
      [restart-count (make-vector 1 0)]
      [other-count (make-vector 1 0)])
  (supervisor-run! sup)
  ;; Child that immediately fails (will be restarted once)
  (let ([spec1 (child-spec 'crasher
                 (lambda ()
                   (vector-set! restart-count 0
                     (+ (vector-ref restart-count 0) 1))
                   (when (= (vector-ref restart-count 0) 1)
                     (error 'crasher "first run fails")))
                 'transient 1 60)])
    ;; Long-running child
    (let ([spec2 (child-spec 'stable
                  (lambda ()
                    (vector-set! other-count 0
                      (+ (vector-ref other-count 0) 1))
                    (sleep (make-time 'time-duration 1000000000 0)))
                  'temporary)])
      (supervisor-start-child! sup spec1)
      (supervisor-start-child! sup spec2)
      ;; Wait for restart
      (sleep (make-time 'time-duration 300000000 0))
      ;; crasher started twice (once, crashed, then restarted)
      (test "crasher-restarted-once"
        (>= (vector-ref restart-count 0) 2)
        #t)
      ;; stable child started only once
      (test "stable-not-restarted"
        (vector-ref other-count 0)
        1)))
  (supervisor-stop! sup))

;; Test 10: supervisor-stop-child! stops specific child
(let ([sup (make-supervisor one-for-one)]
      [counts (make-vector 2 0)])
  (supervisor-run! sup)
  (supervisor-start-child! sup
    (child-spec 'c1
      (lambda ()
        (vector-set! counts 0 (+ (vector-ref counts 0) 1))
        (sleep (make-time 'time-duration 5000000000 0)))  ;; long-running
      'temporary))
  (supervisor-start-child! sup
    (child-spec 'c2
      (lambda ()
        (vector-set! counts 1 (+ (vector-ref counts 1) 1))
        (sleep (make-time 'time-duration 5000000000 0)))
      'temporary))
  (sleep (make-time 'time-duration 50000000 0))
  (supervisor-stop-child! sup 'c1)
  (test "supervisor-still-has-2-children"
    (length (supervisor-children sup))
    2)
  (supervisor-stop! sup))

;; Test 11: supervisor-children returns list
(let ([sup (make-supervisor one-for-all)])
  (supervisor-start-child! sup (child-spec 'a (lambda () (void)) 'temporary))
  (supervisor-start-child! sup (child-spec 'b (lambda () (void)) 'temporary))
  (test "supervisor-children-length"
    (length (supervisor-children sup))
    2))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
