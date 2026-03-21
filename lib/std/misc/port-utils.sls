#!chezscheme
;;; (std misc port-utils) — Port convenience functions
;;;
;;; Utilities for reading/writing with string and bytevector ports.

(library (std misc port-utils)
  (export read-all-as-string read-all-as-bytes
          call-with-input-string call-with-output-string
          ;; Re-exports from Chez
          with-output-to-string with-input-from-string)

  (import (chezscheme))

  ;; Read entire textual port to string
  (define read-all-as-string
    (case-lambda
      [() (read-all-as-string (current-input-port))]
      [(port)
       (let loop ([acc '()])
         (let ([ch (read-char port)])
           (if (eof-object? ch)
               (list->string (reverse acc))
               (loop (cons ch acc)))))]))

  ;; Read entire binary port to bytevector
  (define read-all-as-bytes
    (case-lambda
      [() (read-all-as-bytes (current-input-port))]
      [(port)
       (let loop ([chunks '()] [total 0])
         (let ([buf (get-bytevector-some port)])
           (if (eof-object? buf)
               (let ([result (make-bytevector total)])
                 (let fill ([rest (reverse chunks)] [pos 0])
                   (if (null? rest) result
                       (let ([bv (car rest)])
                         (bytevector-copy! bv 0 result pos (bytevector-length bv))
                         (fill (cdr rest) (+ pos (bytevector-length bv)))))))
               (loop (cons buf chunks)
                     (+ total (bytevector-length buf))))))]))

  ;; Open string input port, call proc, return result
  (define (call-with-input-string str proc)
    (let ([port (open-input-string str)])
      (proc port)))

  ;; Open string output port, call proc, return output string
  (define (call-with-output-string proc)
    (let ([port (open-output-string)])
      (proc port)
      (get-output-string port)))

  ;; with-output-to-string and with-input-from-string are Chez built-ins

) ;; end library
