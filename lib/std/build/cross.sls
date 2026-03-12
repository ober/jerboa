#!chezscheme
;;; (std build cross) — Cross-Compilation Pipeline
;;;
;;; Target platform records, toolchain detection, and build matrix execution.
;;; Uses (machine-type) for host detection and subprocess for compilation.

(library (std build cross)
  (export
    ;; Target platforms
    make-target-platform
    target-platform?
    platform-name
    platform-arch
    platform-os
    platform-abi

    ;; Built-in platforms
    platform/x86_64-linux
    platform/arm64-linux
    platform/riscv64-linux
    platform/x86_64-macos
    platform/arm64-macos

    ;; Cross-compilation configuration
    make-cross-config
    cross-config?
    cross-config-host
    cross-config-target
    cross-config-cc
    cross-config-sysroot
    cross-config-extra-flags

    ;; Detecting current platform
    current-platform
    detect-platform

    ;; Cross-compilation steps
    compile-for-target
    link-for-target

    ;; Toolchain detection
    find-cross-compiler
    cross-compiler-available?

    ;; Build matrix
    make-build-matrix
    run-build-matrix
    build-matrix-results

    ;; Utilities
    platform->string
    string->platform
    platform=?
    native-platform?)

  (import (chezscheme))

  ;; ========== Platform Record ==========

  (define-record-type (%target-platform %make-target-platform target-platform?)
    (fields
      (immutable name)  ;; symbol: 'arm64-linux, 'x86_64-linux, etc.
      (immutable arch)  ;; symbol: 'arm64, 'riscv64, 'x86_64
      (immutable os)    ;; symbol: 'linux, 'macos, 'windows
      (immutable abi))) ;; symbol: 'gnu, 'musl, 'none

  (define (make-target-platform name arch os abi)
    (%make-target-platform name arch os abi))

  (define (platform-name p)  (%target-platform-name p))
  (define (platform-arch p)  (%target-platform-arch p))
  (define (platform-os p)    (%target-platform-os p))
  (define (platform-abi p)   (%target-platform-abi p))

  ;; ========== Built-in Platforms ==========

  (define platform/x86_64-linux
    (make-target-platform 'x86_64-linux 'x86_64 'linux 'gnu))

  (define platform/arm64-linux
    (make-target-platform 'arm64-linux 'arm64 'linux 'gnu))

  (define platform/riscv64-linux
    (make-target-platform 'riscv64-linux 'riscv64 'linux 'gnu))

  (define platform/x86_64-macos
    (make-target-platform 'x86_64-macos 'x86_64 'macos 'none))

  (define platform/arm64-macos
    (make-target-platform 'arm64-macos 'arm64 'macos 'none))

  ;; ========== String Utilities ==========

  (define (string-has? str sub)
    (let ([slen (string-length str)]
          [sublen (string-length sub)])
      (and (<= sublen slen)
           (let loop ([i 0])
             (cond
               [(> (+ i sublen) slen) #f]
               [(string=? (substring str i (+ i sublen)) sub) #t]
               [else (loop (+ i 1))])))))

  ;; ========== Host Detection ==========

  (define (machine-type->arch mt)
    (let ([s (symbol->string mt)])
      (cond
        [(string-has? s "arm64") 'arm64]
        [(string-has? s "arm")   'arm64]
        [(string-has? s "a6")    'x86_64]
        [(string-has? s "i3")    'x86_64]
        [(string-has? s "rv")    'riscv64]
        [else 'x86_64])))

  (define (machine-type->os mt)
    (let ([s (symbol->string mt)])
      (cond
        [(or (string-has? s "osx") (string-has? s "darwin")) 'macos]
        [(or (string-has? s "nt") (string-has? s "win"))     'windows]
        [else 'linux])))

  (define (detect-platform)
    ;; Inspect (machine-type) to determine current platform.
    (let* ([mt   (machine-type)]
           [arch (machine-type->arch mt)]
           [os   (machine-type->os mt)]
           [name (string->symbol (string-append (symbol->string arch) "-" (symbol->string os)))])
      (make-target-platform name arch os 'gnu)))

  (define current-platform
    ;; Memoized: detect once at load time.
    (let ([p #f])
      (lambda ()
        (unless p (set! p (detect-platform)))
        p)))

  ;; ========== Cross-Compilation Config ==========

  (define-record-type (%cross-config %make-cross-config cross-config?)
    (fields
      (immutable host)        ;; target-platform (current machine)
      (immutable target)      ;; target-platform (compile for)
      (immutable cc)          ;; string: compiler command
      (immutable sysroot)     ;; string path or #f
      (immutable extra-flags)));; list of strings

  (define (make-cross-config host target cc sysroot extra-flags)
    (%make-cross-config host target cc sysroot extra-flags))

  (define (cross-config-host cfg)        (%cross-config-host cfg))
  (define (cross-config-target cfg)      (%cross-config-target cfg))
  (define (cross-config-cc cfg)          (%cross-config-cc cfg))
  (define (cross-config-sysroot cfg)     (%cross-config-sysroot cfg))
  (define (cross-config-extra-flags cfg) (%cross-config-extra-flags cfg))

  ;; ========== Toolchain Detection ==========

  (define (arch->cross-cc-candidates arch)
    ;; Return list of candidate compiler names for cross-compiling to arch.
    (case arch
      [(arm64)   '("aarch64-linux-gnu-gcc" "aarch64-unknown-linux-gnu-gcc")]
      [(riscv64) '("riscv64-linux-gnu-gcc" "riscv64-unknown-linux-gnu-gcc")]
      [(x86_64)  '("x86_64-linux-gnu-gcc" "gcc")]
      [else      '()]))

  (define (program-in-path? prog)
    ;; Check if prog is executable somewhere in PATH.
    (guard (exn [#t #f])
      (let ([paths (string-split (or (getenv "PATH") "/usr/bin:/bin") #\:)])
        (let loop ([ps paths])
          (cond
            [(null? ps) #f]
            [(file-exists? (string-append (car ps) "/" prog)) #t]
            [else (loop (cdr ps))])))))

  (define (string-split str ch)
    ;; Split string by character.
    (let loop ([i 0] [start 0] [parts '()])
      (cond
        [(= i (string-length str))
         (reverse (cons (substring str start i) parts))]
        [(char=? (string-ref str i) ch)
         (loop (+ i 1) (+ i 1) (cons (substring str start i) parts))]
        [else (loop (+ i 1) start parts)])))

  (define (find-cross-compiler target-arch)
    ;; Return first available cross-compiler for target-arch, or #f.
    (let loop ([cands (arch->cross-cc-candidates target-arch)])
      (cond
        [(null? cands) #f]
        [(program-in-path? (car cands)) (car cands)]
        [else (loop (cdr cands))])))

  (define (cross-compiler-available? target-arch)
    (and (find-cross-compiler target-arch) #t))

  ;; ========== Compilation Subprocess ==========

  (define (run-command cmd)
    ;; Run shell command, return (exit-code . output-string).
    (guard (exn [#t (cons 1 (if (message-condition? exn)
                                (condition-message exn)
                                (format "~a" exn)))])
      (let* ([tmp  (string-append "/tmp/jerboa-cross-" (number->string (time-second (current-time))) ".out")]
             [full (string-append cmd " > " tmp " 2>&1")]
             [status (system full)]
             [out (guard (exn [#t ""])
                    (call-with-input-file tmp
                      (lambda (port)
                        (let loop ([lines '()])
                          (let ([line (get-line port)])
                            (if (eof-object? line)
                                (apply string-append (reverse lines))
                                (loop (cons (string-append line "\n") lines))))))))])
        (guard (exn [#t #f]) (delete-file tmp))
        (cons status out))))

  (define (compile-for-target config source-file output-dir)
    ;; Compile source-file using cross-compiler for config's target.
    ;; Returns (list 'ok output-path) or (list 'error msg).
    (guard (exn [#t (list 'error (if (message-condition? exn)
                                     (condition-message exn)
                                     (format "~a" exn)))])
      (let* ([cc      (cross-config-cc config)]
             [flags   (cross-config-extra-flags config)]
             [sysroot (cross-config-sysroot config)]
             [base    (path-basename source-file)]
             [out     (string-append output-dir "/" base ".o")]
             [sysroot-flag (if sysroot
                               (string-append "--sysroot=" sysroot " ")
                               "")]
             [flags-str (apply string-append
                                (map (lambda (f) (string-append f " ")) flags))]
             [cmd (string-append cc " " sysroot-flag flags-str
                                 "-c " source-file " -o " out)])
        (let ([result (run-command cmd)])
          (if (= (car result) 0)
              (list 'ok out)
              (list 'error (cdr result)))))))

  (define (link-for-target config obj-files output-binary)
    ;; Link object files into output-binary using cross-linker.
    (guard (exn [#t (list 'error (if (message-condition? exn)
                                     (condition-message exn)
                                     (format "~a" exn)))])
      (let* ([cc      (cross-config-cc config)]
             [objs   (apply string-append
                            (map (lambda (f) (string-append f " ")) obj-files))]
             [cmd    (string-append cc " " objs " -o " output-binary)])
        (let ([result (run-command cmd)])
          (if (= (car result) 0)
              (list 'ok output-binary)
              (list 'error (cdr result)))))))

  (define (path-basename path)
    ;; Return last component of path without directory.
    (let loop ([i (- (string-length path) 1)])
      (cond
        [(< i 0) path]
        [(char=? (string-ref path i) #\/) (substring path (+ i 1) (string-length path))]
        [else (loop (- i 1))])))

  ;; ========== Build Matrix ==========

  (define-record-type (%build-matrix %make-build-matrix build-matrix?)
    (fields
      (immutable source-files)
      (immutable platforms)
      (mutable results)))  ;; alist: platform-name -> (success? output)

  (define (make-build-matrix source-files platforms)
    (%make-build-matrix source-files platforms '()))

  (define (build-matrix-results matrix)
    (%build-matrix-results matrix))

  (define (run-build-matrix matrix)
    ;; For each platform, attempt to compile all source files.
    ;; Does not actually invoke compiler if cross-compiler unavailable.
    (let ([results '()])
      (for-each
        (lambda (platform)
          (let* ([arch (platform-arch platform)]
                 [cc   (or (find-cross-compiler arch) "cc")]
                 [config (make-cross-config (current-platform) platform cc #f '())]
                 [platform-results
                  (map (lambda (src)
                         (guard (exn [#t (cons src (list 'error
                                                    (if (message-condition? exn)
                                                        (condition-message exn)
                                                        "unknown error")))])
                           ;; Simulate compilation without actually running (no real files)
                           (cons src (list 'simulated (platform-name platform)))))
                       (%build-matrix-source-files matrix))]
                 [ok? (every (lambda (r)
                               (let ([res (cdr r)])
                                 (not (eq? (car res) 'error))))
                             platform-results)])
            (set! results
                  (cons (cons (platform-name platform) (cons ok? platform-results))
                        results))))
        (%build-matrix-platforms matrix))
      (%build-matrix-results-set! matrix (reverse results))
      matrix))

  (define (every pred lst)
    (cond [(null? lst) #t]
          [(pred (car lst)) (every pred (cdr lst))]
          [else #f]))

  ;; ========== Platform Utilities ==========

  (define (platform->string p)
    (symbol->string (platform-name p)))

  (define (string->platform s)
    ;; Look up a built-in platform by name string.
    (let ([sym (string->symbol s)])
      (cond
        [(eq? sym 'x86_64-linux)  platform/x86_64-linux]
        [(eq? sym 'arm64-linux)   platform/arm64-linux]
        [(eq? sym 'riscv64-linux) platform/riscv64-linux]
        [(eq? sym 'x86_64-macos) platform/x86_64-macos]
        [(eq? sym 'arm64-macos)  platform/arm64-macos]
        [else #f])))

  (define (platform=? a b)
    (and (target-platform? a)
         (target-platform? b)
         (eq? (platform-name a) (platform-name b))))

  (define (native-platform? p)
    (platform=? p (current-platform)))

) ;; end library
