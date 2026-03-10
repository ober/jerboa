#!chezscheme
(import (chezscheme) (std os epoll))

(define pass-count 0)
(define fail-count 0)

(define-syntax chk
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr] [exp expected])
       (if (equal? result exp) (set! pass-count (+ pass-count 1))
         (begin (set! fail-count (+ fail-count 1))
                (display "FAIL: ") (write 'expr)
                (display " => ") (write result)
                (display " expected ") (write exp) (newline))))]))

;; Constants
(chk (> EPOLLIN 0) => #t)
(chk (> EPOLLOUT 0) => #t)

;; Create/close
(let ([epfd (epoll-create)])
  (chk (> epfd 0) => #t)
  (epoll-close epfd))

;; Pipe + epoll
(let-values ([(rfd wfd) (fd-pipe)])
  (let ([epfd (epoll-create)]
        [evts (make-epoll-events 4)])
    (epoll-add! epfd wfd EPOLLOUT)
    (let ([n (epoll-wait epfd evts 4 0)])
      (chk (> n 0) => #t))
    (free-epoll-events evts)
    (epoll-close epfd)
    (fd-close rfd)
    (fd-close wfd)))

(display "  epoll: ") (display pass-count) (display " passed")
(when (> fail-count 0) (display ", ") (display fail-count) (display " failed"))
(newline)
(when (> fail-count 0) (exit 1))
