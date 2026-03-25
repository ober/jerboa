#!chezscheme
;;; (std db duckdb) — DuckDB high-level interface
;;;
;;; Wraps (std db duckdb-native) with DBI driver registration
;;; and a friendlier API returning vectors for rows.

(library (std db duckdb)
  (export
    ;; Core
    duckdb-open duckdb-close
    duckdb-exec duckdb-eval duckdb-query
    ;; Prepared statements
    duckdb-prepare duckdb-finalize duckdb-reset
    ;; Binding
    duckdb-bind!
    ;; Result access
    duckdb-execute duckdb-free-result
    duckdb-nrows duckdb-ncols
    duckdb-column-name duckdb-column-type
    duckdb-value duckdb-value-is-null?
    ;; Metadata
    duckdb-version
    ;; Parquet / CSV convenience
    duckdb-read-parquet duckdb-read-csv
    duckdb-write-parquet duckdb-write-csv
    ;; Constants
    DUCKDB_INTEGER DUCKDB_FLOAT DUCKDB_TEXT DUCKDB_BLOB
    DUCKDB_NULL DUCKDB_BOOLEAN)

  (import
    (chezscheme)
    (std db duckdb-native))

  ;; --- Bind by type ---

  (define (duckdb-bind! stmt index value)
    (cond
      [(not value)       (duckdb-bind-null stmt index)]
      [(boolean? value)  (duckdb-bind-bool stmt index value)]
      [(integer? value)  (duckdb-bind-int stmt index value)]
      [(flonum? value)   (duckdb-bind-double stmt index value)]
      [(string? value)   (duckdb-bind-text stmt index value)]
      [(bytevector? value) (duckdb-bind-blob stmt index value)]
      [else (error 'duckdb-bind! "unsupported type" value)]))

  ;; --- Value access by type ---

  (define (duckdb-value result col row)
    (if (duckdb-value-is-null? result col row)
      #f
      (let ([typ (duckdb-column-type result col)])
        (cond
          [(= typ DUCKDB_INTEGER) (duckdb-value-int result col row)]
          [(= typ DUCKDB_FLOAT)   (duckdb-value-double result col row)]
          [(= typ DUCKDB_TEXT)    (duckdb-value-text result col row)]
          [(= typ DUCKDB_BLOB)    (duckdb-value-blob result col row)]
          [(= typ DUCKDB_BOOLEAN) (duckdb-value-bool result col row)]
          [else (duckdb-value-text result col row)]))))

  ;; --- Parquet / CSV convenience ---
  ;; DuckDB can read/write Parquet and CSV natively via SQL.

  (define (duckdb-read-parquet handle path)
    (duckdb-query handle
      (string-append "SELECT * FROM read_parquet('" path "')")))

  (define (duckdb-read-csv handle path)
    (duckdb-query handle
      (string-append "SELECT * FROM read_csv_auto('" path "')")))

  (define (duckdb-write-parquet handle sql path)
    (duckdb-exec handle
      (string-append "COPY (" sql ") TO '" path "' (FORMAT PARQUET)")))

  (define (duckdb-write-csv handle sql path)
    (duckdb-exec handle
      (string-append "COPY (" sql ") TO '" path "' (FORMAT CSV, HEADER)")))

  ) ;; end library
