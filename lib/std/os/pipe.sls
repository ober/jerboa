#!chezscheme
;;; (std os pipe) — Unix pipe operations
;;;
;;; Create pipe pairs for inter-thread/process communication.

(library (std os pipe)
  (export open-pipe pipe->ports)

  (import (chezscheme))

  (define dummy-load
    (or (guard (e [#t #f]) (load-shared-object "libc.so.7"))
        (guard (e [#t #f]) (load-shared-object "libc.so.6"))
        (load-shared-object "libc.so")))

  (define c-pipe
    (foreign-procedure "pipe" (u8* ) int))

  (define c-fdopen
    (foreign-procedure "fdopen" (int string) uptr))

  ;; Helper: extract two ints from a bytevector (pipe fds)
  (define (bv->fd-pair bv)
    (values (bytevector-s32-native-ref bv 0)
            (bytevector-s32-native-ref bv 4)))

  ;; Create a pipe, return (values read-fd write-fd)
  (define (open-pipe)
    (let ([bv (make-bytevector 8 0)])
      (let ([ret (c-pipe bv)])
        (when (< ret 0)
          (error 'open-pipe "pipe(2) failed"))
        (bv->fd-pair bv))))

  ;; Convert pipe file descriptors to Scheme ports
  ;; Returns (values input-port output-port)
  (define (pipe->ports)
    (let-values ([(rfd wfd) (open-pipe)])
      (values
        (open-fd-input-port rfd)
        (open-fd-output-port wfd))))

) ;; end library
