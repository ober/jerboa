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

  (define (unsetenv name)
    ;; Chez putenv with empty value effectively unsets on most systems
    (putenv name ""))

  ) ;; end library
