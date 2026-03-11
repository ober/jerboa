#!chezscheme
;;; (std query) -- Query DSL over in-memory collections

(library (std query)
  (export
    ;; Query macro and runtime execute
    query query-execute
    ;; Clause procedures
    from where select order-by group-by limit offset join
    ;; Datasource
    make-datasource datasource? datasource-data
    ;; Predicate constructors
    q:and q:or q:not
    q:= q:< q:> q:<= q:>=
    q:like q:in q:between)

  (import (chezscheme) (std pregexp))

  ;;; ---- Datasource ----

  (define-record-type %datasource
    (fields data)
    (protocol (lambda (new) (lambda (data) (new data)))))

  (define (make-datasource data) (make-%datasource data))
  (define (datasource? x) (%datasource? x))
  (define (datasource-data ds) (%datasource-data ds))

  ;;; ---- Query record ----

  (define-record-type %query
    (fields (mutable collection)
            (mutable predicate)
            (mutable selector)
            (mutable order-key)
            (mutable order-dir)
            (mutable group-key)
            (mutable limit-n)
            (mutable offset-n)
            (mutable join-coll)
            (mutable join-key))
    (protocol (lambda (new)
      (lambda ()
        (new '() #f #f #f 'asc #f #f #f #f #f)))))

  ;;; ---- Field access helpers ----

  (define (get-field record field)
    (cond
      [(procedure? field) (field record)]
      [(symbol? field)
       (cond
         [(and (list? record) (assq field record)) => cdr]
         [(hashtable? record)
          (hashtable-ref record field (hashtable-ref record (symbol->string field) #f))]
         [(vector? record)
          ;; vectors: field is an index
          (if (integer? field) (vector-ref record field) #f)]
         [else #f])]
      [(integer? field)
       (cond
         [(vector? record) (vector-ref record field)]
         [(list? record) (list-ref record field)]
         [else #f])]
      [else #f]))

  ;;; ---- Predicate constructors ----

  (define (q:= field val)
    (lambda (rec) (equal? (get-field rec field) val)))

  (define (q:< field val)
    (lambda (rec) (< (get-field rec field) val)))

  (define (q:> field val)
    (lambda (rec) (> (get-field rec field) val)))

  (define (q:<= field val)
    (lambda (rec) (<= (get-field rec field) val)))

  (define (q:>= field val)
    (lambda (rec) (>= (get-field rec field) val)))

  (define (q:like field pattern)
    ;; pattern: string with % as wildcard
    (let ([rx (string-append "^"
                (apply string-append
                  (map (lambda (s) (if (string=? s "%") ".*" (regexp-quote s)))
                       (split-string-on-char pattern #\%)))
                "$")])
      (lambda (rec)
        (let ([v (get-field rec field)])
          (and (string? v)
               (let ([m (pregexp-match rx v)])
                 (and m #t)))))))

  ;; Helper: split string on char
  (define (split-string-on-char str ch)
    (let loop ([chars (string->list str)] [cur '()] [result '()])
      (cond
        [(null? chars)
         (reverse (cons (list->string (reverse cur)) result))]
        [(char=? (car chars) ch)
         (loop (cdr chars) '() (cons (list->string (reverse cur)) result))]
        [else
         (loop (cdr chars) (cons (car chars) cur) result)])))

  ;; Helper: escape regex special chars
  (define (regexp-quote s)
    (apply string-append
      (map (lambda (c)
             (if (member c '(#\. #\* #\+ #\? #\( #\) #\[ #\] #\{ #\} #\^ #\$ #\| #\\))
               (string #\\ c)
               (string c)))
           (string->list s))))

  (define (q:in field vals)
    (lambda (rec) (member (get-field rec field) vals)))

  (define (q:between field lo hi)
    (lambda (rec)
      (let ([v (get-field rec field)])
        (and (>= v lo) (<= v hi)))))

  (define (q:and . preds)
    (lambda (rec) (for-all (lambda (p) (p rec)) preds)))

  (define (q:or . preds)
    (lambda (rec) (exists (lambda (p) (p rec)) preds)))

  (define (q:not pred)
    (lambda (rec) (not (pred rec))))

  ;;; ---- Pipeline operations ----

  (define (from coll)
    ;; Returns a list from datasource or list
    (cond
      [(%datasource? coll) (%datasource-data coll)]
      [(list? coll) coll]
      [(vector? coll) (vector->list coll)]
      [else (error 'from "expected list, vector, or datasource" coll)]))

  (define (where pred lst)
    (filter pred lst))

  (define (select fields lst)
    (if (eq? fields #t)
      lst
      (map (lambda (rec)
             (cond
               [(procedure? fields) (fields rec)]
               [(list? fields)
                (map (lambda (f) (get-field rec f)) fields)]
               [else (get-field rec fields)]))
           lst)))

  (define (order-by key dir lst)
    (let ([cmp (if (eq? dir 'desc) > <)])
      (list-sort
        (lambda (a b)
          (let ([ka (if (procedure? key) (key a) (get-field a key))]
                [kb (if (procedure? key) (key b) (get-field b key))])
            (cmp ka kb)))
        lst)))

  (define (group-by key lst)
    (let ([groups (make-hashtable equal-hash equal?)])
      (for-each
        (lambda (rec)
          (let* ([k (if (procedure? key) (key rec) (get-field rec key))]
                 [existing (hashtable-ref groups k '())])
            (hashtable-set! groups k (append existing (list rec)))))
        lst)
      (let-values ([(keys vals) (hashtable-entries groups)])
        (map cons (vector->list keys) (vector->list vals)))))

  (define (limit n lst)
    (let loop ([i 0] [l lst] [acc '()])
      (if (or (null? l) (= i n))
        (reverse acc)
        (loop (+ i 1) (cdr l) (cons (car l) acc)))))

  (define (offset n lst)
    (let loop ([i 0] [l lst])
      (if (or (null? l) (= i n))
        l
        (loop (+ i 1) (cdr l)))))

  (define (join coll key lst)
    ;; Inner join: for each record in lst, find matching record in coll
    (let ([coll-list (if (list? coll) coll (from coll))])
      (filter-map
        (lambda (rec)
          (let ([k (if (procedure? key) (key rec) (get-field rec key))])
            (let ([match (find (lambda (r)
                                 (let ([rk (if (procedure? key) (key r) (get-field r key))])
                                   (equal? k rk)))
                               coll-list)])
              (if match (cons rec match) #f))))
        lst)))

  (define (filter-map f lst)
    (let loop ([l lst] [acc '()])
      (if (null? l)
        (reverse acc)
        (let ([v (f (car l))])
          (if v
            (loop (cdr l) (cons v acc))
            (loop (cdr l) acc))))))

  ;;; ---- query-execute: runtime execution ----

  (define (query-execute q)
    ;; q is a %query record
    (let* ([coll (%query-collection q)]
           [lst (from coll)]
           [lst (if (%query-predicate q) (where (%query-predicate q) lst) lst)]
           [lst (if (%query-offset-n q) (offset (%query-offset-n q) lst) lst)]
           [lst (if (%query-limit-n q) (limit (%query-limit-n q) lst) lst)]
           [lst (if (%query-order-key q)
                  (order-by (%query-order-key q) (%query-order-dir q) lst)
                  lst)]
           [lst (if (%query-group-key q) (group-by (%query-group-key q) lst) lst)]
           [lst (if (%query-selector q) (select (%query-selector q) lst) lst)])
      lst))

  ;;; ---- query macro ----
  ;; (query (from coll) clause ...)
  ;; Compiles to a pipeline of operations at macro-expansion time.

  (define-syntax query
    (syntax-rules (from where select order-by group-by limit offset join)
      ;; Base: just from
      [(_ (from coll))
       (from coll)]
      ;; from + where
      [(_ (from coll) (where pred) rest ...)
       (query-pipeline (where pred (from coll)) rest ...)]
      ;; from + select
      [(_ (from coll) (select fields) rest ...)
       (query-pipeline (select fields (from coll)) rest ...)]
      ;; from + order-by
      [(_ (from coll) (order-by key dir) rest ...)
       (query-pipeline (order-by 'key 'dir (from coll)) rest ...)]
      [(_ (from coll) (order-by key) rest ...)
       (query-pipeline (order-by 'key 'asc (from coll)) rest ...)]
      ;; from + group-by
      [(_ (from coll) (group-by key) rest ...)
       (query-pipeline (group-by 'key (from coll)) rest ...)]
      ;; from + limit
      [(_ (from coll) (limit n) rest ...)
       (query-pipeline (limit n (from coll)) rest ...)]
      ;; from + offset
      [(_ (from coll) (offset n) rest ...)
       (query-pipeline (offset n (from coll)) rest ...)]
      ;; from + join
      [(_ (from coll) (join coll2 key) rest ...)
       (query-pipeline (join coll2 'key (from coll)) rest ...)]
      ;; any other single clause
      [(_ (from coll) other-clause rest ...)
       (query-pipeline (from coll) other-clause rest ...)]))

  ;; Helper macro that threads remaining clauses
  (define-syntax query-pipeline
    (syntax-rules (where select order-by group-by limit offset join)
      [(_ lst)
       lst]
      [(_ lst (where pred) rest ...)
       (query-pipeline (where pred lst) rest ...)]
      [(_ lst (select fields) rest ...)
       (query-pipeline (select fields lst) rest ...)]
      [(_ lst (order-by key dir) rest ...)
       (query-pipeline (order-by 'key 'dir lst) rest ...)]
      [(_ lst (order-by key) rest ...)
       (query-pipeline (order-by 'key 'asc lst) rest ...)]
      [(_ lst (group-by key) rest ...)
       (query-pipeline (group-by 'key lst) rest ...)]
      [(_ lst (limit n) rest ...)
       (query-pipeline (limit n lst) rest ...)]
      [(_ lst (offset n) rest ...)
       (query-pipeline (offset n lst) rest ...)]
      [(_ lst (join coll2 key) rest ...)
       (query-pipeline (join coll2 'key lst) rest ...)]
      [(_ lst other rest ...)
       (query-pipeline lst rest ...)]))

) ;; end library
