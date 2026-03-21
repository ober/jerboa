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

  (define (file-sha256-hex path)
    ;; Compute SHA-256 hex digest of a file using sha256sum.
    ;; Returns hex string or #f on error.
    (guard (exn [#t #f])
      (unless (file-exists? path)
        (error 'file-sha256-hex "file not found" path))
      (let-values ([(to-stdin from-stdout from-stderr pid)
                    (open-process-ports
                      (string-append "sha256sum " (shell-quote path))
                      (buffer-mode block)
                      (make-transcoder (utf-8-codec)))])
        (close-port to-stdin)
        (let ([output (get-string-all from-stdout)])
          (close-port from-stdout)
          (close-port from-stderr)
          (and (string? output)
               (>= (string-length output) 64)
               (substring output 0 64))))))

  (define (shell-quote s)
    ;; Basic shell quoting — wrap in single quotes, escape existing quotes.
    (string-append "'"
      (let loop ([i 0] [out '()])
        (if (= i (string-length s))
          (list->string (reverse out))
          (let ([c (string-ref s i)])
            (if (char=? c #\')
              (loop (+ i 1) (append (reverse (string->list "'\\''")) out))
              (loop (+ i 1) (cons c out))))))
      "'"))

  (define (directory-hash dir)
    ;; Hash all files in a directory recursively.
    ;; Returns a combined hex hash or #f.
    (guard (exn [#t #f])
      (let-values ([(to-stdin from-stdout from-stderr pid)
                    (open-process-ports
                      (string-append "find " (shell-quote dir)
                                     " -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum")
                      (buffer-mode block)
                      (make-transcoder (utf-8-codec)))])
        (close-port to-stdin)
        (let ([output (get-string-all from-stdout)])
          (close-port from-stdout)
          (close-port from-stderr)
          (and (string? output)
               (>= (string-length output) 64)
               (substring output 0 64))))))

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
