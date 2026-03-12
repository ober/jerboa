#!chezscheme
;;; Tests for (std build watch) — File Watcher and Incremental Build System

(import (chezscheme) (std build watch))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(printf "--- (std build watch) tests ---~%")

;;; ======== Watch Interval Parameter ========

(printf "~%-- Watch Interval --~%")

(test "*watch-interval-ms* default"
  (*watch-interval-ms*)
  500)

(test "*watch-interval-ms* parameterize"
  (parameterize ([*watch-interval-ms* 200])
    (*watch-interval-ms*))
  200)

;;; ======== File Metadata ========

(printf "~%-- File Metadata --~%")

(let ([f "/tmp/jerboa-watch-test-mtime.txt"])
  (call-with-output-file f
    (lambda (p) (display "hello" p))
    'replace)

  (test "file-mtime returns integer"
    (integer? (file-mtime f))
    #t)

  (test "file-mtime positive"
    (> (file-mtime f) 0)
    #t)

  (test "file-mtime non-existent returns #f"
    (file-mtime "/nonexistent/path/xyz")
    #f)

  (let ([mtime (file-mtime f)])
    (test "file-changed? false same mtime"
      (file-changed? f mtime)
      #f)

    (test "file-changed? true for wrong mtime"
      (file-changed? f 0)
      #t))

  (delete-file f))

;;; ======== Watcher ========

(printf "~%-- Watcher --~%")

(let ([w (make-watcher)])
  (test "make-watcher returns watcher"
    (watcher? w)
    #t)

  (test "watcher? false for non-watcher"
    (watcher? "not a watcher")
    #f)

  (test "watcher-running? initially #f"
    (watcher-running? w)
    #f)

  (test "watcher-watched-paths initially empty"
    (null? (watcher-watched-paths w))
    #t)

  (let ([f "/tmp/jerboa-watch-test-add.txt"])
    (call-with-output-file f (lambda (p) (display "x" p)) 'replace)

    (watcher-add! w f (lambda (path) 'changed))

    (test "watcher-watched-paths after add"
      (member f (watcher-watched-paths w))
      (list f))

    (watcher-remove! w f)

    (test "watcher-watched-paths after remove"
      (null? (watcher-watched-paths w))
      #t)

    (delete-file f)))

(test "watcher-start! and stop!"
  (let ([w (make-watcher)])
    (watcher-start! w)
    (let ([running (watcher-running? w)])
      (watcher-stop! w)
      running))
  #t)

;;; ======== Dependency Graph ========

(printf "~%-- Dependency Graph --~%")

(let ([g (make-dep-graph)])
  (test "make-dep-graph returns dep-graph"
    (dep-graph? g)
    #t)

  (test "dep-graph? false for non-graph"
    (dep-graph? '())
    #f)

  (dep-graph-add! g "a.ss" "b.ss" "c.ss")
  (dep-graph-add! g "b.ss" "c.ss")

  (test "dep-graph-dependencies for a.ss"
    (equal? (dep-graph-dependencies g "a.ss") '("b.ss" "c.ss"))
    #t)

  (test "dep-graph-dependencies for b.ss"
    (dep-graph-dependencies g "b.ss")
    '("c.ss"))

  (test "dep-graph-dependencies unknown file"
    (dep-graph-dependencies g "unknown.ss")
    '())

  (test "dep-graph-dependents of c.ss includes a.ss and b.ss"
    (let ([deps (dep-graph-dependents g "c.ss")])
      (and (member "a.ss" deps) (member "b.ss" deps) #t))
    #t)

  (test "dep-graph-dirty? initially #f"
    (dep-graph-dirty? g "a.ss")
    #f)

  (dep-graph-dirty! g "c.ss")

  (test "dep-graph-dirty? after dirty! on c.ss"
    (dep-graph-dirty? g "c.ss")
    #t)

  (test "dep-graph-dirty? propagates to a.ss"
    (dep-graph-dirty? g "a.ss")
    #t)

  (test "dep-graph-dirty? propagates to b.ss"
    (dep-graph-dirty? g "b.ss")
    #t)

  (test "dep-graph-dirty-set contains dirty files"
    (let ([dirty (dep-graph-dirty-set g)])
      (and (member "a.ss" dirty) (member "b.ss" dirty) (member "c.ss" dirty) #t))
    #t)

  (dep-graph-clean! g "c.ss")

  (test "dep-graph-dirty? after clean! on c.ss"
    (dep-graph-dirty? g "c.ss")
    #f))

(define (list-index lst item)
  (let loop ([l lst] [i 0])
    (cond
      [(null? l) #f]
      [(equal? (car l) item) i]
      [else (loop (cdr l) (+ i 1))])))

;;; ======== Topological Sort ========

(printf "~%-- Topological Sort --~%")

(let ([g (make-dep-graph)])
  (dep-graph-add! g "main.ss" "lib.ss")
  (dep-graph-add! g "lib.ss" "util.ss")

  (let ([order (dep-graph-topo-sort g)])
    (test "topo-sort returns list"
      (list? order)
      #t)

    (test "topo-sort: util.ss before lib.ss"
      (let ([ui (list-index order "util.ss")]
            [li (list-index order "lib.ss")])
        (and ui li (< ui li)))
      #t)

    (test "topo-sort: lib.ss before main.ss"
      (let ([li (list-index order "lib.ss")]
            [mi (list-index order "main.ss")])
        (and li mi (< li mi)))
      #t)))

;;; ======== Build System ========

(printf "~%-- Build System --~%")

(let ([bs (make-build-system)])
  (test "make-build-system returns build-system"
    (build-system? bs)
    #t)

  (test "build-system? false for non-system"
    (build-system? "nope")
    #f)

  (let ([built '()])
    (build-system-add-rule! bs "output.o" '() (lambda (target deps)
                                                  (set! built (cons target built))))
    (let ([result (build-system-build! bs "output.o")])
      (test "build-system-build! returns list"
        (list? result)
        #t)

      (test "build-system-build! ok result"
        (eq? (car result) 'ok)
        #t)

      (test "build-system-build! ran the build fn"
        (member "output.o" built)
        (list "output.o")))

    (let ([result2 (build-system-build! bs "output.o")])
      (test "build-system-build! skips if up to date"
        (eq? (car result2) 'skip)
        #t)))

  (let ([result (build-system-build! bs "no-rule")])
    (test "build-system-build! error for unknown target"
      (eq? (car result) 'error)
      #t)))

;;; ======== format-build-result ========

(printf "~%-- format-build-result --~%")

(test "format-build-result ok"
  (string? (format-build-result '(ok "target.o")))
  #t)

(test "format-build-result skip"
  (let ([s (format-build-result '(skip "target.o"))])
    (and (string? s) (> (string-length s) 0)))
  #t)

(test "format-build-result error"
  (let ([s (format-build-result '(error "target.o" "compile failed"))])
    (and (string? s) (> (string-length s) 0)))
  #t)

(test "format-build-result #f"
  (string? (format-build-result #f))
  #t)

;;; ======== Utilities ========

(printf "~%-- Utilities --~%")

(let* ([dir "/tmp/jerboa-fss-find-test"]
       [f   (string-append dir "/watch-test.sls")])
  (system (string-append "mkdir -p " dir))
  (call-with-output-file f
    (lambda (p)
      (display "(library (test) (export x) (import (chezscheme)) (define x 1))" p))
    'replace)

  (test "find-scheme-files finds .sls"
    (member f (find-scheme-files dir))
    (list f))

  (test "parse-imports finds library imports"
    (list? (parse-imports f))
    #t)

  (delete-file f)
  (system (string-append "rmdir " dir)))

(test "find-scheme-files on nonexistent dir"
  (null? (find-scheme-files "/nonexistent/path"))
  #t)

(test "parse-imports on nonexistent file"
  (null? (parse-imports "/nonexistent.ss"))
  #t)

(let ([dir "/tmp/jerboa-watch-depgraph-test"])
  (guard (exn [#t #f]) (system (string-append "mkdir -p " dir)))
  (let ([f1 (string-append dir "/a.sls")]
        [f2 (string-append dir "/b.sls")])
    (call-with-output-file f1
      (lambda (p) (display "(library (a) (export x) (import (chezscheme) (b)) (define x 1))" p))
      'replace)
    (call-with-output-file f2
      (lambda (p) (display "(library (b) (export y) (import (chezscheme)) (define y 2))" p))
      'replace)

    (let ([g (build-dep-graph-from-dir dir)])
      (test "build-dep-graph-from-dir returns dep-graph"
        (dep-graph? g)
        #t))

    (delete-file f1)
    (delete-file f2))
  (guard (exn [#t #f]) (system (string-append "rm -rf " dir))))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
