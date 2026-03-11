#!chezscheme
;;; (std table) — Columnar Data Tables (Step 40)
;;;
;;; In-memory data tables with SQL-like operations.
;;; Columnar storage for cache efficiency.

(library (std table)
  (export
    ;; Construction
    make-table
    table?
    table-columns
    table-row-count
    table-column-names

    ;; Data access
    table-column
    table-row
    table-ref
    table-rows

    ;; Building
    table-add-row!
    table-from-rows
    table-from-alist

    ;; SQL-like operations
    table-select
    table-where
    table-group-by
    table-sort-by
    table-take
    table-drop
    table-join
    table-aggregate

    ;; Aggregation functions
    agg-count
    agg-sum
    agg-mean
    agg-min
    agg-max
    agg-collect

    ;; Output
    table-print
    table->list)

  (import (chezscheme))

  ;; ========== Table Structure ==========

  ;; Table: #(tag col-names col-data row-count)
  ;; col-data: vector of vectors (one per column)

  (define (make-table col-names)
    (vector 'table
            (list->vector col-names)
            (list->vector (map (lambda (_) (make-vector 0)) col-names))
            0))

  (define (table? x)
    (and (vector? x) (= (vector-length x) 4) (eq? (vector-ref x 0) 'table)))

  (define (table-col-names-vec t)  (vector-ref t 1))
  (define (table-col-data-vec t)   (vector-ref t 2))
  (define (table-row-count t)      (vector-ref t 3))

  (define (table-column-names t)
    (vector->list (table-col-names-vec t)))

  (define (table-columns t)
    (vector-length (table-col-names-vec t)))

  (define (col-index t name)
    (let ([names (table-col-names-vec t)])
      (let loop ([i 0])
        (cond
          [(= i (vector-length names)) (error 'table-ref "column not found" name)]
          [(equal? (vector-ref names i) name) i]
          [else (loop (+ i 1))]))))

  (define (table-column t col-name)
    ;; Return column as a list.
    (let ([idx (col-index t col-name)]
          [data (table-col-data-vec t)]
          [n (table-row-count t)])
      (let ([col (vector-ref data idx)])
        (let loop ([i 0] [acc '()])
          (if (= i n)
            (reverse acc)
            (loop (+ i 1) (cons (vector-ref col i) acc)))))))

  (define (table-row t row-idx)
    ;; Return row as alist (col-name . value).
    (let ([names (table-col-names-vec t)]
          [data  (table-col-data-vec t)])
      (let loop ([i 0] [acc '()])
        (if (= i (vector-length names))
          (reverse acc)
          (loop (+ i 1)
                (cons (cons (vector-ref names i)
                            (vector-ref (vector-ref data i) row-idx))
                      acc))))))

  (define (table-ref t row-idx col-name)
    (let ([idx (col-index t col-name)])
      (vector-ref (vector-ref (table-col-data-vec t) idx) row-idx)))

  (define (table-rows t)
    (map (lambda (i) (table-row t i))
         (let loop ([i 0] [acc '()])
           (if (= i (table-row-count t))
             (reverse acc)
             (loop (+ i 1) (cons i acc))))))

  ;; ========== Building Tables ==========

  (define (grow-col col old-size)
    (let* ([new-size (max 1 (* old-size 2))]
           [new-vec  (make-vector new-size #f)])
      (let loop ([i 0])
        (when (< i old-size)
          (vector-set! new-vec i (vector-ref col i))
          (loop (+ i 1))))
      new-vec))

  (define (table-add-row! t row-alist)
    ;; Add a row to the table (row-alist: list of (col-name . value)).
    (let* ([n      (table-row-count t)]
           [names  (table-col-names-vec t)]
           [data   (table-col-data-vec t)])
      ;; Ensure capacity in each column
      (let loop ([i 0])
        (when (< i (vector-length names))
          (let ([col (vector-ref data i)])
            (when (>= n (vector-length col))
              (vector-set! data i (grow-col col (vector-length col)))))
          (loop (+ i 1))))
      ;; Set values
      (for-each
        (lambda (pair)
          (let ([idx (col-index t (car pair))])
            (vector-set! (vector-ref data idx) n (cdr pair))))
        row-alist)
      (vector-set! t 3 (+ n 1))))

  (define (table-from-rows col-names rows)
    ;; rows: list of lists (one value per column, in col-names order)
    (let ([t (make-table col-names)])
      (for-each
        (lambda (row)
          (table-add-row! t
            (map cons col-names row)))
        rows)
      t))

  (define (table-from-alist col-names data-alist)
    ;; data-alist: list of ((col . value) ...) per row
    (let ([t (make-table col-names)])
      (for-each (lambda (row) (table-add-row! t row)) data-alist)
      t))

  (define (kwarg key opts . default-args)
    (let ([default (if (null? default-args) #f (car default-args))])
      (let loop ([lst opts])
        (cond [(or (null? lst) (null? (cdr lst))) default]
              [(eq? (car lst) key) (cadr lst)]
              [else (loop (cddr lst))]))))

  ;; ========== SQL-Like Operations ==========

  (define (table-select t col-names)
    ;; Select a subset of columns.
    (let* ([idxs (map (lambda (n) (col-index t n)) col-names)]
           [result (make-table col-names)]
           [src-data (table-col-data-vec t)]
           [n (table-row-count t)])
      (let loop ([r 0])
        (when (< r n)
          (table-add-row! result
            (map (lambda (name idx)
                   (cons name (vector-ref (vector-ref src-data idx) r)))
                 col-names idxs))
          (loop (+ r 1))))
      result))

  (define (table-where t pred)
    ;; Filter rows where pred returns #t for the row alist.
    (let* ([result (make-table (table-column-names t))]
           [n (table-row-count t)])
      (let loop ([r 0])
        (when (< r n)
          (let ([row (table-row t r)])
            (when (pred row)
              (table-add-row! result row)))
          (loop (+ r 1))))
      result))

  (define (table-group-by t col-name)
    ;; Group rows by col-name. Returns hashtable: value → table.
    (let ([groups (make-hashtable equal-hash equal?)]
          [n      (table-row-count t)])
      (let loop ([r 0])
        (when (< r n)
          (let* ([row (table-row t r)]
                 [key (cdr (assoc col-name row))])
            (let ([group (hashtable-ref groups key #f)])
              (if group
                (table-add-row! group row)
                (let ([new-group (make-table (table-column-names t))])
                  (table-add-row! new-group row)
                  (hashtable-set! groups key new-group)))))
          (loop (+ r 1))))
      groups))

  (define (table-sort-by t col-name . opts)
    (let* ([descending? (kwarg 'descending: opts)]
           [rows   (table-rows t)]
           [sorted (list-sort
                     (lambda (a b)
                       (let ([va (cdr (assoc col-name a))]
                             [vb (cdr (assoc col-name b))])
                         (if descending?
                           (if (number? va) (> va vb) (string>? (format "~a" va) (format "~a" vb)))
                           (if (number? va) (< va vb) (string<? (format "~a" va) (format "~a" vb))))))
                     rows)])
      (table-from-alist (table-column-names t) sorted)))

  (define (table-take t n)
    (let* ([result (make-table (table-column-names t))]
           [limit  (min n (table-row-count t))])
      (let loop ([r 0])
        (when (< r limit)
          (table-add-row! result (table-row t r))
          (loop (+ r 1))))
      result))

  (define (table-drop t n)
    (let* ([result (make-table (table-column-names t))]
           [total  (table-row-count t)])
      (let loop ([r n])
        (when (< r total)
          (table-add-row! result (table-row t r))
          (loop (+ r 1))))
      result))

  (define (table-join t1 t2 key)
    ;; Inner join on a shared column key.
    (let* ([col-names1 (table-column-names t1)]
           [col-names2 (filter (lambda (c) (not (equal? c key)))
                               (table-column-names t2))]
           [result-cols (append col-names1 col-names2)]
           [result      (make-table result-cols)]
           [n1 (table-row-count t1)]
           [n2 (table-row-count t2)])
      (let loop1 ([r1 0])
        (when (< r1 n1)
          (let* ([row1 (table-row t1 r1)]
                 [val1 (cdr (assoc key row1))])
            (let loop2 ([r2 0])
              (when (< r2 n2)
                (let* ([row2 (table-row t2 r2)]
                       [val2 (cdr (assoc key row2))])
                  (when (equal? val1 val2)
                    (table-add-row! result
                      (append row1
                              (filter (lambda (p) (not (equal? (car p) key)))
                                      row2)))))
                (loop2 (+ r2 1)))))
          (loop1 (+ r1 1))))
      result))

  (define (table-aggregate groups . agg-specs)
    ;; Apply aggregation functions to grouped tables.
    ;; agg-specs: (result-col-name agg-fn col-name) ...
    ;; Returns a new table with one row per group.
    (let* ([spec-triples
            (let loop ([specs agg-specs] [acc '()])
              (if (null? specs)
                (reverse acc)
                (loop (cdddr specs)
                      (cons (list (car specs) (cadr specs) (caddr specs))
                            acc))))]
           [result-cols (map car spec-triples)])
      (let ([result (make-table result-cols)])
        (let-values ([(keys tables) (hashtable-entries groups)])
          (vector-for-each
            (lambda (key tbl)
              (table-add-row! result
                (map (lambda (spec)
                       (let ([col-name (car spec)]
                             [agg-fn   (cadr spec)]
                             [src-col  (caddr spec)])
                         (cons col-name
                               (agg-fn (table-column tbl src-col)))))
                     spec-triples)))
            keys tables))
        result)))

  ;; ========== Aggregation Functions ==========

  (define (agg-count col)
    (length col))

  (define (agg-sum col)
    (apply + col))

  (define (agg-mean col)
    (if (null? col) 0
      (/ (apply + col) (length col))))

  (define (agg-min col)
    (if (null? col) #f
      (apply min col)))

  (define (agg-max col)
    (if (null? col) #f
      (apply max col)))

  (define (agg-collect col)
    col)

  ;; ========== Output ==========

  (define (table-print t . port-args)
    (let* ([port  (if (null? port-args) (current-output-port) (car port-args))]
           [names (table-column-names t)]
           [n     (table-row-count t)])
      ;; Header
      (for-each (lambda (name) (fprintf port "~10a " name)) names)
      (newline port)
      (fprintf port "~a~%" (make-string (+ (* 11 (length names)) 1) #\-))
      ;; Rows
      (let loop ([r 0])
        (when (< r n)
          (for-each
            (lambda (name)
              (fprintf port "~10a " (table-ref t r name)))
            names)
          (newline port)
          (loop (+ r 1))))))

  (define (table->list t)
    ;; Return list of alists.
    (table-rows t))

  ) ;; end library
