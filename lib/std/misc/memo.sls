#!chezscheme
;;; (std misc memo) -- Memoization with TTL and LRU Eviction
;;;
;;; Features:
;;;   - memo: simple memoization (unbounded)
;;;   - memo/lru: memoization with LRU eviction
;;;   - memo/ttl: memoization with time-to-live expiry
;;;   - memo/lru+ttl: combined LRU + TTL
;;;   - Cache introspection: stats, clear, size
;;;
;;; Usage:
;;;   (import (std misc memo))
;;;   (define fib (memo (lambda (n)
;;;     (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))))
;;;   (fib 100)  ; fast!
;;;
;;;   (define fetch (memo/ttl 60  ; 60 second TTL
;;;     (lambda (url) (http-get url))))
;;;
;;;   (define lookup (memo/lru 1000  ; max 1000 entries
;;;     (lambda (key) (db-query key))))

(library (std misc memo)
  (export
    memo
    memo/lru
    memo/ttl
    memo/lru+ttl
    memo-clear!
    memo-stats
    memo-size
    memo-cache
    defmemo)

  (import (chezscheme))

  ;; ========== Simple Memoization ==========
  (define (memo proc)
    (let ([cache (make-hashtable equal-hash equal?)]
          [hits 0]
          [misses 0])
      (let ([wrapper
             (lambda args
               (let ([cached (hashtable-ref cache args #f)])
                 (if cached
                   (begin (set! hits (+ hits 1))
                          (cdr cached))  ; unwrap (found . value)
                   (begin (set! misses (+ misses 1))
                          (let ([result (apply proc args)])
                            (hashtable-set! cache args (cons #t result))
                            result)))))])
        (set-memo-metadata! wrapper cache
          (lambda () (values hits misses))
          (lambda () (hashtable-size cache)))
        wrapper)))

  ;; ========== LRU Memoization ==========
  (define (memo/lru max-size proc)
    (let ([cache (make-hashtable equal-hash equal?)]
          [order '()]  ; most-recent first
          [size 0]
          [hits 0]
          [misses 0])
      (let ([wrapper
             (lambda args
               (let ([cached (hashtable-ref cache args #f)])
                 (if cached
                   (begin
                     (set! hits (+ hits 1))
                     ;; Move to front
                     (set! order (cons args (remove-first args order)))
                     (cdr cached))
                   (begin
                     (set! misses (+ misses 1))
                     ;; Evict if full
                     (when (>= size max-size)
                       (let ([victim (last-element order)])
                         (hashtable-delete! cache victim)
                         (set! order (drop-last order))
                         (set! size (- size 1))))
                     (let ([result (apply proc args)])
                       (hashtable-set! cache args (cons #t result))
                       (set! order (cons args order))
                       (set! size (+ size 1))
                       result)))))])
        (set-memo-metadata! wrapper cache
          (lambda () (values hits misses))
          (lambda () size))
        wrapper)))

  ;; ========== TTL Memoization ==========
  (define (memo/ttl ttl-seconds proc)
    (let ([cache (make-hashtable equal-hash equal?)]
          [hits 0]
          [misses 0])
      (let ([wrapper
             (lambda args
               (let ([cached (hashtable-ref cache args #f)])
                 (if (and cached
                          (< (- (current-seconds) (car cached)) ttl-seconds))
                   (begin (set! hits (+ hits 1))
                          (cdr cached))
                   (begin (set! misses (+ misses 1))
                          (let ([result (apply proc args)])
                            (hashtable-set! cache args
                              (cons (current-seconds) result))
                            result)))))])
        (set-memo-metadata! wrapper cache
          (lambda () (values hits misses))
          (lambda () (hashtable-size cache)))
        wrapper)))

  ;; ========== LRU + TTL Combined ==========
  (define (memo/lru+ttl max-size ttl-seconds proc)
    (let ([cache (make-hashtable equal-hash equal?)]
          [order '()]
          [size 0]
          [hits 0]
          [misses 0])
      (let ([wrapper
             (lambda args
               (let ([cached (hashtable-ref cache args #f)])
                 (if (and cached
                          (< (- (current-seconds) (car cached)) ttl-seconds))
                   (begin
                     (set! hits (+ hits 1))
                     (set! order (cons args (remove-first args order)))
                     (cdr cached))
                   (begin
                     (set! misses (+ misses 1))
                     ;; Remove expired entry if exists
                     (when cached
                       (hashtable-delete! cache args)
                       (set! order (remove-first args order))
                       (set! size (- size 1)))
                     ;; Evict LRU if full
                     (when (>= size max-size)
                       (let ([victim (last-element order)])
                         (hashtable-delete! cache victim)
                         (set! order (drop-last order))
                         (set! size (- size 1))))
                     (let ([result (apply proc args)])
                       (hashtable-set! cache args
                         (cons (current-seconds) result))
                       (set! order (cons args order))
                       (set! size (+ size 1))
                       result)))))])
        (set-memo-metadata! wrapper cache
          (lambda () (values hits misses))
          (lambda () size))
        wrapper)))

  ;; ========== Cache Introspection ==========
  ;; We store metadata in a global weak hashtable keyed by the wrapper procedure

  (define *memo-registry* (make-eq-hashtable))

  (define (set-memo-metadata! wrapper cache stats-fn size-fn)
    (hashtable-set! *memo-registry* wrapper
      (list cache stats-fn size-fn)))

  (define (memo-clear! wrapper)
    (let ([meta (hashtable-ref *memo-registry* wrapper #f)])
      (when meta
        (hashtable-clear! (car meta)))))

  (define (memo-stats wrapper)
    ;; Returns (values hits misses hit-rate)
    (let ([meta (hashtable-ref *memo-registry* wrapper #f)])
      (if meta
        (let-values ([(hits misses) ((cadr meta))])
          (let ([total (+ hits misses)])
            (values hits misses
                    (if (= total 0) 0.0
                      (inexact (/ hits total))))))
        (values 0 0 0.0))))

  (define (memo-size wrapper)
    (let ([meta (hashtable-ref *memo-registry* wrapper #f)])
      (if meta ((caddr meta)) 0)))

  (define (memo-cache wrapper)
    ;; Return the underlying hashtable (for inspection)
    (let ([meta (hashtable-ref *memo-registry* wrapper #f)])
      (and meta (car meta))))

  ;; ========== Syntax: defmemo ==========
  (define-syntax defmemo
    (syntax-rules ()
      [(_ (name . args) body ...)
       (define name
         (memo (lambda args body ...)))]))

  ;; ========== Helpers ==========
  (define (current-seconds)
    (let ([t (current-time)])
      (+ (time-second t)
         (/ (time-nanosecond t) 1000000000.0))))

  (define (remove-first item lst)
    (cond
      [(null? lst) '()]
      [(equal? (car lst) item) (cdr lst)]
      [else (cons (car lst) (remove-first item (cdr lst)))]))

  (define (last-element lst)
    (if (null? (cdr lst)) (car lst)
      (last-element (cdr lst))))

  (define (drop-last lst)
    (if (null? (cdr lst)) '()
      (cons (car lst) (drop-last (cdr lst)))))

) ;; end library
