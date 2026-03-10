#!chezscheme
;;; :std/crypto/cipher -- Symmetric encryption (wraps chez-crypto)

(library (std crypto cipher)
  (export
    encrypt decrypt
    cipher-key-length cipher-iv-length cipher-block-size
    make-cipher-ctx free-cipher-ctx
    encrypt-init! encrypt-update! encrypt-final!
    decrypt-init! decrypt-update! decrypt-final!)

  (import (only (chez-crypto)
    encrypt decrypt
    cipher-key-length cipher-iv-length cipher-block-size
    make-cipher-ctx free-cipher-ctx
    encrypt-init! encrypt-update! encrypt-final!
    decrypt-init! decrypt-update! decrypt-final!))

  ) ;; end library
