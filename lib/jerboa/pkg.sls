#!chezscheme
;;; (jerboa pkg) — Package Manager (Step 34)
;;;
;;; Content-addressed package store with lock files.
;;; Supports source (git/local) and version-range dependencies.

(library (jerboa pkg)
  (export
    ;; Package manifest
    make-package
    package?
    package-name
    package-version
    package-dependencies
    package-description

    ;; Version handling
    make-version
    version?
    version-major
    version-minor
    version-patch
    version->string
    string->version
    version<?
    version=?
    version-satisfies?

    ;; Dependency spec
    make-dep-spec
    dep-spec?
    dep-spec-name
    dep-spec-constraint
    dep-spec-source

    ;; Package registry
    make-registry
    registry?
    registry-add!
    registry-find
    registry-list

    ;; Resolution
    resolve-dependencies
    dependency-graph
    topological-sort

    ;; Lock file
    make-lock-file
    lock-file?
    lock-file-write
    lock-file-read

    ;; Package.sls reader
    read-package-file
    write-package-file)

  (import (chezscheme))

  ;; ========== Version ==========

  (define-record-type (version make-version version?)
    (fields (immutable major version-major)
            (immutable minor version-minor)
            (immutable patch version-patch)))

  (define (version->string v)
    (format "~a.~a.~a"
            (version-major v) (version-minor v) (version-patch v)))

  (define (string->version s)
    ;; Parse "major.minor.patch" — missing parts default to 0
    (let ([parts (let loop ([s s] [acc '()])
                   (let ([idx (let scan ([i 0])
                                (cond [(= i (string-length s)) #f]
                                      [(char=? (string-ref s i) #\.) i]
                                      [else (scan (+ i 1))]))])
                     (if idx
                       (loop (substring s (+ idx 1) (string-length s))
                             (cons (substring s 0 idx) acc))
                       (reverse (cons s acc)))))])
      (let ([nums (map (lambda (p)
                         (guard (exn [#t 0]) (string->number p)))
                       parts)])
        (make-version
          (if (>= (length nums) 1) (or (list-ref nums 0) 0) 0)
          (if (>= (length nums) 2) (or (list-ref nums 1) 0) 0)
          (if (>= (length nums) 3) (or (list-ref nums 2) 0) 0)))))

  (define (version<? a b)
    (or (< (version-major a) (version-major b))
        (and (= (version-major a) (version-major b))
             (or (< (version-minor a) (version-minor b))
                 (and (= (version-minor a) (version-minor b))
                      (< (version-patch a) (version-patch b)))))))

  (define (version=? a b)
    (and (= (version-major a) (version-major b))
         (= (version-minor a) (version-minor b))
         (= (version-patch a) (version-patch b))))

  (define (version-satisfies? v constraint)
    ;; constraint: string like "^1.2.0", "~1.2", ">=1.0.0", "1.2.3", "*"
    (cond
      [(equal? constraint "*") #t]
      [(and (>= (string-length constraint) 1)
            (char=? (string-ref constraint 0) #\^))
       ;; Caret: compatible with, major must match
       (let ([base (string->version (substring constraint 1 (string-length constraint)))])
         (and (= (version-major v) (version-major base))
              (or (> (version-minor v) (version-minor base))
                  (and (= (version-minor v) (version-minor base))
                       (>= (version-patch v) (version-patch base))))))]
      [(and (>= (string-length constraint) 1)
            (char=? (string-ref constraint 0) #\~))
       ;; Tilde: compatible minor, patch can vary
       (let ([base (string->version (substring constraint 1 (string-length constraint)))])
         (and (= (version-major v) (version-major base))
              (= (version-minor v) (version-minor base))
              (>= (version-patch v) (version-patch base))))]
      [(and (>= (string-length constraint) 2)
            (string=? (substring constraint 0 2) ">="))
       (let ([base (string->version (substring constraint 2 (string-length constraint)))])
         (or (version=? v base) (version<? base v)))]
      [(and (>= (string-length constraint) 1)
            (char=? (string-ref constraint 0) #\>))
       (let ([base (string->version (substring constraint 1 (string-length constraint)))])
         (version<? base v))]
      [else
       ;; Exact version match
       (version=? v (string->version constraint))]))

  ;; ========== Dependency Spec ==========

  (define-record-type (dep-spec make-dep-spec dep-spec?)
    (fields (immutable name       dep-spec-name)
            (immutable constraint dep-spec-constraint)  ;; version constraint string
            (immutable source     dep-spec-source)))    ;; #f | '(git url tag) | '(local path)

  ;; ========== Package ==========

  (define-record-type (package make-package package?)
    (fields (immutable name         package-name)
            (immutable version      package-version)      ;; version record
            (immutable dependencies package-dependencies) ;; list of dep-spec
            (immutable description  package-description)
            (immutable authors      package-authors)
            (immutable license      package-license)))

  ;; ========== Registry ==========

  ;; registry: hashtable mapping name → list of (version . package)
  (define-record-type (registry make-registry-raw registry?)
    (fields (immutable packages registry-packages)  ;; hashtable: name → alist (ver . pkg)
            (immutable mutex    registry-mutex)))

  (define (make-registry)
    (make-registry-raw (make-hashtable equal-hash equal?) (make-mutex)))

  (define (registry-add! reg pkg)
    (with-mutex (registry-mutex reg)
      (let* ([name (package-name pkg)]
             [ver  (package-version pkg)]
             [existing (hashtable-ref (registry-packages reg) name '())])
        (hashtable-set! (registry-packages reg) name
          (cons (cons ver pkg)
                (filter (lambda (e) (not (version=? (car e) ver))) existing))))))

  (define (registry-find reg name constraint)
    ;; Find best (highest) version satisfying constraint.
    ;; Returns package or #f.
    (with-mutex (registry-mutex reg)
      (let ([entries (hashtable-ref (registry-packages reg) name '())])
        (let ([satisfying
               (filter (lambda (e) (version-satisfies? (car e) constraint))
                       entries)])
          (if (null? satisfying)
            #f
            (let ([sorted (list-sort (lambda (a b) (version<? (car b) (car a)))
                                     satisfying)])
              (cdar sorted)))))))

  (define (registry-list reg)
    (with-mutex (registry-mutex reg)
      (let-values ([(names _) (hashtable-entries (registry-packages reg))])
        (vector->list names))))

  ;; ========== Dependency Resolution ==========

  (define (resolve-dependencies registry pkg visited)
    ;; Resolve all transitive dependencies of pkg.
    ;; Returns alist of (name . resolved-package) or raises error.
    (let loop ([deps (package-dependencies pkg)]
               [resolved '()]
               [seen visited])
      (if (null? deps)
        resolved
        (let* ([dep   (car deps)]
               [name  (dep-spec-name dep)]
               [cstr  (dep-spec-constraint dep)])
          (if (assoc name resolved)
            ;; Already resolved
            (loop (cdr deps) resolved seen)
            (let ([pkg2 (registry-find registry name cstr)])
              (if (not pkg2)
                (error 'resolve-dependencies
                       "package not found in registry"
                       name cstr)
                ;; Recursively resolve pkg2's deps (avoid cycles via seen)
                (if (member name seen)
                  (loop (cdr deps) resolved seen)  ;; circular dep — skip
                  (let ([sub-resolved
                         (resolve-dependencies registry pkg2 (cons name seen))])
                    (loop (cdr deps)
                          (cons (cons name pkg2)
                                (append sub-resolved resolved))
                          (cons name seen)))))))))))

  (define (dependency-graph pkg registry)
    ;; Returns alist: name → list of dependency names
    (let ([resolved (resolve-dependencies registry pkg '())])
      (map (lambda (entry)
             (cons (car entry)
                   (map dep-spec-name
                        (package-dependencies (cdr entry)))))
           resolved)))

  (define (topological-sort graph)
    ;; Kahn's algorithm for topological sort.
    ;; graph: alist (node . list-of-deps)
    ;; deps = what this node needs (prerequisites)
    ;; Returns list of nodes in dependency order (deps first).
    (let* ([nodes (map car graph)]
           ;; in-degree = number of prerequisites each node has
           [in-degree
            (let ([ht (make-hashtable equal-hash equal?)])
              (for-each (lambda (n)
                          (hashtable-set! ht n
                            (length (filter (lambda (d) (member d nodes))
                                           (let ([e (assoc n graph)])
                                             (if e (cdr e) '()))))))
                        nodes)
              ht)]
           ;; reverse-graph: node -> list of nodes that depend on it
           [rev
            (let ([ht (make-hashtable equal-hash equal?)])
              (for-each (lambda (n) (hashtable-set! ht n '())) nodes)
              (for-each
                (lambda (entry)
                  (for-each
                    (lambda (dep)
                      (when (member dep nodes)
                        (hashtable-set! ht dep
                          (cons (car entry) (hashtable-ref ht dep '())))))
                    (cdr entry)))
                graph)
              ht)]
           [queue (filter (lambda (n) (= 0 (hashtable-ref in-degree n 0))) nodes)])
      (let loop ([q queue] [result '()])
        (if (null? q)
          (if (= (length result) (length nodes))
            (reverse result)
            (error 'topological-sort "cycle detected in dependencies"))
          (let* ([n (car q)]
                 ;; nodes that depend on n (n is a prereq for them)
                 [dependents (hashtable-ref rev n '())]
                 [new-q
                  (let inner ([ds dependents] [q (cdr q)])
                    (if (null? ds) q
                      (let* ([m    (car ds)]
                             [deg  (- (hashtable-ref in-degree m 1) 1)])
                        (hashtable-set! in-degree m deg)
                        (inner (cdr ds)
                               (if (= deg 0) (cons m q) q)))))])
            (loop new-q (cons n result)))))))

  ;; ========== Lock File ==========

  (define-record-type (lock-file make-lock-file lock-file?)
    (fields (immutable entries lock-entries)))  ;; list of (name version source-hash)

  (define (lock-file-write lf port)
    ;; Write lock file as S-expression
    (for-each
      (lambda (e)
        (write e port)
        (newline port))
      (lock-entries lf)))

  (define (lock-file-read port)
    ;; Read lock file from S-expression
    (let loop ([entry (read port)] [entries '()])
      (if (eof-object? entry)
        (make-lock-file (reverse entries))
        (loop (read port) (cons entry entries)))))

  ;; ========== Package File Reader ==========

  (define (read-package-file path)
    ;; Read a package manifest S-expression from file.
    ;; Returns a package record.
    (if (not (file-exists? path))
      (error 'read-package-file "file not found" path)
      (call-with-input-file path
        (lambda (port)
          (let ([form (read port)])
            (parse-package-sexp form))))))

  (define (parse-package-sexp form)
    ;; Parse: (package (name "foo") (version "1.0.0") (dependencies ...) ...)
    (if (not (and (pair? form) (eq? (car form) 'package)))
      (error 'parse-package-sexp "invalid package form" form)
      (let ([clauses (cdr form)])
        (let ([name    (let ([c (assq 'name    clauses)]) (and c (cadr c)))]
              [ver-str (let ([c (assq 'version clauses)]) (and c (cadr c)))]
              [deps    (let ([c (assq 'dependencies clauses)]) (and c (cdr c)))]
              [desc    (let ([c (assq 'description clauses)]) (and c (cadr c)))]
              [authors (let ([c (assq 'authors clauses)]) (and c (cdr c)))]
              [license (let ([c (assq 'license clauses)]) (and c (cadr c)))])
          (unless name
            (error 'parse-package-sexp "missing name in package"))
          (make-package
            name
            (if ver-str (string->version ver-str) (make-version 0 0 0))
            (map parse-dep (or deps '()))
            (or desc "")
            (or authors '())
            (or license ""))))))

  (define (parse-dep dep-form)
    ;; Parse: (name "^1.0.0") or (name "1.0.0" (git "url" #:tag "v1.0"))
    (if (not (pair? dep-form))
      (error 'parse-dep "invalid dependency" dep-form)
      (let ([name (car dep-form)]
            [cstr (cadr dep-form)]
            [src  (if (>= (length dep-form) 3) (caddr dep-form) #f)])
        (make-dep-spec name cstr src))))

  (define (write-package-file pkg path)
    ;; Write package manifest to file.
    (call-with-output-file path
      (lambda (port)
        (write
          `(package
             (name ,(package-name pkg))
             (version ,(version->string (package-version pkg)))
             (description ,(package-description pkg))
             (dependencies
               ,@(map (lambda (d)
                        (if (dep-spec-source d)
                          `(,(dep-spec-name d) ,(dep-spec-constraint d) ,(dep-spec-source d))
                          `(,(dep-spec-name d) ,(dep-spec-constraint d))))
                      (package-dependencies pkg))))
          port)
        (newline port))))

  ) ;; end library
