#!chezscheme
;;; (std dev reload) — Hot Code Reloading (Step 31)
;;;
;;; Reload individual library modules without restarting the process.
;;; Tracks module file locations, modification times, and dependents.
;;; Sends 'code-change notifications to registered actors/callbacks.

(library (std dev reload)
  (export
    ;; Module registry
    register-module!
    unregister-module!
    module-registered?
    registered-modules

    ;; Hot reload
    reload!
    reload-if-changed!
    watch-and-reload!
    stop-watching!

    ;; Change notifications
    on-module-change
    off-module-change
    notify-change!

    ;; Dependency tracking
    module-dependents
    module-file
    module-mtime)

  (import (chezscheme))

  ;; ========== Module Registry ==========

  ;; module-info: (name file-path mtime load-proc)
  (define *modules*      (make-eq-hashtable))   ;; name → module-info
  (define *modules-mutex* (make-mutex))

  ;; change handlers: name → list of (handler-id . proc)
  (define *change-handlers* (make-eq-hashtable))
  (define *handler-id* 0)

  ;; dependents: name → list of dependent names
  (define *dependents* (make-eq-hashtable))

  (define (make-module-info name file mtime load-proc)
    (list name file mtime load-proc))
  (define (minfo-name m)  (list-ref m 0))
  (define (minfo-file m)  (list-ref m 1))
  (define (minfo-mtime m) (list-ref m 2))
  (define (minfo-proc m)  (list-ref m 3))

  (define (register-module! name file-path load-proc . deps)
    ;; Register a module for hot-reload tracking.
    ;; file-path: path to the .sls source file
    ;; load-proc: thunk that (re)loads the module
    ;; deps: list of module names this module depends on
    (let ([mtime (if (file-exists? file-path)
                     (file-modification-time file-path)
                     0)])
      (with-mutex *modules-mutex*
        (hashtable-set! *modules* name
          (make-module-info name file-path mtime load-proc))
        ;; Register as dependent of each dep
        (for-each
          (lambda (dep)
            (let ([current (hashtable-ref *dependents* dep '())])
              (unless (memq name current)
                (hashtable-set! *dependents* dep (cons name current)))))
          deps))))

  (define (unregister-module! name)
    (with-mutex *modules-mutex*
      (hashtable-delete! *modules* name)
      (hashtable-delete! *change-handlers* name)))

  (define (module-registered? name)
    (with-mutex *modules-mutex*
      (and (hashtable-ref *modules* name #f) #t)))

  (define (registered-modules)
    (with-mutex *modules-mutex*
      (let-values ([(keys _) (hashtable-entries *modules*)])
        (vector->list keys))))

  (define (module-file name)
    (let ([m (hashtable-ref *modules* name #f)])
      (and m (minfo-file m))))

  (define (module-mtime name)
    (let ([m (hashtable-ref *modules* name #f)])
      (and m (minfo-mtime m))))

  (define (module-dependents name)
    (hashtable-ref *dependents* name '()))

  ;; ========== Reload ==========

  (define (reload! name)
    ;; Force reload a registered module.
    ;; Returns #t on success, raises error on failure.
    (let ([m (with-mutex *modules-mutex*
               (hashtable-ref *modules* name #f))])
      (unless m
        (error 'reload! "module not registered" name))
      ;; Execute the load procedure
      (guard (exn [#t (raise exn)])
        ((minfo-proc m))
        ;; Update mtime
        (let ([new-mtime (if (file-exists? (minfo-file m))
                              (file-modification-time (minfo-file m))
                              (minfo-mtime m))])
          (with-mutex *modules-mutex*
            (hashtable-set! *modules* name
              (make-module-info name (minfo-file m) new-mtime (minfo-proc m)))))
        ;; Notify change handlers
        (notify-change! name)
        ;; Cascade to dependents
        (for-each
          (lambda (dep)
            (when (module-registered? dep)
              (reload! dep)))
          (module-dependents name))
        #t)))

  (define (reload-if-changed! name)
    ;; Reload only if file has been modified since last load.
    ;; Returns #t if reloaded, #f if unchanged.
    (let ([m (with-mutex *modules-mutex*
               (hashtable-ref *modules* name #f))])
      (if (not m)
        #f
        (let ([current-mtime
               (if (file-exists? (minfo-file m))
                 (file-modification-time (minfo-file m))
                 (minfo-mtime m))])
          (if (> current-mtime (minfo-mtime m))
            (begin (reload! name) #t)
            #f)))))

  ;; ========== File Watching ==========

  (define *watch-threads* (make-eq-hashtable))
  (define *watch-mutex*   (make-mutex))

  (define (watch-and-reload! . module-names)
    ;; Start a background thread that polls for file changes.
    ;; Returns a watch-id that can be used with stop-watching!.
    (let* ([watch-id (gensym "watch")]
           [worker
            (lambda ()
              (let loop ()
                (sleep (make-time 'time-duration 500000000 0))
                (for-each
                  (lambda (name)
                    (guard (exn [#t (void)])
                      (reload-if-changed! name)))
                  module-names)
                (when (with-mutex *watch-mutex*
                        (hashtable-ref *watch-threads* watch-id #f))
                  (loop))))]
           [t (fork-thread worker)])
      (with-mutex *watch-mutex*
        (hashtable-set! *watch-threads* watch-id t))
      watch-id))

  (define (stop-watching! watch-id)
    (with-mutex *watch-mutex*
      (hashtable-delete! *watch-threads* watch-id)))

  ;; ========== Change Notifications ==========

  (define (on-module-change name handler)
    ;; Register a handler called when module name is reloaded.
    ;; Returns handler-id for removal with off-module-change.
    (set! *handler-id* (+ *handler-id* 1))
    (let ([hid *handler-id*])
      (let ([current (hashtable-ref *change-handlers* name '())])
        (hashtable-set! *change-handlers* name
          (cons (cons hid handler) current)))
      hid))

  (define (off-module-change name handler-id)
    (let ([current (hashtable-ref *change-handlers* name '())])
      (hashtable-set! *change-handlers* name
        (filter (lambda (h) (not (= (car h) handler-id))) current))))

  (define (notify-change! name)
    (let ([handlers (hashtable-ref *change-handlers* name '())])
      (for-each
        (lambda (h)
          (guard (exn [#t (void)])
            ((cdr h) name)))
        handlers)))

  ) ;; end library
