#!chezscheme
;;; Tests for (std stm) — Software Transactional Memory

(import (chezscheme) (std stm))

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

(printf "--- (std stm) tests ---~%")

;; Basic TVar operations
(printf "~%-- TVar basics --~%")

(test "make-tvar + tvar-ref"
  (let ([tv (make-tvar 42)])
    (tvar-ref tv))
  42)

(test "tvar?"
  (tvar? (make-tvar 0))
  #t)

(test "tvar? on non-tvar"
  (tvar? 42)
  #f)

;; atomically: read and write
(printf "~%-- atomically: basic read/write --~%")

(test "tvar-read outside transaction (falls back to direct read)"
  (let ([tv (make-tvar 99)])
    (tvar-read tv))
  99)

(test "atomically: read"
  (let ([tv (make-tvar 10)])
    (atomically (tvar-read tv)))
  10)

(test "atomically: write then read"
  (let ([tv (make-tvar 1)])
    (atomically
      (tvar-write! tv 42)
      (tvar-read tv)))
  42)

(test "atomically: write persists after transaction"
  (let ([tv (make-tvar 0)])
    (atomically (tvar-write! tv 100))
    (tvar-ref tv))
  100)

(test "atomically: multiple TVars"
  (let ([a (make-tvar 1)]
        [b (make-tvar 2)])
    (atomically
      (tvar-write! a 10)
      (tvar-write! b 20))
    (list (tvar-ref a) (tvar-ref b)))
  '(10 20))

(test "atomically: read then write"
  (let ([tv (make-tvar 5)])
    (atomically
      (let ([v (tvar-read tv)])
        (tvar-write! tv (* v 2))))
    (tvar-ref tv))
  10)

;; Nested transactions flatten into parent
(printf "~%-- nested atomically --~%")

(test "nested atomically: flattens into parent"
  (let ([tv (make-tvar 0)])
    (atomically
      (atomically (tvar-write! tv 1))
      (atomically (tvar-write! tv (+ (tvar-read tv) 1))))
    (tvar-ref tv))
  2)

;; Composable transfers
(printf "~%-- composable transfers --~%")

(define (transfer! from to amount)
  (atomically
    (let ([f (tvar-read from)]
          [t (tvar-read to)])
      (when (< f amount)
        (error 'transfer! "insufficient funds" f amount))
      (tvar-write! from (- f amount))
      (tvar-write! to   (+ t amount)))))

(test "transfer: basic"
  (let ([a (make-tvar 1000)]
        [b (make-tvar 500)])
    (transfer! a b 300)
    (list (tvar-ref a) (tvar-ref b)))
  '(700 800))

(test "transfer: composed (two in one atomically)"
  (let ([a (make-tvar 1000)]
        [b (make-tvar 500)]
        [c (make-tvar 200)])
    (atomically
      (transfer! a b 100)
      (transfer! b c 50))
    (list (tvar-ref a) (tvar-ref b) (tvar-ref c)))
  '(900 550 250))

;; Concurrent correctness: two threads doing increments
(printf "~%-- concurrent correctness --~%")

(test "concurrent increments"
  (let ([counter (make-tvar 0)]
        [n 100])
    (define (increment!)
      (atomically
        (let ([v (tvar-read counter)])
          (tvar-write! counter (+ v 1)))))
    ;; Run n increments in two threads
    (let ([t1 (fork-thread
                (lambda ()
                  (let loop ([i 0])
                    (when (< i (quotient n 2))
                      (increment!)
                      (loop (+ i 1))))))]
          [t2 (fork-thread
                (lambda ()
                  (let loop ([i 0])
                    (when (< i (quotient n 2))
                      (increment!)
                      (loop (+ i 1))))))])
      ;; Wait for threads to finish
      (let ([m (make-mutex)]
            [c (make-condition)]
            [done 0])
        (define (thread-done!)
          (with-mutex m
            (set! done (+ done 1))
            (condition-broadcast c)))
        ;; Can't join threads in Chez directly; use a simpler approach:
        ;; Just sleep and check
        (sleep (make-time 'time-duration 200000000 0))
        (tvar-ref counter))))
  100)

;; or-else
(printf "~%-- or-else --~%")

(test "or-else: first succeeds"
  (atomically
    (or-else
      42
      99))
  42)

(test "or-else: first retries, second runs"
  (let ([flag (make-tvar #t)])
    (atomically
      (or-else
        (if (tvar-read flag) 'first (retry))
        'second)))
  'first)

(test "or-else: first retries (flag=#f), second runs"
  (let ([flag (make-tvar #f)])
    (atomically
      (or-else
        (if (tvar-read flag) 'first (retry))
        'second)))
  'second)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
