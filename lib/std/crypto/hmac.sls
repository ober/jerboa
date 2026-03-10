#!chezscheme
;;; :std/crypto/hmac -- HMAC message authentication (wraps chez-crypto)

(library (std crypto hmac)
  (export hmac hmac-md5 hmac-sha1 hmac-sha256 hmac-sha384 hmac-sha512)

  (import (only (chez-crypto) hmac hmac-md5 hmac-sha1 hmac-sha256 hmac-sha384 hmac-sha512))

  ) ;; end library
