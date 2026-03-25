#!chezscheme
;;; (std db duckdb-native) — DuckDB via Rust duckdb crate
;;;
;;; Result-set based API: prepare → bind → execute → access results.
;;; All handles must be explicitly freed/finalized.

(library (std db duckdb-native)
  (export
    duckdb-open duckdb-close duckdb-exec
    duckdb-prepare duckdb-finalize duckdb-reset
    duckdb-bind-int duckdb-bind-double duckdb-bind-text
    duckdb-bind-blob duckdb-bind-null duckdb-bind-bool
    duckdb-execute duckdb-free-result
    duckdb-nrows duckdb-ncols
    duckdb-column-name duckdb-column-type
    duckdb-value-int duckdb-value-double duckdb-value-text
    duckdb-value-blob duckdb-value-bool duckdb-value-is-null?
    duckdb-version
    ;; Convenience
    duckdb-eval duckdb-query
    ;; Constants
    DUCKDB_INTEGER DUCKDB_FLOAT DUCKDB_TEXT DUCKDB_BLOB
    DUCKDB_NULL DUCKDB_BOOLEAN)

  (import (chezscheme))

  (define _native-loaded
    (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "./lib/libjerboa_native.so") #t)
        (error 'std/db/duckdb-native "libjerboa_native.so not found")))

  ;; Type constants (match Rust side)
  (define DUCKDB_INTEGER 1)
  (define DUCKDB_FLOAT   2)
  (define DUCKDB_TEXT    3)
  (define DUCKDB_BLOB    4)
  (define DUCKDB_NULL    5)
  (define DUCKDB_BOOLEAN 6)

  ;; --- FFI bindings ---

  (define c-duckdb-open
    (foreign-procedure "jerboa_duckdb_open" (u8* size_t u8*) int))
  (define c-duckdb-close
    (foreign-procedure "jerboa_duckdb_close" (unsigned-64) int))
  (define c-duckdb-exec
    (foreign-procedure "jerboa_duckdb_exec" (unsigned-64 u8* size_t) int))
  (define c-duckdb-prepare
    (foreign-procedure "jerboa_duckdb_prepare" (unsigned-64 u8* size_t u8*) int))
  (define c-duckdb-finalize
    (foreign-procedure "jerboa_duckdb_finalize" (unsigned-64) int))
  (define c-duckdb-reset
    (foreign-procedure "jerboa_duckdb_reset" (unsigned-64) int))

  (define c-duckdb-bind-int
    (foreign-procedure "jerboa_duckdb_bind_int" (unsigned-64 int integer-64) int))
  (define c-duckdb-bind-double
    (foreign-procedure "jerboa_duckdb_bind_double" (unsigned-64 int double-float) int))
  (define c-duckdb-bind-text
    (foreign-procedure "jerboa_duckdb_bind_text" (unsigned-64 int u8* size_t) int))
  (define c-duckdb-bind-blob
    (foreign-procedure "jerboa_duckdb_bind_blob" (unsigned-64 int u8* size_t) int))
  (define c-duckdb-bind-null
    (foreign-procedure "jerboa_duckdb_bind_null" (unsigned-64 int) int))
  (define c-duckdb-bind-bool
    (foreign-procedure "jerboa_duckdb_bind_bool" (unsigned-64 int int) int))

  (define c-duckdb-execute
    (foreign-procedure "jerboa_duckdb_execute" (unsigned-64 u8*) int))

  (define c-duckdb-nrows
    (foreign-procedure "jerboa_duckdb_nrows" (unsigned-64) integer-64))
  (define c-duckdb-ncols
    (foreign-procedure "jerboa_duckdb_ncols" (unsigned-64) integer-64))
  (define c-duckdb-column-name
    (foreign-procedure "jerboa_duckdb_column_name"
      (unsigned-64 int u8* size_t u8*) int))
  (define c-duckdb-column-type
    (foreign-procedure "jerboa_duckdb_column_type" (unsigned-64 int) int))
  (define c-duckdb-value-is-null
    (foreign-procedure "jerboa_duckdb_value_is_null" (unsigned-64 int integer-64) int))
  (define c-duckdb-value-int
    (foreign-procedure "jerboa_duckdb_value_int" (unsigned-64 int integer-64) integer-64))
  (define c-duckdb-value-double
    (foreign-procedure "jerboa_duckdb_value_double" (unsigned-64 int integer-64) double-float))
  (define c-duckdb-value-bool
    (foreign-procedure "jerboa_duckdb_value_bool" (unsigned-64 int integer-64) int))
  (define c-duckdb-value-text
    (foreign-procedure "jerboa_duckdb_value_text"
      (unsigned-64 int integer-64 u8* size_t u8*) int))
  (define c-duckdb-value-blob
    (foreign-procedure "jerboa_duckdb_value_blob"
      (unsigned-64 int integer-64 u8* size_t u8*) int))

  (define c-duckdb-free-result
    (foreign-procedure "jerboa_duckdb_free_result" (unsigned-64) int))
  (define c-duckdb-version
    (foreign-procedure "jerboa_duckdb_version" (u8* size_t u8*) int))

  ;; --- Public API ---

  (define (duckdb-open path)
    (let ([bv (string->utf8 path)]
          [handle-box (make-bytevector 8 0)])
      (let ([rc (c-duckdb-open bv (bytevector-length bv) handle-box)])
        (when (< rc 0)
          (error 'duckdb-open "failed to open database" path))
        (bytevector-u64-native-ref handle-box 0))))

  (define (duckdb-close handle)
    (let ([rc (c-duckdb-close handle)])
      (when (< rc 0)
        (error 'duckdb-close "failed to close database"))
      (void)))

  (define (duckdb-exec handle sql)
    (let ([bv (string->utf8 sql)])
      (let ([rc (c-duckdb-exec handle bv (bytevector-length bv))])
        (when (< rc 0)
          (error 'duckdb-exec "exec failed" sql))
        (void))))

  (define (duckdb-prepare handle sql)
    (let ([bv (string->utf8 sql)]
          [stmt-box (make-bytevector 8 0)])
      (let ([rc (c-duckdb-prepare handle bv (bytevector-length bv) stmt-box)])
        (when (< rc 0)
          (error 'duckdb-prepare "prepare failed" sql))
        (bytevector-u64-native-ref stmt-box 0))))

  (define (duckdb-finalize stmt)
    (c-duckdb-finalize stmt)
    (void))

  (define (duckdb-reset stmt)
    (c-duckdb-reset stmt)
    (void))

  ;; Bind — index is 1-based
  (define (duckdb-bind-int stmt index value)
    (let ([rc (c-duckdb-bind-int stmt index value)])
      (when (< rc 0) (error 'duckdb-bind-int "bind failed" index))
      (void)))

  (define (duckdb-bind-double stmt index value)
    (let ([rc (c-duckdb-bind-double stmt index value)])
      (when (< rc 0) (error 'duckdb-bind-double "bind failed" index))
      (void)))

  (define (duckdb-bind-text stmt index value)
    (let ([bv (string->utf8 value)])
      (let ([rc (c-duckdb-bind-text stmt index bv (bytevector-length bv))])
        (when (< rc 0) (error 'duckdb-bind-text "bind failed" index))
        (void))))

  (define (duckdb-bind-blob stmt index bv)
    (let ([rc (c-duckdb-bind-blob stmt index bv (bytevector-length bv))])
      (when (< rc 0) (error 'duckdb-bind-blob "bind failed" index))
      (void)))

  (define (duckdb-bind-null stmt index)
    (let ([rc (c-duckdb-bind-null stmt index)])
      (when (< rc 0) (error 'duckdb-bind-null "bind failed" index))
      (void)))

  (define (duckdb-bind-bool stmt index value)
    (let ([rc (c-duckdb-bind-bool stmt index (if value 1 0))])
      (when (< rc 0) (error 'duckdb-bind-bool "bind failed" index))
      (void)))

  ;; Execute → result handle
  (define (duckdb-execute stmt)
    (let ([result-box (make-bytevector 8 0)])
      (let ([rc (c-duckdb-execute stmt result-box)])
        (when (< rc 0)
          (error 'duckdb-execute "execute failed"))
        (bytevector-u64-native-ref result-box 0))))

  (define (duckdb-free-result handle)
    (c-duckdb-free-result handle)
    (void))

  ;; Result set access
  (define (duckdb-nrows result) (c-duckdb-nrows result))
  (define (duckdb-ncols result) (c-duckdb-ncols result))

  (define (duckdb-column-name result col)
    (let ([buf (make-bytevector 256)]
          [len-box (make-bytevector 8 0)])
      (let ([rc (c-duckdb-column-name result col buf 256 len-box)])
        (when (< rc 0) (error 'duckdb-column-name "read failed" col))
        (let ([len (bytevector-u64-native-ref len-box 0)])
          (utf8->string (bv-sub buf 0 (min len 256)))))))

  (define (duckdb-column-type result col)
    (c-duckdb-column-type result col))

  (define (duckdb-value-is-null? result col row)
    (= 1 (c-duckdb-value-is-null result col row)))

  (define (duckdb-value-int result col row)
    (c-duckdb-value-int result col row))

  (define (duckdb-value-double result col row)
    (c-duckdb-value-double result col row))

  (define (duckdb-value-bool result col row)
    (not (zero? (c-duckdb-value-bool result col row))))

  (define (duckdb-value-text result col row)
    (let ([buf (make-bytevector 4096)]
          [len-box (make-bytevector 8 0)])
      (let ([rc (c-duckdb-value-text result col row buf 4096 len-box)])
        (when (< rc 0) (error 'duckdb-value-text "read failed" col row))
        (let ([len (bytevector-u64-native-ref len-box 0)])
          (if (= len 0) ""
            (utf8->string (bv-sub buf 0 (min len 4096))))))))

  (define (duckdb-value-blob result col row)
    (let ([buf (make-bytevector 65536)]
          [len-box (make-bytevector 8 0)])
      (let ([rc (c-duckdb-value-blob result col row buf 65536 len-box)])
        (when (< rc 0) (error 'duckdb-value-blob "read failed" col row))
        (let ([len (bytevector-u64-native-ref len-box 0)])
          (bv-sub buf 0 (min len 65536))))))

  (define (duckdb-version)
    (let ([buf (make-bytevector 64)]
          [len-box (make-bytevector 8 0)])
      (let ([rc (c-duckdb-version buf 64 len-box)])
        (if (< rc 0) "unknown"
          (let ([len (bytevector-u64-native-ref len-box 0)])
            (utf8->string (bv-sub buf 0 (min len 64))))))))

  ;; --- Convenience ---

  ;; Bind params by type and execute (no results needed)
  (define (duckdb-eval handle sql . params)
    (let ([stmt (duckdb-prepare handle sql)])
      (bind-params! stmt params)
      (let ([result (duckdb-execute stmt)])
        (duckdb-free-result result)
        (duckdb-finalize stmt)
        (void))))

  ;; Query returning list of association lists
  (define (duckdb-query handle sql . params)
    (let ([stmt (duckdb-prepare handle sql)])
      (bind-params! stmt params)
      (let ([result (duckdb-execute stmt)])
        (let ([nrows (duckdb-nrows result)]
              [ncols (duckdb-ncols result)])
          ;; Get column names
          (let ([names (let loop ([i 0] [acc '()])
                         (if (>= i ncols) (reverse acc)
                           (loop (+ i 1)
                                 (cons (duckdb-column-name result i) acc))))])
            ;; Collect rows as alists
            (let row-loop ([r 0] [rows '()])
              (if (>= r nrows)
                (begin
                  (duckdb-free-result result)
                  (duckdb-finalize stmt)
                  (reverse rows))
                (let col-loop ([c 0] [acc '()])
                  (if (>= c ncols)
                    (row-loop (+ r 1) (cons (reverse acc) rows))
                    (col-loop (+ c 1)
                      (cons
                        (cons (list-ref names c)
                              (if (duckdb-value-is-null? result c r)
                                #f
                                (let ([typ (duckdb-column-type result c)])
                                  (cond
                                    [(= typ DUCKDB_INTEGER) (duckdb-value-int result c r)]
                                    [(= typ DUCKDB_FLOAT)   (duckdb-value-double result c r)]
                                    [(= typ DUCKDB_TEXT)    (duckdb-value-text result c r)]
                                    [(= typ DUCKDB_BLOB)    (duckdb-value-blob result c r)]
                                    [(= typ DUCKDB_BOOLEAN) (duckdb-value-bool result c r)]
                                    [(= typ DUCKDB_NULL)    #f]
                                    [else (duckdb-value-text result c r)]))))
                        acc)))))))))))

  ;; --- Internal helpers ---

  (define (bind-params! stmt params)
    (let loop ([i 1] [rest params])
      (unless (null? rest)
        (let ([v (car rest)])
          (cond
            [(not v)         (duckdb-bind-null stmt i)]
            [(eq? v #t)      (duckdb-bind-bool stmt i #t)]
            [(flonum? v)     (duckdb-bind-double stmt i v)]
            [(integer? v)    (duckdb-bind-int stmt i v)]
            [(string? v)     (duckdb-bind-text stmt i v)]
            [(bytevector? v) (duckdb-bind-blob stmt i v)]
            [else (error 'duckdb "unsupported param type" v)]))
        (loop (+ i 1) (cdr rest)))))

  ;; Helper: sub-bytevector
  (define (bv-sub bv start len)
    (let ([out (make-bytevector len)])
      (bytevector-copy! bv start out 0 len)
      out))

  ) ;; end library
