#!chezscheme
;;; build.ss — Compile all Jerboa libraries to .so files
;;; Usage: scheme --libdirs lib --script support/build.ss

(import (chezscheme))

(compile-imported-libraries #t)
(generate-wpo-files #t)

;; Import the top-level libraries to trigger compilation of everything they depend on.
;; Errors during compilation of optional/platform-specific libraries are non-fatal.
(define libraries-to-compile
  '((jerboa reader)
    (jerboa core)
    (jerboa runtime)
    (jerboa ffi)
    (jerboa modules)
    (jerboa build)))

(define compiled 0)
(define skipped 0)

(for-each
  (lambda (lib)
    (guard (e [#t
               (set! skipped (+ skipped 1))
               (display "  SKIP: ")
               (write lib)
               (display " — ")
               (display (condition-message e))
               (newline)])
      (eval `(import ,lib))
      (set! compiled (+ compiled 1))))
  libraries-to-compile)

(printf "\nBuild complete: ~a compiled, ~a skipped\n" compiled skipped)
