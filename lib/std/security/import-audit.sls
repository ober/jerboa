#!chezscheme
;;; (std security import-audit) — Build-time import policy enforcement
;;;
;;; Scans .sls source files for direct (chezscheme) imports that bypass
;;; capability-gated wrapper modules. Reports violations for use in
;;; build pipelines and CI systems.
;;;
;;; AI-generated code can bypass the capability system simply by importing
;;; (chezscheme) directly and calling system, open-output-file, etc.
;;; This module detects that pattern at build time.

(library (std security import-audit)
  (export
    audit-imports-file
    audit-imports-directory
    import-violation?
    import-violation-file
    import-violation-line
    import-violation-import-spec

    ;; Policy
    *forbidden-imports*
    *trusted-modules*)

  (import (chezscheme))

  ;; ========== Configuration ==========

  ;; Import specs that should not appear in user code.
  ;; Trusted infrastructure modules (security/, jerboa/) are exempt.
  (define *forbidden-imports*
    (make-parameter
      '((chezscheme)
        (scheme))))

  ;; Module path prefixes that are allowed to use forbidden imports.
  ;; These are the trusted infrastructure modules.
  (define *trusted-modules*
    (make-parameter
      '("lib/jerboa/"
        "lib/std/security/"
        "lib/std/crypto/"
        "lib/std/actor/")))

  ;; ========== Violation Record ==========

  (define-record-type import-violation-rec
    (fields
      (immutable file)
      (immutable line)
      (immutable import-spec))
    (sealed #t))

  (define (import-violation? x) (import-violation-rec? x))
  (define (import-violation-file v) (import-violation-rec-file v))
  (define (import-violation-line v) (import-violation-rec-line v))
  (define (import-violation-import-spec v) (import-violation-rec-import-spec v))

  ;; ========== File Scanning ==========

  (define (audit-imports-file filepath)
    ;; Scan a single .sls file for forbidden imports.
    ;; Returns a list of import-violation records.
    ;; Trusted modules (matching *trusted-modules* prefixes) are exempt.
    (if (trusted-path? filepath)
      '()
      (let ([violations '()]
            [port (open-input-file filepath)])
        (let loop ([line-num 1])
          (let ([line (get-line port)])
            (if (eof-object? line)
              (begin (close-port port) (reverse violations))
              (begin
                (for-each
                  (lambda (forbidden)
                    (let ([pattern (format "(import~a" (format " ~a" forbidden))])
                      ;; Also check multi-line import: just (chezscheme) on its own line
                      (when (or (string-contains-ci? line (format "~a" forbidden))
                                (string-contains-ci? line (format "(import ~a" forbidden)))
                        ;; Verify it's actually an import context (not a comment)
                        (let ([trimmed (string-trim-left line)])
                          (unless (and (> (string-length trimmed) 0)
                                       (char=? (string-ref trimmed 0) #\;))
                            (set! violations
                              (cons (make-import-violation-rec
                                      filepath line-num forbidden)
                                    violations)))))))
                  (*forbidden-imports*))
                (loop (+ line-num 1)))))))))

  (define (audit-imports-directory dirpath)
    ;; Scan all .sls files under a directory for forbidden imports.
    ;; Returns a list of import-violation records.
    (let ([violations '()])
      (for-each
        (lambda (filepath)
          (let ([file-violations (audit-imports-file filepath)])
            (set! violations (append violations file-violations))))
        (find-sls-files dirpath))
      violations))

  ;; ========== Helpers ==========

  (define (trusted-path? filepath)
    ;; Is this file path under a trusted module prefix?
    (exists (lambda (prefix)
              (let ([plen (string-length prefix)]
                    [flen (string-length filepath)])
                (and (>= flen plen)
                     (string=? (substring filepath 0 (min plen flen)) prefix))))
            (*trusted-modules*)))

  (define (string-contains-ci? haystack needle)
    ;; Case-insensitive substring search.
    (let ([hlen (string-length haystack)]
          [nlen (string-length needle)])
      (let lp ([i 0])
        (cond
          [(> (+ i nlen) hlen) #f]
          [(string-ci=? (substring haystack i (+ i nlen)) needle) #t]
          [else (lp (+ i 1))]))))

  (define (string-trim-left s)
    (let ([len (string-length s)])
      (let lp ([i 0])
        (cond
          [(>= i len) ""]
          [(char-whitespace? (string-ref s i)) (lp (+ i 1))]
          [else (substring s i len)]))))

  (define (find-sls-files dirpath)
    ;; Recursively find all .sls files under dirpath.
    (let ([results '()])
      (let scan ([dir dirpath])
        (for-each
          (lambda (entry)
            (let ([full (string-append dir "/" entry)])
              (cond
                [(and (> (string-length entry) 4)
                      (string=? (substring entry (- (string-length entry) 4)
                                                 (string-length entry))
                                ".sls"))
                 (set! results (cons full results))]
                [(and (not (string=? entry "."))
                      (not (string=? entry ".."))
                      (file-directory? full))
                 (scan full)])))
          (guard (exn [#t '()])
            (directory-list dir))))
      (reverse results)))

  (define (min a b) (if (< a b) a b))

  ) ;; end library
