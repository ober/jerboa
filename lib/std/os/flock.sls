#!chezscheme
;;; :std/os/flock -- File locking via flock(2)
;;;
;;; Provides POSIX advisory file locking. Locks are per-open-file-description,
;;; inherited across fork, and released on close. Use with-file-lock for
;;; guaranteed cleanup via dynamic-wind.

(library (std os flock)
  (export
    flock-exclusive flock-shared flock-unlock
    flock-try-exclusive flock-try-shared
    with-file-lock
    LOCK_SH LOCK_EX LOCK_UN LOCK_NB)

  (import (chezscheme))

  ;; Load libc
  (define _libc (or (guard (e [#t #f]) (load-shared-object "libc.so.7"))
                    (guard (e [#t #f]) (load-shared-object "libc.so.6"))
                    (guard (e [#t #f]) (load-shared-object "libc.so"))))

  ;; flock(2) FFI
  (define c-flock (foreign-procedure "flock" (int int) int))

  ;; errno access
  (define c-errno-location (foreign-procedure "__errno_location" () void*))
  (define (get-errno) (foreign-ref 'int (c-errno-location) 0))
  (define EWOULDBLOCK 11)  ;; same as EAGAIN on Linux

  ;; ========== Constants ==========

  (define LOCK_SH 1)   ;; shared lock
  (define LOCK_EX 2)   ;; exclusive lock
  (define LOCK_UN 8)   ;; unlock
  (define LOCK_NB 4)   ;; non-blocking (OR with SH or EX)

  ;; ========== Core Operations ==========

  (define (do-flock who fd operation)
    ;; Call flock, retry on EINTR, raise error on failure.
    (let loop ()
      (let ([rc (c-flock fd operation)])
        (cond
          [(= rc 0) (void)]
          [(= (get-errno) 4)  ;; EINTR
           (loop)]
          [else
           (error who "flock failed" fd (get-errno))]))))

  (define (flock-exclusive fd)
    ;; Acquire an exclusive (write) lock. Blocks until acquired.
    (do-flock 'flock-exclusive fd LOCK_EX))

  (define (flock-shared fd)
    ;; Acquire a shared (read) lock. Blocks until acquired.
    (do-flock 'flock-shared fd LOCK_SH))

  (define (flock-unlock fd)
    ;; Release lock on fd.
    (do-flock 'flock-unlock fd LOCK_UN))

  (define (flock-try-exclusive fd)
    ;; Try to acquire exclusive lock without blocking.
    ;; Returns #t if acquired, #f if would block.
    (let loop ()
      (let ([rc (c-flock fd (bitwise-ior LOCK_EX LOCK_NB))])
        (cond
          [(= rc 0) #t]
          [(= (get-errno) EWOULDBLOCK) #f]
          [(= (get-errno) 4) (loop)]  ;; EINTR
          [else (error 'flock-try-exclusive "flock failed" fd (get-errno))]))))

  (define (flock-try-shared fd)
    ;; Try to acquire shared lock without blocking.
    ;; Returns #t if acquired, #f if would block.
    (let loop ()
      (let ([rc (c-flock fd (bitwise-ior LOCK_SH LOCK_NB))])
        (cond
          [(= rc 0) #t]
          [(= (get-errno) EWOULDBLOCK) #f]
          [(= (get-errno) 4) (loop)]  ;; EINTR
          [else (error 'flock-try-shared "flock failed" fd (get-errno))]))))

  ;; ========== with-file-lock ==========

  (define-syntax with-file-lock
    (syntax-rules ()
      [(_ fd lock-type body body* ...)
       (dynamic-wind
         (lambda () (do-flock 'with-file-lock fd lock-type))
         (lambda () body body* ...)
         (lambda () (do-flock 'with-file-lock fd LOCK_UN)))]))

  ) ;; end library
