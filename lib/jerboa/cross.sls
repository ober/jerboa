#!chezscheme
;;; (jerboa cross) — Cross-Compilation Utilities
;;;
;;; Target OS/arch config, ABI info, and C compiler flag generation.

(library (jerboa cross)
  (export
    make-cross-config cross-config?
    cross-config-target-os cross-config-target-arch
    cross-config-sysroot cross-config-cc cross-config-cflags
    target-os-linux? target-os-macos? target-os-windows?
    target-arch-x86-64? target-arch-aarch64? target-arch-riscv64?
    detect-host-config cross-config-valid?
    cc-flags-for-target abi-name endianness-for-target
    pointer-size-for-target platform-string normalize-path-sep)

  (import (chezscheme))

  ;; ========== String search helper ==========
  (define (string-has-substring? str sub)
    ;; Returns #t if sub appears anywhere in str.
    (let ([slen (string-length str)]
          [sublen (string-length sub)])
      (if (> sublen slen)
        #f
        (let loop ([i 0])
          (cond
            [(> (+ i sublen) slen) #f]
            [(let check ([j 0])
               (cond
                 [(= j sublen) #t]
                 [(char=? (string-ref str (+ i j)) (string-ref sub j))
                  (check (+ j 1))]
                 [else #f]))
             #t]
            [else (loop (+ i 1))])))))

  ;; ========== Cross Config ==========

  (define-record-type (%cross-config make-cross-config cross-config?)
    (fields (immutable target-os   cross-config-target-os)    ;; symbol: linux macos windows
            (immutable target-arch cross-config-target-arch)  ;; symbol: x86-64 aarch64 riscv64
            (immutable sysroot     cross-config-sysroot)      ;; string path or #f
            (immutable cc          cross-config-cc)           ;; string path to C compiler
            (immutable cflags      cross-config-cflags)))     ;; list of strings

  ;; ========== Predicates ==========

  (define (target-os-linux?   cfg) (eq? (cross-config-target-os cfg)   'linux))
  (define (target-os-macos?   cfg) (eq? (cross-config-target-os cfg)   'macos))
  (define (target-os-windows? cfg) (eq? (cross-config-target-os cfg)   'windows))

  (define (target-arch-x86-64?  cfg) (eq? (cross-config-target-arch cfg) 'x86-64))
  (define (target-arch-aarch64? cfg) (eq? (cross-config-target-arch cfg) 'aarch64))
  (define (target-arch-riscv64? cfg) (eq? (cross-config-target-arch cfg) 'riscv64))

  ;; ========== Host Detection ==========

  (define (machine-type->os mt)
    ;; Detect OS from Chez machine-type symbol.
    ;; e.g., a6le = x86-64 linux, ta6osx = x86-64 macos threaded
    (let ([s (symbol->string mt)])
      (cond
        [(or (string-has-substring? s "le")
             (string-has-substring? s "l3")) 'linux]
        [(or (string-has-substring? s "osx")
             (string-has-substring? s "darwin")) 'macos]
        [(or (string-has-substring? s "nt")
             (string-has-substring? s "win")) 'windows]
        [else 'linux])))  ;; default

  (define (machine-type->arch mt)
    ;; Detect arch from Chez machine-type symbol.
    ;; a6 = x86-64, arm64 = aarch64, rv = riscv64
    (let ([s (symbol->string mt)])
      (cond
        [(string-has-substring? s "arm64") 'aarch64]
        [(string-has-substring? s "arm")   'aarch64]
        [(string-has-substring? s "a6")    'x86-64]
        [(string-has-substring? s "rv")    'riscv64]
        [(string-has-substring? s "i3")    'x86-64]  ;; treat i386 as x86-64 for simplicity
        [else 'x86-64])))  ;; default

  (define (detect-host-config)
    ;; Return a cross-config for the current host.
    (let* ([mt (machine-type)]
           [os   (machine-type->os mt)]
           [arch (machine-type->arch mt)])
      (make-cross-config os arch #f "cc" '())))

  ;; ========== Validation ==========

  (define (cross-config-valid? cfg)
    ;; Check that OS and arch are known values.
    (and (member (cross-config-target-os cfg)   '(linux macos windows))
         (member (cross-config-target-arch cfg) '(x86-64 aarch64 riscv64))
         #t))

  ;; ========== Compiler Flags ==========

  (define (cc-flags-for-target cfg)
    ;; Generate GCC/Clang cross-compilation flags.
    (let ([os   (cross-config-target-os cfg)]
          [arch (cross-config-target-arch cfg)]
          [sr   (cross-config-sysroot cfg)]
          [extra (cross-config-cflags cfg)])
      (let* ([triple (abi-name cfg)]
             [base (list (string-append "--target=" triple))])
        (append
          base
          (if sr (list (string-append "--sysroot=" sr)) '())
          extra))))

  ;; ========== ABI / Platform Info ==========

  (define (abi-name cfg)
    ;; Returns GNU/LLVM target triple string.
    (let ([os   (cross-config-target-os cfg)]
          [arch (cross-config-target-arch cfg)])
      (let ([arch-str (case arch
                        [(x86-64)  "x86_64"]
                        [(aarch64) "aarch64"]
                        [(riscv64) "riscv64"]
                        [else (symbol->string arch)])]
            [os-str   (case os
                        [(linux)   "linux-gnu"]
                        [(macos)   "apple-darwin"]
                        [(windows) "w64-mingw32"]
                        [else (symbol->string os)])])
        (string-append arch-str "-" os-str))))

  (define (endianness-for-target cfg)
    ;; Returns 'little or 'big.
    ;; All currently supported arches are little-endian.
    (case (cross-config-target-arch cfg)
      [(x86-64 aarch64 riscv64) 'little]
      [else 'little]))

  (define (pointer-size-for-target cfg)
    ;; Returns 4 or 8.
    (case (cross-config-target-arch cfg)
      [(x86-64 aarch64 riscv64) 8]
      [else 8]))

  (define (platform-string cfg)
    ;; Human-readable platform description.
    (let ([os   (cross-config-target-os cfg)]
          [arch (cross-config-target-arch cfg)])
      (format "~a/~a" arch os)))

  (define (normalize-path-sep path cfg)
    ;; Convert / to \\ on Windows targets.
    (if (target-os-windows? cfg)
      (list->string
        (map (lambda (c) (if (char=? c #\/) #\\ c))
             (string->list path)))
      path))

) ;; end library
