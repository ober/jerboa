#!chezscheme
;;; :std/crypto/kdf -- Key derivation functions (wraps chez-crypto)

(library (std crypto kdf)
  (export scrypt)

  (import (only (chez-crypto) scrypt))

  ) ;; end library
