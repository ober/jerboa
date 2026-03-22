#!chezscheme
;;; :std/text/utf32 -- UTF-32 encoding/decoding

(library (std text utf32)
  (export
    string->utf32 utf32->string
    utf32le->string utf32be->string)

  (import
    (except (chezscheme) string->utf32 utf32->string))

  ;; Use Chez's native implementations under aliased names
  (define chez:string->utf32
    (let ()
      (import (only (chezscheme) string->utf32))
      string->utf32))

  (define chez:utf32->string
    (let ()
      (import (only (chezscheme) utf32->string))
      utf32->string))

  ;; Encode a string to a UTF-32 bytevector.
  ;; endianness: 'big (default) or 'little
  (define (string->utf32 str . rest)
    (let ((endian (if (pair? rest) (car rest) 'big)))
      (unless (memq endian '(big little))
        (error 'string->utf32 "endianness must be 'big or 'little" endian))
      (if (eq? endian 'big)
        (chez:string->utf32 str (endianness big))
        (chez:string->utf32 str (endianness little)))))

  ;; Decode UTF-32 bytevector to string.
  ;; Auto-detects endianness from BOM if present; defaults to big-endian.
  (define (utf32->string bv)
    ;; endianness-mandatory? = #f means BOM overrides the specified endianness
    (chez:utf32->string bv (endianness big) #f))

  (define (utf32be->string bv)
    ;; endianness-mandatory? = #t means always use big-endian
    (chez:utf32->string bv (endianness big) #t))

  (define (utf32le->string bv)
    ;; endianness-mandatory? = #t means always use little-endian
    (chez:utf32->string bv (endianness little) #t))

  ) ;; end library
