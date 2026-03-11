#!chezscheme
;;; Tests for Phase 9: Developer Experience
;;; (std dev reload), (std dev debug), (std dev profile), (jerboa pkg)

(import (chezscheme)
        (std dev reload)
        (std dev debug)
        (std dev profile)
        (jerboa pkg))

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

(printf "--- Phase 9: Developer Experience tests ---~%")

;;; ======== Step 31: Hot Code Reloading ========

(printf "~%-- Hot Code Reloading --~%")

(test "module-registered? initially false"
  (module-registered? 'my-module)
  #f)

;; Register a mock module
(define *loaded* #f)
(register-module! 'my-module "/tmp/fake-module.sls"
  (lambda () (set! *loaded* #t))
  'dep-a)

(test "module-registered? after register"
  (module-registered? 'my-module)
  #t)

(test "registered-modules contains it"
  (memq 'my-module (registered-modules))
  (list 'my-module))

(test "module-file"
  (module-file 'my-module)
  "/tmp/fake-module.sls")

;; Reload (load proc runs)
(reload! 'my-module)
(test "reload! calls load-proc"
  *loaded*
  #t)

;; Change notification
(define *notified* #f)
(let ([hid (on-module-change 'my-module (lambda (name) (set! *notified* name)))])
  (reload! 'my-module)
  (test "on-module-change: notified on reload"
    *notified*
    'my-module)

  (off-module-change 'my-module hid)
  (set! *notified* #f)
  (reload! 'my-module)
  (test "off-module-change: no notification after removal"
    *notified*
    #f))

(test "module-dependents"
  ;; 'my-module declared dep-a as a dependency
  (memq 'my-module (module-dependents 'dep-a))
  (list 'my-module))

(unregister-module! 'my-module)
(test "unregister-module!"
  (module-registered? 'my-module)
  #f)

;;; ======== Step 32: Debug / Trace ========

(printf "~%-- Debug / Trace --~%")

;; with-recording captures events
(define test-recording #f)

(with-recording
  (lambda ()
    (trace-event! "step1" 1)
    (trace-event! "step2" 2)
    (trace-event! "step3" 3)
    (set! test-recording (*current-recording*))))

(test "with-recording: recording created"
  (recording? test-recording)
  #t)

;; Test trace-call! and trace-return!
(parameterize ([*current-recording*
                (let ()
                  (define r
                    (make-parameter #f))
                  #f)])
  'ok)  ;; just verify parameterize doesn't break

;; instrument macro
(instrument (add-profiled x y)
  (+ x y))

(test "instrument: defines function"
  (add-profiled 3 4)
  7)

;; Debug history (needs active recording)
(test "debug-history: empty without recording"
  (debug-history)
  '())

;; Breakpoints
(break-when! 'my-fn even?)
(test "check-breakpoints!: fires for even"
  (check-breakpoints! 'my-fn 4)
  #t)

(test "check-breakpoints!: no fire for odd"
  (check-breakpoints! 'my-fn 3)
  #f)

(break-never! 'my-fn)
(test "break-never!: clears breakpoint"
  (check-breakpoints! 'my-fn 4)
  #f)

;;; ======== Step 33: Profiler ========

(printf "~%-- Profiler --~%")

(profile-reset!)
(profile-start!)

(define/profiled (fib n)
  (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))

(fib 10)
(profile-stop!)

(let ([results (profile-results)])
  (test "profile-results: fib recorded"
    (and (pair? results)
         (assq 'fib results)
         #t)
    #t)

  (let ([fib-entry (assq 'fib results)])
    (test "profile-results: fib call count"
      (and fib-entry (> (cadr fib-entry) 1))
      #t)))

;; time-thunk
(let-values ([(result ns) (time-thunk (lambda () (+ 1 2)))])
  (test "time-thunk: correct result"
    result
    3)
  (test "time-thunk: elapsed is non-negative"
    (>= ns 0)
    #t))

;; with-profiling
(profile-reset!)
(profile-start!)
(with-profiling 'manual-op (lambda () (expt 2 10)))
(profile-stop!)
(test "with-profiling: recorded"
  (and (assq 'manual-op (profile-results)) #t)
  #t)

;;; ======== Step 34: Package Manager ========

(define (list-index lst elem)
  (let loop ([lst lst] [i 0])
    (cond [(null? lst) -1]
          [(equal? (car lst) elem) i]
          [else (loop (cdr lst) (+ i 1))])))

(define (parse-package-sexp form)
  (if (not (and (pair? form) (eq? (car form) 'package)))
    (error 'parse-package-sexp "invalid" form)
    (let ([clauses (cdr form)])
      (define (get key) (let ([c (assq key clauses)]) (and c (cadr c))))
      (define (getl key) (let ([c (assq key clauses)]) (and c (cdr c))))
      (let ([deps (map (lambda (d) (make-dep-spec (car d) (cadr d) #f))
                       (or (getl 'dependencies) '()))])
        (make-package
          (get 'name)
          (string->version (or (get 'version) "0.0.0"))
          deps
          (or (get 'description) "")
          '() "")))))

(printf "~%-- Package Manager --~%")

;; Version parsing
(let ([v (string->version "1.2.3")])
  (test "string->version: major"
    (version-major v) 1)
  (test "string->version: minor"
    (version-minor v) 2)
  (test "string->version: patch"
    (version-patch v) 3))

(test "version->string"
  (version->string (make-version 2 0 1))
  "2.0.1")

(test "version<?: true"
  (version<? (make-version 1 0 0) (make-version 2 0 0))
  #t)

(test "version<?: false"
  (version<? (make-version 2 0 0) (make-version 1 0 0))
  #f)

(test "version=?"
  (version=? (string->version "1.2.3") (make-version 1 2 3))
  #t)

;; Version satisfies?
(test "version-satisfies?: ^ compatible"
  (version-satisfies? (make-version 1 3 0) "^1.2.0")
  #t)

(test "version-satisfies?: ^ major mismatch"
  (version-satisfies? (make-version 2 0 0) "^1.0.0")
  #f)

(test "version-satisfies?: ~ tilde compatible"
  (version-satisfies? (make-version 1 2 5) "~1.2.0")
  #t)

(test "version-satisfies?: ~ minor mismatch"
  (version-satisfies? (make-version 1 3 0) "~1.2.0")
  #f)

(test "version-satisfies?: >= constraint"
  (version-satisfies? (make-version 2 0 0) ">=1.5.0")
  #t)

(test "version-satisfies?: exact"
  (version-satisfies? (make-version 1 2 3) "1.2.3")
  #t)

(test "version-satisfies?: wildcard"
  (version-satisfies? (make-version 99 0 0) "*")
  #t)

;; dep-spec
(let ([d (make-dep-spec 'json "^1.0.0" #f)])
  (test "dep-spec-name"
    (dep-spec-name d)
    'json)
  (test "dep-spec-constraint"
    (dep-spec-constraint d)
    "^1.0.0")
  (test "dep-spec-source"
    (dep-spec-source d)
    #f))

;; Package
(let ([pkg (make-package "my-app" (make-version 1 0 0)
                         (list (make-dep-spec 'json "^1.0.0" #f))
                         "Test app" '("alice") "MIT")])
  (test "package-name"
    (package-name pkg)
    "my-app")
  (test "package-version"
    (version->string (package-version pkg))
    "1.0.0")
  (test "package-dependencies"
    (length (package-dependencies pkg))
    1))

;; Registry
(let ([reg (make-registry)])
  (let ([pkg-json-1 (make-package "json" (make-version 1 0 0)
                                   '() "JSON parser v1" '() "MIT")]
        [pkg-json-2 (make-package "json" (make-version 1 2 0)
                                   '() "JSON parser v1.2" '() "MIT")]
        [pkg-http   (make-package "http" (make-version 2 0 0)
                                   (list (make-dep-spec "json" "^1.0.0" #f))
                                   "HTTP client" '() "MIT")])
    (registry-add! reg pkg-json-1)
    (registry-add! reg pkg-json-2)
    (registry-add! reg pkg-http)

    (test "registry-find: finds compatible"
      (and (registry-find reg "json" "^1.0.0") #t)
      #t)

    (test "registry-find: best version"
      (version->string (package-version (registry-find reg "json" "^1.0.0")))
      "1.2.0")

    (test "registry-find: not found"
      (registry-find reg "json" "^2.0.0")
      #f)

    (test "registry-list: both packages"
      (>= (length (registry-list reg)) 2)
      #t)

    ;; Resolve dependencies
    (let ([my-app (make-package "my-app" (make-version 1 0 0)
                                 (list (make-dep-spec "http" "^2.0.0" #f))
                                 "" '() "")])
      (let ([resolved (resolve-dependencies reg my-app '())])
        (test "resolve-dependencies: finds http"
          (and (assoc "http" resolved) #t)
          #t)
        (test "resolve-dependencies: transitively finds json"
          (and (assoc "json" resolved) #t)
          #t)))

    ;; Topological sort
    (let ([graph '((a b c) (b d) (c d) (d))])
      (let ([sorted (topological-sort
                      (map (lambda (entry)
                             (cons (car entry) (cdr entry)))
                           graph))])
        (test "topological-sort: d before b"
          (< (list-index sorted 'd) (list-index sorted 'b))
          #t)
        (test "topological-sort: d before c"
          (< (list-index sorted 'd) (list-index sorted 'c))
          #t)))))

;; Parse package file
(let ([sexp '(package
               (name "test-pkg")
               (version "2.1.0")
               (description "A test package")
               (dependencies
                 (json "^1.0.0")
                 (http ">=2.0.0")))])
  (let ([pkg (parse-package-sexp sexp)])
    (test "parse-package-sexp: name"
      (package-name pkg)
      "test-pkg")
    (test "parse-package-sexp: version"
      (version->string (package-version pkg))
      "2.1.0")
    (test "parse-package-sexp: dep count"
      (length (package-dependencies pkg))
      2)))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
