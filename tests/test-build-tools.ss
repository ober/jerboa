#!chezscheme
;;; Tests for (std build reproducible) and (std build sbom)

(import (chezscheme)
        (std build reproducible)
        (std build sbom))

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

(printf "--- Build Tools Tests ---~%~%")

;; ========== Reproducible: content hashing ==========

(printf "-- Content hashing --~%")

(test "content-hash-string returns non-empty string"
  (let ([h (content-hash-string "hello world")])
    (and (string? h) (> (string-length h) 0)))
  #t)

(test "content-hash-string is deterministic"
  (string=? (content-hash-string "test data")
            (content-hash-string "test data"))
  #t)

(test "content-hash-string differs for different input"
  (string=? (content-hash-string "abc")
            (content-hash-string "def"))
  #f)

;; ========== Manifest ==========

(printf "~%-- Manifest --~%")

(test "make-manifest creates manifest"
  (manifest? (make-manifest))
  #t)

(test "manifest-add! and manifest-get"
  (let ([m (make-manifest)])
    (manifest-add! m "key1" "val1")
    (manifest-get m "key1"))
  "val1")

(test "manifest-hash is deterministic"
  (let ([m1 (make-manifest)]
        [m2 (make-manifest)])
    (manifest-add! m1 "a" "1")
    (manifest-add! m2 "a" "1")
    (string=? (manifest-hash m1) (manifest-hash m2)))
  #t)

(test "manifest round-trip through string"
  (let ([m1 (make-manifest)])
    (manifest-add! m1 "key" "value")
    (let ([m2 (manifest-from-string (manifest->string m1))])
      (manifest-get m2 "key")))
  "value")

;; ========== Artifact store ==========

(printf "~%-- Artifact store --~%")

(let ([store-path "/tmp/jerboa-test-artifact-store"])
  (test "make-artifact-store creates store"
    (let ([s (make-artifact-store store-path)])
      (artifact-store? s))
    #t)

  (test "artifact-store-put! and get round-trip"
    (let ([s (make-artifact-store store-path)])
      (let ([hash (artifact-store-put! s "test content")])
        (artifact-store-get s hash)))
    "test content\n")

  (test "artifact-store-has? works"
    (let ([s (make-artifact-store store-path)])
      (let ([hash (artifact-store-put! s "check me")])
        (artifact-store-has? s hash)))
    #t))

;; ========== Build records ==========

(printf "~%-- Build records --~%")

(test "make-build-record creates record"
  (build-record?
    (make-build-record "src-hash" "deps-hash" "-O2"))
  #t)

(test "build-record-hash is deterministic"
  (let ([r1 (make-build-record "aaa" "bbb" "-O2")]
        [r2 (make-build-record "aaa" "bbb" "-O2")])
    (string=? (build-record-hash r1) (build-record-hash r2)))
  #t)

;; ========== Provenance ==========

(printf "~%-- Provenance --~%")

(test "provenance round-trip"
  (let* ([p (make-provenance "src123" "builder1" "out456")]
         [sexp (provenance->sexp p)]
         [p2 (sexp->provenance sexp)])
    (and (string=? (provenance-source-hash p2) "src123")
         (string=? (provenance-builder-id p2) "builder1")
         (string=? (provenance-output-hash p2) "out456")))
  #t)

(test "verify-provenance checks source hash"
  (let ([p (make-provenance "abc" "b1" "xyz")])
    (and (verify-provenance p "abc")
         (not (verify-provenance p "wrong"))))
  #t)

;; ========== SBOM ==========

(printf "~%-- SBOM --~%")

(test "make-sbom creates sbom"
  (sbom? (make-sbom "test-project" "1.0.0"))
  #t)

(test "sbom-add-component! and find"
  (let ([s (make-sbom "proj" "1.0")])
    (sbom-add-component! s (make-component "ring" "0.17.0" 'library))
    (let ([c (sbom-find-component s "ring")])
      (and (component? c)
           (string=? (component-version c) "0.17.0"))))
  #t)

(test "sbom round-trip through sexp"
  (let ([s1 (make-sbom "proj" "2.0")])
    (sbom-add-component! s1 (make-component "flate2" "1.0.0" 'library))
    (let* ([sexp (sbom->sexp s1)]
           [s2 (sexp->sbom sexp)]
           [c (sbom-find-component s2 "flate2")])
      (and (component? c)
           (string=? (component-version c) "1.0.0"))))
  #t)

;; ========== Rust dep detection ==========

(printf "~%-- Rust dependency detection --~%")

;; Create a test Cargo.lock in /tmp
(let ([test-dir "/tmp/jerboa-test-rust-deps"])
  (guard (exn [#t (void)])
    (mkdir test-dir))
  (call-with-output-file (string-append test-dir "/Cargo.lock")
    (lambda (port)
      (display "# This file is generated\nversion = 3\n\n" port)
      (display "[[package]]\nname = \"ring\"\nversion = \"0.17.5\"\n\n" port)
      (display "[[package]]\nname = \"flate2\"\nversion = \"1.0.28\"\n\n" port))
    'replace)

  (test "detect-rust-deps finds crates from Cargo.lock"
    (let ([deps (detect-rust-deps test-dir)])
      (and (> (length deps) 0)
           (assoc "ring" deps)))
    '("ring" "0.17.5"))

  (test "detect-rust-deps returns all crates"
    (length (detect-rust-deps test-dir))
    2))

;; ========== C dep detection ==========

(printf "~%-- C dependency detection --~%")

(let ([test-build "/tmp/jerboa-test-build.ss"])
  (call-with-output-file test-build
    (lambda (port)
      (display "(exe \"myapp\" (gsc-cc-options \"-lsqlite3 -lz -lm\"))" port))
    'replace)

  (test "detect-c-deps finds -l flags"
    (let ([deps (detect-c-deps test-build)])
      (if (and (member "sqlite3" deps)
               (member "z" deps)
               (member "m" deps))
        #t #f))
    #t))

;; ========== Summary ==========

(printf "~%Build tools tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
