#!chezscheme
;;; (std cli print-exit) — Print and exit utilities
;;;
;;; Convenience procedures for CLI tools: formatted output to stdout/stderr
;;; followed by process exit, plus warning helpers.

(library (std cli print-exit)
  (export
    print-exit print-error-exit
    exit/success exit/failure
    die warn-and-continue)

  (import (chezscheme))

  (define (print-exit fmt . args)
    ;; Format and print to stdout, then exit 0.
    (apply fprintf (console-output-port) fmt args)
    (newline (console-output-port))
    (flush-output-port (console-output-port))
    (exit 0))

  (define (print-error-exit fmt . args)
    ;; Format and print to stderr, then exit 1.
    (apply fprintf (console-error-port) fmt args)
    (newline (console-error-port))
    (flush-output-port (console-error-port))
    (exit 1))

  (define (exit/success)
    ;; Exit with status 0.
    (exit 0))

  (define (exit/failure . rest)
    ;; Exit with status 1. If a message string is given, print it to stderr.
    (when (pair? rest)
      (display (car rest) (console-error-port))
      (newline (console-error-port))
      (flush-output-port (console-error-port)))
    (exit 1))

  (define (die fmt . args)
    ;; Format and print to stderr, then exit 1. Alias for print-error-exit.
    (apply fprintf (console-error-port) fmt args)
    (newline (console-error-port))
    (flush-output-port (console-error-port))
    (exit 1))

  (define (warn-and-continue fmt . args)
    ;; Format and print warning to stderr, continue execution.
    (apply fprintf (console-error-port) fmt args)
    (newline (console-error-port))
    (flush-output-port (console-error-port)))

) ;; end library
