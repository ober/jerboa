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
    imap=? imap-hash
    in-imap in-imap-pairs in-imap-keys in-imap-values

    ;; Transient imap — mutable builder for bulk construction
    imap-transient imap-transient?
    imap-t-set! imap-t-delete! imap-t-ref imap-t-has? imap-t-size
    imap-persistent!

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
    ;; Uses a transient internally — single %pmap allocation at the end.
    (apply make-persistent-map kvs))

  ;; Transient (mutable) imap builder — re-exported from (std pmap)
  (define imap-transient transient-map)
  (define imap-transient? transient-map?)
  (define imap-t-set! tmap-set!)
  (define imap-t-delete! tmap-delete!)
  (define imap-t-ref tmap-ref)
  (define imap-t-has? tmap-has?)
  (define imap-t-size tmap-size)
  (define imap-persistent! persistent-map!)

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
  (define imap=? persistent-map=?)
  (define imap-hash persistent-map-hash)
  (define in-imap in-pmap)
  (define in-imap-pairs in-pmap-pairs)
  (define in-imap-keys in-pmap-keys)
  (define in-imap-values in-pmap-values)

  (define (hashtable->imap ht)
    ;; Convert a mutable hashtable to an immutable map.
    ;; Uses a transient for efficient bulk construction.
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let ([t (transient-map pmap-empty)])
        (let loop ([i 0])
          (if (fx= i (vector-length keys))
              (persistent-map! t)
              (begin
                (tmap-set! t (vector-ref keys i) (vector-ref vals i))
                (loop (fx+ i 1))))))))

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
