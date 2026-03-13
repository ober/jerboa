#!chezscheme
;;; (jerboa build musl) — Static Binary Delivery with musl libc
;;;
;;; Builds fully static executables using:
;;; - musl-gcc for C compilation
;;; - A musl-built Chez Scheme (configured with --static CC=musl-gcc)
;;; - Chez's native static boot embedding (main.o + static_boot_init)
;;;
;;; The musl-built Chez installation provides:
;;;   main.o       — Chez's own main() with arg parsing, REPL, --script, etc.
;;;   libkernel.a  — The Chez runtime (compiled with musl)
;;;   libz.a       — zlib (compiled with musl)
;;;   liblz4.a     — lz4 (compiled with musl)
;;;   scheme.h     — C header for Chez API
;;;   *.boot       — Boot files to embed
;;;
;;; We generate a static_boot.c that provides static_boot_init(), which
;;; main.o calls to register embedded boot files. The application's compiled
;;; .so is bundled into an app boot file via make-boot-file.

(library (jerboa build musl)
  (export
    ;; Detection
    musl-available?
    musl-gcc-path
    musl-sysroot
    
    ;; Configuration
    musl-chez-prefix
    musl-chez-prefix-set!
    
    ;; Build
    build-musl-binary
    musl-link-command
    
    ;; Paths
    musl-libkernel-path
    musl-chez-lib-dir
    musl-boot-files
    musl-crt-objects
    
    ;; Validation
    validate-musl-setup
    
    ;; Cross-compilation
    make-musl-cross-target
    musl-cross-available?)
  
  (import (chezscheme)
          (jerboa build))

  ;; ========== Configuration ==========
  
  ;; Path to musl-built Chez Scheme installation.
  ;; Probed in order: $JERBOA_MUSL_CHEZ_PREFIX, ~/chez-musl, /opt/chez-musl
  (define *musl-chez-prefix* 
    (make-parameter 
      (or (getenv "JERBOA_MUSL_CHEZ_PREFIX")
          (let ([home-prefix (format "~a/chez-musl" (getenv "HOME"))])
            (if (file-directory? home-prefix) home-prefix #f))
          "/opt/chez-musl")))
  
  (define (musl-chez-prefix) (*musl-chez-prefix*))
  (define (musl-chez-prefix-set! path) (*musl-chez-prefix* path))

  ;; ========== Detection ==========
  
  (define (find-musl-executable name)
    "Search PATH for an executable, return full path or #f"
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
          (if (eof-object? line)
            #f
            (let ([trimmed (%musl-string-trim-right line)])
              (if (string=? trimmed "") #f trimmed)))))))
  
  (define (musl-gcc-path)
    "Return path to musl-gcc wrapper, or #f if not found"
    (or (find-musl-executable "musl-gcc")
        (find-musl-executable "x86_64-linux-musl-gcc")))
  
  (define (musl-available?)
    "Check if musl toolchain is available"
    (and (musl-gcc-path) #t))
  
  (define (musl-sysroot)
    "Return the musl sysroot directory"
    (let ([gcc (musl-gcc-path)])
      (if gcc
        (let ([result (with-output-to-string
                        (lambda ()
                          (system (format "~a -print-sysroot 2>/dev/null" gcc))))])
          (let ([trimmed (%musl-string-trim-right result)])
            (if (string=? trimmed "")
              ;; Fallback: standard musl location
              "/usr/lib/x86_64-linux-musl"
              trimmed)))
        #f)))

  ;; ========== Path Resolution ==========
  
  (define (chez-machine-type)
    "Return the Chez Scheme machine type (e.g., ta6le)"
    (symbol->string (machine-type)))
  
  (define (musl-chez-lib-dir)
    "Find the csv<version>/<machine> directory under the musl Chez prefix.
     Scans lib/ for csv* directories since (scheme-version) returns a
     human-readable string unsuitable for path construction."
    (let* ([prefix (musl-chez-prefix)]
           [machine (chez-machine-type)]
           [lib-dir (format "~a/lib" prefix)])
      (if (not (file-directory? lib-dir))
        (error 'musl-chez-lib-dir
               "Chez musl lib directory not found" lib-dir)
        ;; Scan for csv* directories, pick the newest (last sorted)
        (let* ([entries (directory-list lib-dir)]
               [csv-dirs (filter
                           (lambda (e)
                             (and (> (string-length e) 3)
                                  (string=? (substring e 0 3) "csv")))
                           entries)]
               ;; Sort so the highest version comes last
               [sorted (sort string<? csv-dirs)])
          (if (null? sorted)
            (error 'musl-chez-lib-dir
                   "No csv* directory found in" lib-dir)
            ;; Try each csv dir (newest first) for one containing machine/
            (let loop ([dirs (reverse sorted)])
              (if (null? dirs)
                (error 'musl-chez-lib-dir
                       "No csv*/<machine> directory found"
                       (cons lib-dir machine))
                (let ([candidate (format "~a/~a/~a" lib-dir (car dirs) machine)])
                  (if (file-directory? candidate)
                    candidate
                    (loop (cdr dirs)))))))))))
  
  (define (musl-libkernel-path)
    "Return path to musl-built libkernel.a"
    (let ([path (format "~a/libkernel.a" (musl-chez-lib-dir))])
      (if (file-exists? path)
        path
        (error 'musl-libkernel-path 
               "Cannot find musl libkernel.a" path))))
  
  (define (musl-boot-files)
    "Return list of (name . path) for musl-built boot files"
    (let ([dir (musl-chez-lib-dir)])
      (let ([petite (format "~a/petite.boot" dir)]
            [scheme (format "~a/scheme.boot" dir)])
        (unless (file-exists? petite)
          (error 'musl-boot-files "petite.boot not found" petite))
        (unless (file-exists? scheme)
          (error 'musl-boot-files "scheme.boot not found" scheme))
        (list
          (cons "petite" petite)
          (cons "scheme" scheme)))))
  
  (define (musl-scheme-h-path)
    "Return path to scheme.h from musl Chez installation"
    (let ([path (format "~a/scheme.h" (musl-chez-lib-dir))])
      (if (file-exists? path)
        path
        (error 'musl-scheme-h-path "scheme.h not found" path))))
  
  (define (musl-main-o-path)
    "Return path to main.o from musl Chez installation"
    (let ([path (format "~a/main.o" (musl-chez-lib-dir))])
      (if (file-exists? path)
        path
        (error 'musl-main-o-path "main.o not found" path))))
  
  (define (musl-libz-path)
    "Return path to libz.a (zlib) from musl Chez installation, or #f"
    (let ([path (format "~a/libz.a" (musl-chez-lib-dir))])
      (if (file-exists? path) path #f)))
  
  (define (musl-liblz4-path)
    "Return path to liblz4.a from musl Chez installation, or #f"
    (let ([path (format "~a/liblz4.a" (musl-chez-lib-dir))])
      (if (file-exists? path) path #f)))
  
  (define (musl-crt-objects)
    "Return paths to musl CRT objects needed for static linking"
    (let ([sysroot (or (musl-sysroot) "/usr/lib/x86_64-linux-musl")])
      (list
        (format "~a/crt1.o" sysroot)
        (format "~a/crti.o" sysroot)
        (format "~a/crtn.o" sysroot))))

  ;; ========== Validation ==========
  
  (define (validate-musl-setup)
    "Validate that musl toolchain is properly configured. 
     Returns (ok . message) or (error . message)"
    (cond
      [(not (musl-available?))
       (cons 'error "musl-gcc not found. Install musl-tools package.")]
      
      [(not (file-directory? (musl-chez-prefix)))
       (cons 'error 
             (format "musl Chez prefix not found: ~a\n\
                     Build Chez with: ./configure --threads --static CC=musl-gcc\n\
                     Then: make install"
                     (musl-chez-prefix)))]
      
      [(guard (e [#t #f]) (musl-chez-lib-dir) #t)
       => (lambda (_)
            (cond
              [(not (guard (e [#t #f]) (musl-libkernel-path) #t))
               (cons 'error "musl libkernel.a not found")]
              [(not (guard (e [#t #f]) (musl-main-o-path) #t))
               (cons 'error "musl main.o not found (Chez not built with --static?)")]
              [(not (guard (e [#t #f]) (musl-scheme-h-path) #t))
               (cons 'error "scheme.h not found in musl Chez installation")]
              [else
               (let ([crt (musl-crt-objects)])
                 (let loop ([objs crt])
                   (if (null? objs)
                     (cons 'ok 
                           (format "musl toolchain validated (~a)" 
                                   (musl-chez-lib-dir)))
                     (if (file-exists? (car objs))
                       (loop (cdr objs))
                       (cons 'error 
                             (format "CRT object not found: ~a" 
                                     (car objs)))))))]))]
      
      [else
       (cons 'error 
             (format "Cannot locate csv*/<machine> directory under ~a"
                     (musl-chez-prefix)))]))

  ;; ========== Link Command Generation ==========
  
  (define (musl-link-command output-path object-files static-libs)
    "Generate the musl-gcc link command for a static binary.
     
     Uses musl-gcc -static which handles CRT objects and -lc automatically.
     We only need to specify our object files, libkernel.a, and any extra
     static libraries.
     
     Parameters:
       output-path  - Path for the output executable
       object-files - List of .o files to link
       static-libs  - List of additional .a archives
     
     Returns: Command string"
    (let* ([gcc (musl-gcc-path)]
           [libkernel (musl-libkernel-path)]
           [libz (musl-libz-path)]
           [liblz4 (musl-liblz4-path)]
           
           ;; Object files as space-separated string
           [objs (apply string-append
                   (map (lambda (o) (format " '~a'" o))
                        object-files))]
           
           ;; Chez runtime archives
           [chez-libs (apply string-append
                       (filter values
                         (list (format " '~a'" libkernel)
                               (and libz (format " '~a'" libz))
                               (and liblz4 (format " '~a'" liblz4)))))]
           
           ;; User static libraries
           [user-libs (apply string-append
                       (map (lambda (a) (format " '~a'" a))
                            static-libs))]
           
           ;; Standard libraries needed by Chez runtime
           [std-libs "-lm -lrt -lpthread"])
      
      ;; musl-gcc -static handles CRT objects and libc linking automatically
      (format "~a -static~a~a~a ~a -o '~a'"
              gcc
              objs             ;; Application + Chez main.o + static_boot.o
              chez-libs        ;; Chez runtime archives
              user-libs        ;; User static libs
              std-libs         ;; Math, rt, pthreads
              output-path)))

  ;; ========== High-Level Build ==========
  
  (define (build-musl-binary source-path output-path . opts)
    "Build a fully static binary using musl libc.
     
     Uses the Chez Scheme static build infrastructure:
     - The installed main.o provides main() with argument parsing
     - We generate static_boot.c with embedded boot files
     - The application .so is bundled into an app boot file
     
     Parameters:
       source-path - Path to main .ss/.sls source file
       output-path - Path for output executable
     
     Keyword options:
       optimize-level: - Optimization level (0-3, default 2)
       libdirs:        - Library directories for compilation (colon-separated or list)
       static-libs:    - Additional static libraries to link
       extra-c-files:  - Additional C files to compile
       extra-cflags:   - Additional C compiler flags
       verbose:        - Print commands as they execute
     
     Returns: output-path on success, raises on error"
    
    ;; Validate setup first
    (let ([status (validate-musl-setup)])
      (unless (eq? (car status) 'ok)
        (error 'build-musl-binary (cdr status))))
    
    ;; Parse options
    (let* ([opt-level (%musl-kwarg 'optimize-level: opts 2)]
           [libdirs (%musl-kwarg 'libdirs: opts #f)]
           [static-libs (%musl-kwarg 'static-libs: opts '())]
           [extra-c (%musl-kwarg 'extra-c-files: opts '())]
           [extra-cflags (%musl-kwarg 'extra-cflags: opts "")]
           [verbose? (%musl-kwarg 'verbose: opts #f)]
           
           ;; Build directory
           [build-dir (format "/tmp/jerboa-musl-~a" 
                              (time-second (current-time)))]
           [gcc (musl-gcc-path)]
           [scheme-h-dir (let ([p (musl-scheme-h-path)])
                           ;; directory containing scheme.h
                           (%musl-path-dir p))]
           [chez-main-o (musl-main-o-path)])
      
      ;; Create build directory
      (system (format "mkdir -p '~a'" build-dir))
      
      (dynamic-wind
        (lambda () #f)
        
        (lambda ()
          ;; Step 1: Compile Scheme to .so
          (when verbose? (printf "[1/5] Compiling Scheme source: ~a~n" source-path))
          (let ([so-path (format "~a/program.so" build-dir)])
            (parameterize ([optimize-level opt-level]
                           [compile-imported-libraries #t]
                           [generate-inspector-information #f])
              (compile-program source-path so-path))
            
            ;; Step 2: Create app boot file (bundles the .so into a boot file)
            (when verbose? (display "[2/5] Creating boot file...\n"))
            (let* ([boots (musl-boot-files)]
                   [app-boot (format "~a/app.boot" build-dir)])
              (make-boot-file app-boot 
                              (list "petite" "scheme")
                              so-path)
              
              ;; Step 3: Generate static_boot.c (embeds all boot files)
              (when verbose? (display "[3/5] Generating static_boot.c...\n"))
              (let ([static-boot-c (format "~a/static_boot.c" build-dir)])
                (generate-static-boot-c static-boot-c
                                        (map cdr boots)   ;; petite.boot, scheme.boot paths
                                        app-boot)
                
                ;; Step 4: Compile C files
                (when verbose? (display "[4/5] Compiling C...\n"))
                (let* ([static-boot-o (format "~a/static_boot.o" build-dir)]
                       [include-flag (format "-I'~a'" scheme-h-dir)]
                       [compile-cmd 
                        (format "~a -c -O2 ~a ~a -o '~a' '~a'"
                                gcc include-flag extra-cflags
                                static-boot-o static-boot-c)]
                       [rc (begin
                             (when verbose? (printf "  ~a~n" compile-cmd))
                             (system compile-cmd))])
                  (unless (= rc 0)
                    (error 'build-musl-binary 
                           "static_boot.c compilation failed" 
                           compile-cmd))
                  
                  ;; Compile extra C files
                  (let ([extra-objs
                         (map (lambda (c-file)
                                (let ([o-file (format "~a/~a.o" 
                                                build-dir
                                                (%musl-path-root 
                                                  (%musl-path-last c-file)))])
                                  (let ([cmd (format "~a -c -O2 ~a ~a -o '~a' '~a'"
                                                     gcc include-flag extra-cflags 
                                                     o-file c-file)])
                                    (when verbose? (printf "  ~a~n" cmd))
                                    (unless (= (system cmd) 0)
                                      (error 'build-musl-binary
                                             "Extra C compilation failed"
                                             cmd))
                                    o-file)))
                              extra-c)])
                    
                    ;; Step 5: Link
                    (when verbose? (display "[5/5] Linking...\n"))
                    (let* ([all-objs (cons* chez-main-o 
                                            static-boot-o
                                            extra-objs)]
                           [link-cmd (musl-link-command 
                                      output-path 
                                      all-objs
                                      static-libs)]
                           [rc (begin
                                 (when verbose? (printf "  ~a~n" link-cmd))
                                 (system link-cmd))])
                      (unless (= rc 0)
                        (error 'build-musl-binary
                               "Linking failed"
                               link-cmd))
                      
                      ;; Success
                      (when verbose?
                        (printf "~nBuilt: ~a~n" output-path)
                        (system (format "ls -lh '~a'" output-path))
                        (system (format "file '~a'" output-path)))
                      output-path)))))))
        
        ;; Cleanup
        (lambda ()
          (system (format "rm -rf '~a'" build-dir))))))

  ;; ========== C Code Generation ==========
  
  (define (generate-static-boot-c output-path boot-paths app-boot-path)
    "Generate static_boot.c that provides static_boot_init().
     
     This function is called by Chez's own main.o (compiled with 
     -DSTATIC_BOOT=static_boot_init) to register embedded boot files
     before Sbuild_heap() is called.
     
     Boot files are embedded as C byte arrays using file->c-array
     from (jerboa build)."
    
    (call-with-output-file output-path
      (lambda (out)
        (display "#include \"scheme.h\"\n\n" out)
        
        ;; Embed boot files as C arrays
        (for-each
          (lambda (boot-path)
            (let ([name (%musl-path-root (%musl-path-last boot-path))])
              (display (file->c-array boot-path 
                                      (format "~a_boot" name)) 
                       out)
              (newline out)))
          boot-paths)
        
        ;; Embed app boot
        (display (file->c-array app-boot-path "app_boot") out)
        (newline out)
        
        ;; The static_boot_init function
        (display "void static_boot_init(void) {\n" out)
        (for-each
          (lambda (boot-path)
            (let ([name (%musl-path-root (%musl-path-last boot-path))])
              (fprintf out 
                "    Sregister_boot_file_bytes(\"~a\", ~a_boot, ~a_boot_len);\n"
                name name name)))
          boot-paths)
        (display 
          "    Sregister_boot_file_bytes(\"app\", app_boot, app_boot_len);\n" 
          out)
        (display "}\n" out)))
    
    output-path)

  ;; ========== Cross-Compilation ==========
  
  (define (make-musl-cross-target arch)
    "Create a cross-compilation target for musl.
     
     Supported architectures:
       'x86-64   - x86_64-linux-musl-gcc
       'aarch64  - aarch64-linux-musl-gcc
       'armhf    - arm-linux-musleabihf-gcc
       'riscv64  - riscv64-linux-musl-gcc"
    (let ([prefix (case arch
                    [(x86-64)  "x86_64-linux-musl"]
                    [(aarch64) "aarch64-linux-musl"]
                    [(armhf)   "arm-linux-musleabihf"]
                    [(riscv64) "riscv64-linux-musl"]
                    [else (error 'make-musl-cross-target
                                 "Unknown architecture" arch)])])
      (make-cross-target 'linux arch
                         (format "~a-gcc" prefix)
                         (format "~a-ar" prefix))))
  
  (define (musl-cross-available? arch)
    "Check if cross-compilation toolchain for arch is available"
    (let ([target (make-musl-cross-target arch)])
      (and (find-musl-executable (cross-target-cc target)) #t)))

  ;; ========== Helpers ==========
  
  (define (%musl-kwarg key opts . default-args)
    (let ([default (if (null? default-args) #f (car default-args))])
      (let loop ([lst opts])
        (cond [(or (null? lst) (null? (cdr lst))) default]
              [(eq? (car lst) key) (cadr lst)]
              [else (loop (cddr lst))]))))
  
  (define (%musl-path-last path)
    "Return the last component of a path"
    (let ([parts (%musl-string-split path #\/)])
      (if (null? parts) path (car (reverse parts)))))
  
  (define (%musl-path-dir path)
    "Return the directory portion of a path"
    (let ([idx (%musl-string-index-right path #\/)])
      (if idx (substring path 0 idx) ".")))
  
  (define (%musl-path-root path)
    "Return path without extension"
    (let ([dot (%musl-string-index-right path #\.)])
      (if dot (substring path 0 dot) path)))
  
  (define (%musl-string-trim-right s)
    (let loop ([i (- (string-length s) 1)])
      (if (< i 0)
        ""
        (if (char-whitespace? (string-ref s i))
          (loop (- i 1))
          (substring s 0 (+ i 1))))))
  
  (define (%musl-string-split str char)
    (let loop ([chars (string->list str)] [current '()] [result '()])
      (cond
        [(null? chars)
         (reverse (if (null? current) 
                    result 
                    (cons (list->string (reverse current)) result)))]
        [(char=? (car chars) char)
         (loop (cdr chars) 
               '() 
               (if (null? current)
                 result
                 (cons (list->string (reverse current)) result)))]
        [else
         (loop (cdr chars) (cons (car chars) current) result)])))
  
  (define (%musl-string-index-right str char)
    (let loop ([i (- (string-length str) 1)])
      (if (< i 0)
        #f
        (if (char=? (string-ref str i) char)
          i
          (loop (- i 1))))))

  ) ;; end library
