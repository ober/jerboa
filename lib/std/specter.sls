#!chezscheme
;;; (std specter) — Specter-style Path Navigation
;;;
;;; Navigate and transform deeply nested data structures using
;;; composable path navigators.
;;;
;;; Core API:
;;;   (select path data)     → list of matched values
;;;   (select-one path data) → single matched value (or #f)
;;;   (transform path f data) → data with matched values transformed
;;;   (setval path val data)  → data with matched values replaced
;;;
;;; Paths are lists of navigators composed left-to-right.
;;; Works with lists, vectors, hash tables, alists, and nested combos.

(library (std specter)
  (export
    ;; Core operations
    select select-one select-first
    transform setval

    ;; Navigators
    ALL FIRST LAST
    MAP-KEYS MAP-VALS MAP-ENTRIES
    INDEXED-VALS
    nthpath keypath
    filterer pred-nav
    srange
    walker
    must
    NIL->VAL VAL->NIL
    if-path cond-path
    multi-path
    stay-then-continue
    END

    ;; Parameterized
    submap
    collect collect-one
    putval

    ;; Inline path construction
    comp-navs)

  (import (except (chezscheme) collect))

  ;; =========================================================================
  ;; Navigator protocol
  ;;
  ;; A navigator is a procedure: (nav 'select data next) → results
  ;;                             (nav 'transform data next) → transformed-data
  ;;
  ;; 'select: call (next sub-value) for each sub-value, collect results
  ;; 'transform: call (next sub-value) for each sub-value, rebuild structure
  ;; =========================================================================

  ;; Compose a list of navigators into a single navigator
  (define (comp-navs . navs)
    (cond
      [(null? navs) identity-nav]
      [(null? (cdr navs)) (car navs)]
      [else
       (let ([first-nav (car navs)]
             [rest-nav (apply comp-navs (cdr navs))])
         (lambda (op data next)
           (first-nav op data
             (lambda (sub)
               (rest-nav op sub next)))))]))

  (define identity-nav
    (lambda (op data next) (next data)))

  ;; =========================================================================
  ;; Core API
  ;; =========================================================================

  (define (select path data)
    (let ([nav (if (list? path) (apply comp-navs path) path)]
          [results '()])
      (nav 'select data
        (lambda (val) (set! results (cons val results))))
      (reverse results)))

  (define (select-one path data)
    (let ([r (select path data)])
      (if (pair? r) (car r) #f)))

  (define (select-first path data)
    (select-one path data))

  (define (transform path f data)
    (let ([nav (if (list? path) (apply comp-navs path) path)])
      (nav 'transform data
        (lambda (val) (f val)))))

  (define (setval path val data)
    (transform path (lambda (_) val) data))

  ;; =========================================================================
  ;; Built-in navigators
  ;; =========================================================================

  ;; ALL — navigate to every element of a sequential collection
  (define (ALL op data next)
    (cond
      [(list? data)
       (case op
         [(select) (for-each next data)]
         [(transform) (map next data)])]
      [(vector? data)
       (case op
         [(select) (vector-for-each next data)]
         [(transform) (vector-map next data)])]
      [else (error 'ALL "not a sequential collection" data)]))

  ;; FIRST — navigate to first element
  (define (FIRST op data next)
    (cond
      [(pair? data)
       (case op
         [(select) (next (car data))]
         [(transform) (cons (next (car data)) (cdr data))])]
      [(and (vector? data) (> (vector-length data) 0))
       (case op
         [(select) (next (vector-ref data 0))]
         [(transform)
          (let ([v (vector-copy data)])
            (vector-set! v 0 (next (vector-ref data 0)))
            v)])]
      [else (error 'FIRST "empty or not sequential" data)]))

  ;; LAST — navigate to last element
  (define (LAST op data next)
    (cond
      [(pair? data)
       (case op
         [(select)
          (let loop ([l data])
            (if (null? (cdr l)) (next (car l)) (loop (cdr l))))]
         [(transform)
          (let loop ([l data])
            (if (null? (cdr l))
              (list (next (car l)))
              (cons (car l) (loop (cdr l)))))])]
      [(and (vector? data) (> (vector-length data) 0))
       (let ([i (- (vector-length data) 1)])
         (case op
           [(select) (next (vector-ref data i))]
           [(transform)
            (let ([v (vector-copy data)])
              (vector-set! v i (next (vector-ref data i)))
              v)]))]
      [else (error 'LAST "empty or not sequential" data)]))

  ;; MAP-KEYS — navigate to all keys in a hash table
  (define (MAP-KEYS op data next)
    (unless (hashtable? data) (error 'MAP-KEYS "not a hash table" data))
    (let-values ([(keys vals) (hashtable-entries data)])
      (case op
        [(select) (vector-for-each next keys)]
        [(transform)
         (let ([ht (make-hashtable equal-hash equal?)])
           (do ([i 0 (+ i 1)]) ((= i (vector-length keys)) ht)
             (hashtable-set! ht
               (next (vector-ref keys i))
               (vector-ref vals i))))])))

  ;; MAP-VALS — navigate to all values in a hash table
  (define (MAP-VALS op data next)
    (unless (hashtable? data) (error 'MAP-VALS "not a hash table" data))
    (let-values ([(keys vals) (hashtable-entries data)])
      (case op
        [(select) (vector-for-each next vals)]
        [(transform)
         (let ([ht (make-hashtable equal-hash equal?)])
           (do ([i 0 (+ i 1)]) ((= i (vector-length keys)) ht)
             (hashtable-set! ht
               (vector-ref keys i)
               (next (vector-ref vals i)))))])))

  ;; MAP-ENTRIES — navigate to (key . value) pairs
  (define (MAP-ENTRIES op data next)
    (unless (hashtable? data) (error 'MAP-ENTRIES "not a hash table" data))
    (let-values ([(keys vals) (hashtable-entries data)])
      (case op
        [(select)
         (do ([i 0 (+ i 1)]) ((= i (vector-length keys)))
           (next (cons (vector-ref keys i) (vector-ref vals i))))]
        [(transform)
         (let ([ht (make-hashtable equal-hash equal?)])
           (do ([i 0 (+ i 1)]) ((= i (vector-length keys)) ht)
             (let ([entry (next (cons (vector-ref keys i) (vector-ref vals i)))])
               (hashtable-set! ht (car entry) (cdr entry)))))])))

  ;; INDEXED-VALS — navigate to (index . value) pairs
  (define (INDEXED-VALS op data next)
    (cond
      [(list? data)
       (case op
         [(select)
          (let loop ([l data] [i 0])
            (unless (null? l)
              (next (cons i (car l)))
              (loop (cdr l) (+ i 1))))]
         [(transform)
          (let loop ([l data] [i 0])
            (if (null? l) '()
              (let ([entry (next (cons i (car l)))])
                (cons (cdr entry) (loop (cdr l) (+ i 1))))))])]
      [else (error 'INDEXED-VALS "not a list" data)]))

  ;; nthpath — navigate to nth element
  (define (nthpath n)
    (lambda (op data next)
      (cond
        [(list? data)
         (case op
           [(select) (next (list-ref data n))]
           [(transform)
            (let loop ([l data] [i 0])
              (if (= i n)
                (cons (next (car l)) (cdr l))
                (cons (car l) (loop (cdr l) (+ i 1)))))])]
        [(vector? data)
         (case op
           [(select) (next (vector-ref data n))]
           [(transform)
            (let ([v (vector-copy data)])
              (vector-set! v n (next (vector-ref data n)))
              v)])]
        [else (error 'nthpath "not sequential" data)])))

  ;; keypath — navigate to a key in a hash table or alist
  (define (keypath key)
    (lambda (op data next)
      (cond
        [(hashtable? data)
         (case op
           [(select)
            (when (hashtable-contains? data key)
              (next (hashtable-ref data key #f)))]
           [(transform)
            (let ([ht (hashtable-copy data #t)])
              (when (hashtable-contains? ht key)
                (hashtable-set! ht key (next (hashtable-ref ht key #f))))
              ht)])]
        [(and (pair? data) (pair? (car data)))
         ;; Alist
         (case op
           [(select)
            (let ([entry (assoc key data)])
              (when entry (next (cdr entry))))]
           [(transform)
            (map (lambda (entry)
                   (if (equal? (car entry) key)
                     (cons key (next (cdr entry)))
                     entry))
                 data)])]
        [else (error 'keypath "not a map" data)])))

  ;; filterer — navigate to elements matching a predicate
  (define (filterer pred)
    (lambda (op data next)
      (cond
        [(list? data)
         (case op
           [(select) (for-each next (filter pred data))]
           [(transform)
            (map (lambda (x) (if (pred x) (next x) x)) data)])]
        [(vector? data)
         (case op
           [(select)
            (vector-for-each
              (lambda (x) (when (pred x) (next x))) data)]
           [(transform)
            (vector-map
              (lambda (x) (if (pred x) (next x) x)) data)])]
        [else (error 'filterer "not sequential" data)])))

  ;; pred-nav — navigate to value only if predicate holds
  (define (pred-nav pred)
    (lambda (op data next)
      (if (pred data)
        (case op
          [(select) (next data)]
          [(transform) (next data)])
        (case op
          [(select) (void)]
          [(transform) data]))))

  ;; srange — navigate to a subrange [start, end) of a list
  (define (srange start end)
    (lambda (op data next)
      (unless (list? data) (error 'srange "not a list" data))
      (let ([before (list-head data start)]
            [middle (list-head (list-tail data start) (- end start))]
            [after (list-tail data end)])
        (case op
          [(select) (next middle)]
          [(transform)
           (let ([new-middle (next middle)])
             (append before new-middle after))]))))

  ;; walker — recursively navigate to all values matching pred
  (define (walker pred)
    (lambda (op data next)
      (case op
        [(select)
         (when (pred data) (next data))
         (cond
           [(pair? data)
            ((walker pred) op (car data) next)
            ((walker pred) op (cdr data) next)]
           [(vector? data)
            (vector-for-each
              (lambda (x) ((walker pred) op x next)) data)])]
        [(transform)
         (let ([val (if (pred data) (next data) data)])
           (cond
             [(pair? val)
              (cons ((walker pred) op (car val) next)
                    ((walker pred) op (cdr val) next))]
             [(vector? val)
              (vector-map
                (lambda (x) ((walker pred) op x next)) val)]
             [else val]))])))

  ;; must — navigate only if key exists, otherwise skip entirely
  (define (must key)
    (lambda (op data next)
      (when (and (hashtable? data) (hashtable-contains? data key))
        ((keypath key) op data next))))

  ;; NIL->VAL — if data is #f, replace with val
  (define (NIL->VAL val)
    (lambda (op data next)
      (let ([effective (if (not data) val data)])
        (case op
          [(select) (next effective)]
          [(transform) (next effective)]))))

  ;; VAL->NIL — if (pred data), replace with #f
  (define (VAL->NIL pred)
    (lambda (op data next)
      (case op
        [(select) (next (if (pred data) #f data))]
        [(transform) (let ([r (next data)]) (if (pred r) #f r))])))

  ;; END — navigate "past the end" of a list (for appending)
  (define (END op data next)
    (unless (list? data) (error 'END "not a list" data))
    (case op
      [(select) (void)]
      [(transform) (append data (list (next '())))]))

  ;; if-path — conditional navigation
  (define (if-path test then-nav . else-opt)
    (let ([else-nav (if (pair? else-opt) (car else-opt) identity-nav)])
      (lambda (op data next)
        (if (pair? (select test data))
          (then-nav op data next)
          (else-nav op data next)))))

  ;; cond-path — multi-way conditional
  (define (cond-path . clauses)
    ;; clauses: (test nav test nav ... default-nav)
    (lambda (op data next)
      (let loop ([cls clauses])
        (cond
          [(null? cls) (next data)]
          [(null? (cdr cls)) ((car cls) op data next)]
          [else
           (if (pair? (select (car cls) data))
             ((cadr cls) op data next)
             (loop (cddr cls)))]))))

  ;; multi-path — apply multiple paths, collecting all results
  (define (multi-path . paths)
    (lambda (op data next)
      (case op
        [(select)
         (for-each (lambda (p)
                     (let ([nav (if (list? p) (apply comp-navs p) p)])
                       (nav op data next)))
                   paths)]
        [(transform)
         (fold-left (lambda (d p)
                      (let ([nav (if (list? p) (apply comp-navs p) p)])
                        (nav op d next)))
                    data paths)])))

  ;; stay-then-continue — select current node, then recurse into children
  (define (stay-then-continue op data next)
    (case op
      [(select)
       (next data)
       (when (pair? data) (for-each (lambda (x) (stay-then-continue op x next)) data))]
      [(transform)
       (let ([val (next data)])
         (if (pair? val)
           (map (lambda (x) (stay-then-continue op x next)) val)
           val))]))

  ;; collect — collect the current value into context (for select only)
  (define (collect . path)
    (let ([nav (if (null? path) identity-nav (apply comp-navs path))])
      (lambda (op data next)
        (nav op data next))))

  (define (collect-one . path)
    (apply collect path))

  ;; putval — inject a value into the transform
  (define (putval val)
    (lambda (op data next)
      (case op
        [(select) (next data)]
        [(transform) (next val)])))

  ;; submap — navigate to a sub-hashtable with only the specified keys
  (define (submap keys-list)
    (lambda (op data next)
      (unless (hashtable? data) (error 'submap "not a hash table" data))
      (case op
        [(select)
         (let ([sub (make-hashtable equal-hash equal?)])
           (for-each (lambda (k)
                       (when (hashtable-contains? data k)
                         (hashtable-set! sub k (hashtable-ref data k #f))))
                     keys-list)
           (next sub))]
        [(transform)
         (let* ([sub (make-hashtable equal-hash equal?)])
           (for-each (lambda (k)
                       (when (hashtable-contains? data k)
                         (hashtable-set! sub k (hashtable-ref data k #f))))
                     keys-list)
           (let ([new-sub (next sub)]
                 [result (hashtable-copy data #t)])
             (let-values ([(ks vs) (hashtable-entries new-sub)])
               (do ([i 0 (+ i 1)]) ((= i (vector-length ks)) result)
                 (hashtable-set! result (vector-ref ks i) (vector-ref vs i))))))])))

) ;; end library
