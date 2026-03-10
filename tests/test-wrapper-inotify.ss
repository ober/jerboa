#!chezscheme
(import (chezscheme) (std os inotify))

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
(chk (> IN_CREATE 0) => #t)
(chk (> IN_DELETE 0) => #t)

;; Create/close
(let ([fd (inotify-init)])
  (chk (> fd 0) => #t)
  (inotify-close fd))

;; Watch + create file + read event
(let ([dir (format "/tmp/jerboa-inotify-~a" (random 1000000))])
  (mkdir dir)
  (let ([fd (inotify-init)])
    (let ([wd (inotify-add-watch fd dir IN_CREATE)])
      (chk (>= wd 0) => #t)
      (call-with-output-file (format "~a/t.txt" dir)
        (lambda (p) (display "x" p)))
      (when (inotify-poll fd 100)
        (let ([evts (inotify-read-events fd)])
          (chk (> (length evts) 0) => #t)
          (chk (equal? (inotify-event-name (car evts)) "t.txt") => #t)))
      (inotify-rm-watch fd wd))
    (inotify-close fd))
  (delete-file (format "~a/t.txt" dir))
  (delete-directory dir #f))

(display "  inotify: ") (display pass-count) (display " passed")
(when (> fail-count 0) (display ", ") (display fail-count) (display " failed"))
(newline)
(when (> fail-count 0) (exit 1))
