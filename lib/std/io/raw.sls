#!chezscheme
;;; (std io raw) — Raw byte I/O ports
;;;
;;; Track 26: Direct byte I/O that bypasses Chez's UTF-8 codec.
;;; Uses bytevectors as the natural currency for raw I/O.

(library (std io raw)
  (export
    fd-read-bytes
    fd-write-bytes
    fd-read-all
    fd->binary-input-port
    fd->binary-output-port
    fd->binary-input/output-port
    fd->textual-input-port
    fd->textual-output-port
    bytevector-concat)

  (import (chezscheme))

  ;; ========== Low-level FFI ==========

  (define c-read  (foreign-procedure "read" (int u8* size_t) ssize_t))
  (define c-write (foreign-procedure "write" (int u8* size_t) ssize_t))
  (define c-close (foreign-procedure "close" (int) int))

  ;; ========== Direct Byte I/O ==========

  (define (fd-read-bytes fd count)
    ;; Read up to count bytes from fd. Returns bytevector (may be shorter).
    ;; No codec, no intermediate C buffer.
    (let ([buf (make-bytevector count)])
      (let ([n (c-read fd buf count)])
        (cond
          [(< n 0) (error 'fd-read-bytes "read failed" fd)]
          [(= n 0) (make-bytevector 0)]
          [(= n count) buf]
          [else
           (let ([result (make-bytevector n)])
             (bytevector-copy! buf 0 result 0 n)
             result)]))))

  (define (fd-write-bytes fd bv . rest)
    ;; Write bytevector to fd. Optional start and count.
    ;; Returns number of bytes written.
    (let ([start (if (pair? rest) (car rest) 0)]
          [count (if (and (pair? rest) (pair? (cdr rest)))
                   (cadr rest)
                   (bytevector-length bv))])
      (if (= start 0)
        (let ([n (c-write fd bv count)])
          (if (< n 0)
            (error 'fd-write-bytes "write failed" fd)
            n))
        ;; Need to slice
        (let ([slice (make-bytevector count)])
          (bytevector-copy! bv start slice 0 count)
          (let ([n (c-write fd slice count)])
            (if (< n 0)
              (error 'fd-write-bytes "write failed" fd)
              n))))))

  (define (fd-read-all fd)
    ;; Read all bytes from fd until EOF. Returns bytevector.
    (let ([chunk-size 8192])
      (let lp ([chunks '()] [total 0])
        (let ([buf (make-bytevector chunk-size)])
          (let ([n (c-read fd buf chunk-size)])
            (cond
              [(< n 0) (error 'fd-read-all "read failed" fd)]
              [(= n 0)
               ;; EOF — concatenate chunks
               (if (null? chunks)
                 (make-bytevector 0)
                 (bytevector-concat (reverse chunks)))]
              [else
               (let ([chunk (if (= n chunk-size) buf
                              (let ([r (make-bytevector n)])
                                (bytevector-copy! buf 0 r 0 n)
                                r))])
                 (lp (cons chunk chunks) (+ total n)))]))))))

  ;; ========== Bytevector Utilities ==========

  (define (bytevector-concat bvs)
    ;; Concatenate a list of bytevectors
    (let ([total (fold-left + 0 (map bytevector-length bvs))])
      (let ([result (make-bytevector total)])
        (let lp ([bvs bvs] [offset 0])
          (if (null? bvs) result
            (let ([bv (car bvs)]
                  [len (bytevector-length (car bvs))])
              (bytevector-copy! bv 0 result offset len)
              (lp (cdr bvs) (+ offset len))))))))

  ;; ========== Binary Ports from FDs ==========

  (define (fd->binary-input-port fd . rest)
    ;; Create a binary input port backed by a raw fd.
    ;; Uses R6RS make-custom-binary-input-port.
    (let ([name (if (pair? rest) (car rest) (format "fd:~a" fd))]
          [buf-size 8192])
      (make-custom-binary-input-port
        name
        ;; read! procedure: (read! bv start count) -> n
        (lambda (bv start count)
          (if (= start 0)
            (let ([n (c-read fd bv count)])
              (if (< n 0) 0 n))
            ;; Need temp buffer if start != 0
            (let ([tmp (make-bytevector count)])
              (let ([n (c-read fd tmp count)])
                (when (> n 0)
                  (bytevector-copy! tmp 0 bv start n))
                (if (< n 0) 0 n)))))
        ;; get-position (not supported for raw fds)
        #f
        ;; set-position! (not supported for raw fds)
        #f
        ;; close
        (lambda () (c-close fd)))))

  (define (fd->binary-output-port fd . rest)
    ;; Create a binary output port backed by a raw fd.
    (let ([name (if (pair? rest) (car rest) (format "fd:~a" fd))])
      (make-custom-binary-output-port
        name
        ;; write! procedure: (write! bv start count) -> n
        (lambda (bv start count)
          (if (= start 0)
            (let ([n (c-write fd bv count)])
              (if (< n 0) 0 n))
            (let ([tmp (make-bytevector count)])
              (bytevector-copy! bv start tmp 0 count)
              (let ([n (c-write fd tmp count)])
                (if (< n 0) 0 n)))))
        ;; get-position
        #f
        ;; set-position!
        #f
        ;; close
        (lambda () (c-close fd)))))

  (define (fd->binary-input/output-port fd . rest)
    ;; Create a binary input/output port backed by a raw fd.
    (let ([name (if (pair? rest) (car rest) (format "fd:~a" fd))])
      (make-custom-binary-input/output-port
        name
        ;; read!
        (lambda (bv start count)
          (if (= start 0)
            (let ([n (c-read fd bv count)])
              (if (< n 0) 0 n))
            (let ([tmp (make-bytevector count)])
              (let ([n (c-read fd tmp count)])
                (when (> n 0)
                  (bytevector-copy! tmp 0 bv start n))
                (if (< n 0) 0 n)))))
        ;; write!
        (lambda (bv start count)
          (if (= start 0)
            (let ([n (c-write fd bv count)])
              (if (< n 0) 0 n))
            (let ([tmp (make-bytevector count)])
              (bytevector-copy! bv start tmp 0 count)
              (let ([n (c-write fd tmp count)])
                (if (< n 0) 0 n)))))
        ;; get-position
        #f
        ;; set-position!
        #f
        ;; close
        (lambda () (c-close fd)))))

  ;; ========== Textual Ports from FDs ==========

  (define (fd->textual-input-port fd . rest)
    ;; Create a textual input port with selectable codec.
    ;; Default: UTF-8. Use (latin-1-codec) for raw byte preservation.
    (let ([name (if (pair? rest) (car rest) (format "fd:~a" fd))]
          [codec (if (and (pair? rest) (pair? (cdr rest)))
                   (cadr rest)
                   (utf-8-codec))])
      (transcoded-port
        (fd->binary-input-port fd name)
        (make-transcoder codec))))

  (define (fd->textual-output-port fd . rest)
    (let ([name (if (pair? rest) (car rest) (format "fd:~a" fd))]
          [codec (if (and (pair? rest) (pair? (cdr rest)))
                   (cadr rest)
                   (utf-8-codec))])
      (transcoded-port
        (fd->binary-output-port fd name)
        (make-transcoder codec))))

  ) ;; end library
