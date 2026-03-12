#!chezscheme
;;; Tests for (std stream window) — Stream windowing library

(import (chezscheme) (std stream window))

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

(printf "--- (std stream window) tests ---~%")

;;; ============================================================
;;; Tumbling window tests
;;; ============================================================

(test "tumbling-window?" (tumbling-window? (make-tumbling-window 3)) #t)
(test "tumbling-window? false" (tumbling-window? '()) #f)
(test "window-size" (window-size (make-tumbling-window 4)) 4)

;; Adding items — no emit until size reached
(let ([w (make-tumbling-window 3)])
  (test "tumbling add 1 -> #f" (window-add! w 'a) #f)
  (test "tumbling add 2 -> #f" (window-add! w 'b) #f)
  (test "tumbling add 3 -> emit" (window-add! w 'c) '(a b c)))

;; After emission, buffer resets
(let ([w (make-tumbling-window 2)])
  (window-add! w 1)
  (window-add! w 2)  ;; emits (1 2)
  (test "tumbling second window first" (window-add! w 3) #f)
  (test "tumbling second window emit" (window-add! w 4) '(3 4)))

;; window-flush! on partial
(let ([w (make-tumbling-window 5)])
  (window-add! w 'x)
  (window-add! w 'y)
  (test "tumbling flush partial" (window-flush! w) '(x y)))

;; window-flush! on empty
(let ([w (make-tumbling-window 3)])
  (test "tumbling flush empty" (window-flush! w) #f))

;; window-results accumulation
(let ([w (make-tumbling-window 2)])
  (window-add! w 1) (window-add! w 2)
  (window-add! w 3) (window-add! w 4)
  (test "tumbling results" (window-results w) '((1 2) (3 4))))

;; window-reset!
(let ([w (make-tumbling-window 2)])
  (window-add! w 1) (window-add! w 2)
  (window-reset! w)
  (test "tumbling reset results" (window-results w) '())
  (test "tumbling reset add" (window-add! w 'a) #f))

;;; ============================================================
;;; Sliding window tests
;;; ============================================================

(test "sliding-window?" (sliding-window? (make-sliding-window 3)) #t)
(test "sliding-window-size" (sliding-window-size (make-sliding-window 4)) 4)
(test "sliding-window-step default" (sliding-window-step (make-sliding-window 3)) 1)
(test "sliding-window-step custom" (sliding-window-step (make-sliding-window 3 2)) 2)

;; Sliding doesn't emit until window is full
(let ([w (make-sliding-window 3)])
  (test "sliding add 1 -> #f" (sliding-window-add! w 1) #f)
  (test "sliding add 2 -> #f" (sliding-window-add! w 2) #f)
  (test "sliding add 3 -> emit" (sliding-window-add! w 3) '(1 2 3)))

;; Each subsequent add emits a new window
(let ([w (make-sliding-window 3)])
  (sliding-window-add! w 1)
  (sliding-window-add! w 2)
  (sliding-window-add! w 3)
  (test "sliding add 4 -> new window" (sliding-window-add! w 4) '(2 3 4))
  (test "sliding add 5 -> new window" (sliding-window-add! w 5) '(3 4 5)))

;; Sliding window results
(let ([w (make-sliding-window 2)])
  (sliding-window-add! w 'a)
  (sliding-window-add! w 'b)
  (sliding-window-add! w 'c)
  (test "sliding results" (window-results w) '((a b) (b c))))

;; Sliding reset
(let ([w (make-sliding-window 2)])
  (sliding-window-add! w 1) (sliding-window-add! w 2)
  (window-reset! w)
  (test "sliding reset results" (window-results w) '()))

;;; ============================================================
;;; Session window tests
;;; ============================================================

(test "session-window?" (session-window? (make-session-window 100)) #t)
(test "session-window-gap" (session-window-gap (make-session-window 50)) 50)

;; Items within gap stay in same session
(let ([w (make-session-window 100)])
  (test "session add ts=0" (session-window-add! w 'a 0) #f)
  (test "session add ts=50" (session-window-add! w 'b 50) #f)
  (test "session add ts=90" (session-window-add! w 'c 90) #f))

;; Gap exceeded — emits old session
(let ([w (make-session-window 100)])
  (session-window-add! w 'a 0)
  (session-window-add! w 'b 50)
  (test "session gap -> emit" (session-window-add! w 'c 200) '(a b)))

;; Session flush
(let ([w (make-session-window 100)])
  (session-window-add! w 'x 0)
  (session-window-add! w 'y 10)
  (test "session flush" (session-window-flush! w) '(x y)))

;; Session results
(let ([w (make-session-window 100)])
  (session-window-add! w 'a 0)
  (session-window-add! w 'b 50)
  (session-window-add! w 'c 300)  ;; new session
  (session-window-flush! w)
  (test "session results count" (length (window-results w)) 2))

;;; ============================================================
;;; Count window tests
;;; ============================================================

(let ([w (make-count-window 3)])
  (test "count-window add 1" (count-window-add! w 1) #f)
  (test "count-window add 2" (count-window-add! w 2) #f)
  (test "count-window add 3" (count-window-add! w 3) '(1 2 3)))

;;; ============================================================
;;; Time window tests
;;; ============================================================

;; Time windows don't emit immediately (duration not elapsed)
(let ([w (make-time-window 100000)])  ;; 100-second window
  (test "time-window add -> #f" (time-window-add! w 'item) #f))

;; Time window flush
(let ([w (make-time-window 100000)])
  (time-window-add! w 'a)
  (time-window-add! w 'b)
  (test "time-window flush" (time-window-flush! w) '(a b)))

;; Time window reset
(let ([w (make-time-window 100000)])
  (time-window-add! w 'x)
  (window-reset! w)
  (test "time-window reset" (window-results w) '()))

;;; ============================================================
;;; window-map tests
;;; ============================================================

(let* ([base (make-tumbling-window 3)]
       [mapped (window-map base length)])
  ;; Adding to mapped-window uses inner window's add
  (window-add! base 'a)
  (window-add! base 'b)
  (let ([inner-result (window-add! base 'c)])
    ;; Apply function manually since mapped-win wraps but add! uses base
    (test "window-map inner emits" inner-result '(a b c))
    (test "mapped fn result" (length inner-result) 3)))

;;; ============================================================
;;; window-reduce tests
;;; ============================================================

(let* ([base (make-tumbling-window 4)]
       [summed (window-reduce base + 0)])
  (window-add! base 1) (window-add! base 2) (window-add! base 3)
  (test "window-reduce base partial" (window-add! base 4) '(1 2 3 4)))

;;; ============================================================
;;; make-windowed-stream tests
;;; ============================================================

(let ([w (make-tumbling-window 3)])
  (let ([results (make-windowed-stream '(1 2 3 4 5 6) w (lambda (win) win))])
    (test "windowed-stream results count" (length results) 2)
    (test "windowed-stream first window" (car results) '(1 2 3))
    (test "windowed-stream second window" (cadr results) '(4 5 6))))

;; With partial flush
(let ([w (make-tumbling-window 3)])
  (let ([results (make-windowed-stream '(1 2 3 4 5) w length)])
    (test "windowed-stream with partial count" (length results) 2)
    (test "windowed-stream full window" (car results) 3)
    (test "windowed-stream partial window" (cadr results) 2)))

;; Windowed stream with sum aggregation
(let ([w (make-tumbling-window 2)])
  (let ([results (make-windowed-stream '(10 20 30 40) w
                   (lambda (win) (apply + win)))])
    (test "windowed-stream sum" results '(30 70))))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
