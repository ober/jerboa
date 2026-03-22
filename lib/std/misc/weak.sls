#!chezscheme
;;; (std misc weak) — Weak pairs, weak lists, and weak hash tables
;;;
;;; Builds on Chez Scheme's weak-cons, bwp-object?, and weak eq hashtables.
;;;
;;; Weak pairs hold their car weakly — the GC may reclaim it, leaving #!bwp.
;;; Weak lists are chains of weak pairs; compaction removes reclaimed entries.
;;; Weak hash tables hold keys weakly; entries vanish when keys are GC'd.

(library (std misc weak)
  (export
    ;; Weak pairs
    make-weak-pair weak-pair? weak-car weak-cdr weak-pair-value
    ;; Weak lists
    list->weak-list weak-list->list weak-list-compact!
    ;; Weak hash tables
    make-weak-hashtable weak-hashtable-ref weak-hashtable-set!
    weak-hashtable-delete! weak-hashtable-keys)
  (import (except (chezscheme) weak-pair? make-weak-hashtable))

  ;;; --- Weak pairs ---

  ;; Create a weak pair: the car is held weakly, the cdr strongly.
  (define (make-weak-pair key value)
    (weak-cons key value))

  ;; Predicate: is this a weak pair?
  (define (weak-pair? obj)
    (#3%weak-pair? obj))

  ;; Access the car of a weak pair (may be #!bwp if reclaimed).
  (define (weak-car wp)
    (assert (pair? wp))
    (car wp))

  ;; Access the cdr of a weak pair.
  (define (weak-cdr wp)
    (assert (pair? wp))
    (cdr wp))

  ;; Return the car if still live, or #f if reclaimed.
  (define (weak-pair-value wp)
    (assert (pair? wp))
    (let ([v (car wp)])
      (if (bwp-object? v) #f v)))

  ;;; --- Weak lists ---

  ;; Convert a list of values into a weak-cons chain.
  ;; Each element is the car (held weakly), the cdr links to the next pair.
  (define (list->weak-list lst)
    (if (null? lst)
        '()
        (weak-cons (car lst) (list->weak-list (cdr lst)))))

  ;; Collect all live (non-bwp) car values from a weak list.
  (define (weak-list->list wl)
    (let loop ([wl wl] [acc '()])
      (if (null? wl)
          (reverse acc)
          (let ([v (car wl)])
            (if (bwp-object? v)
                (loop (cdr wl) acc)
                (loop (cdr wl) (cons v acc)))))))

  ;; Destructively remove reclaimed entries from a weak list.
  ;; Returns the (possibly new) head of the compacted list.
  (define (weak-list-compact! wl)
    ;; Skip leading dead entries
    (let skip-head ([wl wl])
      (cond
        [(null? wl) '()]
        [(bwp-object? (car wl)) (skip-head (cdr wl))]
        [else
         ;; wl head is live; walk the rest and splice out dead entries
         (let loop ([prev wl] [cur (cdr wl)])
           (cond
             [(null? cur) (void)]
             [(bwp-object? (car cur))
              (set-cdr! prev (cdr cur))
              (loop prev (cdr cur))]
             [else
              (loop cur (cdr cur))]))
         wl])))

  ;;; --- Weak hash tables ---
  ;;;
  ;;; Keys are held weakly (eq-based). When a key is reclaimed by the GC,
  ;;; the entry is automatically removed by Chez's runtime.

  (define make-weak-hashtable
    (case-lambda
      [() (make-weak-eq-hashtable)]
      [(size) (make-weak-eq-hashtable size)]))

  (define (weak-hashtable-ref ht key default)
    (hashtable-ref ht key default))

  (define (weak-hashtable-set! ht key value)
    (hashtable-set! ht key value))

  (define (weak-hashtable-delete! ht key)
    (hashtable-delete! ht key))

  ;; Return a list of live keys (filters out any bwp entries).
  (define (weak-hashtable-keys ht)
    (let ([kvec (hashtable-keys ht)])
      (let loop ([i 0] [acc '()])
        (if (fx>= i (vector-length kvec))
            acc
            (let ([k (vector-ref kvec i)])
              (if (bwp-object? k)
                  (loop (fx+ i 1) acc)
                  (loop (fx+ i 1) (cons k acc))))))))

) ;; end library
