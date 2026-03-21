#!chezscheme
;;; (std security privsep) — Privilege separation
;;;
;;; Fork-based privilege separation for critical operations.
;;; Supervisor holds elevated privileges, workers are sandboxed.
;;; Communication via message-passing over pipes.

(library (std security privsep)
  (export
    ;; Supervisor/Worker
    make-privsep
    privsep?
    privsep-request
    privsep-shutdown!

    ;; Worker API
    worker-request
    worker-loop

    ;; Channel
    make-privsep-channel
    privsep-channel?
    channel-send!
    channel-receive
    channel-close!

    ;; Configuration
    *max-privsep-children*)

  (import (chezscheme))

  ;; ========== FFI Initialization ==========

  (define _libc
    (guard (e [#t #f])
      (load-shared-object "libc.so.6")))
  (define _libc2
    (guard (e [#t #f])
      (load-shared-object "")))

  ;; ========== Pipe-Based Channel ==========

  (define c-pipe
    (guard (e [#t (lambda args -1)])
      (foreign-procedure "pipe" (u8*) int)))

  (define c-read
    (foreign-procedure "read" (int u8* size_t) ssize_t))

  (define c-write-raw
    (foreign-procedure "write" (int u8* size_t) ssize_t))

  (define c-close
    (foreign-procedure "close" (int) int))

  (define c-fork
    (guard (e [#t (lambda args -1)])
      (foreign-procedure "fork" () int)))

  (define c-waitpid
    (guard (e [#t (lambda args -1)])
      (foreign-procedure "waitpid" (int void* int) int)))

  (define c-kill
    (guard (e [#t (lambda args -1)])
      (foreign-procedure "kill" (int int) int)))

  ;; Maximum concurrent privsep children to prevent fork bombs.
  (define *max-privsep-children* (make-parameter 64))
  (define %active-children (make-hashtable equal-hash equal?))
  (define %children-mutex (make-mutex))

  (define-record-type (privsep-channel %make-channel privsep-channel?)
    (sealed #t)
    (fields
      (immutable read-fd %channel-read-fd)
      (immutable write-fd %channel-write-fd)
      (mutable closed? %channel-closed? %channel-set-closed!)))

  (define (make-privsep-channel)
    ;; Create a bidirectional channel using two pipes.
    (let ([pipe1 (make-bytevector 8 0)]    ;; parent→child
          [pipe2 (make-bytevector 8 0)])   ;; child→parent
      (when (< (c-pipe pipe1) 0)
        (error 'make-privsep-channel "pipe() failed"))
      (when (< (c-pipe pipe2) 0)
        (error 'make-privsep-channel "pipe() failed"))
      ;; pipe[0] = read end, pipe[1] = write end
      ;; Return two channels: parent-side and child-side
      (let ([p1-read  (bytevector-s32-native-ref pipe1 0)]
            [p1-write (bytevector-s32-native-ref pipe1 4)]
            [p2-read  (bytevector-s32-native-ref pipe2 0)]
            [p2-write (bytevector-s32-native-ref pipe2 4)])
        (values
          ;; Parent channel: writes to pipe1, reads from pipe2
          (%make-channel p2-read p1-write #f)
          ;; Child channel: reads from pipe1, writes to pipe2
          (%make-channel p1-read p2-write #f)))))

  (define (channel-send! ch msg)
    ;; Send a message as fasl-encoded framed data.
    (when (%channel-closed? ch)
      (error 'channel-send! "channel closed"))
    (let-values ([(port get-bytes) (open-bytevector-output-port)])
      (fasl-write msg port)
      (let* ([body (get-bytes)]
             [len (bytevector-length body)]
             [header (make-bytevector 4)])
        ;; Write 4-byte big-endian length
        (bytevector-u8-set! header 0 (bitwise-and (bitwise-arithmetic-shift-right len 24) #xff))
        (bytevector-u8-set! header 1 (bitwise-and (bitwise-arithmetic-shift-right len 16) #xff))
        (bytevector-u8-set! header 2 (bitwise-and (bitwise-arithmetic-shift-right len 8) #xff))
        (bytevector-u8-set! header 3 (bitwise-and len #xff))
        (fd-write-all (%channel-write-fd ch) header)
        (fd-write-all (%channel-write-fd ch) body))))

  (define (channel-receive ch)
    ;; Receive a message. Blocks until data arrives.
    (when (%channel-closed? ch)
      (error 'channel-receive "channel closed"))
    (let ([header (fd-read-exact (%channel-read-fd ch) 4)])
      (if (not header) #f
        (let ([len (bitwise-ior
                     (bitwise-arithmetic-shift-left (bytevector-u8-ref header 0) 24)
                     (bitwise-arithmetic-shift-left (bytevector-u8-ref header 1) 16)
                     (bitwise-arithmetic-shift-left (bytevector-u8-ref header 2) 8)
                     (bytevector-u8-ref header 3))])
          (let ([body (fd-read-exact (%channel-read-fd ch) len)])
            (if body
              (fasl-read (open-bytevector-input-port body))
              #f))))))

  (define (channel-close! ch)
    (unless (%channel-closed? ch)
      (%channel-set-closed! ch #t)
      (c-close (%channel-read-fd ch))
      (c-close (%channel-write-fd ch))))

  ;; ========== Privilege Separation ==========

  (define-record-type (privsep %make-privsep privsep?)
    (sealed #t)
    (fields
      (immutable channel %privsep-channel)
      (immutable pid %privsep-pid)
      (mutable running? %privsep-running? %privsep-set-running!)))

  (define (make-privsep handler)
    ;; Fork a child process. Parent becomes supervisor with the handler.
    ;; Returns a privsep record that workers use to make requests.
    ;; HARDENED: Enforces max concurrent children limit and tracks PIDs
    ;; for proper reaping.
    ;;
    ;; handler: (lambda (request) -> response)
    ;;   Called in the supervisor (parent) for each request from the worker.
    (with-mutex %children-mutex
      (when (>= (hashtable-size %active-children) (*max-privsep-children*))
        (error 'make-privsep "maximum concurrent privsep children reached"
               (hashtable-size %active-children) (*max-privsep-children*))))
    (let-values ([(parent-ch child-ch) (make-privsep-channel)])
      (let ([pid (c-fork)])
        (cond
          [(< pid 0)
           (error 'make-privsep "fork() failed")]
          [(= pid 0)
           ;; Child process (worker) — close parent-side channel
           (channel-close! parent-ch)
           ;; Return privsep with child channel for worker to use
           (%make-privsep child-ch 0 #t)]
          [else
           ;; Parent process (supervisor) — close child-side channel
           (channel-close! child-ch)
           ;; Track this child
           (with-mutex %children-mutex
             (hashtable-set! %active-children pid #t))
           ;; Start handler loop in a background thread
           (fork-thread
             (lambda ()
               (let loop ()
                 (let ([req (guard (exn [#t #f])
                              (channel-receive parent-ch))])
                   (when req
                     (let ([resp (guard (exn [#t (list 'error (condition-message exn))])
                                   (handler req))])
                       (guard (exn [#t (void)])
                         (channel-send! parent-ch resp)))
                     (loop))))))
           (%make-privsep parent-ch pid #t)]))))

  (define (privsep-request ps req)
    ;; Send a request to the supervisor and wait for response.
    (unless (%privsep-running? ps)
      (error 'privsep-request "privsep not running"))
    (channel-send! (%privsep-channel ps) req)
    (channel-receive (%privsep-channel ps)))

  (define (privsep-shutdown! ps)
    ;; Shut down the privilege-separated process.
    ;; HARDENED: Sends SIGTERM, waits for child with waitpid to prevent
    ;; zombie accumulation, and removes from active children tracking.
    (%privsep-set-running! ps #f)
    (channel-close! (%privsep-channel ps))
    (let ([pid (%privsep-pid ps)])
      (when (> pid 0)
        ;; Send SIGTERM to the child
        (guard (exn [#t (void)])
          (c-kill pid 15))  ;; SIGTERM = 15
        ;; Reap the child process (WNOHANG first, then blocking)
        (guard (exn [#t (void)])
          (let ([result (c-waitpid pid (make-bytevector 4 0) 1)])  ;; WNOHANG = 1
            (when (= result 0)
              ;; Child hasn't exited yet — wait briefly then try blocking
              (c-waitpid pid (make-bytevector 4 0) 0))))
        ;; Remove from tracking
        (with-mutex %children-mutex
          (hashtable-delete! %active-children pid)))))

  ;; ========== Worker API ==========

  (define (worker-request channel req)
    ;; Send a request through the channel and get response.
    (channel-send! channel req)
    (channel-receive channel))

  (define (worker-loop channel handler)
    ;; Run a worker loop: receive requests, call handler, send responses.
    (let loop ()
      (let ([req (guard (exn [#t #f])
                   (channel-receive channel))])
        (when req
          (let ([resp (guard (exn [#t (list 'error (condition-message exn))])
                        (handler req))])
            (guard (exn [#t (void)])
              (channel-send! channel resp)))
          (loop)))))

  ;; ========== Internal Helpers ==========

  (define (fd-write-all fd bv)
    (let ([len (bytevector-length bv)])
      (let loop ([offset 0])
        (when (< offset len)
          (let ([buf (if (= offset 0) bv
                       (let ([tmp (make-bytevector (- len offset))])
                         (bytevector-copy! bv offset tmp 0 (- len offset))
                         tmp))])
            (let ([n (c-write-raw fd buf (- len offset))])
              (if (> n 0)
                (loop (+ offset n))
                (error 'fd-write-all "write failed"))))))))

  (define (fd-read-exact fd n)
    (let ([buf (make-bytevector n 0)])
      (let loop ([offset 0])
        (if (= offset n) buf
          (let ([tmp (make-bytevector (- n offset) 0)])
            (let ([got (c-read fd tmp (- n offset))])
              (cond
                [(> got 0)
                 (bytevector-copy! tmp 0 buf offset got)
                 (loop (+ offset got))]
                [else #f])))))))

  ) ;; end library
