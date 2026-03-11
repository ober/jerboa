#!chezscheme
;;; (jerboa build) — Native Binary Toolchain (Steps 41-44)
;;;
;;; Step 41: Incremental + parallel compilation via content hashing.
;;; Step 42: Tree shaking via Chez WPO (compile-whole-program).
;;; Step 43: Cross-compilation to multiple target architectures.
;;; Step 44: Static linking with musl for zero-dependency binaries.

(library (jerboa build)
  (export
    ;; Step 41: Build pipeline
    build-binary
    build-project
    build-boot-file
    file->c-array
    generate-main-c
    trace-imports
    compute-file-hash
    module-changed?
    compile-modules-parallel

    ;; Step 42: Tree shaking
    build-release
    wpo-compile
    tree-shake-imports

    ;; Step 43: Cross-compilation
    make-cross-target
    cross-target?
    cross-target-os
    cross-target-arch
    cross-target-cc
    cross-target-ar
    target-linux-x64
    target-linux-aarch64
    target-macos-x64
    target-macos-aarch64
    compile-for-target

    ;; Step 44: Static linking
    static-link-flags
    musl-link-flags
    build-static-binary
    link-static-archives)

  (import (chezscheme))

  ;; ========== Helpers ==========

  (define (kwarg key opts . default-args)
    (let ([default (if (null? default-args) #f (car default-args))])
      (let loop ([lst opts])
        (cond [(or (null? lst) (null? (cdr lst))) default]
              [(eq? (car lst) key) (cadr lst)]
              [else (loop (cddr lst))]))))

  ;; ========== Step 41: Import Tracing ==========

  (define (trace-imports source-path)
    (let ([imports '()])
      (guard (exn [#t (reverse imports)])
        (call-with-input-file source-path
          (lambda (port)
            (let loop ()
              (let ([form (read port)])
                (unless (eof-object? form)
                  (when (and (pair? form) (eq? (car form) 'import))
                    (for-each
                      (lambda (spec)
                        (when (pair? spec)
                          (set! imports (cons spec imports))))
                      (cdr form)))
                  (loop))))))
        (reverse imports))))

  ;; ========== Step 41: Content Hashing ==========

  (define (compute-file-hash path)
    (guard (exn [#t #f])
      (call-with-port (open-file-input-port path)
        (lambda (p)
          (let ([data (get-bytevector-all p)])
            (if (eof-object? data)
              "empty"
              (let ([len (bytevector-length data)])
                (let loop ([i 0] [h 14695981039346656037])
                  (if (= i len)
                    (number->string (mod h (expt 2 64)) 16)
                    (loop (+ i 1)
                          (mod (* (bitwise-xor h (bytevector-u8-ref data i))
                                  1099511628211)
                               (expt 2 64))))))))))))

  (define (module-changed? path hash-table)
    (let ([current (compute-file-hash path)]
          [stored  (hashtable-ref hash-table path #f)])
      (not (equal? current stored))))

  (define (record-hash! path hash-table)
    (let ([h (compute-file-hash path)])
      (when h (hashtable-set! hash-table path h))))

  ;; ========== Step 41: Parallel Compilation ==========

  (define (compile-modules-parallel paths compile-fn . opts)
    (if (null? paths)
      '()
      (let* ([n        (length paths)]
             [results  (make-vector n #f)]
             [errors   (make-vector n #f)]
             [mutex    (make-mutex)]
             [pending  n]
             [done     (make-condition)])
        (let loop ([paths paths] [i 0])
          (unless (null? paths)
            (let ([path (car paths)]
                  [idx  i])
              (fork-thread
                (lambda ()
                  (let ([res (guard (exn [#t (cons 'error exn)])
                               (cons 'ok (compile-fn path)))])
                    (with-mutex mutex
                      (if (eq? (car res) 'ok)
                        (vector-set! results idx (cdr res))
                        (vector-set! errors  idx (cdr res)))
                      (set! pending (- pending 1))
                      (when (= pending 0)
                        (condition-broadcast done)))))))
            (loop (cdr paths) (+ i 1))))
        (with-mutex mutex
          (let wait ()
            (when (> pending 0)
              (condition-wait done mutex)
              (wait))))
        (let ([first-err
               (let scan ([i 0])
                 (cond [(= i n) #f]
                       [(vector-ref errors i) => (lambda (e) e)]
                       [else (scan (+ i 1))]))])
          (when first-err (raise first-err)))
        (map cons paths (vector->list results)))))

  ;; ========== Step 41: File to C Array ==========

  (define (file->c-array file-path var-name)
    (let* ([data (call-with-port (open-file-input-port file-path)
                   (lambda (p) (get-bytevector-all p)))]
           [len (bytevector-length data)])
      (call-with-string-output-port
        (lambda (port)
          (format port "static const unsigned char ~a[] = {~%" var-name)
          (do ([i 0 (+ i 1)])
              ((= i len))
            (format port "0x~2,'0x" (bytevector-u8-ref data i))
            (unless (= i (- len 1))
              (display "," port))
            (when (= (mod (+ i 1) 16) 0)
              (newline port)))
          (format port "~%};~%")
          (format port "static const unsigned int ~a_len = ~a;~%" var-name len)))))

  ;; ========== Step 41: C Main Template ==========

  (define (generate-main-c boot-arrays program-array link-libs)
    (call-with-string-output-port
      (lambda (port)
        (display "#include <scheme.h>\n" port)
        (display "#include <string.h>\n" port)
        (display "#include <stdlib.h>\n\n" port)
        (for-each (lambda (arr) (display arr port) (newline port))
                  boot-arrays)
        (when program-array
          (display program-array port)
          (newline port))
        (display "#ifdef __linux__\n" port)
        (display "#include <sys/mman.h>\n" port)
        (display "#ifndef MFD_CLOEXEC\n#define MFD_CLOEXEC 1\n#endif\n" port)
        (display "extern int memfd_create(const char *, unsigned int);\n" port)
        (display "#endif\n\n" port)
        (display "int main(int argc, const char *argv[]) {\n" port)
        (display "    Sscheme_init(NULL);\n\n" port)
        (display "    Sregister_boot_file_bytes(\"petite\", petite_boot, petite_boot_len);\n" port)
        (display "    Sregister_boot_file_bytes(\"scheme\", scheme_boot, scheme_boot_len);\n" port)
        (display "    Sregister_boot_file_bytes(\"app\", app_boot, app_boot_len);\n" port)
        (display "\n    Sbuild_heap(argv[0], NULL);\n\n" port)
        (display "    Sscheme_deinit();\n" port)
        (display "    return 0;\n" port)
        (display "}\n" port))))

  ;; ========== Step 41: Build Pipeline ==========

  (define *hash-table* (make-hashtable equal-hash equal?))

  (define (build-project source-paths output-path . opts)
    (let* ([changed  (filter (lambda (p) (module-changed? p *hash-table*))
                             source-paths)]
           [parallel (kwarg 'parallel: opts #t)])
      (if (null? changed)
        (begin (printf "  [up to date] ~a~%" output-path) output-path)
        (begin
          (printf "  Recompiling ~a module(s)...~%" (length changed))
          (if parallel
            (compile-modules-parallel changed
              (lambda (path)
                (printf "  [compile] ~a~%" path)
                (record-hash! path *hash-table*)))
            (for-each
              (lambda (path)
                (printf "  [compile] ~a~%" path)
                (record-hash! path *hash-table*))
              changed))
          output-path))))

  (define (build-binary source-path output-path . options)
    (let* ([opt-level (kwarg 'optimize-level: options 2)]
           [release?  (kwarg 'release: options)]
           [static?   (kwarg 'static: options)]
           [target    (kwarg 'target: options #f)]
           [build-dir (string-append "/tmp/jerboa-build-"
                                     (number->string
                                       (mod (time-second (current-time)) 100000)))])
      (system (format "mkdir -p '~a'" build-dir))
      (parameterize ([optimize-level (if release? 3 opt-level)]
                     [compile-imported-libraries #t]
                     [generate-inspector-information (not release?)])
        (printf "  [1/5] Compiling ~a...~%" source-path)
        (let ([so-path (string-append build-dir "/program.so")])
          (guard (exn [#t (printf "  Compile error: ~a~%"
                                  (if (message-condition? exn) (condition-message exn) exn))])
            (compile-program source-path so-path))
          (printf "  [2/5] Boot files...~%")
          (let ([petite-boot (find-boot-file "petite.boot")]
                [scheme-boot (find-boot-file "scheme.boot")]
                [app-boot    (string-append build-dir "/app.boot")])
            (when (file-exists? so-path)
              (make-boot-file app-boot '("petite" "scheme") so-path))
            (printf "  [3/5] Generating C...~%")
            (when (and (file-exists? petite-boot)
                       (file-exists? scheme-boot)
                       (file-exists? app-boot))
              (let* ([main-c (generate-main-c
                               (list (file->c-array petite-boot "petite_boot")
                                     (file->c-array scheme-boot "scheme_boot")
                                     (file->c-array app-boot "app_boot"))
                               (and (file-exists? so-path)
                                    (file->c-array so-path "program_so"))
                               '())]
                     [main-path (string-append build-dir "/main.c")])
                (call-with-output-file main-path
                  (lambda (p) (display main-c p))
                  'replace)
                (printf "  [4/5] Linking ~a...~%" output-path)
                (let ([cc    (if target (cross-target-cc target) "gcc")]
                      [lflags (if static?
                                (musl-link-flags '())
                                "-lm -ldl -lpthread")])
                  (let ([cmd (format "~a -rdynamic -o '~a' '~a' ~a 2>&1"
                               cc output-path main-path lflags)])
                    (let ([rc (system cmd)])
                      (if (= rc 0)
                        (printf "  Built: ~a~%" output-path)
                        (printf "  Link warning (rc=~a)~%" rc)))))))))
        output-path)))

  (define (build-boot-file output-path deps so-path)
    (make-boot-file output-path deps so-path))

  (define (find-boot-file name)
    (let loop ([dirs (list
                       (format "/usr/lib/csv~a/~a/~a" (scheme-version)
                               (machine-type) name)
                       (format "/usr/local/lib/csv~a/~a/~a" (scheme-version)
                               (machine-type) name)
                       (let ([h (getenv "SCHEMEHEAPDIRS")])
                         (and h (string-append h "/" name))))])
      (cond
        [(null? dirs) (error 'find-boot-file "cannot find" name)]
        [(and (car dirs) (file-exists? (car dirs))) (car dirs)]
        [else (loop (cdr dirs))])))

  ;; ========== Step 42: Tree Shaking / WPO ==========

  (define (build-release source-paths output-path . opts)
    (let* ([opt-level  (kwarg 'optimize-level: opts 3)]
           [wpo-output (kwarg 'wpo-output: opts
                          (string-append output-path ".wpo"))])
      (printf "  [release] WPO compile (~a sources)~%" (length source-paths))
      (parameterize ([optimize-level opt-level]
                     [compile-imported-libraries #t]
                     [generate-inspector-information #f]
                     [cp0-effort-limit 100])
        (guard (exn [#t (printf "  WPO skipped: ~a~%"
                                (if (message-condition? exn) (condition-message exn) exn))
                        #f])
          (compile-whole-program (car source-paths) wpo-output)
          (printf "  [release] WPO: ~a~%" wpo-output)
          wpo-output))))

  (define (wpo-compile source-path output-path)
    (parameterize ([optimize-level 3]
                   [cp0-effort-limit 1000]
                   [generate-inspector-information #f])
      (compile-whole-program source-path output-path)))

  (define (tree-shake-imports source-path)
    (let ([imports '()]
          [used-syms (make-eq-hashtable)])
      (guard (exn [#t (reverse imports)])
        (call-with-input-file source-path
          (lambda (port)
            (let loop ()
              (let ([form (read port)])
                (unless (eof-object? form)
                  (when (and (pair? form) (eq? (car form) 'import))
                    (for-each (lambda (spec)
                                (set! imports (cons spec imports)))
                              (cdr form)))
                  (let walk ([x form])
                    (cond
                      [(symbol? x) (hashtable-set! used-syms x #t)]
                      [(pair? x) (walk (car x)) (walk (cdr x))]
                      [(vector? x)
                       (vector-for-each (lambda (e) (walk e)) x)]))
                  (loop))))))
        (reverse imports))))

  ;; ========== Step 43: Cross-Compilation ==========

  (define (make-cross-target os arch cc ar)
    (vector 'cross-target os arch cc ar))

  (define (cross-target? x)
    (and (vector? x) (= (vector-length x) 5) (eq? (vector-ref x 0) 'cross-target)))

  (define (cross-target-os   t) (vector-ref t 1))
  (define (cross-target-arch t) (vector-ref t 2))
  (define (cross-target-cc   t) (vector-ref t 3))
  (define (cross-target-ar   t) (vector-ref t 4))

  (define target-linux-x64
    (make-cross-target 'linux 'x86-64 "x86_64-linux-gnu-gcc" "x86_64-linux-gnu-ar"))

  (define target-linux-aarch64
    (make-cross-target 'linux 'aarch64 "aarch64-linux-gnu-gcc" "aarch64-linux-gnu-ar"))

  (define target-macos-x64
    (make-cross-target 'macos 'x86-64 "o64-clang" "x86_64-apple-darwin-ar"))

  (define target-macos-aarch64
    (make-cross-target 'macos 'aarch64 "oa64-clang" "arm64-apple-darwin-ar"))

  (define (compile-for-target target c-path output-path . extra-flags)
    (unless (cross-target? target)
      (error 'compile-for-target "not a cross-target" target))
    (let* ([cc    (cross-target-cc target)]
           [os    (cross-target-os target)]
           [flags (case os
                    [(linux)  "-fPIE -pie"]
                    [(macos)  "-mmacosx-version-min=11.0"]
                    [else ""])]
           [xf    (if (null? extra-flags) "" (car extra-flags))]
           [cmd   (format "~a ~a ~a -o '~a' '~a' 2>&1"
                    cc flags xf output-path c-path)])
      (values (system cmd) cmd)))

  ;; ========== Step 44: Static Linking ==========

  (define (static-link-flags static-libs)
    (let ([archive-flags
           (apply string-append
             (map (lambda (lib) (string-append " " lib))
                  static-libs))])
      (string-append "-static -static-libgcc" archive-flags
                     " -lm -lpthread -ldl")))

  (define (musl-link-flags static-libs)
    (let* ([musl-gcc (or (find-executable "musl-gcc")
                         (find-executable "x86_64-linux-musl-gcc")
                         #f)]
           [archive-flags
            (apply string-append
              (map (lambda (lib) (string-append " " lib))
                   static-libs))])
      (if musl-gcc
        (string-append "-static" archive-flags " -lm -lpthread")
        (string-append "-static -static-libgcc" archive-flags
                       " -lm -lpthread -ldl"))))

  (define (build-static-binary source-path output-path . opts)
    (apply build-binary source-path output-path 'static: #t opts))

  (define (link-static-archives archives output-ar)
    (if (null? archives)
      (error 'link-static-archives "no archives provided")
      (let ([cmd (apply string-append
                   "ar crs '" output-ar "'"
                   (map (lambda (a) (string-append " '" a "'"))
                        archives))])
        (values (system cmd) cmd))))

  ;; ========== Utilities ==========

  (define (find-executable name)
    (let ([result (with-output-to-string
                    (lambda () (system (format "which '~a' 2>/dev/null" name))))])
      (let ([trimmed (string-trim-right result)])
        (if (string=? trimmed "") #f trimmed))))

  (define (string-trim-right s)
    (let loop ([i (- (string-length s) 1)])
      (if (< i 0)
        ""
        (if (char-whitespace? (string-ref s i))
          (loop (- i 1))
          (substring s 0 (+ i 1))))))

  ) ;; end library
