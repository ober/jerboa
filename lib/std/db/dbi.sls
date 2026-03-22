#!chezscheme
;;; (std db dbi) — Generic database interface
;;;
;;; Abstract database interface with pluggable drivers.  Drivers register
;;; themselves via dbi-driver-register! and provide vtable procedures for
;;; connection management, query execution, and transaction control.
;;;
;;; A connection wraps a driver-specific handle with a uniform API.
;;; Statements (from dbi-prepare) are also driver-specific handles wrapped
;;; in a dbi-statement record.

(library (std db dbi)
  (export
    ;; Connection
    dbi-connect dbi-close
    ;; Query
    dbi-query dbi-exec
    ;; Prepared statements
    dbi-prepare dbi-bind dbi-step dbi-columns
    ;; Transactions
    dbi-with-transaction
    ;; Connection record
    make-dbi-connection dbi-connection?
    ;; Driver registration
    dbi-driver-register! dbi-drivers)

  (import (chezscheme))

  ;; ========== Driver registry ==========

  ;; Each driver is an alist of (symbol . procedure):
  ;;   connect  : (connection-params ...) -> driver-handle
  ;;   close    : (driver-handle) -> void
  ;;   query    : (driver-handle sql params) -> list of vectors (rows)
  ;;   exec     : (driver-handle sql params) -> integer (affected rows)
  ;;   prepare  : (driver-handle sql) -> stmt-handle
  ;;   bind     : (stmt-handle params) -> void
  ;;   step     : (stmt-handle) -> #f | vector (row)
  ;;   columns  : (stmt-handle) -> list of strings (column names)
  ;;   begin-tx : (driver-handle) -> void
  ;;   commit-tx  : (driver-handle) -> void
  ;;   rollback-tx: (driver-handle) -> void

  (define *drivers* '())  ; alist of (name . vtable-alist)

  (define (dbi-driver-register! name vtable)
    ;; Register a driver. NAME is a symbol, VTABLE is an alist of
    ;; (symbol . procedure) pairs.
    (unless (symbol? name)
      (error 'dbi-driver-register! "driver name must be a symbol" name))
    (let ([required '(connect close query exec)])
      (for-each
       (lambda (key)
         (unless (assq key vtable)
           (error 'dbi-driver-register!
                  (format "driver ~a missing required operation: ~a" name key)
                  name key)))
       required))
    ;; Replace existing or add new
    (set! *drivers*
      (cons (cons name vtable)
            (remp (lambda (entry) (eq? (car entry) name)) *drivers*))))

  (define (dbi-drivers)
    ;; Return list of registered driver names.
    (map car *drivers*))

  (define (lookup-driver name)
    (let ([entry (assq name *drivers*)])
      (unless entry
        (error 'dbi-connect "unknown driver" name))
      (cdr entry)))

  (define (driver-op vtable op-name)
    ;; Look up an operation in a vtable; return #f if not found.
    (let ([entry (assq op-name vtable)])
      (and entry (cdr entry))))

  (define (driver-op! vtable op-name who)
    ;; Look up an operation, error if not found.
    (let ([proc (driver-op vtable op-name)])
      (unless proc
        (error who (format "driver does not support ~a" op-name) op-name))
      proc))

  ;; ========== Connection record ==========

  (define-record-type dbi-connection
    (fields
     driver-name      ; symbol
     vtable           ; alist of driver procedures
     handle           ; driver-specific connection handle
     (mutable open?)) ; #t while the connection is alive
    (protocol
     (lambda (new)
       (lambda (driver-name vtable handle)
         (new driver-name vtable handle #t)))))

  ;; ========== Statement record ==========

  (define-record-type dbi-statement
    (fields
     connection   ; parent dbi-connection
     handle))     ; driver-specific statement handle

  ;; ========== Helpers ==========

  (define (check-open conn who)
    (unless (dbi-connection-open? conn)
      (error who "connection is closed")))

  ;; ========== Public API ==========

  (define (dbi-connect driver-name . connect-args)
    ;; Connect to a database. DRIVER-NAME is a symbol naming a registered
    ;; driver.  Remaining arguments are passed to the driver's connect proc.
    (let* ([vtable (lookup-driver driver-name)]
           [connect-proc (driver-op! vtable 'connect 'dbi-connect)]
           [handle (apply connect-proc connect-args)])
      (make-dbi-connection driver-name vtable handle)))

  (define (dbi-close conn)
    ;; Close a database connection. Safe to call multiple times.
    (when (dbi-connection-open? conn)
      (let ([close-proc (driver-op! (dbi-connection-vtable conn) 'close 'dbi-close)])
        (close-proc (dbi-connection-handle conn))
        (dbi-connection-open?-set! conn #f))))

  (define (dbi-query conn sql . params)
    ;; Execute SQL and return a list of row vectors.
    (check-open conn 'dbi-query)
    (let ([query-proc (driver-op! (dbi-connection-vtable conn) 'query 'dbi-query)])
      (query-proc (dbi-connection-handle conn) sql params)))

  (define (dbi-exec conn sql . params)
    ;; Execute SQL for side effects, return affected row count.
    (check-open conn 'dbi-exec)
    (let ([exec-proc (driver-op! (dbi-connection-vtable conn) 'exec 'dbi-exec)])
      (exec-proc (dbi-connection-handle conn) sql params)))

  (define (dbi-prepare conn sql)
    ;; Prepare a SQL statement, return a dbi-statement.
    (check-open conn 'dbi-prepare)
    (let ([prepare-proc (driver-op! (dbi-connection-vtable conn) 'prepare 'dbi-prepare)])
      (make-dbi-statement conn (prepare-proc (dbi-connection-handle conn) sql))))

  (define (dbi-bind stmt . params)
    ;; Bind parameters to a prepared statement.
    (let* ([conn (dbi-statement-connection stmt)]
           [bind-proc (driver-op! (dbi-connection-vtable conn) 'bind 'dbi-bind)])
      (check-open conn 'dbi-bind)
      (bind-proc (dbi-statement-handle stmt) params)))

  (define (dbi-step stmt)
    ;; Step a prepared statement.  Returns a row vector or #f when done.
    (let* ([conn (dbi-statement-connection stmt)]
           [step-proc (driver-op! (dbi-connection-vtable conn) 'step 'dbi-step)])
      (check-open conn 'dbi-step)
      (step-proc (dbi-statement-handle stmt))))

  (define (dbi-columns stmt)
    ;; Return list of column name strings for a prepared statement.
    (let* ([conn (dbi-statement-connection stmt)]
           [columns-proc (driver-op! (dbi-connection-vtable conn) 'columns 'dbi-columns)])
      (check-open conn 'dbi-columns)
      (columns-proc (dbi-statement-handle stmt))))

  (define (dbi-with-transaction conn thunk)
    ;; Run THUNK inside a transaction.  Commits on normal return,
    ;; rolls back on exception, then re-raises.
    (check-open conn 'dbi-with-transaction)
    (let* ([vtable (dbi-connection-vtable conn)]
           [handle (dbi-connection-handle conn)]
           [begin-proc (driver-op! vtable 'begin-tx 'dbi-with-transaction)]
           [commit-proc (driver-op! vtable 'commit-tx 'dbi-with-transaction)]
           [rollback-proc (driver-op! vtable 'rollback-tx 'dbi-with-transaction)])
      (begin-proc handle)
      (guard (exn
              [#t
               ;; Attempt rollback, then re-raise
               (guard (rb-exn [#t (void)])
                 (rollback-proc handle))
               (raise exn)])
        (let ([result (thunk)])
          (commit-proc handle)
          result))))

  ) ;; end library
