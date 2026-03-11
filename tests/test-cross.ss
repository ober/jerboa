#!chezscheme
;;; Tests for (jerboa cross) -- Cross-Compilation Utilities

(import (chezscheme)
        (jerboa cross))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(printf "--- Phase 3c: Cross-Compilation ---~%~%")

;;; ======== Cross Config Creation ========

(test "make-cross-config"
  (let ([cfg (make-cross-config 'linux 'x86-64 #f "gcc" '())])
    (cross-config? cfg))
  #t)

(test "cross-config? false"
  (cross-config? "nope")
  #f)

(test "cross-config-target-os"
  (cross-config-target-os (make-cross-config 'linux 'x86-64 #f "gcc" '()))
  'linux)

(test "cross-config-target-arch"
  (cross-config-target-arch (make-cross-config 'linux 'x86-64 #f "gcc" '()))
  'x86-64)

(test "cross-config-sysroot"
  (cross-config-sysroot (make-cross-config 'linux 'aarch64 "/sysroot" "aarch64-cc" '()))
  "/sysroot")

(test "cross-config-cc"
  (cross-config-cc (make-cross-config 'linux 'aarch64 #f "aarch64-linux-gnu-gcc" '()))
  "aarch64-linux-gnu-gcc")

(test "cross-config-cflags"
  (cross-config-cflags (make-cross-config 'linux 'x86-64 #f "gcc" '("-O2")))
  '("-O2"))

;;; ======== OS Predicates ========

(test "target-os-linux?"
  (target-os-linux? (make-cross-config 'linux 'x86-64 #f "gcc" '()))
  #t)

(test "target-os-linux? false"
  (target-os-linux? (make-cross-config 'macos 'x86-64 #f "clang" '()))
  #f)

(test "target-os-macos?"
  (target-os-macos? (make-cross-config 'macos 'x86-64 #f "clang" '()))
  #t)

(test "target-os-windows?"
  (target-os-windows? (make-cross-config 'windows 'x86-64 #f "x86_64-w64-mingw32-gcc" '()))
  #t)

;;; ======== Arch Predicates ========

(test "target-arch-x86-64?"
  (target-arch-x86-64? (make-cross-config 'linux 'x86-64 #f "gcc" '()))
  #t)

(test "target-arch-aarch64?"
  (target-arch-aarch64? (make-cross-config 'linux 'aarch64 #f "gcc" '()))
  #t)

(test "target-arch-riscv64?"
  (target-arch-riscv64? (make-cross-config 'linux 'riscv64 #f "gcc" '()))
  #t)

(test "target-arch-x86-64? false"
  (target-arch-x86-64? (make-cross-config 'linux 'aarch64 #f "gcc" '()))
  #f)

;;; ======== Validation ========

(test "cross-config-valid? true"
  (cross-config-valid? (make-cross-config 'linux 'x86-64 #f "gcc" '()))
  #t)

(test "cross-config-valid? bad os"
  (cross-config-valid? (make-cross-config 'haiku 'x86-64 #f "gcc" '()))
  #f)

(test "cross-config-valid? bad arch"
  (cross-config-valid? (make-cross-config 'linux 'sparc #f "gcc" '()))
  #f)

;;; ======== Host Detection ========

(test "detect-host-config returns cross-config"
  (cross-config? (detect-host-config))
  #t)

(test "detect-host-config valid"
  (cross-config-valid? (detect-host-config))
  #t)

;;; ======== ABI and Platform ========

(test "abi-name linux x86-64"
  (abi-name (make-cross-config 'linux 'x86-64 #f "gcc" '()))
  "x86_64-linux-gnu")

(test "abi-name macos aarch64"
  (abi-name (make-cross-config 'macos 'aarch64 #f "clang" '()))
  "aarch64-apple-darwin")

(test "abi-name windows x86-64"
  (abi-name (make-cross-config 'windows 'x86-64 #f "gcc" '()))
  "x86_64-w64-mingw32")

(test "endianness-for-target x86-64"
  (endianness-for-target (make-cross-config 'linux 'x86-64 #f "gcc" '()))
  'little)

(test "pointer-size-for-target x86-64"
  (pointer-size-for-target (make-cross-config 'linux 'x86-64 #f "gcc" '()))
  8)

(test "platform-string"
  (platform-string (make-cross-config 'linux 'x86-64 #f "gcc" '()))
  "x86-64/linux")

;;; ======== cc-flags-for-target ========

(test "cc-flags-for-target basic"
  (let ([flags (cc-flags-for-target (make-cross-config 'linux 'aarch64 #f "gcc" '()))])
    (member "--target=aarch64-linux-gnu" flags))
  '("--target=aarch64-linux-gnu"))

(test "cc-flags-for-target with sysroot"
  (let ([flags (cc-flags-for-target
                 (make-cross-config 'linux 'aarch64 "/my/sysroot" "gcc" '()))])
    (if (and (member "--target=aarch64-linux-gnu" flags)
             (member "--sysroot=/my/sysroot" flags))
      #t #f))
  #t)

(test "cc-flags-for-target includes extra cflags"
  (let ([flags (cc-flags-for-target
                 (make-cross-config 'linux 'x86-64 #f "gcc" '("-O2" "-march=native")))])
    (if (and (member "-O2" flags) (member "-march=native" flags))
      #t #f))
  #t)

;;; ======== normalize-path-sep ========

(test "normalize-path-sep linux no change"
  (normalize-path-sep "/usr/local/bin" (make-cross-config 'linux 'x86-64 #f "gcc" '()))
  "/usr/local/bin")

(test "normalize-path-sep windows converts slashes"
  (normalize-path-sep "/usr/local/bin" (make-cross-config 'windows 'x86-64 #f "gcc" '()))
  "\\usr\\local\\bin")

;;; Summary

(printf "~%Cross-Compilation: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
