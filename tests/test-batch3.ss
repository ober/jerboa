#!chezscheme
;;; Tests for batch 3: shell, template, memo, retry, time

(import (chezscheme)
        (std os shell)
        (std text template)
        (std misc memo)
        (std misc retry)
        (std time))

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

(define (string-contains* haystack needle)
  (let ([hn (string-length haystack)]
        [nn (string-length needle)])
    (let loop ([i 0])
      (cond
        [(> (+ i nn) hn) #f]
        [(string=? (substring haystack i (+ i nn)) needle) #t]
        [else (loop (+ i 1))]))))

(printf "--- Testing batch 3 modules ---~n")

;; ========== (std os shell) ==========
(printf "  Shell...~n")

;; shell: basic command
(let ([out (shell "echo hello")])
  (check-true (string-contains* out "hello")))

;; shell/lines
(let ([lines (shell/lines "printf 'a\nb\nc\n'")])
  (check (length lines) => 3)
  (check (car lines) => "a"))

;; shell/status: success
(let-values ([(out err code) (shell/status "echo ok")])
  (check code => 0)
  (check-true (string-contains* out "ok")))

;; shell/status: failure
(let-values ([(out err code) (shell/status "false")])
  (check-false (= code 0)))

;; shell!: success
(let ([out (shell! "echo works")])
  (check-true (string-contains* out "works")))

;; shell!: failure raises
(check-true (guard (exn [#t #t])
              (shell! "false")
              #f))

;; shell-pipe
(let ([out (shell-pipe "echo -e 'a\nb\nc'" "wc -l")])
  (check-true (string-contains* out "3")))

;; shell-env
(let ([out (shell-env "printenv MY_VAR" '(("MY_VAR" . "test123")))])
  (check-true (string-contains* out "test123")))

;; shell with directory
(let ([out (shell "pwd" "/tmp")])
  (check-true (string-contains* out "/tmp")))

;; shell-quote
(check (shell-quote "hello") => "hello")
(check-true (string-contains* (shell-quote "it's") "'"))

;; shell-capture
(let-values ([(out err) (shell-capture "echo captured-out; echo captured-err >&2")])
  (check-true (string-contains* out "captured-out"))
  (check-true (string-contains* err "captured-err")))

;; shell-async
(let ([proc (shell-async "echo async-output")])
  (check-true (shell-async? proc))
  (let-values ([(out err) (shell-async-wait proc)])
    (check-true (string-contains* out "async-output"))))

;; ========== (std text template) ==========
(printf "  Template...~n")

;; Simple variable substitution
(check (template-render "Hello {{name}}!" '((name . "world")))
  => "Hello world!")

;; Multiple variables
(check (template-render "{{a}} + {{b}}" '((a . "1") (b . "2")))
  => "1 + 2")

;; Missing variable → empty
(check (template-render "x={{x}}" '()) => "x=")

;; Number value
(check (template-render "n={{n}}" '((n . 42))) => "n=42")

;; Section (truthy)
(check (template-render "{{#show}}yes{{/show}}" '((show . #t))) => "yes")

;; Section (falsy)
(check (template-render "{{#show}}yes{{/show}}" '((show . #f))) => "")

;; Inverted section
(check (template-render "{{^show}}hidden{{/show}}" '((show . #f))) => "hidden")
(check (template-render "{{^show}}hidden{{/show}}" '((show . #t))) => "")

;; Iteration
(check (template-render "{{#items}}[{{.}}]{{/items}}"
         '((items "a" "b" "c")))
  => "[a][b][c]")

;; Empty list → inverted
(check (template-render "{{^items}}none{{/items}}" '((items)))
  => "none")

;; Comments removed
(check (template-render "a{{!comment}}b" '()) => "ab")

;; Compile and reuse
(let ([tpl (template-compile "{{greeting}} {{name}}!")])
  (check (tpl '((greeting . "Hi") (name . "Alice"))) => "Hi Alice!")
  (check (tpl '((greeting . "Hey") (name . "Bob"))) => "Hey Bob!"))

;; Symbol keys work too
(check (template-render "{{x}}" '((x . "val"))) => "val")

;; HTML escaping
(check (template-escape-html "<b>hi</b>") => "&lt;b&gt;hi&lt;/b&gt;")
(check (template-escape-html "a&b") => "a&amp;b")

;; make-template-env
(let ([env (make-template-env '((a . "1") (b . "2")))])
  (check (template-env-ref env "a") => "1"))

;; ========== (std misc memo) ==========
(printf "  Memo...~n")

;; Simple memoization
(define call-count 0)
(define slow-fn (memo (lambda (x)
  (set! call-count (+ call-count 1))
  (* x x))))

(check (slow-fn 5) => 25)
(check (slow-fn 5) => 25)  ;; cached
(check (slow-fn 3) => 9)
(check call-count => 2)  ;; only 2 actual calls

;; memo-stats
(let-values ([(hits misses rate) (memo-stats slow-fn)])
  (check hits => 1)
  (check misses => 2)
  (check-true (> rate 0.0)))

;; memo-size
(check (memo-size slow-fn) => 2)

;; memo-clear!
(memo-clear! slow-fn)
(check (memo-size slow-fn) => 0)

;; LRU memoization
(define lru-count 0)
(define lru-fn (memo/lru 3 (lambda (x)
  (set! lru-count (+ lru-count 1))
  x)))

(lru-fn 1) (lru-fn 2) (lru-fn 3)
(check lru-count => 3)
(lru-fn 1)  ;; cache hit
(check lru-count => 3)
(lru-fn 4)  ;; evicts oldest (2)
(check (memo-size lru-fn) => 3)
(lru-fn 2)  ;; cache miss (was evicted)
(check lru-count => 5)

;; TTL memoization
(define ttl-count 0)
(define ttl-fn (memo/ttl 10  ;; 10 second TTL
  (lambda (x)
    (set! ttl-count (+ ttl-count 1))
    (* x 2))))

(check (ttl-fn 5) => 10)
(check (ttl-fn 5) => 10)  ;; cached
(check ttl-count => 1)

;; defmemo syntax
(defmemo (square x) (* x x))
(check (square 7) => 49)
(check (square 7) => 49)

;; ========== (std misc retry) ==========
(printf "  Retry...~n")

;; retry: succeeds first try
(let ([result (retry (lambda () 42))])
  (check result => 42))

;; retry: succeeds after failures
(define retry-attempts 0)
(let ([result (retry (lambda ()
                       (set! retry-attempts (+ retry-attempts 1))
                       (when (< retry-attempts 3)
                         (error 'test "fail"))
                       99)
                     5 0.01)])
  (check result => 99)
  (check retry-attempts => 3))

;; retry: exhausts max attempts
(check-true (guard (exn [#t #t])
              (retry (lambda () (error 'test "always fails"))
                     2 0.01)
              #f))

;; retry/predicate: only retry matching errors
(define pred-attempts 0)
(check-true (guard (exn [#t #t])
              (retry/predicate
                (lambda ()
                  (set! pred-attempts (+ pred-attempts 1))
                  (error 'test "nope"))
                (lambda (exn) (< pred-attempts 2))
                3 0.01)
              #f))

;; retry-policy
(let ([p (make-retry-policy 5 0.1 10.0 #f)])
  (check (retry-policy-max-attempts p) => 5)
  (check-false (retry-policy-jitter? p)))

;; circuit-breaker
(let ([cb (make-circuit-breaker 3 60)])
  (check (circuit-breaker-state cb) => 'closed)

  ;; Record failures
  (guard (exn [#t (void)])
    (circuit-breaker-call cb (lambda () (error 'test "f1"))))
  (guard (exn [#t (void)])
    (circuit-breaker-call cb (lambda () (error 'test "f2"))))
  (guard (exn [#t (void)])
    (circuit-breaker-call cb (lambda () (error 'test "f3"))))

  ;; Should be open now
  (check (circuit-breaker-state cb) => 'open)

  ;; Calls should fail immediately
  (check-true (guard (exn [#t (string-contains*
                                (condition-message exn)
                                "circuit breaker")])
                (circuit-breaker-call cb (lambda () 'ok))
                #f))

  ;; Reset
  (circuit-breaker-reset! cb)
  (check (circuit-breaker-state cb) => 'closed)

  ;; Success after reset
  (check (circuit-breaker-call cb (lambda () 42)) => 42)

  ;; Stats
  (let ([stats (circuit-breaker-stats cb)])
    (check-true (> (cdr (assq 'total-calls stats)) 0))))

;; ========== (std time) ==========
(printf "  Time...~n")

;; current-timestamp format
(let ([ts (current-timestamp)])
  (check-true (> (string-length ts) 18))
  (check-true (string-contains* ts "T"))
  (check-true (string-contains* ts "Z")))

;; current-unix-time
(let ([t (current-unix-time)])
  (check-true (> t 1000000000))  ;; after 2001
  (check-true (flonum? t)))

;; elapsed
(let ([secs (elapsed (lambda () (+ 1 2)))])
  (check-true (>= secs 0.0))
  (check-true (< secs 1.0)))  ;; should be very fast

;; elapsed/values
(let-values ([(result secs) (elapsed/values (lambda () (* 6 7)))])
  (check result => 42)
  (check-true (>= secs 0.0)))

;; time-it (captures printed output)
(let ([out (with-output-to-string
             (lambda () (time-it "test" (lambda () (+ 1 2)))))])
  (check-true (string-contains* out "test:"))
  (check-true (string-contains* out "wall")))

;; duration->string
(check (duration->string 0.0001) => "100μs")
(check-true (string-contains* (duration->string 0.5) "ms"))
(check-true (string-contains* (duration->string 5.0) "s"))
(check-true (string-contains* (duration->string 120.0) "m"))
(check-true (string-contains* (duration->string 7200.0) "h"))
(check-true (string-contains* (duration->string 172800.0) "d"))

;; seconds->duration
(let ([d (seconds->duration 90061)])
  (check (cdr (assq 'days d)) => 1)
  (check (cdr (assq 'hours d)) => 1)
  (check (cdr (assq 'minutes d)) => 1))

;; Stopwatch
(let ([sw (make-stopwatch)])
  (check-true (stopwatch? sw))
  (stopwatch-start! sw)
  (sleep (make-time 'time-duration 10000000 0))  ;; 10ms
  (stopwatch-lap! sw "phase1")
  (sleep (make-time 'time-duration 10000000 0))
  (let ([total (stopwatch-stop! sw)])
    (check-true (> total 0.0))
    (check-true (= (length (stopwatch-laps sw)) 1))
    (check (caar (stopwatch-laps sw)) => "phase1")))

;; Stopwatch report (just ensure no error)
(let ([sw (make-stopwatch)])
  (stopwatch-start! sw)
  (stopwatch-lap! sw "a")
  (stopwatch-stop! sw)
  (let ([out (with-output-to-string (lambda () (stopwatch-report sw)))])
    (check-true (string-contains* out "Total"))))

;; Throttle
(let* ([call-log '()]
       [throttled (make-throttle 0.1
                    (lambda (x)
                      (set! call-log (cons x call-log))))])
  (throttled 1)  ;; should execute
  (throttled 2)  ;; too soon, skip
  (throttled 3)  ;; too soon, skip
  (check (length call-log) => 1)
  (check (car call-log) => 1))

;; with-timeout: succeeds
(check (with-timeout 1.0 (lambda () (+ 1 2))) => 3)

;; with-timeout: times out with default
(check (with-timeout 0.05
         (lambda () (sleep (make-time 'time-duration 0 1)) 'never)
         'timed-out)
  => 'timed-out)

;; ========== Summary ==========
(printf "~n--- Results: ~a passed, ~a failed ---~n" pass-count fail-count)
(when (> fail-count 0) (exit 1))
