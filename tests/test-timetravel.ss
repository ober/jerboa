#!chezscheme
;;; Tests for (std debug timetravel) — Time-Travel Debugger

(import (chezscheme) (std debug timetravel))

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

(printf "--- (std debug timetravel) tests ---~%")

;;; ---- make-recorder / recorder? ----

(test "make-recorder returns recorder"
  (recorder? (make-recorder))
  #t)

(test "recorder? false for non-recorder"
  (recorder? 42)
  #f)

;;; ---- recorder-start! / recorder-stop! / recorder-events / recorder-event-count ----

(test "fresh recorder has 0 events"
  (recorder-event-count (make-recorder))
  0)

(test "events empty before start"
  (let ([r (make-recorder)])
    (record-event! r 'test 'data)
    (recorder-event-count r))
  0)

(test "record-event! works when running"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (record-event! r 'test 'data)
    (recorder-stop! r)
    (recorder-event-count r))
  1)

(test "events returns list of events"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (record-event! r 'a 1)
    (record-event! r 'b 2)
    (recorder-stop! r)
    (length (recorder-events r)))
  2)

;;; ---- event structure ----

(test "event-tag"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (record-event! r 'my-tag 'my-data)
    (recorder-stop! r)
    (event-tag (car (recorder-events r))))
  'my-tag)

(test "event-data"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (record-event! r 'my-tag 'my-data)
    (recorder-stop! r)
    (event-data (car (recorder-events r))))
  'my-data)

(test "event-step is 1 for first event"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (record-event! r 'first #f)
    (recorder-stop! r)
    (event-step (car (recorder-events r))))
  1)

(test "event-step increments monotonically"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (record-event! r 'a 1)
    (record-event! r 'b 2)
    (record-event! r 'c 3)
    (recorder-stop! r)
    (map event-step (recorder-events r)))
  '(1 2 3))

(test "event-timestamp is a non-negative integer"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (record-event! r 'ts #f)
    (recorder-stop! r)
    (>= (event-timestamp (car (recorder-events r))) 0))
  #t)

(test "event? predicate"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (record-event! r 'tag 'val)
    (recorder-stop! r)
    (event? (car (recorder-events r))))
  #t)

(test "make-event creates an event"
  (event? (make-event 'tag 'data 12345 1))
  #t)

;;; ---- recorder-reset! ----

(test "recorder-reset! clears events"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (record-event! r 'x 1)
    (recorder-stop! r)
    (recorder-reset! r)
    (recorder-event-count r))
  0)

;;; ---- record-call! / record-return! / record-state! ----

(test "record-call! stores call event"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (record-call! r 'my-fn '(1 2 3))
    (recorder-stop! r)
    (let ([ev (car (recorder-events r))])
      (list (event-tag ev) (event-data ev))))
  '(call (my-fn (1 2 3))))

(test "record-return! stores return event"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (record-return! r 'my-fn 42)
    (recorder-stop! r)
    (let ([ev (car (recorder-events r))])
      (list (event-tag ev) (event-data ev))))
  '(return (my-fn 42)))

(test "record-state! stores state event"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (record-state! r 'counter 99)
    (recorder-stop! r)
    (let ([ev (car (recorder-events r))])
      (list (event-tag ev) (event-data ev))))
  '(state (counter 99)))

;;; ---- replay-events ----

(test "replay-events calls handler for each event in order"
  (let ([r (make-recorder)]
        [log '()])
    (recorder-start! r)
    (record-event! r 'a 1)
    (record-event! r 'b 2)
    (record-event! r 'c 3)
    (recorder-stop! r)
    (replay-events (recorder-events r)
                   (lambda (ev) (set! log (append log (list (event-tag ev))))))
    log)
  '(a b c))

;;; ---- replay-to-step ----

(test "replay-to-step returns last state up to step n"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (record-state! r 'x 10)
    (record-state! r 'x 20)
    (record-state! r 'x 30)
    (recorder-stop! r)
    ;; step 2 = second state event
    (replay-to-step (recorder-events r) 2))
  20)

(test "replay-to-step with step beyond all events"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (record-state! r 'x 42)
    (recorder-stop! r)
    (replay-to-step (recorder-events r) 999))
  42)

;;; ---- with-recording macro ----

(test "with-recording starts and stops recorder"
  (let ([r (make-recorder)])
    (with-recording r
      (record-event! r 'inside 'yes))
    (recorder-event-count r))
  1)

(test "with-recording stops recorder after body"
  (let ([r (make-recorder)])
    (with-recording r
      (record-event! r 'a 1))
    ;; after, recorder is stopped so this is ignored
    (record-event! r 'b 2)
    (recorder-event-count r))
  1)

;;; ---- trace-fn ----

(test "trace-fn records call and return"
  (let* ([r (make-recorder)]
         [add (trace-fn r (lambda (x y) (+ x y)))])
    (recorder-start! r)
    (add 3 4)
    (recorder-stop! r)
    (map event-tag (recorder-events r)))
  '(call return))

(test "trace-fn returns correct value"
  (let* ([r (make-recorder)]
         [double (trace-fn r (lambda (x) (* x 2)))])
    (recorder-start! r)
    (let ([result (double 21)])
      (recorder-stop! r)
      result))
  42)

;;; ---- events-between ----

(test "events-between filters by timestamp range"
  (let ([e1 (make-event 'a 1 100 1)]
        [e2 (make-event 'b 2 200 2)]
        [e3 (make-event 'c 3 300 3)])
    (length (events-between (list e1 e2 e3) 150 250)))
  1)

;;; ---- events-by-tag ----

(test "events-by-tag filters by tag"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (record-event! r 'call '(f))
    (record-event! r 'return '(f 1))
    (record-event! r 'call '(g))
    (recorder-stop! r)
    (length (events-by-tag (recorder-events r) 'call)))
  2)

;;; ---- event-diff ----

(test "event-diff identical events"
  (let ([e (make-event 'tag 'data 100 1)])
    (car (event-diff e e)))
  'identical)

(test "event-diff same tag different data"
  (let ([e1 (make-event 'state 10 100 1)]
        [e2 (make-event 'state 20 200 2)])
    (car (event-diff e1 e2)))
  'same-tag)

(test "event-diff different tags"
  (let ([e1 (make-event 'call 'a 100 1)]
        [e2 (make-event 'return 'b 200 2)])
    (car (event-diff e1 e2)))
  'tag-changed)

;;; ---- record-snapshot! / find-snapshot / snapshots-for ----

(test "find-snapshot returns most recent value for label"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (record-snapshot! r 'db-state '(a b))
    (record-snapshot! r 'db-state '(a b c))
    (recorder-stop! r)
    (find-snapshot (recorder-events r) 'db-state))
  '(a b c))

(test "find-snapshot returns #f when label not found"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (recorder-stop! r)
    (find-snapshot (recorder-events r) 'missing))
  #f)

(test "snapshots-for returns all values in order"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (record-snapshot! r 'step 1)
    (record-snapshot! r 'step 2)
    (record-snapshot! r 'step 3)
    (recorder-stop! r)
    (snapshots-for (recorder-events r) 'step))
  '(1 2 3))

(test "snapshots-for returns empty for unknown label"
  (let ([r (make-recorder)])
    (recorder-start! r)
    (record-snapshot! r 'x 1)
    (recorder-stop! r)
    (snapshots-for (recorder-events r) 'y))
  '())

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
