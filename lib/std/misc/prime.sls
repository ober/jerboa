#!chezscheme
;;; (std misc prime) -- Prime number operations
;;;
;;; Trial division for small numbers, Miller-Rabin for large.
;;; Sieve of Eratosthenes for generating primes up to a limit.
;;;
;;; Usage:
;;;   (import (std misc prime))
;;;   (prime? 17)                ;; #t
;;;   (next-prime 10)            ;; 11
;;;   (primes-up-to 20)          ;; (2 3 5 7 11 13 17 19)
;;;   (factorize 360)            ;; ((2 . 3) (3 . 2) (5 . 1))
;;;   (prime-factors 12)         ;; (2 2 3)
;;;   (euler-totient 12)         ;; 4

(library (std misc prime)
  (export
    prime?
    next-prime
    prev-prime
    primes-up-to
    nth-prime
    factorize
    prime-factors
    coprime?
    euler-totient)

  (import (chezscheme))

  ;; ========== Small primes for trial division ==========

  (define small-primes
    '(2 3 5 7 11 13 17 19 23 29 31 37 41 43 47 53 59 61 67 71
      73 79 83 89 97 101 103 107 109 113 127 131 137 139 149 151
      157 163 167 173 179 181 191 193 197 199 211 223 227 229 233
      239 241 251 257 263 269 271 277 281 283 293 307 311 313 317
      331 337 347 349 353 359 367 373 379 383 389 397 401 409 419
      421 431 433 439 443 449 457 461 463 467 479 487 491 499 503
      509 521 523 541 547 557 563 569 571 577 587 593 599 601 607
      613 617 619 631 641 643 647 653 659 661 673 677 683 691 701
      709 719 727 733 739 743 751 757 761 769 773 787 797 809 811
      821 823 827 829 839 853 857 859 863 877 881 883 887 907 911
      919 929 937 941 947 953 967 971 977 983 991 997))

  (define trial-division-limit 1000000)  ;; use trial division below this

  ;; ========== Modular exponentiation ==========

  (define (mod-exp base exp mod)
    ;; base^exp mod mod, using repeated squaring
    (let loop ([b (modulo base mod)] [e exp] [result 1])
      (cond
        [(zero? e) result]
        [(odd? e) (loop (modulo (* b b) mod) (quotient e 2) (modulo (* result b) mod))]
        [else (loop (modulo (* b b) mod) (quotient e 2) result)])))

  ;; ========== Miller-Rabin primality test ==========

  (define (miller-rabin-witness? a n)
    ;; Returns #t if a is a witness to n being composite.
    ;; n must be odd and > 2.
    (let* ([n-1 (- n 1)])
      ;; Write n-1 = d * 2^r
      (let loop ([d n-1] [r 0])
        (if (even? d)
          (loop (quotient d 2) (+ r 1))
          ;; Now n-1 = d * 2^r with d odd
          (let ([x (mod-exp a d n)])
            (cond
              [(or (= x 1) (= x n-1)) #f]  ;; probably prime
              [else
               ;; Square up to r-1 times
               (let inner ([x x] [i 1])
                 (cond
                   [(>= i r) #t]  ;; composite
                   [else
                    (let ([x2 (modulo (* x x) n)])
                      (cond
                        [(= x2 1) #t]      ;; composite
                        [(= x2 n-1) #f]    ;; probably prime
                        [else (inner x2 (+ i 1))]))]))]))))))

  (define (miller-rabin-prime? n)
    ;; Deterministic for n < 3,317,044,064,679,887,385,961,981
    ;; using specific witness sets.
    (cond
      [(< n 2) #f]
      [(= n 2) #t]
      [(even? n) #f]
      [(< n 9) #t]  ;; 3,5,7
      [else
       ;; For n < 3,215,031,751 these witnesses suffice for determinism:
       ;; 2, 3, 5, 7  (for n < 3.2 billion)
       ;; For larger, use more witnesses.
       (let ([witnesses (if (< n 3215031751)
                          '(2 3 5 7)
                          '(2 3 5 7 11 13 17 19 23 29 31 37))])
         (let loop ([ws witnesses])
           (cond
             [(null? ws) #t]
             [(>= (car ws) n) #t]  ;; witness >= n, skip
             [(miller-rabin-witness? (car ws) n) #f]
             [else (loop (cdr ws))])))]))

  ;; ========== Trial division ==========

  (define (trial-division-prime? n)
    (cond
      [(< n 2) #f]
      [(= n 2) #t]
      [(even? n) #f]
      [else
       (let ([limit (isqrt n)])
         (let loop ([d 3])
           (cond
             [(> d limit) #t]
             [(zero? (modulo n d)) #f]
             [else (loop (+ d 2))])))]))

  ;; ========== Public prime? ==========

  (define (prime? n)
    (unless (and (integer? n) (exact? n))
      (error 'prime? "expected an exact integer" n))
    (cond
      [(< n 2) #f]
      [(< n trial-division-limit) (trial-division-prime? n)]
      [else (miller-rabin-prime? n)]))

  ;; ========== next-prime, prev-prime ==========

  (define (next-prime n)
    (unless (and (integer? n) (exact? n))
      (error 'next-prime "expected an exact integer" n))
    (cond
      [(< n 2) 2]
      [(= n 2) 3]
      [else
       (let ([start (if (even? n) (+ n 1) (+ n 2))])
         (let loop ([k start])
           (if (prime? k) k (loop (+ k 2)))))]))

  (define (prev-prime n)
    (unless (and (integer? n) (exact? n))
      (error 'prev-prime "expected an exact integer" n))
    (cond
      [(< n 3) (error 'prev-prime "no prime less than" n)]
      [(<= n 3) 2]
      [else
       (let ([start (if (even? n) (- n 1) (- n 2))])
         (let loop ([k start])
           (cond
             [(< k 2) (error 'prev-prime "no prime found")]
             [(prime? k) k]
             [else (loop (- k 2))])))]))

  ;; ========== Sieve of Eratosthenes ==========

  (define (primes-up-to limit)
    (unless (and (integer? limit) (exact? limit))
      (error 'primes-up-to "expected an exact integer" limit))
    (if (< limit 2)
      '()
      (let ([sieve (make-vector (+ limit 1) #t)])
        (vector-set! sieve 0 #f)
        (vector-set! sieve 1 #f)
        (let outer ([i 2])
          (when (<= (* i i) limit)
            (when (vector-ref sieve i)
              (let inner ([j (* i i)])
                (when (<= j limit)
                  (vector-set! sieve j #f)
                  (inner (+ j i)))))
            (outer (+ i 1))))
        ;; Collect results
        (let loop ([i 2] [acc '()])
          (if (> i limit)
            (reverse acc)
            (loop (+ i 1) (if (vector-ref sieve i) (cons i acc) acc)))))))

  ;; ========== nth-prime ==========

  (define (nth-prime n)
    ;; Return the n-th prime (1-indexed: nth-prime 1 = 2)
    (unless (and (integer? n) (exact? n) (>= n 1))
      (error 'nth-prime "expected a positive exact integer" n))
    (let loop ([count 0] [candidate 2])
      (if (prime? candidate)
        (let ([count (+ count 1)])
          (if (= count n)
            candidate
            (loop count (+ candidate 1))))
        (loop count (+ candidate 1)))))

  ;; ========== Factorization ==========

  (define (factorize n)
    ;; Returns list of (prime . exponent) pairs, sorted by prime.
    (unless (and (integer? n) (exact? n) (> n 0))
      (error 'factorize "expected a positive exact integer" n))
    (if (= n 1)
      '()
      (let loop ([n n] [d 2] [factors '()])
        (cond
          [(> (* d d) n)
           ;; n is prime (remaining factor)
           (if (> n 1)
             (reverse (cons (cons n 1) factors))
             (reverse factors))]
          [(zero? (modulo n d))
           ;; Count how many times d divides n
           (let inner ([n n] [count 0])
             (if (zero? (modulo n d))
               (inner (quotient n d) (+ count 1))
               (loop n (if (= d 2) 3 (+ d 2))
                     (cons (cons d count) factors))))]
          [else
           (loop n (if (= d 2) 3 (+ d 2)) factors)]))))

  (define (prime-factors n)
    ;; Returns flat list of prime factors with repetition.
    (unless (and (integer? n) (exact? n) (> n 0))
      (error 'prime-factors "expected a positive exact integer" n))
    (if (= n 1)
      '()
      (let loop ([n n] [d 2] [factors '()])
        (cond
          [(> (* d d) n)
           (if (> n 1)
             (reverse (cons n factors))
             (reverse factors))]
          [(zero? (modulo n d))
           (loop (quotient n d) d (cons d factors))]
          [else
           (loop n (if (= d 2) 3 (+ d 2)) factors)]))))

  ;; ========== coprime? ==========

  (define (coprime? a b)
    (= (gcd a b) 1))

  ;; ========== Euler's totient function ==========

  (define (euler-totient n)
    ;; phi(n) = n * product of (1 - 1/p) for each distinct prime factor p
    (unless (and (integer? n) (exact? n) (> n 0))
      (error 'euler-totient "expected a positive exact integer" n))
    (if (= n 1)
      1
      (let ([facts (factorize n)])
        (let loop ([facts facts] [result n])
          (if (null? facts)
            result
            (let ([p (caar facts)])
              (loop (cdr facts)
                    (/ (* result (- p 1)) p))))))))

) ;; end library
