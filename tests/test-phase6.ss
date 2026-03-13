#!chezscheme
;;; test-phase6.ss — Tests for Phase 6: Making Real Programs Easier to Build
;;;
;;; Tracks 20-29: POSIX FFI, Platform, Build, App, FD Manager,
;;; Signal Channels, Raw I/O, Persistent Map, Error Diagnostics,
;;; Capability Security

(import (chezscheme))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr]
           [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (display "FAIL: ")
           (write 'expr)
           (display " => ")
           (write result)
           (display " expected ")
           (write exp)
           (newline))))]
    [(_ expr)
     (if expr
       (set! pass-count (+ pass-count 1))
       (begin
         (set! fail-count (+ fail-count 1))
         (display "FAIL: ")
         (write 'expr)
         (display " => #f")
         (newline)))]))

(define-syntax check-no-error
  (syntax-rules ()
    [(_ expr)
     (guard (e [#t
                (set! fail-count (+ fail-count 1))
                (display "FAIL (exception): ")
                (write 'expr)
                (display " => ")
                (if (message-condition? e)
                  (display (condition-message e))
                  (display e))
                (newline)])
       expr
       (set! pass-count (+ pass-count 1)))]))

;;; ======================================================================
;;; Track 20: Declarative POSIX FFI
;;; ======================================================================
(display "--- Track 20: POSIX FFI ---\n")

(import (std os posix))

;; Test process IDs
(let ([pid (posix-getpid)])
  (check (> pid 0))
  (check (integer? pid)))

(let ([ppid (posix-getppid)])
  (check (> ppid 0)))

;; Test wait status decoders
(check (WIFEXITED 0) => #t)
(check (WEXITSTATUS 0) => 0)
(check (WIFEXITED #x0100) => #t)
(check (WEXITSTATUS #x0100) => 1)
(check (WIFSIGNALED #x0009) => #t)
(check (WTERMSIG #x0009) => 9)
(check (WIFSTOPPED #x137f) => #t)
(check (WSTOPSIG #x137f) => 19)

;; Test constants
(check O_RDONLY => 0)
(check O_WRONLY => 1)
(check O_RDWR => 2)
(check SEEK_SET => 0)
(check SEEK_CUR => 1)
(check SEEK_END => 2)
(check WNOHANG => 1)

;; Test signal constants
(check SIGINT => 2)
(check SIGTERM => 15)
(check SIGKILL => 9)
(check SIGCHLD => 17)

;; Test access flags
(check F_OK => 0)
(check R_OK => 4)

;; Test errno/strerror
(check (string? (posix-strerror 2)) => #t)  ;; ENOENT
(check (> (string-length (posix-strerror 2)) 0) => #t)

;; Test posix-access
(check (posix-access "/" R_OK) => #t)
(check (posix-access "/nonexistent-path-xyz" F_OK) => #f)

;; Test posix-isatty (stdin may or may not be a tty in test context)
(check (boolean? (posix-isatty 0)))

;; Test posix-umask
(let ([old (posix-umask #o022)])
  (posix-umask old)  ;; restore
  (check (integer? old)))

;; Test posix-getuid/geteuid/getegid
(check (integer? (posix-getuid)))
(check (integer? (posix-geteuid)))
(check (integer? (posix-getegid)))

;; Test pipe and basic I/O
(let-values ([(rfd wfd) (posix-pipe)])
  (let ([msg (string->utf8 "hello")])
    (posix-write wfd msg 5)
    (let ([buf (make-bytevector 5)])
      (let ([n (posix-read rfd buf 5)])
        (check n => 5)
        (check (utf8->string buf) => "hello"))))
  (posix-close rfd)
  (posix-close wfd))

;; Test posix-open/close with temp file
(let ([path "/tmp/jerboa-test-posix.tmp"])
  (guard (e [#t (void)])
    (let ([fd (posix-open path
                (bitwise-ior O_WRONLY O_CREAT O_TRUNC)
                #o644)])
      (let ([msg (string->utf8 "test data")])
        (posix-write fd msg (bytevector-length msg)))
      (posix-close fd)
      ;; Read it back
      (let ([fd2 (posix-open path O_RDONLY)])
        (let ([buf (make-bytevector 9)])
          (let ([n (posix-read fd2 buf 9)])
            (check n => 9)
            (check (utf8->string buf) => "test data")))
        (posix-close fd2))
      ;; Stat
      (let ([st (posix-stat path)])
        (check (stat-is-regular? st))
        (check (not (stat-is-directory? st)))
        (check (= (stat-size st) 9))
        (check (> (stat-mtime st) 0))
        (free-stat st))
      ;; Cleanup
      (posix-unlink path))))

;; Test posix-dup/dup2
(let-values ([(rfd wfd) (posix-pipe)])
  (let ([dup-fd (posix-dup rfd)])
    (check (> dup-fd 0))
    (check (not (= dup-fd rfd)))
    (posix-close dup-fd))
  (posix-close rfd)
  (posix-close wfd))

;; Test posix-lseek
(let ([path "/tmp/jerboa-test-lseek.tmp"])
  (guard (e [#t (void)])
    (let ([fd (posix-open path (bitwise-ior O_RDWR O_CREAT O_TRUNC) #o644)])
      (posix-write fd (string->utf8 "abcdef") 6)
      (let ([pos (posix-lseek fd 0 SEEK_SET)])
        (check pos => 0))
      (let ([pos (posix-lseek fd 0 SEEK_END)])
        (check pos => 6))
      (posix-close fd)
      (posix-unlink path))))

;; Test posix-fcntl-getfl/setfl
(let-values ([(rfd wfd) (posix-pipe)])
  (let ([flags (posix-fcntl-getfl rfd)])
    (check (integer? flags))
    ;; Set non-blocking
    (posix-fcntl-setfl rfd (bitwise-ior flags O_NONBLOCK))
    (let ([new-flags (posix-fcntl-getfl rfd)])
      (check (not (zero? (bitwise-and new-flags O_NONBLOCK))))))
  (posix-close rfd)
  (posix-close wfd))

;; Test posix error handling
(guard (e [(posix-error? e)
           (check (integer? (posix-error-errno e)))
           (check (symbol? (posix-error-syscall e)))
           (check (string? (posix-error-message e)))]
          [#t (check #f)])
  (posix-open "/nonexistent/path/for/testing" O_RDONLY)
  (check #f))  ;; should not reach here

;; Test resource limits
(let-values ([(soft hard) (posix-getrlimit RLIMIT_NOFILE)])
  (check (> soft 0))
  (check (>= hard soft)))

;; Test strftime
(let ([s (posix-strftime "%Y" 0)])
  (check (string? s))
  (check (> (string-length s) 0)))

;; Test sigprocmask
(let ([old (posix-sigprocmask SIG_BLOCK (list SIGUSR1))])
  (check (list? old))
  ;; Unblock
  (posix-sigprocmask SIG_UNBLOCK (list SIGUSR1)))

;; Test terminal size (may fail on non-terminal)
(let-values ([(rows cols) (posix-get-terminal-size 0)])
  (check (integer? rows))
  (check (integer? cols))
  (check (> rows 0))
  (check (> cols 0)))

;; Test posix-setenv/unsetenv
(posix-setenv "JERBOA_TEST_VAR" "hello" #t)
(check (getenv "JERBOA_TEST_VAR") => "hello")
(posix-unsetenv "JERBOA_TEST_VAR")
(check (getenv "JERBOA_TEST_VAR") => #f)


;;; ======================================================================
;;; Track 21: Portable OS Abstraction
;;; ======================================================================
(display "--- Track 21: Platform ---\n")

(import (std os platform))

(check (string? (platform-name)))
(check (platform-linux?))  ;; we're on Linux
(check (not (platform-macos?)))

(let ([path (platform-executable-path)])
  (check (or (not path) (string? path))))

(let ([cpus (platform-cpu-count)])
  (check (> cpus 0))
  (check (integer? cpus)))

(let ([ps (platform-page-size)])
  (check (> ps 0))
  (check (integer? ps)))

;; Test tmpfile path generation
(let ([p (platform-tmpfile-path "test" ".tmp")])
  (check (string? p))
  (check (> (string-length p) 0)))


;;; ======================================================================
;;; Track 22: Incremental Parallel Build System
;;; ======================================================================
(display "--- Track 22: Build System ---\n")

(import (std build))

;; Test content hashing
(check (integer? (content-hash "hello")))
(check (= (content-hash "hello") (content-hash "hello")))
(check (not (= (content-hash "hello") (content-hash "world"))))

(define (list-index item lst)
  (let lp ([lst lst] [i 0])
    (cond
      [(null? lst) -1]
      [(equal? (car lst) item) i]
      [else (lp (cdr lst) (+ i 1))])))

;; Test topological sort
(let ([dag '(("a" . ("b" "c"))
             ("b" . ("c"))
             ("c" . ())
             ("d" . ("a")))])
  (let ([sorted (topological-sort dag)])
    (check (list? sorted))
    (check (= (length sorted) 4))
    ;; c must come before b, b before a, a before d
    (let ([pos-c (list-index "c" sorted)]
          [pos-b (list-index "b" sorted)]
          [pos-a (list-index "a" sorted)]
          [pos-d (list-index "d" sorted)])
      (check (< pos-c pos-b))
      (check (< pos-b pos-a))
      (check (< pos-a pos-d)))))

;; Test module discovery
(let ([modules (discover-modules "lib/std/os")])
  (check (list? modules))
  (check (> (length modules) 0)))

;; Test build cache
(let ([cache-file "/tmp/jerboa-test-build-cache.fasl"])
  (guard (e [#t (void)])
    (let ([cache (build-cache-load cache-file)])
      (check (hashtable? cache))
      (hashtable-set! cache "test.sls" 12345)
      (build-cache-save cache-file cache)
      (let ([cache2 (build-cache-load cache-file)])
        (check (= (hashtable-ref cache2 "test.sls" 0) 12345))))
    (delete-file cache-file)))


;;; ======================================================================
;;; Track 23: Safe Program Loading
;;; ======================================================================
(display "--- Track 23: Application Framework ---\n")

(import (std app))

;; Test make-app
(let ([a (make-app "test-app"
           (lambda () 'initialized)
           (lambda (args) args))])
  (check (app? a))
  (check (string=? (app-name a) "test-app"))
  (check (procedure? (app-init-proc a)))
  (check (procedure? (app-main-proc a))))


;;; ======================================================================
;;; Track 24: Structured FD and Process Manager
;;; ======================================================================
(display "--- Track 24: FD Manager ---\n")

(import (std os fd))

;; Test FD objects
(let-values ([(rfd wfd) (fd-pipe)])
  (check (fd? rfd))
  (check (fd? wfd))
  (check (fd-open? rfd))
  (check (fd-open? wfd))
  (check (integer? (fd-num rfd)))
  ;; Write and read
  (fd-write wfd (string->utf8 "test"))
  (let ([data (fd-read rfd 4)])
    (check (utf8->string data) => "test"))
  ;; Close
  (fd-close! rfd)
  (fd-close! wfd)
  (check (not (fd-open? rfd)))
  (check (not (fd-open? wfd))))

;; Test with-fds cleanup
(let ([saved-fd #f])
  (with-fds ([p1 (let-values ([(r w) (fd-pipe)])
                   (fd-close! w)  ;; close write end
                   r)])
    (set! saved-fd p1)
    (check (fd-open? p1)))
  ;; After with-fds, fd should be closed
  (check (not (fd-open? saved-fd))))

;; Test with-fds on exception
(let ([saved-fd #f])
  (guard (e [#t (void)])
    (with-fds ([p1 (let-values ([(r w) (fd-pipe)])
                     (fd-close! w)
                     r)])
      (set! saved-fd p1)
      (error 'test "intentional error")))
  ;; fd should still be closed even on error
  (check (not (fd-open? saved-fd))))

;; Test fd-dup
(let-values ([(rfd wfd) (fd-pipe)])
  (let ([dup (fd-dup rfd)])
    (check (fd? dup))
    (check (not (= (fd-num dup) (fd-num rfd))))
    (fd-close! dup))
  (fd-close! rfd)
  (fd-close! wfd))

;; Test process spawning
(let ([proc (spawn-process '("echo" "hello"))])
  (check (process? proc))
  (check (> (process-pid proc) 0))
  (process-wait proc)
  (check (process-exited? proc))
  (check (= (process-exit-code proc) 0)))

;; Test process with failing command
(let ([proc (spawn-process '("false"))])
  (process-wait proc)
  (check (process-exited? proc))
  (check (not (= (process-exit-code proc) 0))))

;; Test constants
(check STDIN_FILENO => 0)
(check STDOUT_FILENO => 1)
(check STDERR_FILENO => 2)


;;; ======================================================================
;;; Track 26: Raw Byte I/O
;;; ======================================================================
(display "--- Track 26: Raw Byte I/O ---\n")

(import (std io raw))

;; Test fd-read-bytes / fd-write-bytes via pipe
(let-values ([(rfd wfd) (posix-pipe)])
  ;; Test binary data with bytes > 127 (would be mangled by UTF-8)
  (let ([data (bytevector 0 127 128 255 0 1)])
    (fd-write-bytes wfd data)
    (let ([result (fd-read-bytes rfd 6)])
      (check (bytevector=? result data) => #t)))
  (posix-close rfd)
  (posix-close wfd))

;; Test fd->binary-input-port / output-port via pipe
(let-values ([(rfd wfd) (posix-pipe)])
  (let ([out-port (fd->binary-output-port wfd "test-out")]
        [in-port (fd->binary-input-port rfd "test-in")])
    (put-bytevector out-port (bytevector 1 2 3 4 5))
    (flush-output-port out-port)
    (close-port out-port)
    (let ([bv (get-bytevector-n in-port 5)])
      (check (bytevector? bv))
      (check (= (bytevector-length bv) 5))
      (check (= (bytevector-u8-ref bv 0) 1))
      (check (= (bytevector-u8-ref bv 4) 5)))
    (close-port in-port)))

;; Test bytevector-concat
(check (bytevector-concat '()) => (make-bytevector 0))
(check (bytevector-concat (list (bytevector 1 2) (bytevector 3 4)))
       => (bytevector 1 2 3 4))
(check (bytevector-concat (list (bytevector 1) (bytevector) (bytevector 2)))
       => (bytevector 1 2))


;;; ======================================================================
;;; Track 27: Persistent Map (Copy-on-Write)
;;; ======================================================================
(display "--- Track 27: Persistent Map ---\n")

(import (std data pmap))

;; Test empty pmap
(check (pmap? pmap-empty))
(check (= (pmap-size pmap-empty) 0))

;; Test insert and lookup
(let* ([m1 (pmap-set pmap-empty "a" 1)]
       [m2 (pmap-set m1 "b" 2)]
       [m3 (pmap-set m2 "c" 3)])
  (check (= (pmap-size m1) 1))
  (check (= (pmap-size m2) 2))
  (check (= (pmap-size m3) 3))
  (check (= (pmap-ref m3 "a" #f) 1))
  (check (= (pmap-ref m3 "b" #f) 2))
  (check (= (pmap-ref m3 "c" #f) 3))
  (check (eq? (pmap-ref m3 "d" 'missing) 'missing))

  ;; Original maps unchanged (persistence!)
  (check (= (pmap-size m1) 1))
  (check (eq? (pmap-ref m1 "b" 'missing) 'missing)))

;; Test update existing key
(let* ([m1 (pmap-set pmap-empty "x" 1)]
       [m2 (pmap-set m1 "x" 2)])
  (check (= (pmap-ref m1 "x" #f) 1))  ;; original unchanged
  (check (= (pmap-ref m2 "x" #f) 2)))  ;; updated

;; Test delete
(let* ([m1 (pmap-set (pmap-set (pmap-set pmap-empty "a" 1) "b" 2) "c" 3)]
       [m2 (pmap-delete m1 "b")])
  (check (= (pmap-size m2) 2))
  (check (= (pmap-ref m2 "a" #f) 1))
  (check (eq? (pmap-ref m2 "b" 'gone) 'gone))
  (check (= (pmap-ref m2 "c" #f) 3))
  ;; Original unchanged
  (check (= (pmap-size m1) 3)))

;; Test contains
(let ([m (pmap-set (pmap-set pmap-empty "a" 1) "b" 2)])
  (check (pmap-contains? m "a"))
  (check (pmap-contains? m "b"))
  (check (not (pmap-contains? m "c"))))

;; Test pmap->alist and alist->pmap
(let* ([alist '(("x" . 10) ("y" . 20) ("z" . 30))]
       [m (alist->pmap alist)])
  (check (= (pmap-size m) 3))
  (check (= (pmap-ref m "x" #f) 10))
  (check (= (pmap-ref m "y" #f) 20))
  (check (= (pmap-ref m "z" #f) 30))
  (let ([alist2 (pmap->alist m)])
    (check (= (length alist2) 3))))

;; Test snapshot (O(1))
(let ([m (alist->pmap '(("a" . 1) ("b" . 2)))])
  (let ([snap (pmap-snapshot m)])
    (check (eq? snap m))))  ;; same object — O(1) snapshot

;; Test pmap-fold
(let ([m (alist->pmap '(("a" . 1) ("b" . 2) ("c" . 3)))])
  (let ([sum (pmap-fold (lambda (k v acc) (+ v acc)) 0 m)])
    (check (= sum 6))))

;; Test pmap-keys and pmap-values
(let ([m (alist->pmap '(("a" . 1) ("b" . 2)))])
  (let ([keys (sort string<? (pmap-keys m))]
        [vals (sort < (pmap-values m))])
    (check keys => '("a" "b"))
    (check vals => '(1 2))))

;; Test pmap-merge
(let ([base (alist->pmap '(("a" . 1) ("b" . 2)))]
      [overlay (alist->pmap '(("b" . 20) ("c" . 30)))])
  (let ([merged (pmap-merge base overlay)])
    (check (= (pmap-ref merged "a" #f) 1))
    (check (= (pmap-ref merged "b" #f) 20))  ;; overlay wins
    (check (= (pmap-ref merged "c" #f) 30))))

;; Test mutable cell wrapper
(let ([cell (make-pmap-cell)])
  (check (pmap-cell? cell))
  (pmap-cell-set! cell "name" "Alice")
  (pmap-cell-set! cell "age" 30)
  (check (equal? (pmap-cell-ref cell "name") "Alice"))
  (check (equal? (pmap-cell-ref cell "age") 30))
  ;; Snapshot
  (let ([snap (pmap-cell-snapshot cell)])
    (pmap-cell-set! cell "name" "Bob")
    ;; Snapshot unchanged
    (check (equal? (pmap-ref snap "name" #f) "Alice"))
    ;; Cell updated
    (check (equal? (pmap-cell-ref cell "name") "Bob"))))

;; Test many keys (stress test HAMT branching)
(let ([m (let lp ([i 0] [m pmap-empty])
           (if (= i 100) m
             (lp (+ i 1) (pmap-set m (number->string i) i))))])
  (check (= (pmap-size m) 100))
  (check (= (pmap-ref m "0" #f) 0))
  (check (= (pmap-ref m "50" #f) 50))
  (check (= (pmap-ref m "99" #f) 99)))


;;; ======================================================================
;;; Track 28: Error Recovery and Diagnostics
;;; ======================================================================
(display "--- Track 28: Error Diagnostics ---\n")

(import (std error diagnostics))
(import (std error recovery))

;; Test diagnostic formatting
(let ([err (condition
             (make-error)
             (make-message-condition "test error")
             (make-irritants-condition '(detail1 detail2))
             (make-who-condition 'test-proc))])
  (let ([formatted (format-diagnostic err '())])
    (check (string? formatted))
    (check (> (string-length formatted) 0))))

;; Test with-diagnostics catches errors
(let ([caught #f])
  (with-diagnostics
    (lambda () (error 'test "intentional error"))
    'on-error: (lambda (err frames port)
                 (set! caught #t)))
  (check caught))

;; Test with-retry
(let ([attempts 0])
  (guard (e [#t (void)])
    (with-retry
      (lambda ()
        (set! attempts (+ attempts 1))
        (when (< attempts 3)
          (error 'test "retry me")))
      'attempts: 5))
  (check (= attempts 3)))

;; Test with-retry exhaustion
(let ([attempts 0])
  (guard (e [#t (void)])
    (with-retry
      (lambda ()
        (set! attempts (+ attempts 1))
        (error 'test "always fails"))
      'attempts: 3))
  (check (= attempts 3)))

;; Test with-fallback
(let ([result (with-fallback
                (lambda () (error 'test "primary fails"))
                (lambda (e) 'fallback-value))])
  (check result => 'fallback-value))

(let ([result (with-fallback
                (lambda () 'primary-value)
                (lambda (e) 'fallback-value))])
  (check result => 'primary-value))

;; Test with-cleanup (only on error)
(let ([cleaned #f])
  (with-cleanup
    (lambda () 42)
    (lambda () (set! cleaned #t)))
  (check (not cleaned)))  ;; cleanup NOT called on success

(let ([cleaned #f])
  (guard (e [#t (void)])
    (with-cleanup
      (lambda () (error 'test "boom"))
      (lambda () (set! cleaned #t))))
  (check cleaned))  ;; cleanup called on error


;;; ======================================================================
;;; Track 29: Capability-Based Security
;;; ======================================================================
(display "--- Track 29: Security Capabilities ---\n")

(import (std security capability))
(import (std security restrict))

;; Test capability creation
(let ([cap (make-fs-capability 'read: #t 'write: #f 'paths: '("/tmp" "/home"))])
  (check (capability? cap))
  (check (eq? (capability-type cap) 'filesystem))
  (check (fs-read? cap))
  (check (not (fs-write? cap)))
  (check (fs-allowed-path? cap "/tmp/test.txt"))
  (check (fs-allowed-path? cap "/home/user/file"))
  (check (not (fs-allowed-path? cap "/etc/passwd"))))

;; Test network capability
(let ([cap (make-net-capability 'connect: #t 'listen: #f
                                'hosts: '("example.com" "api.test.com"))])
  (check (capability? cap))
  (check (net-connect? cap))
  (check (not (net-listen? cap)))
  (check (net-allowed-host? cap "example.com"))
  (check (not (net-allowed-host? cap "evil.com"))))

;; Test process capability
(let ([cap (make-process-capability 'spawn: #t 'signal: #f)])
  (check (process-spawn? cap))
  (check (not (process-signal? cap))))

;; Test environment capability
(let ([cap (make-env-capability 'read: #t 'write: #f)])
  (check (env-read? cap))
  (check (not (env-write? cap))))

;; Test with-capabilities context
(let ([fs-cap (make-fs-capability 'read: #t 'write: #t 'paths: '("/tmp"))])
  (with-capabilities (list fs-cap)
    (lambda ()
      (check (pair? (current-capabilities)))
      (check (eq? (capability-type (car (current-capabilities))) 'filesystem)))))

;; Test capability violation
(guard (e [(capability-violation? e)
           (check (eq? (capability-violation-type e) 'network))]
          [#t (check #f)])
  (with-capabilities
    (list (make-fs-capability))
    (lambda ()
      ;; Try to check for network capability — should fail
      (check-capability! 'network 'connect))))

;; Test restricted eval
(let ([result (restricted-eval '(+ 1 2 3))])
  (check result => 6))

(let ([result (restricted-eval '(map (lambda (x) (* x x)) '(1 2 3 4)))])
  (check result => '(1 4 9 16)))

;; Test restricted eval blocks dangerous operations
(guard (e [#t (check #t)])  ;; should raise error
  (restricted-eval '(load "some-file.ss"))
  (check #f))  ;; should not reach here

;; Test safe-bindings list
(check (list? safe-bindings))
(check (> (length safe-bindings) 50))


;;; ======================================================================
;;; Summary
;;; ======================================================================

(newline)
(display "========================================\n")
(display (format "Phase 6 tests: ~a passed, ~a failed\n" pass-count fail-count))
(display "========================================\n")
(when (> fail-count 0) (exit 1))
