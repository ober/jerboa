#!chezscheme
;;; (std time) -- High-Level Time Utilities
;;;
;;; Features:
;;;   - current-timestamp: ISO 8601 timestamp string
;;;   - elapsed: measure elapsed time of a thunk
;;;   - stopwatch: start/stop/lap timer
;;;   - duration->string: human-readable duration formatting
;;;   - throttle/debounce: rate-limiting wrappers
;;;   - time-it: print elapsed time (like Gerbil's time)
;;;   - with-timeout: run thunk with timeout
;;;
;;; Usage:
;;;   (import (std time))
;;;   (current-timestamp)       ; => "2024-01-15T14:30:45Z"
;;;   (elapsed (lambda () (fib 35)))  ; => 1.234 (seconds)
;;;   (time-it "fib" (lambda () (fib 35)))  ; prints timing
;;;
;;;   (define sw (make-stopwatch))
;;;   (stopwatch-start! sw)
;;;   ... work ...
;;;   (stopwatch-lap! sw "phase1")
;;;   ... more work ...
;;;   (stopwatch-stop! sw)
;;;   (stopwatch-report sw)

(library (std time)
  (export
    current-timestamp
    current-unix-time
    elapsed
    elapsed/values
    time-it
    duration->string
    seconds->duration

    ;; Stopwatch
    make-stopwatch
    stopwatch?
    stopwatch-start!
    stopwatch-stop!
    stopwatch-lap!
    stopwatch-elapsed
    stopwatch-laps
    stopwatch-report
    stopwatch-reset!

    ;; Rate limiting
    make-throttle
    make-debounce

    ;; Timeout
    with-timeout)

  (import (chezscheme))

  ;; ========== Timestamps ==========
  (define (current-timestamp)
    ;; ISO 8601 format: "2024-01-15T14:30:45Z"
    (let ([d (current-date)])
      (format "~4,'0d-~2,'0d-~2,'0dT~2,'0d:~2,'0d:~2,'0dZ"
        (date-year d) (date-month d) (date-day d)
        (date-hour d) (date-minute d) (date-second d))))

  (define (current-unix-time)
    ;; Seconds since epoch as flonum
    (let ([t (current-time)])
      (+ (time-second t)
         (/ (time-nanosecond t) 1000000000.0))))

  ;; ========== Elapsed Time ==========
  (define (elapsed thunk)
    ;; Returns elapsed seconds as flonum
    (let ([start (current-time 'time-monotonic)])
      (thunk)
      (let ([end (current-time 'time-monotonic)])
        (time-diff-seconds end start))))

  (define (elapsed/values thunk)
    ;; Returns (values result elapsed-seconds)
    (let ([start (current-time 'time-monotonic)])
      (call-with-values thunk
        (lambda results
          (let* ([end (current-time 'time-monotonic)]
                 [secs (time-diff-seconds end start)])
            (apply values (append results (list secs))))))))

  (define (time-it label thunk)
    ;; Print timing info, return result
    (let ([start (current-time 'time-monotonic)]
          [start-cpu (current-time 'time-process)])
      (let ([result (thunk)])
        (let* ([end (current-time 'time-monotonic)]
               [end-cpu (current-time 'time-process)]
               [wall (time-diff-seconds end start)]
               [cpu (time-diff-seconds end-cpu start-cpu)])
          (printf "~a: ~a wall, ~a cpu~n"
            label
            (duration->string wall)
            (duration->string cpu))
          result))))

  ;; ========== Duration Formatting ==========
  (define (duration->string seconds)
    ;; Human-readable duration: "1.234s", "5m 23s", "2h 15m", "3d 4h"
    (cond
      [(< seconds 0.001) (format "~aμs" (exact (round (* seconds 1000000))))]
      [(< seconds 1.0) (format "~ams" (round-to (* seconds 1000) 1))]
      [(< seconds 60) (format "~as" (round-to seconds 3))]
      [(< seconds 3600)
       (let* ([mins (exact (floor (/ seconds 60)))]
              [secs (exact (round (- seconds (* mins 60))))])
         (format "~am ~as" mins secs))]
      [(< seconds 86400)
       (let* ([hrs (exact (floor (/ seconds 3600)))]
              [mins (exact (round (/ (- seconds (* hrs 3600)) 60)))])
         (format "~ah ~am" hrs mins))]
      [else
       (let* ([days (exact (floor (/ seconds 86400)))]
              [hrs (exact (round (/ (- seconds (* days 86400)) 3600)))])
         (format "~ad ~ah" days hrs))]))

  (define (seconds->duration s)
    ;; Returns alist: ((days . N) (hours . N) (minutes . N) (seconds . N))
    (let* ([days (exact (floor (/ s 86400)))]
           [s (- s (* days 86400))]
           [hours (exact (floor (/ s 3600)))]
           [s (- s (* hours 3600))]
           [minutes (exact (floor (/ s 60)))]
           [secs (- s (* minutes 60))])
      `((days . ,days) (hours . ,hours) (minutes . ,minutes) (seconds . ,secs))))

  ;; ========== Stopwatch ==========
  (define-record-type stopwatch-rec
    (fields (mutable start-time)   ; time object or #f
            (mutable laps)          ; list of (label . seconds)
            (mutable last-lap)      ; time of last lap
            (mutable total))        ; total seconds after stop
    (protocol (lambda (new)
      (lambda () (new #f '() #f #f)))))

  (define (stopwatch? x) (stopwatch-rec? x))
  (define (make-stopwatch) (make-stopwatch-rec))

  (define (stopwatch-start! sw)
    (let ([now (current-time 'time-monotonic)])
      (stopwatch-rec-start-time-set! sw now)
      (stopwatch-rec-last-lap-set! sw now)
      (stopwatch-rec-laps-set! sw '())
      (stopwatch-rec-total-set! sw #f)))

  (define (stopwatch-stop! sw)
    (let* ([now (current-time 'time-monotonic)]
           [total (time-diff-seconds now (stopwatch-rec-start-time sw))])
      (stopwatch-rec-total-set! sw total)
      total))

  (define (stopwatch-lap! sw label)
    (let* ([now (current-time 'time-monotonic)]
           [lap-time (time-diff-seconds now (stopwatch-rec-last-lap sw))])
      (stopwatch-rec-last-lap-set! sw now)
      (stopwatch-rec-laps-set! sw
        (append (stopwatch-rec-laps sw) (list (cons label lap-time))))
      lap-time))

  (define (stopwatch-elapsed sw)
    (if (stopwatch-rec-total sw)
      (stopwatch-rec-total sw)
      (if (stopwatch-rec-start-time sw)
        (time-diff-seconds (current-time 'time-monotonic)
                           (stopwatch-rec-start-time sw))
        0.0)))

  (define (stopwatch-laps sw)
    (stopwatch-rec-laps sw))

  (define (stopwatch-report sw)
    (printf "Stopwatch Report:~n")
    (for-each
      (lambda (lap)
        (printf "  ~a: ~a~n" (car lap) (duration->string (cdr lap))))
      (stopwatch-rec-laps sw))
    (let ([total (stopwatch-elapsed sw)])
      (printf "  Total: ~a~n" (duration->string total))))

  (define (stopwatch-reset! sw)
    (stopwatch-rec-start-time-set! sw #f)
    (stopwatch-rec-laps-set! sw '())
    (stopwatch-rec-last-lap-set! sw #f)
    (stopwatch-rec-total-set! sw #f))

  ;; ========== Rate Limiting ==========
  (define (make-throttle interval-secs proc)
    ;; Returns a wrapped proc that can only be called once per interval
    (let ([last-call 0.0])
      (lambda args
        (let ([now (current-unix-time)])
          (when (>= (- now last-call) interval-secs)
            (set! last-call now)
            (apply proc args))))))

  (define (make-debounce delay-secs proc)
    ;; Returns a wrapped proc that delays execution; resets on each call
    ;; The last invocation within the delay window wins
    (let ([timer-thread #f]
          [latest-args #f]
          [lock (make-mutex)])
      (lambda args
        (with-mutex lock
          (set! latest-args args)
          (when timer-thread
            ;; Can't cancel thread in Chez, so we just let old one expire
            ;; and check if args changed
            (void))
          (let ([my-args args])
            (set! timer-thread
              (fork-thread
                (lambda ()
                  (sleep (make-time 'time-duration
                           (exact (round (* (- delay-secs (floor delay-secs)) 1000000000)))
                           (exact (floor delay-secs))))
                  (with-mutex lock
                    (when (eq? latest-args my-args)
                      (apply proc my-args)))))))))))

  ;; ========== Timeout ==========
  (define (with-timeout seconds thunk . default)
    ;; Run thunk with a timeout. Returns default (or raises) on timeout.
    ;; Uses a worker thread + polling since Chez lacks condition-wait-for.
    (let ([result-box (box #f)]
          [done? (box #f)])
      (fork-thread
        (lambda ()
          (let ([r (guard (exn [#t (cons 'error exn)])
                     (cons 'ok (thunk)))])
            (set-box! result-box r)
            (set-box! done? #t))))
      ;; Poll with short sleeps until done or timeout
      (let ([deadline (+ (current-unix-time) seconds)])
        (let loop ()
          (cond
            [(unbox done?)
             (let ([result (unbox result-box)])
               (cond
                 [(eq? (car result) 'error) (raise (cdr result))]
                 [else (cdr result)]))]
            [(>= (current-unix-time) deadline)
             (if (pair? default) (car default)
               (error 'with-timeout "operation timed out" seconds))]
            [else
             (sleep (make-time 'time-duration 5000000 0))  ;; 5ms poll
             (loop)])))))

  ;; ========== Helpers ==========
  (define (time-diff-seconds end start)
    (let ([diff (time-difference end start)])
      (+ (time-second diff)
         (/ (time-nanosecond diff) 1000000000.0))))

  (define (round-to n places)
    (let ([factor (expt 10 places)])
      (/ (round (* n factor)) factor)))

) ;; end library
