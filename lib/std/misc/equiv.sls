#!chezscheme
;;; (std misc equiv) --- Cycle-aware structural equality and hashing
;;;
;;; equiv? is like equal? but handles cyclic data structures by tracking
;;; visited object pairs. When a cycle is detected (same pair of objects
;;; seen before), it returns #t, treating the cycle as structurally
;;; equivalent at that point.
;;;
;;; equiv-hash is a hash function that handles cyclic structures by
;;; bounding traversal depth.

(library (std misc equiv)
  (export equiv? equiv-hash)
  (import (chezscheme))

  ;; Combine two hash values (using generic arithmetic to avoid fixnum overflow,
  ;; then mask back to fixnum range)
  (define fixnum-mask (greatest-fixnum))

  (define (hash-combine h1 h2)
    (logand fixnum-mask
            (logxor h1 (+ (ash h2 5) (ash h2 -2) h2))))

  ;; Make a key for a pair of objects using their eq-hash values.
  ;; We use a cons of the two eq-hash values as the key, and store
  ;; in a hashtable keyed by the first object mapping to an alist
  ;; of second objects. This avoids issues with eq-hash collisions.

  ;; The visited set maps object-a -> list of object-b that have been
  ;; seen paired with a.
  (define (make-visited) (make-eq-hashtable))

  (define (visited? seen a b)
    (let ([partners (eq-hashtable-ref seen a '())])
      (memq b partners)))

  (define (visit! seen a b)
    (let ([partners (eq-hashtable-ref seen a '())])
      (eq-hashtable-set! seen a (cons b partners))))

  ;; Core recursive equivalence check
  (define (equiv-rec a b seen)
    (cond
      ;; Fast path: eq? objects are always equivalent
      [(eq? a b) #t]
      ;; Cycle detection: if we've seen this pair, treat as equivalent
      [(visited? seen a b) #t]
      ;; Pairs
      [(and (pair? a) (pair? b))
       (visit! seen a b)
       (and (equiv-rec (car a) (car b) seen)
            (equiv-rec (cdr a) (cdr b) seen))]
      ;; Vectors
      [(and (vector? a) (vector? b))
       (let ([n (vector-length a)])
         (and (fx= n (vector-length b))
              (begin
                (visit! seen a b)
                (let loop ([i 0])
                  (or (fx= i n)
                      (and (equiv-rec (vector-ref a i) (vector-ref b i) seen)
                           (loop (fx+ i 1))))))))]
      ;; Strings
      [(and (string? a) (string? b))
       (string=? a b)]
      ;; Bytevectors
      [(and (bytevector? a) (bytevector? b))
       (bytevector=? a b)]
      ;; Box (Chez Scheme boxes)
      [(and (box? a) (box? b))
       (visit! seen a b)
       (equiv-rec (unbox a) (unbox b) seen)]
      ;; Hashtables
      [(and (hashtable? a) (hashtable? b))
       (and (fx= (hashtable-size a) (hashtable-size b))
            (begin
              (visit! seen a b)
              (let-values ([(keys vals) (hashtable-entries a)])
                (let loop ([i 0])
                  (or (fx= i (vector-length keys))
                      (let ([k (vector-ref keys i)]
                            [v (vector-ref vals i)])
                        (let ([bv (hashtable-ref b k (void))])
                          (and (not (eq? bv (void)))
                               (equiv-rec v bv seen)
                               (loop (fx+ i 1))))))))))]
      ;; Fall back to equal? for everything else (numbers, chars, etc.)
      [else (equal? a b)]))

  ;; Public API
  (define (equiv? a b)
    (equiv-rec a b (make-visited)))

  ;; Cycle-aware hash function
  ;; Uses depth-bounded traversal to avoid infinite recursion on cycles.
  (define equiv-hash
    (case-lambda
      [(x) (equiv-hash-rec x 64)]
      [(x depth) (equiv-hash-rec x depth)]))

  (define (equiv-hash-rec x depth)
    (cond
      [(fx<= depth 0) 0]  ;; depth limit reached, contribute nothing
      [(pair? x)
       (hash-combine
         (equiv-hash-rec (car x) (fx- depth 1))
         (equiv-hash-rec (cdr x) (fx- depth 1)))]
      [(vector? x)
       (let ([n (fxmin (vector-length x) depth)])
         (let loop ([i 0] [h (equal-hash (vector-length x))])
           (if (fx= i n)
               h
               (loop (fx+ i 1)
                     (hash-combine h (equiv-hash-rec (vector-ref x i) (fx- depth 1)))))))]
      [(string? x) (string-hash x)]
      [(bytevector? x) (equal-hash x)]
      [(box? x) (hash-combine 7 (equiv-hash-rec (unbox x) (fx- depth 1)))]
      [else (equal-hash x)]))

) ;; end library
