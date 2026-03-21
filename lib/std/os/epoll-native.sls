#!chezscheme
;;; (std os epoll-native) — Linux epoll via Rust/libc
;;;
;;; Replaces chez-epoll dependency with Rust native implementation.

(library (std os epoll-native)
  (export
    epoll-create epoll-close
    epoll-add! epoll-modify! epoll-remove!
    epoll-wait
    EPOLLIN EPOLLOUT EPOLLERR EPOLLHUP
    EPOLLET EPOLLONESHOT EPOLLRDHUP EPOLLPRI
    EPOLL_CTL_ADD EPOLL_CTL_MOD EPOLL_CTL_DEL)

  (import (chezscheme))

  (define _native-loaded
    (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "./lib/libjerboa_native.so") #t)
        (error 'std/os/epoll-native "libjerboa_native.so not found")))

  ;; Constants
  (define EPOLLIN        #x001)
  (define EPOLLPRI       #x002)
  (define EPOLLOUT       #x004)
  (define EPOLLERR       #x008)
  (define EPOLLHUP       #x010)
  (define EPOLLRDHUP     #x2000)
  (define EPOLLET        (bitwise-arithmetic-shift-left 1 31))
  (define EPOLLONESHOT   (bitwise-arithmetic-shift-left 1 30))

  (define EPOLL_CTL_ADD  1)
  (define EPOLL_CTL_DEL  2)
  (define EPOLL_CTL_MOD  3)

  ;; FFI
  (define c-epoll-create
    (foreign-procedure "jerboa_epoll_create" () int))
  (define c-epoll-ctl
    (foreign-procedure "jerboa_epoll_ctl" (int int int unsigned-32) int))
  (define c-epoll-wait
    (foreign-procedure "jerboa_epoll_wait" (int u8* int int) int))
  (define c-epoll-close
    (foreign-procedure "jerboa_epoll_close" (int) int))

  ;; --- Public API ---

  (define (epoll-create)
    (let ([fd (c-epoll-create)])
      (when (< fd 0) (error 'epoll-create "epoll_create1 failed"))
      fd))

  (define (epoll-close epfd)
    (c-epoll-close epfd)
    (void))

  (define (epoll-add! epfd fd events)
    (let ([rc (c-epoll-ctl epfd EPOLL_CTL_ADD fd events)])
      (when (< rc 0) (error 'epoll-add! "epoll_ctl ADD failed" fd))
      (void)))

  (define (epoll-modify! epfd fd events)
    (let ([rc (c-epoll-ctl epfd EPOLL_CTL_MOD fd events)])
      (when (< rc 0) (error 'epoll-modify! "epoll_ctl MOD failed" fd))
      (void)))

  (define (epoll-remove! epfd fd)
    (let ([rc (c-epoll-ctl epfd EPOLL_CTL_DEL fd 0)])
      (when (< rc 0) (error 'epoll-remove! "epoll_ctl DEL failed" fd))
      (void)))

  ;; Returns list of (fd . events) pairs
  (define (epoll-wait epfd max-events timeout-ms)
    (let ([buf (make-bytevector (* max-events 8))])
      (let ([n (c-epoll-wait epfd buf max-events timeout-ms)])
        (when (< n 0) (error 'epoll-wait "epoll_wait failed"))
        (let loop ([i 0] [acc '()])
          (if (>= i n) (reverse acc)
            (let ([offset (* i 8)])
              (let ([fd (bytevector-s32-native-ref buf offset)]
                    [events (bytevector-u32-native-ref buf (+ offset 4))])
                (loop (+ i 1) (cons (cons fd events) acc)))))))))

  ) ;; end library
