#!chezscheme
;;; Tests for (std build reproducible) — Reproducible Build Utilities

(import (chezscheme) (std build reproducible))

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

(printf "--- (std build reproducible) tests ---~%")

;;; ======== Helpers (defined first) ========

(define (string-search haystack needle)
  ;; Returns #t if needle is found in haystack, #f otherwise.
  (let ([hn (string-length haystack)]
        [nn (string-length needle)])
    (and (<= nn hn)
         (let loop ([i 0])
           (cond
             [(> (+ i nn) hn) #f]
             [(string=? (substring haystack i (+ i nn)) needle) #t]
             [else (loop (+ i 1))])))))

(define (string-trim-right s)
  (let loop ([i (- (string-length s) 1)])
    (cond
      [(< i 0) ""]
      [(char-whitespace? (string-ref s i)) (loop (- i 1))]
      [else (substring s 0 (+ i 1))])))

;;; ======== Content Hashing ========

(printf "~%-- Content Hashing --~%")

(test "content-hash-string returns string"
  (string? (content-hash-string "hello"))
  #t)

(test "content-hash-string non-empty"
  (> (string-length (content-hash-string "hello")) 0)
  #t)

(test "content-hash-string deterministic"
  (string=? (content-hash-string "hello") (content-hash-string "hello"))
  #t)

(test "content-hash-string different for different inputs"
  (string=? (content-hash-string "hello") (content-hash-string "world"))
  #f)

(test "content-hash-string empty string"
  (string? (content-hash-string ""))
  #t)

(let ([f "/tmp/jerboa-repro-hash-test.txt"])
  (call-with-output-file f
    (lambda (p) (display "deterministic content" p))
    'replace)

  (test "content-hash returns string for file"
    (string? (content-hash f))
    #t)

  (test "content-hash deterministic"
    (string=? (content-hash f) (content-hash f))
    #t)

  (let ([h1 (content-hash f)])
    (call-with-output-file f
      (lambda (p) (display "modified content" p))
      'replace)
    (test "content-hash changes after file modification"
      (string=? h1 (content-hash f))
      #f))

  (delete-file f))

(test "content-hash returns #f for missing file"
  (content-hash "/nonexistent/path/xyz.txt")
  #f)

;;; ======== Manifest ========

(printf "~%-- Manifest --~%")

(test "make-manifest returns manifest"
  (manifest? (make-manifest))
  #t)

(test "manifest? false for non-manifest"
  (manifest? "not a manifest")
  #f)

(let ([m (make-manifest)])
  (test "manifest-get on empty manifest"
    (manifest-get m "missing")
    #f)

  (manifest-add! m "key1" "value1")
  (manifest-add! m "key2" "value2")

  (test "manifest-get after add"
    (manifest-get m "key1")
    "value1")

  (test "manifest-get second key"
    (manifest-get m "key2")
    "value2")

  (test "manifest-get missing key returns #f"
    (manifest-get m "absent")
    #f)

  (manifest-add! m "key1" "updated")
  (test "manifest-add! updates existing key"
    (manifest-get m "key1")
    "updated")

  (test "manifest->alist returns list"
    (list? (manifest->alist m))
    #t)

  (test "manifest->alist has correct length"
    (= (length (manifest->alist m)) 2)
    #t)

  (test "manifest->string returns string"
    (string? (manifest->string m))
    #t)

  (test "manifest->string contains key=value"
    (let ([s (manifest->string m)])
      (and (string-search s "key1=updated")
           (string-search s "key2=value2")
           #t))
    #t)

  (test "manifest-hash returns string"
    (string? (manifest-hash m))
    #t)

  (test "manifest-hash non-empty"
    (> (string-length (manifest-hash m)) 0)
    #t))

;;; ======== Manifest Serialization ========

(printf "~%-- Manifest Serialization --~%")

(let ([m (make-manifest)])
  (manifest-add! m "source" "abc123")
  (manifest-add! m "deps"   "def456")
  (manifest-add! m "flags"  "-O2")

  (let* ([s  (manifest->string m)]
         [m2 (manifest-from-string s)])

    (test "manifest roundtrip source"
      (manifest-get m2 "source")
      "abc123")

    (test "manifest roundtrip deps"
      (manifest-get m2 "deps")
      "def456")

    (test "manifest roundtrip flags"
      (manifest-get m2 "flags")
      "-O2")

    (test "manifest-from-string returns manifest"
      (manifest? m2)
      #t)))

;;; ======== Artifact Store ========

(printf "~%-- Artifact Store --~%")

(let* ([store-dir "/tmp/jerboa-repro-store-test"]
       [store (begin (system (string-append "rm -rf " store-dir))
                     (make-artifact-store store-dir))])

  (test "make-artifact-store returns store"
    (artifact-store? store)
    #t)

  (test "artifact-store? false for non-store"
    (artifact-store? "nope")
    #f)

  (let* ([content "compiled artifact content"]
         [hash    (artifact-store-put! store content)])

    (test "artifact-store-put! returns string hash"
      (string? hash)
      #t)

    (test "artifact-store-has? true after put"
      (artifact-store-has? store hash)
      #t)

    (test "artifact-store-has? false for random hash"
      (artifact-store-has? store "deadbeef00000000")
      #f)

    (test "artifact-store-get returns content"
      (let ([got (artifact-store-get store hash)])
        (and (string? got)
             (string=? (string-trim-right got) (string-trim-right content))))
      #t)

    (test "artifact-store-get returns #f for missing"
      (artifact-store-get store "0000000000000000")
      #f)

    (test "artifact-store-path returns string"
      (string? (artifact-store-path store hash))
      #t)

    (test "artifact-store-path contains hash prefix"
      (let ([path (artifact-store-path store hash)])
        (string-search path (substring hash 0 2)))
      #t))

  (system (string-append "rm -rf " store-dir)))

;;; ======== Build Records ========

(printf "~%-- Build Records --~%")

(let ([r (make-build-record "src-hash-123" "deps-hash-456" "-O2 -static")])
  (test "make-build-record returns build-record"
    (build-record? r)
    #t)

  (test "build-record? false for non-record"
    (build-record? '())
    #f)

  (test "build-record-source-hash"
    (build-record-source-hash r)
    "src-hash-123")

  (test "build-record-deps-hash"
    (build-record-deps-hash r)
    "deps-hash-456")

  (test "build-record-timestamp is positive integer"
    (and (integer? (build-record-timestamp r))
         (> (build-record-timestamp r) 0))
    #t)

  (test "build-record-hash returns string"
    (string? (build-record-hash r))
    #t)

  (test "build-record-hash non-empty"
    (> (string-length (build-record-hash r)) 0)
    #t)

  (test "build-record-hash deterministic"
    (string=? (build-record-hash r) (build-record-hash r))
    #t)

  (let ([r2 (make-build-record "other-src" "deps-hash-456" "-O2 -static")])
    (test "build-record-hash differs for different sources"
      (string=? (build-record-hash r) (build-record-hash r2))
      #f)))

;;; ======== Verification ========

(printf "~%-- Verification --~%")

(let ([f "/tmp/jerboa-repro-verify-test.txt"])
  (call-with-output-file f
    (lambda (p) (display "artifact content" p))
    'replace)

  (let ([r (make-build-record (content-hash f) "" "")])
    (test "verify-build returns #t for valid artifact"
      (verify-build r f)
      #t))

  (test "verify-build returns #f for missing file"
    (verify-build (make-build-record "x" "" "") "/nonexistent/artifact.o")
    #f)

  (delete-file f))

;;; ======== Normalize Artifact ========

(printf "~%-- Normalize Artifact --~%")

(let ([f "/tmp/jerboa-repro-normalize-test.txt"])
  (call-with-output-file f
    (lambda (p) (display "built on 2024-01-15 with flags -O2" p))
    'replace)

  (let ([out (normalize-artifact f)])
    (test "normalize-artifact returns path string"
      (string? out)
      #t)

    (test "normalize-artifact creates .normalized file"
      (file-exists? out)
      #t)

    (let ([normalized-content
           (call-with-input-file out
             (lambda (port)
               (let loop ([chars '()])
                 (let ([c (read-char port)])
                   (if (eof-object? c)
                       (list->string (reverse chars))
                       (loop (cons c chars)))))))])
      (test "normalize-artifact strips date"
        (and (not (string-search normalized-content "2024-01-15"))
             (string-search normalized-content "<DATE>")
             #t)
        #t)

      (test "normalize-artifact keeps non-date content"
        (string-search normalized-content "flags -O2")
        #t))

    (delete-file out))

  (delete-file f))

;;; ======== Build Cache ========

(printf "~%-- Build Cache --~%")

(let ([cache (make-build-cache)])
  (test "make-build-cache returns cache"
    (build-cache? cache)
    #t)

  (test "build-cache? false for non-cache"
    (build-cache? '())
    #f)

  (let ([r (make-build-record "src" "deps" "-O2")]
        [artifact "compiled output"])

    (test "build-cache-lookup miss returns #f"
      (build-cache-lookup cache r)
      #f)

    (build-cache-store! cache r artifact)

    (test "build-cache-lookup hit returns artifact"
      (build-cache-lookup cache r)
      "compiled output")

    (let ([stats (build-cache-stats cache)])
      (test "build-cache-stats returns list"
        (list? stats)
        #t)

      (test "build-cache-stats has hits"
        (assq 'hits stats)
        (cons 'hits 1))

      (test "build-cache-stats has misses"
        (assq 'misses stats)
        (cons 'misses 1))

      (test "build-cache-stats has entries"
        (assq 'entries stats)
        (cons 'entries 1))))

  (let ([r1 (make-build-record "s1" "d1" "")]
        [r2 (make-build-record "s2" "d2" "")])
    (build-cache-store! cache r1 "output1")
    (build-cache-store! cache r2 "output2")

    (test "build-cache multiple entries"
      (and (equal? (build-cache-lookup cache r1) "output1")
           (equal? (build-cache-lookup cache r2) "output2"))
      #t)))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
