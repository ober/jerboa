;;; Test fiber-aware I/O: echo server with concurrent fiber clients.
;;; Tests Phase 1 of green-wins: epoll integration with fiber scheduler.

(import (chezscheme))
(import (std fiber))
(import (std net io))

(define test-count 0)
(define pass-count 0)

(define-syntax test
  (syntax-rules ()
    [(_ name body ...)
     (begin
       (set! test-count (+ test-count 1))
       (guard (exn [#t
         (display "FAIL: ") (display name) (newline)
         (display "  Error: ")
         (display (if (message-condition? exn) (condition-message exn) exn))
         (newline)])
         body ...
         (set! pass-count (+ pass-count 1))
         (display "PASS: ") (display name) (newline)))]))

(define-syntax assert-equal
  (syntax-rules ()
    [(_ got expected msg)
     (unless (equal? got expected)
       (error 'assert msg (list 'got: got 'expected: expected)))]))

(define-syntax assert-true
  (syntax-rules ()
    [(_ val msg)
     (unless val (error 'assert msg))]))

;; =========================================================================
;; Test 1: Poller lifecycle
;; =========================================================================

(test "poller creates and stops cleanly"
  (let ([rt (make-fiber-runtime 2)])
    (let ([p (make-io-poller rt)])
      (assert-true (io-poller? p) "is poller")
      (io-poller-start! p)
      (sleep (make-time 'time-duration 50000000 0))  ;; 50ms
      (io-poller-stop! p))))

;; =========================================================================
;; Test 2: Fiber-aware TCP listen + accept + read/write
;; =========================================================================

(test "echo server with fiber I/O"
  (let ([rt (make-fiber-runtime 4)])
    (with-io-poller rt poller
      ;; Start server fiber
      (let-values ([(listen-fd listen-port) (fiber-tcp-listen "127.0.0.1" 0)])
        (fiber-spawn rt
          (lambda ()
            ;; Accept one client
            (let ([client-fd (fiber-tcp-accept listen-fd poller)])
              ;; Echo: read then write back
              (let ([buf (make-bytevector 1024)])
                (let ([n (fiber-tcp-read client-fd buf 1024 poller)])
                  (when (> n 0)
                    (fiber-tcp-write client-fd buf n poller))))
              (fiber-tcp-close client-fd)))
          "echo-server")

        ;; Start client fiber
        (fiber-spawn rt
          (lambda ()
            ;; Small delay to let server fiber start
            (fiber-sleep 20)
            (let ([fd (fiber-tcp-connect "127.0.0.1" listen-port poller)])
              ;; Send message
              (let ([msg (string->bytevector "hello-fiber-io"
                           (make-transcoder (utf-8-codec)))])
                (fiber-tcp-write fd msg (bytevector-length msg) poller)
                ;; Read echo
                (let ([buf (make-bytevector 1024)])
                  (let ([n (fiber-tcp-read fd buf 1024 poller)])
                    (let ([reply (bytevector->string
                                  (let ([b (make-bytevector n)])
                                    (bytevector-copy! buf 0 b 0 n) b)
                                  (make-transcoder (utf-8-codec)))])
                      (assert-equal reply "hello-fiber-io"
                        "echo reply matches")))))))
          "echo-client")

        ;; Run the runtime (blocks until all fibers done)
        (fiber-runtime-run! rt)
        (fiber-tcp-close listen-fd)))))

;; =========================================================================
;; Test 3: Multiple concurrent connections
;; =========================================================================

(test "50 concurrent echo clients"
  (let ([rt (make-fiber-runtime 4)]
        [num-clients 50]
        [results (make-vector 50 #f)])
    (with-io-poller rt poller
      (let-values ([(listen-fd listen-port) (fiber-tcp-listen "127.0.0.1" 0)])
        ;; Server: accept and echo in a loop
        (fiber-spawn rt
          (lambda ()
            (let loop ([i 0])
              (when (< i num-clients)
                (let ([client-fd (fiber-tcp-accept listen-fd poller)])
                  (fiber-spawn*
                    (lambda ()
                      (let ([buf (make-bytevector 256)])
                        (let ([n (fiber-tcp-read client-fd buf 256 poller)])
                          (when (> n 0)
                            (fiber-tcp-write client-fd buf n poller))))
                      (fiber-tcp-close client-fd))
                    "echo-handler"))
                (loop (+ i 1)))))
          "accept-loop")

        ;; Spawn 50 client fibers
        (do ([i 0 (+ i 1)])
          ((= i num-clients))
          (let ([idx i])
            (fiber-spawn rt
              (lambda ()
                (fiber-sleep 10)
                (let ([fd (fiber-tcp-connect "127.0.0.1" listen-port poller)])
                  (let ([msg (string->bytevector
                               (string-append "msg-" (number->string idx))
                               (make-transcoder (utf-8-codec)))])
                    (fiber-tcp-write fd msg (bytevector-length msg) poller)
                    (let ([buf (make-bytevector 256)])
                      (let ([n (fiber-tcp-read fd buf 256 poller)])
                        (let ([reply (bytevector->string
                                       (let ([b (make-bytevector n)])
                                         (bytevector-copy! buf 0 b 0 n) b)
                                       (make-transcoder (utf-8-codec)))])
                          (vector-set! results idx
                            (string=? reply (string-append "msg-" (number->string idx))))))))
                  (fiber-tcp-close fd)))
              (string-append "client-" (number->string idx)))))

        (fiber-runtime-run! rt)
        (fiber-tcp-close listen-fd)

        ;; Check all clients got correct echo
        (let ([ok-count (do ([i 0 (+ i 1)] [c 0 (+ c (if (vector-ref results i) 1 0))])
                          ((= i num-clients) c))])
          (assert-equal ok-count num-clients "all clients echoed correctly"))))))

;; =========================================================================
;; Summary
;; =========================================================================
(newline)
(display "=========================================") (newline)
(display "Results: ") (display pass-count) (display "/")
(display test-count) (display " passed") (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
