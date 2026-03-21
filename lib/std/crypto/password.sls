#!chezscheme
;;; (std crypto password) — Password hashing via PBKDF2
;;;
;;; Uses PKCS5_PBKDF2_HMAC from libcrypto for password hashing.
;;; PBKDF2-HMAC-SHA256 with configurable iterations and salt.
;;; Argon2id would be preferred but requires libargon2 — PBKDF2 is
;;; universally available via OpenSSL.

(library (std crypto password)
  (export
    password-hash
    password-verify
    make-password-salt)

  (import (chezscheme)
          (std crypto random)
          (std crypto compare))

  ;; Load libcrypto
  (define _loaded
    (or (guard (e [#t #f]) (load-shared-object "libcrypto.so") #t)
        (guard (e [#t #f]) (load-shared-object "libcrypto.so.3") #t)))

  (define c-PKCS5_PBKDF2_HMAC
    (if _loaded
      (foreign-procedure "PKCS5_PBKDF2_HMAC"
        (u8* int u8* int int uptr int u8*) int)
      (lambda args (error 'password-hash "libcrypto not available"))))

  (define c-EVP_sha256
    (if _loaded
      (foreign-procedure "EVP_sha256" () uptr)
      (lambda () 0)))

  ;; ========== Public API ==========

  (define default-iterations 600000)  ;; OWASP 2023 recommendation for PBKDF2-SHA256
  (define default-key-len 32)
  (define default-salt-len 16)

  (define (make-password-salt)
    ;; Generate a random salt for password hashing.
    (random-bytes default-salt-len))

  (define (password-hash password . opts)
    ;; Hash a password with PBKDF2-HMAC-SHA256.
    ;; Returns a string: "$pbkdf2-sha256$iterations$salt-hex$hash-hex"
    ;; opts: iterations: N (default 600000), salt: bytevector
    (let* ([pass-bv (if (string? password) (string->utf8 password) password)]
           [iterations (kwarg 'iterations: opts default-iterations)]
           [salt (kwarg 'salt: opts (make-password-salt))]
           [out (make-bytevector default-key-len)])
      (let ([r (c-PKCS5_PBKDF2_HMAC
                 pass-bv (bytevector-length pass-bv)
                 salt (bytevector-length salt)
                 iterations
                 (c-EVP_sha256)
                 default-key-len
                 out)])
        (when (not (= r 1))
          (error 'password-hash "PKCS5_PBKDF2_HMAC failed"))
        ;; Format: $pbkdf2-sha256$iterations$salt$hash
        (string-append "$pbkdf2-sha256$"
          (number->string iterations) "$"
          (bytevector->hex salt) "$"
          (bytevector->hex out)))))

  (define (password-verify password hash-string)
    ;; Verify a password against a hash string.
    ;; Uses timing-safe comparison to prevent timing attacks.
    (let ([parts (string-split-dollar hash-string)])
      (unless (and (= (length parts) 5)
                   (string=? (cadr parts) "pbkdf2-sha256"))
        (error 'password-verify "invalid hash format" hash-string))
      (let* ([iterations (string->number (caddr parts))]
             [salt (hex->bytevector (cadddr parts))]
             [expected-hash (list-ref parts 4)]
             [pass-bv (if (string? password) (string->utf8 password) password)]
             [out (make-bytevector default-key-len)]
             [r (c-PKCS5_PBKDF2_HMAC
                  pass-bv (bytevector-length pass-bv)
                  salt (bytevector-length salt)
                  iterations
                  (c-EVP_sha256)
                  default-key-len
                  out)])
        (when (not (= r 1))
          (error 'password-verify "PKCS5_PBKDF2_HMAC failed"))
        ;; Timing-safe comparison
        (timing-safe-string=? (bytevector->hex out) expected-hash))))

  ;; ========== Helpers ==========

  (define (kwarg key opts default)
    (let loop ([l opts])
      (cond [(null? l) default]
            [(and (pair? (cdr l)) (eq? (car l) key)) (cadr l)]
            [else (loop (cdr l))])))

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

  (define (hex->bytevector s)
    (let* ([len (string-length s)]
           [out-len (quotient len 2)]
           [result (make-bytevector out-len)])
      (do ([i 0 (+ i 2)] [j 0 (+ j 1)])
          ((>= i len) result)
        (bytevector-u8-set! result j
          (+ (* (hex-val (string-ref s i)) 16)
             (hex-val (string-ref s (+ i 1))))))))

  (define (hex-val c)
    (cond [(char<=? #\0 c #\9) (- (char->integer c) (char->integer #\0))]
          [(char<=? #\a c #\f) (+ 10 (- (char->integer c) (char->integer #\a)))]
          [(char<=? #\A c #\F) (+ 10 (- (char->integer c) (char->integer #\A)))]
          [else 0]))

  (define (string-split-dollar s)
    (let ([n (string-length s)])
      (let lp ([i 0] [start 0] [acc '()])
        (cond
          [(>= i n) (reverse (cons (substring s start n) acc))]
          [(char=? (string-ref s i) #\$)
           (lp (+ i 1) (+ i 1) (cons (substring s start i) acc))]
          [else (lp (+ i 1) start acc)]))))

  ) ;; end library
