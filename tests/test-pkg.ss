#!chezscheme
;;; Tests for (jerboa pkg) -- Package Manager

(import (chezscheme)
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

(printf "--- Phase 3c: Package Manager ---~%~%")

;;; ======== Package Records ========

(test "make-package basic"
  (let ([p (make-package "foo" "1.0.0" '() "A library" "Alice")])
    (list (package? p)
          (package-name p)
          (package-version p)))
  '(#t "foo" "1.0.0"))

(test "package-description"
  (package-description (make-package "foo" "1.0.0" '() "hello" "Bob"))
  "hello")

(test "package-author"
  (package-author (make-package "foo" "1.0.0" '() "desc" "Carol"))
  "Carol")

(test "package? predicate false"
  (package? 42)
  #f)

;;; ======== Version Operations ========

(test "version->list basic"
  (version->list "1.2.3")
  '(1 2 3))

(test "version->list short"
  (version->list "2.0")
  '(2 0))

(test "version<? true"
  (version<? "1.0.0" "2.0.0")
  #t)

(test "version<? false"
  (version<? "2.0.0" "1.0.0")
  #f)

(test "version=? true"
  (version=? "1.2.3" "1.2.3")
  #t)

(test "version=? false"
  (version=? "1.2.3" "1.2.4")
  #f)

(test "version>=? equal"
  (version>=? "1.2.3" "1.2.3")
  #t)

(test "version>=? greater"
  (version>=? "2.0.0" "1.9.9")
  #t)

;;; ======== Constraints ========

(test "constraint * satisfied"
  (constraint-satisfied? "1.2.3" "*")
  #t)

(test "constraint >= satisfied"
  (constraint-satisfied? "2.0.0" ">=1.0.0")
  #t)

(test "constraint >= not satisfied"
  (constraint-satisfied? "0.9.0" ">=1.0.0")
  #f)

(test "constraint ^ satisfied"
  (constraint-satisfied? "1.3.0" "^1.0.0")
  #t)

(test "constraint ^ not satisfied (different major)"
  (constraint-satisfied? "2.0.0" "^1.0.0")
  #f)

(test "constraint ~ satisfied"
  (constraint-satisfied? "1.2.5" "~1.2.0")
  #t)

(test "constraint ~ not satisfied (different minor)"
  (constraint-satisfied? "1.3.0" "~1.2.0")
  #f)

(test "constraint = exact match"
  (constraint-satisfied? "1.0.0" "=1.0.0")
  #t)

(test "constraint exact (no prefix)"
  (constraint-satisfied? "1.0.0" "1.0.0")
  #t)

;;; ======== Dependency Records ========

(test "make-dep"
  (let ([d (make-dep "bar" ">=2.0.0")])
    (list (dep? d) (dep-name d) (dep-version-constraint d)))
  '(#t "bar" ">=2.0.0"))

;;; ======== resolve-deps ========

(test "resolve-deps simple"
  (let* ([bar (make-package "bar" "1.0.0" '() "" "")]
         [foo (make-package "foo" "1.0.0"
                (list (make-dep "bar" ">=1.0.0"))
                "" "")]
         [result (resolve-deps (list bar) foo)])
    (map package-name result))
  '("bar"))

(test "resolve-deps transitive"
  (let* ([baz (make-package "baz" "1.0.0" '() "" "")]
         [bar (make-package "bar" "1.0.0"
                (list (make-dep "baz" "*"))
                "" "")]
         [foo (make-package "foo" "1.0.0"
                (list (make-dep "bar" "*"))
                "" "")]
         [result (resolve-deps (list bar baz) foo)])
    ;; baz should come before bar in dependency order
    (let ([names (map package-name result)])
      (and (member "bar" names) (member "baz" names) #t)))
  #t)

(test "resolve-deps unsatisfied raises error"
  (guard (exn [#t 'error])
    (let* ([foo (make-package "foo" "1.0.0"
                  (list (make-dep "missing" "*"))
                  "" "")])
      (resolve-deps '() foo)
      'no-error))
  'error)

;;; ======== Manifest ========

(test "make-manifest"
  (let ([m (make-manifest '())])
    (manifest? m))
  #t)

(test "manifest-add and lookup"
  (let* ([m (make-manifest '())]
         [p (make-package "foo" "1.0.0" '() "" "")])
    (manifest-add m p)
    (package-name (manifest-lookup m "foo")))
  "foo")

(test "manifest-lookup missing returns #f"
  (let ([m (make-manifest '())])
    (manifest-lookup m "nonexistent"))
  #f)

(test "manifest-remove"
  (let* ([m (make-manifest '())]
         [p (make-package "foo" "1.0.0" '() "" "")])
    (manifest-add m p)
    (manifest-remove m "foo")
    (manifest-lookup m "foo"))
  #f)

(test "manifest-add replaces existing"
  (let* ([m  (make-manifest '())]
         [p1 (make-package "foo" "1.0.0" '() "" "")]
         [p2 (make-package "foo" "2.0.0" '() "" "")])
    (manifest-add m p1)
    (manifest-add m p2)
    (package-version (manifest-lookup m "foo")))
  "2.0.0")

;;; Summary

(printf "~%Package Manager: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
