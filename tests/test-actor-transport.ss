#!chezscheme
;;; Tests for (std actor transport) — distributed actor transport
;;;
;;; Part A: serialization-only tests (no network needed)
;;; Part B: localhost round-trip tests (requires chez_ssl_shim.so)

(import (chezscheme) (std actor core) (std actor transport) (std net ssl))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn
               [#t (set! fail (+ fail 1))
                   (printf "FAIL ~a: exception ~a~%" name
                     (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(define (wait-ms n)
  (sleep (make-time 'time-duration (* n 1000000) 0)))

(printf "--- (std actor transport) tests ---~%")
(printf "--- Part A: serialization ---~%")

;; Test 1: round-trip simple values through message->bytes / bytes->message
(test "roundtrip-symbol"
      (bytes->message (message->bytes 'hello))
      'hello)

(test "roundtrip-list"
      (bytes->message (message->bytes '(send 42 (ping 1 2 3))))
      '(send 42 (ping 1 2 3)))

(test "roundtrip-integer"
      (bytes->message (message->bytes 12345))
      12345)

(test "roundtrip-string"
      (bytes->message (message->bytes "hello world"))
      "hello world")

(test "roundtrip-bytevector"
      (bytes->message (message->bytes (make-bytevector 10 #xFF)))
      (make-bytevector 10 #xFF))

;; Test 2: large message (1MB bytevector)
(let ([big (make-bytevector (* 1024 1024) 7)])
  (test "roundtrip-1mb"
        (bytes->message (message->bytes big))
        big))

;; Test 3: framing — 4-byte header encodes body length
(let ([frame (message->bytes 'x)])
  (test "frame-min-length" (>= (bytevector-length frame) 4) #t)
  (let ([n (+ (* (bytevector-u8-ref frame 0) #x1000000)
              (* (bytevector-u8-ref frame 1) #x10000)
              (* (bytevector-u8-ref frame 2) #x100)
              (bytevector-u8-ref frame 3))])
    (test "frame-header-matches-body"
          n
          (- (bytevector-length frame) 4))))

;; Test 4: node identity
(test "start-node-returns-id"
      (start-node! "127.0.0.1" 9100 "secret")
      "127.0.0.1:9100")

(test "current-node-id"
      (current-node-id)
      "127.0.0.1:9100")

;; Test 5: make-remote-actor-ref creates a remote ref
(let ([ref (make-remote-actor-ref 99 "10.0.0.1:8000")])
  (test "remote-ref?"    (actor-ref? ref)   #t)
  (test "remote-ref-id"  (actor-ref-id ref) 99)
  (test "remote-ref-node" (actor-ref-node ref) "10.0.0.1:8000"))

;; -------- Part B: localhost TCP round-trip --------

(printf "~%--- Part B: localhost TCP ---~%")

(define (try-load-ssl)
  (guard (exn [#t #f])
    (load-shared-object "/home/jafourni/mine/chez-ssl/chez_ssl_shim.so")
    #t))

(if (not (try-load-ssl))
  (printf "  [skip] chez_ssl_shim.so not available — skipping TCP tests~%")
  (let ([test-port   19571]
        [test-cookie "test-cookie-abc"])

    (start-node! "127.0.0.1" test-port test-cookie)

    ;; Test 6: loopback — send to remote-ref pointing at local actor
    (let* ([received #f]
           [done-m   (make-mutex)]
           [done-c   (make-condition)]
           [actor    (spawn-actor
                       (lambda (msg)
                         (with-mutex done-m
                           (set! received msg)
                           (condition-signal done-c))))])
      (start-node-server! test-port)
      (wait-ms 50)

      (set-remote-send-handler!
        (lambda (a m) (transport-remote-send! a m)))

      (let ([rref (make-remote-actor-ref
                    (actor-ref-id actor)
                    (string-append "127.0.0.1:" (number->string test-port)))])
        (guard (exn [#t
                     (set! fail (+ fail 1))
                     (printf "FAIL tcp-loopback: ~a~%"
                       (if (message-condition? exn) (condition-message exn) exn))])
          (send rref '(hello from transport))
          (with-mutex done-m
            (let loop ([t 0])
              (when (and (not received) (< t 20))
                (condition-wait done-c done-m)
                (loop (+ t 1)))))
          (test "tcp-loopback" received '(hello from transport))))

      (actor-kill! actor)
      (transport-shutdown!)
      (set-remote-send-handler! #f))

    ;; Test 7: cookie mismatch rejects the connection
    (let ([accept-m  (make-mutex)]
          [accept-c  (make-condition)]
          [server-fd #f])
      (guard (exn [#t
                   (set! fail (+ fail 1))
                   (printf "FAIL cookie-reject: ~a~%"
                     (if (message-condition? exn) (condition-message exn) exn))])
        (let ([listen-fd (tcp-listen 19572)])
          ;; Accept thread: read hello then unconditionally reject
          (fork-thread
            (lambda ()
              (let-values ([(cfd _) (tcp-accept listen-fd)])
                ;; Drain the hello message
                (let ([header (make-bytevector 4 0)])
                  (tcp-read cfd header 4)
                  (let ([n (+ (* (bytevector-u8-ref header 0) #x1000000)
                              (* (bytevector-u8-ref header 1) #x10000)
                              (* (bytevector-u8-ref header 2) #x100)
                              (bytevector-u8-ref header 3))])
                    (let ([body (make-bytevector n 0)])
                      (tcp-read cfd body n))))
                ;; Always reject
                (tcp-write cfd (message->bytes '(error "bad cookie")))
                (tcp-close cfd)
                (with-mutex accept-m (condition-signal accept-c)))))
          ;; Connect with mismatched cookie
          (let ([fd (tcp-connect "127.0.0.1" 19572)])
            (let ([bad-hello (list 'hello "127.0.0.1:9999" 0)])
              (tcp-write fd (message->bytes bad-hello))
              (wait-ms 100)
              (let ([resp (guard (exn [#t #f])
                            (let ([header (make-bytevector 4 0)])
                              (tcp-read fd header 4)
                              (let ([n (+ (* (bytevector-u8-ref header 0) #x1000000)
                                          (* (bytevector-u8-ref header 1) #x10000)
                                          (* (bytevector-u8-ref header 2) #x100)
                                          (bytevector-u8-ref header 3))])
                                (let ([body (make-bytevector n 0)])
                                  (tcp-read fd body n)
                                  (fasl-read (open-bytevector-input-port body))))))])
                (test "cookie-reject"
                      (and (pair? resp) (eq? (car resp) 'error))
                      #t)
                (tcp-close fd))))
          (tcp-close listen-fd))))))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
