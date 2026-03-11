#!chezscheme
(import (chezscheme) (std stream async))

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

(printf "--- Phase 2d: Async Streams ---~%~%")

;; Test 1: list->async-stream and async-stream->list roundtrip
(test "roundtrip-empty"
  (async-stream->list (list->async-stream '()))
  '())

(test "roundtrip-list"
  (async-stream->list (list->async-stream '(1 2 3 4 5)))
  '(1 2 3 4 5))

;; Test 2: async-stream-next! basic
(let ([s (list->async-stream '(10 20 30))])
  (let-values ([(v1 ok1) (async-stream-next! s)]
               [(v2 ok2) (async-stream-next! s)])
    (test "next-first" (and ok1 (= v1 10)) #t)
    (test "next-second" (and ok2 (= v2 20)) #t)))

;; Test 3: async-stream-next! at end
(let ([s (list->async-stream '(42))])
  (async-stream-next! s)  ;; consume the only element
  (let-values ([(v ok) (async-stream-next! s)])
    (test "next-at-eos" ok #f)))

;; Test 4: async-stream-map
(test "async-stream-map"
  (async-stream->list
    (async-stream-map (lambda (x) (* x 2))
                      (list->async-stream '(1 2 3))))
  '(2 4 6))

;; Test 5: async-stream-filter
(test "async-stream-filter"
  (async-stream->list
    (async-stream-filter odd?
                         (list->async-stream '(1 2 3 4 5))))
  '(1 3 5))

;; Test 6: async-stream-take
(test "async-stream-take"
  (async-stream->list
    (async-stream-take 3 (list->async-stream '(1 2 3 4 5))))
  '(1 2 3))

(test "async-stream-take-more-than-available"
  (async-stream->list
    (async-stream-take 10 (list->async-stream '(1 2))))
  '(1 2))

(test "async-stream-take-zero"
  (async-stream->list
    (async-stream-take 0 (list->async-stream '(1 2 3))))
  '())

;; Test 7: async-stream-for-each
(let ([result '()])
  (async-stream-for-each
    (lambda (x) (set! result (cons x result)))
    (list->async-stream '(1 2 3)))
  (test "async-stream-for-each"
    (reverse result)
    '(1 2 3)))

;; Test 8: async-stream-fold
(test "async-stream-fold-sum"
  (async-stream-fold + 0 (list->async-stream '(1 2 3 4 5)))
  15)

(test "async-stream-fold-empty"
  (async-stream-fold + 42 (list->async-stream '()))
  42)

;; Test 9: make-async-stream with producer
(test "make-async-stream-producer"
  (async-stream->list
    (make-async-stream
      (lambda (emit! done!)
        (emit! 'a)
        (emit! 'b)
        (emit! 'c)
        (done!))))
  '(a b c))

;; Test 10: composed stream operations
(test "map-then-filter"
  (async-stream->list
    (async-stream-filter (lambda (x) (> x 4))
      (async-stream-map (lambda (x) (* x 2))
        (list->async-stream '(1 2 3 4 5)))))
  '(6 8 10))

;; Test 11: async-stream-empty? on fresh empty stream
;; Note: empty? is non-blocking so might return #f for pending streams
(let ([s (list->async-stream '())])
  ;; Wait for producer to finish
  (sleep (make-time 'time-duration 50000000 0))
  (test "async-stream-empty-after-wait"
    (async-stream-empty? s)
    #t))

;; Test 12: backpressure (bounded channel)
(test "backpressure-stream"
  (async-stream->list
    (make-async-stream
      (lambda (emit! done!)
        (let loop ([i 0])
          (when (< i 20)
            (emit! i)
            (loop (+ i 1))))
        (done!))
      4)) ;; small buffer
  '(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
