
(library (thunderchez qrencode)
  (export qr-encode-string-8bit
	  qr-encode-init
	  qr-encode-mode
	  qr-ec-level
	  qrcode-width
	  qrcode-version
	  qrcode-data
	  qrcode-data-ref
	  QRcode)
  (import (chezscheme) (thunderchez ffi-utils))
  
  (define-enumeration* qr-ec-level (L M Q H))
  
  (define-flags qr-encode-mode
    (nul -1) (num 0) (an 1) (bit8 2) (kanji 3) (structure 4) (eci 5) (fnc1first 6) (fnc1second 7))
    
  (define-ftype QRcode (struct (version int) (width int) (data (* unsigned-8))))

  (define (qr-encode-init)
    (load-shared-object "libqrencode.so"))

  (define (qr-encode-string-8bit str version level)
    ((foreign-procedure "QRcode_encodeString8bit" (string int int) (* QRcode))
     str version (qr-ec-level level)))
  
  (define (qrcode-width qrcode)
    (ftype-ref QRcode (width) qrcode))

  (define (qrcode-version qrcode)
    (ftype-ref QRcode (version) qrcode))

  (define (qrcode-data qrcode)
    (ftype-ref QRcode (data) qrcode))

  (define (qrcode-data-ref qrcode index)
    (ftype-ref QRcode (data index) qrcode)))


; EXAMPLE
#;(let* ([x (qr-encode-string-8bit "Chez Scheme" 1 'Q)]
       [w (qrcode-width x)])
  (for-each
   (lambda (i)
     (when (= 0 (remainder i w)) (newline))
     (if (= 1 (bitwise-and 1 (qrcode-data-ref x i)))
	 (display "\x2588;")
	 (display " ")))
   (iota (expt w 2))))

