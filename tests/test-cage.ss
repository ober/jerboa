(import (jerboa prelude))
(import (std security cage))
(import (std security landlock))
(import (std security capsicum))
(import (std security seatbelt))

;; fork-process and waitpid for subprocess tests
(guard (e [#t (void)])
  (load-shared-object "libc.so.7"))
(guard (e [#t (void)])
  (load-shared-object "libc.so.6"))
(guard (e [#t (void)])
  (load-shared-object "libc.dylib"))
(define fork-process
  (guard (e [#t (lambda () (error 'fork "not available"))])
    (foreign-procedure "fork" () int)))
(define waitpid
  (let ([c-waitpid
          (guard (e [#t (lambda (pid buf flags) -1)])
            (foreign-procedure "waitpid" (int u8* int) int))])
    (lambda (pid)
      (let ([status-buf (make-bytevector 4 0)])
        (let ([result (c-waitpid pid status-buf 0)])
          (values result (bytevector-s32-native-ref status-buf 0)))))))

(displayln "=== cage tests ===")

;; ---- Config construction ----

(displayln "--- config construction ---")

;; Basic config
(let ([cfg (make-cage-config 'root: "/tmp")])
  (assert! (cage-config? cfg))
  (assert! (string=? (cage-config-root cfg) "/tmp"))
  (assert! (null? (cage-config-read-only cfg)))
  (assert! (null? (cage-config-read-write cfg)))
  (assert! (null? (cage-config-execute cfg)))
  (assert! (eq? #t (cage-config-network cfg)))
  (assert! (eq? 'auto (cage-config-system-paths cfg)))
  (assert! (string=? "/tmp" (cage-config-temp-dir cfg)))
  (displayln "  basic config: ok"))

;; Full config
(let ([cfg (make-cage-config
             'root: "/home/user/project"
             'read-only: '("/usr/share/man")
             'read-write: '("/var/data")
             'execute: '("/opt/bin")
             'network: #f
             'system-paths: #f
             'temp-dir: "/var/tmp")])
  (assert! (string=? "/home/user/project" (cage-config-root cfg)))
  (assert! (equal? '("/usr/share/man") (cage-config-read-only cfg)))
  (assert! (equal? '("/var/data") (cage-config-read-write cfg)))
  (assert! (equal? '("/opt/bin") (cage-config-execute cfg)))
  (assert! (eq? #f (cage-config-network cfg)))
  (assert! (eq? #f (cage-config-system-paths cfg)))
  (assert! (string=? "/var/tmp" (cage-config-temp-dir cfg)))
  (displayln "  full config: ok"))

;; Missing 'root: raises error
(let ([got-error (not #t)])
  (try
    (make-cage-config 'read-only: '("/tmp"))
    (catch (e) (set! got-error #t)))
  (assert! got-error)
  (displayln "  missing root error: ok"))

;; Unknown keyword raises error
(let ([got-error (not #t)])
  (try
    (make-cage-config 'root: "/tmp" 'bogus: 42)
    (catch (e) (set! got-error #t)))
  (assert! got-error)
  (displayln "  unknown keyword error: ok"))

;; ---- State before cage ----

(displayln "--- state checks ---")

(assert! (not (cage-active?)))
(assert! (not (cage-root)))
(assert! (null? (cage-allowed-paths)))
(displayln "  pre-cage state: ok")

;; ---- Cage in forked child (so we don't cage the test runner) ----

(displayln "--- cage! in forked subprocess ---")

;; We test cage! by forking, so the parent test process stays uncaged.
;; The child applies the cage and verifies restrictions.

(when (landlock-available?)
  ;; Create a temp directory for the cage root
  (let ([cage-dir "/tmp/jerboa-cage-test"])
    ;; Setup
    (when (file-exists? cage-dir)
      (system (str "rm -rf " cage-dir)))
    (mkdir cage-dir)
    (write-file-string (str cage-dir "/hello.txt") "hello from cage")

    ;; Fork and cage the child
    (let ([pid (fork-process)])
      (cond
        ((= pid 0)
         ;; === CHILD ===
         (guard (exn
                  (#t
                   (display "CHILD ERROR: ")
                   (display-condition exn)
                   (newline)
                   (exit 1)))

           ;; Apply cage
           (cage! (make-cage-config
                    'root: cage-dir
                    'system-paths: 'auto
                    'temp-dir: "/tmp"))

           ;; Verify cage is active
           (assert! (cage-active?))
           (assert! (string? (cage-root)))

           ;; Can read file inside cage
           (let ([content (read-file-string (str cage-dir "/hello.txt"))])
             (assert! (string=? content "hello from cage")))

           ;; Can write inside cage
           (write-file-string (str cage-dir "/new.txt") "created in cage")
           (assert! (string=? (read-file-string (str cage-dir "/new.txt"))
                              "created in cage"))

           ;; Cannot read outside cage (e.g. /etc/shadow)
           ;; Landlock should block this — we get a permission error
           (let ([blocked (not #t)])
             (guard (exn (#t (set! blocked #t)))
               (read-file-string "/etc/shadow"))
             (assert! blocked))

           ;; Cannot write outside cage
           (let ([blocked (not #t)])
             (guard (exn (#t (set! blocked #t)))
               (write-file-string "/etc/jerboa-cage-escape" "nope"))
             (assert! blocked))

           ;; Can still use /tmp (temp-dir)
           (let ([tmp-file "/tmp/jerboa-cage-tmp-test"])
             (write-file-string tmp-file "tmp works")
             (assert! (string=? (read-file-string tmp-file) "tmp works"))
             (delete-file tmp-file))

           (displayln "  child cage restrictions: ok")
           (exit 0)))

        (else
         ;; === PARENT ===
         (let-values ([(wpid status) (waitpid pid)])
           (let ([exit-code (bitwise-arithmetic-shift-right
                              (bitwise-and status #xFF00) 8)])
             (if (= exit-code 0)
               (displayln "  cage! fork test: ok")
               (begin
                 (displayln (str "  cage! fork test: FAILED (exit " exit-code ")"))
                 (exit 1))))))))

    ;; Cleanup
    (system (str "rm -rf " cage-dir))))

(unless (landlock-available?)
  (displayln "  [skipped — Landlock not available]"))

;; ---- FreeBSD Capsicum cage test ----

(displayln "--- FreeBSD Capsicum cage ---")

(when (capsicum-available?)
  ;; Create a temp directory for the cage root
  (let ([cage-dir "/tmp/jerboa-cage-test-fb"])
    ;; Setup
    (when (file-exists? cage-dir)
      (system (str "rm -rf " cage-dir)))
    (mkdir cage-dir)
    (write-file-string (str cage-dir "/hello.txt") "hello from capsicum cage")

    ;; Fork and cage the child
    (let ([pid (fork-process)])
      (cond
        ((= pid 0)
         ;; === CHILD ===
         (guard (exn
                  (#t
                   (display "CHILD ERROR: ")
                   (display-condition exn)
                   (newline)
                   (exit 1)))

           ;; Apply cage via Capsicum
           (cage! (make-cage-config
                    'root: cage-dir
                    'system-paths: 'auto
                    'temp-dir: "/tmp"))

           ;; Verify cage is active
           (assert! (cage-active?))
           (assert! (string? (cage-root)))

           ;; Verify we're in Capsicum capability mode
           (assert! (capsicum-in-capability-mode?))

           ;; Cannot open new files from global namespace (cap_enter blocks this)
           (let ([blocked (not #t)])
             (guard (exn (#t (set! blocked #t)))
               (open-input-file "/etc/passwd"))
             (assert! blocked))

           (displayln "  child capsicum cage: ok")
           (exit 0)))

        (else
         ;; === PARENT ===
         (let-values ([(wpid status) (waitpid pid)])
           (let ([exit-code (bitwise-arithmetic-shift-right
                              (bitwise-and status #xFF00) 8)])
             (if (= exit-code 0)
               (displayln "  capsicum cage! fork test: ok")
               (begin
                 (displayln (str "  capsicum cage! fork test: FAILED (exit " exit-code ")"))
                 (exit 1))))))))

    ;; Cleanup
    (system (str "rm -rf " cage-dir))))

(unless (capsicum-available?)
  (displayln "  [skipped — Capsicum not available]"))

;; ---- macOS Seatbelt cage test ----

(displayln "--- macOS Seatbelt cage ---")

(when (seatbelt-available?)
  (let ([cage-dir "/tmp/jerboa-cage-test-macos"])
    (when (file-exists? cage-dir)
      (system (str "rm -rf " cage-dir)))
    (mkdir cage-dir)
    (write-file-string (str cage-dir "/hello.txt") "hello from seatbelt cage")

    (let ([pid (fork-process)])
      (cond
        ((= pid 0)
         (guard (exn
                  (#t
                   (display "CHILD ERROR: ")
                   (display-condition exn)
                   (newline)
                   (exit 1)))

           (cage! (make-cage-config
                    'root: cage-dir
                    'system-paths: 'auto
                    'temp-dir: "/tmp"
                    'network: #f))

           (assert! (cage-active?))
           (assert! (string? (cage-root)))

           ;; Read inside cage works
           (let ([content (read-file-string (str cage-dir "/hello.txt"))])
             (assert! (string=? content "hello from seatbelt cage")))

           ;; Write inside cage works
           (write-file-string (str cage-dir "/new.txt") "wrote inside")
           (assert! (string=? (read-file-string (str cage-dir "/new.txt"))
                              "wrote inside"))

           ;; Write outside cage is blocked. /Users is outside the cage
           ;; (root is in /tmp, system paths are read-only).
           (let ([blocked (not #t)])
             (guard (exn (#t (set! blocked #t)))
               (write-file-string "/Users/jerboa-cage-escape" "nope"))
             (assert! blocked))

           ;; Reading non-allowed paths is blocked
           (let ([blocked (not #t)])
             (guard (exn (#t (set! blocked #t)))
               (read-file-string "/etc/master.passwd"))
             (assert! blocked))

           (displayln "  child seatbelt cage: ok")
           (exit 0)))

        (else
         (let-values ([(wpid status) (waitpid pid)])
           (let ([exit-code (bitwise-arithmetic-shift-right
                              (bitwise-and status #xFF00) 8)])
             (if (= exit-code 0)
               (displayln "  seatbelt cage! fork test: ok")
               (begin
                 (displayln (str "  seatbelt cage! fork test: FAILED (exit " exit-code ")"))
                 (exit 1))))))))

    (system (str "rm -rf " cage-dir))))

(unless (seatbelt-available?)
  (displayln "  [skipped — Seatbelt not available]"))

;; ---- Double-cage prevention ----

(displayln "--- double cage prevention ---")

(when (landlock-available?)
  (let ([pid (fork-process)])
    (cond
      ((= pid 0)
       (guard (exn
                (#t (display "CHILD ERROR: ")
                    (display-condition exn) (newline)
                    (exit 1)))
         (let ([cage-dir "/tmp/jerboa-cage-test2"])
           (when (file-exists? cage-dir) (system (str "rm -rf " cage-dir)))
           (mkdir cage-dir)
           (cage! (make-cage-config 'root: cage-dir 'temp-dir: "/tmp"))
           ;; Second cage! should raise
           (let ([got-error (not #t)])
             (try
               (cage! (make-cage-config 'root: cage-dir 'temp-dir: "/tmp"))
               (catch (e) (set! got-error #t)))
             (assert! got-error)
             (displayln "  double cage blocked: ok")
             (system (str "rm -rf " cage-dir))
             (exit 0)))))
      (else
       (let-values ([(wpid status) (waitpid pid)])
         (let ([exit-code (bitwise-arithmetic-shift-right
                            (bitwise-and status #xFF00) 8)])
           (if (= exit-code 0)
             (displayln "  double cage test: ok")
             (begin
               (displayln (str "  double cage test: FAILED (exit " exit-code ")"))
               (exit 1)))))))))

(unless (landlock-available?)
  (displayln "  [skipped — Landlock not available]"))

;; FreeBSD double-cage prevention
(when (capsicum-available?)
  (let ([pid (fork-process)])
    (cond
      ((= pid 0)
       (guard (exn
                (#t (display "CHILD ERROR: ")
                    (display-condition exn) (newline)
                    (exit 1)))
         (let ([cage-dir "/tmp/jerboa-cage-test2-fb"])
           (when (file-exists? cage-dir) (system (str "rm -rf " cage-dir)))
           (mkdir cage-dir)
           (cage! (make-cage-config 'root: cage-dir 'temp-dir: "/tmp"))
           ;; Second cage! should raise
           (let ([got-error (not #t)])
             (try
               (cage! (make-cage-config 'root: cage-dir 'temp-dir: "/tmp"))
               (catch (e) (set! got-error #t)))
             (assert! got-error)
             (displayln "  FreeBSD double cage blocked: ok")
             (exit 0)))))
      (else
       (let-values ([(wpid status) (waitpid pid)])
         (let ([exit-code (bitwise-arithmetic-shift-right
                            (bitwise-and status #xFF00) 8)])
           (if (= exit-code 0)
             (displayln "  FreeBSD double cage test: ok")
             (begin
               (displayln (str "  FreeBSD double cage test: FAILED (exit " exit-code ")"))
               (exit 1)))))))))

(unless (capsicum-available?)
  (displayln "  [skipped — Capsicum not available]"))

;; macOS Seatbelt double-cage prevention
(when (seatbelt-available?)
  (let ([pid (fork-process)])
    (cond
      ((= pid 0)
       (guard (exn
                (#t (display "CHILD ERROR: ")
                    (display-condition exn) (newline)
                    (exit 1)))
         (let ([cage-dir "/tmp/jerboa-cage-test2-macos"])
           (when (file-exists? cage-dir) (system (str "rm -rf " cage-dir)))
           (mkdir cage-dir)
           (cage! (make-cage-config 'root: cage-dir 'temp-dir: "/tmp"))
           (let ([got-error (not #t)])
             (try
               (cage! (make-cage-config 'root: cage-dir 'temp-dir: "/tmp"))
               (catch (e) (set! got-error #t)))
             (assert! got-error)
             (displayln "  macOS double cage blocked: ok")
             (exit 0)))))
      (else
       (let-values ([(wpid status) (waitpid pid)])
         (let ([exit-code (bitwise-arithmetic-shift-right
                            (bitwise-and status #xFF00) 8)])
           (if (= exit-code 0)
             (displayln "  macOS double cage test: ok")
             (begin
               (displayln (str "  macOS double cage test: FAILED (exit " exit-code ")"))
               (exit 1)))))))))

(unless (seatbelt-available?)
  (displayln "  [skipped — Seatbelt not available]"))

(displayln "=== all cage tests passed ===")
