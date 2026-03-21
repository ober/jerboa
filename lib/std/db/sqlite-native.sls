#!chezscheme
;;; (std db sqlite-native) — SQLite via Rust rusqlite
;;;
;;; Handle-based API: open returns a db handle, prepare returns a stmt handle.
;;; All handles must be explicitly closed/finalized.

(library (std db sqlite-native)
  (export
    sqlite-open sqlite-close sqlite-exec
    sqlite-prepare sqlite-finalize sqlite-reset
    sqlite-bind-int sqlite-bind-double sqlite-bind-text
    sqlite-bind-blob sqlite-bind-null
    sqlite-step sqlite-row? sqlite-done?
    sqlite-column-count sqlite-column-type
    sqlite-column-int sqlite-column-double
    sqlite-column-text sqlite-column-blob
    sqlite-column-name
    sqlite-last-insert-rowid sqlite-changes
    sqlite-errmsg
    ;; Convenience
    sqlite-execute sqlite-query
    ;; Constants
    SQLITE_INTEGER SQLITE_FLOAT SQLITE_TEXT SQLITE_BLOB SQLITE_NULL
    SQLITE_ROW SQLITE_DONE)

  (import (chezscheme))

  (define _native-loaded
    (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "./lib/libjerboa_native.so") #t)
        (error 'std/db/sqlite-native "libjerboa_native.so not found")))

  ;; Constants
  (define SQLITE_INTEGER 1)
  (define SQLITE_FLOAT   2)
  (define SQLITE_TEXT    3)
  (define SQLITE_BLOB    4)
  (define SQLITE_NULL    5)
  (define SQLITE_ROW   100)
  (define SQLITE_DONE  101)

  ;; FFI bindings
  (define c-sqlite-open
    (foreign-procedure "jerboa_sqlite_open" (u8* size_t u8*) int))
  (define c-sqlite-close
    (foreign-procedure "jerboa_sqlite_close" (unsigned-64) int))
  (define c-sqlite-exec
    (foreign-procedure "jerboa_sqlite_exec" (unsigned-64 u8* size_t) int))
  (define c-sqlite-prepare
    (foreign-procedure "jerboa_sqlite_prepare" (unsigned-64 u8* size_t u8*) int))
  (define c-sqlite-finalize
    (foreign-procedure "jerboa_sqlite_finalize" (unsigned-64) int))
  (define c-sqlite-reset
    (foreign-procedure "jerboa_sqlite_reset" (unsigned-64) int))

  (define c-sqlite-bind-int
    (foreign-procedure "jerboa_sqlite_bind_int" (unsigned-64 int integer-64) int))
  (define c-sqlite-bind-double
    (foreign-procedure "jerboa_sqlite_bind_double" (unsigned-64 int double-float) int))
  (define c-sqlite-bind-text
    (foreign-procedure "jerboa_sqlite_bind_text" (unsigned-64 int u8* size_t) int))
  (define c-sqlite-bind-blob
    (foreign-procedure "jerboa_sqlite_bind_blob" (unsigned-64 int u8* size_t) int))
  (define c-sqlite-bind-null
    (foreign-procedure "jerboa_sqlite_bind_null" (unsigned-64 int) int))

  (define c-sqlite-step
    (foreign-procedure "jerboa_sqlite_step" (unsigned-64) int))

  (define c-sqlite-column-count
    (foreign-procedure "jerboa_sqlite_column_count" (unsigned-64) int))
  (define c-sqlite-column-type
    (foreign-procedure "jerboa_sqlite_column_type" (unsigned-64 int) int))
  (define c-sqlite-column-int
    (foreign-procedure "jerboa_sqlite_column_int" (unsigned-64 int) integer-64))
  (define c-sqlite-column-double
    (foreign-procedure "jerboa_sqlite_column_double" (unsigned-64 int) double-float))
  (define c-sqlite-column-text
    (foreign-procedure "jerboa_sqlite_column_text"
      (unsigned-64 int u8* size_t u8*) int))
  (define c-sqlite-column-blob
    (foreign-procedure "jerboa_sqlite_column_blob"
      (unsigned-64 int u8* size_t u8*) int))
  (define c-sqlite-column-name
    (foreign-procedure "jerboa_sqlite_column_name"
      (unsigned-64 int u8* size_t u8*) int))

  (define c-sqlite-last-insert-rowid
    (foreign-procedure "jerboa_sqlite_last_insert_rowid" (unsigned-64) integer-64))
  (define c-sqlite-changes
    (foreign-procedure "jerboa_sqlite_changes" (unsigned-64) int))
  (define c-sqlite-errmsg
    (foreign-procedure "jerboa_sqlite_errmsg" (unsigned-64 u8* size_t u8*) int))

  ;; --- Public API ---

  (define (sqlite-open path)
    (let ([bv (string->utf8 path)]
          [handle-box (make-bytevector 8 0)])
      (let ([rc (c-sqlite-open bv (bytevector-length bv) handle-box)])
        (when (< rc 0)
          (error 'sqlite-open "failed to open database" path))
        (bytevector-u64-native-ref handle-box 0))))

  (define (sqlite-close handle)
    (let ([rc (c-sqlite-close handle)])
      (when (< rc 0)
        (error 'sqlite-close "failed to close database"))
      (void)))

  (define (sqlite-exec handle sql)
    (let ([bv (string->utf8 sql)])
      (let ([rc (c-sqlite-exec handle bv (bytevector-length bv))])
        (when (< rc 0)
          (error 'sqlite-exec "exec failed" sql))
        (void))))

  (define (sqlite-prepare handle sql)
    (let ([bv (string->utf8 sql)]
          [stmt-box (make-bytevector 8 0)])
      (let ([rc (c-sqlite-prepare handle bv (bytevector-length bv) stmt-box)])
        (when (< rc 0)
          (error 'sqlite-prepare "prepare failed" sql))
        (bytevector-u64-native-ref stmt-box 0))))

  (define (sqlite-finalize stmt)
    (c-sqlite-finalize stmt)
    (void))

  (define (sqlite-reset stmt)
    (c-sqlite-reset stmt)
    (void))

  ;; Bind — index is 1-based
  (define (sqlite-bind-int stmt index value)
    (let ([rc (c-sqlite-bind-int stmt index value)])
      (when (< rc 0) (error 'sqlite-bind-int "bind failed" index))
      (void)))

  (define (sqlite-bind-double stmt index value)
    (let ([rc (c-sqlite-bind-double stmt index value)])
      (when (< rc 0) (error 'sqlite-bind-double "bind failed" index))
      (void)))

  (define (sqlite-bind-text stmt index value)
    (let ([bv (string->utf8 value)])
      (let ([rc (c-sqlite-bind-text stmt index bv (bytevector-length bv))])
        (when (< rc 0) (error 'sqlite-bind-text "bind failed" index))
        (void))))

  (define (sqlite-bind-blob stmt index bv)
    (let ([rc (c-sqlite-bind-blob stmt index bv (bytevector-length bv))])
      (when (< rc 0) (error 'sqlite-bind-blob "bind failed" index))
      (void)))

  (define (sqlite-bind-null stmt index)
    (let ([rc (c-sqlite-bind-null stmt index)])
      (when (< rc 0) (error 'sqlite-bind-null "bind failed" index))
      (void)))

  ;; Step — returns SQLITE_ROW (100) or SQLITE_DONE (101)
  (define (sqlite-step stmt)
    (let ([rc (c-sqlite-step stmt)])
      (when (< rc 0) (error 'sqlite-step "step failed"))
      rc))

  (define (sqlite-row? rc) (= rc SQLITE_ROW))
  (define (sqlite-done? rc) (= rc SQLITE_DONE))

  ;; Column access
  (define (sqlite-column-count stmt)
    (c-sqlite-column-count stmt))

  (define (sqlite-column-type stmt col)
    (c-sqlite-column-type stmt col))

  (define (sqlite-column-int stmt col)
    (c-sqlite-column-int stmt col))

  (define (sqlite-column-double stmt col)
    (c-sqlite-column-double stmt col))

  (define (sqlite-column-text stmt col)
    (let ([buf (make-bytevector 4096)]
          [len-box (make-bytevector 8 0)])
      (let ([rc (c-sqlite-column-text stmt col buf 4096 len-box)])
        (when (< rc 0) (error 'sqlite-column-text "read failed" col))
        (let ([len (bytevector-u64-native-ref len-box 0)])
          (if (= len 0) ""
            (utf8->string (bv-sub buf 0 (min len 4096))))))))

  (define (sqlite-column-blob stmt col)
    (let ([buf (make-bytevector 65536)]
          [len-box (make-bytevector 8 0)])
      (let ([rc (c-sqlite-column-blob stmt col buf 65536 len-box)])
        (when (< rc 0) (error 'sqlite-column-blob "read failed" col))
        (let ([len (bytevector-u64-native-ref len-box 0)])
          (bv-sub buf 0 (min len 65536))))))

  (define (sqlite-column-name stmt col)
    (let ([buf (make-bytevector 256)]
          [len-box (make-bytevector 8 0)])
      (let ([rc (c-sqlite-column-name stmt col buf 256 len-box)])
        (when (< rc 0) (error 'sqlite-column-name "read failed" col))
        (let ([len (bytevector-u64-native-ref len-box 0)])
          (utf8->string (bv-sub buf 0 (min len 256)))))))

  (define (sqlite-last-insert-rowid handle)
    (c-sqlite-last-insert-rowid handle))

  (define (sqlite-changes handle)
    (c-sqlite-changes handle))

  (define (sqlite-errmsg handle)
    (let ([buf (make-bytevector 1024)]
          [len-box (make-bytevector 8 0)])
      (let ([rc (c-sqlite-errmsg handle buf 1024 len-box)])
        (if (< rc 0) "unknown error"
          (let ([len (bytevector-u64-native-ref len-box 0)])
            (utf8->string (bv-sub buf 0 (min len 1024))))))))

  ;; --- Convenience ---

  ;; Execute SQL with no results (DDL, INSERT, UPDATE, DELETE)
  (define (sqlite-execute handle sql . params)
    (if (null? params)
      (sqlite-exec handle sql)
      (let ([stmt (sqlite-prepare handle sql)])
        (let loop ([i 1] [rest params])
          (unless (null? rest)
            (let ([v (car rest)])
              (cond
                [(integer? v)   (sqlite-bind-int stmt i v)]
                [(flonum? v)    (sqlite-bind-double stmt i v)]
                [(string? v)    (sqlite-bind-text stmt i v)]
                [(bytevector? v)(sqlite-bind-blob stmt i v)]
                [(not v)        (sqlite-bind-null stmt i)]
                [else (error 'sqlite-execute "unsupported param type" v)]))
            (loop (+ i 1) (cdr rest))))
        (sqlite-step stmt)
        (sqlite-finalize stmt)
        (void))))

  ;; Query returning list of association lists
  (define (sqlite-query handle sql . params)
    (let ([stmt (sqlite-prepare handle sql)])
      (let loop ([i 1] [rest params])
        (unless (null? rest)
          (let ([v (car rest)])
            (cond
              [(integer? v)   (sqlite-bind-int stmt i v)]
              [(flonum? v)    (sqlite-bind-double stmt i v)]
              [(string? v)    (sqlite-bind-text stmt i v)]
              [(bytevector? v)(sqlite-bind-blob stmt i v)]
              [(not v)        (sqlite-bind-null stmt i)]
              [else (error 'sqlite-query "unsupported param type" v)]))
          (loop (+ i 1) (cdr rest))))
      (let ([ncols (sqlite-column-count stmt)])
        (let ([names (let loop ([i 0] [acc '()])
                       (if (>= i ncols) (reverse acc)
                         (loop (+ i 1) (cons (sqlite-column-name stmt i) acc))))])
          (let step-loop ([rows '()])
            (let ([rc (sqlite-step stmt)])
              (if (sqlite-done? rc)
                (begin (sqlite-finalize stmt) (reverse rows))
                (let ([row (let col-loop ([i 0] [acc '()])
                             (if (>= i ncols) (reverse acc)
                               (let ([typ (sqlite-column-type stmt i)])
                                 (col-loop (+ i 1)
                                   (cons
                                     (cons (list-ref names i)
                                       (cond
                                         [(= typ SQLITE_INTEGER) (sqlite-column-int stmt i)]
                                         [(= typ SQLITE_FLOAT)   (sqlite-column-double stmt i)]
                                         [(= typ SQLITE_TEXT)    (sqlite-column-text stmt i)]
                                         [(= typ SQLITE_BLOB)    (sqlite-column-blob stmt i)]
                                         [(= typ SQLITE_NULL)    #f]
                                         [else #f]))
                                     acc)))))])
                  (step-loop (cons row rows))))))))))

  ;; Helper: sub-bytevector (avoids R6RS 3-arg bytevector-copy warning)
  (define (bv-sub bv start len)
    (let ([out (make-bytevector len)])
      (bytevector-copy! bv start out 0 len)
      out))

  ) ;; end library
