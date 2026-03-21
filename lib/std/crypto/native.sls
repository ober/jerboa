#!chezscheme
;;; (std crypto native) — Direct FFI bindings to OpenSSL libcrypto
;;;
;;; Replaces shell-based crypto with direct C library calls.
;;; Zero temp files, zero shell invocation, zero race conditions.

(library (std crypto native)
  (export
    ;; Digest
    native-md5 native-sha1 native-sha256 native-sha384 native-sha512
    native-digest

    ;; CSPRNG
    native-random-bytes
    native-random-bytes!

    ;; HMAC
    native-hmac-sha256

    ;; Timing-safe comparison
    native-crypto-memcmp)

  (import (chezscheme))

  ;; Load libcrypto
  (define _libcrypto-loaded
    (guard (e [#t #f])
      (load-shared-object "libcrypto.so")
      #t))

  (define _libcrypto-loaded-alt
    (if _libcrypto-loaded #t
      (guard (e [#t #f])
        (load-shared-object "libcrypto.so.3")
        #t)))

  (define libcrypto-available?
    (or _libcrypto-loaded _libcrypto-loaded-alt))

  ;; ========== EVP Digest Functions ==========

  (define c-EVP_MD_CTX_new
    (if libcrypto-available?
      (foreign-procedure "EVP_MD_CTX_new" () uptr)
      (lambda () 0)))

  (define c-EVP_MD_CTX_free
    (if libcrypto-available?
      (foreign-procedure "EVP_MD_CTX_free" (uptr) void)
      (lambda (ctx) (void))))

  (define c-EVP_DigestInit_ex
    (if libcrypto-available?
      (foreign-procedure "EVP_DigestInit_ex" (uptr uptr uptr) int)
      (lambda (ctx md impl) 0)))

  (define c-EVP_DigestUpdate
    (if libcrypto-available?
      (foreign-procedure "EVP_DigestUpdate" (uptr u8* int) int)
      (lambda (ctx data len) 0)))

  (define c-EVP_DigestFinal_ex
    (if libcrypto-available?
      (foreign-procedure "EVP_DigestFinal_ex" (uptr u8* u8*) int)
      (lambda (ctx md s) 0)))

  (define c-EVP_md5
    (if libcrypto-available?
      (foreign-procedure "EVP_md5" () uptr)
      (lambda () 0)))

  (define c-EVP_sha1
    (if libcrypto-available?
      (foreign-procedure "EVP_sha1" () uptr)
      (lambda () 0)))

  (define c-EVP_sha256
    (if libcrypto-available?
      (foreign-procedure "EVP_sha256" () uptr)
      (lambda () 0)))

  (define c-EVP_sha384
    (if libcrypto-available?
      (foreign-procedure "EVP_sha384" () uptr)
      (lambda () 0)))

  (define c-EVP_sha512
    (if libcrypto-available?
      (foreign-procedure "EVP_sha512" () uptr)
      (lambda () 0)))

  ;; ========== RAND Functions ==========

  (define c-RAND_bytes
    (if libcrypto-available?
      (foreign-procedure "RAND_bytes" (u8* int) int)
      (lambda (buf n) 0)))

  ;; ========== HMAC Function ==========

  (define c-HMAC
    (if libcrypto-available?
      (foreign-procedure "HMAC" (uptr u8* int u8* int u8* u8*) uptr)
      (lambda args 0)))

  ;; ========== CRYPTO_memcmp ==========

  (define c-CRYPTO_memcmp
    (if libcrypto-available?
      (foreign-procedure "CRYPTO_memcmp" (u8* u8* int) int)
      (lambda (a b n) -1)))

  ;; ========== High-Level API ==========

  (define (ensure-libcrypto! who)
    (unless libcrypto-available?
      (error who "libcrypto not available — install OpenSSL")))

  (define (evp-digest md-func digest-size data)
    (ensure-libcrypto! 'native-digest)
    (let ([input (if (bytevector? data) data (string->utf8 data))]
          [md-buf (make-bytevector digest-size)]
          [len-buf (make-bytevector 4 0)]
          [ctx (c-EVP_MD_CTX_new)])
      (when (= ctx 0)
        (error 'native-digest "EVP_MD_CTX_new failed"))
      (dynamic-wind
        (lambda () (void))
        (lambda ()
          (let ([r1 (c-EVP_DigestInit_ex ctx (md-func) 0)])
            (when (= r1 0)
              (error 'native-digest "EVP_DigestInit_ex failed"))
            (let ([r2 (c-EVP_DigestUpdate ctx input (bytevector-length input))])
              (when (= r2 0)
                (error 'native-digest "EVP_DigestUpdate failed"))
              (let ([r3 (c-EVP_DigestFinal_ex ctx md-buf len-buf)])
                (when (= r3 0)
                  (error 'native-digest "EVP_DigestFinal_ex failed"))
                md-buf))))
        (lambda ()
          (c-EVP_MD_CTX_free ctx)))))

  (define (bytevector->hex-string bv)
    (let* ([len (bytevector-length bv)]
           [out (make-string (* len 2))])
      (do ([i 0 (+ i 1)])
          ((= i len) out)
        (let* ([b (bytevector-u8-ref bv i)]
               [hi (bitwise-arithmetic-shift-right b 4)]
               [lo (bitwise-and b #xf)])
          (string-set! out (* i 2) (hex-digit hi))
          (string-set! out (+ (* i 2) 1) (hex-digit lo))))))

  (define (hex-digit n)
    (string-ref "0123456789abcdef" n))

  ;; Public digest API — returns hex string
  (define (native-md5 data)
    (bytevector->hex-string (native-digest 'md5 data)))
  (define (native-sha1 data)
    (bytevector->hex-string (native-digest 'sha1 data)))
  (define (native-sha256 data)
    (bytevector->hex-string (native-digest 'sha256 data)))
  (define (native-sha384 data)
    (bytevector->hex-string (native-digest 'sha384 data)))
  (define (native-sha512 data)
    (bytevector->hex-string (native-digest 'sha512 data)))

  (define (native-digest algo data)
    ;; Returns raw bytevector digest.
    (case algo
      [(md5)    (evp-digest c-EVP_md5 16 data)]
      [(sha1)   (evp-digest c-EVP_sha1 20 data)]
      [(sha256) (evp-digest c-EVP_sha256 32 data)]
      [(sha384) (evp-digest c-EVP_sha384 48 data)]
      [(sha512) (evp-digest c-EVP_sha512 64 data)]
      [else (error 'native-digest "unknown algorithm" algo)]))

  ;; CSPRNG
  (define (native-random-bytes n)
    (ensure-libcrypto! 'native-random-bytes)
    (let ([bv (make-bytevector n)])
      (when (> n 0)
        (let ([r (c-RAND_bytes bv n)])
          (when (not (= r 1))
            (error 'native-random-bytes "RAND_bytes failed"))))
      bv))

  (define (native-random-bytes! bv)
    (ensure-libcrypto! 'native-random-bytes!)
    (let ([n (bytevector-length bv)])
      (when (> n 0)
        (let ([r (c-RAND_bytes bv n)])
          (when (not (= r 1))
            (error 'native-random-bytes! "RAND_bytes failed"))))))

  ;; HMAC-SHA256
  (define (native-hmac-sha256 key data)
    ;; key and data are bytevectors. Returns 32-byte bytevector.
    (ensure-libcrypto! 'native-hmac-sha256)
    (let ([key-bv (if (string? key) (string->utf8 key) key)]
          [data-bv (if (string? data) (string->utf8 data) data)]
          [out (make-bytevector 32)]
          [len-buf (make-bytevector 4 0)])
      (let ([r (c-HMAC (c-EVP_sha256)
                  key-bv (bytevector-length key-bv)
                  data-bv (bytevector-length data-bv)
                  out len-buf)])
        (when (= r 0)
          (error 'native-hmac-sha256 "HMAC failed"))
        out)))

  ;; Timing-safe comparison
  (define (native-crypto-memcmp a b)
    ;; Compare two bytevectors in constant time. Returns #t if equal.
    (ensure-libcrypto! 'native-crypto-memcmp)
    (let ([a-bv (if (string? a) (string->utf8 a) a)]
          [b-bv (if (string? b) (string->utf8 b) b)])
      (if (not (= (bytevector-length a-bv) (bytevector-length b-bv)))
        #f
        (= 0 (c-CRYPTO_memcmp a-bv b-bv (bytevector-length a-bv))))))

  ) ;; end library
