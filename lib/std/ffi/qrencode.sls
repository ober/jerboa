#!chezscheme
;;; (std ffi qrencode) -- Re-export of (thunderchez qrencode) bindings
(library (std ffi qrencode)
  (export
    qr-encode-string-8bit
    qr-encode-init
    qr-encode-mode
    qr-ec-level
    qrcode-width
    qrcode-version
    qrcode-data
    qrcode-data-ref
    QRcode)
  (import (thunderchez qrencode))
) ;; end library
