#!chezscheme
;;; (std net zero-copy) — Zero-Copy Buffer Management
;;;
;;; Pool of pre-allocated bytevectors. Slices are views into those buffers
;;; (offset + length), avoiding data copies. Reference counting tracks
;;; live slices so buffers can be safely returned to the pool.
;;;
;;; API:
;;;   (make-buffer-pool size count)    — pool of `count` buffers of `size` bytes
;;;   (pool-acquire! pool)             — get a buffer (blocks if none available)
;;;   (pool-release! pool buf-id)      — return buffer to pool
;;;   (make-buffer-slice buf-id offset length pool)  — create a slice view
;;;   (slice-data slice)               — the underlying bytevector
;;;   (slice-offset slice)             — offset into buffer
;;;   (slice-length slice)             — length of this slice
;;;   (slice-copy! dst dst-offset slice) — copy slice into another bytevector
;;;   (buffer-pool-stats pool)         — returns alist of stats
;;;   (with-buffer pool proc)          — acquire, call proc with buffer, release
;;;   (slice->bytevector slice)        — copy slice contents to fresh bytevector

(library (std net zero-copy)
  (export
    make-buffer-pool
    buffer-pool?
    pool-acquire!
    pool-release!
    make-buffer-slice
    buffer-slice?
    slice-data
    slice-offset
    slice-length
    slice-copy!
    buffer-pool-stats
    with-buffer
    slice->bytevector)

  (import (chezscheme))

  ;; ========== Buffer Entry ==========
  ;; Each slot in the pool is tracked with a refcount.

  (define-record-type buffer-entry
    (fields
      id              ;; integer id
      data            ;; bytevector
      (mutable refcount)  ;; number of live slices
      (mutable in-use?))  ;; currently acquired by a consumer
    (protocol
      (lambda (new)
        (lambda (id data)
          (new id data 0 #f)))))

  ;; ========== Buffer Pool ==========

  (define-record-type (buffer-pool %make-buffer-pool buffer-pool?)
    (fields
      buf-size        ;; bytes per buffer
      entries         ;; vector of buffer-entry
      (mutable available)  ;; list of free entry ids
      mutex
      not-empty       ;; condition: a buffer became available
      (mutable stats-acquired)
      (mutable stats-released)
      (mutable stats-waits)))

  (define (make-buffer-pool buf-size count)
    (let* ([entries (let build ([i 0] [acc '()])
                      (if (= i count)
                        (list->vector (reverse acc))
                        (build (+ i 1)
                          (cons (make-buffer-entry i (make-bytevector buf-size 0))
                                acc))))]
           [available (let build ([i 0] [acc '()])
                        (if (= i count) (reverse acc) (build (+ i 1) (cons i acc))))])
      (%make-buffer-pool
        buf-size entries available
        (make-mutex) (make-condition)
        0 0 0)))

  (define (pool-acquire! pool)
    ;; Returns (values buf-id bytevector)
    (mutex-acquire (buffer-pool-mutex pool))
    (let loop ()
      (cond
        [(pair? (buffer-pool-available pool))
         (let* ([id (car (buffer-pool-available pool))]
                [entry (vector-ref (buffer-pool-entries pool) id)])
           (buffer-pool-available-set! pool (cdr (buffer-pool-available pool)))
           (buffer-entry-in-use?-set! entry #t)
           (buffer-pool-stats-acquired-set! pool
             (+ (buffer-pool-stats-acquired pool) 1))
           (mutex-release (buffer-pool-mutex pool))
           (values id (buffer-entry-data entry)))]
        [else
         (buffer-pool-stats-waits-set! pool
           (+ (buffer-pool-stats-waits pool) 1))
         (condition-wait (buffer-pool-not-empty pool)
                         (buffer-pool-mutex pool))
         (loop)])))

  (define (pool-release! pool buf-id)
    (mutex-acquire (buffer-pool-mutex pool))
    (let ([entry (vector-ref (buffer-pool-entries pool) buf-id)])
      (when (= (buffer-entry-refcount entry) 0)
        (buffer-entry-in-use?-set! entry #f)
        (buffer-pool-available-set! pool
          (cons buf-id (buffer-pool-available pool)))
        (buffer-pool-stats-released-set! pool
          (+ (buffer-pool-stats-released pool) 1))
        (condition-signal (buffer-pool-not-empty pool))))
    (mutex-release (buffer-pool-mutex pool)))

  (define (buffer-pool-stats pool)
    (mutex-acquire (buffer-pool-mutex pool))
    (let ([stats
           (list
             (cons 'buf-size (buffer-pool-buf-size pool))
             (cons 'total (vector-length (buffer-pool-entries pool)))
             (cons 'available (length (buffer-pool-available pool)))
             (cons 'acquired (buffer-pool-stats-acquired pool))
             (cons 'released (buffer-pool-stats-released pool))
             (cons 'waits (buffer-pool-stats-waits pool)))])
      (mutex-release (buffer-pool-mutex pool))
      stats))

  ;; ========== Buffer Slice ==========
  ;; A slice is a view into a buffer: no data copied.

  (define-record-type (buffer-slice %make-buffer-slice buffer-slice?)
    (fields
      buf-id     ;; which buffer
      data       ;; direct reference to bytevector
      offset     ;; starting offset
      length     ;; number of bytes in this slice
      pool))     ;; owning pool (for release)

  (define (make-buffer-slice buf-id offset length pool)
    ;; Increment refcount
    (let ([entry (vector-ref (buffer-pool-entries pool) buf-id)])
      (mutex-acquire (buffer-pool-mutex pool))
      (buffer-entry-refcount-set! entry (+ (buffer-entry-refcount entry) 1))
      (mutex-release (buffer-pool-mutex pool)))
    (%make-buffer-slice buf-id
                        (buffer-entry-data
                          (vector-ref (buffer-pool-entries pool) buf-id))
                        offset length pool))

  ;; Accessors with renamed field names to avoid confusion
  (define (slice-data slice) (buffer-slice-data slice))
  (define (slice-offset slice) (buffer-slice-offset slice))
  (define (slice-length slice) (buffer-slice-length slice))

  (define (slice-copy! dst dst-offset slice)
    ;; Copy slice contents into dst bytevector at dst-offset
    (let ([src (buffer-slice-data slice)]
          [src-off (buffer-slice-offset slice)]
          [len (buffer-slice-length slice)])
      (let loop ([i 0])
        (when (< i len)
          (bytevector-u8-set! dst (+ dst-offset i)
            (bytevector-u8-ref src (+ src-off i)))
          (loop (+ i 1))))))

  (define (slice->bytevector slice)
    (let* ([len (buffer-slice-length slice)]
           [bv (make-bytevector len)])
      (slice-copy! bv 0 slice)
      bv))

  ;; ========== with-buffer ==========

  (define (with-buffer pool proc)
    ;; Acquire a buffer, call proc with (buf-id bv), always release
    (let-values ([(buf-id bv) (pool-acquire! pool)])
      (dynamic-wind
        (lambda () (void))
        (lambda () (proc buf-id bv))
        (lambda () (pool-release! pool buf-id)))))

) ;; end library
