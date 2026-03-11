#!chezscheme
;;; Tests for (jerboa lock) -- Lockfile Management

(import (chezscheme)
        (jerboa lock))

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

(printf "--- Phase 3c: Lockfile Management ---~%~%")

;;; ======== Lock Entry ========

(test "make-lock-entry"
  (let ([e (make-lock-entry "foo" "1.0.0" "abc123" '("bar"))])
    (list (lock-entry? e)
          (lock-entry-name e)
          (lock-entry-version e)
          (lock-entry-hash e)
          (lock-entry-deps e)))
  '(#t "foo" "1.0.0" "abc123" ("bar")))

(test "lock-entry? false"
  (lock-entry? "not-an-entry")
  #f)

;;; ======== Lockfile ========

(test "make-lockfile empty"
  (let ([lf (make-lockfile '())])
    (list (lockfile? lf) (null? (lockfile-entries lf))))
  '(#t #t))

(test "lockfile-add!"
  (let* ([lf (make-lockfile '())]
         [e  (make-lock-entry "foo" "1.0.0" "abc" '())])
    (lockfile-add! lf e)
    (length (lockfile-entries lf)))
  1)

(test "lockfile-lookup found"
  (let* ([lf (make-lockfile '())]
         [e  (make-lock-entry "foo" "1.0.0" "abc" '())])
    (lockfile-add! lf e)
    (lock-entry-version (lockfile-lookup lf "foo")))
  "1.0.0")

(test "lockfile-lookup not found"
  (let ([lf (make-lockfile '())])
    (lockfile-lookup lf "missing"))
  #f)

(test "lockfile-has? true"
  (let* ([lf (make-lockfile '())]
         [e  (make-lock-entry "foo" "1.0.0" "abc" '())])
    (lockfile-add! lf e)
    (lockfile-has? lf "foo"))
  #t)

(test "lockfile-has? false"
  (let ([lf (make-lockfile '())])
    (lockfile-has? lf "foo"))
  #f)

(test "lockfile-remove!"
  (let* ([lf (make-lockfile '())]
         [e  (make-lock-entry "foo" "1.0.0" "abc" '())])
    (lockfile-add! lf e)
    (lockfile-remove! lf "foo")
    (lockfile-has? lf "foo"))
  #f)

(test "lockfile-add! replaces existing"
  (let* ([lf (make-lockfile '())]
         [e1 (make-lock-entry "foo" "1.0.0" "abc" '())]
         [e2 (make-lock-entry "foo" "2.0.0" "def" '())])
    (lockfile-add! lf e1)
    (lockfile-add! lf e2)
    (lock-entry-version (lockfile-lookup lf "foo")))
  "2.0.0")

;;; ======== Serialization ========

(test "lockfile->sexp"
  (let* ([lf (make-lockfile '())]
         [e  (make-lock-entry "foo" "1.0.0" "abc" '("bar"))])
    (lockfile-add! lf e)
    (let ([s (lockfile->sexp lf)])
      (and (eq? (car s) 'lockfile)
           (= (length (cdr s)) 1)
           (let ([entry (cadr s)])
             (and (eq? (car entry) 'entry)
                  (equal? (list-ref entry 1) "foo"))))))
  #t)

(test "sexp->lockfile round-trip"
  (let* ([lf1 (make-lockfile '())]
         [e   (make-lock-entry "foo" "1.0.0" "abc123" '("bar"))])
    (lockfile-add! lf1 e)
    (let* ([s   (lockfile->sexp lf1)]
           [lf2 (sexp->lockfile s)])
      (let ([e2 (lockfile-lookup lf2 "foo")])
        (and e2
             (equal? (lock-entry-version e2) "1.0.0")
             (equal? (lock-entry-hash e2) "abc123")))))
  #t)

(test "lockfile-write and lockfile-read"
  (let* ([lf1 (make-lockfile '())]
         [e   (make-lock-entry "pkg" "2.1.0" "deadbeef" '())])
    (lockfile-add! lf1 e)
    (let* ([out  (open-output-string)]
           [_    (lockfile-write lf1 out)]
           [str  (get-output-string out)]
           [in   (open-input-string str)]
           [lf2  (lockfile-read in)])
      (let ([e2 (lockfile-lookup lf2 "pkg")])
        (and e2 (equal? (lock-entry-version e2) "2.1.0")))))
  #t)

;;; ======== Merge ========

(test "lockfile-merge basic"
  (let* ([lf1 (make-lockfile '())]
         [lf2 (make-lockfile '())]
         [e1  (make-lock-entry "foo" "1.0.0" "abc" '())]
         [e2  (make-lock-entry "bar" "2.0.0" "def" '())])
    (lockfile-add! lf1 e1)
    (lockfile-add! lf2 e2)
    (let ([merged (lockfile-merge lf1 lf2)])
      (and (lockfile-has? merged "foo")
           (lockfile-has? merged "bar"))))
  #t)

(test "lockfile-merge right takes precedence"
  (let* ([lf1 (make-lockfile '())]
         [lf2 (make-lockfile '())]
         [e1  (make-lock-entry "foo" "1.0.0" "abc" '())]
         [e2  (make-lock-entry "foo" "2.0.0" "def" '())])
    (lockfile-add! lf1 e1)
    (lockfile-add! lf2 e2)
    (let ([merged (lockfile-merge lf1 lf2)])
      (lock-entry-version (lockfile-lookup merged "foo"))))
  "2.0.0")

;;; ======== Diff ========

(test "lockfile-diff added"
  (let* ([lf1 (make-lockfile '())]
         [lf2 (make-lockfile '())]
         [e   (make-lock-entry "new-pkg" "1.0.0" "abc" '())])
    (lockfile-add! lf2 e)
    (let ([diff (lockfile-diff lf1 lf2)])
      (map lock-entry-name (car diff))))
  '("new-pkg"))

(test "lockfile-diff removed"
  (let* ([lf1 (make-lockfile '())]
         [lf2 (make-lockfile '())]
         [e   (make-lock-entry "old-pkg" "1.0.0" "abc" '())])
    (lockfile-add! lf1 e)
    (let ([diff (lockfile-diff lf1 lf2)])
      (map lock-entry-name (cadr diff))))
  '("old-pkg"))

(test "lockfile-diff changed"
  (let* ([lf1 (make-lockfile '())]
         [lf2 (make-lockfile '())]
         [e1  (make-lock-entry "foo" "1.0.0" "abc" '())]
         [e2  (make-lock-entry "foo" "2.0.0" "def" '())])
    (lockfile-add! lf1 e1)
    (lockfile-add! lf2 e2)
    (let ([diff (lockfile-diff lf1 lf2)])
      (map lock-entry-name (caddr diff))))
  '("foo"))

(test "lockfile-diff no changes"
  (let* ([lf1 (make-lockfile '())]
         [lf2 (make-lockfile '())]
         [e   (make-lock-entry "foo" "1.0.0" "abc" '())])
    (lockfile-add! lf1 e)
    (lockfile-add! lf2 e)
    (let ([diff (lockfile-diff lf1 lf2)])
      (list (null? (car diff))
            (null? (cadr diff))
            (null? (caddr diff)))))
  '(#t #t #t))

;;; Summary

(printf "~%Lockfile Management: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
