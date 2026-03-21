#!chezscheme
;;; (std effect io) — Testable I/O via effect handlers
;;;
;;; All I/O as swappable handlers — use real FS in production,
;;; in-memory FS in tests. No mocking frameworks needed.
;;;
;;; API:
;;;   (with-real-fs thunk)           — run with real filesystem I/O
;;;   (with-test-fs files thunk)     — run with in-memory filesystem
;;;   (io-read-file path)            — read file contents
;;;   (io-write-file path content)   — write file contents
;;;   (io-file-exists? path)         — check file existence
;;;   (io-delete-file path)          — delete a file
;;;   (io-read-line)                 — read line from console
;;;   (io-display val)               — display to console
;;;   (with-test-console inputs thunk) — mock console I/O

(library (std effect io)
  (export with-real-fs with-test-fs
          io-read-file io-write-file io-file-exists? io-delete-file
          io-read-line io-display
          with-test-console get-test-output)

  (import (chezscheme))

  ;; ========== File I/O handler ==========

  (define-record-type fs-handler
    (fields read-file write-file file-exists? delete-file))

  (define *fs-handler* (make-thread-parameter #f))

  ;; Real filesystem handler
  (define real-fs
    (make-fs-handler
      (lambda (path)
        (call-with-input-file path get-string-all))
      (lambda (path content)
        (call-with-output-file path
          (lambda (p) (display content p))
          'replace))
      (lambda (path) (file-exists? path))
      (lambda (path) (delete-file path))))

  ;; In-memory filesystem handler
  (define (make-test-fs initial-files)
    (let ([fs (make-hashtable string-hash string=?)])
      (for-each
        (lambda (pair)
          (hashtable-set! fs (car pair) (cdr pair)))
        initial-files)
      (make-fs-handler
        (lambda (path)
          (let ([v (hashtable-ref fs path #f)])
            (or v (error 'io-read-file "file not found" path))))
        (lambda (path content)
          (hashtable-set! fs path content))
        (lambda (path)
          (hashtable-contains? fs path))
        (lambda (path)
          (hashtable-delete! fs path)))))

  (define (with-real-fs thunk)
    (parameterize ([*fs-handler* real-fs])
      (thunk)))

  (define (with-test-fs initial-files thunk)
    (parameterize ([*fs-handler* (make-test-fs initial-files)])
      (thunk)))

  (define (ensure-fs who)
    (or (*fs-handler*)
        (error who "no I/O handler installed — use with-real-fs or with-test-fs")))

  (define (io-read-file path)
    ((fs-handler-read-file (ensure-fs 'io-read-file)) path))

  (define (io-write-file path content)
    ((fs-handler-write-file (ensure-fs 'io-write-file)) path content))

  (define (io-file-exists? path)
    ((fs-handler-file-exists? (ensure-fs 'io-file-exists?)) path))

  (define (io-delete-file path)
    ((fs-handler-delete-file (ensure-fs 'io-delete-file)) path))

  ;; ========== Console I/O handler ==========

  (define-record-type console-handler
    (fields read-line display-proc))

  (define *console-handler* (make-thread-parameter #f))
  (define *test-output* (make-thread-parameter '()))

  (define real-console
    (make-console-handler
      (lambda () (get-line (current-input-port)))
      (lambda (val) (display val) (newline))))

  (define (make-test-console inputs)
    (let ([remaining inputs])
      (make-console-handler
        (lambda ()
          (if (null? remaining)
            (eof-object)
            (let ([line (car remaining)])
              (set! remaining (cdr remaining))
              line)))
        (lambda (val)
          (*test-output* (cons (format "~a" val) (*test-output*)))))))

  (define (with-test-console inputs thunk)
    (parameterize ([*console-handler* (make-test-console inputs)]
                   [*test-output* '()])
      (thunk)))

  (define (get-test-output)
    (reverse (*test-output*)))

  (define (io-read-line)
    (let ([h (or (*console-handler*) real-console)])
      ((console-handler-read-line h))))

  (define (io-display val)
    (let ([h (or (*console-handler*) real-console)])
      ((console-handler-display-proc h) val)))

) ;; end library
