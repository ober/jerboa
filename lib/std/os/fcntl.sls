#!chezscheme
;;; :std/os/fcntl -- File descriptor control via fcntl(2)
;;;
;;; Provides fcntl operations for manipulating file descriptor flags
;;; (F_GETFL/F_SETFL) and file descriptor properties (F_GETFD/F_SETFD).
;;; Includes convenience procedures for setting non-blocking and
;;; close-on-exec flags.

(library (std os fcntl)
  (export
    fcntl-getfl fcntl-setfl
    fcntl-getfd fcntl-setfd
    fd-set-nonblock! fd-set-cloexec!
    fd-flags
    O_NONBLOCK O_CLOEXEC O_APPEND
    FD_CLOEXEC
    F_GETFL F_SETFL F_GETFD F_SETFD)

  (import (chezscheme))

  ;; Load libc
  (define _libc (or (guard (e [#t #f]) (load-shared-object "libc.so.7"))
                    (guard (e [#t #f]) (load-shared-object "libc.so.6"))
                    (guard (e [#t #f]) (load-shared-object "libc.so"))))

  ;; fcntl FFI — uses the 3-argument form (fd, cmd, arg)
  (define c-fcntl (foreign-procedure "fcntl" (int int int) int))

  ;; errno access for error reporting
  (define c-errno-location
    (if (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb))
      (foreign-procedure "__error" () void*)
      (foreign-procedure "__errno_location" () void*)))
  (define (get-errno) (foreign-ref 'int (c-errno-location) 0))

  ;; ========== Constants ==========

  ;; fcntl commands
  (define F_GETFD 1)
  (define F_SETFD 2)
  (define F_GETFL 3)
  (define F_SETFL 4)

  ;; File status flags (F_GETFL/F_SETFL)
  (define O_APPEND    #x400)
  (define O_NONBLOCK  #x800)
  (define O_CLOEXEC   #x80000)

  ;; File descriptor flags (F_GETFD/F_SETFD)
  (define FD_CLOEXEC 1)

  ;; ========== Core Operations ==========

  (define (fcntl-getfl fd)
    ;; Get file status flags. Returns integer flags or raises error.
    (let ([rc (c-fcntl fd F_GETFL 0)])
      (when (< rc 0)
        (error 'fcntl-getfl "fcntl F_GETFL failed" fd (get-errno)))
      rc))

  (define (fcntl-setfl fd flags)
    ;; Set file status flags. Returns void or raises error.
    (let ([rc (c-fcntl fd F_SETFL flags)])
      (when (< rc 0)
        (error 'fcntl-setfl "fcntl F_SETFL failed" fd (get-errno)))
      (void)))

  (define (fcntl-getfd fd)
    ;; Get file descriptor flags. Returns integer flags or raises error.
    (let ([rc (c-fcntl fd F_GETFD 0)])
      (when (< rc 0)
        (error 'fcntl-getfd "fcntl F_GETFD failed" fd (get-errno)))
      rc))

  (define (fcntl-setfd fd flags)
    ;; Set file descriptor flags. Returns void or raises error.
    (let ([rc (c-fcntl fd F_SETFD flags)])
      (when (< rc 0)
        (error 'fcntl-setfd "fcntl F_SETFD failed" fd (get-errno)))
      (void)))

  ;; ========== Convenience ==========

  (define (fd-set-nonblock! fd)
    ;; Set O_NONBLOCK on fd. Gets current flags, ORs in O_NONBLOCK, sets.
    (let ([flags (fcntl-getfl fd)])
      (fcntl-setfl fd (bitwise-ior flags O_NONBLOCK))))

  (define (fd-set-cloexec! fd)
    ;; Set FD_CLOEXEC on fd. Gets current fd flags, ORs in FD_CLOEXEC, sets.
    (let ([flags (fcntl-getfd fd)])
      (fcntl-setfd fd (bitwise-ior flags FD_CLOEXEC))))

  (define (fd-flags fd)
    ;; Return an alist of current flag states for inspection/debugging.
    (let ([fl (fcntl-getfl fd)]
          [fdfl (fcntl-getfd fd)])
      `((nonblock . ,(not (zero? (bitwise-and fl O_NONBLOCK))))
        (append   . ,(not (zero? (bitwise-and fl O_APPEND))))
        (cloexec  . ,(not (zero? (bitwise-and fdfl FD_CLOEXEC)))))))

  ) ;; end library
