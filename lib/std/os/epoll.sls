#!chezscheme
;;; :std/os/epoll -- Linux epoll (wraps chez-epoll)
;;; Requires: chez_epoll_shim.so

(library (std os epoll)
  (export
    epoll-create epoll-close
    epoll-add! epoll-modify! epoll-remove!
    epoll-wait
    make-epoll-events free-epoll-events
    epoll-event-fd epoll-event-events
    fd-pipe fd-write fd-read fd-close
    EPOLLIN EPOLLOUT EPOLLERR EPOLLHUP
    EPOLLET EPOLLONESHOT EPOLLRDHUP EPOLLPRI)

  (import (chez-epoll))

  ) ;; end library
