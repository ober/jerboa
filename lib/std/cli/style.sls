#!chezscheme
;;; style.sls -- ANSI terminal styling
;;; Provides color and style functions for terminal output.

(library (std cli style)
  (export
    ;; Colors
    red green blue yellow cyan magenta white black
    ;; Styles
    bold dim italic underline
    ;; Compound
    styled
    ;; Control
    color-enabled? disable-colors! enable-colors!
    ;; Helpers
    success-prefix error-prefix warning-prefix info-prefix)

  (import (chezscheme))

  ;; --- Color control ---

  (define (stdout-is-tty?)
    (guard (exn (#t #f))
      (load-shared-object #f)
      (let ((isatty (foreign-procedure "isatty" (int) boolean)))
        (isatty 1))))  ; fd 1 = stdout

  (define *colors-enabled*
    (make-parameter (stdout-is-tty?)))

  (define (color-enabled?) (*colors-enabled*))
  (define (disable-colors!) (*colors-enabled* #f))
  (define (enable-colors!) (*colors-enabled* #t))

  ;; --- ANSI escape code wrapping ---

  (define (ansi-wrap code text)
    (if (*colors-enabled*)
      (string-append "\x1b;[" code "m" text "\x1b;[0m")
      text))

  ;; --- Color functions ---

  (define (black text)   (ansi-wrap "30" text))
  (define (red text)     (ansi-wrap "31" text))
  (define (green text)   (ansi-wrap "32" text))
  (define (yellow text)  (ansi-wrap "33" text))
  (define (blue text)    (ansi-wrap "34" text))
  (define (magenta text) (ansi-wrap "35" text))
  (define (cyan text)    (ansi-wrap "36" text))
  (define (white text)   (ansi-wrap "37" text))

  ;; --- Style functions ---

  (define (bold text)      (ansi-wrap "1" text))
  (define (dim text)       (ansi-wrap "2" text))
  (define (italic text)    (ansi-wrap "3" text))
  (define (underline text) (ansi-wrap "4" text))

  ;; --- Compound styling ---

  (define (styled styles text)
    ;; styles is a list of style symbols: (styled '(bold red) "text")
    (let ((style-map `((bold . ,bold) (dim . ,dim) (italic . ,italic) (underline . ,underline)
                       (red . ,red) (green . ,green) (blue . ,blue) (yellow . ,yellow)
                       (cyan . ,cyan) (magenta . ,magenta) (white . ,white) (black . ,black))))
      (fold-left
        (lambda (txt sym)
          (let ((entry (assq sym style-map)))
            (if entry ((cdr entry) txt) txt)))
        text
        styles)))

  ;; --- Prefix helpers ---

  (define (success-prefix) (styled '(bold green) "[OK]"))
  (define (error-prefix)   (styled '(bold red) "[ERROR]"))
  (define (warning-prefix) (styled '(bold yellow) "[WARN]"))
  (define (info-prefix)    (styled '(bold cyan) "[INFO]"))

  ) ;; end library
