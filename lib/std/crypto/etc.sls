#!chezscheme
;;; :std/crypto/etc -- Crypto utilities (wraps chez-crypto)

(library (std crypto etc)
  (export random-bytes random-bytes! crypto-error-string)

  (import (only (chez-crypto) random-bytes random-bytes! crypto-error-string))

  ) ;; end library
