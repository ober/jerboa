#!chezscheme
;;; :std/compress/zlib -- Compression (wraps chez-zlib)
;;; Requires: chez_zlib_shim.so (zlib)

(library (std compress zlib)
  (export
    gzip-bytevector gunzip-bytevector
    deflate-bytevector inflate-bytevector
    gzip-data?
    safe-gunzip-bytevector safe-inflate-bytevector
    *zlib-max-decompressed-size*)

  (import (chezscheme) (chez-zlib))

  (define *zlib-max-decompressed-size* (make-parameter (* 100 1024 1024)))  ;; 100MB

  (define (safe-gunzip-bytevector bv)
    (let ((result (gunzip-bytevector bv)))
      (when (> (bytevector-length result) (*zlib-max-decompressed-size*))
        (error 'safe-gunzip-bytevector "decompressed size exceeds limit"
               (bytevector-length result) (*zlib-max-decompressed-size*)))
      result))

  (define (safe-inflate-bytevector bv)
    (let ((result (inflate-bytevector bv)))
      (when (> (bytevector-length result) (*zlib-max-decompressed-size*))
        (error 'safe-inflate-bytevector "decompressed size exceeds limit"
               (bytevector-length result) (*zlib-max-decompressed-size*)))
      result))

  ) ;; end library
