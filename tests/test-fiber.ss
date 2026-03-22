#!/usr/bin/env scheme-script
#!chezscheme
;;; Test suite for (std fiber) — Green Threads

(import (chezscheme)
        (std fiber))

(define test-count 0)
(define pass-count 0)

(define (test name thunk)
  (set! test-count (+ test-count 1))
  (guard (e [#t (display "FAIL: ") (display name) (newline)
              (display "  Error: ") (display (condition-message e)) (newline)
              (when (irritants-condition? e)
                (display "  Irritants: ") (display (condition-irritants e)) (newline))])
    (thunk)
    (set! pass-count (+ pass-count 1))
    (display "PASS: ") (display name) (newline)))

(define (assert-equal actual expected msg)
  (unless (equal? actual expected)
    (error 'assert-equal
           (string-append msg ": expected " (format "~s" expected)
                          " got " (format "~s" actual)))))

;; =========================================================================
;; Test 1: Basic fiber spawn and completion
;; =========================================================================
(test "basic fiber spawn and run"
  (lambda ()
    (let ([result (box 0)])
      (with-fibers
        (fiber-spawn* (lambda () (set-box! result 42))))
      (assert-equal (unbox result) 42 "fiber should set result"))))

;; =========================================================================
;; Test 2: Multiple fibers run
;; =========================================================================
(test "multiple fibers all complete"
  (lambda ()
    (let ([results (make-vector 5 #f)])
      (with-fibers
        (do ([i 0 (fx+ i 1)]) ((fx= i 5))
          (let ([idx i])
            (fiber-spawn* (lambda () (vector-set! results idx idx))))))
      (assert-equal (vector->list results) '(0 1 2 3 4)
                    "all fibers should complete"))))

;; =========================================================================
;; Test 3: Fiber yield
;; =========================================================================
(test "fiber-yield allows other fibers to run"
  (lambda ()
    (let ([log '()])
      (with-fibers
        (fiber-spawn* (lambda ()
          (set! log (cons 'a1 log))
          (fiber-yield)
          (set! log (cons 'a2 log))))
        (fiber-spawn* (lambda ()
          (set! log (cons 'b1 log))
          (fiber-yield)
          (set! log (cons 'b2 log)))))
      ;; Both fibers should have completed both phases
      (assert-equal (length log) 4 "all 4 events should fire")
      (assert-equal (not (memq 'a1 log)) #f "a1 should be in log")
      (assert-equal (not (memq 'a2 log)) #f "a2 should be in log")
      (assert-equal (not (memq 'b1 log)) #f "b1 should be in log")
      (assert-equal (not (memq 'b2 log)) #f "b2 should be in log"))))

;; =========================================================================
;; Test 4: Fiber sleep
;; =========================================================================
(test "fiber-sleep suspends and resumes"
  (lambda ()
    (let ([result (box #f)])
      (with-fibers
        (fiber-spawn* (lambda ()
          (fiber-sleep 50)
          (set-box! result #t))))
      (assert-equal (unbox result) #t "fiber should resume after sleep"))))

;; =========================================================================
;; Test 5: Fiber state
;; =========================================================================
(test "fiber-done? reports completion"
  (lambda ()
    (let ([rt (make-fiber-runtime 1)]
          [f #f])
      (set! f (fiber-spawn rt (lambda () 42)))
      (assert-equal (fiber-done? f) #f "not done before run")
      (fiber-runtime-run! rt)
      (assert-equal (fiber-done? f) #t "done after run"))))

;; =========================================================================
;; Test 6: Fiber name
;; =========================================================================
(test "fiber-name returns given name"
  (lambda ()
    (let ([rt (make-fiber-runtime 1)])
      (let ([f (fiber-spawn rt (lambda () 1) "my-fiber")])
        (assert-equal (fiber-name f) "my-fiber" "name should match")
        (fiber-runtime-run! rt)))))

;; =========================================================================
;; Test 7: Fiber count
;; =========================================================================
(test "fiber-runtime-fiber-count tracks active fibers"
  (lambda ()
    (let ([rt (make-fiber-runtime 1)])
      (assert-equal (fiber-runtime-fiber-count rt) 0 "none initially")
      (fiber-spawn rt (lambda () 1))
      (fiber-spawn rt (lambda () 2))
      (assert-equal (fiber-runtime-fiber-count rt) 2 "two spawned")
      (fiber-runtime-run! rt)
      (assert-equal (fiber-runtime-fiber-count rt) 0 "all done"))))

;; =========================================================================
;; Test 8: Many fibers (stress test)
;; =========================================================================
(test "1000 fibers all complete"
  (lambda ()
    (let ([counter (box 0)]
          [mx (make-mutex)])
      (with-fibers
        (do ([i 0 (fx+ i 1)]) ((fx= i 1000))
          (fiber-spawn* (lambda ()
            (mutex-acquire mx)
            (set-box! counter (fx+ (unbox counter) 1))
            (mutex-release mx)))))
      (assert-equal (unbox counter) 1000 "all 1000 fibers ran"))))

;; =========================================================================
;; Test 9: Fiber channel basic send/recv
;; =========================================================================
(test "fiber-channel send and recv"
  (lambda ()
    (let ([result (box #f)])
      (with-fibers
        (let ([ch (make-fiber-channel)])
          (fiber-spawn* (lambda ()
            (fiber-channel-send ch 42)))
          (fiber-spawn* (lambda ()
            (set-box! result (fiber-channel-recv ch))))))
      (assert-equal (unbox result) 42 "should recv sent value"))))

;; =========================================================================
;; Test 10: Channel with multiple messages
;; =========================================================================
(test "channel multiple messages in order"
  (lambda ()
    (let ([results '()]
          [mx (make-mutex)])
      (with-fibers
        (let ([ch (make-fiber-channel)])
          (fiber-spawn* (lambda ()
            (fiber-channel-send ch 1)
            (fiber-channel-send ch 2)
            (fiber-channel-send ch 3)))
          (fiber-spawn* (lambda ()
            (let loop ([i 0])
              (when (< i 3)
                (let ([v (fiber-channel-recv ch)])
                  (mutex-acquire mx)
                  (set! results (cons v results))
                  (mutex-release mx))
                (loop (+ i 1))))))))
      (assert-equal (sort < results) '(1 2 3) "all messages received"))))

;; =========================================================================
;; Test 11: Channel try-send/try-recv
;; =========================================================================
(test "try-send and try-recv non-blocking"
  (lambda ()
    (let ([ch (make-fiber-channel 2)])
      ;; try-recv on empty should return #f
      (let-values ([(val ok) (fiber-channel-try-recv ch)])
        (assert-equal ok #f "try-recv on empty"))
      ;; try-send should succeed
      (assert-equal (fiber-channel-try-send ch 10) #t "try-send 10")
      (assert-equal (fiber-channel-try-send ch 20) #t "try-send 20")
      ;; Buffer full (cap=2)
      (assert-equal (fiber-channel-try-send ch 30) #f "try-send full")
      ;; try-recv should return values
      (let-values ([(val ok) (fiber-channel-try-recv ch)])
        (assert-equal ok #t "try-recv ok")
        (assert-equal val 10 "try-recv value")))))

;; =========================================================================
;; Test 12: Channel close
;; =========================================================================
(test "channel close prevents further sends"
  (lambda ()
    (let ([ch (make-fiber-channel)])
      (fiber-channel-close ch)
      (let ([caught #f])
        (guard (e [#t (set! caught #t)])
          (fiber-channel-send ch 1))
        (assert-equal caught #t "send on closed channel should error")))))

;; =========================================================================
;; Test 13: Preemptive scheduling (non-yielding fiber doesn't starve)
;; =========================================================================
(test "preemptive scheduling via engine fuel"
  (lambda ()
    (let ([completed (box #f)])
      (with-fibers
        ;; Fiber that does busy work without yielding
        (fiber-spawn* (lambda ()
          (let loop ([i 0])
            (when (< i 100000)
              (loop (+ i 1))))))
        ;; This fiber should also get to run thanks to preemption
        (fiber-spawn* (lambda ()
          (set-box! completed #t))))
      (assert-equal (unbox completed) #t
                    "second fiber should complete despite busy first fiber"))))

;; =========================================================================
;; Test 14: Fiber yield multiple times
;; =========================================================================
(test "fiber can yield multiple times"
  (lambda ()
    (let ([count (box 0)])
      (with-fibers
        (fiber-spawn* (lambda ()
          (set-box! count (fx+ (unbox count) 1))
          (fiber-yield)
          (set-box! count (fx+ (unbox count) 1))
          (fiber-yield)
          (set-box! count (fx+ (unbox count) 1)))))
      (assert-equal (unbox count) 3 "fiber should run all 3 phases"))))

;; =========================================================================
;; Test 15: Channel ping-pong between fibers
;; =========================================================================
(test "channel ping-pong"
  (lambda ()
    (let ([result (box 0)])
      (with-fibers
        (let ([ch1 (make-fiber-channel)]
              [ch2 (make-fiber-channel)])
          (fiber-spawn* (lambda ()
            (fiber-channel-send ch1 1)
            (let ([v (fiber-channel-recv ch2)])
              (set-box! result v))))
          (fiber-spawn* (lambda ()
            (let ([v (fiber-channel-recv ch1)])
              (fiber-channel-send ch2 (+ v 1)))))))
      (assert-equal (unbox result) 2 "ping-pong should work"))))

;; =========================================================================
;; Test 16: fiber-self returns current fiber
;; =========================================================================
(test "fiber-self returns the running fiber"
  (lambda ()
    (let ([captured-name (box #f)])
      (with-fibers
        (fiber-spawn* (lambda ()
          (set-box! captured-name (fiber-name (fiber-self))))
          "test-fiber"))
      (assert-equal (unbox captured-name) "test-fiber"
                    "fiber-self should return running fiber"))))

;; =========================================================================
;; Test 17: Runtime with explicit worker count
;; =========================================================================
(test "runtime with 1 worker"
  (lambda ()
    (let ([rt (make-fiber-runtime 1)]
          [done (box #f)])
      (fiber-spawn rt (lambda () (set-box! done #t)))
      (fiber-runtime-run! rt)
      (assert-equal (unbox done) #t "single worker completes fiber"))))

;; =========================================================================
;; Test 18: Channel as bounded buffer
;; =========================================================================
(test "bounded channel blocks sender when full"
  (lambda ()
    (let ([received '()]
          [mx (make-mutex)])
      (with-fibers
        (let ([ch (make-fiber-channel 2)])
          ;; Producer sends 5 items through a cap-2 channel
          (fiber-spawn* (lambda ()
            (do ([i 0 (fx+ i 1)]) ((fx= i 5))
              (fiber-channel-send ch i))))
          ;; Consumer reads all 5
          (fiber-spawn* (lambda ()
            (do ([i 0 (fx+ i 1)]) ((fx= i 5))
              (let ([v (fiber-channel-recv ch)])
                (mutex-acquire mx)
                (set! received (cons v received))
                (mutex-release mx)))))))
      (assert-equal (sort < received) '(0 1 2 3 4)
                    "all values flow through bounded channel"))))

;; =========================================================================
;; Summary
;; =========================================================================
(newline)
(display "=========================================") (newline)
(display (format "Results: ~a/~a passed" pass-count test-count)) (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
