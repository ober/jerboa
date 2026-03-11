#!chezscheme
;;; (std actor crdt) — Conflict-Free Replicated Data Types
;;;
;;; Step 30: CRDT-Based Distributed State
;;;
;;; CRDTs are data types that can be concurrently updated by multiple nodes
;;; and then merged without conflict. The merge operation (join) is:
;;;   - Commutative: merge(a, b) = merge(b, a)
;;;   - Associative: merge(a, merge(b, c)) = merge(merge(a, b), c)
;;;   - Idempotent:  merge(a, a) = a
;;;
;;; Implemented types:
;;;   G-Counter     — grow-only counter (increment only)
;;;   PN-Counter    — positive-negative counter (increment and decrement)
;;;   OR-Set        — observed-remove set (add/remove without tombstones)
;;;   LWW-Register  — last-write-wins register (timestamp-based)
;;;   MV-Register   — multi-value register (vector-clock-based, concurrent writes preserved)
;;;   G-Set         — grow-only set (add only)

(library (std actor crdt)
  (export
    ;; G-Counter
    make-gcounter
    gcounter?
    gcounter-increment!
    gcounter-value
    gcounter-merge!
    gcounter-state

    ;; PN-Counter
    make-pncounter
    pncounter?
    pncounter-increment!
    pncounter-decrement!
    pncounter-value
    pncounter-merge!

    ;; G-Set
    make-gset
    gset?
    gset-add!
    gset-member?
    gset-value
    gset-merge!

    ;; OR-Set
    make-orset
    orset?
    orset-add!
    orset-remove!
    orset-member?
    orset-value
    orset-merge!

    ;; LWW-Register
    make-lww-register
    lww-register?
    lww-register-set!
    lww-register-value
    lww-register-timestamp
    lww-register-merge!

    ;; MV-Register
    make-mv-register
    mv-register?
    mv-register-set!
    mv-register-values   ;; returns list of concurrent values
    mv-register-merge!

    ;; Vector clock utilities
    make-vclock
    vclock?
    vclock-increment!
    vclock-get
    vclock-merge!
    vclock-happens-before?
    vclock-concurrent?
    vclock->alist)

  (import (chezscheme))

  ;; ========== Utilities ==========

  ;; new-uuid is replaced by new-tag below — not used directly

  ;; Better unique tag generator using random + time
  (define *tag-counter* 0)
  (define *tag-mutex* (make-mutex))
  (define (new-tag)
    (with-mutex *tag-mutex*
      (set! *tag-counter* (+ *tag-counter* 1))
      (format "~a:~a" (time-second (current-time)) *tag-counter*)))

  (define (alist-merge a b merge-val)
    ;; Merge two alists, applying merge-val to values for shared keys
    (let loop ([b b] [result a])
      (if (null? b)
        result
        (let* ([kv (car b)]
               [k  (car kv)]
               [v  (cdr kv)]
               [existing (assoc k result)])
          (if existing
            (loop (cdr b)
              (cons (cons k (merge-val (cdr existing) v))
                    (filter (lambda (x) (not (equal? (car x) k))) result)))
            (loop (cdr b) (cons kv result)))))))

  ;; ========== Vector Clock ==========

  ;; Vector clock: eq-hashtable mapping node-id → integer count
  (define-record-type (vclock make-vclock-raw vclock?)
    (fields (immutable clock vclock-clock)))

  (define (make-vclock)
    (make-vclock-raw (make-eq-hashtable)))

  (define (vclock-increment! vc node-id)
    (let ([c (vclock-clock vc)])
      (hashtable-set! c node-id
        (+ 1 (hashtable-ref c node-id 0)))))

  (define (vclock-get vc node-id)
    (hashtable-ref (vclock-clock vc) node-id 0))

  (define (vclock-merge! target other)
    ;; Merge other into target by taking max of each component
    (let-values ([(keys vals) (hashtable-entries (vclock-clock other))])
      (vector-for-each
        (lambda (k v)
          (let ([current (hashtable-ref (vclock-clock target) k 0)])
            (when (> v current)
              (hashtable-set! (vclock-clock target) k v))))
        keys vals)))

  (define (vclock-happens-before? a b)
    ;; a happens-before b: every entry in a ≤ corresponding in b, and at least one <
    (let-values ([(keys-a vals-a) (hashtable-entries (vclock-clock a))])
      (let ([has-strict #f]
            [all-leq #t])
        (vector-for-each
          (lambda (k va)
            (let ([vb (vclock-get b k)])
              (when (> va vb) (set! all-leq #f))
              (when (< va vb) (set! has-strict #t))))
          keys-a vals-a)
        ;; Also check any keys only in b
        (and all-leq
             (or has-strict
                 (let-values ([(keys-b _) (hashtable-entries (vclock-clock b))])
                   (vector-any
                     (lambda (k)
                       (let ([va (vclock-get a k)]
                             [vb (vclock-get b k)])
                         (> vb va)))
                     keys-b)))))))

  (define (vector-any pred vec)
    (let loop ([i 0])
      (cond
        [(= i (vector-length vec)) #f]
        [(pred (vector-ref vec i)) #t]
        [else (loop (+ i 1))])))

  (define (vclock-concurrent? a b)
    ;; Concurrent: neither happens-before the other
    (not (or (vclock-happens-before? a b)
             (vclock-happens-before? b a)
             (vclock-equal? a b))))

  (define (vclock-equal? a b)
    (let-values ([(keys-a vals-a) (hashtable-entries (vclock-clock a))]
                 [(keys-b vals-b) (hashtable-entries (vclock-clock b))])
      (and (= (vector-length keys-a) (vector-length keys-b))
           (vector-for-all
             (lambda (k v)
               (= v (vclock-get b k)))
             keys-a vals-a))))

  (define (vector-for-all pred . vecs)
    (let ([len (vector-length (car vecs))])
      (let loop ([i 0])
        (cond
          [(= i len) #t]
          [(apply pred (map (lambda (v) (vector-ref v i)) vecs))
           (loop (+ i 1))]
          [else #f]))))

  (define (vclock->alist vc)
    (let-values ([(keys vals) (hashtable-entries (vclock-clock vc))])
      (map cons (vector->list keys) (vector->list vals))))

  ;; ========== G-Counter ==========
  ;;
  ;; Grow-only counter. Each node has its own counter.
  ;; Value = sum of all node counters.
  ;; Merge = pairwise max.

  (define-record-type (gcounter make-gcounter-raw gcounter?)
    (fields (immutable node-id gcounter-node-id)
            (immutable counts gcounter-counts)  ;; eq-hashtable: node-id → count
            (immutable mutex  gcounter-mutex)))

  (define (make-gcounter node-id)
    (let ([ht (make-eq-hashtable)])
      (hashtable-set! ht node-id 0)
      (make-gcounter-raw node-id ht (make-mutex))))

  (define (gcounter-increment! gc . args)
    (let ([amount (if (null? args) 1 (car args))])
      (with-mutex (gcounter-mutex gc)
        (let ([node (gcounter-node-id gc)])
          (hashtable-set! (gcounter-counts gc) node
            (+ amount (hashtable-ref (gcounter-counts gc) node 0)))))))

  (define (gcounter-value gc)
    (with-mutex (gcounter-mutex gc)
      (let-values ([(keys vals) (hashtable-entries (gcounter-counts gc))])
        (vector-fold-right + 0 vals))))

  (define (vector-fold-right f init vec)
    (let loop ([i 0] [acc init])
      (if (= i (vector-length vec))
        acc
        (loop (+ i 1) (f (vector-ref vec i) acc)))))

  (define (gcounter-state gc)
    (with-mutex (gcounter-mutex gc)
      (let-values ([(keys vals) (hashtable-entries (gcounter-counts gc))])
        (map cons (vector->list keys) (vector->list vals)))))

  (define (gcounter-merge! target other)
    ;; Merge other's counts into target by taking pairwise max
    (with-mutex (gcounter-mutex target)
      (let-values ([(keys vals) (hashtable-entries (gcounter-counts other))])
        (vector-for-each
          (lambda (k v)
            (let ([current (hashtable-ref (gcounter-counts target) k 0)])
              (when (> v current)
                (hashtable-set! (gcounter-counts target) k v))))
          keys vals))))

  ;; ========== PN-Counter ==========
  ;;
  ;; Positive-Negative counter: two G-Counters (positive, negative).
  ;; Value = pos.value - neg.value
  ;; Merge = merge both G-Counters separately

  (define-record-type (pncounter make-pncounter-raw pncounter?)
    (fields (immutable node-id  pncounter-node-id)
            (immutable positive pncounter-positive)
            (immutable negative pncounter-negative)))

  (define (make-pncounter node-id)
    (make-pncounter-raw node-id
      (make-gcounter node-id)
      (make-gcounter node-id)))

  (define (pncounter-increment! pnc . args)
    (gcounter-increment! (pncounter-positive pnc)
      (if (null? args) 1 (car args))))

  (define (pncounter-decrement! pnc . args)
    (gcounter-increment! (pncounter-negative pnc)
      (if (null? args) 1 (car args))))

  (define (pncounter-value pnc)
    (- (gcounter-value (pncounter-positive pnc))
       (gcounter-value (pncounter-negative pnc))))

  (define (pncounter-merge! target other)
    (gcounter-merge! (pncounter-positive target) (pncounter-positive other))
    (gcounter-merge! (pncounter-negative target) (pncounter-negative other)))

  ;; ========== G-Set ==========
  ;;
  ;; Grow-only set. Elements can only be added, never removed.
  ;; Merge = set union.

  (define-record-type (gset make-gset-raw gset?)
    (fields (immutable elements gset-elements)  ;; hashtable: elem → #t
            (immutable mutex    gset-mutex)))

  (define (make-gset)
    (make-gset-raw (make-hashtable equal-hash equal?) (make-mutex)))

  (define (gset-add! gs elem)
    (with-mutex (gset-mutex gs)
      (hashtable-set! (gset-elements gs) elem #t)))

  (define (gset-member? gs elem)
    (with-mutex (gset-mutex gs)
      (hashtable-ref (gset-elements gs) elem #f)))

  (define (gset-value gs)
    (with-mutex (gset-mutex gs)
      (let-values ([(keys _) (hashtable-entries (gset-elements gs))])
        (vector->list keys))))

  (define (gset-merge! target other)
    (with-mutex (gset-mutex target)
      (let-values ([(keys vals) (hashtable-entries (gset-elements other))])
        (vector-for-each
          (lambda (k v)
            (hashtable-set! (gset-elements target) k v))
          keys vals))))

  ;; ========== OR-Set ==========
  ;;
  ;; Observed-Remove Set. Each element is tagged with unique IDs.
  ;; Add: add (elem, tag) to 'added' set.
  ;; Remove: remove all tags for elem from 'added' set.
  ;; Member: elem has at least one tag in 'added' not in 'removed'.
  ;; Merge: union of added sets, union of removed sets.

  (define-record-type (orset make-orset-raw orset?)
    (fields (immutable added   orset-added)    ;; hashtable: (elem . tag) → #t
            (immutable removed orset-removed)  ;; hashtable: (elem . tag) → #t
            (immutable mutex   orset-mutex)))

  (define (make-orset)
    (make-orset-raw (make-hashtable equal-hash equal?) (make-hashtable equal-hash equal?) (make-mutex)))

  (define (orset-add! os elem)
    (with-mutex (orset-mutex os)
      (let ([tag (new-tag)])
        (hashtable-set! (orset-added os) (cons elem tag) #t))))

  (define (orset-remove! os elem)
    (with-mutex (orset-mutex os)
      ;; Move all tags for this element from added to removed
      (let-values ([(pairs _) (hashtable-entries (orset-added os))])
        (vector-for-each
          (lambda (pair)
            (when (equal? (car pair) elem)
              (hashtable-delete! (orset-added os) pair)
              (hashtable-set! (orset-removed os) pair #t)))
          pairs))))

  (define (orset-member? os elem)
    (with-mutex (orset-mutex os)
      (let-values ([(pairs _) (hashtable-entries (orset-added os))])
        (vector-any
          (lambda (pair) (equal? (car pair) elem))
          pairs))))

  (define (orset-value os)
    (with-mutex (orset-mutex os)
      (let ([seen (make-hashtable equal-hash equal?)])
        (let-values ([(pairs _) (hashtable-entries (orset-added os))])
          (vector-for-each
            (lambda (pair)
              (hashtable-set! seen (car pair) #t))
            pairs))
        (let-values ([(elems _) (hashtable-entries seen)])
          (vector->list elems)))))

  (define (orset-merge! target other)
    ;; Union of added, union of removed, then subtract removed from added
    (with-mutex (orset-mutex target)
      ;; Union removed
      (let-values ([(pairs _) (hashtable-entries (orset-removed other))])
        (vector-for-each
          (lambda (pair)
            (hashtable-set! (orset-removed target) pair #t))
          pairs))
      ;; Union added (not already removed)
      (let-values ([(pairs _) (hashtable-entries (orset-added other))])
        (vector-for-each
          (lambda (pair)
            (unless (hashtable-ref (orset-removed target) pair #f)
              (hashtable-set! (orset-added target) pair #t)))
          pairs))
      ;; Remove any added entries that are in removed
      (let-values ([(pairs _) (hashtable-entries (orset-removed target))])
        (vector-for-each
          (lambda (pair)
            (hashtable-delete! (orset-added target) pair))
          pairs))))

  ;; ========== LWW-Register ==========
  ;;
  ;; Last-Write-Wins Register. Stores a single value with a timestamp.
  ;; On merge, the higher-timestamp value wins.

  (define-record-type (lww-register make-lww-raw lww-register?)
    (fields (mutable value     lww-value     lww-set-value!)
            (mutable timestamp lww-timestamp lww-set-timestamp!)
            (immutable mutex   lww-mutex)))

  (define (make-lww-register)
    (make-lww-raw #f -inf.0 (make-mutex)))

  (define (lww-register-value r)
    (with-mutex (lww-mutex r) (lww-value r)))

  (define (lww-register-timestamp r)
    (with-mutex (lww-mutex r) (lww-timestamp r)))

  (define (lww-register-set! r val . args)
    (let ([ts (if (null? args)
                (inexact (time-second (current-time)))
                (car args))])
      (with-mutex (lww-mutex r)
        (when (> ts (lww-timestamp r))
          (lww-set-value! r val)
          (lww-set-timestamp! r ts)))))

  (define (lww-register-merge! target other)
    (with-mutex (lww-mutex target)
      (let ([other-ts (lww-timestamp other)]
            [other-val (lww-value other)])
        (when (> other-ts (lww-timestamp target))
          (lww-set-value! target other-val)
          (lww-set-timestamp! target other-ts)))))

  ;; ========== MV-Register ==========
  ;;
  ;; Multi-Value Register. Uses vector clocks to track causality.
  ;; Concurrent writes are both preserved (unlike LWW which picks one).
  ;; Reading returns a list of all concurrent values.

  (define-record-type (mv-register make-mv-raw mv-register?)
    (fields (mutable entries  mv-entries  mv-set-entries!)  ;; list of (vclock . value)
            (immutable mutex  mv-mutex)))

  (define (make-mv-register)
    (make-mv-raw '() (make-mutex)))

  (define (mv-register-values r)
    (with-mutex (mv-mutex r)
      (map cdr (mv-entries r))))

  (define (mv-register-set! r node-id val)
    (with-mutex (mv-mutex r)
      ;; Create new vector clock by merging all current clocks and incrementing
      (let ([new-vc (make-vclock)])
        ;; Merge all current vector clocks
        (for-each
          (lambda (entry)
            (vclock-merge! new-vc (car entry)))
          (mv-entries r))
        ;; Increment for this node
        (vclock-increment! new-vc node-id)
        ;; Replace all entries dominated by new-vc with single new entry
        (let ([surviving
               (filter
                 (lambda (entry)
                   ;; Keep if not dominated by new-vc
                   (not (vclock-happens-before? (car entry) new-vc)))
                 (mv-entries r))])
          (mv-set-entries! r (cons (cons new-vc val) surviving))))))

  (define (mv-register-merge! target other)
    (with-mutex (mv-mutex target)
      (let ([target-entries (mv-entries target)]
            [other-entries  (mv-entries other)])
        ;; Merge: keep entries not dominated by any entry in the other set
        (let* ([all (append target-entries other-entries)]
               [merged
                (filter
                  (lambda (e1)
                    (not (exists
                           (lambda (e2)
                             (and (not (eq? e1 e2))
                                  (vclock-happens-before? (car e1) (car e2))))
                           all)))
                  all)])
          (mv-set-entries! target merged)))))

  ) ;; end library
