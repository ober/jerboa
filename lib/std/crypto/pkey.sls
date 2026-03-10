#!chezscheme
;;; :std/crypto/pkey -- Public key cryptography (wraps chez-crypto)

(library (std crypto pkey)
  (export ed25519-keygen ed25519-sign ed25519-verify)

  (import (only (chez-crypto) ed25519-keygen ed25519-sign ed25519-verify))

  ) ;; end library
