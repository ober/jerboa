#!/usr/bin/env scheme-script
#!chezscheme
;;; fuzz-router.ss -- Fuzzer for std/net/router
;;;
;;; Targets: router-match, router-add!, parse-pattern
;;; Bug classes: path traversal, segment explosion, crash on malformed paths

(import (chezscheme)
        (std net router)
        (std test fuzz))

;;; ========== Setup: build a router with some routes ==========

(define test-router (make-router))

;; Add various route patterns
(for-each
  (lambda (pattern)
    (router-add! test-router "GET" pattern
      (lambda (req) (list 'ok pattern))))
  '("/users/:id"
    "/users/:id/posts/:post-id"
    "/files/*"
    "/api/v1/data"
    "/static/css/style.css"
    "/:catchall"))

;;; ========== Generators ==========

(define (gen-random-path)
  (case (random 10)
    [(0) ;; path traversal
     (string-append "/"
       (apply string-append
         (make-list (+ 2 (random 20)) "../"))
       "etc/passwd")]
    [(1) ;; very deep path
     (string-append "/"
       (apply string-append
         (map (lambda (_) (string-append (random-ascii-string 5) "/"))
              (make-list (+ 10 (random 200))))))]
    [(2) ;; normal path with param
     (string-append "/users/" (number->string (random 10000)))]
    [(3) ;; wildcard path
     (string-append "/files/" (random-ascii-string 50))]
    [(4) ;; empty path
     ""]
    [(5) ;; just slash
     "/"]
    [(6) ;; double slashes
     "//users///id//"]
    [(7) ;; special characters in segments
     (string-append "/users/" (random-ascii-string 20)
                    "?query=value&other=thing")]
    [(8) ;; null bytes
     (string-append "/users/" (string #\nul) "/posts")]
    [(9) ;; encoded traversal
     "/users/%2e%2e/%2e%2e/etc/passwd"]))

;;; ========== Run ==========

(define router-stats
  (fuzz-run "router-match"
    (lambda (path)
      (guard (exn [#t (void)])
        (router-match test-router "GET" path)))
    gen-random-path))

;; Fuzz pattern parsing
(define pattern-stats
  (fuzz-run "router-pattern"
    (lambda (_)
      (let ([pattern (gen-random-path)])
        (guard (exn [#t (void)])
          (let ([r (make-router)])
            (router-add! r "GET" pattern
              (lambda (req) 'ok))
            (router-match r "GET" pattern)))))
    (lambda () #f)
    (quotient (fuzz-iterations) 2)))

(when (or (> (fuzz-stats-crashes router-stats) 0)
          (> (fuzz-stats-crashes pattern-stats) 0))
  (exit 1))
