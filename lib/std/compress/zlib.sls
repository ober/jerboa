#!chezscheme
;;; :std/compress/zlib -- Compression (wraps chez-zlib)
;;; Requires: chez_zlib_shim.so (zlib)

(library (std compress zlib)
  (export
    gzip-bytevector gunzip-bytevector
    deflate-bytevector inflate-bytevector
    gzip-data?)

  (import (chez-zlib))

  ) ;; end library
