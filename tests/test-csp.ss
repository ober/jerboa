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
        (std csp clj)
        (std transducer))

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

;;; chan-classify-by — n-way classifier. Uses `initial-keys` so we can
;;; grab per-class channels immediately without racing the helper thread.

(test "chan-classify-by — three classes with initial-keys"
  (let* ([in  (to-chan '(1 2 3 4 5 6 7 8 9))]
         [classify
          (lambda (n)
            (cond [(zero? (modulo n 3)) 'third]
                  [(even? n)             'even]
                  [else                  'odd]))]
         [tbl (chan-classify-by classify in
                                (lambda (_k) (make-channel 16))
                                '(third even odd))]
         [e   (list-sort < (chan->list (hashtable-ref tbl 'even  #f)))]
         [o   (list-sort < (chan->list (hashtable-ref tbl 'odd   #f)))]
         [t   (list-sort < (chan->list (hashtable-ref tbl 'third #f)))])
    (list e o t))
  '((2 4 8) (1 5 7) (3 6 9)))

(test "chan-classify-by — default buf-fn, two classes"
  (let* ([in  (to-chan '("aa" "bbb" "cc" "dddd" "e"))]
         [tbl (chan-classify-by string-length in)])
    ;; default buf-fn makes unbuffered channels, so we need to read on
    ;; helper threads. Use chan->list synchronously per-key since the
    ;; helper thread will block putting until we drain.
    ;; Simpler: wait for the source to drain and read via the table.
    (sleep (millis 30))
    (list (list-sort string<? (chan->list (hashtable-ref tbl 1 #f)))
          (list-sort string<? (chan->list (hashtable-ref tbl 2 #f)))
          (list-sort string<? (chan->list (hashtable-ref tbl 3 #f)))
          (list-sort string<? (chan->list (hashtable-ref tbl 4 #f)))))
  '(("e") ("aa" "cc") ("bbb") ("dddd")))

(test "chan-classify-by — initial-keys eager channels are closed on EOF"
  (let* ([in  (to-chan '())]    ;; empty source
         [tbl (chan-classify-by car in
                                (lambda (_k) (make-channel 4))
                                '(a b c))])
    (sleep (millis 20))
    (list (eof-object? (chan-get! (hashtable-ref tbl 'a #f)))
          (eof-object? (chan-get! (hashtable-ref tbl 'b #f)))
          (eof-object? (chan-get! (hashtable-ref tbl 'c #f)))))
  '(#t #t #t))

(test "chan-classify-by — new keys appear in table as they are seen"
  (let* ([in  (to-chan '(apple ant banana bear cherry))]
         [tbl (chan-classify-by
                (lambda (sym) (string-ref (symbol->string sym) 0))
                in
                (lambda (_k) (make-channel 8)))])
    ;; Drain helper: wait until classifier has processed everything, then
    ;; enumerate the keys in the table.
    (sleep (millis 30))
    (list
      (list-sort < (map char->integer (vector->list
        (hashtable-keys tbl))))
      (chan->list (hashtable-ref tbl #\a #f))
      (chan->list (hashtable-ref tbl #\b #f))
      (chan->list (hashtable-ref tbl #\c #f))))
  (list (list-sort < (list (char->integer #\a)
                           (char->integer #\b)
                           (char->integer #\c)))
        '(apple ant)
        '(banana bear)
        '(cherry)))

;; Clojure-style split-by alias
(test "split-by — Clojure alias for chan-classify-by"
  (let* ([in  (to-chan '(1 2 3 4 5 6))]
         [tbl (split-by (lambda (n) (if (even? n) 'even 'odd))
                        in
                        (lambda (_k) (make-channel 8))
                        '(even odd))])
    (list (list-sort < (chan->list (hashtable-ref tbl 'even #f)))
          (list-sort < (chan->list (hashtable-ref tbl 'odd  #f)))))
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

;;; ======== Transducer-backed channels (Phase A.2) ========

(test "chan/mapping — increments every put"
  (let ([ch (chan 8 (mapping (lambda (x) (+ x 1))))])
    (chan-put! ch 1) (chan-put! ch 2) (chan-put! ch 3)
    (chan-close! ch)
    (chan->list ch))
  '(2 3 4))

(test "chan/filtering — keeps only evens"
  (let ([ch (chan 8 (filtering even?))])
    (for-each (lambda (x) (chan-put! ch x)) '(1 2 3 4 5 6))
    (chan-close! ch)
    (chan->list ch))
  '(2 4 6))

(test "chan/taking — early-stop closes channel"
  (let ([ch (chan 8 (taking 3))])
    ;; Put 5 values; only first 3 survive, and channel is auto-closed
    ;; after the 3rd by the reduced? signal.
    (chan-put! ch 'a) (chan-put! ch 'b) (chan-put! ch 'c)
    ;; Subsequent try-puts should fail because ch is closed.
    (let ([drained (chan->list ch)]
          [after   (chan-try-put! ch 'd)])
      (list drained after)))
  '((a b c) #f))

(test "chan/flat-mapping — one input produces many outputs"
  (let ([ch (chan 16 (flat-mapping (lambda (x) (list x (* x 10)))))])
    (chan-put! ch 1) (chan-put! ch 2)
    (chan-close! ch)
    (chan->list ch))
  '(1 10 2 20))

(test "chan/composed — filter then map then take"
  (let ([ch (chan 32
              (compose-transducers
                (filtering odd?)
                (mapping (lambda (x) (* x x)))
                (taking 3)))])
    ;; Use chan-try-put! so a closed channel (after taking stops) simply
    ;; returns #f instead of raising. Then drain to see the survivors.
    (for-each (lambda (x) (chan-try-put! ch x)) '(1 2 3 4 5 6 7 8 9 10))
    (chan->list ch))
  '(1 9 25))

(test "chan/partitioning-by — close flushes pending partition"
  (let ([ch (chan 16 (partitioning-by even?))])
    (for-each (lambda (x) (chan-put! ch x)) '(1 3 2 4 5 7))
    (chan-close! ch)
    (chan->list ch))
  '((1 3) (2 4) (5 7)))

(test "chan/ex-handler — exception routed to handler, value dropped"
  (let ([ch (chan 8
              (mapping (lambda (x)
                         (if (= x 0) (error 'bad "zero") x)))
              ;; Handler returns #f ⇒ swallow the error; nothing put.
              (lambda (exn) #f))])
    (chan-put! ch 1)
    (chan-put! ch 0)  ;; raises inside xform — ex-handler returns #f
    (chan-put! ch 2)
    (chan-close! ch)
    (chan->list ch))
  '(1 2))

(test "chan/ex-handler — handler returns substitute value"
  (let ([ch (chan 8
              (mapping (lambda (x)
                         (if (= x 0) (error 'bad "zero") x)))
              (lambda (exn) 'oops))])
    (chan-put! ch 1)
    (chan-put! ch 0)  ;; raises → handler returns 'oops → enqueued raw
    (chan-put! ch 2)
    (chan-close! ch)
    (chan->list ch))
  '(1 oops 2))

;;; ======== Callback-style put! / take! (Phase C.1) ========

(test "put! with callback — successful put reports #t"
  (let ([ch (chan 4)]
        [result (make-channel 1)])
    (put! ch 'hello (lambda (ok?) (chan-put! result ok?) (chan-close! result)))
    (let ([ok? (chan-get! result)])
      (list ok? (chan-get! ch))))
  '(#t hello))

(test "put! with callback — closed channel reports #f"
  (let ([ch (chan 1)]
        [result (make-channel 1)])
    (chan-close! ch)
    (put! ch 'bye (lambda (ok?) (chan-put! result ok?) (chan-close! result)))
    (chan-get! result))
  #f)

(test "put! fire-and-forget (2-arg form)"
  (let ([ch (chan 4)])
    (put! ch 'fire)
    (sleep (millis 20))  ;; give helper thread a chance
    (chan-get! ch))
  'fire)

(test "take! delivers arriving value"
  (let ([ch (chan 1)]
        [seen (make-channel 1)])
    (take! ch (lambda (v) (chan-put! seen v) (chan-close! seen)))
    (chan-put! ch 42)
    (chan-get! seen))
  42)

(test "take! delivers eof on close"
  (let ([ch (chan 1)]
        [seen (make-channel 1)])
    (take! ch (lambda (v)
                (chan-put! seen (if (eof-object? v) 'eof v))
                (chan-close! seen)))
    (chan-close! ch)
    (chan-get! seen))
  'eof)

(test "take! runs after put! — full async round-trip"
  (let ([ch  (chan 4)]
        [out (make-channel 1)])
    (take! ch (lambda (v) (chan-put! out (+ v 100)) (chan-close! out)))
    (put! ch 7)
    (chan-get! out))
  107)

(test "put! callback runs for buffered channel without blocking caller"
  ;; The caller should NOT block even if the channel buffer fills up
  ;; — put! delegates the wait to a helper thread. Here we fill a
  ;; size-1 channel with one item; the second put! must return
  ;; immediately to the caller while waiting in a helper thread, and
  ;; fire its callback only after a reader drains the channel.
  (let ([ch     (chan 1)]
        [tag-ch (make-channel 4)])
    (chan-put! ch 'first)
    (put! ch 'second
      (lambda (ok?) (chan-put! tag-ch (if ok? 'second-delivered 'failed))))
    (chan-put! tag-ch 'after-put-returned)  ;; should land BEFORE 'second-delivered
    (let ([a (chan-get! tag-ch)])           ;; drain tag before reading ch
      (chan-get! ch)                         ;; unblock helper: makes room
      (let ([b (chan-get! tag-ch)])
        (list a b))))
  '(after-put-returned second-delivered))

;;; ======== async-reduce + onto-chan! / onto-chan!! (Phase C.2) ========

(test "async-reduce sum"
  (let* ([input (to-chan '(1 2 3 4 5))]
         [p     (async-reduce + 0 input)])
    (<!! p))
  15)

(test "async-reduce conj into list"
  (let* ([input (to-chan '(a b c d))]
         [p     (async-reduce (lambda (acc v) (cons v acc)) '() input)])
    (<!! p))
  '(d c b a))

(test "async-reduce on empty channel returns init"
  (let* ([ch  (make-channel)]
         [p   (async-reduce + 100 ch)])
    (chan-close! ch)
    (<!! p))
  100)

(test "async-reduce second get returns eof (channel drains then closes)"
  ;; Matches Clojure's async/reduce which uses (chan 1) internally —
  ;; the first taker gets the value, the channel then closes, and
  ;; subsequent takers see (eof-object). Users who need caching
  ;; semantics should wrap the result channel in a mult or promise.
  (let* ([input (to-chan '(10 20 30))]
         [p     (async-reduce + 0 input)])
    (let ([a (<!! p)] [b (<!! p)])
      (list a (eof-object? b))))
  '(60 #t))

(test "onto-chan! (async) feeds and closes"
  (let ([ch (make-channel 16)])
    (onto-chan! ch '(1 2 3))
    (chan->list ch))
  '(1 2 3))

(test "onto-chan! with close?=#f leaves channel open"
  (let ([ch (make-channel 16)])
    (onto-chan! ch '(a b c) #f)
    (sleep (millis 20))          ;; let feeder finish
    (list (chan-get! ch) (chan-get! ch) (chan-get! ch)
          (chan-closed? ch)))
  '(a b c #f))

(test "onto-chan!! (blocking) returns only after everything landed"
  ;; With a big enough buffer the blocking variant returns
  ;; synchronously; we then drain.
  (let ([ch (make-channel 16)])
    (onto-chan!! ch '(x y z))
    (chan->list ch))
  '(x y z))

(test "onto-chan!! followed by async-reduce is deterministic"
  (let ([ch (make-channel 64)])
    (onto-chan!! ch '(1 2 3 4 5 6 7 8 9 10))
    (<!! (async-reduce + 0 ch)))
  55)

;;; Summary

(printf "~%CSP: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
