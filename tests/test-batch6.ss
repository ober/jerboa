#!chezscheme
;;; Tests for batch 6: event-emitter, trie, rate-limiter, pool, state-machine

(import (chezscheme)
        (std misc event-emitter)
        (std misc trie)
        (std misc rate-limiter)
        (std misc pool)
        (std misc state-machine))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr]
           [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (printf "FAIL: ~s => ~s (expected ~s)~n" 'expr result exp))))]))

(define-syntax check-true
  (syntax-rules ()
    [(_ expr)
     (let ([result expr])
       (if result
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (printf "FAIL: ~s => ~s (expected truthy)~n" 'expr result))))]))

(define-syntax check-false
  (syntax-rules ()
    [(_ expr)
     (let ([result expr])
       (if (not result)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (printf "FAIL: ~s => ~s (expected falsy)~n" 'expr result))))]))

(printf "--- Testing batch 6 modules ---~n")

;; ========== (std misc event-emitter) ==========
(printf "  Event emitter...~n")

;; Basic on/emit
(let ([ee (make-event-emitter)]
      [received '()])
  (check-true (event-emitter? ee))
  (on ee 'data (lambda (x) (set! received (cons x received))))
  (emit ee 'data 42)
  (emit ee 'data 99)
  (check received => '(99 42)))

;; Multiple listeners
(let ([ee (make-event-emitter)]
      [log '()])
  (on ee 'msg (lambda (x) (set! log (cons (list 'a x) log))))
  (on ee 'msg (lambda (x) (set! log (cons (list 'b x) log))))
  (emit ee 'msg 1)
  (check (length log) => 2))

;; once — fires only once
(let ([ee (make-event-emitter)]
      [count 0])
  (once ee 'init (lambda () (set! count (+ count 1))))
  (emit ee 'init)
  (emit ee 'init)
  (check count => 1))

;; off — remove all listeners
(let ([ee (make-event-emitter)]
      [count 0])
  (on ee 'x (lambda () (set! count (+ count 1))))
  (emit ee 'x)
  (off ee 'x)
  (emit ee 'x)
  (check count => 1))

;; off-all
(let ([ee (make-event-emitter)])
  (on ee 'a (lambda () (void)))
  (on ee 'b (lambda () (void)))
  (off-all ee)
  (check (length (event-names ee)) => 0))

;; listener-count
(let ([ee (make-event-emitter)])
  (on ee 'x (lambda () (void)))
  (on ee 'x (lambda () (void)))
  (check (listener-count ee 'x) => 2)
  (check (listener-count ee 'y) => 0))

;; event-names
(let ([ee (make-event-emitter)])
  (on ee 'a (lambda () (void)))
  (on ee 'b (lambda () (void)))
  (check (length (event-names ee)) => 2))

;; Emit with no listeners (no crash)
(let ([ee (make-event-emitter)])
  (emit ee 'nonexistent)
  (set! pass-count (+ pass-count 1)))

;; ========== (std misc trie) ==========
(printf "  Trie...~n")

(let ([t (make-trie)])
  (check-true (trie? t))
  (check (trie-size t) => 0)

  (trie-insert! t "hello")
  (trie-insert! t "help")
  (trie-insert! t "world")
  (trie-insert! t "hero")
  (check (trie-size t) => 4)

  ;; Search
  (check-true (trie-search t "hello"))
  (check-true (trie-search t "world"))
  (check-false (trie-search t "hell"))
  (check-false (trie-search t "xyz"))

  ;; Starts with
  (check-true (trie-starts-with? t "hel"))
  (check-true (trie-starts-with? t "wor"))
  (check-false (trie-starts-with? t "xyz"))

  ;; Prefix search
  (let ([results (trie-prefix-search t "hel")])
    (check-true (member "hello" results))
    (check-true (member "help" results))
    (check-false (member "hero" results)))

  ;; Autocomplete with limit
  (let ([results (trie-autocomplete t "he" 2)])
    (check (length results) => 2))

  ;; Delete
  (trie-delete! t "hello")
  (check-false (trie-search t "hello"))
  (check (trie-size t) => 3)

  ;; All words
  (check (length (trie-words t)) => 3))

;; Duplicate insert
(let ([t (make-trie)])
  (trie-insert! t "abc")
  (trie-insert! t "abc")
  (check (trie-size t) => 1))

;; list->trie
(let ([t (list->trie '("cat" "car" "card"))])
  (check (trie-size t) => 3)
  (check-true (trie-search t "car"))
  (check-true (trie-search t "card")))

;; ========== (std misc rate-limiter) ==========
(printf "  Rate limiter...~n")

(let ([rl (make-rate-limiter 5 100.0)])  ;; 5 tokens, 100/sec refill
  (check-true (rate-limiter? rl))

  ;; Should have 5 tokens initially
  (check (rate-limiter-available rl) => 5)

  ;; Acquire tokens
  (check-true (rate-limiter-try-acquire rl))
  (check-true (rate-limiter-try-acquire rl))
  (check-true (rate-limiter-try-acquire rl))
  (check-true (rate-limiter-try-acquire rl))
  (check-true (rate-limiter-try-acquire rl))
  ;; All used up
  (check-false (rate-limiter-try-acquire rl))

  ;; Reset
  (rate-limiter-reset! rl)
  (check (rate-limiter-available rl) => 5))

;; with-rate-limit
(let ([rl (make-rate-limiter 5 100.0)]
      [result #f])
  (with-rate-limit rl (lambda () (set! result 42)))
  (check result => 42))

;; ========== (std misc pool) ==========
(printf "  Pool...~n")

;; Basic pool
(let* ([created 0]
       [destroyed 0]
       [p (make-pool
            (lambda () (set! created (+ created 1)) created)
            (lambda (r) (set! destroyed (+ destroyed 1)))
            'max-size: 3)])
  (check-true (pool? p))
  (check (pool-size p) => 0)

  ;; Acquire creates
  (let ([r1 (pool-acquire p)])
    (check (pool-size p) => 1)
    (check r1 => 1)

    ;; Release returns to pool
    (pool-release p r1)
    (check (pool-available p) => 1)

    ;; Re-acquire reuses
    (let ([r2 (pool-acquire p)])
      (check r2 => 1)  ;; same resource
      (check created => 1)  ;; no new creation
      (pool-release p r2)))

  ;; pool-with-resource
  (let ([result (pool-with-resource p (lambda (r) (* r 10)))])
    (check result => 10))

  ;; Drain
  (pool-drain! p)
  (check (pool-available p) => 0)
  (check-true (> destroyed 0)))

;; ========== (std misc state-machine) ==========
(printf "  State machine...~n")

;; Traffic light
(let ([sm (make-state-machine 'red
            `((red    (timer) green  ,void)
              (green  (timer) yellow ,void)
              (yellow (timer) red    ,void)))])
  (check-true (state-machine? sm))
  (check (sm-state sm) => 'red)

  (sm-send! sm 'timer)
  (check (sm-state sm) => 'green)

  (sm-send! sm 'timer)
  (check (sm-state sm) => 'yellow)

  (sm-send! sm 'timer)
  (check (sm-state sm) => 'red)

  ;; History
  (check (length (sm-history sm)) => 3)

  ;; can-send?
  (check-true (sm-can-send? sm 'timer))
  (check-false (sm-can-send? sm 'unknown))

  ;; Reset
  (sm-reset! sm)
  (check (sm-state sm) => 'red)
  (check (length (sm-history sm)) => 0))

;; State machine with actions
(define *sm-log* '())
(let ([sm (make-state-machine 'idle
            `((idle (start) running
                    ,(lambda () (set! *sm-log* (cons 'started *sm-log*))))
              (running (stop) idle
                       ,(lambda () (set! *sm-log* (cons 'stopped *sm-log*))))
              (running (pause) paused
                       ,(lambda () (set! *sm-log* (cons 'paused *sm-log*))))
              (paused (resume) running
                      ,(lambda () (set! *sm-log* (cons 'resumed *sm-log*))))))])
  (sm-send! sm 'start)
  (check (sm-state sm) => 'running)
  (sm-send! sm 'pause)
  (check (sm-state sm) => 'paused)
  (sm-send! sm 'resume)
  (check (sm-state sm) => 'running)
  (sm-send! sm 'stop)
  (check (sm-state sm) => 'idle)
  (check *sm-log* => '(stopped resumed paused started)))

;; Invalid transition raises error
(let ([sm (make-state-machine 'a
            `((a (go) b ,void)))])
  (check-true (guard (exn [#t #t])
                (sm-send! sm 'invalid)
                #f)))

;; on-transition callback
(let ([sm (make-state-machine 'off
            `((off (toggle) on ,void)
              (on  (toggle) off ,void)))]
      [transitions '()])
  (sm-on-transition! sm (lambda (from event to)
    (set! transitions (cons (list from to) transitions))))
  (sm-send! sm 'toggle)
  (sm-send! sm 'toggle)
  (check (length transitions) => 2)
  (check (car transitions) => '(on off)))

;; sm-transitions (valid from current state)
(let ([sm (make-state-machine 'a
            `((a (x) b ,void)
              (a (y) c ,void)
              (b (z) a ,void)))])
  (check (length (sm-transitions sm)) => 2))

;; ========== Summary ==========
(printf "~n--- Results: ~a passed, ~a failed ---~n" pass-count fail-count)
(when (> fail-count 0) (exit 1))
