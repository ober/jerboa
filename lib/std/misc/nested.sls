#!chezscheme
;;; (std misc nested) — Clojure-style nested access (get-in / assoc-in / update-in)
;;;
;;; Polymorphic over:
;;;   - persistent-map / imap    (immutable, pure updates)
;;;   - concurrent-hash / chash  (thread-safe, mutating updates)
;;;   - hash-table               (mutable, mutating updates)
;;;   - vector                   (integer keys only, mutating for assoc-in!)
;;;
;;; Read side (get-in) is always polymorphic.
;;;
;;; Write side comes in two flavours, pick the one matching your container:
;;;   - assoc-in / update-in     pure, returns new container (for imap/pmap)
;;;   - assoc-in! / update-in!   mutating, for chash/hash/vector
;;;
;;; Clojure semantics for intermediate keys:
;;;   - get-in: short-circuits on #f/missing, returns default
;;;   - assoc-in / update-in on imap: creates new pmap-empty intermediates
;;;     when the path doesn't exist
;;;   - assoc-in! / update-in! on chash/hash: creates new empty containers
;;;     of the same type as intermediates
;;;
;;; Usage:
;;;   (import (std misc nested))
;;;
;;;   (def m (imap "user" (imap "name" "Alice" "prefs" (imap "theme" "dark"))))
;;;   (get-in m '("user" "name"))                ;; => "Alice"
;;;   (get-in m '("user" "prefs" "theme"))       ;; => "dark"
;;;   (get-in m '("user" "missing") 'none)       ;; => none
;;;
;;;   (def m2 (assoc-in m '("user" "prefs" "theme") "light"))
;;;   (get-in m  '("user" "prefs" "theme"))      ;; => "dark"  (unchanged)
;;;   (get-in m2 '("user" "prefs" "theme"))      ;; => "light"
;;;
;;;   (def m3 (update-in m '("user" "name") string-upcase))
;;;   (get-in m3 '("user" "name"))               ;; => "ALICE"
;;;
;;;   ;; Mutating on chash:
;;;   (def state (chash "user" (chash "count" 0)))
;;;   (update-in! state '("user" "count") + 1)
;;;   (get-in state '("user" "count"))           ;; => 1

(library (std misc nested)
  (export
    ;; Polymorphic read
    get-in
    ;; Pure (imap/pmap) updates — returns new container
    assoc-in
    update-in
    ;; Mutating (chash/hash/vector) updates — returns the same container
    assoc-in!
    update-in!
    ;; Single-level polymorphic dispatch (exposed for composition)
    nested-get
    nested-empty-like)

  (import (except (chezscheme) make-hash-table hash-table? 1+ 1- iota)
          (jerboa runtime)
          (std pmap)
          (std concur hash))

  ;; =========================================================================
  ;; Single-level polymorphic accessors
  ;; =========================================================================

  (define (nested-get container key default)
    ;; Returns the value stored at `key` in `container`, or `default`
    ;; if missing. Polymorphic across all supported container types.
    (cond
      [(persistent-map? container)
       (persistent-map-ref container key (lambda () default))]
      [(concurrent-hash? container)
       (concurrent-hash-get container key default)]
      [(hash-table? container)
       (if (hash-key? container key)
           (hash-get container key)
           default)]
      [(vector? container)
       (if (and (integer? key)
                (exact? key)
                (>= key 0)
                (< key (vector-length container)))
           (vector-ref container key)
           default)]
      [(pair? container)
       ;; Alist — fall back to assoc
       (let ([pair (assoc key container)])
         (if pair (cdr pair) default))]
      [(record? container)
       ;; Record — look up field by name (accepts symbol, string, keyword).
       ;; Walks the parent chain so inherited fields are reachable.
       ;; This powers get-in over nested records / defstruct instances.
       (%nested-record-ref container key default)]
      [else default]))

  (define (%nested-record-key->symbol k)
    (cond
      [(symbol? k) k]
      [(string? k) (string->symbol k)]
      [(keyword? k) (string->symbol (keyword->string k))]
      [else #f]))

  (define (%nested-record-ref rec key default)
    (let ([name (%nested-record-key->symbol key)])
      (cond
        [(not name) default]
        [else
         (let walk ([r (record-rtd rec)])
           (cond
             [(not r) default]
             [else
              (let* ([names (record-type-field-names r)]
                     [n (vector-length names)])
                (let loop ([i 0])
                  (cond
                    [(= i n) (walk (record-type-parent r))]
                    [(eq? (vector-ref names i) name)
                     ((record-accessor r i) rec)]
                    [else (loop (+ i 1))])))]))])))

  (define (nested-empty-like container)
    ;; Return a fresh empty container of the same type as `container`.
    ;; Used by assoc-in! / update-in! to create intermediates.
    (cond
      [(persistent-map? container) pmap-empty]
      [(concurrent-hash? container) (make-concurrent-hash)]
      [(hash-table? container) (make-hash-table)]
      [else
       (error 'nested-empty-like
              "don't know how to create an empty version of this container"
              container)]))

  ;; =========================================================================
  ;; Polymorphic read — get-in
  ;; =========================================================================

  (define get-in
    (case-lambda
      [(container keys) (get-in container keys #f)]
      [(container keys default)
       (let loop ([c container] [ks keys])
         (cond
           [(null? ks) c]
           [(eq? c #f) default]
           [else
            (let ([next (nested-get c (car ks) #f)])
              (if (eq? next #f)
                  (if (null? (cdr ks))
                      (nested-get c (car ks) default)
                      default)
                  (loop next (cdr ks))))]))]))

  ;; =========================================================================
  ;; Pure updates (imap / persistent-map) — returns new container
  ;; =========================================================================

  (define (assoc-in m keys value)
    ;; Pure: returns new imap with `value` at the nested path.
    ;; Missing intermediate keys are filled with empty pmaps.
    ;; Requires an immutable input (persistent-map). For mutable
    ;; containers, use assoc-in!.
    (when (null? keys)
      (error 'assoc-in "empty key path" keys))
    (let ([k (car keys)] [rest (cdr keys)])
      (if (null? rest)
          (persistent-map-set m k value)
          (let ([sub (persistent-map-ref m k (lambda () pmap-empty))])
            (persistent-map-set m k
              (assoc-in (if (persistent-map? sub) sub pmap-empty)
                        rest value))))))

  (define update-in
    ;; Pure: returns new imap with (f old-val args...) at the nested path.
    (case-lambda
      [(m keys f) (update-in* m keys f '())]
      [(m keys f . args) (update-in* m keys f args)]))

  (define (update-in* m keys f args)
    (when (null? keys)
      (error 'update-in "empty key path" keys))
    (let ([k (car keys)] [rest (cdr keys)])
      (if (null? rest)
          (let ([old (persistent-map-ref m k (lambda () #f))])
            (persistent-map-set m k (apply f old args)))
          (let ([sub (persistent-map-ref m k (lambda () pmap-empty))])
            (persistent-map-set m k
              (update-in* (if (persistent-map? sub) sub pmap-empty)
                          rest f args))))))

  ;; =========================================================================
  ;; Mutating updates (chash / hash-table / vector) — returns same container
  ;; =========================================================================

  (define (nested-put! container key value)
    ;; Mutating put on a single level.
    (cond
      [(concurrent-hash? container)
       (concurrent-hash-put! container key value)]
      [(hash-table? container)
       (hash-put! container key value)]
      [(vector? container)
       (vector-set! container key value)]
      [else
       (error 'nested-put!
              "cannot mutate this container type"
              container)]))

  (define (assoc-in! container keys value)
    ;; Mutating: walks into `container`, creating intermediate containers
    ;; of the same type if missing, and sets `value` at the final position.
    ;; Returns the original top-level container.
    (when (null? keys)
      (error 'assoc-in! "empty key path" keys))
    (let loop ([c container] [ks keys])
      (let ([k (car ks)] [rest (cdr ks)])
        (if (null? rest)
            (nested-put! c k value)
            (let ([sub (nested-get c k #f)])
              (if (and sub
                       (or (concurrent-hash? sub)
                           (hash-table? sub)
                           (persistent-map? sub)))
                  (loop sub rest)
                  ;; Create an intermediate of the same type as `c`
                  (let ([new-sub (nested-empty-like c)])
                    (nested-put! c k new-sub)
                    (loop new-sub rest)))))))
    container)

  (define update-in!
    ;; Mutating: (update-in! container keys f args...) applies
    ;; (f old-val args...) at the nested path. Returns container.
    (case-lambda
      [(container keys f) (update-in!* container keys f '())]
      [(container keys f . args) (update-in!* container keys f args)]))

  (define (update-in!* container keys f args)
    (when (null? keys)
      (error 'update-in! "empty key path" keys))
    (let loop ([c container] [ks keys])
      (let ([k (car ks)] [rest (cdr ks)])
        (if (null? rest)
            (let ([old (nested-get c k #f)])
              (nested-put! c k (apply f old args)))
            (let ([sub (nested-get c k #f)])
              (if (and sub
                       (or (concurrent-hash? sub)
                           (hash-table? sub)
                           (persistent-map? sub)))
                  (loop sub rest)
                  (let ([new-sub (nested-empty-like c)])
                    (nested-put! c k new-sub)
                    (loop new-sub rest)))))))
    container)

) ;; end library
