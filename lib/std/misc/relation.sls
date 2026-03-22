#!chezscheme
;;; (std misc relation) — Relational operations on tabular data
;;;
;;; A relation is a set of rows with named columns, like an in-memory table.
;;;
;;; (define r (make-relation '(name age) '(("Alice" 30) ("Bob" 25))))
;;; (relation-select r (lambda (row) (> (relation-ref row 'age) 27)))
;;; (relation-project r '(name))
;;; (relation-join r1 r2 'id)

(library (std misc relation)
  (export make-relation relation? relation-columns relation-rows relation-count
          relation-ref relation-select relation-project relation-extend
          relation-sort relation-group-by relation-join
          relation->alist-list alist-list->relation
          relation-aggregate)
  (import (chezscheme))

  ;; Internal representation: columns as a list of symbols, rows as a list of alists
  (define-record-type rel
    (fields (immutable cols)    ;; list of symbols
            (immutable data)))  ;; list of alists: ((col . val) ...)

  (define (relation? x)
    (rel? x))

  (define (relation-columns r)
    (rel-cols r))

  (define (relation-rows r)
    (rel-data r))

  (define (relation-count r)
    (length (rel-data r)))

  ;; Get a column value from a row (which is an alist)
  (define (relation-ref row col)
    (let ([pair (assq col row)])
      (if pair
          (cdr pair)
          (error 'relation-ref "column not found" col))))

  ;; Create a relation from column names and rows.
  ;; Rows can be list-of-alists or list-of-lists (positional).
  (define (make-relation columns rows)
    (let ([cols (map (lambda (c)
                       (if (symbol? c) c
                           (error 'make-relation "column name must be a symbol" c)))
                     columns)])
      (make-rel cols (map (lambda (row) (row->alist cols row)) rows))))

  ;; Convert a row to alist form. If already an alist, validate and return.
  ;; If a plain list, zip with column names.
  (define (row->alist cols row)
    (cond
      [(and (pair? row) (pair? (car row)) (symbol? (caar row)))
       ;; Looks like an alist — use as-is
       row]
      [(list? row)
       ;; Plain list — zip with columns
       (unless (= (length row) (length cols))
         (error 'make-relation "row length does not match columns" row cols))
       (map cons cols row)]
      [else (error 'make-relation "row must be a list or alist" row)]))

  ;; Filter rows by predicate on the row alist
  (define (relation-select r pred)
    (make-rel (rel-cols r)
              (filter pred (rel-data r))))

  ;; Select specific columns
  (define (relation-project r cols)
    (let ([project-row (lambda (row)
                         (map (lambda (c)
                                (let ([pair (assq c row)])
                                  (if pair pair
                                      (error 'relation-project
                                             "column not found" c))))
                              cols))])
      (make-rel cols (map project-row (rel-data r)))))

  ;; Add a computed column
  (define (relation-extend r col-name proc)
    (make-rel (append (rel-cols r) (list col-name))
              (map (lambda (row)
                     (append row (list (cons col-name (proc row)))))
                   (rel-data r))))

  ;; Sort rows by a column using the given comparator
  (define (relation-sort r col comparator)
    (make-rel (rel-cols r)
              (list-sort (lambda (a b)
                           (comparator (cdr (assq col a))
                                       (cdr (assq col b))))
                         (rel-data r))))

  ;; Group rows by a column. Returns alist of (key-value . sub-relation).
  (define (relation-group-by r col)
    (let ([groups (make-hashtable equal-hash equal?)]
          [cols (rel-cols r)])
      (for-each (lambda (row)
                  (let* ([key (cdr (assq col row))]
                         [existing (hashtable-ref groups key '())])
                    (hashtable-set! groups key (cons row existing))))
                (rel-data r))
      (let-values ([(keys vals) (hashtable-entries groups)])
        (map (lambda (k v) (cons k (make-rel cols (reverse v))))
             (vector->list keys)
             (vector->list vals)))))

  ;; Inner join two relations on a shared key column
  (define (relation-join r1 r2 key-col)
    (let* ([cols1 (rel-cols r1)]
           [cols2 (rel-cols r2)]
           ;; Merged columns: all of r1, plus r2 cols excluding the key
           [extra-cols (filter (lambda (c) (not (eq? c key-col))) cols2)]
           [merged-cols (append cols1 extra-cols)]
           ;; Index r2 by key for efficiency
           [index (let ([ht (make-hashtable equal-hash equal?)])
                    (for-each (lambda (row)
                                (let* ([k (cdr (assq key-col row))]
                                       [existing (hashtable-ref ht k '())])
                                  (hashtable-set! ht k (cons row existing))))
                              (rel-data r2))
                    ht)])
      (make-rel merged-cols
                (apply append
                  (map (lambda (row1)
                         (let* ([k (cdr (assq key-col row1))]
                                [matches (hashtable-ref index k '())])
                           (map (lambda (row2)
                                  (append row1
                                          (filter (lambda (pair)
                                                    (not (eq? (car pair) key-col)))
                                                  row2)))
                                matches)))
                       (rel-data r1))))))

  ;; Export as list of alists
  (define (relation->alist-list r)
    (rel-data r))

  ;; Import from list of alists
  (define (alist-list->relation alist-list)
    (if (null? alist-list)
        (make-rel '() '())
        (let ([cols (map car (car alist-list))])
          (make-rel cols alist-list))))

  ;; Aggregate: fold over a column's values
  (define (relation-aggregate r col proc init)
    (fold-left (lambda (acc row)
                 (proc acc (cdr (assq col row))))
               init
               (rel-data r)))

) ;; end library
