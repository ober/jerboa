#!chezscheme
;;; :std/os/fdio -- File descriptor I/O operations via POSIX read(2)/write(2)

(library (std os fdio)
  (export fdread fdwrite write-subu8vector
          fdopen-input-port fdopen-output-port fdclose)

  (import (chezscheme))

  ;; fdread: read count bytes from fd, returns bytevector
  (define (fdread fd count)
    (let* ((buf (make-bytevector count))
           (n ((foreign-procedure "read" (int u8* unsigned-int) int) fd buf count)))
      (if (> n 0)
        (if (= n count) buf
          (let ((result (make-bytevector n)))
            (bytevector-copy! buf 0 result 0 n)
            result))
        (make-bytevector 0))))

  ;; fdwrite: write bytevector to fd, returns bytes written
  (define (fdwrite fd bv)
    ((foreign-procedure "write" (int u8* unsigned-int) int) fd bv (bytevector-length bv)))

  ;; write-subu8vector: write a slice of a bytevector to a port
  (define (write-subu8vector bv start end . port-opt)
    (let ((port (if (pair? port-opt) (car port-opt) (current-output-port))))
      (if (binary-port? port)
        (put-bytevector port bv start (- end start))
        ;; Textual port: convert bytevector slice to string
        (let ((sub (if (and (= start 0) (= end (bytevector-length bv)))
                     bv
                     (let ((r (make-bytevector (- end start))))
                       (bytevector-copy! bv start r 0 (- end start))
                       r))))
          (display (utf8->string sub) port)))))

  ;; fdopen-input-port: open input port from file descriptor
  (define (fdopen-input-port fd . rest)
    (open-fd-input-port fd
      (buffer-mode block)
      (if (pair? rest) (car rest) (native-transcoder))))

  ;; fdopen-output-port: open output port from file descriptor
  (define (fdopen-output-port fd . rest)
    (open-fd-output-port fd
      (buffer-mode block)
      (if (pair? rest) (car rest) (native-transcoder))))

  ;; fdclose: close a raw file descriptor
  (define fdclose
    (foreign-procedure "close" (int) int))

  ) ;; end library
