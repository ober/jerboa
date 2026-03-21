#!chezscheme
;;; (std os tty) — Terminal detection and control
;;;
;;; Terminal detection, size queries, and raw mode control.

(library (std os tty)
  (export tty? tty-size with-raw-mode)

  (import (chezscheme))

  (define dummy-load (load-shared-object "libc.so.6"))

  (define c-isatty
    (foreign-procedure "isatty" (int) int))

  ;; Check if a file descriptor (or port) is a terminal
  (define (tty? fd-or-port)
    (let ([fd (if (fixnum? fd-or-port) fd-or-port 0)])
      (= 1 (c-isatty fd))))

  ;; Get terminal size as (values rows cols)
  ;; Uses stty as a portable fallback
  (define (tty-size)
    (guard (exn
      [else (values 24 80)])  ;; default fallback
      (let* ([result (with-output-to-string
                       (lambda () (system "stty size 2>/dev/null")))]
             [parts (string-split result #\space)])
        (if (>= (length parts) 2)
            (values (string->number (car parts))
                    (string->number (cadr parts)))
            (values 24 80)))))

  ;; Simple string split by char
  (define (string-split str ch)
    (let ([len (string-length str)])
      (let loop ([i 0] [start 0] [acc '()])
        (cond
          [(= i len)
           (let ([last (substring str start i)])
             (reverse (if (string=? last "") acc (cons last acc))))]
          [(char=? (string-ref str i) ch)
           (loop (+ i 1) (+ i 1)
                 (let ([s (substring str start i)])
                   (if (string=? s "") acc (cons s acc))))]
          [else (loop (+ i 1) start acc)]))))

  ;; Execute body with terminal in raw mode, restore on exit
  ;; Only works if stdin is a tty; otherwise just runs body
  (define-syntax with-raw-mode
    (syntax-rules ()
      [(_ body body* ...)
       (if (tty? 0)
           (dynamic-wind
             (lambda () (system "stty raw -echo 2>/dev/null"))
             (lambda () body body* ...)
             (lambda () (system "stty cooked echo 2>/dev/null")))
           (begin body body* ...))]))

) ;; end library
