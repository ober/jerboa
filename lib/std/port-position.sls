#!chezscheme
;;; (std port-position) — Port position tracking
;;;
;;; Re-exports Chez's port position API for seekable I/O.

(library (std port-position)
  (export port-position set-port-position!
          port-has-port-position? port-has-set-port-position!?
          file-port-length)

  (import (chezscheme))

  ;; file-port-length: get file size by seeking to end
  ;; Uses port-file-descriptor + fstat via foreign procedure
  (define c-fstat-size
    (let ()
      ;; Use stat struct; on Linux x86-64, st_size is at offset 48
      ;; Instead, use a simpler approach: read file-length from path
      ;; For ports opened with open-file-*-port, we can use Chez's file-length
      ;; if we have the path. As fallback, save pos, read to end, restore.
      #f))

  (define (file-port-length port)
    (unless (and (port-has-port-position? port)
                 (port-has-set-port-position!? port))
      (error 'file-port-length "port does not support positioning" port))
    (let ([saved (port-position port)])
      ;; Read to end to find length
      (let loop ()
        (let ([b (get-u8 port)])
          (if (eof-object? b)
              (let ([len (port-position port)])
                (set-port-position! port saved)
                len)
              (loop))))))

  ;; Note: port-position, set-port-position!,
  ;; port-has-port-position?, port-has-set-port-position!?
  ;; are all Chez built-ins re-exported.

) ;; end library
