#!chezscheme
;;; (std debug pp) — Pretty printer
;;;
;;; Expose Chez's pretty printer with Gerbil-compatible API.

(library (std debug pp)
  (export pp pp-to-string pprint
          pretty-print-columns)

  (import (chezscheme))

  ;; pp: pretty-print to current output or specified port
  (define pp
    (case-lambda
      [(obj) (pretty-print obj)]
      [(obj port) (pretty-print obj port)]))

  ;; pp-to-string: pretty-print to string
  (define (pp-to-string obj)
    (let ([port (open-output-string)])
      (pretty-print obj port)
      (get-output-string port)))

  ;; pprint: Gerbil-style alias
  (define pprint pp)

  ;; pretty-print-columns: re-export Chez parameter
  ;; (pretty-line-length) gets/sets the print width
  ;; We alias for Gerbil compatibility
  (define pretty-print-columns pretty-line-length)

) ;; end library
