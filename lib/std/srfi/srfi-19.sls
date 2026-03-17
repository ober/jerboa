#!chezscheme
;;; :std/srfi/19 -- Date/time handling

(library (std srfi srfi-19)
  (export
    current-date
    current-time
    time?
    date?
    make-date
    date-nanosecond
    date-second
    date-minute
    date-hour
    date-day
    date-month
    date-year
    date-zone-offset
    date->string
    string->date
    date->time-utc
    time-utc->date
    time->seconds
    seconds->time
    time-difference
    add-duration
    time-utc
    make-time
    ;; Chez built-ins re-exported for Gerbil API compatibility
    time-second
    time-nanosecond
    time-type
    time-duration time-monotonic
    date-week-day)

  (import (chezscheme))

  (define time-utc 'time-utc)
  (define time-duration 'time-duration)
  (define time-monotonic 'time-monotonic)

  ;; All these are already provided by Chez:
  ;; current-date, current-time, time?, date?, make-date,
  ;; date-nanosecond, date-second, date-minute, date-hour,
  ;; date-day, date-month, date-year, date-zone-offset,
  ;; date->time-utc, time-utc->date, time-difference, add-duration

  ;; Gerbil's time->seconds: convert a time object to seconds as a float
  (define (time->seconds t)
    (if (time? t)
      (+ (time-second t) (/ (time-nanosecond t) 1000000000.0))
      t))

  (define (seconds->time secs)
    (let* ((whole (exact (floor secs)))
           (frac (- secs whole))
           (ns (exact (round (* frac 1000000000)))))
      (make-time 'time-utc ns whole)))

  (define (date->string d . rest)
    (let ((fmt (if (pair? rest) (car rest) "~Y-~m-~d ~H:~M:~S")))
      (let lp ((i 0) (out '()) (len (string-length fmt)))
        (cond
          ((>= i len) (list->string (reverse out)))
          ((and (< (+ i 1) len) (char=? (string-ref fmt i) #\~))
           (let* ((code (string-ref fmt (+ i 1)))
                  (replacement
                    (case code
                      ((#\Y) (pad4 (date-year d)))
                      ((#\m) (pad2 (date-month d)))
                      ((#\d) (pad2 (date-day d)))
                      ((#\H) (pad2 (date-hour d)))
                      ((#\M) (pad2 (date-minute d)))
                      ((#\S) (pad2 (date-second d)))
                      ((#\~) "~")
                      (else (string code)))))
             (lp (+ i 2) (append (reverse (string->list replacement)) out) len)))
          (else
           (lp (+ i 1) (cons (string-ref fmt i) out) len))))))

  (define (string->date str fmt)
    (let ((parts (string-tokenize str (lambda (c) (not (memv c '(#\- #\space #\: #\T)))))))
      (cond
        ((>= (length parts) 6)
         (make-date 0
           (string->number (list-ref parts 5))
           (string->number (list-ref parts 4))
           (string->number (list-ref parts 3))
           (string->number (list-ref parts 2))
           (string->number (list-ref parts 1))
           (string->number (list-ref parts 0))
           0))
        ((>= (length parts) 3)
         (make-date 0 0 0 0
           (string->number (list-ref parts 2))
           (string->number (list-ref parts 1))
           (string->number (list-ref parts 0))
           0))
        (else (error 'string->date "cannot parse date" str)))))

  ;; Helpers
  (define (pad2 n)
    (let ((s (number->string n)))
      (if (< (string-length s) 2) (string-append "0" s) s)))

  (define (pad4 n)
    (let ((s (number->string n)))
      (let lp ((s s))
        (if (< (string-length s) 4) (lp (string-append "0" s)) s))))

  (define (string-tokenize str pred)
    (let lp ((i 0) (tokens '()) (len (string-length str)))
      (cond
        ((>= i len) (reverse tokens))
        ((pred (string-ref str i))
         (let lp2 ((j (+ i 1)))
           (cond
             ((or (>= j len) (not (pred (string-ref str j))))
              (lp j (cons (substring str i j) tokens) len))
             (else (lp2 (+ j 1))))))
        (else (lp (+ i 1) tokens len)))))

  ) ;; end library
