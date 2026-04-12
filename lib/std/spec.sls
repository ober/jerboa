#!chezscheme
;;; (std spec) — Composable validation specs (inspired by clojure.spec)
;;;
;;; Provides composable predicate specs, map specs, function specs,
;;; and validation. Not a full clojure.spec clone, but covers the
;;; essential use cases.
;;;
;;; Usage:
;;;   (import (std spec))
;;;
;;;   (s-def ::name (s-and string? (s-pred (lambda (s) (> (string-length s) 0)))))
;;;   (s-def ::age (s-and integer? (s-pred positive?)))
;;;   (s-def ::person (s-keys ::name ::age))
;;;
;;;   (s-valid? ::name "Alice")       ;; => #t
;;;   (s-valid? ::person my-map)      ;; => #t or #f
;;;   (s-explain ::person bad-map)    ;; prints what's wrong
;;;
;;;   (s-fdef my-fn
;;;     :args (s-cat :x integer? :y string?)
;;;     :ret string?)

(library (std spec)
  (export
    ;; Registry
    s-def s-get-spec
    ;; Spec constructors
    s-pred s-and s-or s-keys s-keys-opt
    s-cat s-coll-of s-map-of
    s-nilable s-tuple s-enum
    s-int-in s-double-in
    ;; Validation
    s-valid? s-conform s-explain s-explain-str s-assert
    ;; Function specs
    s-fdef s-check-fn
    ;; Generation (basic)
    s-exercise)

  (import (chezscheme))

  ;; ================================================================
  ;; Spec Registry
  ;; ================================================================

  (define *spec-registry* (make-hashtable equal-hash equal?))

  ;; s-def — register a spec under a name (typically a keyword symbol like ::name)
  (define-syntax s-def
    (syntax-rules ()
      [(_ name spec-expr)
       (hashtable-set! *spec-registry* 'name spec-expr)]))

  (define (s-get-spec name)
    (hashtable-ref *spec-registry* name #f))

  ;; Resolve: if it's a registered name, look it up; otherwise assume it's a spec.
  (define (resolve-spec spec-or-name)
    (cond
      [(procedure? spec-or-name) spec-or-name]
      [(symbol? spec-or-name)
       (let ([s (s-get-spec spec-or-name)])
         (or s (error 'resolve-spec "no spec registered for" spec-or-name)))]
      [(spec-record? spec-or-name) spec-or-name]
      [else (error 'resolve-spec "not a spec" spec-or-name)]))

  ;; ================================================================
  ;; Spec Records
  ;; ================================================================

  (define-record-type spec-record
    (fields (immutable kind)       ;; symbol: 'pred, 'and, 'or, 'keys, etc.
            (immutable data)       ;; kind-specific payload
            (immutable validator)  ;; (lambda (value) -> #t or explain-data)
            ))

  ;; ================================================================
  ;; Spec Constructors
  ;; ================================================================

  ;; s-pred — wrap a plain predicate as a spec
  (define (s-pred pred)
    (make-spec-record
      'pred pred
      (lambda (v) (if (pred v) #t
                      (list (cons 'pred (or (object->name pred) "predicate"))
                            (cons 'val v))))))

  (define (object->name obj)
    (cond
      [(procedure? obj)
       (let ([info (try-inspect obj)])
         (if info (format "~a" info) #f))]
      [else #f]))

  ;; Wrapper to handle both raw predicates and spec-records
  (define (validate spec v)
    (cond
      [(procedure? spec) (if (spec v) #t
                             (list (cons 'pred (format "~a" spec))
                                   (cons 'val v)))]
      [(spec-record? spec) ((spec-record-validator spec) v)]
      [(symbol? spec) (validate (resolve-spec spec) v)]
      [else (error 'validate "not a spec" spec)]))

  ;; s-and — all specs must be satisfied
  (define (s-and . specs)
    (make-spec-record
      'and specs
      (lambda (v)
        (let lp ([rest specs])
          (if (null? rest) #t
              (let ([result (validate (car rest) v)])
                (if (eq? result #t)
                    (lp (cdr rest))
                    result)))))))

  ;; s-or — at least one spec must be satisfied (returns the tag of the first match)
  ;; (s-or :string string? :number number?)
  (define (s-or . tag-spec-pairs)
    (make-spec-record
      'or tag-spec-pairs
      (lambda (v)
        (let lp ([rest tag-spec-pairs])
          (cond
            [(null? rest)
             (list (cons 'or "no alternative matched")
                   (cons 'val v))]
            [(null? (cdr rest))
             (error 's-or "odd number of arguments")]
            [else
             (let ([tag (car rest)]
                   [spec (cadr rest)])
               (if (eq? (validate spec v) #t)
                   #t
                   (lp (cddr rest))))])))))

  ;; s-keys — map spec: required keys
  ;; Keys are spec names; values at those keys must conform to the named spec.
  ;; The map is expected to be a hash-table or alist with symbol keys.
  (define (s-keys . required-keys)
    (make-spec-record
      'keys required-keys
      (lambda (v)
        (let lp ([ks required-keys])
          (if (null? ks) #t
              (let* ([k (car ks)]
                     [key-spec (s-get-spec k)])
                (cond
                  [(not (map-has-key? v k))
                   (list (cons 'key k)
                         (cons 'problem "missing required key")
                         (cons 'val v))]
                  [(not key-spec)
                   ;; No spec registered for this key — just check presence
                   (lp (cdr ks))]
                  [else
                   (let ([result (validate key-spec (map-get v k))])
                     (if (eq? result #t)
                         (lp (cdr ks))
                         (list (cons 'key k)
                               (cons 'problem result)
                               (cons 'val (map-get v k)))))])))))))

  ;; s-keys-opt — map spec: optional keys (only validated if present)
  (define (s-keys-opt . optional-keys)
    (make-spec-record
      'keys-opt optional-keys
      (lambda (v)
        (let lp ([ks optional-keys])
          (if (null? ks) #t
              (let* ([k (car ks)]
                     [key-spec (s-get-spec k)])
                (cond
                  [(not (map-has-key? v k)) (lp (cdr ks))]
                  [(not key-spec) (lp (cdr ks))]
                  [else
                   (let ([result (validate key-spec (map-get v k))])
                     (if (eq? result #t)
                         (lp (cdr ks))
                         (list (cons 'key k)
                               (cons 'problem result)
                               (cons 'val (map-get v k)))))])))))))

  ;; s-cat — positional spec for sequences
  ;; (s-cat :x integer? :y string?) validates a list with matching positions
  (define (s-cat . tag-spec-pairs)
    (make-spec-record
      'cat tag-spec-pairs
      (lambda (v)
        (unless (or (list? v) (vector? v))
          (list (cons 'problem "expected a sequence") (cons 'val v)))
        (let ([lst (if (vector? v) (vector->list v) v)])
          (let lp ([rest tag-spec-pairs] [vals lst] [idx 0])
            (cond
              [(and (null? rest) (null? vals)) #t]
              [(null? rest)
               (list (cons 'problem "extra elements")
                     (cons 'val vals))]
              [(null? vals)
               (list (cons 'problem "missing elements")
                     (cons 'at (car rest)))]
              [else
               (let ([tag (car rest)]
                     [spec (cadr rest)])
                 (let ([result (validate spec (car vals))])
                   (if (eq? result #t)
                       (lp (cddr rest) (cdr vals) (+ idx 1))
                       (list (cons 'at tag)
                             (cons 'index idx)
                             (cons 'problem result)))))]))))))

  ;; s-coll-of — every element must satisfy the spec
  (define (s-coll-of spec)
    (make-spec-record
      'coll-of spec
      (lambda (v)
        (cond
          [(list? v)
           (let lp ([rest v] [idx 0])
             (if (null? rest) #t
                 (let ([result (validate spec (car rest))])
                   (if (eq? result #t)
                       (lp (cdr rest) (+ idx 1))
                       (list (cons 'index idx)
                             (cons 'problem result))))))]
          [(vector? v)
           (let ([n (vector-length v)])
             (let lp ([i 0])
               (if (= i n) #t
                   (let ([result (validate spec (vector-ref v i))])
                     (if (eq? result #t)
                         (lp (+ i 1))
                         (list (cons 'index i)
                               (cons 'problem result)))))))]
          [else (list (cons 'problem "expected a collection")
                      (cons 'val v))]))))

  ;; s-map-of — key-spec and value-spec for all entries
  (define (s-map-of key-spec val-spec)
    (make-spec-record
      'map-of (list key-spec val-spec)
      (lambda (v)
        (let ([entries (map-entries v)])
          (let lp ([rest entries])
            (if (null? rest) #t
                (let ([k (caar rest)] [val (cdar rest)])
                  (let ([kr (validate key-spec k)])
                    (if (not (eq? kr #t))
                        (list (cons 'key k)
                              (cons 'problem (list (cons 'key-spec kr))))
                        (let ([vr (validate val-spec val)])
                          (if (not (eq? vr #t))
                              (list (cons 'key k)
                                    (cons 'problem (list (cons 'val-spec vr))))
                              (lp (cdr rest)))))))))))))

  ;; s-nilable — allows #f (nil) or the spec
  (define (s-nilable spec)
    (make-spec-record
      'nilable spec
      (lambda (v)
        (if (eq? v #f) #t (validate spec v)))))

  ;; s-tuple — fixed-length heterogeneous sequence
  (define (s-tuple . specs)
    (make-spec-record
      'tuple specs
      (lambda (v)
        (let ([lst (if (vector? v) (vector->list v) v)])
          (if (not (= (length lst) (length specs)))
              (list (cons 'problem "wrong length")
                    (cons 'expected (length specs))
                    (cons 'got (length lst)))
              (let lp ([ss specs] [vs lst] [idx 0])
                (if (null? ss) #t
                    (let ([result (validate (car ss) (car vs))])
                      (if (eq? result #t)
                          (lp (cdr ss) (cdr vs) (+ idx 1))
                          (list (cons 'index idx)
                                (cons 'problem result)))))))))))

  ;; s-enum — value must be one of a fixed set
  (define (s-enum . values)
    (make-spec-record
      'enum values
      (lambda (v)
        (if (member v values) #t
            (list (cons 'problem "not in enum")
                  (cons 'val v)
                  (cons 'allowed values))))))

  ;; s-int-in — integer in range [lo, hi)
  (define (s-int-in lo hi)
    (s-and integer? (s-pred (lambda (x) (and (>= x lo) (< x hi))))))

  ;; s-double-in — inexact number in range
  (define (s-double-in lo hi)
    (s-and number? (s-pred (lambda (x) (and (>= x lo) (<= x hi))))))

  ;; ================================================================
  ;; Validation API
  ;; ================================================================

  (define (s-valid? spec v)
    (eq? (validate (resolve-spec-or-pred spec) v) #t))

  (define (s-conform spec v)
    (let ([result (validate (resolve-spec-or-pred spec) v)])
      (if (eq? result #t) v 'invalid)))

  (define (s-explain spec v)
    (let ([result (validate (resolve-spec-or-pred spec) v)])
      (if (eq? result #t)
          (display "Success\n")
          (begin
            (display "Spec validation failed:\n")
            (for-each (lambda (pair)
                        (display "  ")
                        (display (car pair))
                        (display ": ")
                        (write (cdr pair))
                        (newline))
                      result)))))

  (define (s-explain-str spec v)
    (with-output-to-string
      (lambda () (s-explain spec v))))

  (define (s-assert spec v)
    (let ([result (validate (resolve-spec-or-pred spec) v)])
      (unless (eq? result #t)
        (error 's-assert "spec assertion failed" result))))

  (define (resolve-spec-or-pred x)
    (cond
      [(symbol? x) (resolve-spec x)]
      [(procedure? x) x]
      [(spec-record? x) x]
      [else (error 'resolve-spec-or-pred "not a spec" x)]))

  ;; ================================================================
  ;; Function Specs
  ;; ================================================================

  ;; s-fdef — register a function spec
  ;; (s-fdef my-fn :args args-spec :ret ret-spec)
  (define *fspec-registry* (make-hashtable equal-hash equal?))

  (define-syntax s-fdef
    (syntax-rules ()
      [(_ name kv ...)
       (hashtable-set! *fspec-registry* 'name
         (parse-fspec 'kv ...))]))

  (define (parse-fspec . kvs)
    (let lp ([rest kvs] [args #f] [ret #f])
      (cond
        [(null? rest) (list (cons 'args args) (cons 'ret ret))]
        [(eq? (car rest) ':args)
         (lp (cddr rest) (cadr rest) ret)]
        [(eq? (car rest) ':ret)
         (lp (cddr rest) args (cadr rest))]
        [else (error 'parse-fspec "unknown key" (car rest))])))

  ;; s-check-fn — validate a function against its fspec
  (define (s-check-fn name f sample-args)
    (let ([fspec (hashtable-ref *fspec-registry* name #f)])
      (cond
        [(not fspec) (error 's-check-fn "no fspec for" name)]
        [else
         (let ([args-spec (cdr (assq 'args fspec))]
               [ret-spec (cdr (assq 'ret fspec))])
           ;; Validate args
           (when args-spec
             (let ([result (validate args-spec sample-args)])
               (unless (eq? result #t)
                 (error 's-check-fn "args don't conform" name result))))
           ;; Call function
           (let ([ret (apply f sample-args)])
             ;; Validate return
             (when ret-spec
               (let ([result (validate ret-spec ret)])
                 (unless (eq? result #t)
                   (error 's-check-fn "return doesn't conform" name result))))
             ret))])))

  ;; ================================================================
  ;; Generation (basic exercise)
  ;; ================================================================

  ;; s-exercise — generate n sample values that conform to a spec
  ;; Very basic: only works for simple predicates.
  (define s-exercise
    (case-lambda
      [(spec) (s-exercise spec 10)]
      [(spec n)
       (let ([generators
               (list
                 (cons integer? (lambda () (- (random 200) 100)))
                 (cons number? (lambda () (* (random 1000) 0.01)))
                 (cons string? (lambda () (list-ref '("foo" "bar" "baz" "hello" "world")
                                                    (random 5))))
                 (cons symbol? (lambda () (list-ref '(a b c x y z) (random 6))))
                 (cons boolean? (lambda () (= (random 2) 0)))
                 (cons positive? (lambda () (+ 1 (random 100))))
                 (cons char? (lambda () (integer->char (+ 65 (random 26))))))])
         (let ([gen (find-generator spec generators)])
           (if gen
               (let lp ([i 0] [acc '()])
                 (if (= i n)
                     (reverse acc)
                     (let ([v (gen)])
                       (if (s-valid? spec v)
                           (lp (+ i 1) (cons v acc))
                           (lp i acc)))))  ;; retry
               (error 's-exercise "no generator for spec" spec))))]))

  (define (find-generator spec generators)
    (cond
      [(null? generators) #f]
      [(procedure? spec)
       (if (eq? spec (caar generators))
           (cdar generators)
           (find-generator spec (cdr generators)))]
      [else #f]))

  ;; ================================================================
  ;; Map helpers — work with alists and hash tables
  ;; ================================================================

  (define (map-has-key? m k)
    (cond
      [(hashtable? m) (hashtable-contains? m k)]
      [(and (list? m) (every-alist-pair? m))
       (if (assoc k m) #t #f)]
      [else #f]))

  (define (map-get m k)
    (cond
      [(hashtable? m) (hashtable-ref m k #f)]
      [(list? m)
       (let ([p (assoc k m)])
         (if p (cdr p) #f))]
      [else #f]))

  (define (map-entries m)
    (cond
      [(hashtable? m)
       (let-values ([(keys vals) (hashtable-entries m)])
         (let ([n (vector-length keys)])
           (let lp ([i 0] [acc '()])
             (if (= i n) acc
                 (lp (+ i 1)
                     (cons (cons (vector-ref keys i) (vector-ref vals i))
                           acc))))))]
      [(list? m) m]
      [else '()]))

  (define (every-alist-pair? lst)
    (or (null? lst)
        (and (pair? (car lst))
             (every-alist-pair? (cdr lst)))))

  ;; try-inspect — try to get source info from a procedure (may fail)
  (define (try-inspect obj)
    (guard (exn [#t #f])
      (let ([info (((inspect/object obj) 'code) 'source)])
        info)))

) ;; end library
