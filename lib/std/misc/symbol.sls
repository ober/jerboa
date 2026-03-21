#!chezscheme
;;; (std misc symbol) — Symbol manipulation utilities
;;;
;;; (symbol-append 'make- 'point) => make-point
;;; (interned-symbol? (gensym)) => #f

(library (std misc symbol)
  (export symbol-append make-symbol symbol->keyword keyword->symbol
          interned-symbol?)

  (import (chezscheme))

  ;; Concatenate symbols: (symbol-append 'foo 'bar) => foobar
  ;; Also accepts strings and numbers.
  (define (symbol-append . parts)
    (string->symbol
     (apply string-append
            (map (lambda (p)
                   (cond
                     [(symbol? p) (symbol->string p)]
                     [(string? p) p]
                     [(number? p) (number->string p)]
                     [else (format "~a" p)]))
                 parts))))

  ;; Alias for symbol-append
  (define make-symbol symbol-append)

  ;; Convert symbol to keyword: 'foo => foo:
  (define (symbol->keyword sym)
    (string->symbol
     (string-append (symbol->string sym) ":")))

  ;; Convert keyword to symbol: foo: => 'foo
  (define (keyword->symbol kw)
    (let ([s (symbol->string kw)])
      (if (and (> (string-length s) 1)
               (char=? (string-ref s (- (string-length s) 1)) #\:))
          (string->symbol (substring s 0 (- (string-length s) 1)))
          kw)))

  ;; Check if symbol is interned (not a gensym)
  (define (interned-symbol? sym)
    (and (symbol? sym)
         (not (gensym? sym))))

) ;; end library
