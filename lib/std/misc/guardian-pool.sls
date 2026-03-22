#!chezscheme
;;; (std misc guardian-pool) — Guardian-based FFI resource cleanup
;;;
;;; Standardized guardian-based resource cleanup for FFI handles.
;;; Resources registered with a guardian pool are automatically cleaned up
;;; when the GC reclaims them, or can be manually drained on shutdown.
;;;
;;; Usage:
;;;   (define pool (make-guardian-pool free-handle!))
;;;   (guardian-pool-register pool handle)
;;;   ;; ... later, after GC has reclaimed some handles:
;;;   (guardian-pool-collect! pool)
;;;   ;; On shutdown:
;;;   (guardian-pool-drain! pool)
;;;
;;; Pointerlike usage:
;;;   (define pool (make-guardian-pool free-handle!))
;;;   (define h (make-pointerlike pool 42))
;;;   (pointerlike-value h) => 42
;;;   (pointerlike-free! h) ;; manual free
;;;
;;; Scoped usage:
;;;   (with-guarded-resource (h (allocate-handle) pool)
;;;     (use h))  ;; cleanup runs on scope exit

(library (std misc guardian-pool)
  (export make-guardian-pool
          guardian-pool?
          guardian-pool-register
          guardian-pool-collect!
          guardian-pool-drain!
          with-guarded-resource
          make-pointerlike
          pointerlike?
          pointerlike-value
          pointerlike-free!)
  (import (chezscheme))

  ;; Guardian pool: wraps a Chez guardian with a cleanup procedure
  ;; and a set tracking all live (registered, not yet cleaned) resources.
  (define-record-type gpool
    (fields
      (immutable guardian)       ;; Chez guardian object
      (immutable cleanup-proc)   ;; procedure: resource -> void
      (mutable live-set))        ;; eq hashtable of live resources
    (protocol
      (lambda (new)
        (lambda (cleanup-proc)
          (new (make-guardian) cleanup-proc (make-eq-hashtable))))))

  (define (guardian-pool? x)
    (gpool? x))

  (define (make-guardian-pool cleanup-proc)
    (unless (procedure? cleanup-proc)
      (error 'make-guardian-pool "expected a cleanup procedure" cleanup-proc))
    (make-gpool cleanup-proc))

  ;; Register a resource with the pool.
  ;; The guardian will prevent the resource from being finalized until the
  ;; GC determines it is unreachable, at which point collect! can clean it up.
  ;; Returns the resource for convenience.
  (define (guardian-pool-register pool resource)
    (unless (gpool? pool)
      (error 'guardian-pool-register "expected a guardian pool" pool))
    (let ([guardian (gpool-guardian pool)]
          [live (gpool-live-set pool)])
      (guardian resource)
      (hashtable-set! live resource #t)
      resource))

  ;; Collect GC'd resources: drain the guardian and call cleanup on each.
  ;; Returns the number of resources cleaned up.
  (define (guardian-pool-collect! pool)
    (unless (gpool? pool)
      (error 'guardian-pool-collect! "expected a guardian pool" pool))
    (let ([guardian (gpool-guardian pool)]
          [cleanup (gpool-cleanup-proc pool)]
          [live (gpool-live-set pool)]
          [count 0])
      (let loop ()
        (let ([obj (guardian)])
          (when obj
            ;; Only clean up if still in the live set (not already manually freed)
            (when (hashtable-ref live obj #f)
              (hashtable-delete! live obj)
              (guard (e [#t (void)])  ;; swallow errors during cleanup
                (cleanup obj))
              (set! count (+ count 1)))
            (loop))))
      count))

  ;; Drain ALL live resources (for shutdown). Cleans up everything registered,
  ;; regardless of whether the GC has reclaimed it.
  ;; Returns the number of resources cleaned up.
  (define (guardian-pool-drain! pool)
    (unless (gpool? pool)
      (error 'guardian-pool-drain! "expected a guardian pool" pool))
    ;; First, collect anything the GC has already reclaimed
    (guardian-pool-collect! pool)
    ;; Then forcibly clean up everything still in the live set
    (let ([cleanup (gpool-cleanup-proc pool)]
          [live (gpool-live-set pool)]
          [count 0])
      (let-values ([(keys vals) (hashtable-entries live)])
        (vector-for-each
          (lambda (resource _val)
            (guard (e [#t (void)])
              (cleanup resource))
            (set! count (+ count 1)))
          keys vals))
      (hashtable-clear! live)
      count))

  ;; Scoped resource management: create a resource, register with pool,
  ;; ensure cleanup on scope exit (normal or exception).
  (define-syntax with-guarded-resource
    (syntax-rules ()
      [(_ (var init pool) body body* ...)
       (let ([p pool])
         (let ([var init])
           (guardian-pool-register p var)
           (dynamic-wind
             void
             (lambda () body body* ...)
             (lambda ()
               ;; Remove from live set and clean up immediately
               (let ([live (gpool-live-set p)])
                 (when (hashtable-ref live var #f)
                   (hashtable-delete! live var)
                   (guard (e [#t (void)])
                     ((gpool-cleanup-proc p) var))))))))]))

  ;; --- Pointerlike: a handle record wrapping an integer/pointer value ---

  (define-record-type ptrlike
    (fields
      (immutable pool)          ;; guardian pool this belongs to
      (mutable val)             ;; the integer/pointer value, or #f if freed
      (mutable freed?))         ;; #t after manual free
    (protocol
      (lambda (new)
        (lambda (pool value)
          (new pool value #f)))))

  (define (pointerlike? x)
    (ptrlike? x))

  (define (pointerlike-value p)
    (unless (ptrlike? p)
      (error 'pointerlike-value "expected a pointerlike" p))
    (when (ptrlike-freed? p)
      (error 'pointerlike-value "pointerlike has been freed" p))
    (ptrlike-val p))

  ;; Create a pointerlike, register with pool for auto-cleanup.
  (define (make-pointerlike pool value)
    (unless (gpool? pool)
      (error 'make-pointerlike "expected a guardian pool" pool))
    (let ([p (make-ptrlike pool value)])
      (guardian-pool-register pool p)
      p))

  ;; Manually free a pointerlike. Calls the pool's cleanup proc and
  ;; removes it from the live set so the guardian won't double-free.
  (define (pointerlike-free! p)
    (unless (ptrlike? p)
      (error 'pointerlike-free! "expected a pointerlike" p))
    (unless (ptrlike-freed? p)
      (let ([pool (ptrlike-pool p)]
            [live-set (gpool-live-set (ptrlike-pool p))])
        (guard (e [#t (void)])
          ((gpool-cleanup-proc pool) p))
        (hashtable-delete! live-set p)
        (ptrlike-freed?-set! p #t)
        (ptrlike-val-set! p #f))))

) ;; end library
