#!chezscheme
;;; :std/web/fastcgi -- FastCGI protocol implementation
;;;
;;; Implements the FastCGI binary protocol (spec version 1)
;;; for serving web applications behind a FastCGI-capable web server
;;; (nginx, Apache, lighttpd, etc.).
;;;
;;; Protocol reference: https://fastcgi-archives.github.io/FastCGI_Specification.html
;;;
;;; Record format (8 bytes):
;;;   version(1) | type(1) | requestIdB1(1) | requestIdB0(1)
;;;   contentLengthB1(1) | contentLengthB0(1) | paddingLength(1) | reserved(1)
;;;   contentData[contentLength] | paddingData[paddingLength]

(library (std web fastcgi)
  (export
    fastcgi-listen
    fastcgi-accept
    fastcgi-request-params
    fastcgi-request-stdin
    fastcgi-respond
    fastcgi-close
    make-fastcgi-server)

  (import (chezscheme))

  ;; ========== FFI ==========

  (define _libc-loaded
    (let ((v (getenv "JEMACS_STATIC")))
      (if (and v (not (string=? v "")) (not (string=? v "0")))
          #f
          (load-shared-object #f))))

  (define c-socket    (foreign-procedure "socket" (int int int) int))
  (define c-bind      (foreign-procedure "bind" (int void* int) int))
  (define c-listen    (foreign-procedure "listen" (int int) int))
  (define c-accept    (foreign-procedure "accept" (int void* void*) int))
  (define c-close     (foreign-procedure "close" (int) int))
  (define c-setsockopt (foreign-procedure "setsockopt" (int int int void* int) int))
  (define c-read      (foreign-procedure "read" (int void* size_t) ssize_t))
  (define c-write     (foreign-procedure "write" (int void* size_t) ssize_t))
  (define c-htons     (foreign-procedure "htons" (unsigned-short) unsigned-short))
  (define c-inet-pton (foreign-procedure "inet_pton" (int string void*) int))
  (define c-fcntl     (foreign-procedure "fcntl" (int int int) int))
  (define c-errno-location
    (let ((mt (symbol->string (machine-type))))

      (if (or (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb))

              (and (>= (string-length mt) 3)

                   (string=? (substring mt (- (string-length mt) 3) (string-length mt)) "osx")))

        (foreign-procedure "__error" () void*)

        (foreign-procedure "__errno_location" () void*))))
  (define (get-errno) (foreign-ref 'int (c-errno-location) 0))

  (define AF_INET 2)
  (define SOCK_STREAM 1)
  (define SOL_SOCKET (if *freebsd?* #xffff 1))
  (define SO_REUSEADDR (if *freebsd?* 4 2))
  (define INADDR_ANY 0)
  (define SOCKADDR_IN_SIZE 16)
  (define *freebsd?* (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb)))
  (define EINTR 4)
  (define EAGAIN (if *freebsd?* 35 11))
  (define F_GETFL 3)
  (define F_SETFL 4)
  (define O_NONBLOCK
    (if (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb)) #x4 #x800))

  (define *retry-delay* (make-time 'time-duration 10000000 0))

  ;; ========== FastCGI protocol constants ==========

  (define FCGI_VERSION_1 1)

  ;; Record types
  (define FCGI_BEGIN_REQUEST    1)
  (define FCGI_ABORT_REQUEST   2)
  (define FCGI_END_REQUEST     3)
  (define FCGI_PARAMS          4)
  (define FCGI_STDIN           5)
  (define FCGI_STDOUT          6)
  (define FCGI_STDERR          7)
  (define FCGI_DATA            8)
  (define FCGI_GET_VALUES      9)
  (define FCGI_GET_VALUES_RESULT 10)
  (define FCGI_UNKNOWN_TYPE    11)

  ;; Roles (in BEGIN_REQUEST body)
  (define FCGI_RESPONDER  1)
  (define FCGI_AUTHORIZER 2)
  (define FCGI_FILTER     3)

  ;; Protocol status (in END_REQUEST body)
  (define FCGI_REQUEST_COMPLETE 0)
  (define FCGI_CANT_MPX_CONN    1)
  (define FCGI_OVERLOADED       2)
  (define FCGI_UNKNOWN_ROLE     3)

  ;; Header size
  (define FCGI_HEADER_SIZE 8)

  ;; Max content per record
  (define FCGI_MAX_CONTENT_LEN 65535)

  ;; ========== Record types ==========

  ;; A parsed FastCGI record header
  (define-record-type fcgi-header
    (fields version type request-id content-length padding-length))

  ;; A FastCGI request (accumulated from multiple records)
  (define-record-type fcgi-request
    (fields
      (mutable request-id)
      (mutable role)
      (mutable flags)
      (mutable params)       ;; alist of (name . value)
      (mutable stdin-data)   ;; bytevector
      (mutable client-fd)))  ;; the socket fd for this connection

  ;; A FastCGI server (listener)
  (define-record-type fcgi-server
    (fields fd port))

  ;; ========== Bytevector helpers ==========

  (define (bytevector->pointer bv)
    (#%$object-address bv (+ (foreign-sizeof 'ptr) 1)))

  (define (bytevector->pointer-offset bv offset)
    (+ (bytevector->pointer bv) offset))

  (define (make-sockaddr-in address port)
    (let ((buf (make-bytevector SOCKADDR_IN_SIZE 0)))
      (if *freebsd?*
          (begin
            (bytevector-u8-set! buf 0 16)        ;; sin_len = sizeof(sockaddr_in)
            (bytevector-u8-set! buf 1 AF_INET))  ;; sin_family (uint8)
          (bytevector-u16-set! buf 0 AF_INET (native-endianness)))
      (bytevector-u16-set! buf 2 (c-htons port) (native-endianness))
      (if (string=? address "0.0.0.0")
          (bytevector-u32-set! buf 4 INADDR_ANY (native-endianness))
          (begin
            (let ((addr-buf (make-bytevector 4 0)))
              (c-inet-pton AF_INET address (bytevector->pointer addr-buf))
              (bytevector-copy! addr-buf 0 buf 4 4))))
      buf))

  ;; ========== Low-level I/O ==========

  ;; Read exactly n bytes from fd. Returns bytevector or #f on EOF/error.
  (define (read-exactly fd n)
    (let ((buf (make-bytevector n)))
      (let lp ((pos 0))
        (if (>= pos n)
            buf
            (let ((ret (c-read fd
                               (bytevector->pointer-offset buf pos)
                               (- n pos))))
              (cond
                ((> ret 0) (lp (+ pos ret)))
                ((= ret 0) #f)  ;; EOF
                (else
                 (let ((err (get-errno)))
                   (cond
                     ((= err EINTR) (lp pos))
                     ((= err EAGAIN)
                      (sleep *retry-delay*)
                      (lp pos))
                     (else #f))))))))))

  ;; Write all bytes from bytevector to fd.
  (define (write-all fd bv)
    (let ((len (bytevector-length bv)))
      (let lp ((pos 0))
        (when (< pos len)
          (let ((n (c-write fd
                            (bytevector->pointer-offset bv pos)
                            (- len pos))))
            (cond
              ((> n 0) (lp (+ pos n)))
              ((and (< n 0) (= (get-errno) EINTR)) (lp pos))
              ((and (< n 0) (= (get-errno) EAGAIN))
               (sleep *retry-delay*)
               (lp pos))
              (else (void))))))))

  ;; ========== FastCGI record reading ==========

  ;; Read a single FastCGI record header from fd.
  ;; Returns fcgi-header or #f on EOF.
  (define (read-fcgi-header fd)
    (let ((buf (read-exactly fd FCGI_HEADER_SIZE)))
      (and buf
           (make-fcgi-header
             (bytevector-u8-ref buf 0)           ;; version
             (bytevector-u8-ref buf 1)           ;; type
             (+ (bitwise-arithmetic-shift-left    ;; requestId (big-endian)
                  (bytevector-u8-ref buf 2) 8)
                (bytevector-u8-ref buf 3))
             (+ (bitwise-arithmetic-shift-left    ;; contentLength (big-endian)
                  (bytevector-u8-ref buf 4) 8)
                (bytevector-u8-ref buf 5))
             (bytevector-u8-ref buf 6)))))       ;; paddingLength

  ;; Read the content data of a record.
  ;; Returns bytevector (possibly empty) or #f on error.
  (define (read-fcgi-content fd header)
    (let ((clen (fcgi-header-content-length header))
          (plen (fcgi-header-padding-length header)))
      (let ((content (if (> clen 0)
                         (read-exactly fd clen)
                         (make-bytevector 0))))
        (when (and content (> plen 0))
          (read-exactly fd plen))  ;; discard padding
        content)))

  ;; ========== FastCGI name-value pair parsing ==========

  ;; Parse the name-value pair encoding used in PARAMS records.
  ;; Each pair: nameLength(1|4) valueLength(1|4) nameData valueData
  ;; Length encoding: if high bit set, 4 bytes big-endian (with high bit masked).
  (define (parse-name-value-pairs bv)
    (let ((len (bytevector-length bv)))
      (let lp ((pos 0) (acc '()))
        (if (>= pos len)
            (reverse acc)
            (let-values (((name-len pos2) (decode-length bv pos)))
              (if (not name-len)
                  (reverse acc)
                  (let-values (((val-len pos3) (decode-length bv pos2)))
                    (if (or (not val-len) (> (+ pos3 name-len val-len) len))
                        (reverse acc)
                        (let* ((name (utf8->string
                                       (bytevector-slice bv pos3 (+ pos3 name-len))))
                               (val  (utf8->string
                                       (bytevector-slice bv
                                         (+ pos3 name-len)
                                         (+ pos3 name-len val-len)))))
                          (lp (+ pos3 name-len val-len)
                              (cons (cons name val) acc)))))))))))

  ;; Decode a FastCGI length field. Returns (values length new-pos) or (values #f #f).
  (define (decode-length bv pos)
    (if (>= pos (bytevector-length bv))
        (values #f #f)
        (let ((b0 (bytevector-u8-ref bv pos)))
          (if (< b0 128)
              ;; 1-byte length
              (values b0 (+ pos 1))
              ;; 4-byte length (high bit is flag, mask it off)
              (if (> (+ pos 4) (bytevector-length bv))
                  (values #f #f)
                  (values (+ (bitwise-arithmetic-shift-left (bitwise-and b0 #x7f) 24)
                             (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ pos 1)) 16)
                             (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ pos 2)) 8)
                             (bytevector-u8-ref bv (+ pos 3)))
                          (+ pos 4)))))))

  ;; Encode a FastCGI length field.
  (define (encode-length n)
    (if (< n 128)
        (let ((bv (make-bytevector 1)))
          (bytevector-u8-set! bv 0 n)
          bv)
        (let ((bv (make-bytevector 4)))
          (bytevector-u8-set! bv 0 (bitwise-ior #x80
                                     (bitwise-and
                                       (bitwise-arithmetic-shift-right n 24) #x7f)))
          (bytevector-u8-set! bv 1 (bitwise-and (bitwise-arithmetic-shift-right n 16) #xff))
          (bytevector-u8-set! bv 2 (bitwise-and (bitwise-arithmetic-shift-right n 8) #xff))
          (bytevector-u8-set! bv 3 (bitwise-and n #xff))
          bv)))

  ;; Slice a bytevector
  (define (bytevector-slice bv start end)
    (let* ((len (- end start))
           (result (make-bytevector len)))
      (bytevector-copy! bv start result 0 len)
      result))

  ;; Concatenate bytevectors
  (define (bytevector-append . bvs)
    (let ((total (apply + (map bytevector-length bvs))))
      (let ((result (make-bytevector total)))
        (let lp ((bvs bvs) (pos 0))
          (if (null? bvs)
              result
              (let ((bv (car bvs)))
                (bytevector-copy! bv 0 result pos (bytevector-length bv))
                (lp (cdr bvs) (+ pos (bytevector-length bv)))))))))

  ;; ========== FastCGI record writing ==========

  ;; Build a FastCGI record header as a bytevector.
  (define (make-fcgi-header-bytes type request-id content-length)
    (let ((padding (modulo (- 8 (modulo content-length 8)) 8))
          (buf (make-bytevector FCGI_HEADER_SIZE 0)))
      ;; Clamp padding: if content-length is 0 mod 8, padding should be 0
      (let ((pad (if (= padding 8) 0 padding)))
        (bytevector-u8-set! buf 0 FCGI_VERSION_1)
        (bytevector-u8-set! buf 1 type)
        (bytevector-u8-set! buf 2 (bitwise-and (bitwise-arithmetic-shift-right request-id 8) #xff))
        (bytevector-u8-set! buf 3 (bitwise-and request-id #xff))
        (bytevector-u8-set! buf 4 (bitwise-and (bitwise-arithmetic-shift-right content-length 8) #xff))
        (bytevector-u8-set! buf 5 (bitwise-and content-length #xff))
        (bytevector-u8-set! buf 6 pad)
        (bytevector-u8-set! buf 7 0)
        (values buf pad))))

  ;; Write a complete FastCGI record (header + content + padding).
  (define (write-fcgi-record fd type request-id content)
    (let ((clen (bytevector-length content)))
      ;; Split into chunks of max FCGI_MAX_CONTENT_LEN
      (let lp ((pos 0))
        (if (>= pos clen)
            ;; Send empty record to signal stream end (if content was non-empty)
            (void)
            (let* ((chunk-len (min (- clen pos) FCGI_MAX_CONTENT_LEN)))
              (let-values (((hdr pad) (make-fcgi-header-bytes type request-id chunk-len)))
                (write-all fd hdr)
                (write-all fd (bytevector-slice content pos (+ pos chunk-len)))
                (when (> pad 0)
                  (write-all fd (make-bytevector pad 0)))
                (lp (+ pos chunk-len))))))))

  ;; Write an empty record (signals end of stream).
  (define (write-fcgi-empty-record fd type request-id)
    (let-values (((hdr _pad) (make-fcgi-header-bytes type request-id 0)))
      (write-all fd hdr)))

  ;; ========== Public API ==========

  ;; Create a TCP listener for FastCGI connections.
  ;; Returns an fcgi-server record.
  (define (fastcgi-listen address port)
    (let ((fd (c-socket AF_INET SOCK_STREAM 0)))
      (when (< fd 0)
        (error 'fastcgi-listen "socket() failed"))
      ;; SO_REUSEADDR
      (let ((one (make-bytevector 4 0)))
        (bytevector-s32-set! one 0 1 (native-endianness))
        (c-setsockopt fd SOL_SOCKET SO_REUSEADDR
                      (bytevector->pointer one) 4))
      (let* ((addr (make-sockaddr-in address port))
             (ret (c-bind fd (bytevector->pointer addr) SOCKADDR_IN_SIZE)))
        (when (< ret 0)
          (c-close fd)
          (error 'fastcgi-listen "bind() failed" address port)))
      (let ((ret (c-listen fd 128)))
        (when (< ret 0)
          (c-close fd)
          (error 'fastcgi-listen "listen() failed")))
      (make-fcgi-server fd port)))

  ;; Accept a FastCGI request: reads BEGIN_REQUEST, accumulates PARAMS
  ;; and STDIN records until their streams are closed (empty record).
  ;; Returns an fcgi-request record or #f on connection close.
  (define (fastcgi-accept server)
    (let* ((server-fd (fcgi-server-fd server))
           (addr (make-bytevector SOCKADDR_IN_SIZE 0))
           (len-buf (make-bytevector 4 0)))
      (bytevector-s32-set! len-buf 0 SOCKADDR_IN_SIZE (native-endianness))
      (let accept-retry ()
        (let ((client-fd (c-accept server-fd
                                   (bytevector->pointer addr)
                                   (bytevector->pointer len-buf))))
          (if (< client-fd 0)
              (let ((err (get-errno)))
                (cond
                  ((or (= err EINTR) (= err EAGAIN))
                   (sleep *retry-delay*)
                   (accept-retry))
                  (else #f)))
              ;; Read the FastCGI request from this connection
              (read-fastcgi-request client-fd))))))

  ;; Read a complete FastCGI request from a connection fd.
  ;; Accumulates BEGIN_REQUEST + PARAMS + STDIN records.
  (define (read-fastcgi-request client-fd)
    (let ((req (make-fcgi-request 0 0 0 '() (make-bytevector 0) client-fd))
          (params-data (make-bytevector 0))
          (stdin-data (make-bytevector 0))
          (params-done? #f)
          (stdin-done? #f))
      (let lp ()
        (let ((hdr (read-fcgi-header client-fd)))
          (if (not hdr)
              ;; Connection closed prematurely
              #f
              (let ((content (read-fcgi-content client-fd hdr))
                    (rtype (fcgi-header-type hdr)))
                (cond
                  ((not content) #f)

                  ;; BEGIN_REQUEST: extract role and flags
                  ((= rtype FCGI_BEGIN_REQUEST)
                   (when (>= (bytevector-length content) 3)
                     (let ((role (+ (bitwise-arithmetic-shift-left
                                      (bytevector-u8-ref content 0) 8)
                                    (bytevector-u8-ref content 1)))
                           (flags (bytevector-u8-ref content 2)))
                       (fcgi-request-request-id-set! req (fcgi-header-request-id hdr))
                       (fcgi-request-role-set! req role)
                       (fcgi-request-flags-set! req flags)))
                   (lp))

                  ;; PARAMS: accumulate until empty record
                  ((= rtype FCGI_PARAMS)
                   (if (= (bytevector-length content) 0)
                       (begin
                         (set! params-done? #t)
                         (fcgi-request-params-set! req
                           (parse-name-value-pairs params-data))
                         (if (and params-done? stdin-done?)
                             req
                             (lp)))
                       (begin
                         (set! params-data (bytevector-append params-data content))
                         (lp))))

                  ;; STDIN: accumulate until empty record
                  ((= rtype FCGI_STDIN)
                   (if (= (bytevector-length content) 0)
                       (begin
                         (set! stdin-done? #t)
                         (fcgi-request-stdin-data-set! req stdin-data)
                         (if (and params-done? stdin-done?)
                             req
                             (lp)))
                       (begin
                         (set! stdin-data (bytevector-append stdin-data content))
                         (lp))))

                  ;; ABORT_REQUEST
                  ((= rtype FCGI_ABORT_REQUEST)
                   #f)

                  ;; Unknown type: skip
                  (else (lp)))))))))

  ;; Get the params alist from a request.
  (define (fastcgi-request-params req)
    (fcgi-request-params req))

  ;; Get the stdin data as a bytevector.
  (define (fastcgi-request-stdin req)
    (fcgi-request-stdin-data req))

  ;; Send a response back on a FastCGI connection.
  ;; status: integer HTTP status code
  ;; headers: alist of (name . value)
  ;; body: string or bytevector
  (define (fastcgi-respond req status headers body)
    (let* ((client-fd (fcgi-request-client-fd req))
           (request-id (fcgi-request-request-id req))
           (body-bytes (if (bytevector? body) body (string->utf8 body)))
           ;; Build the HTTP response as STDOUT data
           (header-str (apply string-append
                              (cons (string-append "Status: "
                                                   (number->string status) "\r\n")
                                    (map (lambda (h)
                                           (string-append (car h) ": " (cdr h) "\r\n"))
                                         headers))))
           (stdout-data (bytevector-append
                          (string->utf8 (string-append header-str "\r\n"))
                          body-bytes)))
      ;; Send STDOUT records
      (write-fcgi-record client-fd FCGI_STDOUT request-id stdout-data)
      ;; Send empty STDOUT to close the stream
      (write-fcgi-empty-record client-fd FCGI_STDOUT request-id)
      ;; Send END_REQUEST
      (let ((end-body (make-bytevector 8 0)))
        ;; appStatus = 0 (4 bytes, big-endian) — already zero
        ;; protocolStatus = FCGI_REQUEST_COMPLETE (byte 4)
        (bytevector-u8-set! end-body 4 FCGI_REQUEST_COMPLETE)
        (write-fcgi-record client-fd FCGI_END_REQUEST request-id end-body))))

  ;; Close a FastCGI request connection.
  (define (fastcgi-close req)
    (c-close (fcgi-request-client-fd req)))

  ;; Convenience: create a FastCGI server that listens and dispatches
  ;; requests to a handler procedure.
  ;; handler: (lambda (params stdin) (values status headers body))
  ;; Runs in a loop, handling one request at a time.
  (define (make-fastcgi-server address port handler)
    (let ((server (fastcgi-listen address port)))
      (let loop ()
        (let ((req (fastcgi-accept server)))
          (when req
            (guard (exn
                    (#t
                     ;; On error, send 500 and close
                     (guard (exn2 (#t (void)))
                       (fastcgi-respond req 500
                         '(("Content-Type" . "text/plain"))
                         "Internal Server Error"))
                     (fastcgi-close req)))
              (let-values (((status headers body)
                            (handler (fastcgi-request-params req)
                                     (fastcgi-request-stdin req))))
                (fastcgi-respond req status headers body)
                (fastcgi-close req))))
          (loop)))))

  ) ;; end library
