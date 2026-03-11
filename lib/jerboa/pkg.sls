#!chezscheme
;;; (jerboa pkg) — Package Manager
;;;
;;; Semantic versioning, dependency resolution, manifests.

(library (jerboa pkg)
  (export
    ;; Package records
    make-package package? package-name package-version package-deps
    package-description package-author

    ;; Version operations
    version->list version-compare version<? version=? version>=?

    ;; Dependency records
    make-dep dep? dep-name dep-version-constraint

    ;; Constraint checking
    constraint-satisfied?

    ;; Resolution
    resolve-deps dependency-order

    ;; Manifest
    make-manifest manifest? manifest-packages
    manifest-add manifest-remove manifest-lookup)

  (import (chezscheme))

  ;; ========== Package ==========

  (define-record-type (%package make-package package?)
    (fields (immutable name        package-name)
            (immutable version     package-version)     ;; string "1.2.3"
            (immutable deps        package-deps)        ;; list of dep
            (immutable description package-description)
            (immutable author      package-author)))

  ;; ========== Version ==========

  (define (version->list ver-str)
    ;; "1.2.3" -> (1 2 3)
    (let loop ([s ver-str] [acc '()])
      (let ([idx (let scan ([i 0])
                   (cond [(= i (string-length s)) #f]
                         [(char=? (string-ref s i) #\.) i]
                         [else (scan (+ i 1))]))])
        (if idx
          (loop (substring s (+ idx 1) (string-length s))
                (cons (string->number (substring s 0 idx)) acc))
          (reverse (cons (or (string->number s) 0) acc))))))

  (define (version-compare a b)
    ;; Compare version strings a and b.
    ;; Returns -1, 0, or 1.
    (let ([la (version->list a)]
          [lb (version->list b)])
      (let loop ([la la] [lb lb])
        (cond
          [(and (null? la) (null? lb)) 0]
          [(null? la) -1]
          [(null? lb)  1]
          [(< (car la) (car lb)) -1]
          [(> (car la) (car lb))  1]
          [else (loop (cdr la) (cdr lb))]))))

  (define (version<? a b)  (= (version-compare a b) -1))
  (define (version=? a b)  (= (version-compare a b)  0))
  (define (version>=? a b) (>= (version-compare a b) 0))

  ;; ========== Dependency ==========

  (define-record-type (%dep make-dep dep?)
    (fields (immutable name               dep-name)
            (immutable version-constraint dep-version-constraint)))

  ;; ========== Constraint Checking ==========

  (define (constraint-satisfied? ver-str constraint)
    ;; constraint: "*", ">=1.0.0", "^1.0.0", "~1.2.0", "=1.0.0", "1.0.0"
    (cond
      [(equal? constraint "*") #t]
      [(and (>= (string-length constraint) 2)
            (string=? (substring constraint 0 2) ">="))
       (version>=? ver-str (substring constraint 2 (string-length constraint)))]
      [(and (>= (string-length constraint) 1)
            (char=? (string-ref constraint 0) #\^))
       ;; Caret: same major, >= base minor.patch
       (let* ([base (substring constraint 1 (string-length constraint))]
              [blist (version->list base)]
              [vlist (version->list ver-str)])
         (and (= (car vlist) (car blist))
              (or (> (cadr vlist) (cadr blist))
                  (and (= (cadr vlist) (cadr blist))
                       (>= (caddr vlist) (caddr blist))))))]
      [(and (>= (string-length constraint) 1)
            (char=? (string-ref constraint 0) #\~))
       ;; Tilde: same major.minor, >= base patch
       (let* ([base (substring constraint 1 (string-length constraint))]
              [blist (version->list base)]
              [vlist (version->list ver-str)])
         (and (= (car vlist) (car blist))
              (= (cadr vlist) (cadr blist))
              (>= (caddr vlist) (caddr blist))))]
      [(and (>= (string-length constraint) 1)
            (char=? (string-ref constraint 0) #\=))
       (version=? ver-str (substring constraint 1 (string-length constraint)))]
      [else
       ;; Exact match
       (version=? ver-str constraint)]))

  ;; ========== Dependency Resolution ==========

  (define (resolve-deps packages root-pkg)
    ;; Given a list of packages and a root package, return packages
    ;; in dependency order (topological sort, deps first).
    ;; Raises error on circular deps or unsatisfied deps.
    (let ([pkg-map (let ([ht (make-hashtable equal-hash equal?)])
                     (for-each (lambda (p)
                                 (hashtable-set! ht (package-name p) p))
                               packages)
                     ht)])
      ;; Topological sort with cycle detection
      (let ([visited  (make-hashtable equal-hash equal?)]
            [in-stack (make-hashtable equal-hash equal?)]
            [result   '()])
        (define (visit pkg)
          (let ([name (package-name pkg)])
            (when (hashtable-ref in-stack name #f)
              (error 'resolve-deps "circular dependency detected" name))
            (unless (hashtable-ref visited name #f)
              (hashtable-set! in-stack name #t)
              (for-each
                (lambda (dep)
                  (let ([dep-pkg (hashtable-ref pkg-map (dep-name dep) #f)])
                    (unless dep-pkg
                      (error 'resolve-deps "unsatisfied dependency"
                             (dep-name dep) (dep-version-constraint dep)))
                    (unless (constraint-satisfied?
                               (package-version dep-pkg)
                               (dep-version-constraint dep))
                      (error 'resolve-deps "version constraint not satisfied"
                             (dep-name dep) (dep-version-constraint dep)
                             (package-version dep-pkg)))
                    (visit dep-pkg)))
                (package-deps pkg))
              (hashtable-set! in-stack name #f)
              (hashtable-set! visited name #t)
              (set! result (cons pkg result)))))
        ;; Visit all deps of root
        (for-each
          (lambda (dep)
            (let ([dep-pkg (hashtable-ref pkg-map (dep-name dep) #f)])
              (unless dep-pkg
                (error 'resolve-deps "unsatisfied dependency"
                       (dep-name dep) (dep-version-constraint dep)))
              (visit dep-pkg)))
          (package-deps root-pkg))
        result)))

  (define (dependency-order packages root-pkg)
    ;; Returns packages in dependency order: deps before dependents.
    (resolve-deps packages root-pkg))

  ;; ========== Manifest ==========

  (define-record-type (%manifest make-manifest manifest?)
    (fields (mutable packages manifest-packages manifest-packages-set!)))  ;; list of package

  (define (manifest-add manifest pkg)
    ;; Add or replace a package in the manifest.
    (let ([existing (filter (lambda (p)
                              (not (equal? (package-name p) (package-name pkg))))
                            (manifest-packages manifest))])
      (manifest-packages-set! manifest (cons pkg existing))))

  (define (manifest-remove manifest name)
    ;; Remove a package by name.
    (manifest-packages-set! manifest
      (filter (lambda (p) (not (equal? (package-name p) name)))
              (manifest-packages manifest))))

  (define (manifest-lookup manifest name)
    ;; Find a package by name; returns #f if not found.
    (let loop ([pkgs (manifest-packages manifest)])
      (cond
        [(null? pkgs) #f]
        [(equal? (package-name (car pkgs)) name) (car pkgs)]
        [else (loop (cdr pkgs))])))

) ;; end library
