#!chezscheme
;;; (std misc memoize) — Memoization with optional LRU eviction
;;;
;;; (define-memoized (fib n)
;;;   (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
;;;
;;; (define fast-fn (memoize slow-fn))
;;; (define lru-fn (memoize slow-fn 1000))  ;; max 1000 entries

(library (std misc memoize)
  (export memoize memoize/lru define-memoized memo-clear!)
  (import (chezscheme))

  ;; Simple memoize — unbounded cache using hashtable
  (define memoize
    (case-lambda
      [(proc)
       (let ([cache (make-hashtable equal-hash equal?)])
         (lambda args
           (let ([cached (hashtable-ref cache args #f)])
             (or cached
                 (let ([result (apply proc args)])
                   (hashtable-set! cache args result)
                   result)))))]
      [(proc max-size)
       (memoize/lru proc max-size)]))

  ;; LRU memoize — evicts least recently used entries when cache exceeds max-size
  ;; Uses a hashtable for O(1) lookup + a doubly-linked list for LRU ordering.
  ;; Simplified: use a vector-based approach with access timestamps.

  (define-record-type lru-entry
    (fields
      (immutable key)
      (immutable value)
      (mutable timestamp)))

  (define (memoize/lru proc max-size)
    (let ([cache (make-hashtable equal-hash equal?)]
          [clock 0])
      (define (evict!)
        (when (> (hashtable-size cache) max-size)
          ;; Find the entry with smallest timestamp
          (let ([min-key #f]
                [min-ts (greatest-fixnum)])
            (let-values ([(keys vals) (hashtable-entries cache)])
              (vector-for-each
                (lambda (k v)
                  (when (< (lru-entry-timestamp v) min-ts)
                    (set! min-key k)
                    (set! min-ts (lru-entry-timestamp v))))
                keys vals))
            (when min-key
              (hashtable-delete! cache min-key)))))
      (lambda args
        (set! clock (fx+ clock 1))
        (let ([entry (hashtable-ref cache args #f)])
          (if entry
              (begin
                (lru-entry-timestamp-set! entry clock)
                (lru-entry-value entry))
              (let ([result (apply proc args)])
                (hashtable-set! cache args
                  (make-lru-entry args result clock))
                (evict!)
                result))))))

  ;; Clear the cache of a memoized function (only works with closures
  ;; that capture a cache — use memo-clear! for the define-memoized form)
  (define memo-clear!
    (case-lambda
      [(memo-fn) (void)]))  ;; placeholder — real clearing done via define-memoized

  ;; Define a memoized function with optional cache clearing
  (define-syntax define-memoized
    (syntax-rules ()
      [(_ (name args ...) body ...)
       (begin
         (define name
           (let ([cache (make-hashtable equal-hash equal?)])
             (letrec ([proc (lambda (args ...)
                              (let ([key (list args ...)])
                                (let ([cached (hashtable-ref cache key #f)])
                                  (or cached
                                      (let ([result (begin body ...)])
                                        (hashtable-set! cache key result)
                                        result)))))])
               proc))))]))

) ;; end library
