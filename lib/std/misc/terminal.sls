#!chezscheme
;;; (std misc terminal) — ANSI terminal control
;;;
;;; Cursor, screen, text styling, colors, raw mode, and alternate screen.
;;; All escape sequences are written to current-output-port.
;;;
;;; (cursor-up 3)           ; move cursor up 3 lines
;;; (bold "hello")          ; => "\e[1mhello\e[0m"
;;; (fg-color 'red "text")  ; => "\e[31mtext\e[0m"
;;; (with-raw-mode (lambda () ...))

(library (std misc terminal)
  (export
    ;; Cursor control
    cursor-up cursor-down cursor-forward cursor-back
    cursor-position cursor-save cursor-restore
    cursor-hide cursor-show

    ;; Screen control
    clear-screen clear-line clear-to-end clear-to-beginning

    ;; Text styling
    bold dim italic underline blink reverse-video reset-style

    ;; Colors
    fg-color bg-color

    ;; Terminal dimensions
    terminal-width terminal-height

    ;; Raw mode
    with-raw-mode

    ;; Alternate screen
    with-alternate-screen)

  (import (chezscheme))

  ;; ========== Escape sequence helpers ==========

  (define esc "\x1b;")

  (define (csi . parts)
    (apply string-append esc "[" parts))

  (define (emit . strings)
    (for-each (lambda (s) (display s (current-output-port))) strings)
    (flush-output-port (current-output-port)))

  ;; ========== Cursor control ==========

  (define cursor-up
    (case-lambda
      [() (emit (csi "1" "A"))]
      [(n) (emit (csi (number->string n) "A"))]))

  (define cursor-down
    (case-lambda
      [() (emit (csi "1" "B"))]
      [(n) (emit (csi (number->string n) "B"))]))

  (define cursor-forward
    (case-lambda
      [() (emit (csi "1" "C"))]
      [(n) (emit (csi (number->string n) "C"))]))

  (define cursor-back
    (case-lambda
      [() (emit (csi "1" "D"))]
      [(n) (emit (csi (number->string n) "D"))]))

  (define (cursor-position row col)
    (emit (csi (number->string row) ";" (number->string col) "H")))

  (define (cursor-save)
    (emit (csi "s")))

  (define (cursor-restore)
    (emit (csi "u")))

  (define (cursor-hide)
    (emit (csi "?" "25" "l")))

  (define (cursor-show)
    (emit (csi "?" "25" "h")))

  ;; ========== Screen control ==========

  (define (clear-screen)
    (emit (csi "2" "J")))

  (define (clear-line)
    (emit (csi "2" "K")))

  (define (clear-to-end)
    (emit (csi "0" "K")))

  (define (clear-to-beginning)
    (emit (csi "1" "K")))

  ;; ========== Text styling ==========
  ;;
  ;; Each styling function can be called two ways:
  ;;   (bold)          => emits the SGR code (turn on bold)
  ;;   (bold "text")   => returns styled string with reset appended

  (define (sgr-code n)
    (csi (number->string n) "m"))

  (define (make-style-fn code)
    (case-lambda
      [() (emit (sgr-code code))]
      [(text)
       (string-append (sgr-code code) text (sgr-code 0))]))

  (define bold         (make-style-fn 1))
  (define dim          (make-style-fn 2))
  (define italic       (make-style-fn 3))
  (define underline    (make-style-fn 4))
  (define blink        (make-style-fn 5))
  (define reverse-video (make-style-fn 7))

  (define (reset-style)
    (emit (sgr-code 0)))

  ;; ========== Colors ==========
  ;;
  ;; Named colors: black red green yellow blue magenta cyan white
  ;; 256-color: pass an integer 0-255
  ;;
  ;; (fg-color 'red)           => emits foreground red
  ;; (fg-color 'red "text")    => returns string with fg red + text + reset
  ;; (fg-color 196)            => emits 256-color foreground
  ;; (fg-color 196 "text")     => returns string with 256-color + text + reset

  (define color-table
    '((black   . 0)
      (red     . 1)
      (green   . 2)
      (yellow  . 3)
      (blue    . 4)
      (magenta . 5)
      (cyan    . 6)
      (white   . 7)))

  (define (color-name->code name)
    (let ([pair (assq name color-table)])
      (if pair
        (cdr pair)
        (error 'color "unknown color name" name))))

  (define (fg-escape color)
    (cond
      [(symbol? color)
       (sgr-code (+ 30 (color-name->code color)))]
      [(and (integer? color) (<= 0 color 255))
       (csi "38;5;" (number->string color) "m")]
      [else (error 'fg-color "expected color name or 0-255" color)]))

  (define (bg-escape color)
    (cond
      [(symbol? color)
       (sgr-code (+ 40 (color-name->code color)))]
      [(and (integer? color) (<= 0 color 255))
       (csi "48;5;" (number->string color) "m")]
      [else (error 'bg-color "expected color name or 0-255" color)]))

  (define fg-color
    (case-lambda
      [(color) (emit (fg-escape color))]
      [(color text)
       (string-append (fg-escape color) text (sgr-code 0))]))

  (define bg-color
    (case-lambda
      [(color) (emit (bg-escape color))]
      [(color text)
       (string-append (bg-escape color) text (sgr-code 0))]))

  ;; ========== Terminal dimensions ==========

  (define (read-all port)
    (let lp ((chunks '()))
      (let ((buf (get-string-n port 4096)))
        (if (eof-object? buf)
          (if (null? chunks)
            ""
            (apply string-append (reverse chunks)))
          (lp (cons buf chunks))))))

  (define (string-trim s)
    ;; Trim leading and trailing whitespace
    (let* ([len (string-length s)]
           [start (let lp ([i 0])
                    (if (and (< i len) (char-whitespace? (string-ref s i)))
                      (lp (+ i 1))
                      i))]
           [end (let lp ([i len])
                  (if (and (> i start) (char-whitespace? (string-ref s (- i 1))))
                    (lp (- i 1))
                    i))])
      (substring s start end)))

  (define (stty-size)
    ;; Returns (values rows cols) from `stty size`, or #f #f on failure.
    (guard (exn [#t (values #f #f)])
      (let-values ([(to-stdin from-stdout from-stderr pid)
                    (open-process-ports "stty size </dev/tty 2>/dev/null"
                                        'line (native-transcoder))])
        (close-port to-stdin)
        (let* ([output (string-trim (read-all from-stdout))]
               [_ (close-port from-stdout)]
               [_ (close-port from-stderr)])
          (if (= (string-length output) 0)
            (values #f #f)
            (let ([parts (string-split output #\space)])
              (if (>= (length parts) 2)
                (values (string->number (car parts))
                        (string->number (cadr parts)))
                (values #f #f))))))))

  (define (string-split s ch)
    ;; Split string s on character ch, skipping empty parts
    (let ([len (string-length s)])
      (let lp ([i 0] [start 0] [acc '()])
        (cond
          [(= i len)
           (reverse (if (> i start)
                      (cons (substring s start i) acc)
                      acc))]
          [(char=? (string-ref s i) ch)
           (lp (+ i 1) (+ i 1)
               (if (> i start)
                 (cons (substring s start i) acc)
                 acc))]
          [else (lp (+ i 1) start acc)]))))

  (define (terminal-width)
    (or (let ([v (getenv "COLUMNS")])
          (and v (string->number v)))
        (let-values ([(rows cols) (stty-size)])
          (or cols 80))))

  (define (terminal-height)
    (or (let ([v (getenv "LINES")])
          (and v (string->number v)))
        (let-values ([(rows cols) (stty-size)])
          (or rows 24))))

  ;; ========== Raw mode ==========

  (define (with-raw-mode thunk)
    ;; Save terminal settings, switch to raw mode, run thunk, restore.
    ;; Uses stty since we don't want to depend on FFI/ioctl.
    (let ([saved #f])
      (dynamic-wind
        (lambda ()
          ;; Save current terminal settings
          (guard (exn [#t (void)])
            (let-values ([(to from err pid)
                          (open-process-ports "stty -g </dev/tty"
                                              'line (native-transcoder))])
              (close-port to)
              (set! saved (string-trim (read-all from)))
              (close-port from)
              (close-port err)))
          ;; Switch to raw mode
          (guard (exn [#t (void)])
            (system "stty raw -echo </dev/tty 2>/dev/null")))
        thunk
        (lambda ()
          ;; Restore saved settings
          (when (and saved (> (string-length saved) 0))
            (guard (exn [#t (void)])
              (system (string-append "stty " saved " </dev/tty 2>/dev/null"))))))))

  ;; ========== Alternate screen ==========

  (define (with-alternate-screen thunk)
    ;; Switch to alternate screen buffer, run thunk, switch back.
    (dynamic-wind
      (lambda ()
        (emit (csi "?" "1049" "h")))
      thunk
      (lambda ()
        (emit (csi "?" "1049" "l")))))

) ;; end library
