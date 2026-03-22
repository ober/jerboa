#!chezscheme
;;; :std/text/utf16 -- UTF-16 encoding/decoding

(library (std text utf16)
  (export
    string->utf16 utf16->string
    utf16-length utf16-bom?
    utf16le->string utf16be->string)

  (import
    (except (chezscheme) string->utf16 utf16->string))

  ;; Use Chez's native implementations under aliased names
  (define chez:string->utf16
    (let ()
      (import (only (chezscheme) string->utf16))
      string->utf16))

  (define chez:utf16->string
    (let ()
      (import (only (chezscheme) utf16->string))
      utf16->string))

  ;; Encode a string to a UTF-16 bytevector.
  ;; endianness: 'big (default) or 'little
  (define (string->utf16 str . rest)
    (let ((endian (if (pair? rest) (car rest) 'big)))
      (unless (memq endian '(big little))
        (error 'string->utf16 "endianness must be 'big or 'little" endian))
      (if (eq? endian 'big)
        (chez:string->utf16 str (endianness big))
        (chez:string->utf16 str (endianness little)))))

  ;; Return the number of UTF-16 code units needed for a string
  (define (utf16-length str)
    (let lp ((i 0) (count 0))
      (if (= i (string-length str))
        count
        (let ((cp (char->integer (string-ref str i))))
          (if (> cp #xFFFF)
            (lp (+ i 1) (+ count 2))  ; surrogate pair = 2 code units
            (lp (+ i 1) (+ count 1)))))))

  ;; Check if a bytevector starts with a UTF-16 BOM
  (define (utf16-bom? bv)
    (and (>= (bytevector-length bv) 2)
         (let ((b0 (bytevector-u8-ref bv 0))
               (b1 (bytevector-u8-ref bv 1)))
           (or (and (= b0 #xFE) (= b1 #xFF))    ; big-endian BOM
               (and (= b0 #xFF) (= b1 #xFE)))))) ; little-endian BOM

  ;; Decode UTF-16 bytevector to string.
  ;; Auto-detects endianness from BOM if present; defaults to big-endian.
  (define (utf16->string bv)
    ;; endianness-mandatory? = #f means BOM overrides the specified endianness
    (chez:utf16->string bv (endianness big) #f))

  (define (utf16be->string bv)
    ;; endianness-mandatory? = #t means always use big-endian, ignore BOM
    (chez:utf16->string bv (endianness big) #t))

  (define (utf16le->string bv)
    ;; endianness-mandatory? = #t means always use little-endian, ignore BOM
    (chez:utf16->string bv (endianness little) #t))

  ) ;; end library
