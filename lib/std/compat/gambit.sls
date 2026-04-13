#!chezscheme
;;; :std/compat/gambit -- Gambit ## primitive compatibility
;;;
;;; Provides Chez equivalents for the ~5 Gambit ## primitives
;;; actually used by gerbil-emacs.

(library (std compat gambit)
  (export
    gambit-object->string
    gambit-cpu-count
    gambit-current-time-milliseconds
    gambit-heap-size)

  (import (chezscheme))

  ;; Load libc for sysconf
  (define load-libc (load-shared-object #f))

  ;; ##object->string — convert any value to its printed representation
  (define (gambit-object->string obj)
    (call-with-string-output-port
      (lambda (p) (write obj p))))

  ;; ##cpu-count — number of online processors
  ;; _SC_NPROCESSORS_ONLN: 58 on macOS/BSD, 84 on Linux
  (define gambit-cpu-count
    (let* ([mt (symbol->string (machine-type))]
           [len (string-length mt)]
           [ends? (lambda (sfx)
                    (let ([sl (string-length sfx)])
                      (and (>= len sl)
                           (string=? (substring mt (- len sl) len) sfx))))]
           [sc (if (or (ends? "osx") (ends? "fb") (ends? "ob") (ends? "nb"))
                 58 84)]
           [sysconf (foreign-procedure "sysconf" (long) long)])
      (lambda ()
        (let ([n (sysconf sc)])
          (if (> n 0) n 1)))))

  ;; ##current-time-milliseconds — monotonic time in milliseconds
  (define (gambit-current-time-milliseconds)
    (let ([t (current-time 'time-monotonic)])
      (+ (* (time-second t) 1000)
         (quotient (time-nanosecond t) 1000000))))

  ;; ##heap-size — approximate heap usage in bytes
  (define (gambit-heap-size)
    (let ([stats (statistics)])
      ;; statistics returns a vector of stats; bytes allocated is
      ;; available via (bytes-allocated)
      (bytes-allocated)))

  ) ;; end library
