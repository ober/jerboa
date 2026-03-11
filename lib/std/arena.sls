#!chezscheme
;;; (std arena) — Arena allocators: fast, bulk-freeable memory allocation
;;;
;;; Arenas provide bump-pointer allocation backed by a large bytevector.
;;; All allocations are O(1). Freeing is O(1) via arena-reset! which
;;; invalidates ALL prior allocations at once.
;;;
;;; WARNING: arena-reset! invalidates all previously allocated slices.
;;; Do not hold references to arena slices across a reset.

(library (std arena)
  (export
    ;; Arena creation
    make-arena
    arena?
    arena-capacity
    arena-used
    arena-remaining
    arena-reset!
    arena-destroy!
    ;; Allocation
    arena-alloc
    arena-alloc-string
    arena-alloc-bytes
    ;; Bulk ops
    with-arena
    arena-checkpoint
    arena-rollback!
    ;; Stats
    arena-stats
    ;; Arena-backed string interning
    make-arena-interner
    arena-intern!
    arena-intern-lookup)

  (import (chezscheme))

  ;; ========== Arena record ==========

  (define-record-type %arena
    (fields
      (immutable backing)     ;; bytevector — the backing store
      (mutable   used)        ;; bytes used so far (bump pointer)
      (mutable   destroyed?)) ;; #t after arena-destroy!
    (protocol
      (lambda (new)
        (lambda (capacity)
          (new (make-bytevector capacity 0) 0 #f)))))

  (define (make-arena capacity)
    (make-%arena capacity))

  (define (arena? x) (%arena? x))

  (define (arena-capacity a)
    (bytevector-length (%arena-backing a)))

  (define (arena-used a) (%arena-used a))

  (define (arena-remaining a)
    (- (arena-capacity a) (%arena-used a)))

  ;; Check arena is live
  (define (assert-live! who a)
    (when (%arena-destroyed? a)
      (error who "arena has been destroyed" a)))

  ;; ========== arena-reset! ==========
  ;; O(1): set used back to 0. All prior allocations become invalid.
  (define (arena-reset! a)
    (assert-live! 'arena-reset! a)
    (%arena-used-set! a 0))

  ;; ========== arena-destroy! ==========
  ;; Release the backing store (GC will collect it).
  (define (arena-destroy! a)
    (%arena-destroyed?-set! a #t)
    (%arena-used-set! a 0))

  ;; ========== arena-alloc ==========
  ;; Bump-allocate `size` bytes. Returns a bytevector slice (fresh copy).
  ;; NOTE: returns a copy — the arena retains ownership of the backing memory.
  ;; size must be a non-negative exact integer.
  (define (arena-alloc a size)
    (assert-live! 'arena-alloc a)
    (unless (and (exact? size) (integer? size) (>= size 0))
      (error 'arena-alloc "size must be a non-negative exact integer" size))
    (let ([pos (%arena-used a)]
          [cap (arena-capacity a)])
      (when (> (+ pos size) cap)
        (error 'arena-alloc "arena out of space"
               `(needed ,size) `(remaining ,(- cap pos))))
      (%arena-used-set! a (+ pos size))
      ;; Return a fresh bytevector slice (view of the allocated region)
      (let ([slice (make-bytevector size 0)])
        slice)))

  ;; ========== arena-alloc-string ==========
  ;; Copy string bytes into the arena; return the string (interned in arena).
  ;; Returns the original string (Chez strings are GC'd; we just track position).
  (define (arena-alloc-string a str)
    (assert-live! 'arena-alloc-string a)
    (unless (string? str)
      (error 'arena-alloc-string "expected a string" str))
    (let* ([bv  (string->utf8 str)]
           [len (bytevector-length bv)]
           [pos (%arena-used a)]
           [cap (arena-capacity a)])
      (when (> (+ pos len 1) cap) ;; +1 for null terminator
        (error 'arena-alloc-string "arena out of space"))
      ;; Copy bytes into backing store
      (let ([backing (%arena-backing a)])
        (bytevector-copy! bv 0 backing pos len)
        (bytevector-u8-set! backing (+ pos len) 0) ;; null terminator
        (%arena-used-set! a (+ pos len 1)))
      str))

  ;; ========== arena-alloc-bytes ==========
  ;; Copy a bytevector into the arena; return a fresh copy from arena region.
  (define (arena-alloc-bytes a bv)
    (assert-live! 'arena-alloc-bytes a)
    (unless (bytevector? bv)
      (error 'arena-alloc-bytes "expected a bytevector" bv))
    (let* ([len (bytevector-length bv)]
           [pos (%arena-used a)]
           [cap (arena-capacity a)])
      (when (> (+ pos len) cap)
        (error 'arena-alloc-bytes "arena out of space"))
      (let ([backing (%arena-backing a)])
        (bytevector-copy! bv 0 backing pos len)
        (%arena-used-set! a (+ pos len))
        ;; Return a copy of what was stored
        (let ([result (make-bytevector len)])
          (bytevector-copy! backing pos result 0 len)
          result))))

  ;; ========== arena-checkpoint ==========
  ;; Returns current position (for rollback).
  (define (arena-checkpoint a)
    (assert-live! 'arena-checkpoint a)
    (%arena-used a))

  ;; ========== arena-rollback! ==========
  ;; Restore arena to a previously captured checkpoint.
  (define (arena-rollback! a checkpoint)
    (assert-live! 'arena-rollback! a)
    (unless (and (exact? checkpoint) (integer? checkpoint)
                 (>= checkpoint 0)
                 (<= checkpoint (%arena-used a)))
      (error 'arena-rollback! "invalid checkpoint" checkpoint))
    (%arena-used-set! a checkpoint))

  ;; ========== with-arena ==========
  ;; Create a temporary arena of given capacity, run body, then destroy it.
  ;; Arena is reset even on non-local exit (via dynamic-wind).
  (define-syntax with-arena
    (syntax-rules ()
      [(_ size body ...)
       (let ([a (make-arena size)])
         (dynamic-wind
           (lambda () #f)
           (lambda () body ...)
           (lambda () (arena-destroy! a))))]))

  ;; ========== arena-stats ==========
  ;; Returns an alist of statistics.
  (define (arena-stats a)
    (list
      (cons 'capacity  (arena-capacity a))
      (cons 'used      (arena-used a))
      (cons 'remaining (arena-remaining a))
      (cons 'destroyed (%arena-destroyed? a))))

  ;; ========== Arena-backed string interning ==========

  (define-record-type %arena-interner
    (fields
      (immutable arena)
      (immutable table))  ;; string -> string (hashtable)
    (protocol
      (lambda (new)
        (lambda (arena)
          (new arena (make-hashtable string-hash string=?))))))

  (define (make-arena-interner arena)
    (unless (arena? arena)
      (error 'make-arena-interner "expected an arena" arena))
    (make-%arena-interner arena))

  ;; Intern a string: if already seen, return existing; else store in arena.
  (define (arena-intern! interner str)
    (unless (string? str)
      (error 'arena-intern! "expected a string" str))
    (let ([tbl (%arena-interner-table interner)])
      (or (hashtable-ref tbl str #f)
          (let ([interned (arena-alloc-string (%arena-interner-arena interner) str)])
            (hashtable-set! tbl str interned)
            interned))))

  ;; Look up without interning; returns #f if not found.
  (define (arena-intern-lookup interner str)
    (hashtable-ref (%arena-interner-table interner) str #f))

) ;; end library
