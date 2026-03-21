#!/usr/bin/env scheme-script
#!chezscheme
;;; Tests for Weeks 5-6 Rust native modules:
;;; SQLite, epoll, inotify, landlock
;;; (PostgreSQL requires a live server, tested separately)

(import (chezscheme)
        (std db sqlite-native)
        (std os epoll-native)
        (std os inotify-native)
        (std os landlock-native))

(define test-count 0)
(define pass-count 0)
(define fail-count 0)

(define (test name thunk)
  (set! test-count (+ test-count 1))
  (guard (e [#t
             (set! fail-count (+ fail-count 1))
             (display (string-append "FAIL: " name "\n"))
             (display (string-append "  Error: "
               (if (message-condition? e)
                 (condition-message e)
                 "unknown error")
               "\n"))])
    (thunk)
    (set! pass-count (+ pass-count 1))
    (display (string-append "PASS: " name "\n"))))

(define (assert-true msg val)
  (unless val (error 'assert-true msg)))

(define (assert-false msg val)
  (when val (error 'assert-false msg)))

(define (assert-equal msg expected actual)
  (unless (equal? expected actual)
    (error 'assert-equal msg expected actual)))

;;; ===== Helpers =====

;; Load libc for pipe/close
(load-shared-object "libc.so.6")

(define c-pipe (foreign-procedure "pipe" (u8*) int))
(define c-close (foreign-procedure "close" (int) int))
(define c-write (foreign-procedure "write" (int u8* size_t) ssize_t))
(define c-mkdir (foreign-procedure "mkdir" (string int) int))
(define c-rmdir (foreign-procedure "rmdir" (string) int))

(define (open-fd-pair)
  (let ([fds (make-bytevector 8 0)])
    (when (< (c-pipe fds) 0)
      (error 'open-fd-pair "pipe() failed"))
    (values (bytevector-s32-native-ref fds 0)
            (bytevector-s32-native-ref fds 4))))

(define (close-fd fd) (c-close fd))

(define (random-id)
  (let ([bv (make-bytevector 4)])
    (let ([p (open-file-input-port "/dev/urandom"
               (file-options) (buffer-mode block) #f)])
      (get-bytevector-n! p bv 0 4)
      (close-port p))
    (modulo (bytevector-u32-native-ref bv 0) 999999)))

;;; ===== SQLite Tests =====

(test "sqlite: open in-memory database"
  (lambda ()
    (let ([db (sqlite-open ":memory:")])
      (assert-true "handle > 0" (> db 0))
      (sqlite-close db))))

(test "sqlite: create table and insert"
  (lambda ()
    (let ([db (sqlite-open ":memory:")])
      (sqlite-exec db "CREATE TABLE t1 (id INTEGER PRIMARY KEY, name TEXT, val REAL)")
      (sqlite-exec db "INSERT INTO t1 VALUES (1, 'hello', 3.14)")
      (sqlite-exec db "INSERT INTO t1 VALUES (2, 'world', 2.72)")
      (assert-equal "changes" 1 (sqlite-changes db))
      (sqlite-close db))))

(test "sqlite: prepared statement with bind"
  (lambda ()
    (let ([db (sqlite-open ":memory:")])
      (sqlite-exec db "CREATE TABLE t2 (a INTEGER, b TEXT)")
      (let ([stmt (sqlite-prepare db "INSERT INTO t2 VALUES (?, ?)")])
        (sqlite-bind-int stmt 1 42)
        (sqlite-bind-text stmt 2 "test")
        (sqlite-step stmt)
        (sqlite-finalize stmt))
      (assert-equal "changes" 1 (sqlite-changes db))
      (sqlite-close db))))

(test "sqlite: query with step/column"
  (lambda ()
    (let ([db (sqlite-open ":memory:")])
      (sqlite-exec db "CREATE TABLE t3 (id INTEGER, name TEXT, val REAL)")
      (sqlite-exec db "INSERT INTO t3 VALUES (1, 'alice', 1.5)")
      (sqlite-exec db "INSERT INTO t3 VALUES (2, 'bob', 2.5)")
      (let ([stmt (sqlite-prepare db "SELECT id, name, val FROM t3 ORDER BY id")])
        (assert-equal "column count" 3 (sqlite-column-count stmt))
        ;; First row
        (let ([rc (sqlite-step stmt)])
          (assert-true "row 1" (sqlite-row? rc))
          (assert-equal "id=1" 1 (sqlite-column-int stmt 0))
          (assert-equal "name=alice" "alice" (sqlite-column-text stmt 1))
          (assert-true "val~1.5" (< (abs (- 1.5 (sqlite-column-double stmt 2))) 0.001)))
        ;; Second row
        (let ([rc (sqlite-step stmt)])
          (assert-true "row 2" (sqlite-row? rc))
          (assert-equal "id=2" 2 (sqlite-column-int stmt 0))
          (assert-equal "name=bob" "bob" (sqlite-column-text stmt 1)))
        ;; Done
        (let ([rc (sqlite-step stmt)])
          (assert-true "done" (sqlite-done? rc)))
        (sqlite-finalize stmt))
      (sqlite-close db))))

(test "sqlite: column names"
  (lambda ()
    (let ([db (sqlite-open ":memory:")])
      (sqlite-exec db "CREATE TABLE t4 (foo INTEGER, bar TEXT)")
      (let ([stmt (sqlite-prepare db "SELECT foo, bar FROM t4")])
        (assert-equal "col 0" "foo" (sqlite-column-name stmt 0))
        (assert-equal "col 1" "bar" (sqlite-column-name stmt 1))
        (sqlite-finalize stmt))
      (sqlite-close db))))

(test "sqlite: column types"
  (lambda ()
    (let ([db (sqlite-open ":memory:")])
      (sqlite-exec db "CREATE TABLE t5 (a INTEGER, b REAL, c TEXT, d BLOB)")
      (sqlite-exec db "INSERT INTO t5 VALUES (1, 2.0, 'x', X'BEEF')")
      (let ([stmt (sqlite-prepare db "SELECT a, b, c, d FROM t5")])
        (sqlite-step stmt)
        (assert-equal "int type" SQLITE_INTEGER (sqlite-column-type stmt 0))
        (assert-equal "float type" SQLITE_FLOAT (sqlite-column-type stmt 1))
        (assert-equal "text type" SQLITE_TEXT (sqlite-column-type stmt 2))
        (assert-equal "blob type" SQLITE_BLOB (sqlite-column-type stmt 3))
        (sqlite-finalize stmt))
      (sqlite-close db))))

(test "sqlite: NULL handling"
  (lambda ()
    (let ([db (sqlite-open ":memory:")])
      (sqlite-exec db "CREATE TABLE t6 (a INTEGER, b TEXT)")
      (let ([stmt (sqlite-prepare db "INSERT INTO t6 VALUES (?, ?)")])
        (sqlite-bind-null stmt 1)
        (sqlite-bind-null stmt 2)
        (sqlite-step stmt)
        (sqlite-finalize stmt))
      (let ([stmt (sqlite-prepare db "SELECT a, b FROM t6")])
        (sqlite-step stmt)
        (assert-equal "null type" SQLITE_NULL (sqlite-column-type stmt 0))
        (assert-equal "null type 2" SQLITE_NULL (sqlite-column-type stmt 1))
        (sqlite-finalize stmt))
      (sqlite-close db))))

(test "sqlite: blob read/write"
  (lambda ()
    (let ([db (sqlite-open ":memory:")])
      (sqlite-exec db "CREATE TABLE t7 (data BLOB)")
      (let ([blob (make-bytevector 256)])
        (let loop ([i 0])
          (when (< i 256)
            (bytevector-u8-set! blob i (modulo i 256))
            (loop (+ i 1))))
        (let ([stmt (sqlite-prepare db "INSERT INTO t7 VALUES (?)")])
          (sqlite-bind-blob stmt 1 blob)
          (sqlite-step stmt)
          (sqlite-finalize stmt)))
      (let ([stmt (sqlite-prepare db "SELECT data FROM t7")])
        (sqlite-step stmt)
        (let ([result (sqlite-column-blob stmt 0)])
          (assert-equal "blob length" 256 (bytevector-length result))
          (assert-equal "blob[0]" 0 (bytevector-u8-ref result 0))
          (assert-equal "blob[255]" 255 (bytevector-u8-ref result 255)))
        (sqlite-finalize stmt))
      (sqlite-close db))))

(test "sqlite: last-insert-rowid"
  (lambda ()
    (let ([db (sqlite-open ":memory:")])
      (sqlite-exec db "CREATE TABLE t8 (id INTEGER PRIMARY KEY, x TEXT)")
      (sqlite-exec db "INSERT INTO t8 (x) VALUES ('a')")
      (assert-equal "rowid 1" 1 (sqlite-last-insert-rowid db))
      (sqlite-exec db "INSERT INTO t8 (x) VALUES ('b')")
      (assert-equal "rowid 2" 2 (sqlite-last-insert-rowid db))
      (sqlite-close db))))

(test "sqlite: reset and re-execute"
  (lambda ()
    (let ([db (sqlite-open ":memory:")])
      (sqlite-exec db "CREATE TABLE t9 (v INTEGER)")
      (let ([stmt (sqlite-prepare db "INSERT INTO t9 VALUES (?)")])
        (sqlite-bind-int stmt 1 10)
        (sqlite-step stmt)
        (sqlite-reset stmt)
        (sqlite-bind-int stmt 1 20)
        (sqlite-step stmt)
        (sqlite-finalize stmt))
      ;; Verify both rows
      (let ([rows (sqlite-query db "SELECT v FROM t9 ORDER BY v")])
        (assert-equal "2 rows" 2 (length rows))
        ;; rows is list of alists: ((("v" . 10)) (("v" . 20)))
        (assert-equal "first row" 10 (cdr (caar rows)))
        (assert-equal "second row" 20 (cdr (caar (cdr rows)))))
      (sqlite-close db))))

(test "sqlite: convenience query"
  (lambda ()
    (let ([db (sqlite-open ":memory:")])
      (sqlite-exec db "CREATE TABLE t10 (id INTEGER, name TEXT)")
      (sqlite-execute db "INSERT INTO t10 VALUES (?, ?)" 1 "alice")
      (sqlite-execute db "INSERT INTO t10 VALUES (?, ?)" 2 "bob")
      (let ([rows (sqlite-query db "SELECT id, name FROM t10 ORDER BY id")])
        (assert-equal "2 rows" 2 (length rows))
        (let ([r1 (car rows)])
          (assert-equal "id" 1 (cdr (assoc "id" r1)))
          (assert-equal "name" "alice" (cdr (assoc "name" r1)))))
      (sqlite-close db))))

(test "sqlite: error on invalid SQL"
  (lambda ()
    (let ([db (sqlite-open ":memory:")])
      (let ([got-error #f])
        (guard (e [#t (set! got-error #t)])
          (sqlite-exec db "NOT VALID SQL"))
        (assert-true "got error" got-error))
      (sqlite-close db))))

(test "sqlite: multiple databases"
  (lambda ()
    (let ([db1 (sqlite-open ":memory:")]
          [db2 (sqlite-open ":memory:")])
      (sqlite-exec db1 "CREATE TABLE a (x INTEGER)")
      (sqlite-exec db2 "CREATE TABLE b (y TEXT)")
      (sqlite-exec db1 "INSERT INTO a VALUES (1)")
      (sqlite-exec db2 "INSERT INTO b VALUES ('hello')")
      (let ([r1 (sqlite-query db1 "SELECT x FROM a")]
            [r2 (sqlite-query db2 "SELECT y FROM b")])
        (assert-equal "db1 row" 1 (cdr (assoc "x" (car r1))))
        (assert-equal "db2 row" "hello" (cdr (assoc "y" (car r2)))))
      (sqlite-close db1)
      (sqlite-close db2))))

;;; ===== epoll Tests =====

(test "epoll: create and close"
  (lambda ()
    (let ([epfd (epoll-create)])
      (assert-true "valid fd" (> epfd 0))
      (epoll-close epfd))))

(test "epoll: add pipe fd and wait"
  (lambda ()
    (let-values ([(in out) (open-fd-pair)])
      (let ([epfd (epoll-create)])
        (epoll-add! epfd in EPOLLIN)
        ;; Write to pipe so epoll detects readability
        (let ([bv (string->utf8 "hello")])
          (c-write out bv (bytevector-length bv)))
        ;; Wait with short timeout
        (let ([events (epoll-wait epfd 10 100)])
          (assert-true "got events" (> (length events) 0))
          (let ([ev (car events)])
            (assert-equal "correct fd" in (car ev))
            (assert-true "EPOLLIN set" (> (bitwise-and (cdr ev) EPOLLIN) 0))))
        (epoll-close epfd)
        (close-fd in)
        (close-fd out)))))

(test "epoll: timeout with no events"
  (lambda ()
    (let-values ([(in out) (open-fd-pair)])
      (let ([epfd (epoll-create)])
        (epoll-add! epfd in EPOLLIN)
        ;; Don't write anything - should timeout
        (let ([events (epoll-wait epfd 10 1)])
          (assert-equal "no events" 0 (length events)))
        (epoll-close epfd)
        (close-fd in)
        (close-fd out)))))

(test "epoll: constants defined"
  (lambda ()
    (assert-equal "EPOLLIN" #x001 EPOLLIN)
    (assert-equal "EPOLLOUT" #x004 EPOLLOUT)
    (assert-equal "EPOLLERR" #x008 EPOLLERR)
    (assert-equal "EPOLLHUP" #x010 EPOLLHUP)))

;;; ===== inotify Tests =====

(test "inotify: init and close"
  (lambda ()
    (let ([fd (inotify-init)])
      (assert-true "valid fd" (> fd 0))
      (inotify-close fd))))

(test "inotify: watch a directory"
  (lambda ()
    (let ([fd (inotify-init)]
          [dir (or (getenv "TMPDIR") "/tmp")])
      (let ([wd (inotify-add-watch fd dir IN_CREATE)])
        (assert-true "valid wd" (>= wd 0))
        (inotify-rm-watch fd wd))
      (inotify-close fd))))

(test "inotify: detect file creation"
  (lambda ()
    (let ([dir (string-append (or (getenv "TMPDIR") "/tmp")
                              "/jerboa-inotify-test-"
                              (number->string (random-id)))])
      (c-mkdir dir #o755)
      (let ([fd (inotify-init)])
        (let ([wd (inotify-add-watch fd dir IN_CREATE)])
          (let ([testfile (string-append dir "/testfile")])
            (call-with-output-file testfile
              (lambda (p) (display "test" p)))
            ;; Read events
            (let ([events (inotify-read-events fd)])
              (assert-true "got events" (> (length events) 0))
              (let ([ev (car events)])
                (assert-true "is inotify-event" (inotify-event? ev))
                (assert-equal "correct wd" wd (inotify-event-wd ev))
                (assert-true "CREATE mask"
                  (> (bitwise-and (inotify-event-mask ev) IN_CREATE) 0))
                (assert-equal "filename" "testfile" (inotify-event-name ev))))
            (delete-file testfile))
          (inotify-rm-watch fd wd))
        (inotify-close fd))
      (c-rmdir dir))))

(test "inotify: no events returns empty list"
  (lambda ()
    (let ([fd (inotify-init)]
          [dir (or (getenv "TMPDIR") "/tmp")])
      (let ([wd (inotify-add-watch fd dir IN_DELETE)])
        (let ([events (inotify-read-events fd)])
          (assert-equal "no events" '() events))
        (inotify-rm-watch fd wd))
      (inotify-close fd))))

(test "inotify: constants defined"
  (lambda ()
    (assert-equal "IN_CREATE" #x100 IN_CREATE)
    (assert-equal "IN_DELETE" #x200 IN_DELETE)
    (assert-equal "IN_MODIFY" #x002 IN_MODIFY)
    (assert-true "IN_ALL_EVENTS" (> IN_ALL_EVENTS 0))))

;;; ===== Landlock Tests =====

(test "landlock: abi version check"
  (lambda ()
    (let ([v (landlock-abi-version)])
      (assert-true "version is integer" (integer? v))
      (if (>= v 1)
        (begin
          (assert-true "available" (landlock-available?))
          (display (string-append "  (Landlock ABI v" (number->string v) " available)\n")))
        (display "  (Landlock not supported on this kernel)\n")))))

(test "landlock: constants defined"
  (lambda ()
    (assert-equal "FS_READ_FILE" 4 LANDLOCK_ACCESS_FS_READ_FILE)
    (assert-equal "FS_WRITE_FILE" 2 LANDLOCK_ACCESS_FS_WRITE_FILE)
    (assert-equal "FS_EXECUTE" 1 LANDLOCK_ACCESS_FS_EXECUTE)
    (assert-equal "NET_BIND" 1 LANDLOCK_ACCESS_NET_BIND_TCP)))

(test "landlock: create and close ruleset"
  (lambda ()
    (if (landlock-available?)
      (let ([fd (landlock-create-ruleset
                  (bitwise-ior LANDLOCK_ACCESS_FS_READ_FILE
                               LANDLOCK_ACCESS_FS_READ_DIR) 0)])
        (assert-true "valid fd" (>= fd 0))
        (close-fd fd))
      (display "  (skipped - landlock not available)\n"))))

;;; ===== PostgreSQL binding test (load only) =====

(test "postgresql-native: module loads"
  (lambda ()
    (eval '(import (std db postgresql-native)))
    (assert-true "loaded" #t)))

;;; ===== Summary =====

(newline)
(display (string-append
  "Results: " (number->string pass-count) "/" (number->string test-count)
  " passed, " (number->string fail-count) " failed\n"))

(when (> fail-count 0)
  (exit 1))
