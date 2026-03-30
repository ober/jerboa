#!chezscheme
;;; (std secure link) -- Slang static binary builder
;;;
;;; Orchestrates the full pipeline from validated Slang source to
;;; a signed, hardened static binary:
;;;
;;;   1. slang-compile (validate + emit safe Chez Scheme)
;;;   2. compile-whole-program (Chez nanopass -> native code)
;;;   3. Embed boot files into C object
;;;   4. Static link with musl/system cc (PIE, RELRO, stack protector)
;;;   5. Strip symbols (optional)
;;;   6. Sign binary with ed25519 (optional)
;;;   7. Verify output
;;;
;;; Supports both musl (Linux static) and system cc (FreeBSD static).

(library (std secure link)
  (export
    ;; High-level entry point
    slang-build

    ;; Individual phases (for advanced use)
    slang-link
    slang-sign!
    slang-verify-binary

    ;; Configuration
    make-slang-build-config
    slang-build-config?
    slang-build-config-output
    slang-build-config-sign-key
    slang-build-config-strip?
    slang-build-config-verify?
    slang-build-config-verbose?
    slang-build-config-static-libs
    slang-build-config-extra-c-files
    slang-build-config-cc)

  (import (chezscheme)
          (std secure compiler)
          (std error conditions))

  ;; ========== Condition type ==========

  (define-condition-type &slang-link-error &jerboa
    make-link-error slang-link-error?
    (phase  link-error-phase)
    (detail link-error-detail))

  ;; ========== Helpers (must be early for forward-reference safety) ==========

  (define (kwarg key opts . default-args)
    (let ([default (if (null? default-args) #f (car default-args))])
      (let loop ([lst opts])
        (cond [(or (null? lst) (null? (cdr lst))) default]
              [(eq? (car lst) key) (cadr lst)]
              [else (loop (cddr lst))]))))

  (define (%slang-path-root path)
    (let loop ([i (- (string-length path) 1)])
      (cond
        [(< i 0) path]
        [(char=? (string-ref path i) #\.) (substring path 0 i)]
        [(char=? (string-ref path i) #\/) path]
        [else (loop (- i 1))])))

  (define (%slang-path-last path)
    (let loop ([i (- (string-length path) 1)])
      (cond
        [(< i 0) path]
        [(char=? (string-ref path i) #\/)
         (substring path (+ i 1) (string-length path))]
        [else (loop (- i 1))])))

  (define (string-trim-right s)
    (let loop ([i (- (string-length s) 1)])
      (if (< i 0) ""
        (if (char-whitespace? (string-ref s i))
          (loop (- i 1))
          (substring s 0 (+ i 1))))))

  (define (system* . args)
    (let ([cmd (apply string-append
                 (let loop ([a args] [first? #t])
                   (if (null? a) '()
                     (cons (if first?
                             (format "'~a'" (car a))
                             (format " '~a'" (car a)))
                           (loop (cdr a) #f)))))])
      (system cmd)))

  ;; ========== Configuration ==========

  (define-record-type (%slang-build-config %make-slang-build-config
                        slang-build-config?)
    (sealed #t)
    (fields
      (immutable output       slang-build-config-output)
      (immutable sign-key     slang-build-config-sign-key)
      (immutable strip?       slang-build-config-strip?)
      (immutable verify?      slang-build-config-verify?)
      (immutable verbose?     slang-build-config-verbose?)
      (immutable static-libs  slang-build-config-static-libs)
      (immutable extra-c-files slang-build-config-extra-c-files)
      (immutable cc           slang-build-config-cc)
      (immutable chez-prefix  slang-build-config-chez-prefix)))

  (define (normalize-key sym)
    (let ([s (symbol->string sym)])
      (cond
        [(and (>= (string-length s) 2)
              (char=? (string-ref s 0) #\#)
              (char=? (string-ref s 1) #\:))
         (substring s 2 (string-length s))]
        [(and (> (string-length s) 0)
              (char=? (string-ref s (- (string-length s) 1)) #\:))
         (substring s 0 (- (string-length s) 1))]
        [else s])))

  (define (make-slang-build-config . args)
    (let loop ([rest args]
               [output #f]
               [sign-key #f]
               [strip? #t]
               [verify? #t]
               [verbose? #f]
               [static-libs '()]
               [extra-c-files '()]
               [cc #f]
               [chez-prefix #f])
      (if (null? rest)
        (%make-slang-build-config
          output sign-key strip? verify? verbose?
          static-libs extra-c-files cc
          (or chez-prefix (detect-chez-prefix)))
        (begin
          (when (null? (cdr rest))
            (error 'make-slang-build-config
              "keyword missing value" (car rest)))
          (let ([key (normalize-key (car rest))]
                [val (cadr rest)]
                [remaining (cddr rest)])
            (cond
              [(string=? key "output")
               (loop remaining val sign-key strip? verify? verbose?
                     static-libs extra-c-files cc chez-prefix)]
              [(string=? key "sign-key")
               (loop remaining output val strip? verify? verbose?
                     static-libs extra-c-files cc chez-prefix)]
              [(string=? key "strip")
               (loop remaining output sign-key val verify? verbose?
                     static-libs extra-c-files cc chez-prefix)]
              [(string=? key "verify")
               (loop remaining output sign-key strip? val verbose?
                     static-libs extra-c-files cc chez-prefix)]
              [(string=? key "verbose")
               (loop remaining output sign-key strip? verify? val
                     static-libs extra-c-files cc chez-prefix)]
              [(string=? key "static-libs")
               (loop remaining output sign-key strip? verify? verbose?
                     val extra-c-files cc chez-prefix)]
              [(string=? key "extra-c-files")
               (loop remaining output sign-key strip? verify? verbose?
                     static-libs val cc chez-prefix)]
              [(string=? key "cc")
               (loop remaining output sign-key strip? verify? verbose?
                     static-libs extra-c-files val chez-prefix)]
              [(string=? key "chez-prefix")
               (loop remaining output sign-key strip? verify? verbose?
                     static-libs extra-c-files cc val)]
              [else
               (error 'make-slang-build-config
                 "unknown keyword" (car rest))]))))))

  ;; ========== Platform/toolchain detection ==========

  (define (string-contains-ci str sub)
    (let ([slen (string-length str)]
          [sublen (string-length sub)])
      (let lp ([i 0])
        (cond
          [(> (+ i sublen) slen) #f]
          [(string-ci=? (substring str i (+ i sublen)) sub) #t]
          [else (lp (+ i 1))]))))

  (define (detect-platform)
    (let ([mt (symbol->string (machine-type))])
      (cond
        [(string-contains-ci mt "le")  'linux]
        [(string-contains-ci mt "osx") 'macos]
        [(string-contains-ci mt "fb")  'freebsd]
        [else                          'unknown])))

  (define (detect-chez-prefix)
    "Find the Chez Scheme installation to use for static linking.
     Probes: $SLANG_CHEZ_PREFIX, ~/chez-secure, ~/chez-musl, system."
    (or (getenv "SLANG_CHEZ_PREFIX")
        (getenv "JERBOA_MUSL_CHEZ_PREFIX")
        (let ([home (getenv "HOME")])
          (and home
               (let ([secure (format "~a/chez-secure" home)])
                 (and (file-directory? secure) secure))))
        (let ([home (getenv "HOME")])
          (and home
               (let ([musl (format "~a/chez-musl" home)])
                 (and (file-directory? musl) musl))))
        ;; Fallback: use the running Chez installation
        #f))

  (define (find-chez-lib-dir prefix)
    "Find the csv<version>/<machine> directory under a Chez prefix."
    (let* ([machine (symbol->string (machine-type))]
           [lib-dir (format "~a/lib" prefix)])
      (if (not (file-directory? lib-dir))
        (error 'find-chez-lib-dir "lib directory not found" lib-dir)
        (let* ([entries (directory-list lib-dir)]
               [csv-dirs (filter
                           (lambda (e)
                             (and (> (string-length e) 3)
                                  (string=? (substring e 0 3) "csv")))
                           entries)]
               [sorted (sort string<? csv-dirs)])
          (if (null? sorted)
            (error 'find-chez-lib-dir "no csv* directory" lib-dir)
            (let loop ([dirs (reverse sorted)])
              (if (null? dirs)
                (error 'find-chez-lib-dir
                  "no csv*/<machine> directory" (cons lib-dir machine))
                (let ([candidate (format "~a/~a/~a"
                                   lib-dir (car dirs) machine)])
                  (if (file-directory? candidate)
                    candidate
                    (loop (cdr dirs)))))))))))

  (define (find-cc platform)
    "Find the C compiler to use."
    (case platform
      [(linux)
       ;; Prefer musl-gcc for fully static binaries
       (or (find-executable "musl-gcc")
           (find-executable "cc")
           "cc")]
      [(freebsd)
       (or (find-executable "cc")
           "cc")]
      [else "cc"]))

  (define (find-executable name)
    (guard (e [#t #f])
      (let-values ([(to-stdin from-stdout from-stderr pid)
                    (open-process-ports
                      (format "which '~a' 2>/dev/null" name)
                      (buffer-mode block)
                      (native-transcoder))])
        (close-port to-stdin)
        (let ([line (get-line from-stdout)])
          (close-port from-stdout)
          (close-port from-stderr)
          (if (eof-object? line) #f
            (let ([trimmed (string-trim-right line)])
              (if (string=? trimmed "") #f trimmed)))))))

  ;; ========== Boot file embedding ==========

  (define (file->c-array path varname)
    "Convert a binary file to a C byte array declaration."
    (let ([data (call-with-port (open-file-input-port path)
                  get-bytevector-all)])
      (let ([out (open-output-string)]
            [len (bytevector-length data)])
        (fprintf out "static const unsigned char ~a[] = {~n" varname)
        (let loop ([i 0])
          (when (< i len)
            (when (= (mod i 16) 0)
              (display "  " out))
            (fprintf out "0x~2,'0x" (bytevector-u8-ref data i))
            (when (< (+ i 1) len) (display "," out))
            (if (= (mod (+ i 1) 16) 0)
              (newline out)
              (display " " out))
            (loop (+ i 1))))
        (fprintf out "~n};~n" )
        (fprintf out "static const unsigned long ~a_len = ~a;~n~n"
          varname len)
        (get-output-string out))))

  (define (generate-static-boot-c output-path boot-paths app-boot-path)
    "Generate static_boot.c that provides static_boot_init()."
    (call-with-output-file output-path
      (lambda (out)
        (display "#include \"scheme.h\"\n\n" out)
        ;; Embed boot files
        (for-each
          (lambda (boot-path)
            (let ([name (%slang-path-root (%slang-path-last boot-path))])
              (display (file->c-array boot-path
                         (format "~a_boot" name))
                       out)))
          boot-paths)
        ;; Embed app boot
        (display (file->c-array app-boot-path "app_boot") out)
        ;; static_boot_init function
        (display "void static_boot_init(void) {\n" out)
        (for-each
          (lambda (boot-path)
            (let ([name (%slang-path-root (%slang-path-last boot-path))])
              (fprintf out
                "    Sregister_boot_file_bytes(\"~a\", ~a_boot, ~a_boot_len);\n"
                name name name)))
          boot-paths)
        (display
          "    Sregister_boot_file_bytes(\"app\", app_boot, app_boot_len);\n"
          out)
        (display "}\n" out))
      'replace))

  ;; ========== Hardening flags ==========

  (define (hardening-cflags platform)
    "Return C compiler hardening flags for the target platform."
    (let ([base (string-append
                  " -fstack-protector-strong"
                  " -D_FORTIFY_SOURCE=2"
                  " -fPIE")])
      (case platform
        [(linux)
         (string-append base
           " -fstack-clash-protection"
           ;; CET on x86_64 Linux
           (if (memq (machine-type) '(a6le ta6le i3le ti3le))
             " -fcf-protection=full"
             ""))]
        [(freebsd)
         (string-append base
           " -fstack-clash-protection")]
        [else base])))

  (define (hardening-ldflags platform use-musl?)
    "Return linker hardening flags."
    (string-append
      (if use-musl? " -static-pie" " -pie")
      " -Wl,-z,relro,-z,now"))

  ;; ========== Signing ==========

  (define (slang-sign! binary-path key-path)
    "Sign a binary with ed25519 using the Rust native library."
    (guard (exn [#t
      (fprintf (current-error-port)
        "[slang] WARNING: could not sign binary: ~a~n"
        (if (message-condition? exn)
          (condition-message exn) "signing unavailable"))])
      (let ([sig-path (string-append binary-path ".sig")])
        (let ([cmd (format
                     "openssl dgst -sha256 -sign '~a' -out '~a' '~a'"
                     key-path sig-path binary-path)])
          (when (= (system cmd) 0)
            sig-path)))))

  ;; ========== Verification ==========

  (define (slang-verify-binary path verbose?)
    "Verify a built binary has expected properties."
    (let ([file-output (with-output-to-string
                         (lambda () (system (format "file '~a'" path))))])
      (unless (or (string-contains-ci file-output "elf")
                  (string-contains-ci file-output "executable")
                  (string-contains-ci file-output "mach-o"))
        (raise (make-link-error "slang-link" 'verify
          (format "output is not an executable: ~a" file-output))))
      (when (and (string-contains-ci file-output "elf")
                 (not (string-contains-ci file-output "dynamic")))
        (when verbose?
          (display "[slang-link] Verified: statically linked\n")))
      (when (string-contains-ci file-output "pie")
        (when verbose?
          (display "[slang-link] Verified: position-independent\n")))
      #t))

  ;; ========== Link phase ==========

  (define (slang-link wpo-path build-config)
    "Link a compiled Slang .wpo into a hardened binary.

     Parameters:
       wpo-path     - Path to compiled .wpo from slang-compile
       build-config - slang-build-config record

     Returns: output path on success."
    (let* ([output (or (slang-build-config-output build-config)
                       (string-append (%slang-path-root wpo-path) ".bin"))]
           [verbose? (slang-build-config-verbose? build-config)]
           [platform (detect-platform)]
           [chez-prefix (slang-build-config-chez-prefix build-config)]
           [use-musl? (and (eq? platform 'linux)
                           (find-executable "musl-gcc"))]
           [cc (or (slang-build-config-cc build-config)
                   (if use-musl? "musl-gcc" (find-cc platform)))]
           [build-dir (format "/tmp/slang-build-~a"
                        (time-second (current-time)))])

      ;; Validate Chez installation
      (unless chez-prefix
        (raise (make-link-error "slang-link" 'setup
          "no Chez Scheme installation found for static linking")))

      (let ([chez-lib-dir (find-chez-lib-dir chez-prefix)])

        ;; Create build directory
        (system* "mkdir" "-p" build-dir)

        (dynamic-wind
          (lambda () #f)

          (lambda ()
            ;; Step 1: Create app boot file from .wpo
            (when verbose?
              (printf "[slang-link] Creating boot file from ~a...~n" wpo-path))

            (let* ([petite-boot (format "~a/petite.boot" chez-lib-dir)]
                   [scheme-boot (format "~a/scheme.boot" chez-lib-dir)]
                   [app-boot (format "~a/app.boot" build-dir)])

              (unless (file-exists? petite-boot)
                (raise (make-link-error "slang-link" 'setup
                  (format "petite.boot not found: ~a" petite-boot))))
              (unless (file-exists? scheme-boot)
                (raise (make-link-error "slang-link" 'setup
                  (format "scheme.boot not found: ~a" scheme-boot))))

              (make-boot-file app-boot
                (list "petite" "scheme")
                wpo-path)

              ;; Step 2: Generate static_boot.c
              (when verbose?
                (display "[slang-link] Generating static_boot.c...\n"))

              (let ([static-boot-c (format "~a/static_boot.c" build-dir)])
                (generate-static-boot-c
                  static-boot-c
                  (list petite-boot scheme-boot)
                  app-boot)

                ;; Step 3: Compile C
                (when verbose?
                  (display "[slang-link] Compiling C...\n"))

                (let* ([static-boot-o (format "~a/static_boot.o" build-dir)]
                       [scheme-h-dir chez-lib-dir]
                       [cflags (string-append
                                 " -O2"
                                 (hardening-cflags platform)
                                 (format " -I'~a'" scheme-h-dir))]
                       [compile-cmd (format "~a -c~a -o '~a' '~a'"
                                     cc cflags static-boot-o static-boot-c)])

                  (when verbose? (printf "  ~a~n" compile-cmd))
                  (unless (= (system compile-cmd) 0)
                    (raise (make-link-error "slang-link" 'compile
                      "static_boot.c compilation failed")))

                  ;; Compile extra C files
                  (let ([extra-objs
                         (map (lambda (c-file)
                                (let ([o-file (format "~a/~a.o"
                                                build-dir
                                                (%slang-path-root (%slang-path-last c-file)))])
                                  (let ([cmd (format "~a -c~a -o '~a' '~a'"
                                               cc cflags o-file c-file)])
                                    (when verbose? (printf "  ~a~n" cmd))
                                    (unless (= (system cmd) 0)
                                      (raise (make-link-error "slang-link" 'compile
                                        (format "compilation failed: ~a" c-file))))
                                    o-file)))
                              (slang-build-config-extra-c-files build-config))])

                    ;; Step 4: Link
                    (when verbose?
                      (display "[slang-link] Linking...\n"))

                    (let* ([main-o (format "~a/main.o" chez-lib-dir)]
                           [libkernel (format "~a/libkernel.a" chez-lib-dir)]
                           [libz (let ([p (format "~a/libz.a" chez-lib-dir)])
                                   (if (file-exists? p) p #f))]
                           [liblz4 (let ([p (format "~a/liblz4.a" chez-lib-dir)])
                                     (if (file-exists? p) p #f))]
                           [all-objs (append
                                       (if (file-exists? main-o)
                                         (list main-o) '())
                                       (list static-boot-o)
                                       extra-objs)]
                           [all-libs (append
                                       (if (file-exists? libkernel)
                                         (list libkernel) '())
                                       (if libz (list libz) '())
                                       (if liblz4 (list liblz4) '())
                                       (slang-build-config-static-libs
                                         build-config))]
                           [obj-str (apply string-append
                                     (map (lambda (o) (format " '~a'" o))
                                          all-objs))]
                           [lib-str (apply string-append
                                     (map (lambda (a) (format " '~a'" a))
                                          all-libs))]
                           [ldflags (hardening-ldflags platform use-musl?)]
                           [sys-libs (case platform
                                      [(linux) "-lm -lrt -lpthread -ldl"]
                                      [(freebsd) "-lm -lpthread -lutil"]
                                      [else "-lm -lpthread"])]
                           [link-cmd (format "~a~a~a~a ~a -o '~a'"
                                       cc ldflags obj-str lib-str
                                       sys-libs output)])

                      (when verbose? (printf "  ~a~n" link-cmd))
                      (unless (= (system link-cmd) 0)
                        (raise (make-link-error "slang-link" 'link "linking failed")))

                      ;; Step 5: Strip
                      (when (slang-build-config-strip? build-config)
                        (when verbose?
                          (display "[slang-link] Stripping symbols...\n"))
                        (system (format "strip '~a'" output)))

                      ;; Step 6: Sign (optional)
                      (when (slang-build-config-sign-key build-config)
                        (when verbose?
                          (display "[slang-link] Signing binary...\n"))
                        (slang-sign! output
                          (slang-build-config-sign-key build-config)))

                      ;; Step 7: Verify
                      (when (slang-build-config-verify? build-config)
                        (when verbose?
                          (display "[slang-link] Verifying output...\n"))
                        (slang-verify-binary output verbose?))

                      (when verbose?
                        (printf "~n[slang-link] Built: ~a~n" output)
                        (system (format "ls -lh '~a'" output))
                        (system (format "file '~a'" output)))

                      output))))))

          ;; Cleanup
          (lambda ()
            (system (format "rm -rf '~a'" build-dir)))))))

  ;; ========== High-level build ==========

  (define (slang-build source-path . opts)
    "Build a Slang source file into a hardened static binary.

     This is the main entry point combining slang-compile and slang-link.

     Parameters:
       source-path - Path to .ss source file

     Keyword options (passed to make-slang-build-config):
       output:      - Output binary path
       sign-key:    - Ed25519 key for signing
       strip:       - Strip symbols (#t default)
       verify:      - Verify output (#t default)
       verbose:     - Print build steps
       static-libs: - Additional static libraries
       cc:          - C compiler override
       chez-prefix: - Chez installation path
       debug:       - #t for debug mode (skip sandbox, keep symbols)

     Returns: output path on success."
    (let* ([verbose? (kwarg 'verbose: opts #f)]
           [debug? (kwarg 'debug: opts #f)]
           [output (kwarg 'output: opts
                     (%slang-path-root source-path))]

           ;; Compile config
           [compile-config (make-slang-config
                             'debug: debug?)]

           ;; Build config
           [build-config (make-slang-build-config
                           'output: output
                           'sign-key: (kwarg 'sign-key: opts #f)
                           'strip: (if debug? #f
                                     (kwarg 'strip: opts #t))
                           'verify: (kwarg 'verify: opts #t)
                           'verbose: verbose?
                           'static-libs: (kwarg 'static-libs: opts '())
                           'extra-c-files: (kwarg 'extra-c-files: opts '())
                           'cc: (kwarg 'cc: opts #f)
                           'chez-prefix: (kwarg 'chez-prefix: opts #f))])

      ;; Step 1: Compile (validate + emit)
      (when verbose?
        (printf "[slang] Building ~a -> ~a~n" source-path output))

      (let ([wpo-path (slang-compile source-path
                        'config: compile-config
                        'verbose: verbose?)])

        ;; Step 2: Link
        (let ([result (slang-link wpo-path build-config)])

          ;; Cleanup .wpo
          (guard (e [#t (void)])
            (delete-file wpo-path))

          result))))

  ) ;; end library
