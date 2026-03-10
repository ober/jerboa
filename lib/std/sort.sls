#!chezscheme
;;; :std/sort -- Gerbil-compatible sort API

(library (std sort)
  (export sort sort! stable-sort stable-sort!)
  (import (except (chezscheme) sort sort!))

  (define (sort lst less?)
    (list-sort less? lst))

  (define (sort! lst less?)
    (list-sort less? lst))

  (define stable-sort sort)
  (define stable-sort! sort!)

  ) ;; end library
