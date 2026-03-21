#!chezscheme
;;; (std db postgresql-native) — PostgreSQL via Rust rust-postgres
;;;
;;; Handle-based API: connect returns a connection handle,
;;; query returns a result handle.

(library (std db postgresql-native)
  (export
    pg-connect pg-disconnect
    pg-exec pg-query
    pg-nrows pg-ncols
    pg-get-value pg-is-null? pg-column-name
    pg-free-result)

  (import (chezscheme))

  (define _native-loaded
    (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "./lib/libjerboa_native.so") #t)
        (error 'std/db/postgresql-native "libjerboa_native.so not found")))

  ;; FFI bindings
  (define c-pg-connect
    (foreign-procedure "jerboa_pg_connect" (u8* size_t u8*) int))
  (define c-pg-disconnect
    (foreign-procedure "jerboa_pg_disconnect" (unsigned-64) int))
  (define c-pg-exec
    (foreign-procedure "jerboa_pg_exec" (unsigned-64 u8* size_t) int))
  (define c-pg-query
    (foreign-procedure "jerboa_pg_query" (unsigned-64 u8* size_t u8*) int))
  (define c-pg-nrows
    (foreign-procedure "jerboa_pg_nrows" (unsigned-64) int))
  (define c-pg-ncols
    (foreign-procedure "jerboa_pg_ncols" (unsigned-64) int))
  (define c-pg-get-value
    (foreign-procedure "jerboa_pg_get_value"
      (unsigned-64 int int u8* size_t u8*) int))
  (define c-pg-is-null
    (foreign-procedure "jerboa_pg_is_null" (unsigned-64 int int) int))
  (define c-pg-column-name
    (foreign-procedure "jerboa_pg_column_name"
      (unsigned-64 int u8* size_t u8*) int))
  (define c-pg-free-result
    (foreign-procedure "jerboa_pg_free_result" (unsigned-64) int))

  ;; --- Public API ---

  (define (pg-connect connstr)
    (let ([bv (string->utf8 connstr)]
          [handle-box (make-bytevector 8 0)])
      (let ([rc (c-pg-connect bv (bytevector-length bv) handle-box)])
        (when (< rc 0)
          (error 'pg-connect "connection failed" connstr))
        (bytevector-u64-native-ref handle-box 0))))

  (define (pg-disconnect handle)
    (c-pg-disconnect handle)
    (void))

  (define (pg-exec handle sql)
    (let ([bv (string->utf8 sql)])
      (let ([rc (c-pg-exec handle bv (bytevector-length bv))])
        (when (< rc 0)
          (error 'pg-exec "exec failed" sql))
        (void))))

  (define (pg-query handle sql)
    (let ([bv (string->utf8 sql)]
          [result-box (make-bytevector 8 0)])
      (let ([rc (c-pg-query handle bv (bytevector-length bv) result-box)])
        (when (< rc 0)
          (error 'pg-query "query failed" sql))
        (bytevector-u64-native-ref result-box 0))))

  (define (pg-nrows result)
    (c-pg-nrows result))

  (define (pg-ncols result)
    (c-pg-ncols result))

  (define (pg-get-value result row col)
    (let ([buf (make-bytevector 4096)]
          [len-box (make-bytevector 8 0)])
      (let ([rc (c-pg-get-value result row col buf 4096 len-box)])
        (cond
          [(= rc 1) #f]  ;; NULL
          [(< rc 0) (error 'pg-get-value "read failed" row col)]
          [else
            (let ([len (bytevector-u64-native-ref len-box 0)])
              (utf8->string (bv-sub buf 0 (min len 4096))))]))))

  (define (pg-is-null? result row col)
    (= 1 (c-pg-is-null result row col)))

  (define (pg-column-name result col)
    (let ([buf (make-bytevector 256)]
          [len-box (make-bytevector 8 0)])
      (let ([rc (c-pg-column-name result col buf 256 len-box)])
        (when (< rc 0) (error 'pg-column-name "read failed" col))
        (let ([len (bytevector-u64-native-ref len-box 0)])
          (utf8->string (bv-sub buf 0 (min len 256)))))))

  (define (pg-free-result result)
    (c-pg-free-result result)
    (void))

  ;; Helper
  (define (bv-sub bv start len)
    (let ([out (make-bytevector len)])
      (bytevector-copy! bv start out 0 len)
      out))

  ) ;; end library
