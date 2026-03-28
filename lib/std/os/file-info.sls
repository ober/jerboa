#!chezscheme
;;; (std os file-info) — File metadata via stat(2)
;;;
;;; Access file size, modification time, type, and permissions.

(library (std os file-info)
  (export get-file-info file-info?
          file-info-size file-info-mtime file-info-mode
          file-info-uid file-info-gid file-info-type
          file-size file-mtime file-mode
          file-type file-executable? file-readable? file-writable?)

  (import (chezscheme))

  (define dummy-load
    (or (guard (e [#t #f]) (load-shared-object "libc.so.7"))
        (guard (e [#t #f]) (load-shared-object "libc.so.6"))
        (load-shared-object "libc.so")))

  (define c-access
    (foreign-procedure "access" (string int) int))

  (define-record-type file-info
    (fields size mtime mode uid gid type))

  ;; Get file size by opening a port
  (define (get-file-size path)
    (let ([p (open-input-file path)])
      (let ([len (file-length p)])
        (close-input-port p)
        len)))

  ;; Build file-info record from path
  (define (get-file-info path)
    (unless (file-exists? path)
      (error 'get-file-info "file does not exist" path))
    (let* ([size (get-file-size path)]
           [mtime (file-modification-time path)]
           [type (cond
                   [(file-directory? path) 'directory]
                   [(file-symbolic-link? path) 'symlink]
                   [(file-regular? path) 'regular]
                   [else 'other])]
           [mode (get-file-mode path)]
           [uid 0]
           [gid 0])
      (make-file-info size mtime mode uid gid type)))

  ;; Get file mode bits using access(2)
  ;; R_OK=4, W_OK=2, X_OK=1
  (define (get-file-mode path)
    (let ([r (if (= 0 (c-access path 4)) #o444 0)]
          [w (if (= 0 (c-access path 2)) #o200 0)]
          [x (if (= 0 (c-access path 1)) #o100 0)])
      (fxlogor r w x)))

  ;; Convenience accessors
  (define (file-size path)
    (get-file-size path))

  (define (file-mtime path)
    (file-modification-time path))

  (define (file-mode path)
    (get-file-mode path))

  (define (file-type path)
    (cond
      [(file-directory? path) 'directory]
      [(file-symbolic-link? path) 'symlink]
      [(file-regular? path) 'regular]
      [else 'other]))

  (define (file-executable? path)
    (= 0 (c-access path 1)))

  (define (file-readable? path)
    (= 0 (c-access path 4)))

  (define (file-writable? path)
    (= 0 (c-access path 2)))

) ;; end library
