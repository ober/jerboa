#!chezscheme
;;; Tests for Phase 12: Native Binary Toolchain (Steps 41-44)

(import (chezscheme)
        (jerboa build))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%"  name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%"  name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s expected ~s~%"  name got expected)))))]))

;; Portable substring search helper
(define (str-has? s sub)
  (let* ([slen   (string-length s)]
         [sublen (string-length sub)])
    (let loop ([i 0])
      (cond
        [(> (+ i sublen) slen) #f]
        [(string=? (substring s i (+ i sublen)) sub) #t]
        [else (loop (+ i 1))]))))

(printf "--- Phase 12: Native Binary Toolchain ---~%")

;;; ======== Step 41: Content Hashing ========

(printf "~%-- Step 41: Incremental Compilation --~%")

(let ([f "/tmp/jerboa-build-test.ss"])
  (call-with-output-file f
    (lambda (p) (display "(define x 42)" p))
    'replace)

  (test "compute-file-hash returns string"
    (string? (compute-file-hash f))
    #t)

  (test "compute-file-hash non-empty"
    (> (string-length (compute-file-hash f)) 0)
    #t)

  (test "compute-file-hash deterministic"
    (string=? (compute-file-hash f) (compute-file-hash f))
    #t)

  (let ([ht (make-hashtable equal-hash equal?)])
    (test "module-changed? true for new file"
      (module-changed? f ht)
      #t)

    (hashtable-set! ht f (compute-file-hash f))

    (test "module-changed? false after recording"
      (module-changed? f ht)
      #f)

    (call-with-output-file f
      (lambda (p) (display "(define x 99)" p))
      'replace)

    (test "module-changed? true after modification"
      (module-changed? f ht)
      #t))

  (delete-file f))

(test "compute-file-hash returns #f for missing file"
  (compute-file-hash "/nonexistent/file")
  #f)

;;; ======== Step 41: Parallel Compilation ========

(printf "~%-- Step 41: Parallel Compilation --~%")

(let ([compiled '()]
      [mutex (make-mutex)])
  (let ([paths '("/tmp/a.ss" "/tmp/b.ss" "/tmp/c.ss")])
    (for-each
      (lambda (p)
        (call-with-output-file p
          (lambda (port) (display "(define x 1)" port))
          'replace))
      paths)

    (let ([results
           (compile-modules-parallel paths
             (lambda (path)
               (with-mutex mutex
                 (set! compiled (cons path compiled)))
               (string-length path)))])

      (test "parallel compile: returns list"
        (list? results)
        #t)

      (test "parallel compile: correct count"
        (length results)
        3)

      (test "parallel compile: all compiled"
        (= (length compiled) 3)
        #t)

      (test "parallel compile: result is pair"
        (and (pair? (car results)) #t)
        #t))

    (for-each delete-file paths)))

(test "parallel compile: empty paths"
  (compile-modules-parallel '() (lambda (x) x))
  '())

;;; ======== Step 41: Import Tracing ========

(printf "~%-- Step 41: Import Tracing --~%")

(let ([f "/tmp/jerboa-trace-test.ss"])
  (call-with-output-file f
    (lambda (p)
      (display "(import (chezscheme) (std seq))\n(define x 1)\n(import (std table))" p))
    'replace)

  (let ([imports (trace-imports f)])
    (test "trace-imports returns list"
      (list? imports)
      #t)
    (test "trace-imports finds imports"
      (> (length imports) 0)
      #t))

  (delete-file f))

(test "trace-imports: missing file returns list"
  (list? (trace-imports "/nonexistent.ss"))
  #t)

;;; ======== Step 41: C Code Generation ========

(printf "~%-- Step 41: C Code Generation --~%")

(let ([main-c (generate-main-c '() #f '())])
  (test "generate-main-c returns string"
    (string? main-c)
    #t)
  (test "generate-main-c contains main"
    (str-has? main-c "int main")
    #t)
  (test "generate-main-c contains Sscheme_init"
    (str-has? main-c "Sscheme_init")
    #t))

;;; ======== Step 42: Tree Shaking ========

(printf "~%-- Step 42: Tree Shaking --~%")

(let ([f "/tmp/jerboa-shake-test.ss"])
  (call-with-output-file f
    (lambda (p)
      (display "(import (chezscheme))\n(define (foo x) (+ x 1))\n(display (foo 5))" p))
    'replace)

  (let ([imports (tree-shake-imports f)])
    (test "tree-shake-imports returns list"
      (list? imports)
      #t))

  (delete-file f))

;;; ======== Step 43: Cross-Compilation Targets ========

(printf "~%-- Step 43: Cross-Compilation Targets --~%")

(test "target-linux-x64 is cross-target"
  (cross-target? target-linux-x64)
  #t)

(test "target-linux-aarch64 is cross-target"
  (cross-target? target-linux-aarch64)
  #t)

(test "target-macos-x64 is cross-target"
  (cross-target? target-macos-x64)
  #t)

(test "target-macos-aarch64 is cross-target"
  (cross-target? target-macos-aarch64)
  #t)

(test "cross-target-os linux-x64"
  (cross-target-os target-linux-x64)
  'linux)

(test "cross-target-arch linux-x64"
  (cross-target-arch target-linux-x64)
  'x86-64)

(test "cross-target-cc linux-x64"
  (cross-target-cc target-linux-x64)
  "x86_64-linux-gnu-gcc")

(test "cross-target-os macos-aarch64"
  (cross-target-os target-macos-aarch64)
  'macos)

(test "cross-target-arch macos-aarch64"
  (cross-target-arch target-macos-aarch64)
  'aarch64)

(let ([custom (make-cross-target 'linux 'riscv64 "riscv64-linux-gcc" "riscv64-linux-ar")])
  (test "make-cross-target custom"
    (cross-target? custom)
    #t)
  (test "custom target cc"
    (cross-target-cc custom)
    "riscv64-linux-gcc"))

(test "cross-target? false for non-target"
  (cross-target? '(not a target))
  #f)

;;; ======== Step 44: Static Linking ========

(printf "~%-- Step 44: Static Linking --~%")

(let ([flags (static-link-flags '())])
  (test "static-link-flags returns string"
    (string? flags)
    #t)
  (test "static-link-flags contains -static"
    (str-has? flags "-static")
    #t)
  (test "static-link-flags contains -lm"
    (str-has? flags "-lm")
    #t))

(let ([flags (static-link-flags '("/usr/lib/libsqlite3.a"))])
  (test "static-link-flags with archives"
    (str-has? flags "libsqlite3.a")
    #t))

(let ([flags (musl-link-flags '())])
  (test "musl-link-flags returns string"
    (string? flags)
    #t)
  (test "musl-link-flags contains -static"
    (str-has? flags "-static")
    #t))

(test "link-static-archives errors on empty"
  (guard (exn [#t #t])
    (link-static-archives '() "/tmp/out.a")
    #f)
  #t)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
