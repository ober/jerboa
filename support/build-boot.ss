#!chezscheme
;;; build-boot.ss — Compile a Jerboa script with Whole-Program Optimization
;;;
;;; Usage:
;;;   scheme --libdirs <libdirs> --script build-boot.ss <entry.ss> <output.so> [<obj-dir>]
;;;
;;; <obj-dir>  Optional writable directory for compiled library .so output.
;;;            Use when the source lib directory is read-only (e.g. Docker bind mounts).
;;;            If omitted, compiled output goes alongside the source files.
;;;
;;; Produces a single WPO-optimised .so containing the compiled program +
;;; all imported libraries, ready for embedding in a static binary.

(import (chezscheme))

(define (string-suffix? str suffix)
  (let ([slen (string-length str)]
        [xlen (string-length suffix)])
    (and (>= slen xlen)
         (string=? (substring str (- slen xlen) slen) suffix))))

(let ([args (cdr (command-line))])  ;; strip argv[0] (build-boot.ss path)
  (when (< (length args) 2)
    (display "Usage: build-boot.ss <entry.ss> <output.so> [<obj-dir>]\n"
             (current-error-port))
    (exit 1))

  (let ([entry-file (list-ref args 0)]
        [output-so  (list-ref args 1)]
        [obj-dir    (and (>= (length args) 3) (list-ref args 2))])

    ;; When a separate object directory is requested, redirect compiled library
    ;; output there while keeping source lookup in the original lib directories.
    ;; This lets us compile against a read-only source tree (e.g. Docker :ro mount).
    (when obj-dir
      (library-directories
        (map (lambda (pair)
               (cons (if (pair? pair) (car pair) pair) obj-dir))
             (library-directories))))

    ;; Enable WPO
    (compile-imported-libraries #t)
    (generate-wpo-files #t)

    (let* ([base (if (string-suffix? entry-file ".ss")
                   (substring entry-file 0 (- (string-length entry-file) 3))
                   entry-file)]
           [wpo-file (string-append base ".wpo")])

      (display (format "  compile-program ~a ...\n" entry-file) (current-error-port))
      (compile-program entry-file)

      (display (format "  compile-whole-program ~a -> ~a ...\n" wpo-file output-so)
               (current-error-port))
      ;; NOTE: see single-binary.md §13 — WPO can eliminate identifier-syntax cells.
      ;; If startup crashes with unbound-variable, try: (system (format "cp ~a.so ~a" base output-so))
      (compile-whole-program wpo-file output-so #t)

      (display "  build-boot.ss done.\n" (current-error-port)))))
