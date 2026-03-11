#!chezscheme
;;; Tests for (std debug flamegraph) — Flame Graph Profiler

(import (chezscheme) (std debug flamegraph))

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
    [(_ name expr pred)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (pred got)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: predicate failed on ~s~%" name got)))))]))

(printf "--- (std debug flamegraph) tests ---~%")

;;; ---- make-profiler / profiler? ----

(test "make-profiler returns profiler"
  (profiler? (make-profiler))
  #t)

(test "profiler? false for non-profiler"
  (profiler? 'not-a-profiler)
  #f)

;;; ---- profiler-start! / profiler-stop! / profiler-running? ----

(test "fresh profiler is not running"
  (profiler-running? (make-profiler))
  #f)

(test "profiler-start! makes it running"
  (let ([p (make-profiler)])
    (profiler-start! p)
    (profiler-running? p))
  #t)

(test "profiler-stop! makes it not running"
  (let ([p (make-profiler)])
    (profiler-start! p)
    (profiler-stop! p)
    (profiler-running? p))
  #f)

;;; ---- profiler-reset! ----

(test "profiler-reset! clears samples"
  (let ([p (make-profiler)])
    (profiler-start! p)
    (profiler-enter! p 'foo)
    (profiler-exit! p 'foo)
    (profiler-stop! p)
    (profiler-reset! p)
    (profiler-total-samples p))
  0)

(test "profiler-reset! stops profiler"
  (let ([p (make-profiler)])
    (profiler-start! p)
    (profiler-reset! p)
    (profiler-running? p))
  #f)

;;; ---- profiler-enter! / profiler-exit! ----

(test "profiler-enter! adds a sample when running"
  (let ([p (make-profiler)])
    (profiler-start! p)
    (profiler-enter! p 'foo)
    (profiler-exit! p 'foo)
    (profiler-stop! p)
    (> (profiler-total-samples p) 0))
  #t)

(test "profiler-enter! no-op when not running"
  (let ([p (make-profiler)])
    (profiler-enter! p 'foo)
    (profiler-exit! p 'foo)
    (profiler-total-samples p))
  0)

;;; ---- profiler-samples ----

(test "profiler-samples returns list of pairs"
  (let ([p (make-profiler)])
    (profiler-start! p)
    (profiler-enter! p 'a)
    (profiler-exit! p 'a)
    (profiler-stop! p)
    (pair? (profiler-samples p)))
  #t)

(test "profiler-total-samples counts correctly"
  (let ([p (make-profiler)])
    (profiler-start! p)
    (profiler-enter! p 'a)  ;; stack: (a)         -> sample
    (profiler-enter! p 'b)  ;; stack: (b a)       -> sample
    (profiler-exit! p 'b)
    (profiler-exit! p 'a)
    (profiler-stop! p)
    (profiler-total-samples p))
  2)

;;; ---- profiler-flat-stats ----

(test "profiler-flat-stats is alist"
  (let ([p (make-profiler)])
    (profiler-start! p)
    (profiler-enter! p 'foo)
    (profiler-exit! p 'foo)
    (profiler-stop! p)
    (list? (profiler-flat-stats p)))
  #t)

(test "profiler-flat-stats includes entered function"
  (let ([p (make-profiler)])
    (profiler-start! p)
    (profiler-enter! p 'foo)
    (profiler-exit! p 'foo)
    (profiler-stop! p)
    (assoc 'foo (profiler-flat-stats p))
    ;; should be a pair (foo . count)
    (pair? (assoc 'foo (profiler-flat-stats p))))
  #t)

(test "profiler-flat-stats counts nested function"
  (let ([p (make-profiler)])
    (profiler-start! p)
    (profiler-enter! p 'outer)
    (profiler-enter! p 'inner)
    (profiler-exit! p 'inner)
    (profiler-exit! p 'outer)
    (profiler-stop! p)
    ;; outer should be counted more than inner (outer appears in both samples)
    (let ([stats (profiler-flat-stats p)])
      (and (pair? (assoc 'outer stats)) (pair? (assoc 'inner stats))))
    )
  #t)

;;; ---- profiler-hotspots ----

(test "profiler-hotspots returns list sorted by count desc"
  (let ([p (make-profiler)])
    (profiler-start! p)
    ;; enter foo 3 times (3 samples), bar 1 time (1 sample)
    (profiler-enter! p 'foo)
    (profiler-enter! p 'bar)
    (profiler-exit! p 'bar)
    (profiler-enter! p 'bar)
    (profiler-exit! p 'bar)
    (profiler-exit! p 'foo)
    (profiler-stop! p)
    ;; foo appears in all 3 samples (before bar entered and each bar sample)
    (let ([hs (profiler-hotspots p)])
      (>= (cdr (car hs)) (cdr (cadr hs)))))
  #t)

;;; ---- top-k-hotspots ----

(test "top-k-hotspots returns at most k results"
  (let ([p (make-profiler)])
    (profiler-start! p)
    (profiler-enter! p 'a)
    (profiler-enter! p 'b)
    (profiler-enter! p 'c)
    (profiler-exit! p 'c)
    (profiler-exit! p 'b)
    (profiler-exit! p 'a)
    (profiler-stop! p)
    (<= (length (top-k-hotspots p 2)) 2))
  #t)

;;; ---- with-profile macro ----

(test "with-profile records samples"
  (let ([p (make-profiler)])
    (profiler-start! p)
    (with-profile p compute
      (+ 1 2))
    (profiler-stop! p)
    (> (profiler-total-samples p) 0))
  #t)

(test "with-profile returns body value"
  (let ([p (make-profiler)])
    (profiler-start! p)
    (let ([result (with-profile p myblock (* 6 7))])
      (profiler-stop! p)
      result))
  42)

;;; ---- profile-fn ----

(test "profile-fn wraps function and records samples"
  (let* ([p (make-profiler)]
         [add (profile-fn p (lambda (x y) (+ x y)))])
    (profiler-start! p)
    (add 1 2)
    (profiler-stop! p)
    (> (profiler-total-samples p) 0))
  #t)

(test "profile-fn preserves return value"
  (let* ([p (make-profiler)]
         [square (profile-fn p (lambda (x) (* x x)))])
    (profiler-start! p)
    (let ([result (square 7)])
      (profiler-stop! p)
      result))
  49)

;;; ---- profiler->flamegraph-text ----

(test "profiler->flamegraph-text returns string"
  (let ([p (make-profiler)])
    (profiler-start! p)
    (profiler-enter! p 'main)
    (profiler-exit! p 'main)
    (profiler-stop! p)
    (string? (profiler->flamegraph-text p)))
  #t)

(test "profiler->flamegraph-text contains function name"
  (let ([p (make-profiler)])
    (profiler-start! p)
    (profiler-enter! p 'myfunction)
    (profiler-exit! p 'myfunction)
    (profiler-stop! p)
    (let ([txt (profiler->flamegraph-text p)])
      ;; Check that "myfunction" appears somewhere in the output
      (let loop ([i 0])
        (cond
          [(> (+ i 10) (string-length txt)) #f]
          [(string=? (substring txt i (+ i 10)) "myfunction") #t]
          [else (loop (+ i 1))]))))
  #t)

;;; ---- profiler->alist ----

(test "profiler->alist returns list"
  (let ([p (make-profiler)])
    (profiler-start! p)
    (profiler-enter! p 'f)
    (profiler-exit! p 'f)
    (profiler-stop! p)
    (list? (profiler->alist p)))
  #t)

;;; ---- profiler-timing-enter! / profiler-timing-exit! / profiler-timing-stats ----

(test "profiler-timing-stats returns list"
  (let ([p (make-profiler)])
    (profiler-timing-enter! p 'foo)
    (profiler-timing-exit! p 'foo)
    (list? (profiler-timing-stats p)))
  #t)

(test "profiler-timing-stats includes entered function"
  (let ([p (make-profiler)])
    (profiler-timing-enter! p 'myop)
    (profiler-timing-exit! p 'myop)
    (assoc 'myop (profiler-timing-stats p))
    (pair? (assoc 'myop (profiler-timing-stats p))))
  #t)

(test "profiler-timing-stats call count is 1 after one call"
  (let ([p (make-profiler)])
    (profiler-timing-enter! p 'op)
    (profiler-timing-exit! p 'op)
    (let ([entry (assoc 'op (profiler-timing-stats p))])
      (cadr entry)))  ;; calls count
  1)

;;; ---- with-profile/timed ----

(test "with-profile/timed records timing"
  (let ([p (make-profiler)])
    (with-profile/timed p slow-op
      (+ 1 1))
    (pair? (assoc 'slow-op (profiler-timing-stats p))))
  #t)

;;; ---- profile-fn/timed ----

(test "profile-fn/timed records timing for wrapped function"
  (let* ([p (make-profiler)]
         [f (profile-fn/timed p (lambda (x) (* x x)))])
    (f 5)
    (not (null? (profiler-timing-stats p))))
  #t)

;;; ---- profile-thunk ----

(test "profile-thunk returns plist with samples key"
  (let ([result (profile-thunk (lambda () #f))])
    (not (eq? (member 'samples result) #f)))
  #t)

(test "profile-thunk returns plist with total key"
  (let ([result (profile-thunk (lambda () #f))])
    (not (eq? (member 'total result) #f)))
  #t)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
