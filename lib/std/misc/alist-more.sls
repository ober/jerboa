#!chezscheme
;;; (std misc alist-more) — Extended association list operations
;;;
;;; Additional alist operations for config handling and key-value stores.

(library (std misc alist-more)
  (export alist-ref/default alist-update alist-merge
          alist-filter alist-map alist-keys alist-values
          alist->hash)

  (import (chezscheme))

  ;; Lookup with default
  (define (alist-ref/default key alist default)
    (let ([pair (assoc key alist)])
      (if pair (cdr pair) default)))

  ;; Functional update: return new alist with key set to value
  (define (alist-update key value alist)
    (let loop ([rest alist] [found #f] [acc '()])
      (cond
        [(null? rest)
         (if found
             (reverse acc)
             (reverse (cons (cons key value) acc)))]
        [(equal? (caar rest) key)
         (loop (cdr rest) #t (cons (cons key value) acc))]
        [else
         (loop (cdr rest) found (cons (car rest) acc))])))

  ;; Merge two alists (second takes precedence)
  (define (alist-merge alist1 alist2)
    (let loop ([rest alist2] [result alist1])
      (if (null? rest)
          result
          (loop (cdr rest)
                (alist-update (caar rest) (cdar rest) result)))))

  ;; Filter entries by predicate (key value → bool)
  (define (alist-filter pred alist)
    (filter (lambda (pair) (pred (car pair) (cdr pair))) alist))

  ;; Map over values, keeping keys
  (define (alist-map proc alist)
    (map (lambda (pair) (cons (car pair) (proc (cdr pair)))) alist))

  ;; Extract keys
  (define (alist-keys alist)
    (map car alist))

  ;; Extract values
  (define (alist-values alist)
    (map cdr alist))

  ;; Convert alist to hash table
  (define (alist->hash alist)
    (let ([ht (make-hashtable equal-hash equal?)])
      (for-each (lambda (pair) (hashtable-set! ht (car pair) (cdr pair)))
                alist)
      ht))

  ;; hash->alist is in (std misc hash-more); use that module for round-trip

) ;; end library
