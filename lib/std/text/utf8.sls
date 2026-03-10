#!chezscheme
;;; :std/text/utf8 -- UTF-8 encoding/decoding utilities

(library (std text utf8)
  (export
    string->utf8
    utf8->string
    utf8-encode
    utf8-decode
    utf8-length)

  (import (chezscheme))

  ;; Chez already has string->utf8 and utf8->string as bytevector operations

  (define (utf8-encode str)
    (string->utf8 str))

  (define (utf8-decode bv . rest)
    (if (pair? rest)
      (let ((start (car rest))
            (end (if (pair? (cdr rest)) (cadr rest) (bytevector-length bv))))
        (utf8->string (bytevector-range bv start end)))
      (utf8->string bv)))

  (define (utf8-length str)
    (bytevector-length (string->utf8 str)))

  (define (bytevector-range bv start end)
    (let* ((len (- end start))
           (result (make-bytevector len)))
      (bytevector-copy! bv start result 0 len)
      result))

  ) ;; end library
