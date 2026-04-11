#!chezscheme
;;; (std transducer) — Composable, efficient data transformations
;;;
;;; A transducer is a function xf :: rf -> rf', where rf is a
;;; reducing function with three arities:
;;;
;;;   (rf)           — init: return initial accumulator
;;;   (rf acc)       — completion: flush / finalize
;;;   (rf acc item)  — step: fold one item into accumulator
;;;
;;; Transducers are composable via compose-transducers (left-to-right
;;; data flow, right-to-left function composition, matching Clojure
;;; convention).
;;;
;;; API:
;;;   Core transducers:
;;;     (mapping f)           — transform each element
;;;     (filtering pred)      — keep elements satisfying pred
;;;     (taking n)            — keep first n elements
;;;     (dropping n)          — drop first n elements
;;;     (flat-mapping f)      — map then flatten one level
;;;     (taking-while pred)   — take while pred holds
;;;     (dropping-while pred) — drop while pred holds
;;;     (cat)                 — flatten one level of nesting
;;;     (deduplicate)         — remove consecutive duplicates
;;;     (partitioning-by f)   — group into runs with same (f item)
;;;     (windowing n)         — sliding windows of size n
;;;     (indexing)            — pair each element with its 0-based index
;;;     (enumerating)         — alias for indexing
;;;
;;;   Composition:
;;;     (compose-transducers xf1 xf2 ...)
;;;     (xf-compose xf1 xf2 ...)         — alias
;;;
;;;   Reduction:
;;;     (transduce xf rf init coll)
;;;
;;;   Common reducing functions:
;;;     (rf-cons)       — build list (reversed during reduction, corrected at completion)
;;;     (rf-append!)    — build list efficiently with pair pointer
;;;     (rf-count)      — count elements
;;;     (rf-sum)        — sum numbers
;;;     (rf-into-vector)— collect into a vector (via list then list->vector)
;;;
;;;   High-level:
;;;     (into dest xf coll)   — transduce into dest (list, vector, or string)
;;;     (sequence xf coll)    — returns a list
;;;     (eduction xf coll)    — lazy composable sequence (represented as thunk)

