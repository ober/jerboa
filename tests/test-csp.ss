#!chezscheme
;;; Tests for (std csp), (std csp select), (std csp ops), (std csp clj).
;;; Covers Phase 0 (buffer policies), Phase 1 (alts / timeout),
;;; Phase 2 (to-chan, merge, split, pipe), Phase 3 (mult, pub,
;;; pipeline, promise-chan), and the Clojure compat layer.

;; The (std csp clj) module re-exports `merge`/`go`/etc. under
;; Clojure names. `(chezscheme)` has its own `merge` (sorted-merge)
;; and `(std csp)` exports `go` as a plain function, so we shadow
;; both before importing the clj layer so the test bodies see the
;; Clojure versions.
(import (except (chezscheme) merge)
        (except (std csp) go go-named)
        (std csp select)
        (std csp ops)
        (std csp clj))

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

(define (millis ms)
  ;; helper for sleeps in tests — chez make-time takes nanos + whole secs
  (make-time 'time-duration (* ms 1000000) 0))

(printf "--- CSP / core.async ---~%~%")

;;; ======== Phase 0: buffered + buffer policies ========

(test "fixed buffer basic"
  (let ([ch (make-channel 2)])
    (chan-put! ch 1) (chan-put! ch 2) (chan-close! ch)
    (list (chan-get! ch) (chan-get! ch) (eof-object? (chan-get! ch))))
  '(1 2 #t))

(test "chan-kind fixed"
  (chan-kind (make-channel 4))
  'fixed)

(test "sliding drops oldest"
  (let ([ch (make-channel/sliding 2)])
    (chan-put! ch 1) (chan-put! ch 2)
    (chan-put! ch 3) (chan-put! ch 4)
    (chan-close! ch)
    (chan->list ch))
  '(3 4))

(test "sliding kind"
  (chan-kind (make-channel/sliding 2))
  'sliding)

(test "dropping drops incoming"
  (let ([ch (make-channel/dropping 2)])
    (chan-put! ch 1) (chan-put! ch 2)
    (chan-put! ch 3) (chan-put! ch 4)
    (chan-close! ch)
    (chan->list ch))
  '(1 2))

(test "dropping kind"
  (chan-kind (make-channel/dropping 2))
  'dropping)

(test "try-put full fixed"
  (let ([ch (make-channel 1)])
    (chan-put! ch 'first)
    (list (chan-try-put! ch 'second) (chan-get! ch)))
  '(#f first))

(test "try-put full sliding"
  (let ([ch (make-channel/sliding 1)])
    (chan-put! ch 'first)
    (chan-try-put! ch 'second)
    (chan-close! ch)
    (chan->list ch))
  '(second))

(test "chan-empty? after drain"
  (let ([ch (make-channel 2)])
    (chan-put! ch 1) (chan-get! ch)
    (chan-empty? ch))
  #t)

;;; ======== Phase 1: alts! / alt! / timeout ========

(test "alts!! take hit priority"
  (let ([c1 (make-channel 1)] [c2 (make-channel 1)])
    (chan-put! c1 'a) (chan-put! c2 'b)
    (let ([pick (alts!! (list c1 c2) 'priority)])
      (list (car pick) (eq? (cadr pick) c1))))
  '(a #t))

(test "alts!! put spec"
  (let ([c (make-channel 1)])
    (let ([pick (alts!! (list (list c 'hello)))])
      (list (car pick) (chan-get! c))))
  '(#t hello))

(test "alts!! default on empty"
  (let ([c (make-channel)])
    (let ([pick (alts!! (list c) 'default 'nothing)])
      (list (car pick) (cadr pick))))
  '(nothing default))

(test "timeout fires"
  (let ([pick (alts!! (list (timeout 20)))])
    (eof-object? (car pick)))
  #t)

(test "alt!! dispatches to winning channel"
  (let ([c1 (make-channel 1)] [c2 (make-channel 1)])
    (chan-put! c1 42)
    (alt!!
      (c1 (+ v 1))
      (c2 'from-c2)))
  43)

(test "alt!! default clause"
  (let ([c (make-channel)])
    (alt!!
      (c (+ v 1))
      (default 'fell-back)))
  'fell-back)

;;; ======== Phase 2: to-chan / merge / split / pipe-to ========

(test "to-chan drains"
  (chan->list (to-chan '(1 2 3 4 5)))
  '(1 2 3 4 5))

(test "chan-reduce sum"
  (chan-reduce + 0 (to-chan '(1 2 3 4 5)))
  15)

(test "chan-into empty list"
  (chan-into '() (to-chan '(a b c)))
  '(a b c))

(test "chan-merge fan-in"
  (list-sort <
    (chan->list
      (chan-merge (list (to-chan '(1 2 3)) (to-chan '(4 5 6))) 8)))
  '(1 2 3 4 5 6))

(test "chan-split by predicate"
  (let* ([res (chan-split even? (to-chan '(1 2 3 4 5 6)))]
         [e   (list-sort < (chan->list (car res)))]
         [o   (list-sort < (chan->list (cadr res)))])
    (list e o))
  '((2 4 6) (1 3 5)))

(test "chan-pipe-to"
  (let* ([in  (to-chan '(1 2 3))]
         [out (make-channel 8)])
    (chan-pipe-to in out)
    (chan->list out))
  '(1 2 3))

;;; ======== Phase 3: mult / pub / pipeline / promise-chan ========

(test "mult fan-out"
  (let* ([src (make-channel 4)]
         [m   (make-mult src)]
         [s1  (make-channel 8)]
         [s2  (make-channel 8)])
    (tap! m s1) (tap! m s2)
    (chan-put! src 'a) (chan-put! src 'b)
    (chan-close! src)
    (sleep (millis 80))
    (list (chan->list s1) (chan->list s2)))
  '((a b) (a b)))

(test "pub / sub by topic"
  (let* ([src (make-channel 10)]
         [p   (make-pub src car)]
         [e   (make-channel 10)]
         [o   (make-channel 10)])
    (sub! p 'even e) (sub! p 'odd o)
    (chan-put! src '(even 2))
    (chan-put! src '(odd  3))
    (chan-put! src '(even 4))
    (chan-close! src)
    (sleep (millis 100))
    (list (chan->list e) (chan->list o)))
  '(((even 2) (even 4)) ((odd 3))))

(test "pipeline ordered output"
  (let* ([in  (to-chan '(1 2 3 4 5 6 7 8 9 10))]
         [out (make-channel 20)])
    (chan-pipeline 4 out (lambda (x) (* x x)) in)
    (chan->list out))
  '(1 4 9 16 25 36 49 64 81 100))

(test "promise-channel first-put-wins"
  (let ([p (make-promise-channel)])
    (list (promise-channel-put! p 42)
          (promise-channel-put! p 99)
          (promise-channel-get! p)
          (promise-channel-get! p)))
  '(#t #f 42 42))

;;; ======== Clojure compat layer ========

(test "clj chan + >!! / <!!"
  (let ([ch (chan 2)])
    (>!! ch 10) (>!! ch 20)
    (close! ch)
    (list (<!! ch) (<!! ch) (eof-object? (<!! ch))))
  '(10 20 #t))

(test "clj sliding-buffer"
  (let ([ch (chan (sliding-buffer 2))])
    (>!! ch 'a) (>!! ch 'b) (>!! ch 'c)
    (close! ch)
    (chan->list ch))
  '(b c))

(test "clj go returns result"
  (let ([r (go (+ 1 2 3))])
    (<!! r))
  6)

(test "clj go-loop accumulator"
  (let ([r (go-loop ((i 0) (acc 0))
             (if (= i 10) acc (loop (+ i 1) (+ acc i))))])
    (<!! r))
  45)

(test "clj poll! offer!"
  (let ([ch (chan 1)])
    (list (offer! ch 'x) (poll! ch) (poll! ch)))
  '(#t x #f))

(test "clj merge fan-in"
  (list-sort <
    (chan->list (merge (list (to-chan '(1 2)) (to-chan '(3 4))) 4)))
  '(1 2 3 4))

;;; Summary

(printf "~%CSP: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
