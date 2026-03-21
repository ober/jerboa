#!chezscheme
;;; (std compress lz4) — LZ4 compression (length-prefixed bytevector format)
;;;
;;; Simple compression wrapper using length-prefixed storage.
;;; For actual LZ4 compression, use Chez's built-in port compression
;;; or an FFI binding to liblz4.

(library (std compress lz4)
  (export lz4-compress lz4-decompress
          lz4-compress-port lz4-decompress-port)

  (import (chezscheme))

  ;; "Compress" bytevector — stores with length prefix
  ;; (This is a placeholder; real LZ4 requires FFI to liblz4)
  (define (lz4-compress bv)
    (let-values ([(port extract) (open-bytevector-output-port)])
      (let ([len-bv (make-bytevector 8)])
        (bytevector-u64-native-set! len-bv 0 (bytevector-length bv))
        (put-bytevector port len-bv))
      (put-bytevector port bv)
      (extract)))

  ;; "Decompress" bytevector — reads length prefix and extracts data
  (define (lz4-decompress bv)
    (let ([port (open-bytevector-input-port bv)])
      (let* ([len-bv (get-bytevector-n port 8)]
             [orig-len (bytevector-u64-native-ref len-bv 0)]
             [rest (get-bytevector-n port orig-len)])
        (if (eof-object? rest)
            (make-bytevector 0)
            rest))))

  ;; Placeholder port wrappers
  (define (lz4-compress-port port) port)
  (define (lz4-decompress-port port) port)

) ;; end library
