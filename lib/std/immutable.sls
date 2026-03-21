#!chezscheme
;;; (std immutable) — Immutable-by-default data structures
;;;
;;; Re-exports persistent map and vector as the primary data structure API.
;;; Functional updates return new values; originals are never mutated.
;;; This prevents accidental mutation bugs in Claude-generated code.
;;;
;;; Usage:
;;;   (import (std immutable))
;;;
;;;   ;; Immutable hash map (HAMT)
;;;   (define m (imap "name" "Alice" "age" 30))
;;;   (define m2 (imap-set m "age" 31))    ;; m unchanged, m2 has age=31
;;;   (imap-ref m "name")                  ;; => "Alice"
;;;
;;;   ;; Immutable vector (persistent trie)
;;;   (define v (ivec 1 2 3))
;;;   (define v2 (ivec-set v 0 99))        ;; v unchanged, v2 = #(99 2 3)
;;;   (define v3 (ivec-append v 4))        ;; v3 = #(1 2 3 4)

(library (std immutable)
  (export
    ;; Immutable map (pmap wrappers with short names)
    imap
    imap-empty
    imap?
    imap-ref
    imap-has?
    imap-set
    imap-delete
    imap-size
    imap->alist
    imap-keys
    imap-values
    imap-for-each
    imap-map
    imap-fold
    imap-filter
    imap-merge

    ;; Immutable vector (pvec wrappers with short names)
    ivec
    ivec-empty
    ivec?
    ivec-ref
    ivec-set
    ivec-append
    ivec-length
    ivec->list
    ivec-for-each
    ivec-map
    ivec-fold
    ivec-filter
    ivec-concat
    ivec-slice

    ;; Conversion from mutable
    hashtable->imap
    vector->ivec
    list->ivec

    ;; Re-export full APIs for advanced use
    persistent-map?
    persistent-vector?)

  (import (chezscheme)
          (std pmap)
          (std pvec))

  ;; =========================================================================
  ;; Immutable Map — short aliases for persistent-map
  ;; =========================================================================

  (define imap-empty pmap-empty)

  (define imap? persistent-map?)

  (define (imap . kvs)
    ;; Construct from alternating key/value pairs:
    ;; (imap "a" 1 "b" 2) => {"a": 1, "b": 2}
    (let loop ([pairs kvs] [m imap-empty])
      (cond
        [(null? pairs) m]
        [(null? (cdr pairs))
         (error 'imap "odd number of arguments — expected key/value pairs")]
        [else
         (loop (cddr pairs)
               (persistent-map-set m (car pairs) (cadr pairs)))])))

  (define (imap-ref m key . default)
    (if (null? default)
        (persistent-map-ref m key)
        (persistent-map-ref m key (car default))))

  (define imap-has? persistent-map-has?)
  (define imap-set persistent-map-set)
  (define imap-delete persistent-map-delete)
  (define imap-size persistent-map-size)
  (define imap->alist persistent-map->list)
  (define imap-keys persistent-map-keys)
  (define imap-values persistent-map-values)
  (define imap-for-each persistent-map-for-each)
  (define imap-map persistent-map-map)
  (define imap-fold persistent-map-fold)
  (define imap-filter persistent-map-filter)
  (define imap-merge persistent-map-merge)

  (define (hashtable->imap ht)
    ;; Convert a mutable hashtable to an immutable map.
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let loop ([i 0] [m imap-empty])
        (if (fx= i (vector-length keys))
            m
            (loop (fx+ i 1)
                  (persistent-map-set m
                    (vector-ref keys i)
                    (vector-ref vals i)))))))

  ;; =========================================================================
  ;; Immutable Vector — short aliases for persistent-vector
  ;; =========================================================================

  (define ivec-empty pvec-empty)

  (define ivec? persistent-vector?)

  (define (ivec . items)
    ;; Construct from arguments: (ivec 1 2 3)
    (list->persistent-vector items))

  (define ivec-ref persistent-vector-ref)
  (define ivec-set persistent-vector-set)
  (define ivec-append persistent-vector-append)
  (define ivec-length persistent-vector-length)
  (define ivec->list persistent-vector->list)
  (define ivec-for-each persistent-vector-for-each)
  (define ivec-map persistent-vector-map)
  (define ivec-fold persistent-vector-fold)
  (define ivec-filter persistent-vector-filter)
  (define ivec-concat persistent-vector-concat)
  (define ivec-slice persistent-vector-slice)

  (define (vector->ivec vec)
    ;; Convert a mutable vector to an immutable vector.
    (list->persistent-vector (vector->list vec)))

  (define list->ivec list->persistent-vector)

) ;; end library
