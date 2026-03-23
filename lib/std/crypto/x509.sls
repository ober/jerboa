#!chezscheme
;;; (std crypto x509) — Self-signed certificate generation via Rust rcgen
;;;
;;; Generates Ed25519 self-signed certificates with IP address SANs.
;;; Intended for TOFU (trust-on-first-use) scenarios like remote mux servers.
;;; Certificates and keys are written as PEM files.

(library (std crypto x509)
  (export
    generate-self-signed-cert!
    cert-fingerprint)

  (import (chezscheme))

  ;; Load the Rust native library
  (define _native-loaded
    (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "./lib/libjerboa_native.so") #t)
        #f))

  ;; --- FFI bindings ---

  (define c-jerboa-last-error
    (foreign-procedure "jerboa_last_error" (u8* size_t) size_t))

  (define c-jerboa-x509-generate
    (foreign-procedure "jerboa_x509_generate_self_signed"
      (u8* size_t int u8* size_t u8* size_t) int))

  (define c-jerboa-x509-fingerprint
    (foreign-procedure "jerboa_x509_cert_fingerprint"
      (u8* size_t u8* size_t) int))

  ;; --- Helpers ---

  (define (native-last-error)
    (let ([buf (make-bytevector 1024)])
      (let ([len (c-jerboa-last-error buf 1024)])
        (if (> len 0)
          (utf8->string
            (let ([out (make-bytevector (min len 1023))])
              (bytevector-copy! buf 0 out 0 (min len 1023))
              out))
          ""))))

  (define (ensure-native! who)
    (unless _native-loaded
      (error who "libjerboa_native.so not available — build with `make native`")))

  (define (bytevector->hex bv)
    (let* ([len (bytevector-length bv)]
           [out (make-string (* len 2))])
      (do ([i 0 (+ i 1)])
          ((= i len) out)
        (let* ([b (bytevector-u8-ref bv i)]
               [hi (bitwise-arithmetic-shift-right b 4)]
               [lo (bitwise-and b #xf)])
          (string-set! out (* i 2) (string-ref "0123456789abcdef" hi))
          (string-set! out (+ (* i 2) 1) (string-ref "0123456789abcdef" lo))))))

  (define (ensure-parent-dirs! path)
    (let ([dir (x509-path-parent path)])
      (when (and dir (not (string=? dir "")) (not (file-exists? dir)))
        (x509-mkdir dir))))

  (define (x509-path-parent path)
    (let ([idx (string-last-index path #\/)])
      (if idx
        (substring path 0 idx)
        #f)))

  (define (string-last-index s ch)
    (let loop ([i (- (string-length s) 1)])
      (cond
        [(< i 0) #f]
        [(char=? (string-ref s i) ch) i]
        [else (loop (- i 1))])))

  (define (x509-mkdir path)
    (guard (e [#t (void)])
      (mkdir path)))

  ;; --- Public API ---

  ;; Generate a self-signed Ed25519 certificate with IP address SANs.
  ;;
  ;; ip-addresses: a string ("1.2.3.4") or list of strings ("1.2.3.4" "::1")
  ;; cert-path: filesystem path for PEM certificate output
  ;; key-path: filesystem path for PEM private key output
  ;; validity-days: certificate lifetime (default 365)
  ;;
  ;; Returns the SHA-256 fingerprint of the certificate as a hex string.
  ;; Creates parent directories if needed. Key file gets 0600 permissions.
  (define generate-self-signed-cert!
    (case-lambda
      [(ip-addresses cert-path key-path)
       (generate-self-signed-cert! ip-addresses cert-path key-path 365)]
      [(ip-addresses cert-path key-path validity-days)
       (ensure-native! 'generate-self-signed-cert!)
       (let* ([ips (if (list? ip-addresses)
                     (apply string-append
                       (let loop ([addrs ip-addresses] [acc '()])
                         (if (null? addrs)
                           (reverse acc)
                           (loop (cdr addrs)
                                 (if (null? acc)
                                   (list (car addrs))
                                   (cons (car addrs) (cons "," acc)))))))
                     ip-addresses)]
              [ips-bv (string->utf8 ips)]
              [cert-bv (string->utf8 cert-path)]
              [key-bv (string->utf8 key-path)])
         ;; Ensure parent directories exist
         (ensure-parent-dirs! cert-path)
         (ensure-parent-dirs! key-path)
         (let ([rc (c-jerboa-x509-generate
                     ips-bv (bytevector-length ips-bv)
                     validity-days
                     cert-bv (bytevector-length cert-bv)
                     key-bv (bytevector-length key-bv))])
           (when (< rc 0)
             (error 'generate-self-signed-cert! (native-last-error)))
           ;; Return the fingerprint
           (cert-fingerprint cert-path)))]))

  ;; Compute the SHA-256 fingerprint of a PEM certificate file.
  ;; Returns a 64-character hex string (e.g., "a1b2c3...").
  (define (cert-fingerprint cert-path)
    (ensure-native! 'cert-fingerprint)
    (let ([cert-bv (string->utf8 cert-path)]
          [out (make-bytevector 32)])
      (let ([rc (c-jerboa-x509-fingerprint
                  cert-bv (bytevector-length cert-bv)
                  out 32)])
        (when (< rc 0)
          (error 'cert-fingerprint (native-last-error)))
        (bytevector->hex out))))

  ) ;; end library
