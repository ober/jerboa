#!chezscheme
;;; (jerboa build musl) — Static Binary Delivery with musl libc
;;;
;;; Provides musl-specific build functionality for creating fully static
;;; executables with zero runtime dependencies.

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
  
  ;; Path to musl-built Chez Scheme installation
  ;; Default: /opt/chez-musl (can be overridden)
  (define *musl-chez-prefix* 
    (make-parameter 
      (or (getenv "JERBOA_MUSL_CHEZ_PREFIX")
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
            (let ([trimmed (musl-string-trim-right line)])
              (if (string=? trimmed "") #f trimmed)))))))
  
  (define (musl-string-trim-right s)
    (let loop ([i (- (string-length s) 1)])
      (if (< i 0)
        ""
        (if (char-whitespace? (string-ref s i))
          (loop (- i 1))
          (substring s 0 (+ i 1))))))
  
  (define (musl-gcc-path)
    "Return path to musl-gcc wrapper, or #f if not found"
    (or (find-musl-executable "musl-gcc")
        (find-musl-executable "x86_64-linux-musl-gcc")))
  
  (define (musl-available?)
    "Check if musl toolchain is available"
    (and (musl-gcc-path) #t))
  
  (define (musl-sysroot)
    "Return the musl sysroot directory"
    ;; Query musl-gcc for its sysroot
    (let ([gcc (musl-gcc-path)])
      (if gcc
        (let ([result (with-output-to-string
                        (lambda ()
                          (system (format "~a -print-sysroot 2>/dev/null" gcc))))])
          (let ([trimmed (musl-string-trim-right result)])
            (if (string=? trimmed "")
              ;; Fallback: standard musl location
              "/usr/lib/x86_64-linux-musl"
              trimmed)))
        #f)))

  ;; ========== Path Resolution ==========
  
  (define (chez-machine-type)
    "Return the Chez Scheme machine type (e.g., ta6le)"
    (symbol->string (machine-type)))
  
  (define (musl-libkernel-path)
    "Return path to musl-built libkernel.a"
    (let* ([prefix (musl-chez-prefix)]
           [machine (chez-machine-type)]
           ;; Try common patterns
           [paths (list
                    (format "~a/lib/csv~a/~a/libkernel.a" 
                            prefix (scheme-version) machine)
                    (format "~a/lib/~a/libkernel.a" prefix machine)
                    (format "~a/libkernel.a" prefix))])
      (let loop ([ps paths])
        (if (null? ps)
          (error 'musl-libkernel-path 
                 "Cannot find musl libkernel.a" 
                 (musl-chez-prefix))
          (if (file-exists? (car ps))
            (car ps)
            (loop (cdr ps)))))))
  
  (define (musl-boot-files)
    "Return list of (name . path) for musl-built boot files"
    (let* ([prefix (musl-chez-prefix)]
           [machine (chez-machine-type)]
           [boot-dir (format "~a/lib/csv~a/~a" 
                            prefix (scheme-version) machine)])
      (if (file-directory? boot-dir)
        (list
          (cons "petite" (format "~a/petite.boot" boot-dir))
          (cons "scheme" (format "~a/scheme.boot" boot-dir)))
        (error 'musl-boot-files
               "Cannot find musl boot directory"
               boot-dir))))
  
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
      
      [(not (file-exists? (musl-chez-prefix)))
       (cons 'error 
             (format "musl Chez prefix not found: ~a\n\
                     Build Chez with musl or set JERBOA_MUSL_CHEZ_PREFIX"
                     (musl-chez-prefix)))]
      
      [(guard (e [#t #f]) (musl-libkernel-path) #t)
       => (lambda (_)
            (let ([crt (musl-crt-objects)])
              (let loop ([objs crt])
                (if (null? objs)
                  (cons 'ok "musl toolchain validated")
                  (if (file-exists? (car objs))
                    (loop (cdr objs))
                    (cons 'error 
                          (format "CRT object not found: ~a" 
                                  (car objs))))))))]
      
      [else
       (cons 'error "musl libkernel.a not found")]))

  ;; ========== Link Command Generation ==========
  
  (define (musl-link-command output-path object-files static-libs)
    "Generate the musl-gcc link command for a static binary.
     
     Parameters:
       output-path  - Path for the output executable
       object-files - List of .o files to link
       static-libs  - List of additional .a archives
     
     Returns: Command string"
    (let* ([gcc (musl-gcc-path)]
           [libkernel (musl-libkernel-path)]
           [crt (musl-crt-objects)]
           [crt1 (car crt)]
           [crti (cadr crt)]
           [crtn (caddr crt)]
           [sysroot (musl-sysroot)]
           
           ;; Object files as space-separated string
           [objs (apply string-append
                   (map (lambda (o) (format " '~a'" o))
                        object-files))]
           
           ;; Static libraries
           [libs (apply string-append
                   (map (lambda (a) (format " '~a'" a))
                        static-libs))]
           
           ;; Standard libraries (provided by musl)
           [std-libs "-lm -lpthread"])
      
      ;; Full link command
      ;; Note: Order matters! CRT objects must be first and last
      (format "~a -static -nostdlib \
               '~a' '~a' \
               ~a \
               '~a' \
               ~a \
               ~a \
               '~a' \
               -o '~a'"
              gcc
              crt1 crti        ;; CRT start objects
              objs             ;; Application objects
              libkernel        ;; Chez runtime
              libs             ;; User static libs (zlib, lz4, etc.)
              std-libs         ;; musl libc
              crtn             ;; CRT end object
              output-path)))

  ;; ========== High-Level Build ==========
  
  (define (build-musl-binary source-path output-path . opts)
    "Build a fully static binary using musl libc.
     
     Parameters:
       source-path - Path to main .sls source file
       output-path - Path for output executable
     
     Keyword options:
       optimize-level: - Optimization level (0-3, default 2)
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
           [static-libs (%musl-kwarg 'static-libs: opts '())]
           [extra-c (%musl-kwarg 'extra-c-files: opts '())]
           [extra-cflags (%musl-kwarg 'extra-cflags: opts "")]
           [verbose? (%musl-kwarg 'verbose: opts #f)]
           
           ;; Build directory
           [build-dir (format "/tmp/jerboa-musl-~a" (current-time))]
           [gcc (musl-gcc-path)])
      
      ;; Create build directory
      (system (format "mkdir -p '~a'" build-dir))
      
      (dynamic-wind
        (lambda () #f)
        
        (lambda ()
          ;; Step 1: Compile Scheme to .so
          (when verbose? (display "[1/5] Compiling Scheme...\n"))
          (let ([so-path (format "~a/program.so" build-dir)])
            (parameterize ([optimize-level opt-level]
                           [generate-inspector-information #f])
              (compile-program source-path so-path))
            
            ;; Step 2: Generate boot file
            (when verbose? (display "[2/5] Creating boot file...\n"))
            (let ([app-boot (format "~a/app.boot" build-dir)]
                  [boots (musl-boot-files)])
              (make-boot-file app-boot 
                              (list "petite" "scheme")
                              so-path)
              
              ;; Step 3: Generate C main with embedded boot files
              (when verbose? (display "[3/5] Generating C...\n"))
              (let ([main-c (format "~a/main.c" build-dir)])
                (generate-musl-main-c main-c
                                      (map cdr boots)  ;; boot file paths
                                      app-boot
                                      so-path)
                
                ;; Step 4: Compile C files
                (when verbose? (display "[4/5] Compiling C...\n"))
                (let* ([main-o (format "~a/main.o" build-dir)]
                       [compile-cmd 
                        (format "~a -c -static -O2 ~a -o '~a' '~a'"
                                gcc extra-cflags main-o main-c)]
                       [rc (system compile-cmd)])
                  (unless (= rc 0)
                    (error 'build-musl-binary 
                           "C compilation failed" 
                           compile-cmd))
                  
                  ;; Compile extra C files
                  (let ([extra-objs
                         (map (lambda (c-file)
                                (let ([o-file (format "~a/~a.o" 
                                                build-dir
                                                (%musl-path-root (%musl-path-last c-file)))])
                                  (let ([cmd (format "~a -c -static -O2 ~a -o '~a' '~a'"
                                                     gcc extra-cflags o-file c-file)])
                                    (unless (= (system cmd) 0)
                                      (error 'build-musl-binary
                                             "Extra C compilation failed"
                                             cmd))
                                    o-file)))
                              extra-c)])
                    
                    ;; Step 5: Link
                    (when verbose? (display "[5/5] Linking...\n"))
                    (let* ([all-objs (cons main-o extra-objs)]
                           [link-cmd (musl-link-command 
                                      output-path 
                                      all-objs
                                      static-libs)]
                           [rc (system link-cmd)])
                      (unless (= rc 0)
                        (error 'build-musl-binary
                               "Linking failed"
                               link-cmd))
                      
                      ;; Success
                      (when verbose?
                        (display (format "Built: ~a\n" output-path)))
                      output-path)))))))
        
        ;; Cleanup
        (lambda ()
          (system (format "rm -rf '~a'" build-dir))))))

  ;; ========== C Code Generation ==========
  
  (define (generate-musl-main-c output-path boot-paths app-boot-path so-path)
    "Generate the C main() that embeds boot files and initializes Chez.
     
     This is similar to generate-main-c from (jerboa build) but includes
     musl-specific adjustments:
     - No dlopen (all code is statically linked)
     - memfd_create for loading the program .so"
    
    (call-with-output-file output-path
      (lambda (out)
        ;; Includes
        (display "#define _GNU_SOURCE\n" out)
        (display "#include <stdio.h>\n" out)
        (display "#include <stdlib.h>\n" out)
        (display "#include <string.h>\n" out)
        (display "#include <unistd.h>\n" out)
        (display "#include <sys/mman.h>\n" out)
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
        
        ;; Embed program .so
        (display (file->c-array so-path "program_so") out)
        (newline out)
        
        ;; Main function
        (display "
int main(int argc, char *argv[]) {
    /* Save arguments in environment (bypass Chez arg parsing) */
    char buf[32];
    snprintf(buf, sizeof(buf), \"%d\", argc - 1);
    setenv(\"JERBOA_ARGC\", buf, 1);
    for (int i = 1; i < argc; i++) {
        snprintf(buf, sizeof(buf), \"JERBOA_ARG%d\", i - 1);
        setenv(buf, argv[i], 1);
    }
    
    /* Initialize Chez Scheme */
    Sscheme_init(NULL);
    
    /* Register boot files from embedded data */
    Sregister_boot_file_bytes(\"petite\", petite_boot, petite_boot_len);
    Sregister_boot_file_bytes(\"scheme\", scheme_boot, scheme_boot_len);
    Sregister_boot_file_bytes(\"app\", app_boot, app_boot_len);
    
    /* Build the heap */
    Sbuild_heap(NULL, NULL);
    
    /* Load program via memfd (Linux-specific) */
    int fd = memfd_create(\"jerboa-program\", MFD_CLOEXEC);
    if (fd < 0) {
        perror(\"memfd_create\");
        return 1;
    }
    
    if (write(fd, program_so, program_so_len) != (ssize_t)program_so_len) {
        perror(\"write program\");
        return 1;
    }
    
    char prog_path[64];
    snprintf(prog_path, sizeof(prog_path), \"/proc/self/fd/%d\", fd);
    
    /* Run the program */
    int status = Sscheme_script(prog_path, 0, NULL);
    
    /* Cleanup */
    close(fd);
    Sscheme_deinit();
    
    return status;
}
" out))))

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
  
  (define (%musl-path-root path)
    "Return path without extension"
    (let ([dot (%musl-string-index-right path #\.)])
      (if dot (substring path 0 dot) path)))
  
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
