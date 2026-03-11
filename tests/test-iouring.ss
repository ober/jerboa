#!chezscheme
;;; Tests for (std os iouring) — io_uring async I/O

(import (chezscheme) (std os iouring) (std async))

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

(printf "--- (std os iouring) tests ---~%")

(if (not (iouring-available?))
  (begin
    (printf "  SKIP: liburing-ffi.so.2 not available~%"))
  (begin

    ;; Test 1: availability check
    (test "iouring-available?" (iouring-available?) #t)

    ;; Test 2: create a ring with default depth
    (test "make-iouring/default"
      (let ([ring (make-iouring)])
        (let ([ok (iouring? ring)])
          (iouring-close! ring)
          ok))
      #t)

    ;; Test 3: create a ring with explicit depth
    (test "make-iouring/depth"
      (let ([ring (make-iouring 8)])
        (let ([ok (iouring? ring)])
          (iouring-close! ring)
          ok))
      #t)

    ;; Test 4: submit with no ops returns 0
    (test "iouring-submit!/empty"
      (let ([ring (make-iouring 16)])
        (let ([n (iouring-submit! ring)])
          (iouring-close! ring)
          n))
      0)

    ;; Test 5: multiple rings can coexist
    (test "iouring/multiple-rings"
      (let ([ring1 (make-iouring 8)]
            [ring2 (make-iouring 8)])
        (let ([ok (and (iouring? ring1) (iouring? ring2))])
          (iouring-close! ring1)
          (iouring-close! ring2)
          ok))
      #t)

    ;; Test 6: async NOP op via io_uring
    (test "iouring/nop-completion"
      (run-async
        (lambda ()
          (let ([ring (make-iouring 16)])
            (let ([p (iouring-nop! ring)])
              (iouring-submit! ring)
              (run-iouring-loop ring)
              (let ([result (Async await p)])
                (iouring-close! ring)
                ;; NOP returns 0 on success
                result)))))
      0)))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
