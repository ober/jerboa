#!chezscheme
;;; (jerboa wasm gc) -- Heap allocator and arena GC for WASM linear memory
;;;
;;; Provides WASM source forms (for compile-program) that implement:
;;;   - Bump allocator with 4-byte alignment
;;;   - Arena reset (instant "GC" — reset bump pointer to arena base)
;;;   - Memory growth via memory.grow when heap is exhausted
;;;   - Root stack for preserving values across arena boundaries
;;;
;;; Arena model:
;;;   DNS query processing allocates heap objects per-query, then calls
;;;   arena-reset to reclaim all memory at once. No tracing GC needed.
;;;   For long-lived data (zone config), allocate before setting the
;;;   arena base, so arena-reset doesn't reclaim it.
;;;
;;; Memory layout (from values.sls):
;;;   0-255:     Reserved null-trap zone
;;;   256-1023:  Root stack
;;;   1024-4095: Static data
;;;   4096-8191: I/O buffers
;;;   8192+:     Heap (bump-allocated)

(library (jerboa wasm gc)
  (export
    gc-allocator-forms    ;; core alloc + arena-reset
    gc-root-stack-forms   ;; root push/pop for cross-arena values
    gc-memory-grow-forms  ;; memory.grow integration
    gc-all-forms          ;; all gc forms combined
    )

  (import (chezscheme)
          (jerboa wasm values))

  ;; ================================================================
  ;; Core allocator: bump allocation with arena reset
  ;; ================================================================

  (define gc-allocator-forms
    '(
      ;; Allocate `size` bytes from the heap. Returns pointer.
      ;; Size must be a multiple of 4 (caller ensures alignment).
      ;; Calls grow-memory if heap is exhausted.
      (define (alloc size)
        (let ([ptr (global.get 0)])       ;; heap-ptr
          (let ([new-ptr (+ ptr size)])
            (when (> new-ptr (global.get 1))  ;; heap-end
              (grow-memory size))
            (global.set 0 (+ (global.get 0) size))
            ptr)))

      ;; Reset the arena: reclaim all heap memory allocated since arena-base.
      ;; Call this between DNS queries to instantly free per-query allocations.
      (define (arena-reset)
        (global.set 0 (global.get 3)))   ;; heap-ptr = arena-base

      ;; Set the current heap pointer as the new arena base.
      ;; Objects allocated before this call survive arena-reset.
      (define (arena-mark)
        (global.set 3 (global.get 0)))   ;; arena-base = heap-ptr

      ;; Return the number of bytes currently allocated in the arena.
      (define (arena-used)
        (- (global.get 0) (global.get 3)))

      ;; Return the number of bytes available before growth is needed.
      (define (heap-available)
        (- (global.get 1) (global.get 0)))
      ))

  ;; ================================================================
  ;; Memory growth
  ;; ================================================================

  (define gc-memory-grow-forms
    '(
      ;; Grow linear memory to accommodate at least `needed` more bytes.
      ;; Grows by at least 1 page (64KB) or enough pages for `needed`.
      (define (grow-memory needed)
        (let ([pages-needed (+ (shr-u needed 16) 1)])  ;; ceil(needed/65536)
          (let ([result (memory.grow pages-needed)])
            (when (= result -1)
              ;; memory.grow failed — out of memory, trap
              (unreachable))
            ;; Update heap-end to reflect new size
            (global.set 1 (* (memory.size) 65536)))))
      ))

  ;; ================================================================
  ;; Root stack: preserve values that must survive arena reset
  ;; ================================================================

  (define gc-root-stack-forms
    '(
      ;; Push a value onto the root stack.
      ;; Used to protect values that must survive arena-reset.
      (define (root-push val)
        (let ([sp (global.get 2)])        ;; root-sp
          (i32.store sp val)
          (global.set 2 (+ sp 4))))

      ;; Pop and return the top value from the root stack.
      (define (root-pop)
        (let ([sp (- (global.get 2) 4)])
          (global.set 2 sp)
          (i32.load sp)))

      ;; Peek at the top of the root stack without popping.
      (define (root-peek)
        (i32.load (- (global.get 2) 4)))

      ;; Return current root stack depth (number of entries).
      (define (root-depth)
        (shr-u (- (global.get 2) 256) 2))  ;; (sp - ROOT_BASE) / 4
      ))

  ;; ================================================================
  ;; Combined: all GC forms
  ;; ================================================================

  (define gc-all-forms
    (append gc-allocator-forms
            gc-memory-grow-forms
            gc-root-stack-forms))

) ;; end library
