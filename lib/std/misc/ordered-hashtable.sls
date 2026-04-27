#!chezscheme
;;; (std misc ordered-hashtable) — Insertion-ordered hash tables
;;;
;;; Thin wrapper exposing Chez core ordered-hashtable (Phase 68, Round 12 —
;;; landed 2026-04-26 in ChezScheme).  Keys preserve insertion order across
;;; ref / set! / delete! / clear! and are walked in that order by
;;; ordered-hashtable-walk and ordered-hashtable-keys/values/entries/cells.
;;;
;;; Use cases: HTTP header tables, YAML mappings, JSON object preservation,
;;; LRU eviction queues, deterministic test fixtures.
;;;
;;; This is a distinct Chez record type from R6RS hashtables — predicates
;;; like (hashtable? oht) return #f, so don't substitute it blindly into
;;; APIs that consume eq-/eqv-hashtables.

(library (std misc ordered-hashtable)
  (export
    make-ordered-hashtable        ;; (hashfn equiv) → oht (eq-comparable: pass eq? eqv? equal?)
    make-string-ordered-hashtable ;; convenience: string-hash + string=?
    make-eq-ordered-hashtable     ;; convenience: eq-style ordered table
    ordered-hashtable?
    ordered-hashtable-size
    ordered-hashtable-ref
    ordered-hashtable-contains?
    ordered-hashtable-set!
    ordered-hashtable-delete!
    ordered-hashtable-update!
    ordered-hashtable-clear!
    ordered-hashtable-keys
    ordered-hashtable-values
    ordered-hashtable-entries
    ordered-hashtable-cells
    ordered-hashtable-copy
    ordered-hashtable-walk
    ordered-hashtable->alist
    alist->ordered-hashtable)

  (import (chezscheme))

  (define (make-string-ordered-hashtable)
    (make-ordered-hashtable string-hash string=?))

  (define (make-eq-ordered-hashtable)
    ;; eq? has no separate hash fn; equal-hash on identity works.
    (make-ordered-hashtable equal-hash eq?))

  (define (ordered-hashtable->alist oht)
    ;; Returns list of (key . value) pairs in insertion order.
    (let-values ([(keys vals) (ordered-hashtable-entries oht)])
      (let ([n (vector-length keys)])
        (let loop ([i 0] [acc '()])
          (if (fx= i n)
            (reverse acc)
            (loop (fx+ i 1)
                  (cons (cons (vector-ref keys i) (vector-ref vals i))
                        acc)))))))

  (define (alist->ordered-hashtable alist . hash/equiv)
    ;; (alist->ordered-hashtable alist)              uses string-hash/string=?
    ;; (alist->ordered-hashtable alist hashfn equiv) for custom keys
    (let ([oht (cond
                 [(null? hash/equiv) (make-string-ordered-hashtable)]
                 [(null? (cdr hash/equiv))
                  (error 'alist->ordered-hashtable
                    "must pass both hashfn and equiv-fn or neither")]
                 [else (make-ordered-hashtable
                         (car hash/equiv) (cadr hash/equiv))])])
      (for-each (lambda (pair)
                  (ordered-hashtable-set! oht (car pair) (cdr pair)))
                alist)
      oht))

  ) ;; end library
