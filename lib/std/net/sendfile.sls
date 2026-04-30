#!chezscheme
;;; (std net sendfile) — Zero-copy file serving via sendfile(2)
;;;
;;; Uses the Linux sendfile(2) syscall to transfer file data directly
;;; from the kernel page cache to a socket, bypassing userspace copies.
;;; Fiber-aware: parks the fiber on EAGAIN for non-blocking sockets.
;;;
;;; API:
;;;   (fiber-sendfile sock-fd path poller)           — send entire file
;;;   (fiber-sendfile* sock-fd path offset count poller) — send range

(library (std net sendfile)
  (export
    fiber-sendfile
    fiber-sendfile*)

  (import (chezscheme)
          (std fiber)
          (std net io))

  ;; FFI
  (define _libc-loaded
    (let ((v (getenv "JERBOA_STATIC")))
      (if (and v (not (string=? v "")) (not (string=? v "0")))
          #f
          (load-shared-object #f))))

  (define c-open    (foreign-procedure "open" (string int) int))
  (define c-close   (foreign-procedure "close" (int) int))
  (define c-fstat   (foreign-procedure "__fxstat" (int int void*) int))
  (define c-sendfile (foreign-procedure "sendfile" (int int void* size_t) ssize_t))

  ;; errno
  (define c-errno-location
    (cond
      ((foreign-entry? "__errno_location")
       (foreign-procedure "__errno_location" () void*))
      (else (foreign-procedure "__errno_location" () void*))))
  (define (get-errno) (foreign-ref 'int (c-errno-location) 0))
  (define EAGAIN 11)
  (define EINTR 4)
  (define O_RDONLY 0)

  ;; Get file size using fstat
  (define (file-size-fd fd)
    ;; struct stat is 144 bytes on x86_64 Linux
    ;; st_size is at offset 48
    (let ([buf (foreign-alloc 144)])
      ;; __fxstat version 1 = STAT_VER_LINUX on x86_64
      (let ([rc (c-fstat 1 fd buf)])
        (if (< rc 0)
          (begin (foreign-free buf) -1)
          (let ([size (foreign-ref 'long buf 48)])  ;; st_size at offset 48
            (foreign-free buf)
            size)))))

  ;; Send entire file to socket using sendfile(2).
  ;; Returns total bytes sent.
  (define (fiber-sendfile sock-fd path poller)
    (let ([file-fd (c-open path O_RDONLY)])
      (when (< file-fd 0)
        (error 'fiber-sendfile "open() failed" path))
      (let ([size (file-size-fd file-fd)])
        (when (< size 0)
          (c-close file-fd)
          (error 'fiber-sendfile "fstat() failed" path))
        (let ([result (fiber-sendfile-loop sock-fd file-fd 0 size poller)])
          (c-close file-fd)
          result))))

  ;; Send a range of a file.
  ;; Returns total bytes sent.
  (define (fiber-sendfile* sock-fd path offset count poller)
    (let ([file-fd (c-open path O_RDONLY)])
      (when (< file-fd 0)
        (error 'fiber-sendfile* "open() failed" path))
      (let ([result (fiber-sendfile-loop sock-fd file-fd offset count poller)])
        (c-close file-fd)
        result)))

  ;; Internal: sendfile loop with fiber parking on EAGAIN
  (define (fiber-sendfile-loop sock-fd file-fd offset count poller)
    (let ([off-buf (foreign-alloc 8)])
      (foreign-set! 'long off-buf 0 offset)
      (let loop ([remaining count] [total 0])
        (if (<= remaining 0)
          (begin (foreign-free off-buf) total)
          (let ([rc (c-sendfile sock-fd file-fd off-buf remaining)])
            (cond
              [(> rc 0)
               (loop (- remaining rc) (+ total rc))]
              [(= rc 0)
               ;; EOF
               (foreign-free off-buf)
               total]
              [else
               (let ([e (get-errno)])
                 (cond
                   [(or (= e EAGAIN) (= e EINTR))
                    ;; Socket buffer full — park fiber until writable
                    (fiber-wait-writable sock-fd poller)
                    (loop remaining total)]
                   [else
                    (foreign-free off-buf)
                    total]))]))))))

) ;; end library
