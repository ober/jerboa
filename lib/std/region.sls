#!chezscheme
;;; (std region) — Region-based memory with automatic cleanup
;;;
;;; Allocate memory in a region; all memory freed when region exits.
;;; No GC pressure for FFI-heavy code. Guardian as safety net.
;;;
;;; API:
;;;   (with-region body ...)           — execute body with a fresh region
;;;   (region-alloc region size)       — allocate bytes in region
;;;   (region-ref region ptr offset)   — read byte at offset
;;;   (region-set! region ptr offset val) — write byte at offset
;;;   (region-alloc-string region str) — allocate a C string in region
;;;   (region-alive? region)           — check if region is still valid
;;;   (make-region)                    — create a region manually
;;;   (region-free! region)            — free all allocations in region

(library (std region)
  (export with-region region-alloc region-ref region-set!
          region-alloc-string region-alive? make-region region-free!
          region-alloc-bytevector)

  (import (chezscheme))

  ;; ========== Region record ==========

  (define-record-type region
    (fields
      (mutable allocations)    ;; list of foreign pointers
      (mutable alive?))
    (protocol
      (lambda (new)
        (lambda () (new '() #t)))))

  ;; ========== Allocation ==========

  (define (region-alloc region size)
    (unless (region-alive? region)
      (error 'region-alloc "region has been freed"))
    (let ([ptr (foreign-alloc size)])
      (region-allocations-set! region
        (cons ptr (region-allocations region)))
      ptr))

  (define (region-ref _region ptr offset)
    (foreign-ref 'unsigned-8 ptr offset))

  (define (region-set! _region ptr offset val)
    (foreign-set! 'unsigned-8 ptr offset val))

  (define (region-alloc-string region str)
    (let* ([len (string-length str)]
           [ptr (region-alloc region (+ len 1))])
      (do ([i 0 (+ i 1)])
          ((= i len))
        (foreign-set! 'unsigned-8 ptr i
          (char->integer (string-ref str i))))
      (foreign-set! 'unsigned-8 ptr len 0)
      ptr))

  (define (region-alloc-bytevector region bv)
    (let* ([len (bytevector-length bv)]
           [ptr (region-alloc region len)])
      (do ([i 0 (+ i 1)])
          ((= i len))
        (foreign-set! 'unsigned-8 ptr i
          (bytevector-u8-ref bv i)))
      ptr))

  ;; ========== Cleanup ==========

  (define (region-free! region)
    (when (region-alive? region)
      (for-each
        (lambda (ptr)
          (guard (exn [#t (void)])
            (foreign-free ptr)))
        (region-allocations region))
      (region-allocations-set! region '())
      (region-alive?-set! region #f)))

  ;; ========== with-region ==========

  (define-syntax with-region
    (syntax-rules ()
      [(_ body ...)
       (let ([r (make-region)])
         (dynamic-wind
           void
           (lambda () body ...)
           (lambda () (region-free! r))))]))

) ;; end library
