#!chezscheme
;;; (std os platform) — Portable OS abstraction layer
;;;
;;; Track 21: Provides platform-independent APIs for executable path,
;;; memory-backed execution, CPU count, and platform detection.
;;; Uses (machine-type) for compile-time dispatch.

(library (std os platform)
  (export
    platform-name
    platform-linux?
    platform-macos?
    platform-bsd?
    platform-executable-path
    platform-cpu-count
    platform-page-size
    platform-load-program
    platform-tmpfile-path
    platform-load-libc)

  (import (chezscheme))

  ;; ========== Platform Detection ==========

  (define (platform-name)
    (let ([mt (symbol->string (machine-type))])
      (cond
        [(or (string-contains mt "le") (string-contains mt "a6"))
         ;; Linux machine types: ta6le, ti3le, a6le, i3le, arm64le, etc.
         (if (string-contains mt "le") "linux" "unknown")]
        [(string-contains mt "osx") "macos"]
        [(string-contains mt "fb") "freebsd"]
        [(string-contains mt "ob") "openbsd"]
        [(string-contains mt "nb") "netbsd"]
        [(string-contains mt "nt") "windows"]
        [else "unknown"])))

  (define (platform-linux?)  (string=? (platform-name) "linux"))
  (define (platform-macos?)  (string=? (platform-name) "macos"))
  (define (platform-bsd?)    (member (platform-name) '("freebsd" "openbsd" "netbsd")))

  (define (string-contains str sub)
    (let ([slen (string-length str)]
          [sublen (string-length sub)])
      (let lp ([i 0])
        (cond
          [(> (+ i sublen) slen) #f]
          [(string=? (substring str i (+ i sublen)) sub) #t]
          [else (lp (+ i 1))]))))

  ;; ========== Executable Path ==========

  (define (platform-executable-path)
    (cond
      [(platform-linux?)
       ;; /proc/self/exe is a symlink to the binary
       (guard (e [#t #f])
         (let ([buf (make-bytevector 4096 0)])
           (let ([n ((foreign-procedure "readlink" (string u8* size_t) ssize_t)
                     "/proc/self/exe" buf 4096)])
             (if (> n 0)
               (let ([result (make-bytevector n)])
                 (bytevector-copy! buf 0 result 0 n)
                 (utf8->string result))
               #f))))]
      [(platform-macos?)
       ;; _NSGetExecutablePath
       (guard (e [#t #f])
         (let ([buf (make-bytevector 4096 0)]
               [size-buf (foreign-alloc 4)])
           (dynamic-wind
             void
             (lambda ()
               (foreign-set! 'unsigned-32 size-buf 0 4096)
               (let ([rc ((foreign-procedure "_NSGetExecutablePath"
                            (u8* void*) int) buf size-buf)])
                 (if (= rc 0)
                   (let* ([len (let lp ([i 0])
                                 (if (= (bytevector-u8-ref buf i) 0) i (lp (+ i 1))))]
                          [result (make-bytevector len)])
                     (bytevector-copy! buf 0 result 0 len)
                     (utf8->string result))
                   #f)))
             (lambda () (foreign-free size-buf)))))]
      [else #f]))

  ;; ========== CPU Count ==========

  (define (platform-cpu-count)
    (guard (e [#t 1])
      (cond
        [(or (platform-linux?) (platform-macos?) (platform-bsd?))
         (let ([n ((foreign-procedure "sysconf" (int) long) 84)])  ;; _SC_NPROCESSORS_ONLN
           (if (> n 0) n 1))]
        [else 1])))

  ;; ========== Page Size ==========

  (define (platform-page-size)
    (guard (e [#t 4096])
      ((foreign-procedure "getpagesize" () int))))

  ;; ========== Memory-Backed Program Loading ==========

  (define (platform-load-program program-text)
    ;; Load a Scheme program text after boot, allowing threads.
    ;; On Linux: uses memfd_create for anonymous file
    ;; Elsewhere: uses temporary file
    (cond
      [(platform-linux?)
       (load-via-memfd program-text)]
      [else
       (load-via-tmpfile program-text)]))

  (define (load-via-memfd program-text)
    (guard (e [#t (load-via-tmpfile program-text)])
      (let* ([memfd ((foreign-procedure "memfd_create" (string unsigned) int)
                     "scheme-boot" #x1)]  ;; MFD_CLOEXEC = 1
             [bv (string->utf8 program-text)]
             [n ((foreign-procedure "write" (int u8* size_t) ssize_t)
                 memfd bv (bytevector-length bv))])
        (when (< n 0)
          (error 'platform-load-program "write to memfd failed"))
        (let ([path (format "/proc/self/fd/~a" memfd)])
          (load path)
          ((foreign-procedure "close" (int) int) memfd)))))

  (define (load-via-tmpfile program-text)
    (let ([path (platform-tmpfile-path "scheme-program" ".ss")])
      (dynamic-wind
        void
        (lambda ()
          (call-with-output-file path
            (lambda (port)
              (display program-text port)))
          (load path))
        (lambda ()
          (guard (e [#t (void)])
            (delete-file path))))))

  (define (platform-tmpfile-path prefix suffix)
    (let ([dir (or (getenv "TMPDIR") "/tmp")])
      (format "~a/~a-~a~a" dir prefix (random 999999999) suffix)))

  ;; ========== Portable libc Loading ==========

  (define (platform-load-libc)
    (or (guard (e [#t #f]) (load-shared-object "libc.so.7"))       ;; FreeBSD
        (guard (e [#t #f]) (load-shared-object "libc.so.6"))       ;; Linux (glibc)
        (guard (e [#t #f]) (load-shared-object "libc.dylib"))      ;; macOS
        (guard (e [#t #f]) (load-shared-object "libc.so"))         ;; generic fallback
        (error 'platform-load-libc "cannot find libc shared object")))

  ) ;; end library
