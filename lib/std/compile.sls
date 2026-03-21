#!chezscheme
;;; (std compile) — Compilation utilities
;;;
;;; Re-exports Chez's compilation infrastructure for build systems.

(library (std compile)
  (export compile-file compile-whole-program compile-to-port
          optimize-level generate-wpo-files
          compile-imported-libraries
          compile-library compile-program)

  (import (chezscheme))

  ;; All exports are Chez built-ins, re-exported for:
  ;;   compile-file: compile .sls to .so
  ;;   compile-whole-program: whole-program optimization from .wpo
  ;;   compile-to-port: compile to binary output port
  ;;   optimize-level: parameter (0-3)
  ;;   generate-wpo-files: parameter (bool)
  ;;   compile-imported-libraries: parameter (bool)
  ;;   compile-library: compile a single library file
  ;;   compile-program: compile a program file

) ;; end library
