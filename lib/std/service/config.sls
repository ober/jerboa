#!chezscheme
;;; (std service config) — Service configuration for daemontools-style supervision
;;;
;;; Parses optional config.scm files from service directories specifying
;;; sandbox rules, resource limits, user/group identity, and environment.

(library (std service config)
  (export
    make-service-config service-config?
    service-config-user service-config-group
    service-config-memory-limit service-config-file-limit
    service-config-nofile-limit service-config-nproc-limit
    service-config-env-dir
    service-config-sandbox-read service-config-sandbox-write
    service-config-sandbox-exec
    service-config-seccomp?
    default-service-config
    load-service-config)

  (import (chezscheme))

  ;; Service configuration record
  (define-record-type service-config
    (fields
      user              ;; string or #f (username to setuid to)
      group             ;; string or #f (group to setgid to)
      memory-limit      ;; integer or #f (RLIMIT_AS in bytes)
      file-limit        ;; integer or #f (RLIMIT_FSIZE in bytes)
      nofile-limit      ;; integer or #f (RLIMIT_NOFILE count)
      nproc-limit       ;; integer or #f (RLIMIT_NPROC count)
      env-dir           ;; string or #f (path to envdir-style directory)
      sandbox-read      ;; list of strings (read-only paths)
      sandbox-write     ;; list of strings (read-write paths)
      sandbox-exec      ;; list of strings (executable paths)
      seccomp?          ;; boolean (apply default seccomp filter)
    )
    (nongenerative service-config))

  (define default-service-config
    (make-service-config
      #f    ;; user
      #f    ;; group
      #f    ;; memory-limit
      #f    ;; file-limit
      #f    ;; nofile-limit
      #f    ;; nproc-limit
      #f    ;; env-dir
      '()   ;; sandbox-read
      '()   ;; sandbox-write
      '()   ;; sandbox-exec
      #f))  ;; seccomp?

  ;; Load service configuration from config.scm in service directory
  ;; Format: alist, e.g.:
  ;;   ((user . "dns")
  ;;    (group . "dns")
  ;;    (memory-limit . 67108864)
  ;;    (sandbox-read . ("/etc/dns"))
  ;;    (seccomp . #t))
  (define (load-service-config service-dir)
    (let ([config-path (string-append service-dir "/config.scm")])
      (if (file-exists? config-path)
        (guard (e [#t default-service-config])
          (let ([alist (call-with-input-file config-path read)])
            (if (list? alist)
              (parse-config-alist alist)
              default-service-config)))
        default-service-config)))

  (define (alist-ref alist key default)
    (let ([pair (assq key alist)])
      (if pair (cdr pair) default)))

  (define (parse-config-alist alist)
    (make-service-config
      (alist-ref alist 'user #f)
      (alist-ref alist 'group #f)
      (alist-ref alist 'memory-limit #f)
      (alist-ref alist 'file-limit #f)
      (alist-ref alist 'nofile-limit #f)
      (alist-ref alist 'nproc-limit #f)
      (alist-ref alist 'env-dir #f)
      (alist-ref alist 'sandbox-read '())
      (alist-ref alist 'sandbox-write '())
      (alist-ref alist 'sandbox-exec '())
      (alist-ref alist 'seccomp #f)))

  ) ;; end library
