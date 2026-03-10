#!chezscheme
;;; (jerboa build) — Static native binary builder
;;;
;;; Automates the process of building a standalone ELF binary from a
;;; Scheme program:
;;;   1. Trace imports to build dependency graph
;;;   2. Compile all libraries
;;;   3. Create boot file (libraries in dependency order)
;;;   4. Compile the program
;;;   5. Serialize boot + program as C byte arrays
;;;   6. Generate C main + link to produce ELF binary
;;;
;;; Usage:
;;;   (build-binary "myapp.ss" "myapp" '())  ;; basic
;;;   (build-binary "myapp.ss" "myapp" '(optimize-level: 3 release: #t))

(library (jerboa build)
  (export
    build-binary
    build-boot-file
    file->c-array
    generate-main-c
    trace-imports)
  (import (chezscheme))

  ;; ========== Import Tracing ==========

  ;; Extract import forms from a Scheme file (simple regex-free approach)
  (define (trace-imports source-path)
    (let ([imports '()])
      (guard (exn [#t imports])
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

  ;; ========== File → C Array ==========

  ;; Convert a binary file to a C byte array declaration
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

  ;; ========== C Main Template ==========

  (define (generate-main-c boot-arrays program-array link-libs)
    (call-with-string-output-port
      (lambda (port)
        (display "#include <scheme.h>\n" port)
        (display "#include <string.h>\n" port)
        (display "#include <stdlib.h>\n\n" port)

        ;; Embed byte arrays
        (for-each (lambda (arr) (display arr port) (newline port))
                  boot-arrays)
        (when program-array
          (display program-array port)
          (newline port))

        ;; memfd_create for Linux
        (display "#ifdef __linux__\n" port)
        (display "#include <sys/mman.h>\n" port)
        (display "#ifndef MFD_CLOEXEC\n" port)
        (display "#define MFD_CLOEXEC 1\n" port)
        (display "#endif\n" port)
        (display "extern int memfd_create(const char *, unsigned int);\n" port)
        (display "#endif\n\n" port)

        (display "int main(int argc, const char *argv[]) {\n" port)
        (display "    Sscheme_init(NULL);\n\n" port)

        ;; Register boot files
        (display "    Sregister_boot_file_bytes(\"petite\", petite_boot, petite_boot_len);\n" port)
        (display "    Sregister_boot_file_bytes(\"scheme\", scheme_boot, scheme_boot_len);\n" port)
        (display "    Sregister_boot_file_bytes(\"app\", app_boot, app_boot_len);\n" port)

        (display "\n    Sbuild_heap(argv[0], NULL);\n\n" port)

        ;; Load program via memfd
        (when program-array
          (display "    #ifdef __linux__\n" port)
          (display "    {\n" port)
          (display "        int fd = memfd_create(\"program\", MFD_CLOEXEC);\n" port)
          (display "        write(fd, program_so, program_so_len);\n" port)
          (display "        lseek(fd, 0, SEEK_SET);\n" port)
          (display "        char path[64];\n" port)
          (display "        snprintf(path, sizeof(path), \"/proc/self/fd/%d\", fd);\n" port)
          (display "        Sscheme_script(\"(load \\\")\", 0, NULL);\n" port)
          (display "    }\n" port)
          (display "    #endif\n\n" port))

        (display "    Sscheme_deinit();\n" port)
        (display "    return 0;\n" port)
        (display "}\n" port))))

  ;; ========== Build Pipeline ==========

  (define (build-binary source-path output-path options)
    (let* ([opt-level (or (getprop options 'optimize-level:) 2)]
           [release? (getprop options 'release:)]
           [lib-dirs (library-directories)]
           [build-dir (string-append "/tmp/jerboa-build-" (number->string (random 100000)))])

      ;; Create build directory
      (system (format "mkdir -p '~a'" build-dir))

      (parameterize ([optimize-level (if release? 3 opt-level)]
                     [compile-imported-libraries #t]
                     [generate-inspector-information (not release?)])

        ;; Step 1: Compile the program and all dependencies
        (printf "  [1/5] Compiling ~a...~%" source-path)
        (let ([so-path (string-append build-dir "/program.so")])
          (compile-program source-path so-path)

          ;; Step 2: Find Chez boot files
          (printf "  [2/5] Locating boot files...~%")
          (let* ([chez-lib (or (getenv "SCHEMEHEAPDIRS")
                               (format "~a/lib/csv~a"
                                 (path-parent (path-parent (car (library-directories))))
                                 (scheme-version)))]
                 [petite-boot (find-boot-file "petite.boot")]
                 [scheme-boot (find-boot-file "scheme.boot")])

            ;; Step 3: Create application boot file
            (printf "  [3/5] Creating boot file...~%")
            (let ([app-boot (string-append build-dir "/app.boot")])
              (when (file-exists? so-path)
                (make-boot-file app-boot '("petite" "scheme") so-path))

              ;; Step 4: Generate C main
              (printf "  [4/5] Generating C code...~%")
              (let* ([petite-c (file->c-array petite-boot "petite_boot")]
                     [scheme-c (file->c-array scheme-boot "scheme_boot")]
                     [app-c (file->c-array app-boot "app_boot")]
                     [program-c (file->c-array so-path "program_so")]
                     [main-c (generate-main-c
                               (list petite-c scheme-c app-c)
                               program-c
                               '())]
                     [main-path (string-append build-dir "/main.c")])
                (call-with-output-file main-path
                  (lambda (p) (display main-c p)))

                ;; Step 5: Compile and link
                (printf "  [5/5] Linking ~a...~%" output-path)
                (let ([cmd (format "gcc -rdynamic -o '~a' '~a' -lkernel -llz4 -lz -lm -ldl -lpthread -lncurses 2>&1"
                             output-path main-path)])
                  (let ([rc (system cmd)])
                    (if (= rc 0)
                      (printf "  Built: ~a~%" output-path)
                      (printf "  Link failed (rc=~a). Run manually: ~a~%" rc cmd))))))))))

      ;; Cleanup
      ;; (system (format "rm -rf '~a'" build-dir))
      ))

  ;; Find a boot file in standard locations
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

  (define (getprop alist key)
    (cond
      [(null? alist) #f]
      [(eq? (car alist) key)
       (if (null? (cdr alist)) #t (cadr alist))]
      [else (getprop (cddr alist) key)]))

  ) ;; end library
