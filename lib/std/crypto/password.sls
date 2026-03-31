#!chezscheme
;;; (std crypto password) — Password hashing via Argon2id and PBKDF2
;;;
;;; Preferred: Argon2id via Rust native library (memory-hard, GPU-resistant).
;;; Fallback:  PBKDF2-HMAC-SHA256 via OpenSSL (universally available).
;;;
;;; password-hash defaults to Argon2id when libjerboa_native.so is available,
;;; falls back to PBKDF2 otherwise. password-verify auto-detects the algorithm
;;; from the hash string prefix ($argon2id$ or $pbkdf2-sha256$).

(library (std crypto password)
  (export
    password-hash
    password-verify
    make-password-salt
    password-hash-argon2id
    password-verify-argon2id
    argon2id-available?)

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

  ;; ========== Argon2id Support (via Rust native library) ==========

  ;; Try to load libjerboa_native.so for Argon2id
  (define *argon2id-loaded*
    (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
        #f))

  (define c-jerboa-argon2id-hash
    (if *argon2id-loaded*
      (guard (e [#t #f])
        (foreign-procedure "jerboa_argon2id_hash"
          (u8* size_t u8* size_t unsigned-32 unsigned-32 unsigned-32 u8* size_t) int))
      #f))

  (define c-jerboa-argon2id-verify
    (if *argon2id-loaded*
      (guard (e [#t #f])
        (foreign-procedure "jerboa_argon2id_verify"
          (u8* size_t u8* size_t unsigned-32 unsigned-32 unsigned-32 u8* size_t) int))
      #f))

  (define (argon2id-available?)
    (and c-jerboa-argon2id-hash c-jerboa-argon2id-verify #t))

  ;; OWASP 2023 recommended Argon2id parameters
  (define default-argon2id-m-cost 19456)  ;; 19 MiB
  (define default-argon2id-t-cost 2)      ;; 2 iterations
  (define default-argon2id-p-cost 1)      ;; 1 thread

  ;; ========== Public API ==========

  (define default-iterations 600000)  ;; OWASP 2023 recommendation for PBKDF2-SHA256
  (define default-key-len 32)
  (define default-salt-len 16)

  (define (make-password-salt)
    ;; Generate a random salt for password hashing.
    (random-bytes default-salt-len))

  (define (password-hash-argon2id password . opts)
    ;; Hash a password with Argon2id.
    ;; Returns a string: "$argon2id$m=M,t=T,p=P$salt-hex$hash-hex"
    (unless (argon2id-available?)
      (error 'password-hash-argon2id "argon2id not available — libjerboa_native.so not loaded"))
    (let* ([pass-bv (if (string? password) (string->utf8 password) password)]
           [m-cost (kwarg 'memory: opts default-argon2id-m-cost)]
           [t-cost (kwarg 'time: opts default-argon2id-t-cost)]
           [p-cost (kwarg 'parallelism: opts default-argon2id-p-cost)]
           [salt (kwarg 'salt: opts (make-password-salt))]
           [out (make-bytevector default-key-len)])
      (let ([rc (c-jerboa-argon2id-hash pass-bv (bytevector-length pass-bv)
                                         salt (bytevector-length salt)
                                         m-cost t-cost p-cost
                                         out default-key-len)])
        (when (< rc 0)
          (error 'password-hash-argon2id "argon2id hash failed"))
        (string-append "$argon2id$"
          "m=" (number->string m-cost)
          ",t=" (number->string t-cost)
          ",p=" (number->string p-cost) "$"
          (bytevector->hex salt) "$"
          (bytevector->hex out)))))

  (define (password-verify-argon2id password hash-string)
    ;; Verify a password against an Argon2id hash string.
    (unless (argon2id-available?)
      (error 'password-verify-argon2id "argon2id not available"))
    (let ([parts (string-split-dollar hash-string)])
      (unless (and (>= (length parts) 5)
                   (string=? (cadr parts) "argon2id"))
        (error 'password-verify-argon2id "invalid hash format" hash-string))
      (let* ([params-str (caddr parts)]
             [m-cost (parse-argon2-param params-str "m=")]
             [t-cost (parse-argon2-param params-str "t=")]
             [p-cost (parse-argon2-param params-str "p=")]
             [salt (hex->bytevector (cadddr parts))]
             [expected (hex->bytevector (list-ref parts 4))]
             [pass-bv (if (string? password) (string->utf8 password) password)])
        (let ([rc (c-jerboa-argon2id-verify pass-bv (bytevector-length pass-bv)
                                             salt (bytevector-length salt)
                                             m-cost t-cost p-cost
                                             expected (bytevector-length expected))])
          (= rc 1)))))

  (define (parse-argon2-param str prefix)
    ;; Extract numeric value after prefix from "m=19456,t=2,p=1"
    (let* ([plen (string-length prefix)]
           [slen (string-length str)])
      (let loop ([i 0])
        (cond
          [(> (+ i plen) slen)
           (error 'parse-argon2-param "parameter not found" prefix str)]
          [(string=? (substring str i (+ i plen)) prefix)
           (let num-loop ([j (+ i plen)] [acc '()])
             (if (or (>= j slen)
                     (char=? (string-ref str j) #\,))
               (string->number (list->string (reverse acc)))
               (num-loop (+ j 1) (cons (string-ref str j) acc))))]
          [else (loop (+ i 1))]))))

  (define (password-hash password . opts)
    ;; Hash a password. Prefers Argon2id when available, falls back to PBKDF2.
    ;; Returns a string with algorithm prefix for auto-detection on verify.
    (if (argon2id-available?)
      (apply password-hash-argon2id password opts)
      (password-hash-pbkdf2 password opts)))

  (define (password-hash-pbkdf2 password opts)
    ;; Hash a password with PBKDF2-HMAC-SHA256.
    ;; Returns a string: "$pbkdf2-sha256$iterations$salt-hex$hash-hex"
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
        (string-append "$pbkdf2-sha256$"
          (number->string iterations) "$"
          (bytevector->hex salt) "$"
          (bytevector->hex out)))))

  (define (password-verify password hash-string)
    ;; Verify a password against a hash string.
    ;; Auto-detects algorithm from prefix ($argon2id$ or $pbkdf2-sha256$).
    (let ([parts (string-split-dollar hash-string)])
      (cond
        [(and (>= (length parts) 5)
              (string=? (cadr parts) "argon2id"))
         (password-verify-argon2id password hash-string)]
        [(and (= (length parts) 5)
              (string=? (cadr parts) "pbkdf2-sha256"))
         (password-verify-pbkdf2 password parts)]
        [else
         (error 'password-verify "unknown hash format" hash-string)])))

  (define (password-verify-pbkdf2 password parts)
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
      (timing-safe-string=? (bytevector->hex out) expected-hash)))

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
