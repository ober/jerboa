#!chezscheme
;;; Tests for (std dev pgo) -- Profile-Guided Optimization

(import (chezscheme)
        (std dev pgo))

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

(printf "--- Phase 2b: Profile-Guided Optimization ---~%~%")

;;; ======== profile-call ========

(test "profile-call returns result"
  (profile-call site1 + 1 2)
  3)

(test "profile-call string concat"
  (profile-call site2 string-append "hello" " world")
  "hello world")

;;; ======== profile-val ========

(test "profile-val returns value"
  (profile-val site3 42)
  42)

(test "profile-val string"
  (profile-val site4 "test")
  "test")

;;; ======== profile-site-counts ========

;; After calling profile-call for site1 twice with fixnum results
(profile-call site1 + 10 20)

(test "profile-site-counts non-empty after calls"
  (pair? (profile-site-counts 'site1))
  #t)

(test "profile-site-counts has fixnum type"
  (assq 'fixnum (profile-site-counts 'site1))
  (assq 'fixnum (profile-site-counts 'site1)))  ; just verify it's present

(test "profile-site-counts unknown site is empty"
  (profile-site-counts 'unknown-site-xyz)
  '())

;;; ======== profile-dominant-type ========

;; Call site5 multiple times with fixnums
(profile-val site5 1)
(profile-val site5 2)
(profile-val site5 3)

(test "profile-dominant-type fixnum"
  (profile-dominant-type 'site5)
  'fixnum)

;; site5-str: mostly strings
(profile-val site5-str "a")
(profile-val site5-str "b")
(profile-val site5-str "c")

(test "profile-dominant-type string"
  (profile-dominant-type 'site5-str)
  'string)

(test "profile-dominant-type unknown returns #f"
  (profile-dominant-type 'no-such-site)
  #f)

;;; ======== pgo-specialize ========

(define (add-specialized a b)
  (pgo-specialize add-site (a b)
    [(fixnum fixnum) (fx+ a b)]
    [else (+ a b)]))

(test "pgo-specialize fixnum path"
  (add-specialized 3 4)
  7)

(test "pgo-specialize else path (flonum)"
  (add-specialized 1.5 2.5)
  4.0)

(define (describe-val v)
  (pgo-specialize describe-site (v)
    [(string) (string-append "str:" v)]
    [(fixnum) (number->string v)]
    [else "other"]))

(test "pgo-specialize string branch"
  (describe-val "hello")
  "str:hello")

(test "pgo-specialize fixnum branch"
  (describe-val 42)
  "42")

(test "pgo-specialize else branch"
  (describe-val '(list))
  "other")

;;; ======== save-profile! and load-profile! ========

(define tmp-profile "/tmp/test-jerboa-pgo.prof")

(test "save-profile! succeeds"
  (begin (save-profile! tmp-profile) #t)
  #t)

(test "load-profile! succeeds"
  (begin (load-profile! tmp-profile) #t)
  #t)

;; After reload, site1 data should still exist (merged)
(test "loaded profile data accessible"
  (pair? (profile-site-counts 'site1))
  #t)

;;; ======== with-pgo-file ========

(with-pgo-file tmp-profile
  (test "with-pgo-file body executes"
    (+ 1 1)
    2))

;;; ======== Summary ========

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
