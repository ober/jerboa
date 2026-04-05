#!chezscheme
;;; :std/net/repl -- Network REPL server for remote debugging
;;;
;;; Starts a TCP server that accepts connections and runs a
;;; read-eval-print loop for each client. Each client gets its
;;; own thread. Exceptions are caught and reported to the client
;;; without crashing the server.

(library (std net repl)
  (export
    start-repl-server
    stop-repl-server
    repl-server?
    repl-server-port)

  (import (chezscheme))

  ;; ========== FFI ==========

  (define _libc (or (guard (e [#t #f]) (load-shared-object "libc.so.7"))
                    (guard (e [#t #f]) (load-shared-object "libc.so.6"))
                    (guard (e [#t #f]) (load-shared-object "libc.so"))))

  (define c-socket    (foreign-procedure "socket" (int int int) int))
  (define c-bind      (foreign-procedure "bind" (int void* int) int))
  (define c-listen    (foreign-procedure "listen" (int int) int))
  (define c-accept    (foreign-procedure "accept" (int void* void*) int))
  (define c-close     (foreign-procedure "close" (int) int))
  (define c-setsockopt (foreign-procedure "setsockopt" (int int int void* int) int))
  (define c-htons     (foreign-procedure "htons" (unsigned-short) unsigned-short))
  (define c-getsockname (foreign-procedure "getsockname" (int void* void*) int))
  (define c-fcntl     (foreign-procedure "fcntl" (int int int) int))
  (define c-errno-location
    (let ((mt (symbol->string (machine-type))))

      (if (or (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb))

              (and (>= (string-length mt) 3)

                   (string=? (substring mt (- (string-length mt) 3) (string-length mt)) "osx")))

        (foreign-procedure "__error" () void*)

        (foreign-procedure "__errno_location" () void*))))
  (define (get-errno) (foreign-ref 'int (c-errno-location) 0))

  ;; Constants (values differ between Linux and FreeBSD)
  (define *freebsd?* (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb)))
  (define AF_INET 2)
  (define SOCK_STREAM 1)
  (define SOL_SOCKET    (if *freebsd?* #xffff 1))
  (define SO_REUSEADDR  (if *freebsd?* 4 2))
  (define SOCKADDR_IN_SIZE 16)
  (define F_GETFL 3)
  (define F_SETFL 4)
  (define O_NONBLOCK (if *freebsd?* #x4 #x800))
  (define EINTR 4)
  (define EAGAIN (if *freebsd?* 35 11))
  (define *retry-delay* (make-time 'time-duration 10000000 0))

  ;; ========== Helpers ==========

  (define (set-nonblocking! fd)
    (let ([flags (c-fcntl fd F_GETFL 0)])
      (c-fcntl fd F_SETFL (bitwise-ior flags O_NONBLOCK))))

  (define (make-sockaddr-in port)
    ;; Bind to INADDR_ANY (0.0.0.0)
    (let ([buf (foreign-alloc SOCKADDR_IN_SIZE)])
      (let lp ([i 0])
        (when (< i SOCKADDR_IN_SIZE)
          (foreign-set! 'unsigned-8 buf i 0)
          (lp (+ i 1))))
      (if *freebsd?*
        (begin
          (foreign-set! 'unsigned-8 buf 0 SOCKADDR_IN_SIZE)  ;; sin_len
          (foreign-set! 'unsigned-8 buf 1 AF_INET))          ;; sin_family (uint8)
        (foreign-set! 'unsigned-short buf 0 AF_INET))        ;; sin_family (uint16)
      (foreign-set! 'unsigned-short buf 2 (c-htons port))
      ;; sin_addr stays 0 = INADDR_ANY
      buf))

  (define (sockaddr-in-port buf)
    (let ([hi (foreign-ref 'unsigned-8 buf 2)]
          [lo (foreign-ref 'unsigned-8 buf 3)])
      (+ (* hi 256) lo)))

  ;; ========== Server Record ==========

  (define-record-type repl-server
    (fields
      (immutable fd)
      (immutable port-num)
      (mutable running?))
    (sealed #t))

  ;; ========== Server Lifecycle ==========

  (define (start-repl-server port)
    (let ([fd (c-socket AF_INET SOCK_STREAM 0)])
      (when (< fd 0)
        (error 'start-repl-server "socket() failed"))
      ;; SO_REUSEADDR
      (let ([one (foreign-alloc 4)])
        (foreign-set! 'int one 0 1)
        (c-setsockopt fd SOL_SOCKET SO_REUSEADDR one 4)
        (foreign-free one))
      ;; Bind
      (let ([addr (make-sockaddr-in port)])
        (let ([rc (c-bind fd addr SOCKADDR_IN_SIZE)])
          (foreign-free addr)
          (when (< rc 0)
            (c-close fd)
            (error 'start-repl-server "bind() failed" port))))
      ;; Listen
      (when (< (c-listen fd 16) 0)
        (c-close fd)
        (error 'start-repl-server "listen() failed"))
      ;; Non-blocking for GC-safe accept
      (set-nonblocking! fd)
      ;; Get actual port
      (let* ([buf (foreign-alloc SOCKADDR_IN_SIZE)]
             [len (foreign-alloc 4)])
        (foreign-set! 'int len 0 SOCKADDR_IN_SIZE)
        (c-getsockname fd buf len)
        (let ([actual-port (sockaddr-in-port buf)])
          (foreign-free buf)
          (foreign-free len)
          (let ([srv (make-repl-server fd actual-port #t)])
            ;; Start accept thread
            (fork-thread (lambda () (accept-loop srv)))
            srv)))))

  (define (stop-repl-server srv)
    (repl-server-running?-set! srv #f)
    (c-close (repl-server-fd srv)))

  (define (repl-server-port srv)
    (repl-server-port-num srv))

  ;; ========== Accept Loop ==========

  (define (accept-loop srv)
    (let loop ()
      (when (repl-server-running? srv)
        (let ([client-fd (c-accept (repl-server-fd srv) 0 0)])
          (cond
            [(>= client-fd 0)
             ;; Spawn a client handler thread
             (fork-thread (lambda () (client-repl client-fd)))
             (loop)]
            [(let ([e (get-errno)]) (or (= e EINTR) (= e EAGAIN)))
             (sleep *retry-delay*)
             (loop)]
            [else
             ;; Accept failed — if still running, retry
             (when (repl-server-running? srv)
               (sleep *retry-delay*)
               (loop))])))))

  ;; ========== Client REPL ==========

  (define (client-repl fd)
    (let ([ip (open-fd-input-port fd (buffer-mode block)
               (make-transcoder (utf-8-codec) (eol-style none)
                 (error-handling-mode replace)))]
          [op (open-fd-output-port fd (buffer-mode line)
               (make-transcoder (utf-8-codec) (eol-style lf)
                 (error-handling-mode replace)))])
      (dynamic-wind
        void
        (lambda ()
          (let loop ()
            (guard (e [#t
                       ;; I/O error on the connection itself — stop
                       (void)])
              (display "jerboa> " op)
              (flush-output-port op)
              (let ([expr (guard (e [#t
                                     (display (format #f "read error: ~a\n"
                                       (if (message-condition? e)
                                         (condition-message e)
                                         e))
                                       op)
                                     (flush-output-port op)
                                     'continue])
                            (read ip))])
                (cond
                  [(eof-object? expr) (void)]  ;; client disconnected
                  [(eq? expr 'continue) (loop)]
                  [else
                   (guard (e [#t
                              (display (format #f "error: ~a\n"
                                (if (message-condition? e)
                                  (condition-message e)
                                  e))
                                op)
                              (flush-output-port op)])
                     (call-with-values
                       (lambda () (eval expr (interaction-environment)))
                       (lambda results
                         (for-each
                           (lambda (v)
                             (unless (eq? v (void))
                               (write v op)
                               (newline op)))
                           results)
                         (flush-output-port op))))
                   (loop)])))))
        (lambda ()
          (guard (e [#t (void)])
            (close-port ip))
          (guard (e [#t (void)])
            (close-port op))))))

  ) ;; end library
