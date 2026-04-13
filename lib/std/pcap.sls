#!chezscheme
;;; (std pcap) — Live packet capture via rscap (Rust)
;;;
;;; Wraps libjerboa_native.so FFI for raw layer-2 packet capture.
;;;
;;; Usage:
;;;   (import (std pcap))
;;;   (def cap (pcap-open "eth0"))         ; open + activate capture
;;;   (def pkt (pcap-next cap))            ; => #(bytevector ts-sec ts-usec) or #f
;;;   (pcap-close cap)                     ; free handle
;;;   (pcap-interfaces)                    ; => ("lo" "eth0" ...)
;;;
;;; Notes:
;;;   - Requires root or CAP_NET_RAW on Linux; root on macOS (BPF device).
;;;   - pcap-next blocks until a packet arrives.
;;;   - The returned bytevector is a fresh copy each call — safe to retain.

(library (std pcap)
  (export
    pcap-open
    pcap-next
    pcap-close
    pcap-interfaces
    pcap-available?)

  (import (chezscheme))

  ;; Load native library — try relative paths first, then absolute fallbacks
  (define _loaded
    (let* ([home       (or (getenv "HOME") "")]
           [jerboa-dir (or (getenv "JERBOA_HOME")
                           (string-append home "/mine/jerboa"))])
      (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
          (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
          (guard (e [#t #f]) (load-shared-object "libjerboa_native.dylib") #t)
          (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.dylib") #t)
          ;; Absolute fallback for macOS (dylib in JERBOA_HOME/lib/)
          (guard (e [#t #f])
            (load-shared-object (string-append jerboa-dir "/lib/libjerboa_native.dylib"))
            #t)
          ;; Absolute fallback for Linux
          (guard (e [#t #f])
            (load-shared-object (string-append jerboa-dir "/lib/libjerboa_native.so"))
            #t)
          #f)))

  (define (pcap-available?) _loaded)

  ;; ── Sub-bytevector helper (bytevector-copy in Chez takes 1 arg, not 3) ────

  (define (bv-sub bv start len)
    (let ([out (make-bytevector len)])
      (bytevector-copy! bv start out 0 len)
      out))

  ;; ── FFI declarations ──────────────────────────────────────────────────────

  (define c-pcap-open
    (foreign-procedure "jerboa_pcap_open" (u8* size_t) integer-64))

  (define c-pcap-next
    (foreign-procedure "jerboa_pcap_next"
      (integer-64 u8* size_t u8* u8*) int))

  (define c-pcap-close
    (foreign-procedure "jerboa_pcap_close" (integer-64) int))

  (define c-pcap-list-interfaces
    (foreign-procedure "jerboa_pcap_list_interfaces" (u8* size_t) int))

  (define c-last-error
    (foreign-procedure "jerboa_last_error" (u8* size_t) size_t))

  ;; ── Error helper ─────────────────────────────────────────────────────────

  (define (last-error)
    (let ([buf (make-bytevector 1024 0)])
      (let ([n (c-last-error buf 1024)])
        (if (> n 0)
            (utf8->string (bv-sub buf 0 (min n 1023)))
            "unknown error"))))

  ;; ── pcap-open ─────────────────────────────────────────────────────────────

  ;;; Open a live capture on IFACE (string, e.g. "eth0").
  ;;; Returns an opaque handle. Raises an error on failure.
  ;;; Requires root/CAP_NET_RAW.
  (define (pcap-open iface)
    (unless _loaded
      (error 'pcap-open "libjerboa_native not available"))
    (let* ([bv (string->utf8 iface)]
           [handle (c-pcap-open bv (bytevector-length bv))])
      (when (< handle 0)
        (error 'pcap-open (last-error) iface))
      handle))

  ;; ── pcap-next ────────────────────────────────────────────────────────────

  ;;; Block until the next packet arrives on the capture.
  ;;; Returns a vector #(data ts-sec ts-usec) where data is a bytevector.
  ;;; Returns #f if the sniffer is deactivated/closed.
  ;;; Raises on hard errors.
  (define pcap-next
    (let ([buf (make-bytevector 65536)])     ; reused per call — copied on return
      (define ts-sec-bv  (make-bytevector 8 0))
      (define ts-usec-bv (make-bytevector 8 0))
      (lambda (handle)
        (let ([n (c-pcap-next handle buf 65536 ts-sec-bv ts-usec-bv)])
          (cond
            [(> n 0)
             (let ([data (bv-sub buf 0 n)]
                   [ts-sec  (bytevector-u64-native-ref ts-sec-bv  0)]
                   [ts-usec (bytevector-u64-native-ref ts-usec-bv 0)])
               (vector data ts-sec ts-usec))]
            [(= n 0) #f]          ; deactivated / no data (non-blocking WouldBlock)
            [else
             (let ([msg (last-error)])
               ;; NotConnected = deactivated cleanly
               (if (string=? msg "")
                   #f
                   (error 'pcap-next msg)))])))))

  ;; ── pcap-close ───────────────────────────────────────────────────────────

  ;;; Close a capture handle and free its resources.
  (define (pcap-close handle)
    (c-pcap-close handle)
    (void))

  ;; ── pcap-interfaces ──────────────────────────────────────────────────────

  ;;; Return a list of network interface name strings available on this host.
  (define (pcap-interfaces)
    (unless _loaded
      (error 'pcap-interfaces "libjerboa_native not available"))
    (let ([buf (make-bytevector 4096 0)])
      (let ([n (c-pcap-list-interfaces buf 4096)])
        (if (< n 0)
            (error 'pcap-interfaces (last-error))
            (let ([s (utf8->string (bv-sub buf 0 n))])
              (if (string=? s "")
                  '()
                  ;; Manual newline split — string-split is Jerboa prelude, not in base Chez
                  (let loop ([i 0] [start 0] [acc '()] [len (string-length s)])
                    (cond
                      [(= i len)
                       (let ([part (substring s start i)])
                         (reverse (if (string=? part "") acc (cons part acc))))]
                      [(char=? (string-ref s i) #\newline)
                       (let ([part (substring s start i)])
                         (loop (+ i 1) (+ i 1)
                               (if (string=? part "") acc (cons part acc))
                               len))]
                      [else (loop (+ i 1) start acc len)]))))))))

  ) ;; end library
