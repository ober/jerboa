#!chezscheme
;;; :std/format -- Gerbil-compatible format

(library (std format)
  (export format printf fprintf eprintf)
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

  ) ;; end library
