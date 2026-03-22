#!chezscheme
;;; (std misc fmt) — Format string compilation and formatting
;;;
;;; (define fmt-point (compile-format "Point(~a, ~a)"))
;;; (fmt-point 3 4) => "Point(3, 4)"
;;;
;;; (fmt "~a + ~a = ~a" 1 2 3) => "1 + 2 = 3"
;;; (fmt/port (current-output-port) "hello ~a~%" "world")

(library (std misc fmt)
  (export compile-format fmt fmt/port pad-left pad-right)
  (import (chezscheme))

  ;; --- String padding helpers ---

  (define (pad-left str width . maybe-char)
    (let* ([ch (if (null? maybe-char) #\space (car maybe-char))]
           [len (string-length str)]
           [pad (- width len)])
      (if (<= pad 0)
          str
          (string-append (make-string pad ch) str))))

  (define (pad-right str width . maybe-char)
    (let* ([ch (if (null? maybe-char) #\space (car maybe-char))]
           [len (string-length str)]
           [pad (- width len)])
      (if (<= pad 0)
          str
          (string-append str (make-string pad ch)))))

  ;; --- Format string parser (compile-time version via meta define) ---
  ;; Directives:
  ;;   (literal . "text"), (display), (write), (decimal), (binary),
  ;;   (octal), (hex), (newline), (tilde), (width . n)

  (meta define (ct-parse-fmt str)
    (let ([len (string-length str)])
      (let loop ([i 0] [acc '()] [lit-start 0])
        (cond
          [(>= i len)
           (reverse
             (if (< lit-start len)
                 (cons (cons 'literal (substring str lit-start len)) acc)
                 acc))]
          [(char=? (string-ref str i) #\~)
           (let ([acc (if (< lit-start i)
                          (cons (cons 'literal (substring str lit-start i)) acc)
                          acc)]
                 [j (+ i 1)])
             (when (>= j len)
               (error 'parse-format-string "incomplete directive at end" str))
             (if (char-numeric? (string-ref str j))
                 (let digit-loop ([k j] [digits '()])
                   (cond
                     [(>= k len)
                      (error 'parse-format-string "incomplete width directive" str)]
                     [(char-numeric? (string-ref str k))
                      (digit-loop (+ k 1) (cons (string-ref str k) digits))]
                     [(char=? (string-ref str k) #\w)
                      (let ([width (string->number (list->string (reverse digits)))])
                        (loop (+ k 1)
                              (cons (cons 'width width) acc)
                              (+ k 1)))]
                     [else
                      (error 'parse-format-string
                             "expected 'w' after width digits" str)]))
                 (let ([ch (string-ref str j)])
                   (case ch
                     [(#\a) (loop (+ j 1) (cons '(display) acc) (+ j 1))]
                     [(#\s) (loop (+ j 1) (cons '(write) acc) (+ j 1))]
                     [(#\d) (loop (+ j 1) (cons '(decimal) acc) (+ j 1))]
                     [(#\b) (loop (+ j 1) (cons '(binary) acc) (+ j 1))]
                     [(#\o) (loop (+ j 1) (cons '(octal) acc) (+ j 1))]
                     [(#\x) (loop (+ j 1) (cons '(hex) acc) (+ j 1))]
                     [(#\%) (loop (+ j 1) (cons '(newline) acc) (+ j 1))]
                     [(#\~) (loop (+ j 1) (cons '(tilde) acc) (+ j 1))]
                     [else
                      (error 'parse-format-string
                             "unknown directive" str ch)]))))]
          [else
           (loop (+ i 1) acc lit-start)]))))

  (meta define (ct-count-args directives)
    (let loop ([ds directives] [n 0])
      (if (null? ds)
          n
          (case (caar ds)
            [(literal newline tilde) (loop (cdr ds) n)]
            [else (loop (cdr ds) (+ n 1))]))))

  (meta define (ct-directive->code d arg-ref)
    (case (car d)
      [(literal)  `(display ,(cdr d) p)]
      [(display)  `(display ,arg-ref p)]
      [(write)    `(write ,arg-ref p)]
      [(decimal)  `(display (number->string ,arg-ref 10) p)]
      [(binary)   `(display (number->string ,arg-ref 2) p)]
      [(octal)    `(display (number->string ,arg-ref 8) p)]
      [(hex)      `(display (string-downcase (number->string ,arg-ref 16)) p)]
      [(newline)  '(newline p)]
      [(tilde)    `(display "~" p)]
      [(width)    `(display (pad-right (format "~a" ,arg-ref) ,(cdr d)) p)]
      [else (error 'directive->code "unknown directive" d)]))

  ;; --- compile-format macro ---
  ;; Parses the format string at compile time and produces a lambda
  ;; that calls display/write/etc. directly — no runtime parsing.

  (define-syntax compile-format
    (lambda (stx)
      (syntax-case stx ()
        [(k fmt-str)
         (string? (syntax->datum #'fmt-str))
         (let* ([str (syntax->datum #'fmt-str)]
                [directives (ct-parse-fmt str)]
                [nargs (ct-count-args directives)]
                [arg-names (map (lambda (i) (string->symbol (format "a~a" i)))
                                (iota nargs))])
           ;; Build the entire lambda as a datum, then inject it
           (let loop ([ds directives] [args arg-names] [body '()])
             (if (null? ds)
                 (let* ([body-forms (reverse body)]
                        [whole `(lambda ,arg-names
                                  (let ([p (open-output-string)])
                                    ,@body-forms
                                    (get-output-string p)))])
                   (datum->syntax #'k whole))
                 (let ([d (car ds)])
                   (case (car d)
                     [(literal newline tilde)
                      (loop (cdr ds) args
                            (cons (ct-directive->code d #f) body))]
                     [else
                      (loop (cdr ds) (cdr args)
                            (cons (ct-directive->code d (car args)) body))])))))])))

  ;; --- Runtime format string parser (same logic, runtime phase) ---

  (define (parse-format-string str)
    (let ([len (string-length str)])
      (let loop ([i 0] [acc '()] [lit-start 0])
        (cond
          [(>= i len)
           (reverse
             (if (< lit-start len)
                 (cons (cons 'literal (substring str lit-start len)) acc)
                 acc))]
          [(char=? (string-ref str i) #\~)
           (let ([acc (if (< lit-start i)
                          (cons (cons 'literal (substring str lit-start i)) acc)
                          acc)]
                 [j (+ i 1)])
             (when (>= j len)
               (error 'parse-format-string "incomplete directive at end" str))
             (if (char-numeric? (string-ref str j))
                 (let digit-loop ([k j] [digits '()])
                   (cond
                     [(>= k len)
                      (error 'parse-format-string "incomplete width directive" str)]
                     [(char-numeric? (string-ref str k))
                      (digit-loop (+ k 1) (cons (string-ref str k) digits))]
                     [(char=? (string-ref str k) #\w)
                      (let ([width (string->number (list->string (reverse digits)))])
                        (loop (+ k 1)
                              (cons (cons 'width width) acc)
                              (+ k 1)))]
                     [else
                      (error 'parse-format-string
                             "expected 'w' after width digits" str)]))
                 (let ([ch (string-ref str j)])
                   (case ch
                     [(#\a) (loop (+ j 1) (cons '(display) acc) (+ j 1))]
                     [(#\s) (loop (+ j 1) (cons '(write) acc) (+ j 1))]
                     [(#\d) (loop (+ j 1) (cons '(decimal) acc) (+ j 1))]
                     [(#\b) (loop (+ j 1) (cons '(binary) acc) (+ j 1))]
                     [(#\o) (loop (+ j 1) (cons '(octal) acc) (+ j 1))]
                     [(#\x) (loop (+ j 1) (cons '(hex) acc) (+ j 1))]
                     [(#\%) (loop (+ j 1) (cons '(newline) acc) (+ j 1))]
                     [(#\~) (loop (+ j 1) (cons '(tilde) acc) (+ j 1))]
                     [else
                      (error 'parse-format-string
                             "unknown directive" str ch)]))))]
          [else
           (loop (+ i 1) acc lit-start)]))))

  ;; --- Runtime formatting ---

  ;; Write formatted output to a port
  (define (fmt/port port fmt-str . args)
    (let ([directives (parse-format-string fmt-str)]
          [remaining args])
      (for-each
        (lambda (d)
          (case (car d)
            [(literal)  (display (cdr d) port)]
            [(display)
             (when (null? remaining)
               (error 'fmt/port "not enough arguments for ~a" fmt-str))
             (display (car remaining) port)
             (set! remaining (cdr remaining))]
            [(write)
             (when (null? remaining)
               (error 'fmt/port "not enough arguments for ~s" fmt-str))
             (write (car remaining) port)
             (set! remaining (cdr remaining))]
            [(decimal)
             (when (null? remaining)
               (error 'fmt/port "not enough arguments for ~d" fmt-str))
             (display (number->string (car remaining) 10) port)
             (set! remaining (cdr remaining))]
            [(binary)
             (when (null? remaining)
               (error 'fmt/port "not enough arguments for ~b" fmt-str))
             (display (number->string (car remaining) 2) port)
             (set! remaining (cdr remaining))]
            [(octal)
             (when (null? remaining)
               (error 'fmt/port "not enough arguments for ~o" fmt-str))
             (display (number->string (car remaining) 8) port)
             (set! remaining (cdr remaining))]
            [(hex)
             (when (null? remaining)
               (error 'fmt/port "not enough arguments for ~x" fmt-str))
             (display (string-downcase (number->string (car remaining) 16)) port)
             (set! remaining (cdr remaining))]
            [(newline) (newline port)]
            [(tilde)   (display "~" port)]
            [(width)
             (when (null? remaining)
               (error 'fmt/port "not enough arguments for ~w" fmt-str))
             (display (pad-right (format "~a" (car remaining)) (cdr d)) port)
             (set! remaining (cdr remaining))]
            [else (error 'fmt/port "unknown directive" d)]))
        directives)))

  ;; Return formatted string
  (define (fmt fmt-str . args)
    (let ([p (open-output-string)])
      (apply fmt/port p fmt-str args)
      (get-output-string p)))

) ;; end library
