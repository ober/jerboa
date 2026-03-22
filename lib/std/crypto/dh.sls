#!chezscheme
;;; (std crypto dh) — Diffie-Hellman key exchange
;;;
;;; Provides parameter generation, key generation, and shared-secret
;;; computation for classic DH over Z/pZ.  Includes RFC 3526 Group 14
;;; (2048-bit MODP) as a ready-to-use parameter set.
;;;
;;; Random bytes are read from /dev/urandom for security-relevant operations.

(library (std crypto dh)
  (export
    make-dh-params dh-params? dh-params-p dh-params-g
    make-dh-key dh-key? dh-key-public dh-key-private
    dh-generate-parameters
    dh-generate-key
    dh-compute-shared
    dh-2048-modp)

  (import (chezscheme)
          (std crypto bn))

  ;; ========== Record types ==========

  (define-record-type dh-params
    (fields p g)
    (protocol
     (lambda (new)
       (lambda (p g)
         (unless (and (integer? p) (positive? p))
           (error 'make-dh-params "p must be a positive integer" p))
         (unless (and (integer? g) (positive? g))
           (error 'make-dh-params "g must be a positive integer" g))
         (new p g)))))

  (define-record-type dh-key
    (fields public private)
    (protocol
     (lambda (new)
       (lambda (public private)
         (new public private)))))

  ;; ========== Random number generation (from /dev/urandom) ==========

  (define (read-urandom-bytes n)
    ;; Read N bytes from /dev/urandom, return as a bytevector.
    (let ([bv (make-bytevector n)]
          [port (open-file-input-port "/dev/urandom"
                  (file-options)
                  (buffer-mode block))])
      (dynamic-wind
        (lambda () (void))
        (lambda ()
          (let loop ([offset 0])
            (when (< offset n)
              (let ([got (get-bytevector-n! port bv offset (- n offset))])
                (when (eof-object? got)
                  (error 'read-urandom-bytes "unexpected EOF from /dev/urandom"))
                (loop (+ offset got)))))
          bv)
        (lambda () (close-port port)))))

  (define (random-integer-below limit)
    ;; Return a random integer in [1, limit-1] using /dev/urandom.
    ;; Uses rejection sampling to avoid modular bias.
    (when (<= limit 2)
      (error 'random-integer-below "limit must be > 2" limit))
    (let* ([byte-len (fxdiv (fx+ (bn-bit-length limit) 7) 8)]
           ;; Compute mask: 2^(bit-length of limit) - 1
           [bit-len (bn-bit-length limit)]
           [mask (- (bitwise-arithmetic-shift-left 1 bit-len) 1)])
      (let loop ()
        (let* ([bv (read-urandom-bytes byte-len)]
               [candidate (bitwise-and (bytevector->bn bv) mask)])
          ;; We need candidate in [1, limit-1]
          (if (and (> candidate 0) (< candidate limit))
              candidate
              (loop))))))

  ;; ========== RFC 3526 Group 14: 2048-bit MODP ==========

  (define dh-2048-modp
    (make-dh-params
     (hex->bn
      (string-append
       "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD1"
       "29024E088A67CC74020BBEA63B139B22514A08798E3404DD"
       "EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245"
       "E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED"
       "EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3D"
       "C2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F"
       "83655D23DCA3AD961C62F356208552BB9ED529077096966D"
       "670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B"
       "E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9"
       "DE2BCBF6955817183995497CEA956AE515D2261898FA0510"
       "15728E5A8AACAA68FFFFFFFFFFFFFFFF"))
     2))

  ;; ========== Parameter generation ==========

  (define (dh-generate-parameters bits . args)
    ;; Generate DH parameters with a prime of approximately BITS bits.
    ;; Optional keyword: generator (default 2).
    ;; NOTE: For production use, prefer dh-2048-modp or other well-known
    ;; groups.  This generates a random probable prime, which is slower
    ;; and less auditable than established parameters.
    (let ([g (if (null? args) 2 (car args))])
      (unless (and (fixnum? bits) (>= bits 512))
        (error 'dh-generate-parameters "bits must be >= 512" bits))
      (let ([p (generate-safe-prime bits)])
        (make-dh-params p g))))

  (define (generate-safe-prime bits)
    ;; Find a probable safe prime p where p = 2q + 1 and q is also prime.
    ;; Uses Miller-Rabin with enough rounds for confidence.
    (let loop ()
      (let* ([candidate (random-odd-with-bits bits)])
        ;; Check if candidate is prime, and (candidate-1)/2 is also prime
        (if (and (miller-rabin-prime? candidate 20)
                 (miller-rabin-prime? (div (- candidate 1) 2) 20))
            candidate
            (loop)))))

  (define (random-odd-with-bits bits)
    ;; Generate a random odd number with exactly BITS bits (high bit set).
    (let* ([byte-len (fxdiv (fx+ bits 7) 8)]
           [bv (read-urandom-bytes byte-len)]
           [n (bytevector->bn bv)]
           ;; Set the high bit
           [n (bitwise-ior n (bitwise-arithmetic-shift-left 1 (- bits 1)))]
           ;; Clear any bits above our target bit-length
           [mask (- (bitwise-arithmetic-shift-left 1 bits) 1)]
           [n (bitwise-and n mask)]
           ;; Make odd
           [n (bitwise-ior n 1)])
      n))

  (define (miller-rabin-prime? n rounds)
    ;; Miller-Rabin primality test. Returns #t if n is probably prime.
    (cond
      [(< n 2) #f]
      [(= n 2) #t]
      [(= n 3) #t]
      [(even? n) #f]
      [else
       ;; Write n-1 as 2^r * d where d is odd
       (let-values ([(r d) (factor-out-2s (- n 1))])
         (let loop ([i 0])
           (if (>= i rounds)
               #t  ; probably prime
               (let* ([a (+ 2 (random-integer-below (- n 3)))]
                      ;; a is in [2, n-2]
                      [x (bn-expt-mod a d n)])
                 (cond
                   [(or (= x 1) (= x (- n 1)))
                    (loop (+ i 1))]
                   [else
                    (let inner ([j 1] [x x])
                      (cond
                        [(>= j r) #f]  ; composite
                        [(= (bn-expt-mod x 2 n) (- n 1))
                         (loop (+ i 1))]
                        [(= (bn-expt-mod x 2 n) 1)
                         #f]  ; composite
                        [else
                         (inner (+ j 1) (bn-expt-mod x 2 n))]))])))))]))

  (define (factor-out-2s n)
    ;; Return (values r d) where n = 2^r * d and d is odd.
    (let loop ([r 0] [d n])
      (if (even? d)
          (loop (+ r 1) (div d 2))
          (values r d))))

  ;; ========== Key generation ==========

  (define (dh-generate-key params)
    ;; Generate a DH key pair given parameters.
    ;; Private key: random integer in [1, p-2]
    ;; Public key: g^private mod p
    (let* ([p (dh-params-p params)]
           [g (dh-params-g params)]
           [private (random-integer-below (- p 1))]  ; [1, p-2]
           [public (bn-expt-mod g private p)])
      (make-dh-key public private)))

  ;; ========== Shared secret computation ==========

  (define (dh-compute-shared params own-private other-public)
    ;; Compute shared secret: other-public^own-private mod p
    (let ([p (dh-params-p params)])
      (unless (and (> other-public 1) (< other-public (- p 1)))
        (error 'dh-compute-shared
               "other party's public key out of safe range" other-public))
      (bn-expt-mod other-public own-private p)))

  ) ;; end library
