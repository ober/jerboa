#!chezscheme
;;; (std datetime) — Date/time handling for data pipelines
;;;
;;; Pure Scheme implementation with ISO 8601 support.
;;; Dates are stored as records with year/month/day/hour/minute/second/nanosecond/offset.
;;; Designed for parsing timestamps from data sources (CSV, Parquet, databases).

(library (std datetime)
  (export
    ;; Constructors
    make-datetime datetime?
    make-date make-time
    datetime-now datetime-utc-now
    ;; Accessors
    datetime-year datetime-month datetime-day
    datetime-hour datetime-minute datetime-second
    datetime-nanosecond datetime-offset
    ;; Parsing
    parse-datetime parse-date parse-time
    ;; Formatting
    datetime->string date->string time->string
    datetime->iso8601
    ;; Conversion
    datetime->epoch epoch->datetime
    datetime->julian julian->datetime
    ;; Arithmetic
    datetime-add datetime-subtract
    datetime-diff
    duration duration? duration-seconds duration-nanoseconds
    make-duration
    ;; Comparison
    datetime<? datetime>? datetime=? datetime<=? datetime>=?
    datetime-min datetime-max datetime-clamp
    ;; Components
    day-of-week day-of-year days-in-month leap-year?
    ;; Utilities
    datetime->alist
    datetime-truncate
    datetime-floor-hour datetime-floor-day datetime-floor-month)

  (import (except (chezscheme) make-date make-time))

  ;; --- Records ---

  (define-record-type dt
    (fields year month day hour minute second nanosecond offset)
    (protocol
      (lambda (new)
        (case-lambda
          [(y m d) (new y m d 0 0 0 0 0)]
          [(y m d h mi s) (new y m d h mi s 0 0)]
          [(y m d h mi s ns) (new y m d h mi s ns 0)]
          [(y m d h mi s ns off) (new y m d h mi s ns off)]))))

  (define (datetime? x) (dt? x))

  (define (make-datetime y m d . rest)
    (apply make-dt y m d rest))

  (define (make-date y m d)
    (make-dt y m d 0 0 0 0 0))

  (define (make-time h m s)
    (make-dt 0 0 0 h m s 0 0))

  ;; Accessors
  (define datetime-year dt-year)
  (define datetime-month dt-month)
  (define datetime-day dt-day)
  (define datetime-hour dt-hour)
  (define datetime-minute dt-minute)
  (define datetime-second dt-second)
  (define datetime-nanosecond dt-nanosecond)
  (define datetime-offset dt-offset)

  ;; --- Current time ---

  (define (datetime-now)
    (let ([t (current-time 'time-utc)])
      (epoch->datetime (time-second t))))

  (define datetime-utc-now datetime-now)

  ;; --- Epoch conversion ---

  ;; Seconds since 1970-01-01T00:00:00Z
  (define (datetime->epoch dt)
    (let* ([y (dt-year dt)]
           [m (dt-month dt)]
           [d (dt-day dt)]
           [jd (date->julian-day y m d)]
           [epoch-jd (date->julian-day 1970 1 1)]
           [days (- jd epoch-jd)]
           [secs (+ (* days 86400)
                    (* (dt-hour dt) 3600)
                    (* (dt-minute dt) 60)
                    (dt-second dt)
                    (- (* (dt-offset dt) 60)))])  ;; offset is minutes from UTC
      secs))

  (define (epoch->datetime secs)
    (let* ([days (floor (/ secs 86400))]
           [rem (- secs (* days 86400))]
           [rem (if (< rem 0) (begin (set! days (- days 1)) (+ rem 86400)) rem)]
           [h (floor (/ rem 3600))]
           [rem (- rem (* h 3600))]
           [mi (floor (/ rem 60))]
           [s (- rem (* mi 60))])
      (let-values ([(y m d) (julian-day->date (+ (date->julian-day 1970 1 1) days))])
        (make-dt (exact y) (exact m) (exact d)
                 (exact h) (exact mi) (exact s) 0 0))))

  ;; --- Julian day helpers ---

  (define (date->julian-day y m d)
    (let* ([a (quotient (- 14 m) 12)]
           [y1 (+ y 4800 (- a))]
           [m1 (+ m (* 12 a) -3)])
      (+ d
         (quotient (+ (* 153 m1) 2) 5)
         (* 365 y1)
         (quotient y1 4)
         (- (quotient y1 100))
         (quotient y1 400)
         -32045)))

  (define (julian-day->date jd)
    (let* ([a (+ jd 32044)]
           [b (quotient (+ (* 4 a) 3) 146097)]
           [c (- a (quotient (* 146097 b) 4))]
           [d (quotient (+ (* 4 c) 3) 1461)]
           [e (- c (quotient (* 1461 d) 4))]
           [m (quotient (+ (* 5 e) 2) 153)]
           [day (+ e (- (quotient (+ (* 153 m) 2) 5)) 1)]
           [month (+ m 3 (- (* 12 (quotient m 10))))]
           [year (+ (* 100 b) d -4800 (quotient m 10))])
      (values year month day)))

  (define datetime->julian
    (lambda (dt)
      (date->julian-day (dt-year dt) (dt-month dt) (dt-day dt))))

  (define julian->datetime
    (lambda (jd)
      (let-values ([(y m d) (julian-day->date jd)])
        (make-dt y m d 0 0 0 0 0))))

  ;; --- Parsing ---

  ;; Parse ISO 8601: "2024-03-25T10:30:00Z" or "2024-03-25T10:30:00+05:30"
  ;; Also handles: "2024-03-25", "2024-03-25 10:30:00", "2024-03-25T10:30:00.123456789Z"
  (define (parse-datetime str)
    (let ([len (string-length str)])
      (when (< len 10)
        (error 'parse-datetime "string too short" str))
      (let* ([year (string->number (substring str 0 4))]
             [month (string->number (substring str 5 7))]
             [day (string->number (substring str 8 10))])
        (unless (and year month day)
          (error 'parse-datetime "invalid date components" str))
        (if (<= len 10)
          (make-dt year month day 0 0 0 0 0)
          ;; Has time component
          (let ([sep-pos 10])
            (unless (or (char=? (string-ref str sep-pos) #\T)
                        (char=? (string-ref str sep-pos) #\t)
                        (char=? (string-ref str sep-pos) #\space))
              (error 'parse-datetime "expected T or space separator" str))
            (when (< len 19)
              (error 'parse-datetime "incomplete time" str))
            (let* ([hour (string->number (substring str 11 13))]
                   [minute (string->number (substring str 14 16))]
                   [second (string->number (substring str 17 19))])
              (unless (and hour minute second)
                (error 'parse-datetime "invalid time components" str))
              ;; Check for fractional seconds
              (let-values ([(ns rest-pos)
                            (if (and (> len 19) (char=? (string-ref str 19) #\.))
                              (parse-fractional str 20)
                              (values 0 19))])
                ;; Check for timezone
                (let ([offset (parse-tz-offset str rest-pos len)])
                  (make-dt year month day hour minute second ns offset)))))))))

  ;; Parse fractional seconds, return (values nanoseconds end-position)
  (define (parse-fractional str start)
    (let loop ([i start] [digits '()])
      (if (and (< i (string-length str))
               (char<=? #\0 (string-ref str i))
               (char<=? (string-ref str i) #\9))
        (loop (+ i 1) (cons (string-ref str i) digits))
        (let* ([digit-str (list->string (reverse digits))]
               ;; Pad to 9 digits for nanoseconds
               [padded (string-append digit-str
                         (make-string (max 0 (- 9 (length digits))) #\0))]
               [ns (string->number (substring padded 0 9))])
          (values (or ns 0) i)))))

  ;; Parse timezone offset from position, return offset in minutes
  (define (parse-tz-offset str pos len)
    (cond
      [(>= pos len) 0]
      [(char=? (string-ref str pos) #\Z) 0]
      [(char=? (string-ref str pos) #\z) 0]
      [(or (char=? (string-ref str pos) #\+)
           (char=? (string-ref str pos) #\-))
       (let* ([sign (if (char=? (string-ref str pos) #\+) 1 -1)]
              [tz-str (substring str (+ pos 1) len)]
              [tz-h (string->number (substring tz-str 0 2))]
              [tz-m (if (> (string-length tz-str) 2)
                      (string->number (substring tz-str
                                        (if (char=? (string-ref tz-str 2) #\:) 3 2)
                                        (min (string-length tz-str)
                                             (if (char=? (string-ref tz-str 2) #\:) 5 4))))
                      0)])
         (* sign (+ (* (or tz-h 0) 60) (or tz-m 0))))]
      [else 0]))

  (define (parse-date str)
    (parse-datetime str))

  (define (parse-time str)
    ;; Parse "HH:MM:SS" or "HH:MM:SS.nnn"
    (parse-datetime (string-append "0000-01-01T" str)))

  ;; --- Formatting ---

  (define (pad2 n)
    (if (< n 10)
      (string-append "0" (number->string n))
      (number->string n)))

  (define (pad4 n)
    (cond
      [(< n 10) (string-append "000" (number->string n))]
      [(< n 100) (string-append "00" (number->string n))]
      [(< n 1000) (string-append "0" (number->string n))]
      [else (number->string n)]))

  (define (datetime->iso8601 d)
    (let ([base (string-append
                  (pad4 (dt-year d)) "-"
                  (pad2 (dt-month d)) "-"
                  (pad2 (dt-day d)) "T"
                  (pad2 (dt-hour d)) ":"
                  (pad2 (dt-minute d)) ":"
                  (pad2 (dt-second d)))])
      (let ([with-ns (if (> (dt-nanosecond d) 0)
                       (string-append base "."
                         (let ([s (number->string (dt-nanosecond d))])
                           (string-append (make-string (- 9 (string-length s)) #\0) s)))
                       base)])
        (cond
          [(= (dt-offset d) 0) (string-append with-ns "Z")]
          [else
           (let* ([abs-off (abs (dt-offset d))]
                  [sign (if (>= (dt-offset d) 0) "+" "-")]
                  [h (quotient abs-off 60)]
                  [m (remainder abs-off 60)])
             (string-append with-ns sign (pad2 h) ":" (pad2 m)))]))))

  (define (datetime->string d)
    (datetime->iso8601 d))

  (define (date->string d)
    (string-append (pad4 (dt-year d)) "-"
                   (pad2 (dt-month d)) "-"
                   (pad2 (dt-day d))))

  (define (time->string d)
    (string-append (pad2 (dt-hour d)) ":"
                   (pad2 (dt-minute d)) ":"
                   (pad2 (dt-second d))))

  ;; --- Duration ---

  (define-record-type dur
    (fields seconds nanoseconds))

  (define (duration? x) (dur? x))
  (define duration-seconds dur-seconds)
  (define duration-nanoseconds dur-nanoseconds)

  (define make-duration
    (case-lambda
      [(secs) (make-dur secs 0)]
      [(secs ns) (make-dur secs ns)]))

  (define duration make-duration)

  ;; --- Arithmetic ---

  ;; Add a duration (or seconds) to a datetime
  (define datetime-add
    (case-lambda
      [(d secs) (datetime-add d secs 0)]
      [(d secs ns)
       (let* ([total-ns (+ (dt-nanosecond d) ns)]
              [carry-s (quotient total-ns 1000000000)]
              [new-ns (remainder total-ns 1000000000)]
              [epoch (+ (datetime->epoch d) secs carry-s)])
         (let ([base (epoch->datetime epoch)])
           (make-dt (dt-year base) (dt-month base) (dt-day base)
                    (dt-hour base) (dt-minute base) (dt-second base)
                    new-ns (dt-offset d))))]))

  ;; Subtract seconds from a datetime
  (define datetime-subtract
    (case-lambda
      [(d secs) (datetime-add d (- secs))]
      [(d secs ns) (datetime-add d (- secs) (- ns))]))

  ;; Difference between two datetimes in seconds
  (define (datetime-diff d1 d2)
    (- (datetime->epoch d1) (datetime->epoch d2)))

  ;; --- Comparison ---

  (define (datetime<? a b) (< (datetime->epoch a) (datetime->epoch b)))
  (define (datetime>? a b) (> (datetime->epoch a) (datetime->epoch b)))
  (define (datetime=? a b) (= (datetime->epoch a) (datetime->epoch b)))
  (define (datetime<=? a b) (<= (datetime->epoch a) (datetime->epoch b)))
  (define (datetime>=? a b) (>= (datetime->epoch a) (datetime->epoch b)))

  (define (datetime-min a b) (if (datetime<? a b) a b))
  (define (datetime-max a b) (if (datetime>? a b) a b))

  (define (datetime-clamp d lo hi)
    (datetime-min (datetime-max d lo) hi))

  ;; --- Calendar utilities ---

  (define (leap-year? y)
    (or (and (zero? (mod y 4)) (not (zero? (mod y 100))))
        (zero? (mod y 400))))

  (define (days-in-month y m)
    (case m
      [(1 3 5 7 8 10 12) 31]
      [(4 6 9 11) 30]
      [(2) (if (leap-year? y) 29 28)]
      [else (error 'days-in-month "invalid month" m)]))

  ;; 0=Sunday, 1=Monday, ..., 6=Saturday (Zeller's formula)
  (define (day-of-week y m d)
    (let* ([jd (date->julian-day y m d)])
      (mod (+ jd 1) 7)))

  (define (day-of-year y m d)
    (let loop ([i 1] [total 0])
      (if (= i m) (+ total d)
        (loop (+ i 1) (+ total (days-in-month y i))))))

  ;; --- Utilities ---

  (define (datetime->alist d)
    (list (cons 'year (dt-year d))
          (cons 'month (dt-month d))
          (cons 'day (dt-day d))
          (cons 'hour (dt-hour d))
          (cons 'minute (dt-minute d))
          (cons 'second (dt-second d))
          (cons 'nanosecond (dt-nanosecond d))
          (cons 'offset (dt-offset d))))

  ;; Truncate to given precision
  (define (datetime-truncate d precision)
    (case precision
      [(year) (make-dt (dt-year d) 1 1 0 0 0 0 (dt-offset d))]
      [(month) (make-dt (dt-year d) (dt-month d) 1 0 0 0 0 (dt-offset d))]
      [(day) (make-dt (dt-year d) (dt-month d) (dt-day d) 0 0 0 0 (dt-offset d))]
      [(hour) (make-dt (dt-year d) (dt-month d) (dt-day d)
                       (dt-hour d) 0 0 0 (dt-offset d))]
      [(minute) (make-dt (dt-year d) (dt-month d) (dt-day d)
                         (dt-hour d) (dt-minute d) 0 0 (dt-offset d))]
      [(second) (make-dt (dt-year d) (dt-month d) (dt-day d)
                         (dt-hour d) (dt-minute d) (dt-second d) 0 (dt-offset d))]
      [else (error 'datetime-truncate "invalid precision" precision)]))

  (define (datetime-floor-hour d)
    (datetime-truncate d 'hour))

  (define (datetime-floor-day d)
    (datetime-truncate d 'day))

  (define (datetime-floor-month d)
    (datetime-truncate d 'month))

  ) ;; end library