(library (std transducer)
  (export
    ;; Record predicate (make-transducer is intentionally not exported —
    ;; transducers are just procedures; the record wraps them for identity.)
    transducer?

    ;; Reduced sentinel (exposed so users and other libraries
    ;; can signal early termination in custom reducing functions)
    reduced reduced? unreduced

    ;; Core transducers
    mapping
    filtering
    taking
    dropping
    flat-mapping
    taking-while
    dropping-while
    cat
    deduplicate
    partitioning-by
    windowing
    indexing
    enumerating

    ;; Composition
    compose-transducers
    xf-compose

    ;; Reduction
    transduce

    ;; Reducing functions
    rf-cons
    rf-append!
    rf-count
    rf-sum
    rf-into-vector
    rf-into-pmap
    rf-into-pset
    rf-into-pvec

    ;; High-level combinators
    into
    sequence
    eduction)

  (import (chezscheme)
          (std pmap)
          (std pset)
          (rename (std pvec)
                  (transient         pvec-transient)
                  (transient?        pvec-transient?)
                  (persistent!       pvec-persistent!)
                  (transient-append! pvec-t-append!)))

  ;; ======================================================================
  ;; Transducer record
  ;; A thin wrapper around a transformer function so transducer? works.
  ;; ======================================================================

  (define-record-type xducer
    (fields (immutable fn))
    (sealed #t))

  (define (transducer? x) (xducer? x))

  ;; Internal: apply a transducer to a reducing function
  (define (apply-xf xf rf)
    ((xducer-fn xf) rf))

  ;; ======================================================================
  ;; Reduced sentinel
  ;; When a reducing function wants to short-circuit (e.g. taking),
  ;; it wraps the accumulator in a reduced box.
  ;; ======================================================================

  (define-record-type reduced-box
    (fields (immutable val))
    (sealed #t))

  (define (reduced x) (make-reduced-box x))
  (define (reduced? x) (reduced-box? x))
  (define (unreduced x)
    (if (reduced-box? x) (reduced-box-val x) x))

  ;; Ensure result is unwrapped at the top level
  (define (ensure-unreduced x)
    (if (reduced-box? x) (reduced-box-val x) x))

  ;; ======================================================================
  ;; Reducing function helpers
  ;; ======================================================================

  ;; A reducing function (rf) is a procedure of 0, 1, or 2 arguments.
  ;; We represent it as a case-lambda.

  ;; Collect items into a list (constructed in reverse, reversed at completion)
  (define (rf-cons)
    (case-lambda
      [()       '()]
      [(acc)    (reverse acc)]
      [(acc x)  (cons x acc)]))

  ;; Efficient list builder using a mutable tail pointer
  ;; Internal state: a pair (head-sentinel . last-pair)
  (define (rf-append!)
    (case-lambda
      [()
       ;; init: sentinel cons cell; tail points to it
       (let ([sentinel (list 'sentinel)])
         (cons sentinel sentinel))]
      [(state)
       ;; completion: return everything after sentinel
       (cdr (car state))]
      [(state x)
       ;; step: append x to the end via tail pointer
       (let* ([new-pair (list x)]
              [tail     (cdr state)])
         (set-cdr! tail new-pair)
         (cons (car state) new-pair))]))

  ;; Count items
  (define (rf-count)
    (case-lambda
      [()      0]
      [(acc)   acc]
      [(acc _) (+ acc 1)]))

  ;; Sum numbers
  (define (rf-sum)
    (case-lambda
      [()      0]
      [(acc)   acc]
      [(acc x) (+ acc x)]))

  ;; Collect into a vector (builds a list, converts at completion)
  (define (rf-into-vector)
    (let ([inner (rf-cons)])
      (case-lambda
        [()      (inner)]
        [(acc)   (list->vector (inner acc))]
        [(acc x) (inner acc x)])))

  ;; Collect into a persistent-map. Steps receive (k . v) pairs
  ;; (matching Clojure's map-as-seq-of-entries convention).
  (define (rf-into-pmap)
    (case-lambda
      [()       (transient-map pmap-empty)]
      [(t)      (persistent-map! t)]
      [(t kv)   (tmap-set! t (car kv) (cdr kv)) t]))

  ;; Collect into a persistent-set.
  (define (rf-into-pset)
    (case-lambda
      [()       (transient-set pset-empty)]
      [(t)      (persistent-set! t)]
      [(t x)    (tset-add! t x) t]))

  ;; Collect into a persistent-vector via the pvec transient API.
  (define (rf-into-pvec)
    (case-lambda
      [()       (pvec-transient pvec-empty)]
      [(t)      (pvec-persistent! t)]
      [(t x)    (pvec-t-append! t x) t]))

  ;; ======================================================================
  ;; Core transducers
  ;; ======================================================================

  ;; (mapping f) — apply f to each element before passing to rf
  (define (mapping f)
    (make-xducer
      (lambda (rf)
        (case-lambda
          [()        (rf)]
          [(acc)     (rf acc)]
          [(acc x)   (rf acc (f x))]))))

  ;; (filtering pred) — only pass elements satisfying pred
  (define (filtering pred)
    (make-xducer
      (lambda (rf)
        (case-lambda
          [()       (rf)]
          [(acc)    (rf acc)]
          [(acc x)  (if (pred x) (rf acc x) acc)]))))

  ;; (taking n) — pass first n elements, then short-circuit
  (define (taking n)
    (make-xducer
      (lambda (rf)
        (let ([remaining (box n)])
          (case-lambda
            [()       (rf)]
            [(acc)    (rf acc)]
            [(acc x)
             (let ([r (unbox remaining)])
               (cond
                 [(fx<= r 0) (reduced acc)]
                 [else
                  (set-box! remaining (fx- r 1))
                  (let ([result (rf acc x)])
                    (if (fx<= (unbox remaining) 0)
                      (reduced (ensure-unreduced result))
                      result))]))])))))

  ;; (dropping n) — skip first n elements, then pass rest
  (define (dropping n)
    (make-xducer
      (lambda (rf)
        (let ([remaining (box n)])
          (case-lambda
            [()       (rf)]
            [(acc)    (rf acc)]
            [(acc x)
             (let ([r (unbox remaining)])
               (if (fx> r 0)
                 (begin (set-box! remaining (fx- r 1)) acc)
                 (rf acc x)))])))))

  ;; (flat-mapping f) — map f (which returns a collection) then flatten one level
  (define (flat-mapping f)
    (make-xducer
      (lambda (rf)
        (case-lambda
          [()       (rf)]
          [(acc)    (rf acc)]
          [(acc x)
           ;; f returns a list; fold it into acc using rf
           (let ([items (f x)])
             (let loop ([a acc] [lst items])
               (cond
                 [(null? lst) a]
                 [(reduced? a) a]
                 [else (loop (rf a (car lst)) (cdr lst))])))]))))

  ;; (taking-while pred) — pass elements while pred holds, then stop
  (define (taking-while pred)
    (make-xducer
      (lambda (rf)
        (case-lambda
          [()       (rf)]
          [(acc)    (rf acc)]
          [(acc x)
           (if (pred x)
             (rf acc x)
             (reduced acc))]))))

  ;; (dropping-while pred) — drop elements while pred holds, then pass rest
  (define (dropping-while pred)
    (make-xducer
      (lambda (rf)
        (let ([dropping? (box #t)])
          (case-lambda
            [()       (rf)]
            [(acc)    (rf acc)]
            [(acc x)
             (if (unbox dropping?)
               (if (pred x)
                 acc   ;; still dropping
                 (begin
                   (set-box! dropping? #f)
                   (rf acc x)))
               (rf acc x))])))))

  ;; (cat) — concatenate; each element is itself a collection, flatten one level
  (define (cat)
    (make-xducer
      (lambda (rf)
        (case-lambda
          [()       (rf)]
          [(acc)    (rf acc)]
          [(acc coll)
           (let loop ([a acc] [lst coll])
             (cond
               [(null? lst) a]
               [(reduced? a) a]
               [else (loop (rf a (car lst)) (cdr lst))]))]))))

  ;; (deduplicate) — remove consecutive duplicate elements
  (define (deduplicate)
    (make-xducer
      (lambda (rf)
        (let ([prev (box *no-value*)])
          (case-lambda
            [()       (rf)]
            [(acc)    (rf acc)]
            [(acc x)
             (if (and (not (eq? (unbox prev) *no-value*))
                      (equal? (unbox prev) x))
               acc
               (begin
                 (set-box! prev x)
                 (rf acc x)))])))))

  (define *no-value* (list 'no-value))  ;; unique sentinel

  ;; (partitioning-by f) — group consecutive elements with same (f item)
  ;; Emits a list of lists; each partition is emitted when the key changes.
  (define (partitioning-by f)
    (make-xducer
      (lambda (rf)
        (let ([current-key (box *no-value*)]
              [current-buf (box '())])
          (case-lambda
            [()      (rf)]
            [(acc)
             ;; Flush any remaining partition
             (let ([buf (reverse (unbox current-buf))])
               (if (null? buf)
                 (rf acc)
                 (rf (rf acc buf))))]
            [(acc x)
             (let ([key (f x)])
               (cond
                 [(eq? (unbox current-key) *no-value*)
                  ;; First element
                  (set-box! current-key key)
                  (set-box! current-buf (list x))
                  acc]
                 [(equal? (unbox current-key) key)
                  ;; Same partition
                  (set-box! current-buf (cons x (unbox current-buf)))
                  acc]
                 [else
                  ;; New partition — emit the old one
                  (let ([buf (reverse (unbox current-buf))])
                    (set-box! current-key key)
                    (set-box! current-buf (list x))
                    (rf acc buf))]))])))))

  ;; (windowing n) — sliding windows of size n as lists
  (define (windowing n)
    (make-xducer
      (lambda (rf)
        (let ([buf (box '())]    ;; buffer (recent n items, newest first)
              [cnt (box 0)])     ;; number of items seen
          (case-lambda
            [()       (rf)]
            [(acc)    (rf acc)]
            [(acc x)
             (let ([new-cnt (fx+ (unbox cnt) 1)])
               (set-box! cnt new-cnt)
               ;; Prepend x and keep at most n items
               (let* ([new-buf (cons x (unbox buf))]
                      [trimmed (if (fx> (length new-buf) n)
                                 (list-head new-buf n)
                                 new-buf)])
                 (set-box! buf trimmed)
                 (if (fx>= new-cnt n)
                   ;; Full window available — emit in original order
                   (rf acc (reverse trimmed))
                   acc)))])))))

  ;; (indexing) — pair each element with its 0-based index: (index . item)
  (define (indexing)
    (make-xducer
      (lambda (rf)
        (let ([idx (box 0)])
          (case-lambda
            [()       (rf)]
            [(acc)    (rf acc)]
            [(acc x)
             (let ([i (unbox idx)])
               (set-box! idx (fx+ i 1))
               (rf acc (cons i x)))])))))

  ;; (enumerating) — alias for indexing
  (define enumerating indexing)

  ;; ======================================================================
  ;; Composition
  ;; ======================================================================

  ;; Compose transducers left-to-right (data flows left to right).
  ;; Internally implemented as right-to-left function composition of
  ;; the transformer functions (standard transducer convention).
  ;;
  ;; (compose-transducers xf1 xf2 xf3)
  ;; => data flows: xf1 -> xf2 -> xf3 -> rf
  ;; => function composition: xf1-fn ∘ xf2-fn ∘ xf3-fn applied to rf

  (define (compose-transducers . xfs)
    (cond
      [(null? xfs)
       ;; Identity transducer
       (make-xducer (lambda (rf) rf))]
      [(null? (cdr xfs))
       (car xfs)]
      [else
       (make-xducer
         (lambda (rf)
           ;; Fold right: apply rightmost first to rf
           (let loop ([fns (reverse xfs)] [r rf])
             (if (null? fns)
               r
               (loop (cdr fns) (apply-xf (car fns) r))))))]))

  (define xf-compose compose-transducers)

  ;; ======================================================================
  ;; Reduction
  ;; ======================================================================

  ;; (transduce xf rf init coll)
  ;; Apply transducer xf to reducing function rf, then fold coll.
  ;; coll may be a proper list, a vector, a string, or a persistent
  ;; map/set/vector (HAMT / BVT structures from std pmap/pset/pvec).
  ;;
  ;; Elements handed to the reducing function:
  ;;   - list/vector/string/pvec : each element in order
  ;;   - pset                    : each element (HAMT iteration order)
  ;;   - pmap                    : each (key . val) pair (like Clojure's seq-of-entries)
  (define (transduce xf rf init coll)
    (let ([xrf (apply-xf xf rf)])
      (cond
        ;; List — existing fast path.
        [(or (null? coll) (pair? coll))
         (let loop ([acc init] [lst coll])
           (cond
             [(null? lst)
              (xrf (ensure-unreduced acc))]
             [(reduced? acc)
              (xrf (reduced-box-val acc))]
             [else
              (let ([result (xrf acc (car lst))])
                (loop result (cdr lst)))]))]
        ;; Vector — indexed walk.
        [(vector? coll)
         (let ([n (vector-length coll)])
           (let loop ([acc init] [i 0])
             (cond
               [(fx>= i n)
                (xrf (ensure-unreduced acc))]
               [(reduced? acc)
                (xrf (reduced-box-val acc))]
               [else
                (loop (xrf acc (vector-ref coll i)) (fx+ i 1))])))]
        ;; String — indexed walk yielding characters.
        [(string? coll)
         (let ([n (string-length coll)])
           (let loop ([acc init] [i 0])
             (cond
               [(fx>= i n)
                (xrf (ensure-unreduced acc))]
               [(reduced? acc)
                (xrf (reduced-box-val acc))]
               [else
                (loop (xrf acc (string-ref coll i)) (fx+ i 1))])))]
        ;; Persistent map — iterate (k, v) and hand the rf a pair.
        [(persistent-map? coll)
         (call/cc
           (lambda (escape)
             (let ([final
                    (persistent-map-fold
                      (lambda (acc k v)
                        (let ([r (xrf acc (cons k v))])
                          (if (reduced? r)
                              (escape (xrf (reduced-box-val r)))
                              r)))
                      init coll)])
               (xrf (ensure-unreduced final)))))]
        ;; Persistent set — each element.
        [(persistent-set? coll)
         (call/cc
           (lambda (escape)
             (let ([final
                    (persistent-set-fold
                      (lambda (acc x)
                        (let ([r (xrf acc x)])
                          (if (reduced? r)
                              (escape (xrf (reduced-box-val r)))
                              r)))
                      init coll)])
               (xrf (ensure-unreduced final)))))]
        ;; Persistent vector — ordered.
        [(persistent-vector? coll)
         (call/cc
           (lambda (escape)
             (let ([final
                    (persistent-vector-fold
                      (lambda (acc x)
                        (let ([r (xrf acc x)])
                          (if (reduced? r)
                              (escape (xrf (reduced-box-val r)))
                              r)))
                      init coll)])
               (xrf (ensure-unreduced final)))))]
        [else
         (error 'transduce "unsupported collection type" coll)])))

  ;; ======================================================================
  ;; High-level combinators
  ;; ======================================================================

  ;; (sequence xf coll) — transduce into a list
  (define (sequence xf coll)
    (transduce xf (rf-cons) '() coll))

  ;; (into dest xf coll)
  ;; dest: '()              -> returns a list
  ;;       #()              -> returns a vector
  ;;       ""               -> returns a string (elements must be chars)
  ;;       persistent-map   -> returns a persistent-map (src yields k.v pairs)
  ;;       persistent-set   -> returns a persistent-set
  ;;       persistent-vec   -> returns a persistent-vector
  (define (into dest xf coll)
    (cond
      [(null? dest)
       (sequence xf coll)]
      [(vector? dest)
       (let ([rf (rf-into-vector)])
         (transduce xf rf (rf) coll))]
      [(string? dest)
       (list->string (sequence xf coll))]
      [(persistent-map? dest)
       ;; Start from the existing dest via a transient. rf-into-pmap's
       ;; completion finalises the transient back into a persistent map.
       (transduce xf (rf-into-pmap) (transient-map dest) coll)]
      [(persistent-set? dest)
       (transduce xf (rf-into-pset) (transient-set dest) coll)]
      [(persistent-vector? dest)
       (transduce xf (rf-into-pvec) (pvec-transient dest) coll)]
      [else
       (error 'into "unsupported destination type" dest)]))

  ;; (eduction xf coll)
  ;; Returns a lazy sequence represented as a thunk.
  ;; The thunk, when called, materialises into a list.
  ;; Eductions are composable: (eduction xf2 (eduction xf1 coll)) works
  ;; because an eduction behaves as a collection (a thunk returning a list).
  (define (eduction xf coll)
    (lambda ()
      (let ([src (if (procedure? coll) (coll) coll)])
        (sequence xf src))))

  ) ;; end library
