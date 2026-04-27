#!chezscheme
;;; (std build verify) — Dependency Verification
;;;
;;; Cryptographic verification of all dependencies against lockfile hashes.
;;; Extends (jerboa lock) with SHA-256 integrity checking.

(library (std build verify)
  (export
    ;; Verification
    verify-dependency
    verify-all-dependencies
    verification-result?
    verification-result-name
    verification-result-status
    verification-result-expected
    verification-result-actual

    ;; Hash computation
    file-sha256-hex
    directory-hash

    ;; Lockfile verification
    verify-lockfile!
    lockfile-verify-report)

  (import (chezscheme)
         (jerboa lock))

  ;; ========== Verification Result ==========

  (define-record-type (verification-result %make-verification-result verification-result?)
    (sealed #t)
    (fields
      (immutable name verification-result-name)
      (immutable status verification-result-status)       ;; 'ok | 'mismatch | 'missing | 'error
      (immutable expected verification-result-expected)   ;; expected hash
      (immutable actual verification-result-actual)))     ;; actual hash or error message

  ;; ========== SHA-256 Hex ==========
  ;;
  ;; sha256-bytevector landed in Chez core (Phase 67, Round 12).  This
  ;; replaces the previous sha256sum/find/xargs shell pipeline, which had
  ;; shell-quote injection surface and required two process spawns per
  ;; verification.  Pure-Scheme path now: read file → hash → hex-encode.

  (define hex-chars "0123456789abcdef")

  (define (bv->hex bv)
    (let* ([n (bytevector-length bv)]
           [out (make-string (fx* 2 n))])
      (let loop ([i 0])
        (when (fx< i n)
          (let ([b (bytevector-u8-ref bv i)])
            (string-set! out (fx* 2 i)
              (string-ref hex-chars (fxarithmetic-shift-right b 4)))
            (string-set! out (fx+ (fx* 2 i) 1)
              (string-ref hex-chars (fxand b #xf))))
          (loop (fx+ i 1))))
      out))

  (define (read-file-bytevector path)
    (let* ([port (open-file-input-port path)]
           [bv (get-bytevector-all port)])
      (close-port port)
      (if (eof-object? bv) #vu8() bv)))

  (define (file-sha256-hex path)
    ;; SHA-256 hex digest of a file using Chez-core sha256-bytevector.
    ;; Returns hex string or #f on error.
    (guard (exn [#t #f])
      (unless (file-exists? path)
        (error 'file-sha256-hex "file not found" path))
      (bv->hex (sha256-bytevector (read-file-bytevector path)))))

  (define (directory-hash dir)
    ;; Hash all files in a directory recursively, sorted by relative path.
    ;; Mirrors `find … -type f | sort | xargs sha256sum | sha256sum` but
    ;; entirely in-process — no shell, no quoting.
    (guard (exn [#t #f])
      (let* ([files (sort string<?
                          (collect-files dir (string-length dir)))]
             [parts (map (lambda (rel)
                           (let* ([full (string-append dir "/" rel)]
                                  [h (file-sha256-hex full)])
                             (string->utf8
                              (string-append h "  " rel "\n"))))
                         files)]
             [combined (apply bytevector-append parts)])
        (bv->hex (sha256-bytevector combined)))))

  (define (collect-files root prefix-len)
    ;; Returns a list of paths relative to root (no leading slash).
    (let loop ([dir root] [acc '()])
      (fold-left
        (lambda (a entry)
          (let ([full (string-append dir "/" entry)])
            (cond
              [(file-directory? full) (loop full a)]
              [else (cons (substring full (fx+ prefix-len 1)
                                     (string-length full)) a)])))
        acc
        (directory-list dir))))

  ;; ========== Single Dependency Verification ==========

  (define (verify-dependency name expected-hash path)
    ;; Verify a single dependency at path against expected hash.
    (guard (exn
      [#t (%make-verification-result name 'error expected-hash
            (if (condition? exn) (condition-message exn) "unknown error"))])
      (cond
        [(not (file-exists? path))
         (%make-verification-result name 'missing expected-hash "not found")]
        [else
         (let ([actual (if (file-directory? path)
                          (directory-hash path)
                          (file-sha256-hex path))])
           (if (and actual (string=? actual expected-hash))
             (%make-verification-result name 'ok expected-hash actual)
             (%make-verification-result name 'mismatch expected-hash
               (or actual "hash computation failed"))))])))

  ;; ========== Batch Verification ==========

  (define (verify-all-dependencies lockfile dep-dir)
    ;; Verify all entries in a lockfile against files in dep-dir.
    ;; Returns list of verification-result records.
    (map (lambda (entry)
           (let ([path (string-append dep-dir "/" (lock-entry-name entry))])
             (verify-dependency
               (lock-entry-name entry)
               (lock-entry-hash entry)
               path)))
         (lockfile-entries lockfile)))

  ;; ========== Lockfile Verification ==========

  (define (verify-lockfile! lockfile dep-dir on-mismatch)
    ;; Verify all dependencies. on-mismatch: 'abort | 'warn | 'ignore
    ;; Returns #t if all ok, #f otherwise.
    ;; Raises error on mismatch when on-mismatch is 'abort.
    (let* ([results (verify-all-dependencies lockfile dep-dir)]
           [failures (filter (lambda (r)
                              (not (eq? (verification-result-status r) 'ok)))
                            results)])
      (cond
        [(null? failures) #t]
        [(eq? on-mismatch 'abort)
         (error 'verify-lockfile! "dependency verification failed"
           (map (lambda (r)
                  (list (verification-result-name r)
                        (verification-result-status r)))
                failures))]
        [(eq? on-mismatch 'warn)
         #f]
        [else #f])))

  (define (lockfile-verify-report lockfile dep-dir)
    ;; Generate a human-readable report of verification results.
    ;; Returns an alist: ((total . N) (ok . N) (failed . N) (details . results))
    (let* ([results (verify-all-dependencies lockfile dep-dir)]
           [ok-count (length (filter (lambda (r) (eq? (verification-result-status r) 'ok)) results))]
           [fail-count (- (length results) ok-count)])
      (list (cons 'total (length results))
            (cons 'ok ok-count)
            (cons 'failed fail-count)
            (cons 'details results))))

) ;; end library
