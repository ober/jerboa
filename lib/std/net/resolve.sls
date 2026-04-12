#!chezscheme
;;; (std net resolve) — Fiber-aware DNS resolution
;;;
;;; Resolves hostnames on a thread pool since getaddrinfo blocks.
;;; The calling fiber parks while resolution happens on a pool thread.
;;;
;;; API:
;;;   (make-dns-resolver)           — create resolver (default 2 threads)
;;;   (make-dns-resolver n)         — create with n threads
;;;   (dns-resolver-start! r)       — start resolver
;;;   (dns-resolver-stop! r)        — stop resolver
;;;   (fiber-resolve host resolver) — resolve hostname, returns first IPv4 address string
;;;   (with-dns-resolver body ...)  — scoped resolver lifecycle

(library (std net resolve)
  (export
    make-dns-resolver
    dns-resolver?
    dns-resolver-start!
    dns-resolver-stop!
    fiber-resolve
    with-dns-resolver)

  (import (chezscheme)
          (std fiber)
          (std net workpool))

  ;; ========== FFI: getaddrinfo ==========

  (define _libc-loaded
    (let ((v (getenv "JEMACS_STATIC")))
      (if (and v (not (string=? v "")) (not (string=? v "0")))
          #f
          (load-shared-object #f))))

  (define c-getaddrinfo
    (foreign-procedure "getaddrinfo" (string string void* void*) int))
  (define c-freeaddrinfo
    (foreign-procedure "freeaddrinfo" (void*) void))
  (define c-inet-ntop
    (foreign-procedure "inet_ntop" (int void* u8* int) void*))

  (define AF_INET 2)
  (define SOCK_STREAM 1)
  (define INET_ADDRSTRLEN 16)

  ;; struct addrinfo layout (Linux x86_64):
  ;;   int      ai_flags       @ 0
  ;;   int      ai_family      @ 4
  ;;   int      ai_socktype    @ 8
  ;;   int      ai_protocol    @ 12
  ;;   socklen  ai_addrlen     @ 16  (unsigned int)
  ;;   padding                 @ 20  (4 bytes on 64-bit)
  ;;   void*    ai_addr        @ 24  (pointer, 8 bytes on 64-bit)
  ;;   char*    ai_canonname   @ 32
  ;;   void*    ai_next        @ 40

  (define (resolve-blocking hostname)
    ;; Set up hints: AF_INET, SOCK_STREAM
    (let ([hints (foreign-alloc 48)])
      ;; Zero out hints
      (do ([i 0 (+ i 1)]) ((= i 48))
        (foreign-set! 'unsigned-8 hints i 0))
      (foreign-set! 'int hints 4 AF_INET)     ;; ai_family
      (foreign-set! 'int hints 8 SOCK_STREAM) ;; ai_socktype

      (let ([result-ptr (foreign-alloc 8)])
        (foreign-set! 'void* result-ptr 0 0)
        (let ([rc (c-getaddrinfo hostname #f hints result-ptr)])
          (foreign-free hints)
          (cond
            [(not (= rc 0))
             (foreign-free result-ptr)
             (error 'fiber-resolve "DNS resolution failed" hostname rc)]
            [else
             (let ([result (foreign-ref 'void* result-ptr 0)])
               (foreign-free result-ptr)
               (if (= result 0)
                 (error 'fiber-resolve "no addresses found" hostname)
                 ;; Extract first IPv4 address
                 ;; sockaddr_in: family(2) + port(2) + in_addr(4)
                 ;; in_addr starts at offset 4 in sockaddr_in
                 (let ([addr-ptr (foreign-ref 'void* result 24)])
                   (let ([in-addr-ptr (+ addr-ptr 4)]
                         [buf (make-bytevector INET_ADDRSTRLEN)])
                     (let ([p (c-inet-ntop AF_INET in-addr-ptr buf INET_ADDRSTRLEN)])
                       (c-freeaddrinfo result)
                       (if (= p 0)
                         (error 'fiber-resolve "inet_ntop failed" hostname)
                         ;; Read null-terminated string from buf
                         (let loop ([i 0])
                           (if (= (bytevector-u8-ref buf i) 0)
                             (bytevector->string
                               (let ([b (make-bytevector i)])
                                 (bytevector-copy! buf 0 b 0 i) b)
                               (make-transcoder (utf-8-codec)))
                             (loop (+ i 1))))))))))])))))

  ;; ========== DNS Resolver ==========

  (define-record-type dns-resolver
    (fields (immutable pool))
    (protocol
      (lambda (new)
        (case-lambda
          [() (new (make-work-pool 2))]
          [(n) (new (make-work-pool n))]))))

  (define (dns-resolver-start! r)
    (work-pool-start! (dns-resolver-pool r)))

  (define (dns-resolver-stop! r)
    (work-pool-stop! (dns-resolver-pool r)))

  ;; Resolve hostname from a fiber — parks fiber while resolution runs.
  ;; Returns IPv4 address as a string (e.g., "93.184.216.34").
  (define (fiber-resolve hostname resolver)
    (work-pool-submit! (dns-resolver-pool resolver)
      (lambda () (resolve-blocking hostname))))

  ;; Convenience macro
  (define-syntax with-dns-resolver
    (syntax-rules ()
      [(_ var body ...)
       (let ([var (make-dns-resolver)])
         (dns-resolver-start! var)
         (guard (exn [#t (dns-resolver-stop! var) (raise exn)])
           (let ([result (begin body ...)])
             (dns-resolver-stop! var)
             result)))]))

) ;; end library
