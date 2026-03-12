#!chezscheme
;;; (std dataframe) — Tabular data with column-oriented storage
;;;
;;; A dataframe stores data as a vector of column vectors.
;;; All transformations return new dataframes (immutable API).
;;;
;;; Record layout:
;;;   columns : vector of symbols (column names)
;;;   data    : vector of vectors (one per column, all same length)

(library (std dataframe)
  (export
    ;; Creation
    make-dataframe
    dataframe?
    dataframe-columns
    dataframe-nrow
    dataframe-ncol
    ;; Access
    dataframe-column
    dataframe-row
    dataframe-ref
    dataframe-head
    dataframe-tail
    ;; Construction
    dataframe-from-alists
    dataframe-from-vectors
    dataframe->alists
    dataframe->vectors
    ;; Transformation
    dataframe-select
    dataframe-drop
    dataframe-filter
    dataframe-map
    dataframe-mutate
    dataframe-rename
    dataframe-sort
    dataframe-join
    dataframe-left-join
    dataframe-append
    ;; Aggregation
    dataframe-group-by
    dataframe-summarize
    dataframe-count
    ;; Stats
    col-sum col-mean col-min col-max col-median col-std
    ;; I/O
    dataframe->csv-string
    dataframe-from-csv-string
    ;; Display
    dataframe-display
    dataframe-describe)

  (import (chezscheme))

  ;; ======================================================================
  ;; Internal record
  ;; ======================================================================

  (define-record-type df-record
    (fields
      (immutable columns)   ;; vector of symbols
      (immutable data))     ;; vector of vectors (column-major)
    (sealed #t))

  (define (dataframe? x) (df-record? x))

  ;; Build a df from parallel symbol-vector lists (already validated).
  (define (%make-df cols data)
    (make-df-record (list->vector cols) (list->vector data)))

  ;; ======================================================================
  ;; make-dataframe
  ;; ======================================================================

  ;; (make-dataframe columns data)
  ;;   columns : list of symbols
  ;;   data    : list of lists  — each inner list is one column's values
  (define (make-dataframe columns data)
    (unless (list? columns)
      (error 'make-dataframe "columns must be a list of symbols" columns))
    (let* ([ncol (length columns)]
           [vecs (map list->vector data)])
      (unless (= (length data) ncol)
        (error 'make-dataframe "number of data lists must equal number of columns"))
      (when (> ncol 0)
        (let ([n (vector-length (car vecs))])
          (for-each (lambda (v)
                      (unless (= (vector-length v) n)
                        (error 'make-dataframe "all columns must have equal length")))
                    vecs)))
      (%make-df columns vecs)))

  ;; ======================================================================
  ;; Basic accessors
  ;; ======================================================================

  (define (dataframe-columns df) (vector->list (df-record-columns df)))
  (define (dataframe-ncol df) (vector-length (df-record-columns df)))
  (define (dataframe-nrow df)
    (if (= (vector-length (df-record-data df)) 0)
      0
      (vector-length (vector-ref (df-record-data df) 0))))

  ;; Find column index (or error).
  (define (%col-index df col-name)
    (let ([cols (df-record-columns df)])
      (let loop ([i 0])
        (cond
          [(= i (vector-length cols))
           (error 'dataframe-column "column not found" col-name)]
          [(eq? (vector-ref cols i) col-name) i]
          [else (loop (+ i 1))]))))

  (define (dataframe-column df col-name)
    (vector-copy (vector-ref (df-record-data df) (%col-index df col-name))))

  (define (dataframe-row df i)
    (let ([cols (df-record-columns df)]
          [data (df-record-data df)])
      (let loop ([j 0] [acc '()])
        (if (= j (vector-length cols))
          (reverse acc)
          (loop (+ j 1)
                (cons (cons (vector-ref cols j)
                            (vector-ref (vector-ref data j) i))
                      acc))))))

  (define (dataframe-ref df row col)
    (vector-ref (vector-ref (df-record-data df) (%col-index df col)) row))

  ;; ======================================================================
  ;; Head / Tail
  ;; ======================================================================

  (define (dataframe-head df n)
    (let* ([nrow (min n (dataframe-nrow df))]
           [cols (dataframe-columns df)]
           [data (df-record-data df)])
      (%make-df cols
        (map (lambda (i) (vector-copy (vector-ref data i) 0 nrow))
             (iota (vector-length (df-record-columns df)))))))

  (define (dataframe-tail df n)
    (let* ([nrow (dataframe-nrow df)]
           [start (max 0 (- nrow n))]
           [count (- nrow start)]
           [cols (dataframe-columns df)]
           [data (df-record-data df)])
      (%make-df cols
        (map (lambda (i) (vector-copy (vector-ref data i) start count))
             (iota (vector-length (df-record-columns df)))))))

  ;; ======================================================================
  ;; Construction helpers
  ;; ======================================================================

  ;; (dataframe-from-alists (list alist ...)) — each alist is one row
  (define (dataframe-from-alists alists)
    (if (null? alists)
      (%make-df '() '())
      (let* ([cols (map car (car alists))]
             [nrow (length alists)]
             [ncol (length cols)]
             [vecs (make-vector ncol #f)])
        ;; Initialize column vectors
        (let loop ([j 0])
          (when (< j ncol)
            (vector-set! vecs j (make-vector nrow #f))
            (loop (+ j 1))))
        ;; Fill row by row
        (let row-loop ([row alists] [i 0])
          (unless (null? row)
            (for-each
              (lambda (pair j)
                (vector-set! (vector-ref vecs j) i (cdr pair)))
              (car row)
              (iota ncol))
            (row-loop (cdr row) (+ i 1))))
        (%make-df cols (vector->list vecs)))))

  ;; (dataframe-from-vectors col-names (list vec ...))
  (define (dataframe-from-vectors col-names vecs)
    (%make-df col-names (map vector-copy vecs)))

  ;; (dataframe->alists df) — list of row alists
  (define (dataframe->alists df)
    (let ([nrow (dataframe-nrow df)])
      (map (lambda (i) (dataframe-row df i)) (iota nrow))))

  ;; (dataframe->vectors df) — list of (col-name . vector) pairs
  (define (dataframe->vectors df)
    (map (lambda (col) (cons col (dataframe-column df col)))
         (dataframe-columns df)))

  ;; ======================================================================
  ;; Selection and dropping
  ;; ======================================================================

  (define (dataframe-select df . col-names)
    (let ([data (df-record-data df)])
      (%make-df col-names
        (map (lambda (col)
               (vector-copy (vector-ref data (%col-index df col))))
             col-names))))

  (define (dataframe-drop df . col-names)
    (let ([keep (filter (lambda (c) (not (memq c col-names)))
                        (dataframe-columns df))])
      (apply dataframe-select df keep)))

  ;; ======================================================================
  ;; Filter / Map / Mutate
  ;; ======================================================================

  ;; (dataframe-filter df pred) — pred takes a row alist
  (define (dataframe-filter df pred)
    (let* ([cols (dataframe-columns df)]
           [data (df-record-data df)]
           [ncol (length cols)]
           [nrow (dataframe-nrow df)]
           [new-rows '()])
      ;; Collect row indices satisfying pred
      (let loop ([i 0] [acc '()])
        (if (= i nrow)
          (let ([kept (reverse acc)])
            (let ([new-nrow (length kept)])
              (%make-df cols
                (map (lambda (j)
                       (let ([src (vector-ref data j)]
                             [dst (make-vector new-nrow #f)])
                         (let fill ([rows kept] [k 0])
                           (unless (null? rows)
                             (vector-set! dst k (vector-ref src (car rows)))
                             (fill (cdr rows) (+ k 1))))
                         dst))
                     (iota ncol)))))
          (let ([row-alist (dataframe-row df i)])
            (loop (+ i 1)
                  (if (pred row-alist)
                    (cons i acc)
                    acc)))))))

  ;; (dataframe-map df proc) — proc maps row alist -> row alist
  (define (dataframe-map df proc)
    (let ([nrow (dataframe-nrow df)])
      (dataframe-from-alists
        (map (lambda (i) (proc (dataframe-row df i)))
             (iota nrow)))))

  ;; (dataframe-mutate df col-name expr-proc)
  ;; expr-proc takes a row alist and returns the new value for col-name
  (define (dataframe-mutate df col-name expr-proc)
    (let* ([cols (dataframe-columns df)]
           [data (df-record-data df)]
           [nrow (dataframe-nrow df)]
           [ncol (length cols)]
           [new-col (make-vector nrow #f)])
      ;; Fill new column
      (let loop ([i 0])
        (when (< i nrow)
          (vector-set! new-col i (expr-proc (dataframe-row df i)))
          (loop (+ i 1))))
      ;; Check if col-name already exists
      (let ([existing-idx
             (let loop ([j 0])
               (cond
                 [(= j ncol) #f]
                 [(eq? (vector-ref (df-record-columns df) j) col-name) j]
                 [else (loop (+ j 1))]))])
        (if existing-idx
          ;; Replace existing column
          (let ([new-data (vector-copy data)])
            (vector-set! new-data existing-idx new-col)
            (make-df-record (df-record-columns df) new-data))
          ;; Append new column
          (%make-df (append cols (list col-name))
            (append (map (lambda (j) (vector-copy (vector-ref data j)))
                         (iota ncol))
                    (list new-col)))))))

  ;; (dataframe-rename df old-name new-name)
  (define (dataframe-rename df old-name new-name)
    (let ([cols (df-record-columns df)])
      (make-df-record
        (vector-map (lambda (c) (if (eq? c old-name) new-name c)) cols)
        (df-record-data df))))

  ;; ======================================================================
  ;; Sort
  ;; ======================================================================

  ;; (dataframe-sort df col [less?])
  (define (dataframe-sort df col . rest)
    (let* ([less? (if (null? rest) < (car rest))]
           [nrow (dataframe-nrow df)]
           [col-vec (vector-ref (df-record-data df) (%col-index df col))]
           [indices (list->vector (iota nrow))])
      ;; Sort indices by col values
      (vector-sort!
        (lambda (a b) (less? (vector-ref col-vec a) (vector-ref col-vec b)))
        indices)
      ;; Reorder all columns
      (let* ([cols (dataframe-columns df)]
             [data (df-record-data df)]
             [ncol (length cols)])
        (%make-df cols
          (map (lambda (j)
                 (let ([src (vector-ref data j)]
                       [dst (make-vector nrow #f)])
                   (let loop ([k 0])
                     (when (< k nrow)
                       (vector-set! dst k (vector-ref src (vector-ref indices k)))
                       (loop (+ k 1))))
                   dst))
               (iota ncol))))))

  ;; ======================================================================
  ;; Joins
  ;; ======================================================================

  ;; Inner join: keep rows where key exists in both df1 and df2.
  (define (dataframe-join df1 df2 key)
    (%join-impl df1 df2 key 'inner))

  ;; Left join: keep all rows from df1, fill df2 cols with #f if no match.
  (define (dataframe-left-join df1 df2 key)
    (%join-impl df1 df2 key 'left))

  (define (%join-impl df1 df2 key join-type)
    (let* ([cols1 (dataframe-columns df1)]
           [cols2 (filter (lambda (c) (not (eq? c key)))
                          (dataframe-columns df2))]
           [all-cols (append cols1 cols2)]
           [ncols2 (length cols2)]
           [nrow1 (dataframe-nrow df1)]
           [nrow2 (dataframe-nrow df2)]
           ;; Build lookup table: key-val -> first row index in df2
           [lookup (make-hashtable equal-hash equal?)])
      (let loop ([i 0])
        (when (< i nrow2)
          (let ([kv (dataframe-ref df2 i key)])
            (unless (hashtable-ref lookup kv #f)
              (hashtable-set! lookup kv i)))
          (loop (+ i 1))))
      ;; Build result rows
      (let ([result-rows '()])
        (let loop ([i (- nrow1 1)])
          (when (>= i 0)
            (let* ([kv (dataframe-ref df1 i key)]
                   [j  (hashtable-ref lookup kv #f)])
              (when (or j (eq? join-type 'left))
                (let ([row1 (dataframe-row df1 i)]
                      [row2 (if j
                              (filter (lambda (p) (not (eq? (car p) key)))
                                      (dataframe-row df2 j))
                              (map (lambda (c) (cons c #f)) cols2))])
                  (set! result-rows (cons (append row1 row2) result-rows)))))
            (loop (- i 1))))
        (dataframe-from-alists result-rows))))

  ;; ======================================================================
  ;; Append (concatenate rows)
  ;; ======================================================================

  (define (dataframe-append df1 df2)
    (let* ([cols (dataframe-columns df1)]
           [data1 (df-record-data df1)]
           [data2 (df-record-data df2)]
           [nrow1 (dataframe-nrow df1)]
           [nrow2 (dataframe-nrow df2)]
           [ncol (length cols)])
      (%make-df cols
        (map (lambda (j)
               (let* ([v1 (vector-ref data1 j)]
                      [v2 (vector-ref data2 j)]
                      [out (make-vector (+ nrow1 nrow2) #f)])
                 (let loop1 ([k 0]) (when (< k nrow1) (vector-set! out k (vector-ref v1 k)) (loop1 (+ k 1))))
                 (let loop2 ([k 0]) (when (< k nrow2) (vector-set! out (+ nrow1 k) (vector-ref v2 k)) (loop2 (+ k 1))))
                 out))
             (iota ncol)))))

  ;; ======================================================================
  ;; Group-by and Summarize
  ;; ======================================================================

  ;; (dataframe-group-by df col ...) -> hashtable: group-key -> sub-df
  (define (dataframe-group-by df . group-cols)
    (let* ([nrow (dataframe-nrow df)]
           [groups (make-hashtable equal-hash equal?)]
           ;; For each row, compute group key and accumulate row indices
           [key-rows (make-hashtable equal-hash equal?)])
      (let loop ([i 0])
        (when (< i nrow)
          (let ([key (map (lambda (col) (dataframe-ref df i col)) group-cols)])
            (hashtable-update! key-rows key
              (lambda (lst) (cons i lst)) '()))
          (loop (+ i 1))))
      ;; Build sub-dataframes
      (let-values ([(keys row-lists) (hashtable-entries key-rows)])
        (let loop ([k 0])
          (when (< k (vector-length keys))
            (let* ([key (vector-ref keys k)]
                   [rows (reverse (vector-ref row-lists k))]
                   [sub-df (%rows-subset df rows)])
              (hashtable-set! groups key sub-df))
            (loop (+ k 1)))))
      groups))

  ;; Build a sub-dataframe from a list of row indices.
  (define (%rows-subset df rows)
    (let* ([cols (dataframe-columns df)]
           [data (df-record-data df)]
           [ncol (length cols)]
           [n    (length rows)])
      (%make-df cols
        (map (lambda (j)
               (let ([src (vector-ref data j)]
                     [dst (make-vector n #f)])
                 (let fill ([rs rows] [k 0])
                   (unless (null? rs)
                     (vector-set! dst k (vector-ref src (car rs)))
                     (fill (cdr rs) (+ k 1))))
                 dst))
             (iota ncol)))))

  ;; (dataframe-summarize grouped-df (col agg-fn) ...) -> df
  (define (dataframe-summarize groups . agg-specs)
    ;; groups is a hashtable key -> sub-df
    ;; agg-specs: list of (col-name agg-fn) pairs
    (let-values ([(keys sub-dfs) (hashtable-entries groups)])
      (let ([rows '()])
        (let loop ([k 0])
          (when (< k (vector-length keys))
            (let* ([key    (vector-ref keys k)]
                   [sub-df (vector-ref sub-dfs k)]
                   [agg-vals
                    (map (lambda (spec)
                           (let ([col-name (car spec)]
                                 [agg-fn   (cadr spec)])
                             (cons col-name
                                   (agg-fn (dataframe-column sub-df col-name)))))
                         agg-specs)])
              ;; key is a list of group values; build a row alist
              (set! rows (cons agg-vals rows)))
            (loop (+ k 1))))
        (dataframe-from-alists (reverse rows)))))

  ;; (dataframe-count groups) -> df with 'n column
  (define (dataframe-count groups)
    (let-values ([(keys sub-dfs) (hashtable-entries groups)])
      (let ([rows '()])
        (let loop ([k 0])
          (when (< k (vector-length keys))
            (let* ([key    (vector-ref keys k)]
                   [sub-df (vector-ref sub-dfs k)]
                   [n      (dataframe-nrow sub-df)])
              (set! rows (cons (list (cons 'n n)) rows)))
            (loop (+ k 1))))
        (dataframe-from-alists (reverse rows)))))

  ;; ======================================================================
  ;; Stats on column vectors
  ;; ======================================================================

  (define (col-sum vec)
    (let ([n (vector-length vec)])
      (let loop ([i 0] [s 0])
        (if (= i n) s (loop (+ i 1) (+ s (vector-ref vec i)))))))

  (define (col-mean vec)
    (let ([n (vector-length vec)])
      (if (= n 0) 0 (/ (col-sum vec) n))))

  (define (col-min vec)
    (let ([n (vector-length vec)])
      (if (= n 0) +inf.0
        (let loop ([i 1] [m (vector-ref vec 0)])
          (if (= i n) m (loop (+ i 1) (min m (vector-ref vec i))))))))

  (define (col-max vec)
    (let ([n (vector-length vec)])
      (if (= n 0) -inf.0
        (let loop ([i 1] [m (vector-ref vec 0)])
          (if (= i n) m (loop (+ i 1) (max m (vector-ref vec i))))))))

  (define (col-median vec)
    (let* ([n (vector-length vec)]
           [sorted (vector-sort < (vector-copy vec))])
      (if (= n 0) 0
        (if (odd? n)
          (vector-ref sorted (quotient n 2))
          (/ (+ (vector-ref sorted (- (quotient n 2) 1))
                (vector-ref sorted (quotient n 2)))
             2)))))

  (define (col-std vec)
    (let* ([n (vector-length vec)]
           [m (col-mean vec)])
      (if (<= n 1) 0
        (let ([variance
               (let loop ([i 0] [s 0])
                 (if (= i n) (/ s (- n 1))
                   (let ([d (- (vector-ref vec i) m)])
                     (loop (+ i 1) (+ s (* d d))))))])
          (sqrt variance)))))

  ;; ======================================================================
  ;; CSV I/O
  ;; ======================================================================

  ;; Simple CSV serialization (no quoting of commas inside values).
  (define (dataframe->csv-string df)
    (let* ([cols (dataframe-columns df)]
           [nrow (dataframe-nrow df)]
           [port (open-output-string)])
      ;; Header
      (for-each (lambda (c i)
                  (when (> i 0) (write-char #\, port))
                  (display (symbol->string c) port))
                cols
                (iota (length cols)))
      (newline port)
      ;; Rows
      (let loop ([i 0])
        (when (< i nrow)
          (for-each (lambda (col j)
                      (when (> j 0) (write-char #\, port))
                      (let ([v (dataframe-ref df i col)])
                        (display v port)))
                    cols
                    (iota (length cols)))
          (newline port)
          (loop (+ i 1))))
      (get-output-string port)))

  ;; Parse a CSV string. First row is header.
  (define (dataframe-from-csv-string str)
    (let* ([lines (string-split-lines str)]
           [non-empty (filter (lambda (s) (> (string-length s) 0)) lines)])
      (if (null? non-empty)
        (%make-df '() '())
        (let* ([header  (map string->symbol (split-csv-line (car non-empty)))]
               [data-lines (cdr non-empty)]
               [rows    (map split-csv-line data-lines)]
               [nrow    (length rows)]
               [ncol    (length header)]
               [vecs    (make-vector ncol #f)])
          (let loop ([j 0])
            (when (< j ncol)
              (vector-set! vecs j (make-vector nrow #f))
              (loop (+ j 1))))
          (let row-loop ([rs rows] [i 0])
            (unless (null? rs)
              (let col-loop ([cells (car rs)] [j 0])
                (unless (or (null? cells) (= j ncol))
                  (vector-set! (vector-ref vecs j) i
                    (%parse-csv-value (car cells)))
                  (col-loop (cdr cells) (+ j 1))))
              (row-loop (cdr rs) (+ i 1))))
          (%make-df header (vector->list vecs))))))

  (define (string-split-lines s)
    (let loop ([i 0] [start 0] [acc '()])
      (cond
        [(= i (string-length s))
         (reverse (cons (substring s start i) acc))]
        [(char=? (string-ref s i) #\newline)
         (loop (+ i 1) (+ i 1) (cons (substring s start i) acc))]
        [else (loop (+ i 1) start acc)])))

  (define (split-csv-line line)
    (let loop ([i 0] [start 0] [acc '()])
      (cond
        [(= i (string-length line))
         (reverse (cons (substring line start i) acc))]
        [(char=? (string-ref line i) #\,)
         (loop (+ i 1) (+ i 1) (cons (substring line start i) acc))]
        [else (loop (+ i 1) start acc)])))

  (define (%parse-csv-value s)
    (let ([n (string->number s)])
      (or n s)))

  ;; ======================================================================
  ;; Display
  ;; ======================================================================

  (define (dataframe-display df)
    (let* ([cols (dataframe-columns df)]
           [nrow (dataframe-nrow df)]
           [ncol (length cols)]
           ;; Compute column widths
           [widths
            (map (lambda (col)
                   (let ([header-w (string-length (symbol->string col))])
                     (let loop ([i 0] [w header-w])
                       (if (= i nrow) w
                         (loop (+ i 1)
                               (max w (string-length
                                        (format "~a" (dataframe-ref df i col)))))))))
                 cols)])
      ;; Header
      (for-each (lambda (col w)
                  (let ([s (symbol->string col)])
                    (display (string-pad-right s w))
                    (display "  ")))
                cols widths)
      (newline)
      ;; Separator
      (for-each (lambda (w)
                  (display (make-string w #\-))
                  (display "  "))
                widths)
      (newline)
      ;; Rows
      (let loop ([i 0])
        (when (< i nrow)
          (for-each (lambda (col w)
                      (let ([s (format "~a" (dataframe-ref df i col))])
                        (display (string-pad-right s w))
                        (display "  ")))
                    cols widths)
          (newline)
          (loop (+ i 1))))))

  (define (string-pad-right s w)
    (let ([n (string-length s)])
      (if (>= n w) s (string-append s (make-string (- w n) #\space)))))

  ;; (dataframe-describe df) — summary statistics per numeric column
  (define (dataframe-describe df)
    (let* ([cols (dataframe-columns df)]
           [stats '(min max mean median std)])
      (for-each
        (lambda (col)
          (let ([vec (dataframe-column df col)])
            (let ([nums (vector->list
                          (vector-filter number? vec))])
              (when (not (null? nums))
                (let ([v (list->vector nums)])
                  (printf "~a: n=~a min=~a max=~a mean=~a median=~a std=~a~%"
                    col
                    (vector-length v)
                    (col-min v) (col-max v)
                    (col-mean v) (col-median v)
                    (col-std v)))))))
        cols)))

  (define (vector-filter pred v)
    (list->vector (filter pred (vector->list v))))

  ) ;; end library
