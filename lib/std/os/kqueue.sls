#!chezscheme
;;; :std/os/kqueue -- BSD/macOS kqueue event notification
;;;
;;; On macOS: wraps kqueue(2) and kevent(2) via FFI.
;;; On Linux: all operational functions raise a clear error directing
;;; users to (std os epoll).  Constants and record types are still
;;; defined so code that references them can compile.

(library (std os kqueue)
  (export
    kqueue-create kqueue-close
    kqueue-add-read kqueue-add-write
    kqueue-add-signal kqueue-add-timer
    kqueue-remove kqueue-wait
    kqueue-event? kqueue-event-fd
    kqueue-event-filter kqueue-event-data
    EVFILT_READ EVFILT_WRITE EVFILT_SIGNAL EVFILT_TIMER
    EV_ADD EV_DELETE EV_ENABLE EV_DISABLE)

  (import (chezscheme))

  ;; ---------- Platform detection ----------

  (define (macos?)
    (let ([mt (symbol->string (machine-type))])
      (let loop ([i 0])
        (cond
          [(> (+ i 3) (string-length mt)) #f]
          [(string=? (substring mt i (+ i 3)) "osx") #t]
          [else (loop (+ i 1))]))))

  (define (platform-error who)
    (error who "kqueue is not available on this platform; use (std os epoll) instead"))

  ;; ---------- Constants ----------
  ;; These are defined on all platforms so referencing code compiles.

  (define EVFILT_READ   -1)
  (define EVFILT_WRITE  -2)
  (define EVFILT_SIGNAL -6)
  (define EVFILT_TIMER  -7)

  (define EV_ADD     #x0001)
  (define EV_DELETE  #x0002)
  (define EV_ENABLE  #x0004)
  (define EV_DISABLE #x0008)

  ;; ---------- Event record ----------

  (define-record-type kqueue-event
    (fields fd filter data))

  ;; ---------- macOS FFI ----------

  ;; struct kevent on macOS/amd64:
  ;;   uintptr_t ident;    8 bytes  offset 0
  ;;   int16_t   filter;   2 bytes  offset 8
  ;;   uint16_t  flags;    2 bytes  offset 10
  ;;   uint32_t  fflags;   4 bytes  offset 12
  ;;   intptr_t  data;     8 bytes  offset 16
  ;;   void     *udata;    8 bytes  offset 24
  ;; Total: 32 bytes

  (define kevent-size 32)

  (define (pack-kevent! bv offset ident filter flags fflags data udata)
    (bytevector-u64-set! bv (+ offset 0) ident (native-endianness))
    (bytevector-s16-set! bv (+ offset 8) filter (native-endianness))
    (bytevector-u16-set! bv (+ offset 10) flags (native-endianness))
    (bytevector-u32-set! bv (+ offset 12) fflags (native-endianness))
    (bytevector-s64-set! bv (+ offset 16) data (native-endianness))
    (bytevector-u64-set! bv (+ offset 24) udata (native-endianness)))

  (define (unpack-kevent bv offset)
    (make-kqueue-event
      (bytevector-u64-ref bv (+ offset 0) (native-endianness))   ; ident/fd
      (bytevector-s16-ref bv (+ offset 8) (native-endianness))   ; filter
      (bytevector-s64-ref bv (+ offset 16) (native-endianness)))) ; data

  ;; ---------- Implementation ----------

  (define kqueue-ffi
    (if (macos?)
      (foreign-procedure "kqueue" () int)
      #f))

  (define kevent-ffi
    (if (macos?)
      (foreign-procedure "kevent" (int void* int void* int void*) int)
      #f))

  (define close-ffi
    (if (macos?)
      (foreign-procedure "close" (int) int)
      #f))

  (define (kqueue-create)
    (if (macos?)
      (let ([fd (kqueue-ffi)])
        (when (< fd 0)
          (error 'kqueue-create "kqueue() failed" fd))
        fd)
      (platform-error 'kqueue-create)))

  (define (kqueue-close kq)
    (if (macos?)
      (close-ffi kq)
      (platform-error 'kqueue-close)))

  (define (kqueue-kevent-register kq ident filter flags)
    ;; Register a single kevent change
    (let ([change (make-bytevector kevent-size 0)])
      (pack-kevent! change 0 ident filter flags 0 0 0)
      (let ([rc (kevent-ffi kq
                            change 1   ;; changelist, nchanges
                            0 0         ;; eventlist, nevents (null, 0)
                            0)])        ;; timeout (null = no wait)
        (when (< rc 0)
          (error 'kqueue-register "kevent() register failed" rc ident filter)))))

  (define (kqueue-add-read kq fd)
    (if (macos?)
      (kqueue-kevent-register kq fd EVFILT_READ EV_ADD)
      (platform-error 'kqueue-add-read)))

  (define (kqueue-add-write kq fd)
    (if (macos?)
      (kqueue-kevent-register kq fd EVFILT_WRITE EV_ADD)
      (platform-error 'kqueue-add-write)))

  (define (kqueue-add-signal kq signo)
    (if (macos?)
      (kqueue-kevent-register kq signo EVFILT_SIGNAL EV_ADD)
      (platform-error 'kqueue-add-signal)))

  (define (kqueue-add-timer kq ident millis)
    (if (macos?)
      (let ([change (make-bytevector kevent-size 0)])
        (pack-kevent! change 0 ident EVFILT_TIMER EV_ADD 0 millis 0)
        (let ([rc (kevent-ffi kq change 1 0 0 0)])
          (when (< rc 0)
            (error 'kqueue-add-timer "kevent() timer failed" rc ident millis))))
      (platform-error 'kqueue-add-timer)))

  (define (kqueue-remove kq fd filter)
    (if (macos?)
      (kqueue-kevent-register kq fd filter EV_DELETE)
      (platform-error 'kqueue-remove)))

  (define (kqueue-wait kq max-events timeout-ms)
    ;; Wait for events. timeout-ms: #f = block forever, 0 = poll, N = milliseconds.
    ;; Returns a list of kqueue-event records.
    (if (macos?)
      (let* ([buf (make-bytevector (* kevent-size max-events) 0)]
             [ts (if timeout-ms
                   (let ([bv (make-bytevector 16 0)])
                     ;; struct timespec: tv_sec (8 bytes) + tv_nsec (8 bytes)
                     (bytevector-s64-set! bv 0 (div timeout-ms 1000) (native-endianness))
                     (bytevector-s64-set! bv 8 (* (mod timeout-ms 1000) 1000000) (native-endianness))
                     bv)
                   0)]  ;; null pointer = block forever
             [n (kevent-ffi kq 0 0 buf max-events ts)])
        (cond
          [(< n 0) (error 'kqueue-wait "kevent() wait failed" n)]
          [(= n 0) '()]
          [else
           (let loop ([i 0] [acc '()])
             (if (= i n)
               (reverse acc)
               (loop (+ i 1)
                     (cons (unpack-kevent buf (* i kevent-size)) acc))))]))
      (platform-error 'kqueue-wait)))

  ) ;; end library
