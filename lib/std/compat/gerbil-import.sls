#!chezscheme
;;; :std/compat/gerbil-import -- Gerbil→Chez import/export translation
;;;
;;; Translates Gerbil import specs (:std/foo → (std foo)) and
;;; provides (export-all) for Gerbil's (export #t) pattern.
;;;
;;; This module assists mechanical porting from Gerbil to jerboa.

(library (std compat gerbil-import)
  (export
    gerbil-import
    export-all)

  (import (chezscheme))

  ;; Helper: split string by character at compile time
  (meta define (meta-string-split str ch)
    (let ([len (string-length str)])
      (let loop ([i 0] [start 0] [acc '()])
        (cond
          [(>= i len)
           (reverse (cons (substring str start len) acc))]
          [(char=? (string-ref str i) ch)
           (loop (+ i 1) (+ i 1) (cons (substring str start i) acc))]
          [else (loop (+ i 1) start acc)]))))

  ;; Translate a Gerbil import spec symbol to R6RS library reference
  ;; :std/foo/bar → (std foo bar)
  ;; :gerbil/core → (gerbil core)
  (meta define (translate-gerbil-import spec)
    (if (symbol? spec)
      (let* ([s (symbol->string spec)]
             [len (string-length s)])
        (if (and (> len 0) (char=? (string-ref s 0) #\:))
          (let* ([without-colon (substring s 1 len)]
                 [parts (meta-string-split without-colon #\/)])
            (map string->symbol parts))
          (list spec)))
      spec))

  ;; gerbil-import: translate Gerbil-style import specs to R6RS
  ;; Usage: (gerbil-import :std/sugar :std/iter :myapp/core)
  ;; Expands to: (import (std sugar) (std iter) (myapp core))
  (define-syntax gerbil-import
    (lambda (stx)
      (syntax-case stx ()
        [(k specs ...)
         (let ([translated (map (lambda (s)
                                  (datum->syntax #'k
                                    (translate-gerbil-import (syntax->datum s))))
                                (syntax->list #'(specs ...)))])
           (with-syntax ([(lib ...) translated])
             #'(import lib ...)))])))

  ;; export-all: Gerbil's (export #t) — re-export everything.
  ;; In R6RS libraries this is not possible programmatically.
  ;; This is a no-op placeholder; users should list exports explicitly.
  ;; For top-level programs, all definitions are already visible.
  (define-syntax export-all
    (syntax-rules ()
      [(_) (void)]))

  ) ;; end library
