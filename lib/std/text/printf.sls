#!chezscheme
;;; (std text printf) -- C-style Format Strings
;;;
;;; Supports: %d %i %s %f %e %x %X %o %b %c %%
;;; With: width, precision, left-align (-), zero-pad (0), + sign
;;;
;;; Usage:
;;;   (import (std text printf))
;;;   (sprintf "%d + %d = %d" 1 2 3)  ; => "1 + 2 = 3"
;;;   (sprintf "%08x" 255)             ; => "000000ff"
;;;   (sprintf "%.2f" 3.14159)         ; => "3.14"
;;;   (sprintf "%-20s|" "hello")       ; => "hello               |"
;;;   (cprintf "%d items" 42)          ; prints to current-output-port

(library (std text printf)
  (export
    sprintf
    cprintf
    fprintf*
    format-one)

  (import (chezscheme))

  ;; ========== sprintf ==========
  (define (sprintf fmt . args)
    (let ([out (open-output-string)])
      (apply fprintf-impl out fmt args)
      (get-output-string out)))

  ;; ========== cprintf (print to stdout) ==========
  (define (cprintf fmt . args)
    (apply fprintf-impl (current-output-port) fmt args))

  ;; ========== fprintf* (print to port) ==========
  (define (fprintf* port fmt . args)
    (apply fprintf-impl port fmt args))

  ;; ========== format-one ==========
  (define (format-one fmt val)
    ;; Format a single value with a format specifier
    (sprintf fmt val))

  ;; ========== Implementation ==========
  (define (fprintf-impl port fmt . args)
    (let ([n (string-length fmt)]
          [args-left args])
      (let loop ([i 0])
        (when (< i n)
          (let ([c (string-ref fmt i)])
            (cond
              [(and (char=? c #\%) (< (+ i 1) n))
               (let-values ([(spec end) (parse-format-spec fmt (+ i 1))])
                 (if (eq? (format-spec-type spec) 'percent)
                   (begin (display #\% port)
                          (loop end))
                   (if (null? args-left)
                     (begin (display "<?>" port)
                            (loop end))
                     (let ([val (car args-left)])
                       (set! args-left (cdr args-left))
                       (display (format-value spec val) port)
                       (loop end)))))]
              [else
               (display c port)
               (loop (+ i 1))]))))))

  ;; ========== Format Spec ==========
  (define-record-type format-spec
    (fields (immutable flags)      ;; string of flag chars
            (immutable width)      ;; #f or integer
            (immutable precision)  ;; #f or integer
            (immutable type))      ;; symbol: 'd 'f 's 'x 'X 'o 'b 'e 'c 'percent
    (protocol (lambda (new)
      (lambda (flags width prec type)
        (new flags width prec type)))))

  (define (parse-format-spec fmt start)
    ;; Returns (values spec end-index)
    (let ([n (string-length fmt)])
      ;; %% shortcut
      (if (and (< start n) (char=? (string-ref fmt start) #\%))
        (values (make-format-spec "" #f #f 'percent) (+ start 1))
        ;; Parse flags
        (let loop-flags ([i start] [flags '()])
          (if (and (< i n) (memv (string-ref fmt i) '(#\- #\+ #\0 #\space #\#)))
            (loop-flags (+ i 1) (cons (string-ref fmt i) flags))
            ;; Parse width
            (let-values ([(width i) (parse-number fmt i n)])
              ;; Parse precision
              (let-values ([(prec i)
                            (if (and (< i n) (char=? (string-ref fmt i) #\.))
                              (parse-number fmt (+ i 1) n)
                              (values #f i))])
                ;; Parse type
                (if (< i n)
                  (let ([type (case (string-ref fmt i)
                                [(#\d #\i) 'd]
                                [(#\f) 'f]
                                [(#\e #\E) 'e]
                                [(#\s) 's]
                                [(#\x) 'x]
                                [(#\X) 'X]
                                [(#\o) 'o]
                                [(#\b) 'b]
                                [(#\c) 'c]
                                [else 's])])
                    (values (make-format-spec (list->string (reverse flags))
                                             width prec type)
                            (+ i 1)))
                  (values (make-format-spec "" #f #f 's) i)))))))))

  (define (parse-number fmt i n)
    (let loop ([i i] [num #f])
      (if (and (< i n) (char-numeric? (string-ref fmt i)))
        (loop (+ i 1) (+ (* (or num 0) 10) (- (char->integer (string-ref fmt i)) 48)))
        (values num i))))

  ;; ========== Value Formatting ==========
  (define (format-value spec val)
    (let* ([type (format-spec-type spec)]
           [raw (case type
                  [(d) (if (number? val) (number->string (exact (truncate val))) (format "~a" val))]
                  [(f) (format-float val (or (format-spec-precision spec) 6))]
                  [(e) (format-scientific val (or (format-spec-precision spec) 6))]
                  [(s) (if (string? val) val (format "~a" val))]
                  [(x) (if (number? val)
                         (string-downcase (number->string (exact (truncate val)) 16))
                         (format "~a" val))]
                  [(X) (if (number? val)
                         (string-upcase (number->string (exact (truncate val)) 16))
                         (format "~a" val))]
                  [(o) (if (number? val)
                         (number->string (exact (truncate val)) 8)
                         (format "~a" val))]
                  [(b) (if (number? val)
                         (number->string (exact (truncate val)) 2)
                         (format "~a" val))]
                  [(c) (if (char? val) (string val)
                         (if (integer? val) (string (integer->char val))
                           (format "~a" val)))]
                  [else (format "~a" val)])]
           [flags (format-spec-flags spec)]
           [width (format-spec-width spec)]
           [left-align (string-contains-char? flags #\-)]
           [zero-pad (string-contains-char? flags #\0)]
           [plus (string-contains-char? flags #\+)])

      ;; Add + sign for positive numbers if requested
      (let ([raw (if (and plus (memq type '(d f e))
                          (number? val) (>= val 0))
                   (string-append "+" raw)
                   raw)])
        ;; Apply width padding
        (if (and width (> width (string-length raw)))
          (let ([pad-char (if (and zero-pad (not left-align)
                                   (memq type '(d f e x X o b))) #\0 #\space)]
                [pad-len (- width (string-length raw))])
            (if left-align
              (string-append raw (make-string pad-len #\space))
              (string-append (make-string pad-len pad-char) raw)))
          raw))))

  (define (format-float val prec)
    (if (not (number? val)) (format "~a" val)
      (let* ([v (inexact val)]
             [neg (< v 0)]
             [v (abs v)]
             [factor (expt 10 prec)]
             [rounded (/ (round (* v factor)) factor)]
             [int-part (exact (floor rounded))]
             [frac-part (- rounded int-part)]
             [frac-str (let ([s (number->string (exact (round (* frac-part factor))))])
                         (let pad ([s s])
                           (if (< (string-length s) prec)
                             (pad (string-append "0" s))
                             s)))])
        (string-append (if neg "-" "")
                       (number->string int-part)
                       "."
                       frac-str))))

  (define (format-scientific val prec)
    (if (not (number? val)) (format "~a" val)
      (let* ([v (inexact val)]
             [neg (< v 0)]
             [v (abs v)]
             [exp (if (= v 0.0) 0 (exact (floor (log10 v))))]
             [mantissa (if (= v 0.0) 0.0 (/ v (expt 10.0 exp)))])
        (string-append (if neg "-" "")
                       (format-float mantissa prec)
                       "e"
                       (if (>= exp 0) "+" "-")
                       (let ([s (number->string (abs exp))])
                         (if (< (string-length s) 2)
                           (string-append "0" s)
                           s))))))

  (define (log10 x)
    (/ (log x) (log 10)))

  (define (string-contains-char? s c)
    (let ([n (string-length s)])
      (let loop ([i 0])
        (cond
          [(= i n) #f]
          [(char=? (string-ref s i) c) #t]
          [else (loop (+ i 1))]))))

) ;; end library
