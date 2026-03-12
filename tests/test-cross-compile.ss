#!chezscheme
;;; Tests for (std build cross) — Cross-Compilation Pipeline

(import (chezscheme) (std build cross))

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

(printf "--- (std build cross) tests ---~%")

;;; ======== Platform Record ========

(printf "~%-- Platform Record --~%")

(test "target-platform? for built-in platform"
  (target-platform? platform/x86_64-linux)
  #t)

(test "target-platform? false for non-platform"
  (target-platform? "not a platform")
  #f)

(test "target-platform? false for list"
  (target-platform? '(x86_64 linux))
  #f)

(test "make-target-platform creates platform"
  (target-platform? (make-target-platform 'custom-os 'arm64 'linux 'gnu))
  #t)

;;; ======== Built-in Platforms ========

(printf "~%-- Built-in Platforms --~%")

(test "platform/x86_64-linux name"
  (platform-name platform/x86_64-linux)
  'x86_64-linux)

(test "platform/x86_64-linux arch"
  (platform-arch platform/x86_64-linux)
  'x86_64)

(test "platform/x86_64-linux os"
  (platform-os platform/x86_64-linux)
  'linux)

(test "platform/x86_64-linux abi"
  (platform-abi platform/x86_64-linux)
  'gnu)

(test "platform/arm64-linux name"
  (platform-name platform/arm64-linux)
  'arm64-linux)

(test "platform/arm64-linux arch"
  (platform-arch platform/arm64-linux)
  'arm64)

(test "platform/arm64-linux os"
  (platform-os platform/arm64-linux)
  'linux)

(test "platform/riscv64-linux name"
  (platform-name platform/riscv64-linux)
  'riscv64-linux)

(test "platform/riscv64-linux arch"
  (platform-arch platform/riscv64-linux)
  'riscv64)

(test "platform/x86_64-macos name"
  (platform-name platform/x86_64-macos)
  'x86_64-macos)

(test "platform/x86_64-macos os"
  (platform-os platform/x86_64-macos)
  'macos)

(test "platform/arm64-macos name"
  (platform-name platform/arm64-macos)
  'arm64-macos)

(test "platform/arm64-macos abi"
  (platform-abi platform/arm64-macos)
  'none)

;;; ======== Host Detection ========

(printf "~%-- Host Detection --~%")

(test "current-platform returns a platform"
  (target-platform? (current-platform))
  #t)

(test "detect-platform returns a platform"
  (target-platform? (detect-platform))
  #t)

(test "current-platform has valid arch"
  (and (memq (platform-arch (current-platform)) '(x86_64 arm64 riscv64)) #t)
  #t)

(test "current-platform has valid os"
  (and (memq (platform-os (current-platform)) '(linux macos windows)) #t)
  #t)

;;; ======== Cross-Compilation Config ========

(printf "~%-- Cross-Compilation Config --~%")

(let ([cfg (make-cross-config platform/x86_64-linux
                               platform/arm64-linux
                               "aarch64-linux-gnu-gcc"
                               "/sysroot/arm"
                               '("-O2" "-static"))])

  (test "cross-config? true"
    (cross-config? cfg)
    #t)

  (test "cross-config-host"
    (platform-name (cross-config-host cfg))
    'x86_64-linux)

  (test "cross-config-target"
    (platform-name (cross-config-target cfg))
    'arm64-linux)

  (test "cross-config-cc"
    (cross-config-cc cfg)
    "aarch64-linux-gnu-gcc")

  (test "cross-config-sysroot"
    (cross-config-sysroot cfg)
    "/sysroot/arm")

  (test "cross-config-extra-flags"
    (cross-config-extra-flags cfg)
    '("-O2" "-static")))

(test "cross-config? false for non-config"
  (cross-config? 'nope)
  #f)

;;; ======== Platform Utilities ========

(printf "~%-- Platform Utilities --~%")

(test "platform->string x86_64-linux"
  (platform->string platform/x86_64-linux)
  "x86_64-linux")

(test "platform->string arm64-linux"
  (platform->string platform/arm64-linux)
  "arm64-linux")

(test "string->platform x86_64-linux"
  (platform-name (string->platform "x86_64-linux"))
  'x86_64-linux)

(test "string->platform arm64-linux"
  (platform-name (string->platform "arm64-linux"))
  'arm64-linux)

(test "string->platform riscv64-linux"
  (platform-name (string->platform "riscv64-linux"))
  'riscv64-linux)

(test "string->platform x86_64-macos"
  (platform-name (string->platform "x86_64-macos"))
  'x86_64-macos)

(test "string->platform arm64-macos"
  (platform-name (string->platform "arm64-macos"))
  'arm64-macos)

(test "string->platform unknown returns #f"
  (string->platform "sparc-solaris")
  #f)

(test "platform=? same platform"
  (platform=? platform/x86_64-linux platform/x86_64-linux)
  #t)

(test "platform=? different platforms"
  (platform=? platform/x86_64-linux platform/arm64-linux)
  #f)

(test "platform=? non-platform returns #f"
  (platform=? platform/x86_64-linux "string")
  #f)

;;; ======== Toolchain Detection ========

(printf "~%-- Toolchain Detection --~%")

(test "find-cross-compiler returns string or #f"
  (let ([cc (find-cross-compiler 'x86_64)])
    (or (not cc) (string? cc)))
  #t)

(test "cross-compiler-available? returns boolean"
  (boolean? (cross-compiler-available? 'arm64))
  #t)

(test "native-platform? for current platform"
  (native-platform? (current-platform))
  #t)

(test "native-platform? false for non-native"
  ;; arm64-linux is unlikely to be the native platform on this x86 machine
  (let ([p (current-platform)])
    ;; Create a different platform to test against
    (let ([other (make-target-platform 'fake-platform 'riscv64 'windows 'gnu)])
      (native-platform? other)))
  #f)

;;; ======== Build Matrix ========

(printf "~%-- Build Matrix --~%")

(let ([matrix (make-build-matrix '("main.c" "lib.c")
                                  (list platform/x86_64-linux platform/arm64-linux))])
  (test "make-build-matrix works"
    (record? matrix)
    #t)

  (run-build-matrix matrix)

  (test "build-matrix-results returns list"
    (list? (build-matrix-results matrix))
    #t)

  (test "build-matrix-results has entry per platform"
    (= (length (build-matrix-results matrix)) 2)
    #t)

  (test "build-matrix-results contains platform names"
    (let ([names (map car (build-matrix-results matrix))])
      (and (member 'x86_64-linux names) (member 'arm64-linux names) #t))
    #t))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
