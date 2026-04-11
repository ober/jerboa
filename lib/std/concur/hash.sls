#!chezscheme
;;; (std concur hash) — Thread-safe concurrent hash table
;;;
;;; A concurrent hash table for multi-threaded code. Uses a persistent
;;; HAMT (std pmap) inside a shared cell (std misc shared). Writers
;;; serialize through a mutex; readers grab a snapshot pointer and
;;; query the immutable underlying map — no lock contention on reads.
;;;
;;; Why not a plain (make-hash-table) with a mutex? Chez's hash tables
;;; are not safe under concurrent mutation — empirical testing in
;;; jerboa-code showed ~35% of hash-put! calls silently dropped, and
;;; torn bucket writes can create cyclic chains that hang readers.
;;; A persistent HAMT behind an atomic cell has no shared mutable links,
;;; so those classes of bug are impossible by construction.
;;;
;;; Usage:
;;;   (import (std concur hash))
;;;   (define h (make-concurrent-hash))
;;;   (concurrent-hash-put! h "alice" alice-record)
;;;   (concurrent-hash-get  h "alice")
;;;   (concurrent-hash-update! h "counter" (lambda (n) (+ (or n 0) 1)))
;;;
;;;   ;; Multi-key atomic update — hand the whole pmap to a function:
;;;   (concurrent-hash-swap! h
;;;     (lambda (m) (persistent-map-filter (lambda (k v) (active? v)) m)))
;;;
;;;   ;; Iterate without holding a lock:
;;;   (concurrent-hash-for-each
;;;     (lambda (k v) (displayln k " => " v))
;;;     h)
;;;
;;; Naming: "concurrent-hash" matches Java's ConcurrentHashMap and
;;; C#'s ConcurrentDictionary. "chash-*" short aliases are also exported
;;; for ergonomics.

