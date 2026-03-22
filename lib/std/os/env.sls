#!chezscheme
;;; :std/os/env -- Environment variable access

(library (std os env)
  (export
    getenv
    setenv
    unsetenv)

  (import (chezscheme))

  ;; Chez Scheme already has getenv. We re-export it plus provide setenv/unsetenv
  ;; via putenv.

  (define (setenv name value)
    (putenv name value))

  ;; Chez's putenv with empty string sets to "", it does NOT unset.
  ;; On POSIX systems, use the C unsetenv(3) function via FFI.
  (define c-unsetenv
    (guard (exn [#t #f])
      (foreign-procedure "unsetenv" (string) int)))

  (define (unsetenv name)
    (if c-unsetenv
      (c-unsetenv name)
      ;; Fallback: putenv with empty value (imperfect but best available)
      (putenv name "")))

  ) ;; end library
