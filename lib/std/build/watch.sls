#!chezscheme
;;; (std build watch) — File watcher with incremental compilation support
;;;
;;; Polls files for mtime changes and triggers recompilation callbacks.
;;; Includes dependency graph, dirty tracking, and a simple build system.

(library (std build watch)
  (export
    ;; File watching
    make-watcher
    watcher?
    watcher-add!
    watcher-remove!
    watcher-start!
    watcher-stop!
    watcher-running?
    watcher-watched-paths

    ;; Polling
    *watch-interval-ms*

    ;; File metadata
    file-mtime
    file-changed?

    ;; Dependency graph
    make-dep-graph
    dep-graph?
    dep-graph-add!
    dep-graph-dependents
    dep-graph-dependencies
    dep-graph-topo-sort
    dep-graph-dirty!
    dep-graph-clean!
    dep-graph-dirty?
    dep-graph-dirty-set

    ;; Incremental build system
    make-build-system
    build-system?
    build-system-add-rule!
    build-system-build!
    build-system-build-all!
    build-system-clean!

    ;; Watch + rebuild
    watch-and-build!

    ;; Utilities
    find-scheme-files
    parse-imports
    build-dep-graph-from-dir
    format-build-result)

  (import (chezscheme))

  ;; ========== Watch Interval Parameter ==========

  (define *watch-interval-ms* (make-parameter 500))

  ;; ========== File Metadata ==========

  (define (file-mtime path)
    ;; Returns integer seconds since epoch, or #f if file does not exist.
    (guard (exn [#t #f])
      (let ([t (file-modification-time path)])
        ;; file-modification-time returns a time record; extract seconds
        (time-second t))))

  (define (file-changed? path last-mtime)
    ;; Returns #t if the file's mtime differs from last-mtime.
    (let ([current (file-mtime path)])
      (not (equal? current last-mtime))))

  ;; ========== Watcher ==========

  (define-record-type (%watcher %make-watcher watcher?)
    (fields
      (mutable mtimes)    ;; hashtable: path -> last-mtime
      (mutable callbacks) ;; hashtable: path -> callback procedure
      (mutable running)   ;; boolean
      (mutable thread)))  ;; thread or #f

  (define (make-watcher)
    (%make-watcher
      (make-hashtable equal-hash equal?)
      (make-hashtable equal-hash equal?)
      #f
      #f))

  (define (watcher-add! w path callback)
    ;; Register path for watching; callback called as (callback path) on change.
    (hashtable-set! (%watcher-mtimes w) path (file-mtime path))
    (hashtable-set! (%watcher-callbacks w) path callback))

  (define (watcher-remove! w path)
    (hashtable-delete! (%watcher-mtimes w) path)
    (hashtable-delete! (%watcher-callbacks w) path))

  (define (watcher-watched-paths w)
    (vector->list (hashtable-keys (%watcher-mtimes w))))

  (define (watcher-running? w)
    (%watcher-running w))

  (define (watcher-poll! w)
    ;; Check all watched paths for changes and invoke callbacks.
    (let-values ([(paths mtimes) (hashtable-entries (%watcher-mtimes w))])
      (vector-for-each
        (lambda (path last-mtime)
          (let ([current (file-mtime path)])
            (unless (equal? current last-mtime)
              (hashtable-set! (%watcher-mtimes w) path current)
              (let ([cb (hashtable-ref (%watcher-callbacks w) path #f)])
                (when cb (cb path))))))
        paths mtimes)))

  (define (watcher-start! w)
    ;; Start background polling thread.
    (unless (%watcher-running w)
      (%watcher-running-set! w #t)
      (let ([t (fork-thread
                 (lambda ()
                   (let loop ()
                     (when (%watcher-running w)
                       (guard (exn [#t #f])
                         (watcher-poll! w))
                       (sleep (make-time 'time-duration
                                (* (*watch-interval-ms*) 1000000)
                                0))
                       (loop)))))])
        (%watcher-thread-set! w t))))

  (define (watcher-stop! w)
    (%watcher-running-set! w #f))

  ;; ========== Dependency Graph ==========

  (define-record-type (%dep-graph %make-dep-graph dep-graph?)
    (fields
      (mutable deps)       ;; hashtable: file -> list of files it depends on
      (mutable dependents) ;; hashtable: file -> list of files that depend on it
      (mutable dirty)))    ;; hashtable: file -> #t

  (define (make-dep-graph)
    (%make-dep-graph
      (make-hashtable equal-hash equal?)
      (make-hashtable equal-hash equal?)
      (make-hashtable equal-hash equal?)))

  (define (dep-graph-add! graph file . deps)
    ;; Record that file depends on each dep.
    (hashtable-set! (%dep-graph-deps graph) file deps)
    (for-each
      (lambda (dep)
        (let ([existing (hashtable-ref (%dep-graph-dependents graph) dep '())])
          (unless (member file existing)
            (hashtable-set! (%dep-graph-dependents graph) dep (cons file existing)))))
      deps))

  (define (dep-graph-dependents graph file)
    (hashtable-ref (%dep-graph-dependents graph) file '()))

  (define (dep-graph-dependencies graph file)
    (hashtable-ref (%dep-graph-deps graph) file '()))

  (define (dep-graph-dirty! graph file)
    ;; Mark file dirty and propagate to all dependents recursively.
    (unless (hashtable-ref (%dep-graph-dirty graph) file #f)
      (hashtable-set! (%dep-graph-dirty graph) file #t)
      (for-each
        (lambda (dep) (dep-graph-dirty! graph dep))
        (dep-graph-dependents graph file))))

  (define (dep-graph-clean! graph file)
    (hashtable-delete! (%dep-graph-dirty graph) file))

  (define (dep-graph-dirty? graph file)
    (hashtable-ref (%dep-graph-dirty graph) file #f))

  (define (dep-graph-dirty-set graph)
    (vector->list (hashtable-keys (%dep-graph-dirty graph))))

  (define (dep-graph-topo-sort graph)
    ;; Kahn's algorithm: BFS from nodes with no (known) dependencies.
    ;; Returns list of all nodes in topological order.
    (let* ([all-deps   (%dep-graph-deps graph)]
           [all-depnts (%dep-graph-dependents graph)]
           [in-degree  (make-hashtable equal-hash equal?)]
           [all-nodes  '()])

      ;; Collect all nodes
      (let-values ([(ks vs) (hashtable-entries all-deps)])
        (vector-for-each
          (lambda (k deps-list)
            (unless (member k all-nodes)
              (set! all-nodes (cons k all-nodes)))
            (hashtable-set! in-degree k
              (+ (hashtable-ref in-degree k 0) (length deps-list)))
            (for-each
              (lambda (d)
                (unless (member d all-nodes)
                  (set! all-nodes (cons d all-nodes)))
                (unless (hashtable-ref in-degree d #f)
                  (hashtable-set! in-degree d 0)))
              deps-list))
          ks vs))

      ;; Initialize queue with zero-in-degree nodes
      (let ([queue (filter (lambda (n) (= (hashtable-ref in-degree n 0) 0))
                           all-nodes)]
            [sorted '()])
        (let loop ([q queue])
          (if (null? q)
              (reverse sorted)
              (let ([node (car q)]
                    [rest (cdr q)])
                (set! sorted (cons node sorted))
                (let ([deps-of-node (dep-graph-dependents graph node)]
                      [new-queue rest])
                  (let ([new-q
                         (fold-left
                           (lambda (acc dep)
                             (let ([new-deg (- (hashtable-ref in-degree dep 0) 1)])
                               (hashtable-set! in-degree dep new-deg)
                               (if (= new-deg 0)
                                   (append acc (list dep))
                                   acc)))
                           new-queue
                           deps-of-node)])
                    (loop new-q)))))))))

  ;; ========== Build System ==========

  ;; A rule is: (target deps build-fn)
  (define-record-type (%build-system %make-build-system build-system?)
    (fields
      (mutable rules)  ;; hashtable: target -> (deps build-fn)
      (mutable graph)  ;; dep-graph
      (mutable mtimes)));; hashtable: target -> last-mtime

  (define (make-build-system)
    (%make-build-system
      (make-hashtable equal-hash equal?)
      (make-dep-graph)
      (make-hashtable equal-hash equal?)))

  (define (build-system-add-rule! bs target deps build-fn)
    (hashtable-set! (%build-system-rules bs) target (cons deps build-fn))
    (apply dep-graph-add! (%build-system-graph bs) target deps))

  (define (build-system-build! bs target)
    ;; Build target only if it or any dependency is dirty/stale.
    (let ([rule (hashtable-ref (%build-system-rules bs) target #f)])
      (if (not rule)
          (list 'error target "no rule")
          (let* ([deps     (car rule)]
                 [build-fn (cdr rule)]
                 [target-mtime (hashtable-ref (%build-system-mtimes bs) target #f)]
                 [needs-build?
                  (or (not target-mtime)
                      (dep-graph-dirty? (%build-system-graph bs) target)
                      (any (lambda (dep)
                             (let ([dm (file-mtime dep)])
                               (and dm target-mtime (> dm target-mtime))))
                           deps))])
            (if needs-build?
                (let ([result
                       (guard (exn [#t (list 'error target
                                         (if (message-condition? exn)
                                             (condition-message exn)
                                             (format "~a" exn)))])
                         (build-fn target deps)
                         (list 'ok target))])
                  (when (eq? (car result) 'ok)
                    (hashtable-set! (%build-system-mtimes bs) target
                      (time-second (current-time)))
                    (dep-graph-clean! (%build-system-graph bs) target))
                  result)
                (list 'skip target))))))

  (define (any pred lst)
    (cond [(null? lst) #f]
          [(pred (car lst)) #t]
          [else (any pred (cdr lst))]))

  (define (build-system-build-all! bs)
    ;; Rebuild everything in topological order.
    (let* ([graph (%build-system-graph bs)]
           [order (dep-graph-topo-sort graph)])
      (map (lambda (target)
             (when (hashtable-ref (%build-system-rules bs) target #f)
               (let ([rule (hashtable-ref (%build-system-rules bs) target #f)])
                 (when rule
                   (dep-graph-dirty! graph target)))))
           order)
      (map (lambda (target)
             (if (hashtable-ref (%build-system-rules bs) target #f)
                 (build-system-build! bs target)
                 #f))
           order)))

  (define (build-system-clean! bs)
    ;; Mark all targets dirty.
    (let-values ([(targets _) (hashtable-entries (%build-system-rules bs))])
      (vector-for-each
        (lambda (t) (dep-graph-dirty! (%build-system-graph bs) t))
        targets)))

  ;; ========== Watch + Build ==========

  (define (watch-and-build! bs paths)
    ;; Run forever: watch paths, rebuild dirty targets on change.
    ;; Returns only when interrupted (or never in normal use).
    (let ([w (make-watcher)])
      (for-each
        (lambda (path)
          (watcher-add! w path
            (lambda (changed-path)
              (dep-graph-dirty! (%build-system-graph bs) changed-path)
              (let-values ([(targets _) (hashtable-entries (%build-system-rules bs))])
                (vector-for-each
                  (lambda (t) (build-system-build! bs t))
                  targets)))))
        paths)
      (watcher-start! w)
      w))

  ;; ========== Utilities ==========

  (define (find-scheme-files dir)
    ;; Return list of .sls and .ss files under dir.
    ;; Each subdirectory is guarded independently to handle permission errors.
    (let ([result '()])
      (let scan ([d dir])
        (guard (exn [#t #f])  ;; skip unreadable directories
          (for-each
            (lambda (entry)
              (let ([full (string-append d "/" entry)])
                (cond
                  [(guard (e [#t #f]) (file-directory? full))
                   (scan full)]
                  [(or (string-suffix? ".sls" entry)
                       (string-suffix? ".ss"  entry))
                   (set! result (cons full result))])))
            (directory-list d))))
      (reverse result)))

  (define (string-suffix? suffix str)
    (let ([sl (string-length suffix)]
          [sl2 (string-length str)])
      (and (>= sl2 sl)
           (string=? (substring str (- sl2 sl) sl2) suffix))))

  (define (parse-imports file)
    ;; Read the file and collect all (import ...) library specs.
    (guard (exn [#t '()])
      (call-with-input-file file
        (lambda (port)
          (let loop ([imports '()])
            (let ([form (read port)])
              (cond
                [(eof-object? form) (reverse imports)]
                [(and (pair? form) (eq? (car form) 'import))
                 (loop (append (reverse (cdr form)) imports))]
                [(and (pair? form) (or (eq? (car form) 'library)
                                       (eq? (car form) 'program)))
                 ;; Scan inside library/program body
                 (let inner ([body (cddr form)] [imps imports])
                   (cond
                     [(null? body) (loop imps)]
                     [(and (pair? (car body)) (eq? (caar body) 'import))
                      (inner (cdr body)
                             (append (reverse (cdar body)) imps))]
                     [else (inner (cdr body) imps)]))]
                [else (loop imports)])))))))

  (define (build-dep-graph-from-dir dir)
    ;; Build a dependency graph from Scheme files in dir.
    ;; Edges go from each file to files that provide its imports
    ;; (simplified: just extract import spec names as strings).
    (let ([graph (make-dep-graph)]
          [files (find-scheme-files dir)])
      (for-each
        (lambda (file)
          (let ([imports (parse-imports file)])
            (apply dep-graph-add! graph file
                   (map (lambda (spec)
                          (if (pair? spec)
                              (format "~a" spec)
                              (format "~a" spec)))
                        imports))))
        files)
      graph))

  (define (format-build-result result)
    ;; Human-readable string for a build result.
    (cond
      [(not result) "skipped (no rule)"]
      [(eq? (car result) 'ok)
       (format "ok: ~a" (cadr result))]
      [(eq? (car result) 'skip)
       (format "skip: ~a (up to date)" (cadr result))]
      [(eq? (car result) 'error)
       (format "error: ~a — ~a" (cadr result) (caddr result))]
      [else (format "~a" result)]))

) ;; end library
