#!chezscheme
;;; Tests for (std repl server) -- SWANK-like REPL server

(import (chezscheme)
        (std repl server))

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

(define (string-contains* haystack needle)
  (let ([hn (string-length haystack)]
        [nn (string-length needle)])
    (let loop ([i 0])
      (cond
        [(> (+ i nn) hn) #f]
        [(string=? (substring haystack i (+ i nn)) needle) #t]
        [else (loop (+ i 1))]))))

;; ========== Helpers ==========
(define (nc-request port msg)
  ;; Send a message via nc and get response, with retry on empty
  (define (try-once)
    (let-values ([(to-stdin from-stdout from-stderr pid)
                  (open-process-ports
                    (format "echo '~a' | nc -w 2 -q 2 127.0.0.1 ~a 2>/dev/null" msg port)
                    'line (native-transcoder))])
      (close-port to-stdin)
      (let ([response (get-line from-stdout)])
        (close-port from-stdout)
        (close-port from-stderr)
        (if (eof-object? response) "" response))))
  ;; Try up to 2 times
  (let ([r (try-once)])
    (if (string=? r "")
      (begin
        (sleep (make-time 'time-duration 200000000 0))
        (try-once))
      r)))

(printf "--- Testing (std repl server) ---~n")

;; ========== Server lifecycle ==========
(printf "  Server lifecycle...~n")
(let ([srv (repl-server-start 0)])
  (check-true (repl-server? srv))
  (check-true (repl-server-running? srv))
  (check-true (> (repl-server-port srv) 0))
  (sleep (make-time 'time-duration 100000000 0))
  (repl-server-stop srv)
  (check (repl-server-running? srv) => #f)
  (set! pass-count (+ pass-count 1)))

;; ========== Client interaction via nc ==========
(printf "  Client eval via nc...~n")
(define (brief-pause) (sleep (make-time 'time-duration 100000000 0)))
(let ([srv (repl-server-start 0)])
  (let ([port (repl-server-port srv)])
    (sleep (make-time 'time-duration 500000000 0))

    ;; Test: eval simple expression
    (let ([resp (nc-request port "(1 eval \"(+ 1 2)\")")])
      (check-true (string-contains* resp ":ok"))
      (check-true (string-contains* resp "3")))
    (brief-pause)

    ;; Test: eval with stdout
    (let ([resp (nc-request port "(2 eval \"(begin (display 42) 99)\")")])
      (check-true (string-contains* resp ":ok"))
      (check-true (string-contains* resp "99"))
      (check-true (string-contains* resp "42")))
    (brief-pause)

    ;; Test: eval error (division by zero)
    (let ([resp (nc-request port "(3 eval \"(/ 1 0)\")")])
      (check-true (string-contains* resp ":error")))
    (brief-pause)

    ;; Test: complete
    (let ([resp (nc-request port "(4 complete \"string-\")")])
      (check-true (string-contains* resp ":ok"))
      (check-true (string-contains* resp "string-append")))
    (brief-pause)

    ;; Test: doc
    (let ([resp (nc-request port "(5 doc car)")])
      (check-true (string-contains* resp ":ok"))
      (check-true (string-contains* resp "pair")))
    (brief-pause)

    ;; Test: apropos
    (let ([resp (nc-request port "(6 apropos \"hashtable\")")])
      (check-true (string-contains* resp ":ok")))
    (brief-pause)

    ;; Test: type
    (let ([resp (nc-request port "(7 type \"42\")")])
      (check-true (string-contains* resp "Fixnum")))
    (brief-pause)

    ;; Test: ping
    (let ([resp (nc-request port "(8 ping)")])
      (check-true (string-contains* resp "pong")))
    (brief-pause)

    ;; Test: pwd
    (let ([resp (nc-request port "(9 pwd)")])
      (check-true (string-contains* resp ":ok")))
    (brief-pause)

    ;; Test: env
    (let ([resp (nc-request port "(10 env \"cons\")")])
      (check-true (string-contains* resp ":ok")))
    (brief-pause)

    ;; Test: expand
    (let ([resp (nc-request port "(11 expand \"(and 1 2)\")")])
      (check-true (string-contains* resp ":ok")))

    (repl-server-stop srv)))

;; ========== Multiple server instances ==========
(printf "  Multiple servers...~n")
(let ([srv1 (repl-server-start 0)]
      [srv2 (repl-server-start 0)])
  (check-true (not (= (repl-server-port srv1) (repl-server-port srv2))))
  (repl-server-stop srv1)
  (repl-server-stop srv2)
  (set! pass-count (+ pass-count 1)))

;; ========== Summary ==========
(printf "~n--- Results: ~a passed, ~a failed ---~n" pass-count fail-count)
(when (> fail-count 0) (exit 1))
