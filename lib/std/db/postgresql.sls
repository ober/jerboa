#!chezscheme
;;; :std/db/postgresql -- PostgreSQL database (wraps chez-postgresql)
;;; Requires: chez_pg_shim.so, libpq.so.5

(library (std db postgresql)
  (export
    ;; Core
    pg-connect pg-finish pg-status pg-error-message
    pg-exec pg-exec* pg-query pg-eval
    ;; Result access
    pg-result-status pg-result-error pg-clear
    pg-ntuples pg-nfields pg-fname pg-columns
    pg-getvalue pg-getlength pg-getisnull
    pg-cmd-tuples pg-ftype
    ;; Utilities
    pg-escape-literal pg-escape-identifier
    pg-server-version pg-socket
    ;; Constants
    CONNECTION_OK CONNECTION_BAD
    PGRES_EMPTY_QUERY PGRES_COMMAND_OK PGRES_TUPLES_OK PGRES_FATAL_ERROR)

  (import (chez-postgresql))

  ) ;; end library
