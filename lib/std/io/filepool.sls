#!chezscheme
;;; (std io filepool) — Fiber-aware file I/O via thread pool
;;;
;;; Regular files on Linux always return "ready" from epoll, making
;;; epoll useless for file I/O. This module offloads blocking file
;;; operations to a thread pool so fibers don't block worker threads.
;;;
;;; API:
;;;   (make-file-pool)              — create pool (default 4 threads)
;;;   (make-file-pool n)            — create with n threads
;;;   (file-pool-start! pool)       — start the worker threads
;;;   (file-pool-stop! pool)        — drain and stop workers
;;;   (fiber-read-file path pool)   — read entire file as string
;;;   (fiber-read-file-bytes path pool)  — read entire file as bytevector
;;;   (fiber-write-file path data pool)  — write string to file
;;;   (fiber-write-file-bytes path data pool) — write bytevector to file
;;;   (fiber-append-file path data pool)      — append string to file
;;;   (fiber-file-exists? path pool)          — check if file exists
;;;   (with-file-pool body ...)               — scoped pool lifecycle

(library (std io filepool)
  (export
    make-file-pool
    file-pool?
    file-pool-start!
    file-pool-stop!
    fiber-read-file
    fiber-read-file-bytes
    fiber-write-file
    fiber-write-file-bytes
    fiber-append-file
    fiber-file-exists?
    with-file-pool)

  (import (chezscheme)
          (std fiber)
          (std net workpool))

  ;; ========== File pool ==========

  (define-record-type file-pool
    (fields (immutable pool))
    (protocol
      (lambda (new)
        (case-lambda
          [() (new (make-work-pool 4))]
          [(n) (new (make-work-pool n))]))))

  (define (file-pool-start! fp)
    (work-pool-start! (file-pool-pool fp)))

  (define (file-pool-stop! fp)
    (work-pool-stop! (file-pool-pool fp)))

  ;; ========== Fiber-aware file operations ==========

  ;; Read entire file as string, parking the fiber.
  (define (fiber-read-file path pool)
    (work-pool-submit! (file-pool-pool pool)
      (lambda ()
        (let ([p (open-file-input-port path
                   (file-options) (buffer-mode block)
                   (make-transcoder (utf-8-codec)))])
          (let ([content (get-string-all p)])
            (close-input-port p)
            (if (eof-object? content) "" content))))))

  ;; Read entire file as bytevector, parking the fiber.
  (define (fiber-read-file-bytes path pool)
    (work-pool-submit! (file-pool-pool pool)
      (lambda ()
        (let ([p (open-file-input-port path)])
          (let ([content (get-bytevector-all p)])
            (close-input-port p)
            (if (eof-object? content) (make-bytevector 0) content))))))

  ;; Write string to file (overwrite), parking the fiber.
  (define (fiber-write-file path data pool)
    (work-pool-submit! (file-pool-pool pool)
      (lambda ()
        (let ([p (open-file-output-port path
                   (file-options no-fail)
                   (buffer-mode block)
                   (make-transcoder (utf-8-codec)))])
          (put-string p data)
          (close-output-port p)
          (void)))))

  ;; Write bytevector to file (overwrite), parking the fiber.
  (define (fiber-write-file-bytes path data pool)
    (work-pool-submit! (file-pool-pool pool)
      (lambda ()
        (let ([p (open-file-output-port path
                   (file-options no-fail)
                   (buffer-mode block))])
          (put-bytevector p data)
          (close-output-port p)
          (void)))))

  ;; Append string to file, parking the fiber.
  (define (fiber-append-file path data pool)
    (work-pool-submit! (file-pool-pool pool)
      (lambda ()
        (let ([p (open-file-output-port path
                   (file-options no-fail no-truncate)
                   (buffer-mode block)
                   (make-transcoder (utf-8-codec)))])
          (set-port-position! p (port-length p))
          (put-string p data)
          (close-output-port p)
          (void)))))

  ;; Check if file exists, parking the fiber.
  (define (fiber-file-exists? path pool)
    (work-pool-submit! (file-pool-pool pool)
      (lambda () (file-exists? path))))

  ;; Convenience macro
  (define-syntax with-file-pool
    (syntax-rules ()
      [(_ var body ...)
       (let ([var (make-file-pool)])
         (file-pool-start! var)
         (guard (exn [#t (file-pool-stop! var) (raise exn)])
           (let ([result (begin body ...)])
             (file-pool-stop! var)
             result)))]))

) ;; end library
