#!chezscheme
;;; (std crypto secure-mem) — Secure memory region outside GC
;;;
;;; mlock'd, guard-page protected, DONTDUMP, explicit_bzero on free.
;;; Secrets stored here are never swapped to disk, never visible in core dumps,
;;; and never copied by the GC.

(library (std crypto secure-mem)
  (export
    secure-alloc secure-free secure-wipe
    secure-random-fill
    with-secure-region
    secure-region? secure-region-pointer secure-region-size)

  (import (chezscheme))

  (define _native-loaded
    (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
        (error 'std/crypto/secure-mem "libjerboa_native.so not found")))

  (define-record-type secure-region
    (fields pointer size)
    (nongenerative secure-region-type)
    (sealed #t)
    (opaque #t))

  ;; Use uptr (unsigned pointer-sized integer) for void* returns
  (define c-jerboa-secure-alloc
    (foreign-procedure "jerboa_secure_alloc" (size_t) uptr))

  (define c-jerboa-secure-free
    (foreign-procedure "jerboa_secure_free" (uptr size_t) int))

  (define c-jerboa-secure-wipe
    (foreign-procedure "jerboa_secure_wipe" (uptr size_t) int))

  (define c-jerboa-secure-random-fill
    (foreign-procedure "jerboa_secure_random_fill" (uptr size_t) int))

  (define (secure-alloc size)
    (let ([ptr (c-jerboa-secure-alloc size)])
      (when (= ptr 0)
        (error 'secure-alloc "mmap failed" size))
      (make-secure-region ptr size)))

  (define (secure-free region)
    (c-jerboa-secure-free (secure-region-pointer region)
                          (secure-region-size region))
    (void))

  (define (secure-wipe region)
    (c-jerboa-secure-wipe (secure-region-pointer region)
                          (secure-region-size region))
    (void))

  (define (secure-random-fill region)
    (let ([rc (c-jerboa-secure-random-fill (secure-region-pointer region)
                                            (secure-region-size region))])
      (when (< rc 0)
        (error 'secure-random-fill "CSPRNG failed"))
      (void)))

  (define-syntax with-secure-region
    (syntax-rules ()
      [(_ ([name size] ...) body ...)
       (let ([name (secure-alloc size)] ...)
         (dynamic-wind
           void
           (lambda () body ...)
           (lambda ()
             (secure-free name) ...)))]))

  ) ;; end library
