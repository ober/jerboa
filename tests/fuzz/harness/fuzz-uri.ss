#!/usr/bin/env scheme-script
#!chezscheme
;;; fuzz-uri.ss -- Fuzzer for std/net/uri
;;;
;;; Targets: uri-parse, uri-decode, uri-encode, uri->string
;;; Bug classes: malformed URLs, injection, encoding bugs

(import (chezscheme)
        (std net uri)
        (std test fuzz))

;;; ========== Seed corpus ==========

(define uri-seeds
  '("http://example.com"
    "https://user:pass@host:8080/path?q=v#frag"
    "ftp://files.example.com/pub/file.txt"
    "/"
    "/path/to/resource"
    "http://[::1]:8080/"
    "http://example.com/path?a=1&b=2"
    "mailto:user@example.com"
    ""
    "://no-scheme"
    "http://"
    "http://host/../../etc/passwd"
    ))

;;; ========== Generators ==========

(define (gen-random-uri)
  (case (random 10)
    [(0) ;; scheme + authority + path
     (string-append
       (random-element '("http" "https" "ftp" "file" "" "x"))
       "://"
       (random-ascii-string (+ 1 (random 30)))
       "/"
       (random-ascii-string (+ 1 (random 50))))]
    [(1) ;; path traversal
     (string-append "http://host/"
       (apply string-append
         (make-list (+ 2 (random 20)) "../"))
       "etc/passwd")]
    [(2) ;; huge query string
     (string-append "http://host/path?"
       (apply string-append
         (map (lambda (i)
                (string-append (if (> i 0) "&" "")
                               "key" (number->string i) "=value"))
              (iota (+ 100 (random 500))))))]
    [(3) ;; percent encoding edge cases
     (random-element
       '("http://host/%00" "http://host/%ZZ" "http://host/%"
         "http://host/%2" "http://host/%2G"
         "http://host/%2F%2F%2F"))]
    [(4) ;; null bytes
     (string-append "http://host/path" (string #\nul) "evil")]
    [(5) ;; IPv6
     (string-append "http://[" (random-ascii-string 20) "]:80/")]
    [(6) ;; backslash confusion
     "http://host\\@evil.com/"]
    [(7) ;; very long URL
     (string-append "http://host/" (make-string (+ 1000 (random 5000)) #\a))]
    [(8) ;; mutated seed
     (mutate-string (random-element uri-seeds))]
    [(9) ;; pure random
     (random-ascii-string (+ 1 (random 500)))]))

;;; ========== Percent-encoding fuzz ==========

(define uri-encode-stats
  (fuzz-run "uri-encode-decode"
    (lambda (_)
      (let* ([input (random-ascii-string (+ 1 (random 200)))]
             [encoded (uri-encode input)]
             [decoded (uri-decode encoded)])
        (unless (string=? input decoded)
          (error 'uri-roundtrip "mismatch" input decoded))))
    (lambda () #f)
    (quotient (fuzz-iterations) 4)))

;;; ========== Parse fuzz ==========

(define uri-parse-stats
  (fuzz-run "uri-parse"
    (lambda (input)
      (guard (exn [#t (void)])
        (let ([u (uri-parse input)])
          ;; If parse succeeded, try to reconstruct
          (when u (uri->string u)))))
    gen-random-uri))

(when (or (> (fuzz-stats-crashes uri-parse-stats) 0)
          (> (fuzz-stats-crashes uri-encode-stats) 0))
  (exit 1))
