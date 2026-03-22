#!chezscheme
;;; :std/sort -- Gerbil-compatible sort API

(library (std sort)
  (export sort sort! stable-sort stable-sort!)
  (import (except (chezscheme) sort sort!))

  (define (sort lst less?)
    (list-sort less? lst))

  ;; NOTE: sort! returns a new sorted list — it does NOT mutate the input.
  ;; R6RS list-sort is not guaranteed to be destructive. Always use the
  ;; return value: (set! lst (sort! lst <)) or (let ([sorted (sort! lst <)]) ...)
  (define (sort! lst less?)
    (list-sort less? lst))

  (define stable-sort sort)
  (define stable-sort! sort!)

  ) ;; end library
