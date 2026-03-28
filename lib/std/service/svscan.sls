#!chezscheme
;;; (std service svscan) — Service directory scanner
;;;
;;; Scans a directory for service subdirectories, spawns supervise
;;; for each one. Rescans every 5 seconds. Sets up log pipes
;;; between services and their log/ subdirectories.

(library (std service svscan)
  (export svscan!)

  (import
    (chezscheme)
    (std os posix)
    (std service supervise))

  ;; ========== Service Tracking ==========
  ;; Track services by (dev . ino) to handle renames correctly.

  (define-record-type tracked-service
    (fields
      name       ;; string (directory name)
      dev        ;; integer (device number)
      ino        ;; integer (inode number)
      pid        ;; integer (supervise process PID)
      log-pid    ;; integer or #f (log supervise PID)
    )
    (nongenerative tracked-service))

  ;; ========== Service Discovery ==========

  (define (scan-service-dirs scan-dir)
    ;; Returns list of (name dev ino has-log?) for each service subdirectory
    (let ([entries (directory-list scan-dir)])
      (filter values
        (map (lambda (name)
               (let ([path (string-append scan-dir "/" name)])
                 (guard (e [#t #f])
                   (let ([st (posix-stat path)])
                     (let ([dev (stat-dev st)]
                           [ino (stat-ino st)]
                           [is-dir? (stat-is-directory? st)])
                       (free-stat st)
                       (and is-dir?
                            ;; Skip hidden dirs and supervise dirs
                            (not (char=? (string-ref name 0) #\.))
                            (not (string=? name "supervise"))
                            ;; Must have a run script
                            (file-exists? (string-append path "/run"))
                            (let ([has-log? (and (file-exists?
                                                   (string-append path "/log"))
                                                 (file-exists?
                                                   (string-append path "/log/run")))])
                              (list name dev ino has-log?))))))))
             entries))))

  ;; ========== Spawning ==========

  (define (spawn-supervise! scan-dir name log-pipe-read-fd)
    ;; Fork a child that runs supervise! for the service
    (let ([service-dir (string-append scan-dir "/" name)]
          [pid (posix-fork)])
      (cond
        [(= pid 0)
         ;; Child: redirect stdin from log pipe if provided
         (when log-pipe-read-fd
           (posix-dup2 log-pipe-read-fd 0)
           (posix-close log-pipe-read-fd))
         ;; Run supervise (does not return)
         (guard (e [#t (posix-exit 111)])
           (supervise! service-dir))
         (posix-exit 0)]
        [else pid])))

  (define (start-service! scan-dir name has-log?)
    ;; Start supervise for a service, optionally with log pipe
    (if has-log?
      ;; Create pipe: service stdout → log stdin
      (let-values ([(pipe-r pipe-w) (posix-pipe)])
        (let* ([log-dir (string-append scan-dir "/" name "/log")]
               ;; Start log supervise first (reads from pipe)
               [log-pid (let ([p (posix-fork)])
                          (cond
                            [(= p 0)
                             (posix-close pipe-w)
                             (posix-dup2 pipe-r 0)
                             (posix-close pipe-r)
                             (guard (e [#t (posix-exit 111)])
                               (supervise! log-dir))
                             (posix-exit 0)]
                            [else p]))]
               ;; Start service supervise (writes to pipe)
               [svc-pid (let ([p (posix-fork)])
                          (cond
                            [(= p 0)
                             (posix-close pipe-r)
                             (posix-dup2 pipe-w 1)
                             (posix-close pipe-w)
                             (guard (e [#t (posix-exit 111)])
                               (supervise! (string-append scan-dir "/" name)))
                             (posix-exit 0)]
                            [else p]))])
          ;; Parent closes both ends of pipe
          (posix-close pipe-r)
          (posix-close pipe-w)
          (values svc-pid log-pid)))
      ;; No log — just start service
      (let ([svc-pid (spawn-supervise! scan-dir name #f)])
        (values svc-pid #f))))

  ;; ========== Main Scanner Loop ==========

  (define (svscan! scan-dir)
    ;; Block SIGCHLD for cleanup
    (posix-sigprocmask SIG_BLOCK (list SIGCHLD))

    (let loop ([services '()])
      ;; Reap any dead children (non-blocking)
      (let reap ()
        (let-values ([(pid status)
                      (guard (e [#t (values 0 0)])
                        (posix-waitpid -1 WNOHANG))])
          (when (> pid 0)
            ;; Remove from tracked list
            (set! services
              (filter (lambda (s)
                        (and (not (= (tracked-service-pid s) pid))
                             (or (not (tracked-service-log-pid s))
                                 (not (= (tracked-service-log-pid s) pid)))))
                      services))
            (reap))))

      ;; Scan for services
      (let ([found (scan-service-dirs scan-dir)])
        ;; Find new services (not already tracked)
        (let ([tracked-keys (map (lambda (s)
                                   (cons (tracked-service-dev s)
                                         (tracked-service-ino s)))
                                 services)])
          (for-each
            (lambda (entry)
              (let ([name (car entry)]
                    [dev (cadr entry)]
                    [ino (caddr entry)]
                    [has-log? (cadddr entry)])
                (unless (member (cons dev ino) tracked-keys)
                  ;; New service — start it
                  (let-values ([(svc-pid log-pid) (start-service! scan-dir name has-log?)])
                    (set! services
                      (cons (make-tracked-service name dev ino svc-pid log-pid)
                            services))))))
            found)))

      ;; Sleep 5 seconds, then rescan
      (sleep (make-time 'time-duration 0 5))
      (loop services)))

  ) ;; end library
