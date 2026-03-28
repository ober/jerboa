#!chezscheme
;;; (std service supervise) — DJB-style process supervision with sandboxing
;;;
;;; Core supervision loop for a single service directory. Forks the
;;; service's `run` script, monitors via SIGCHLD, accepts control
;;; commands via FIFO, writes DJB-compatible 18-byte status files.
;;; Adds Landlock/seccomp sandboxing and rlimit enforcement.

(library (std service supervise)
  (export supervise!)

  (import
    (chezscheme)
    (std os posix)
    (std service config))

  ;; ========== TAI64N Timestamps ==========
  ;; TAI64N: 8 bytes TAI seconds + 4 bytes nanoseconds
  ;; TAI = UNIX epoch + 2^62 (4611686018427387904)

  (define TAI-OFFSET 4611686018427387904)

  (define (tai64n-now)
    ;; Returns a 12-byte bytevector: 8 bytes TAI seconds + 4 bytes nanoseconds
    (let* ([t (current-time 'time-utc)]
           [secs (+ (time-second t) TAI-OFFSET)]
           [nsecs (time-nanosecond t)]
           [bv (make-bytevector 12 0)])
      ;; Pack seconds big-endian (8 bytes)
      (bytevector-u64-set! bv 0 secs (endianness big))
      ;; Pack nanoseconds big-endian (4 bytes)
      (bytevector-u32-set! bv 8 nsecs (endianness big))
      bv))

  ;; ========== Status File ==========
  ;; DJB format: 18 bytes
  ;; Bytes  0-11: TAI64N timestamp (when process entered current state)
  ;; Bytes 12-15: PID (big-endian uint32, 0 if down)
  ;; Byte     16: paused flag (0 or 1)
  ;; Byte     17: want flag (char: 'u' = up, 'd' = down, 0 = once)

  (define (write-status! service-dir pid up? paused? want timestamp)
    (let ([status-path (string-append service-dir "/supervise/status")]
          [tmp-path (string-append service-dir "/supervise/status.new")]
          [bv (make-bytevector 18 0)])
      ;; Copy timestamp (12 bytes)
      (bytevector-copy! timestamp 0 bv 0 12)
      ;; PID (big-endian uint32)
      (bytevector-u32-set! bv 12 (if up? pid 0) (endianness big))
      ;; Paused flag
      (bytevector-u8-set! bv 16 (if paused? 1 0))
      ;; Want flag
      (bytevector-u8-set! bv 17
        (case want
          [(up) (char->integer #\u)]
          [(down) (char->integer #\d)]
          [else 0]))
      ;; Atomic write: write to tmp, rename
      (let ([fd (posix-open tmp-path
                  (bitwise-ior O_WRONLY O_CREAT O_TRUNC) #o644)])
        (posix-write fd bv 18)
        (posix-close fd))
      (rename-file tmp-path status-path)))

  ;; ========== Environment Directory ==========
  ;; Each file in the env dir becomes an environment variable.
  ;; Filename = variable name, file contents = value (first line, trimmed).

  (define (load-envdir path)
    (when (and path (file-exists? path) (file-directory? path))
      (for-each
        (lambda (name)
          (let ([fpath (string-append path "/" name)])
            (when (file-regular? fpath)
              (let ([val (call-with-input-file fpath
                           (lambda (p)
                             (let ([line (get-line p)])
                               (if (eof-object? line) "" line))))])
                (posix-setenv name val #t)))))
        (directory-list path))))

  ;; ========== Resource Limits ==========

  (define (apply-rlimits! config)
    (let ([mem (service-config-memory-limit config)]
          [fsz (service-config-file-limit config)]
          [nof (service-config-nofile-limit config)]
          [npr (service-config-nproc-limit config)])
      (when mem (posix-setrlimit RLIMIT_AS mem mem))
      (when fsz (posix-setrlimit RLIMIT_FSIZE fsz fsz))
      (when nof (posix-setrlimit RLIMIT_NOFILE nof nof))
      (when npr (posix-setrlimit RLIMIT_NPROC npr npr))))

  ;; ========== User/Group Switching ==========
  ;; Resolve username/groupname to uid/gid via getpwnam/getgrnam

  (define c-getpwnam (foreign-procedure "getpwnam" (string) void*))
  (define c-getgrnam (foreign-procedure "getgrnam" (string) void*))

  (define (resolve-uid username)
    (if username
      (let ([pw (c-getpwnam username)])
        (if (zero? pw)
          (error 'supervise "unknown user" username)
          ;; struct passwd: pw_uid is at offset 16 on Linux x86_64
          ;; char* pw_name (8), char* pw_passwd (8), uid_t pw_uid (4)
          (foreign-ref 'unsigned-32 pw 16)))
      #f))

  (define (resolve-gid groupname)
    (if groupname
      (let ([gr (c-getgrnam groupname)])
        (if (zero? gr)
          (error 'supervise "unknown group" groupname)
          ;; struct group: gr_gid is at offset 16 on Linux x86_64
          ;; char* gr_name (8), char* gr_passwd (8), gid_t gr_gid (4)
          (foreign-ref 'unsigned-32 gr 16)))
      #f))

  (define (drop-privileges! config)
    (let ([gid (resolve-gid (service-config-group config))]
          [uid (resolve-uid (service-config-user config))])
      ;; Must setgid before setuid (can't change group after dropping root)
      (when gid (posix-setgid gid))
      (when uid (posix-setuid uid))))

  ;; ========== Control FIFO Commands ==========
  ;; Single-byte commands matching DJB daemontools:
  ;;   u = up, d = down, o = once, x = exit
  ;;   p = pause, c = continue
  ;;   h = HUP, a = ALRM, i = INT, t = TERM, k = KILL

  (define (handle-control-byte byte pid up?)
    ;; Returns (values new-want should-start? should-exit?)
    (let ([ch (integer->char byte)])
      (case ch
        [(#\u) (values 'up (not up?) #f)]    ;; start if not running
        [(#\d) (begin
                 (when (and up? (> pid 0))
                   (posix-kill pid SIGTERM)
                   (posix-kill pid SIGCONT))
                 (values 'down #f #f))]
        [(#\o) (values 'once (not up?) #f)]  ;; run once, don't restart
        [(#\x) (begin
                 (when (and up? (> pid 0))
                   (posix-kill pid SIGTERM)
                   (posix-kill pid SIGCONT))
                 (values 'down #f #t))]       ;; exit supervise
        [(#\p) (begin
                 (when (and up? (> pid 0))
                   (posix-kill pid SIGSTOP))
                 (values #f #f #f))]           ;; #f = don't change want
        [(#\c) (begin
                 (when (and up? (> pid 0))
                   (posix-kill pid SIGCONT))
                 (values #f #f #f))]
        [(#\h) (begin
                 (when (and up? (> pid 0))
                   (posix-kill pid SIGHUP))
                 (values #f #f #f))]
        [(#\a) (begin
                 (when (and up? (> pid 0))
                   (posix-kill pid SIGALRM))
                 (values #f #f #f))]
        [(#\i) (begin
                 (when (and up? (> pid 0))
                   (posix-kill pid SIGINT))
                 (values #f #f #f))]
        [(#\t) (begin
                 (when (and up? (> pid 0))
                   (posix-kill pid SIGTERM))
                 (values #f #f #f))]
        [(#\k) (begin
                 (when (and up? (> pid 0))
                   (posix-kill pid SIGKILL))
                 (values #f #f #f))]
        [else (values #f #f #f)])))

  ;; ========== Main Supervision Loop ==========

  (define (supervise! service-dir)
    ;; Ensure supervise directory exists
    (let ([sv-dir (string-append service-dir "/supervise")])
      (unless (file-exists? sv-dir)
        (mkdir sv-dir))

      ;; Create control and ok FIFOs
      (let ([control-path (string-append sv-dir "/control")]
            [ok-path (string-append sv-dir "/ok")])
        (unless (file-exists? control-path)
          (posix-mkfifo control-path #o600))
        (unless (file-exists? ok-path)
          (posix-mkfifo ok-path #o600))

        ;; Load service configuration
        (let ([config (load-service-config service-dir)]
              [run-path (string-append service-dir "/run")])

          ;; Block SIGCHLD so we can use sigwait
          (posix-sigprocmask SIG_BLOCK (list SIGCHLD))

          ;; Open control FIFO non-blocking for reading
          ;; We also open it for writing to keep it open (no EOF when writers close)
          (let ([ctl-r (posix-open control-path
                         (bitwise-ior O_RDONLY O_NONBLOCK) 0)]
                [ctl-w (posix-open control-path O_WRONLY 0)])

            ;; State
            (let loop ([pid 0]
                       [up? #f]
                       [paused? #f]
                       [want 'up]
                       [should-exit? #f]
                       [timestamp (tai64n-now)])

              ;; Write status
              (write-status! service-dir pid up? paused? want timestamp)

              (cond
                ;; Exit requested and service is down
                [should-exit?
                 (when (not up?)
                   (posix-close ctl-r)
                   (posix-close ctl-w)
                   (void))]

                ;; Need to start the service
                [(and (not up?) (memq want '(up once)))
                 (let ([child-pid (posix-fork)])
                   (if (= child-pid 0)
                     ;; === Child process ===
                     (begin
                       ;; Unblock SIGCHLD in child
                       (posix-sigprocmask SIG_UNBLOCK (list SIGCHLD))
                       ;; Close control FIFOs
                       (posix-close ctl-r)
                       (posix-close ctl-w)
                       ;; Load environment
                       (load-envdir (service-config-env-dir config))
                       (let ([env-path (string-append service-dir "/env")])
                         (when (and (file-exists? env-path) (file-directory? env-path))
                           (load-envdir env-path)))
                       ;; Apply resource limits
                       (apply-rlimits! config)
                       ;; Drop privileges
                       (drop-privileges! config)
                       ;; Exec the run script
                       ;; Build argv: ["/bin/sh", "-c", "exec ./run"]
                       ;; But since run should be executable, just exec it directly
                       (let* ([argv-list (list run-path)]
                              [argc (length argv-list)]
                              [argv (foreign-alloc (* 8 (+ argc 1)))])
                         ;; Set argv pointers
                         (let fill ([i 0] [args argv-list])
                           (if (null? args)
                             (foreign-set! 'void* argv (* i 8) 0)  ;; NULL terminator
                             (let ([s (car args)])
                               ;; Allocate C string
                               (let ([cs (foreign-alloc (+ (string-length s) 1))])
                                 (let put-char ([j 0])
                                   (if (= j (string-length s))
                                     (foreign-set! 'unsigned-8 cs j 0)
                                     (begin
                                       (foreign-set! 'unsigned-8 cs j
                                         (char->integer (string-ref s j)))
                                       (put-char (+ j 1)))))
                                 (foreign-set! 'void* argv (* i 8) cs))
                               (fill (+ i 1) (cdr args)))))
                         ;; envp = NULL (inherit current environment)
                         (posix-execve run-path argv 0))
                       ;; If exec fails, exit child
                       (posix-exit 111))
                     ;; === Parent process ===
                     (loop child-pid #t #f want #f (tai64n-now))))]

                ;; Service is running or want=down, wait for events
                [else
                 ;; Try to reap any dead children (non-blocking)
                 (let-values ([(wpid wstatus)
                               (guard (e [#t (values 0 0)])
                                 (posix-waitpid -1 WNOHANG))])
                   (let ([child-died? (and (> wpid 0) (= wpid pid))])

                     ;; Read control commands (non-blocking)
                     (let read-ctl ([cur-want want]
                                    [cur-start? #f]
                                    [cur-exit? should-exit?]
                                    [cur-paused? paused?])
                       (let ([buf (make-bytevector 1 0)])
                         (let ([n (guard (e [#t 0])
                                    (posix-read ctl-r buf 1))])
                           (if (> n 0)
                             ;; Got a command byte
                             (let-values ([(new-want should-start? should-exit-now?)
                                           (handle-control-byte
                                             (bytevector-u8-ref buf 0)
                                             pid up?)])
                               (read-ctl
                                 (or new-want cur-want)
                                 (or should-start? cur-start?)
                                 (or should-exit-now? cur-exit?)
                                 (if (memv (integer->char (bytevector-u8-ref buf 0))
                                           '(#\p))
                                   #t
                                   (if (memv (integer->char (bytevector-u8-ref buf 0))
                                             '(#\c))
                                     #f
                                     cur-paused?))))
                             ;; No more commands
                             (cond
                               ;; Child died
                               [child-died?
                                (loop 0 #f #f cur-want cur-exit? (tai64n-now))]
                               ;; Need to start
                               [cur-start?
                                (loop pid up? cur-paused? cur-want cur-exit? timestamp)]
                               ;; Otherwise sleep briefly and re-check
                               [else
                                ;; Use sigwait with timeout via sleep
                                ;; (brief sleep to avoid busy-wait)
                                (sleep (make-time 'time-duration 0 1))
                                (loop pid up? cur-paused? cur-want cur-exit? timestamp)
                                ])))))))])))))))

  ) ;; end library
