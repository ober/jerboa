#!chezscheme
;;; (std compress native-rust) — Compression backed by Rust flate2
;;;
;;; Drop-in replacement for (std compress zlib) chez-zlib bindings.
;;; Built-in decompression bomb protection via output size cap.

(library (std compress native-rust)
  (export
    rust-deflate rust-inflate
    rust-gzip rust-gunzip
    *rust-max-decompressed-size*)

  (import (chezscheme))

  (define _native-loaded
    (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
        (error 'std/compress/native-rust "libjerboa_native.so not found")))

  (define *rust-max-decompressed-size* (make-parameter (* 100 1024 1024)))  ;; 100MB

  (define (bv-sub bv start len)
    (let ([out (make-bytevector len)])
      (bytevector-copy! bv start out 0 len)
      out))

  ;; --- Deflate/Inflate ---

  (define c-jerboa-deflate
    (foreign-procedure "jerboa_deflate" (u8* size_t u8* size_t u8*) int))

  (define c-jerboa-inflate
    (foreign-procedure "jerboa_inflate" (u8* size_t u8* size_t u8*) int))

  (define c-jerboa-gzip
    (foreign-procedure "jerboa_gzip" (u8* size_t u8* size_t u8*) int))

  (define c-jerboa-gunzip
    (foreign-procedure "jerboa_gunzip" (u8* size_t u8* size_t u8*) int))

  (define c-jerboa-last-error
    (foreign-procedure "jerboa_last_error" (u8* size_t) size_t))

  (define (get-last-error)
    (let ([buf (make-bytevector 512)])
      (let ([len (c-jerboa-last-error buf 512)])
        (if (> len 0)
          (utf8->string (bv-sub buf 0 (min len 511)))
          "unknown error"))))

  (define (compress-op c-func name input output-max)
    (let ([out (make-bytevector output-max)]
          [len-buf (make-bytevector 8)])
      (let ([rc (c-func input (bytevector-length input) out output-max len-buf)])
        (when (< rc 0)
          (error name (get-last-error)))
        (let ([actual-len (bytevector-u64-native-ref len-buf 0)])
          (if (= actual-len output-max)
            out
            (bv-sub out 0 actual-len))))))

  (define (rust-deflate bv)
    ;; Compressed output should be no larger than input + some overhead
    (compress-op c-jerboa-deflate 'rust-deflate bv
                 (+ (bytevector-length bv) 64)))

  (define (rust-inflate bv)
    (compress-op c-jerboa-inflate 'rust-inflate bv
                 (*rust-max-decompressed-size*)))

  (define (rust-gzip bv)
    (compress-op c-jerboa-gzip 'rust-gzip bv
                 (+ (bytevector-length bv) 64)))

  (define (rust-gunzip bv)
    (compress-op c-jerboa-gunzip 'rust-gunzip bv
                 (*rust-max-decompressed-size*)))

  ) ;; end library
