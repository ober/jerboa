#!chezscheme
;;; std/net/grpc.sls -- gRPC-style RPC over TCP using S-expressions as wire format
;;;
;;; Protocol: client sends (method arg ...) as an S-expression followed by newline.
;;; Server responds with (ok result) or (error message).
;;; Length-prefix framing is not needed since `read` handles S-expression boundaries.

(library (std net grpc)
  (export
    define-service define-rpc
    make-grpc-server grpc-server-start! grpc-server-stop! grpc-server-port
    make-grpc-client grpc-call grpc-call-async
    grpc-status grpc-ok? grpc-error?
    with-grpc-client)

  (import (chezscheme))

  ;; ---- C socket FFI ----

  (define *libc-loaded* #f)

  (define (ensure-libc!)
    (unless *libc-loaded*
      (or (guard (e [#t #f]) (load-shared-object "libc.so.7"))
          (guard (e [#t #f]) (load-shared-object "libc.so.6"))
          (load-shared-object "libc.so"))
      (set! *libc-loaded* #t)))

  (define (get-socket-fn)   (foreign-procedure "socket"     (int int int) int))
  (define (get-bind-fn)     (foreign-procedure "bind"       (int u8* int) int))
  (define (get-listen-fn)   (foreign-procedure "listen"     (int int) int))
  (define (get-accept-fn)   (foreign-procedure "accept"     (int u8* u32*) int))
  (define (get-connect-fn)  (foreign-procedure "connect"    (int u8* int) int))
  (define (get-close-fn)    (foreign-procedure "close"      (int) int))
  (define (get-dup-fn)      (foreign-procedure "dup"        (int) int))
  (define (get-setsockopt-fn) (foreign-procedure "setsockopt" (int int int u8* int) int))

  (define AF_INET    2)
  (define SOCK_STREAM 1)
  (define SOL_SOCKET  1)
  (define SO_REUSEADDR 2)

  (define (make-sockaddr port h0 h1 h2 h3)
    (let ([bv (make-bytevector 16 0)])
      (bytevector-u8-set! bv 0 AF_INET)
      (bytevector-u8-set! bv 2 (quotient port 256))
      (bytevector-u8-set! bv 3 (remainder port 256))
      (bytevector-u8-set! bv 4 h0)
      (bytevector-u8-set! bv 5 h1)
      (bytevector-u8-set! bv 6 h2)
      (bytevector-u8-set! bv 7 h3)
      bv))

  ;; Create separate input/output ports from a socket fd
  (define (fd->ports fd)
    (let* ([c-dup  (get-dup-fn)]
           [fd2    (c-dup fd)]
           [inp    (open-fd-input-port  fd  (buffer-mode block) (native-transcoder))]
           [out    (open-fd-output-port fd2 (buffer-mode block) (native-transcoder))])
      (cons inp out)))

  ;; ---- gRPC Status ----

  (define-record-type grpc-status-rec
    (fields ok? code message data)
    (protocol
      (lambda (new)
        (lambda (ok? code message . data)
          (new ok? code message (if (null? data) #f (car data)))))))

  (define (grpc-status ok? code message . data)
    (apply make-grpc-status-rec ok? code message data))

  (define (grpc-ok?    s) (grpc-status-rec-ok? s))
  (define (grpc-error? s) (not (grpc-status-rec-ok? s)))

  ;; ---- Service registry ----

  ;; A "service" is a hashtable from symbol -> procedure
  ;; Global service registry
  (define *service-registry* (make-hashtable equal-hash equal?))

  (define-syntax define-service
    (syntax-rules ()
      [(_ service-name)
       (define service-name (make-hashtable equal-hash equal?))]))

  (define-syntax define-rpc
    (syntax-rules ()
      [(_ service-name method-name handler)
       (hashtable-set! service-name 'method-name handler)]))

  ;; ---- gRPC Server ----

  (define-record-type grpc-server-rec
    (fields (mutable socket-fd)
            (mutable running?)
            (mutable port-number)
            (mutable thread)
            services)
    (protocol
      (lambda (new)
        (lambda (port services)
          (new -1 #f port #f services)))))

  (define (grpc-server-port srv) (grpc-server-rec-port-number srv))

  (define (make-grpc-server port . services)
    (let ([svc (if (null? services)
                   (make-hashtable equal-hash equal?)
                   (car services))])
      (make-grpc-server-rec port svc)))

  (define (grpc-server-start! srv)
    (ensure-libc!)
    (let ([c-socket     (get-socket-fn)]
          [c-bind       (get-bind-fn)]
          [c-listen     (get-listen-fn)]
          [c-setsockopt (get-setsockopt-fn)]
          [c-accept     (get-accept-fn)]
          [c-close      (get-close-fn)]
          [port         (grpc-server-rec-port-number srv)]
          [services     (grpc-server-rec-services srv)])
      (let* ([fd  (c-socket AF_INET SOCK_STREAM 0)]
             [rab (make-bytevector 4 0)])
        (bytevector-u8-set! rab 0 1)
        (c-setsockopt fd SOL_SOCKET SO_REUSEADDR rab 4)
        (let ([rc (c-bind fd (make-sockaddr port 0 0 0 0) 16)])
          (when (< rc 0)
            (error "grpc-server-start!" "bind failed" port rc)))
        (c-listen fd 16)
        (grpc-server-rec-socket-fd-set! srv fd)
        (grpc-server-rec-running?-set! srv #t)
        ;; Accept loop in background thread
        (let ([t (fork-thread
                   (lambda ()
                     (let accept-loop ()
                       (when (grpc-server-rec-running? srv)
                         (guard (exn [#t (void)])
                           (let ([client-fd (c-accept fd #f #f)])
                             (when (>= client-fd 0)
                               ;; Handle client in separate thread
                               (fork-thread
                                 (lambda ()
                                   (handle-client client-fd services c-close))))))
                         (accept-loop)))))])
          (grpc-server-rec-thread-set! srv t)))))

  (define (handle-client client-fd services c-close)
    (let* ([ps  (fd->ports client-fd)]
           [inp (car ps)]
           [out (cdr ps)])
      (let loop ()
        (let ([msg (guard (exn [#t (eof-object)])
                     (read inp))])
          (unless (eof-object? msg)
            (let ([response (dispatch-rpc services msg)])
              (write response out)
              (flush-output-port out)
              (loop)))))
      (close-port inp)
      (close-port out)))

  (define (dispatch-rpc services msg)
    (if (and (pair? msg) (symbol? (car msg)))
        (let ([handler (hashtable-ref services (car msg) #f)])
          (if handler
              (guard (exn [#t
                           (list 'error
                                 (if (message-condition? exn)
                                     (condition-message exn)
                                     (format "~s" exn)))])
                (let ([result (apply handler (cdr msg))])
                  (list 'ok result)))
              (list 'error (format "unknown method: ~s" (car msg)))))
        (list 'error "malformed request")))

  (define (grpc-server-stop! srv)
    (grpc-server-rec-running?-set! srv #f)
    (let ([fd (grpc-server-rec-socket-fd srv)])
      (when (>= fd 0)
        (ensure-libc!)
        ((get-close-fn) fd)
        (grpc-server-rec-socket-fd-set! srv -1))))

  ;; ---- gRPC Client ----

  (define-record-type grpc-client-rec
    (fields host port (mutable inp) (mutable out) (mutable connected?))
    (protocol
      (lambda (new)
        (lambda (host port)
          (new host port #f #f #f)))))

  (define (make-grpc-client host port)
    (make-grpc-client-rec host port))

  (define (grpc-client-connect! client)
    (ensure-libc!)
    (let ([c-socket  (get-socket-fn)]
          [c-connect (get-connect-fn)]
          [host      (grpc-client-rec-host client)]
          [port      (grpc-client-rec-port client)])
      (let ([fd (c-socket AF_INET SOCK_STREAM 0)])
        ;; Parse host - only support "127.0.0.1" or "localhost" for simplicity
        (let ([addr (parse-host-addr host port)])
          (let ([rc (c-connect fd addr 16)])
            (when (< rc 0)
              (error "grpc-client-connect!" "connect failed" host port))
            (let* ([ps  (fd->ports fd)]
                   [inp (car ps)]
                   [out (cdr ps)])
              (grpc-client-rec-inp-set! client inp)
              (grpc-client-rec-out-set! client out)
              (grpc-client-rec-connected?-set! client #t)))))))

  (define (parse-host-addr host port)
    (cond
      [(or (string=? host "localhost") (string=? host "127.0.0.1"))
       (make-sockaddr port 127 0 0 1)]
      [else
       ;; Try to parse dotted-decimal
       (let ([parts (string-split host #\.)])
         (if (= (length parts) 4)
             (apply make-sockaddr port (map string->number parts))
             (make-sockaddr port 127 0 0 1)))]))

  (define (string-split s ch)
    (let loop ([i 0] [start 0] [acc '()])
      (cond
        [(= i (string-length s))
         (reverse (cons (substring s start i) acc))]
        [(char=? (string-ref s i) ch)
         (loop (+ i 1) (+ i 1) (cons (substring s start i) acc))]
        [else
         (loop (+ i 1) start acc)])))

  (define (grpc-call client method . args)
    (unless (grpc-client-rec-connected? client)
      (grpc-client-connect! client))
    (let ([inp (grpc-client-rec-inp client)]
          [out (grpc-client-rec-out client)])
      (write (cons method args) out)
      (flush-output-port out)
      (let ([resp (read inp)])
        (if (and (pair? resp) (eq? (car resp) 'ok))
            (cadr resp)
            (if (and (pair? resp) (eq? (car resp) 'error))
                (error "grpc-call" (cadr resp) method)
                (error "grpc-call" "malformed response" resp))))))

  (define (grpc-call-async client method args callback)
    (fork-thread
      (lambda ()
        (guard (exn [#t (callback #f exn)])
          (let ([result (apply grpc-call client method args)])
            (callback result #f))))))

  (define (grpc-client-close! client)
    (when (grpc-client-rec-connected? client)
      (close-port (grpc-client-rec-inp client))
      (close-port (grpc-client-rec-out client))
      (grpc-client-rec-connected?-set! client #f)))

  ;; ---- with-grpc-client ----

  (define-syntax with-grpc-client
    (syntax-rules ()
      [(_ ([client host port]) body ...)
       (let ([client (make-grpc-client host port)])
         (dynamic-wind
           (lambda () (grpc-client-connect! client))
           (lambda () body ...)
           (lambda () (grpc-client-close! client))))]))

  ) ;; end library
