#!chezscheme
;;; (std crypto aead) — Authenticated Encryption with Associated Data
;;;
;;; AES-256-GCM via OpenSSL EVP_AEAD interface.
;;; Provides encrypt-then-authenticate in a single operation.

(library (std crypto aead)
  (export
    aead-encrypt
    aead-decrypt
    aead-key-generate)

  (import (chezscheme)
          (std crypto random))

  ;; Load libcrypto
  (define _loaded
    (or (guard (e [#t #f]) (load-shared-object "libcrypto.so") #t)
        (guard (e [#t #f]) (load-shared-object "libcrypto.so.3") #t)))

  ;; EVP cipher interface
  (define c-EVP_CIPHER_CTX_new
    (if _loaded (foreign-procedure "EVP_CIPHER_CTX_new" () uptr) (lambda () 0)))
  (define c-EVP_CIPHER_CTX_free
    (if _loaded (foreign-procedure "EVP_CIPHER_CTX_free" (uptr) void) (lambda (x) (void))))
  (define c-EVP_aes_256_gcm
    (if _loaded (foreign-procedure "EVP_aes_256_gcm" () uptr) (lambda () 0)))
  (define c-EVP_EncryptInit_ex
    (if _loaded (foreign-procedure "EVP_EncryptInit_ex" (uptr uptr uptr u8* u8*) int) (lambda args 0)))
  (define c-EVP_EncryptUpdate
    (if _loaded (foreign-procedure "EVP_EncryptUpdate" (uptr u8* u8* u8* int) int) (lambda args 0)))
  ;; Separate binding for AAD (NULL output buffer)
  (define c-EVP_EncryptUpdate_AAD
    (if _loaded (foreign-procedure "EVP_EncryptUpdate" (uptr uptr u8* u8* int) int) (lambda args 0)))
  (define c-EVP_EncryptFinal_ex
    (if _loaded (foreign-procedure "EVP_EncryptFinal_ex" (uptr u8* u8*) int) (lambda args 0)))
  (define c-EVP_CIPHER_CTX_ctrl
    (if _loaded (foreign-procedure "EVP_CIPHER_CTX_ctrl" (uptr int int u8*) int) (lambda args 0)))
  (define c-EVP_DecryptInit_ex
    (if _loaded (foreign-procedure "EVP_DecryptInit_ex" (uptr uptr uptr u8* u8*) int) (lambda args 0)))
  (define c-EVP_DecryptUpdate
    (if _loaded (foreign-procedure "EVP_DecryptUpdate" (uptr u8* u8* u8* int) int) (lambda args 0)))
  (define c-EVP_DecryptUpdate_AAD
    (if _loaded (foreign-procedure "EVP_DecryptUpdate" (uptr uptr u8* u8* int) int) (lambda args 0)))
  (define c-EVP_DecryptFinal_ex
    (if _loaded (foreign-procedure "EVP_DecryptFinal_ex" (uptr u8* u8*) int) (lambda args 0)))

  ;; EVP_CTRL constants
  (define EVP_CTRL_GCM_SET_IVLEN #x9)
  (define EVP_CTRL_GCM_GET_TAG #x10)
  (define EVP_CTRL_GCM_SET_TAG #x11)

  (define GCM_IV_LEN 12)
  (define GCM_TAG_LEN 16)
  (define AES_KEY_LEN 32)  ;; AES-256

  ;; ========== Public API ==========

  (define (aead-key-generate)
    ;; Generate a random 256-bit key for AES-256-GCM.
    (random-bytes AES_KEY_LEN))

  (define (aead-encrypt key plaintext . aad-opt)
    ;; Encrypt plaintext with AES-256-GCM.
    ;; key: 32-byte bytevector
    ;; plaintext: bytevector or string
    ;; aad: optional associated data bytevector (authenticated but not encrypted)
    ;; Returns: bytevector containing IV || ciphertext || tag
    (unless _loaded (error 'aead-encrypt "libcrypto not available"))
    (unless (and (bytevector? key) (= (bytevector-length key) AES_KEY_LEN))
      (error 'aead-encrypt "key must be 32-byte bytevector"))
    (let* ([pt (if (string? plaintext) (string->utf8 plaintext) plaintext)]
           [aad (if (pair? aad-opt) (car aad-opt) #f)]
           [iv (random-bytes GCM_IV_LEN)]
           [ct (make-bytevector (bytevector-length pt))]
           [tag (make-bytevector GCM_TAG_LEN)]
           [outlen (make-bytevector 4 0)]
           [ctx (c-EVP_CIPHER_CTX_new)])
      (when (= ctx 0) (error 'aead-encrypt "EVP_CIPHER_CTX_new failed"))
      (dynamic-wind
        (lambda () (void))
        (lambda ()
          ;; Init
          (when (= 0 (c-EVP_EncryptInit_ex ctx (c-EVP_aes_256_gcm) 0 key iv))
            (error 'aead-encrypt "EVP_EncryptInit_ex failed"))
          ;; AAD (output buffer = NULL for AAD)
          (when aad
            (let ([aad-bv (if (string? aad) (string->utf8 aad) aad)])
              (when (= 0 (c-EVP_EncryptUpdate_AAD ctx 0 outlen aad-bv (bytevector-length aad-bv)))
                (error 'aead-encrypt "EVP_EncryptUpdate (AAD) failed"))))
          ;; Encrypt
          (when (= 0 (c-EVP_EncryptUpdate ctx ct outlen pt (bytevector-length pt)))
            (error 'aead-encrypt "EVP_EncryptUpdate failed"))
          ;; Finalize
          (when (= 0 (c-EVP_EncryptFinal_ex ctx (make-bytevector 16) outlen))
            (error 'aead-encrypt "EVP_EncryptFinal_ex failed"))
          ;; Get tag
          (when (= 0 (c-EVP_CIPHER_CTX_ctrl ctx EVP_CTRL_GCM_GET_TAG GCM_TAG_LEN tag))
            (error 'aead-encrypt "get tag failed"))
          ;; Return IV || ciphertext || tag
          (let ([result (make-bytevector (+ GCM_IV_LEN (bytevector-length ct) GCM_TAG_LEN))])
            (bytevector-copy! iv 0 result 0 GCM_IV_LEN)
            (bytevector-copy! ct 0 result GCM_IV_LEN (bytevector-length ct))
            (bytevector-copy! tag 0 result (+ GCM_IV_LEN (bytevector-length ct)) GCM_TAG_LEN)
            result))
        (lambda ()
          (c-EVP_CIPHER_CTX_free ctx)))))

  (define (aead-decrypt key ciphertext . aad-opt)
    ;; Decrypt ciphertext with AES-256-GCM.
    ;; ciphertext: bytevector containing IV || encrypted || tag
    ;; Returns: plaintext bytevector, or raises error on auth failure
    (unless _loaded (error 'aead-decrypt "libcrypto not available"))
    (unless (and (bytevector? key) (= (bytevector-length key) AES_KEY_LEN))
      (error 'aead-decrypt "key must be 32-byte bytevector"))
    (let* ([total-len (bytevector-length ciphertext)]
           [ct-len (- total-len GCM_IV_LEN GCM_TAG_LEN)])
      (when (< ct-len 0)
        (error 'aead-decrypt "ciphertext too short"))
      (let* ([aad (if (pair? aad-opt) (car aad-opt) #f)]
             [iv (make-bytevector GCM_IV_LEN)]
             [ct (make-bytevector ct-len)]
             [tag (make-bytevector GCM_TAG_LEN)]
             [pt (make-bytevector ct-len)]
             [outlen (make-bytevector 4 0)]
             [ctx (c-EVP_CIPHER_CTX_new)])
        ;; Extract IV, ciphertext, tag
        (bytevector-copy! ciphertext 0 iv 0 GCM_IV_LEN)
        (bytevector-copy! ciphertext GCM_IV_LEN ct 0 ct-len)
        (bytevector-copy! ciphertext (+ GCM_IV_LEN ct-len) tag 0 GCM_TAG_LEN)
        (when (= ctx 0) (error 'aead-decrypt "EVP_CIPHER_CTX_new failed"))
        (dynamic-wind
          (lambda () (void))
          (lambda ()
            ;; Init
            (when (= 0 (c-EVP_DecryptInit_ex ctx (c-EVP_aes_256_gcm) 0 key iv))
              (error 'aead-decrypt "EVP_DecryptInit_ex failed"))
            ;; AAD (output buffer = NULL for AAD)
            (when aad
              (let ([aad-bv (if (string? aad) (string->utf8 aad) aad)])
                (when (= 0 (c-EVP_DecryptUpdate_AAD ctx 0 outlen aad-bv (bytevector-length aad-bv)))
                  (error 'aead-decrypt "EVP_DecryptUpdate (AAD) failed"))))
            ;; Decrypt
            (when (= 0 (c-EVP_DecryptUpdate ctx pt outlen ct ct-len))
              (error 'aead-decrypt "EVP_DecryptUpdate failed"))
            ;; Set expected tag
            (when (= 0 (c-EVP_CIPHER_CTX_ctrl ctx EVP_CTRL_GCM_SET_TAG GCM_TAG_LEN tag))
              (error 'aead-decrypt "set tag failed"))
            ;; Verify
            (let ([r (c-EVP_DecryptFinal_ex ctx (make-bytevector 16) outlen)])
              (when (= r 0)
                (error 'aead-decrypt "authentication failed — ciphertext tampered"))
              pt))
          (lambda ()
            (c-EVP_CIPHER_CTX_free ctx))))))

  ) ;; end library