(library (std concur hash)
  (export
    ;; ---- Full names (Java ConcurrentHashMap style) ----
    make-concurrent-hash
    concurrent-hash
    concurrent-hash?
    concurrent-hash-get
    concurrent-hash-ref
    concurrent-hash-put!
    concurrent-hash-remove!
    concurrent-hash-update!
    concurrent-hash-key?
    concurrent-hash-size
    concurrent-hash-keys
    concurrent-hash-values
    concurrent-hash->list
    concurrent-hash-for-each
    concurrent-hash-clear!
    concurrent-hash-snapshot
    concurrent-hash-swap!
    concurrent-hash-merge!

    ;; ---- Short aliases (chash-*) ----
    make-chash
    chash
    chash?
    chash-get
    chash-ref
    chash-put!
    chash-remove!
    chash-update!
    chash-key?
    chash-size
    chash-keys
    chash-values
    chash->list
    chash-for-each
    chash-clear!
    chash-snapshot
    chash-swap!
    chash-merge!)

  (import (chezscheme)
          (std pmap)
          (std misc shared))

  ;; Opaque record wrapping a shared cell that holds a persistent-map.
  ;; All mutation routes through shared-update! (serialized via mutex);
  ;; reads route through shared-ref and operate on the immutable pmap.
  (define-record-type %chash
    (fields (immutable cell))
    (sealed #t))

  (define (make-concurrent-hash)
    (make-%chash (make-shared pmap-empty)))

  (define (concurrent-hash . kvs)
    ;; Literal constructor: (concurrent-hash "a" 1 "b" 2) → chash {"a":1,"b":2}
    (let loop ([pairs kvs] [m pmap-empty])
      (cond
        [(null? pairs) (make-%chash (make-shared m))]
        [(null? (cdr pairs))
         (error 'concurrent-hash
                "odd number of arguments — expected key/value pairs"
                kvs)]
        [else
         (loop (cddr pairs)
               (persistent-map-set m (car pairs) (cadr pairs)))])))

  (define (concurrent-hash? x) (%chash? x))

  ;; =========================================================================
  ;; Reads — grab snapshot pointer, query the immutable pmap
  ;; =========================================================================

  (define (concurrent-hash-get ch key . default)
    ;; Returns value, or default (or #f if no default given).
    (let ([m (shared-ref (%chash-cell ch))])
      (cond
        [(null? default) (persistent-map-ref m key (lambda () #f))]
        [else (persistent-map-ref m key (lambda () (car default)))])))

  (define (concurrent-hash-ref ch key . default)
    ;; Like -get but raises on missing key unless a default is provided.
    (let ([m (shared-ref (%chash-cell ch))])
      (cond
        [(null? default) (persistent-map-ref m key)]
        [else (persistent-map-ref m key (lambda () (car default)))])))

  (define (concurrent-hash-key? ch key)
    (persistent-map-has? (shared-ref (%chash-cell ch)) key))

  (define (concurrent-hash-size ch)
    (persistent-map-size (shared-ref (%chash-cell ch))))

  (define (concurrent-hash-keys ch)
    (persistent-map-keys (shared-ref (%chash-cell ch))))

  (define (concurrent-hash-values ch)
    (persistent-map-values (shared-ref (%chash-cell ch))))

  (define (concurrent-hash->list ch)
    (persistent-map->list (shared-ref (%chash-cell ch))))

  (define (concurrent-hash-for-each proc ch)
    ;; Iterate on a lock-free snapshot. Safe to walk even while other
    ;; threads mutate — you see a consistent view of one point in time.
    (persistent-map-for-each proc (shared-ref (%chash-cell ch))))

  (define (concurrent-hash-snapshot ch)
    ;; Returns the underlying persistent-map. Immutable, so safe to
    ;; hand off to another thread for long iteration / analysis.
    (shared-ref (%chash-cell ch)))

  ;; =========================================================================
  ;; Writes — all serialized through shared-update!
  ;; =========================================================================

  (define (concurrent-hash-put! ch key val)
    (shared-update! (%chash-cell ch)
      (lambda (m) (persistent-map-set m key val)))
    (void))

  (define (concurrent-hash-remove! ch key)
    (shared-update! (%chash-cell ch)
      (lambda (m) (persistent-map-delete m key)))
    (void))

  (define (concurrent-hash-update! ch key proc . default)
    ;; Atomic read-modify-write:
    ;;   (proc old-val) → new-val, where old-val is the current value
    ;;   for `key`, or the default (or #f if no default given).
    ;; The whole read-modify-write happens under the cell's mutex,
    ;; so no lost updates even under contention.
    (shared-update! (%chash-cell ch)
      (lambda (m)
        (let* ([default-val (if (null? default) #f (car default))]
               [old (persistent-map-ref m key (lambda () default-val))])
          (persistent-map-set m key (proc old)))))
    (void))

  (define (concurrent-hash-clear! ch)
    (shared-update! (%chash-cell ch) (lambda (_) pmap-empty))
    (void))

  (define (concurrent-hash-swap! ch proc)
    ;; Multi-key atomic update. proc takes the whole persistent-map
    ;; and returns a new one. Serialized under the cell's mutex.
    (shared-update! (%chash-cell ch) proc)
    (void))

  (define (concurrent-hash-merge! ch other)
    ;; Merge another concurrent-hash (or a persistent-map) into this one.
    ;; On conflict, values from `other` win (right-wins semantics).
    (let ([other-map
           (cond
             [(%chash? other) (shared-ref (%chash-cell other))]
             [(persistent-map? other) other]
             [else (error 'concurrent-hash-merge!
                          "expected concurrent-hash or persistent-map"
                          other)])])
      (shared-update! (%chash-cell ch)
        (lambda (m) (persistent-map-merge m other-map))))
    (void))

  ;; =========================================================================
  ;; Short aliases (chash-*)
  ;; =========================================================================

  (define make-chash        make-concurrent-hash)
  (define chash             concurrent-hash)
  (define chash?            concurrent-hash?)
  (define chash-get         concurrent-hash-get)
  (define chash-ref         concurrent-hash-ref)
  (define chash-put!        concurrent-hash-put!)
  (define chash-remove!     concurrent-hash-remove!)
  (define chash-update!     concurrent-hash-update!)
  (define chash-key?        concurrent-hash-key?)
  (define chash-size        concurrent-hash-size)
  (define chash-keys        concurrent-hash-keys)
  (define chash-values      concurrent-hash-values)
  (define chash->list       concurrent-hash->list)
  (define chash-for-each    concurrent-hash-for-each)
  (define chash-clear!      concurrent-hash-clear!)
  (define chash-snapshot    concurrent-hash-snapshot)
  (define chash-swap!       concurrent-hash-swap!)
  (define chash-merge!      concurrent-hash-merge!)

) ;; end library
