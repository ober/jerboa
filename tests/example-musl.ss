#!/usr/bin/env scheme-script
#!chezscheme

;;; Example: Building a static binary with musl
;;;
;;; This demonstrates how to use the (jerboa build musl) library
;;; to create fully static executables with zero runtime dependencies.

(import (chezscheme)
        (jerboa build)
        (jerboa build musl))

;; Display header
(display "====================================\n")
(display "Jerboa musl Static Build Example\n")
(display "====================================\n\n")

;; Step 1: Check if musl is available
(display "1. Checking musl toolchain...\n")
(if (musl-available?)
    (begin
      (display "   ✓ musl-gcc found: ")
      (display (musl-gcc-path))
      (newline))
    (begin
      (display "   ✗ musl-gcc not found\n")
      (display "   Install: sudo apt install musl-tools\n")
      (exit 1)))

;; Step 2: Validate setup
(display "\n2. Validating musl setup...\n")
(let ([result (validate-musl-setup)])
  (if (eq? (car result) 'ok)
      (begin
        (display "   ✓ ")
        (display (cdr result))
        (newline))
      (begin
        (display "   ✗ ")
        (display (cdr result))
        (newline)
        (display "\n   Note: You may need to build Chez Scheme with musl.\n")
        (display "   See: support/musl-chez-build.sh\n")
        (exit 0))))

;; Step 3: Show configuration
(display "\n3. Configuration:\n")
(display "   musl Chez prefix: ")
(display (musl-chez-prefix))
(newline)

(display "   musl sysroot: ")
(display (musl-sysroot))
(newline)

;; Step 4: Show CRT objects
(display "\n4. CRT objects:\n")
(for-each
  (lambda (obj)
    (display "   - ")
    (display obj)
    (newline))
  (musl-crt-objects))

;; Step 5: Example build command
(display "\n5. Example usage:\n\n")
(display "(import (jerboa build musl))\n\n")
(display "(build-musl-binary \"myapp.sls\" \"myapp\"\n")
(display "  'optimize-level: 2\n")
(display "  'verbose: #t)\n\n")

(display "This creates a fully static binary with:\n")
(display "  - Zero runtime dependencies\n")
(display "  - Works on any Linux distro\n")
(display "  - Alpine/musl native\n")
(display "  - Container-friendly (FROM scratch)\n\n")

;; Step 6: Cross-compilation info
(display "6. Cross-compilation targets:\n")
(for-each
  (lambda (arch)
    (display "   - ")
    (display arch)
    (display ": ")
    (display (if (musl-cross-available? arch) "available" "not found"))
    (newline))
  '(x86-64 aarch64 riscv64 armhf))

(display "\n====================================\n")
(display "Setup complete!\n")
(display "====================================\n")
