#!chezscheme
;;; :std/db/sqlite -- SQLite3 database (wraps chez-sqlite)
;;; Requires: chez_sqlite_shim.so, libsqlite3.so

(library (std db sqlite)
  (export
    ;; Core
    sqlite-open sqlite-close
    sqlite-exec sqlite-eval sqlite-query
    ;; Prepared statements
    sqlite-prepare sqlite-finalize
    sqlite-step sqlite-reset sqlite-clear-bindings
    ;; Binding
    sqlite-bind! sqlite-bind-null!
    ;; Column access
    sqlite-column-count sqlite-column-name sqlite-column-type
    sqlite-column-value sqlite-columns
    ;; Metadata
    sqlite-last-insert-rowid sqlite-changes sqlite-errmsg
    ;; Constants
    SQLITE_ROW SQLITE_DONE SQLITE_OK
    SQLITE_INTEGER SQLITE_FLOAT SQLITE_TEXT SQLITE_BLOB SQLITE_NULL)

  (import (chez-sqlite))

  ) ;; end library
