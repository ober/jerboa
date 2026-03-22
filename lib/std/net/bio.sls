#!chezscheme
;;; :std/net/bio -- Buffered network I/O
;;;
;;; Wraps input and output ports with bytevector buffers for efficient
;;; byte-at-a-time and line-oriented reading/writing.  Provides peek
;;; and unread for single-byte lookahead.

(library (std net bio)
  (export
    make-bio-input  bio-read-byte  bio-read-line
    bio-read-bytes  bio-peek-byte  bio-unread-byte
    make-bio-output bio-write-byte bio-write-bytes
    bio-write-string bio-flush bio-close)

  (import (chezscheme))

  ;; ========== Buffered Input ==========

  (define-record-type bio-in
    (fields
      (immutable port)          ;; underlying binary input port
      (immutable buf)           ;; bytevector buffer
      (mutable pos)             ;; next byte to read in buf
      (mutable limit)           ;; number of valid bytes in buf
      (mutable unread))         ;; #f or an unread byte (integer 0..255)
    (sealed #t))

  (define make-bio-input
    (case-lambda
      [(port) (make-bio-input port 8192)]
      [(port size)
       (unless (input-port? port)
         (error 'make-bio-input "expected input port" port))
       (make-bio-in port (make-bytevector size) 0 0 #f)]))

  ;; Refill the buffer from the underlying port.
  ;; Returns the number of bytes read (0 means EOF).
  (define (bio-refill! bio)
    (let* ([buf (bio-in-buf bio)]
           [n   (get-bytevector-some! (bio-in-port bio)
                                      buf 0 (bytevector-length buf))])
      (cond
        [(eof-object? n)
         (bio-in-pos-set! bio 0)
         (bio-in-limit-set! bio 0)
         0]
        [else
         (bio-in-pos-set! bio 0)
         (bio-in-limit-set! bio n)
         n])))

  (define (bio-read-byte bio)
    ;; Return the next byte as an integer, or eof-object.
    (let ([u (bio-in-unread bio)])
      (cond
        [u
         (bio-in-unread-set! bio #f)
         u]
        [(< (bio-in-pos bio) (bio-in-limit bio))
         (let ([b (bytevector-u8-ref (bio-in-buf bio) (bio-in-pos bio))])
           (bio-in-pos-set! bio (+ (bio-in-pos bio) 1))
           b)]
        [else
         (let ([n (bio-refill! bio)])
           (if (= n 0)
             (eof-object)
             (bio-read-byte bio)))])))

  (define (bio-peek-byte bio)
    ;; Peek at the next byte without consuming it.
    (let ([u (bio-in-unread bio)])
      (cond
        [u u]
        [(< (bio-in-pos bio) (bio-in-limit bio))
         (bytevector-u8-ref (bio-in-buf bio) (bio-in-pos bio))]
        [else
         (let ([n (bio-refill! bio)])
           (if (= n 0)
             (eof-object)
             (bytevector-u8-ref (bio-in-buf bio) 0)))])))

  (define (bio-unread-byte bio byte)
    ;; Push one byte back.  Only one level of unread is supported.
    (when (bio-in-unread bio)
      (error 'bio-unread-byte "already have an unread byte"))
    (bio-in-unread-set! bio byte))

  (define (bio-read-bytes bio count)
    ;; Read exactly COUNT bytes, returning a bytevector.
    ;; Returns a shorter bytevector or eof-object if the stream ends early.
    (let ([result (make-bytevector count)])
      (let loop ([got 0])
        (if (= got count)
          result
          (let ([b (bio-read-byte bio)])
            (if (eof-object? b)
              (if (= got 0)
                (eof-object)
                (let ([short (make-bytevector got)])
                  (bytevector-copy! result 0 short 0 got)
                  short))
              (begin
                (bytevector-u8-set! result got b)
                (loop (+ got 1)))))))))

  (define (bio-read-line bio)
    ;; Read bytes until LF (or CR LF).  Returns a string (without the
    ;; line ending) or eof-object at end of stream.
    (let loop ([acc '()])
      (let ([b (bio-read-byte bio)])
        (cond
          [(eof-object? b)
           (if (null? acc)
             (eof-object)
             (bytes->string (reverse acc)))]
          [(= b 10)  ;; LF
           (bytes->string (reverse acc))]
          [(= b 13)  ;; CR — consume following LF if present
           (let ([next (bio-peek-byte bio)])
             (when (and (not (eof-object? next)) (= next 10))
               (bio-read-byte bio)))
           (bytes->string (reverse acc))]
          [else
           (loop (cons b acc))]))))

  (define (bytes->string byte-list)
    ;; Convert a list of byte integers to a UTF-8 string.
    (let ([bv (u8-list->bytevector byte-list)])
      (utf8->string bv)))

  ;; ========== Buffered Output ==========

  (define-record-type bio-out
    (fields
      (immutable port)          ;; underlying binary output port
      (immutable buf)           ;; bytevector buffer
      (mutable pos))            ;; next write position in buf
    (sealed #t))

  (define make-bio-output
    (case-lambda
      [(port) (make-bio-output port 8192)]
      [(port size)
       (unless (output-port? port)
         (error 'make-bio-output "expected output port" port))
       (make-bio-out port (make-bytevector size) 0)]))

  (define (bio-flush bio)
    ;; Write all buffered bytes to the underlying port.
    (let ([pos (bio-out-pos bio)])
      (when (> pos 0)
        (put-bytevector (bio-out-port bio)
                        (bio-out-buf bio) 0 pos)
        (flush-output-port (bio-out-port bio))
        (bio-out-pos-set! bio 0))))

  (define (bio-write-byte bio byte)
    (let ([buf (bio-out-buf bio)]
          [pos (bio-out-pos bio)])
      (bytevector-u8-set! buf pos byte)
      (let ([new-pos (+ pos 1)])
        (bio-out-pos-set! bio new-pos)
        (when (= new-pos (bytevector-length buf))
          (bio-flush bio)))))

  (define (bio-write-bytes bio bv)
    ;; Write a bytevector.
    (let ([len (bytevector-length bv)])
      (let loop ([i 0])
        (when (< i len)
          (bio-write-byte bio (bytevector-u8-ref bv i))
          (loop (+ i 1))))))

  (define (bio-write-string bio str)
    ;; Write a string as UTF-8.
    (bio-write-bytes bio (string->utf8 str)))

  (define bio-close
    (case-lambda
      [(bio)
       (cond
         [(bio-in? bio)
          (close-port (bio-in-port bio))]
         [(bio-out? bio)
          (bio-flush bio)
          (close-port (bio-out-port bio))]
         [else (error 'bio-close "not a bio object" bio)])]
      [(bio-in bio-out)
       (bio-close bio-in)
       (bio-close bio-out)]))

  ) ;; end library
