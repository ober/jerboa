#!chezscheme
;;; tests/test-grpc.ss -- Tests for (std net grpc)

(import (chezscheme) (std net grpc))

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

(printf "--- Phase 2e: gRPC ---~%~%")

;; ---- 1. grpc-status ----
(let ([ok  (grpc-status #t 0 "ok")]
      [err (grpc-status #f 1 "not found")])
  (test "grpc-ok?"    (grpc-ok?    ok)  #t)
  (test "grpc-error?" (grpc-error? ok)  #f)
  (test "grpc-error-ok?"    (grpc-ok?    err) #f)
  (test "grpc-error-error?" (grpc-error? err) #t))

;; ---- 2. define-service and define-rpc ----
(define-service calc-service)

(define-rpc calc-service add
  (lambda (a b) (+ a b)))

(define-rpc calc-service multiply
  (lambda (a b) (* a b)))

(define-rpc calc-service greet
  (lambda (name) (string-append "Hello, " name "!")))

;; Service is a hashtable
(test "service-has-add"      (procedure? (hashtable-ref calc-service 'add      #f)) #t)
(test "service-has-multiply" (procedure? (hashtable-ref calc-service 'multiply #f)) #t)
(test "service-has-greet"    (procedure? (hashtable-ref calc-service 'greet    #f)) #t)

;; ---- 3. Start server and make calls ----
(define test-port 19900)

(let ([server (make-grpc-server test-port calc-service)])
  (test "server?" (grpc-server-port server) test-port)

  ;; Start server
  (grpc-server-start! server)

  ;; Give server time to bind
  (let loop ([i 0])
    (when (< i 10)
      (sleep (make-time 'time-duration 100000000 0))  ; 0.1s
      (loop (+ i 1))))

  ;; Make calls
  (let ([client (make-grpc-client "127.0.0.1" test-port)])
    (test "grpc-call-add"      (grpc-call client 'add 3 4)        7)
    (test "grpc-call-multiply" (grpc-call client 'multiply 6 7)   42)
    (test "grpc-call-greet"    (grpc-call client 'greet "World")   "Hello, World!")
    ;; Multiple calls on same client
    (test "grpc-call-add2"     (grpc-call client 'add 10 20)      30)
    ;; Unknown method returns error
    (guard (exn [#t (test "grpc-unknown-method-error"
                          (message-condition? exn) #t)])
      (grpc-call client 'unknown-method)
      (test "grpc-unknown-method-should-err" #f #t)))

  ;; Stop server
  (grpc-server-stop! server)
  (test "server-stopped" (grpc-server-port server) test-port))

;; ---- 4. with-grpc-client macro ----
(define test-port2 19901)

(define-service echo-service)
(define-rpc echo-service echo (lambda (x) x))
(define-rpc echo-service double (lambda (n) (* n 2)))

(let ([server2 (make-grpc-server test-port2 echo-service)])
  (grpc-server-start! server2)
  (let loop ([i 0])
    (when (< i 10)
      (sleep (make-time 'time-duration 100000000 0))
      (loop (+ i 1))))

  (with-grpc-client ([client "127.0.0.1" test-port2])
    (test "with-grpc-echo"   (grpc-call client 'echo 'hello) 'hello)
    (test "with-grpc-double" (grpc-call client 'double 21) 42))

  (grpc-server-stop! server2))

;; ---- 5. grpc-call-async ----
(define test-port3 19902)
(define-service async-service)
(define-rpc async-service square (lambda (n) (* n n)))

(let ([server3 (make-grpc-server test-port3 async-service)])
  (grpc-server-start! server3)
  (let loop ([i 0])
    (when (< i 10)
      (sleep (make-time 'time-duration 100000000 0))
      (loop (+ i 1))))

  (let* ([result-box (list #f)]
         [client (make-grpc-client "127.0.0.1" test-port3)]
         [t (grpc-call-async client 'square '(7) (lambda (r e)
                                                   (set-car! result-box (or r e))))])
    ;; Wait for async result
    (let loop ([i 0])
      (when (and (< i 20) (not (car result-box)))
        (sleep (make-time 'time-duration 50000000 0))
        (loop (+ i 1))))
    (test "grpc-async-result" (car result-box) 49))

  (grpc-server-stop! server3))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
