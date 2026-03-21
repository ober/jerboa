#!chezscheme
;;; :std/format -- Gerbil-compatible format

(library (std format)
  (export format printf fprintf eprintf
          safe-printf safe-fprintf safe-eprintf)
  (import (except (chezscheme) printf fprintf))

  ;; format is already in Chez, re-export it
  ;; printf: format to stdout
  (define (printf fmt . args)
    (display (apply format fmt args)))

  ;; fprintf: format to port
  (define (fprintf port fmt . args)
    (display (apply format fmt args) port))

  ;; eprintf: format to stderr
  (define (eprintf fmt . args)
    (display (apply format fmt args) (current-error-port)))

  ;; Safe variants: treat message as literal text (no format directives)
  ;; Use these when the format string may contain user-controlled data.
  (define (safe-printf msg . args)
    (display msg)
    (for-each display args))

  (define (safe-fprintf port msg . args)
    (display msg port)
    (for-each (lambda (a) (display a port)) args))

  (define (safe-eprintf msg . args)
    (display msg (current-error-port))
    (for-each (lambda (a) (display a (current-error-port))) args))

  ) ;; end library
