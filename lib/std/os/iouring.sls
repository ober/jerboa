#!chezscheme
;;; (std os iouring) — Linux io_uring via liburing
;;;
;;; Provides zero-copy async I/O using io_uring (Linux 5.1+).
;;; Requires: liburing.so.2
;;;
;;; API:
;;;   (iouring-available?)            — #t if liburing.so is present
;;;   (make-iouring [depth])          — initialize ring
;;;   (iouring-close! ring)           — shut down ring
;;;   (iouring-read! ring fd buf n)   — async read, returns promise<bytes-read>
;;;   (iouring-write! ring fd buf n)  — async write, returns promise<bytes-written>
;;;   (iouring-accept! ring fd)       — async accept, returns promise<client-fd>
;;;   (iouring-submit! ring)          — submit pending SQEs
;;;   (iouring-wait! ring)            — wait for 1 completion
;;;   (run-iouring-loop ring)         — completion loop in background thread

(library (std os iouring)
  (export
    iouring-available?
    make-iouring
    iouring?
    iouring-ring-addr
    iouring-pending
    iouring-close!
    iouring-nop!
    iouring-read!
    iouring-write!
    iouring-accept!
    iouring-submit!
    iouring-wait!
    run-iouring-loop)

  (import (chezscheme) (std async))

  ;; ========== Constants ==========

  ;; io_uring struct size (liburing 2.x is 216 bytes; we use 256 for safety)
  (define *ring-struct-size* 256)

  ;; ========== liburing availability ==========

  ;; liburing-ffi.so.2 exposes all inline functions as real symbols
  (define *liburing-available*
    (guard (exn [#t #f])
      (load-shared-object "liburing-ffi.so.2")
      #t))

  (define (iouring-available?) *liburing-available*)

  ;; ========== FFI stubs (replaced when library is present) ==========

  (define (not-available . args)
    (error 'iouring "liburing not available; install liburing2"))

  (define io-uring-queue-init  not-available)
  (define io-uring-queue-exit  not-available)
  (define io-uring-get-sqe     not-available)
  (define io-uring-submit      not-available)
  (define io-uring-wait-cqe    not-available)
  (define io-uring-cqe-seen    not-available)
  (define io-uring-sqe-set-data64 not-available)
  (define io-uring-cqe-get-data64 not-available)
  (define io-uring-prep-read   not-available)
  (define io-uring-prep-write  not-available)
  (define io-uring-prep-accept not-available)

  ;; ========== iouring record ==========

  (define-record-type (iouring %make-iouring iouring?)
    (fields
      (immutable ring-addr)   ;; uptr: address of foreign-alloc'd io_uring struct
      (immutable depth)       ;; queue depth
      (mutable pending)       ;; eq-hashtable: op-id -> async-promise
      (immutable mutex))      ;; protects pending table
    (sealed #t))

  ;; ========== Operation ID counter ==========

  (define *next-op-id* 0)
  (define *op-id-mutex* (make-mutex))

  (define (next-op-id!)
    (with-mutex *op-id-mutex*
      (let ([id *next-op-id*])
        (set! *next-op-id* (+ id 1))
        id)))

  ;; ========== make-iouring ==========

  (define make-iouring
    (case-lambda
      [()      (make-iouring-impl 256)]
      [(depth) (make-iouring-impl depth)]))

  (define (make-iouring-impl depth)
    (unless *liburing-available*
      (error 'make-iouring "liburing not available; install liburing2"))
    (let ([ring-addr (foreign-alloc *ring-struct-size*)])
      (do ([i 0 (+ i 1)])
          ((= i *ring-struct-size*))
        (foreign-set! 'unsigned-8 ring-addr i 0))
      (let ([ret (io-uring-queue-init depth ring-addr 0)])
        (when (< ret 0)
          (foreign-free ring-addr)
          (error 'make-iouring "io_uring_queue_init failed, errno" (- ret)))
        (%make-iouring ring-addr depth (make-eq-hashtable) (make-mutex)))))

  ;; ========== iouring-close! ==========

  (define (iouring-close! ring)
    (io-uring-queue-exit (iouring-ring-addr ring))
    (foreign-free (iouring-ring-addr ring)))

  ;; ========== Internal: submit one op, return promise ==========

  (define (iouring-op! ring prep-thunk)
    (let ([sqe-addr (io-uring-get-sqe (iouring-ring-addr ring))])
      (when (zero? sqe-addr)
        (error 'iouring-op! "submission queue full"))
      (let ([op-id (next-op-id!)]
            [p (make-async-promise)])
        (prep-thunk sqe-addr)
        (io-uring-sqe-set-data64 sqe-addr op-id)
        (with-mutex (iouring-mutex ring)
          (hashtable-set! (iouring-pending ring) op-id p))
        p)))

  ;; ========== iouring-nop! ==========
  ;; Submit a no-op for testing ring functionality.

  (define (iouring-nop! ring)
    (iouring-op! ring
      (lambda (sqe)
        ((foreign-procedure "io_uring_prep_nop" (uptr) void) sqe))))

  ;; ========== iouring-read! ==========
  ;; buf must be a uptr (foreign-alloc'd buffer); returns promise<bytes-read>.

  (define (iouring-read! ring fd buf-addr n)
    (iouring-op! ring
      (lambda (sqe)
        (io-uring-prep-read sqe fd buf-addr n 0))))

  ;; ========== iouring-write! ==========

  (define (iouring-write! ring fd buf-addr n)
    (iouring-op! ring
      (lambda (sqe)
        (io-uring-prep-write sqe fd buf-addr n 0))))

  ;; ========== iouring-accept! ==========

  (define (iouring-accept! ring fd)
    (iouring-op! ring
      (lambda (sqe)
        (io-uring-prep-accept sqe fd 0 0 0))))

  ;; ========== iouring-submit! ==========

  (define (iouring-submit! ring)
    (let ([ret (io-uring-submit (iouring-ring-addr ring))])
      (when (< ret 0)
        (error 'iouring-submit! "io_uring_submit failed" ret))
      ret))

  ;; ========== iouring-wait! ==========
  ;; Wait for one completion, resolve its promise.

  (define (iouring-wait! ring)
    (let ([cqe-ptr-addr (foreign-alloc 8)])
      (foreign-set! 'unsigned-64 cqe-ptr-addr 0 0)
      (let ([ret (io-uring-wait-cqe (iouring-ring-addr ring) cqe-ptr-addr)])
        (let ([cqe-addr (foreign-ref 'uptr cqe-ptr-addr 0)])
          (foreign-free cqe-ptr-addr)
          (when (< ret 0)
            (error 'iouring-wait! "io_uring_wait_cqe failed" ret))
          ;; io_uring_cqe: user_data(u64 @0), res(s32 @8), flags(u32 @12)
          (let ([op-id (io-uring-cqe-get-data64 cqe-addr)]
                [res   (foreign-ref 'integer-32 cqe-addr 8)])
            (io-uring-cqe-seen (iouring-ring-addr ring) cqe-addr)
            (let ([p (with-mutex (iouring-mutex ring)
                       (let ([entry (hashtable-ref (iouring-pending ring) op-id #f)])
                         (when entry
                           (hashtable-delete! (iouring-pending ring) op-id))
                         entry))])
              (when p
                (async-promise-resolve! p res))))))))

  ;; ========== run-iouring-loop ==========

  (define (run-iouring-loop ring)
    (fork-thread
      (lambda ()
        (let loop ()
          (guard (exn [#t (void)])
            (iouring-submit! ring)
            (iouring-wait! ring))
          (loop)))))

  ;; ========== Initialize FFI when library is available ==========

  (when *liburing-available*
    (set! io-uring-queue-init
      (foreign-procedure "io_uring_queue_init"
        (unsigned-32 uptr unsigned-32) int))
    (set! io-uring-queue-exit
      (foreign-procedure "io_uring_queue_exit"
        (uptr) void))
    (set! io-uring-get-sqe
      (foreign-procedure "io_uring_get_sqe"
        (uptr) uptr))
    (set! io-uring-submit
      (foreign-procedure "io_uring_submit"
        (uptr) int))
    (set! io-uring-wait-cqe
      (foreign-procedure "io_uring_wait_cqe"
        (uptr uptr) int))
    (set! io-uring-cqe-seen
      (foreign-procedure "io_uring_cqe_seen"
        (uptr uptr) void))
    (set! io-uring-sqe-set-data64
      (foreign-procedure "io_uring_sqe_set_data64"
        (uptr unsigned-64) void))
    (set! io-uring-cqe-get-data64
      (foreign-procedure "io_uring_cqe_get_data64"
        (uptr) unsigned-64))
    (set! io-uring-prep-read
      (foreign-procedure "io_uring_prep_read"
        (uptr int uptr unsigned-32 unsigned-64) void))
    (set! io-uring-prep-write
      (foreign-procedure "io_uring_prep_write"
        (uptr int uptr unsigned-32 unsigned-64) void))
    (set! io-uring-prep-accept
      (foreign-procedure "io_uring_prep_accept"
        (uptr int uptr uptr int) void)))

  ) ;; end library
