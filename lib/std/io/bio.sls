#!chezscheme
;;; (std io bio) — Buffered I/O with lookahead
;;;
;;; Wraps binary ports with user-space bytevector buffers for efficient
;;; byte-at-a-time reading and writing, plus peek and unread support.

(library (std io bio)
  (export
    make-buffered-input make-buffered-output
    buffered-input? buffered-output?
    buffered-read-byte buffered-read-char
    buffered-read-line buffered-read-bytes
    buffered-peek-byte buffered-peek-char
    buffered-unread-byte
    buffered-write-byte buffered-write-bytes
    buffered-write-string buffered-write-line
    buffered-flush buffered-close)

  (import (chezscheme))

  ;; ========== Buffered input ==========

  (define-record-type buffered-input
    (fields
      (immutable port bi-port)                     ; underlying binary input port
      (mutable buf    bi-buf    set-bi-buf!)        ; bytevector buffer
      (mutable pos    bi-pos    set-bi-pos!)        ; current read position in buffer
      (mutable limit  bi-limit  set-bi-limit!)      ; number of valid bytes in buffer
      (mutable unread bi-unread set-bi-unread!))    ; pushed-back byte or #f
    (protocol
      (lambda (new)
        (lambda (port . rest)
          (let ([size (if (pair? rest) (car rest) 8192)])
            (unless (and (binary-port? port) (input-port? port))
              (error 'make-buffered-input "expected binary input port" port))
            (new port (make-bytevector size) 0 0 #f))))))

  ;; Refill the internal buffer from the underlying port.
  ;; Returns the number of bytes read (0 means EOF).
  (define (bi-refill! bi)
    (let* ([buf (bi-buf bi)]
           [n (get-bytevector-n! (bi-port bi) buf 0 (bytevector-length buf))])
      (cond
        [(eof-object? n)
         (set-bi-pos! bi 0)
         (set-bi-limit! bi 0)
         0]
        [else
         (set-bi-pos! bi 0)
         (set-bi-limit! bi n)
         n])))

  (define (buffered-read-byte bi)
    ;; Check unread slot first
    (let ([u (bi-unread bi)])
      (cond
        [u
         (set-bi-unread! bi #f)
         u]
        [(< (bi-pos bi) (bi-limit bi))
         (let ([b (bytevector-u8-ref (bi-buf bi) (bi-pos bi))])
           (set-bi-pos! bi (+ (bi-pos bi) 1))
           b)]
        [else
         (let ([n (bi-refill! bi)])
           (if (zero? n)
               (eof-object)
               (let ([b (bytevector-u8-ref (bi-buf bi) 0)])
                 (set-bi-pos! bi 1)
                 b)))])))

  (define (buffered-peek-byte bi)
    (let ([u (bi-unread bi)])
      (cond
        [u u]
        [(< (bi-pos bi) (bi-limit bi))
         (bytevector-u8-ref (bi-buf bi) (bi-pos bi))]
        [else
         (let ([n (bi-refill! bi)])
           (if (zero? n)
               (eof-object)
               (bytevector-u8-ref (bi-buf bi) 0)))])))

  (define (buffered-unread-byte bi byte)
    (when (bi-unread bi)
      (error 'buffered-unread-byte "already have an unread byte"))
    (set-bi-unread! bi byte))

  (define (buffered-read-char bi)
    ;; Read a single UTF-8 character. For simplicity, handles ASCII directly
    ;; and decodes multi-byte sequences.
    (let ([b (buffered-read-byte bi)])
      (cond
        [(eof-object? b) (eof-object)]
        [(< b #x80) (integer->char b)]
        [else
         ;; Multi-byte UTF-8
         (let* ([len (cond
                       [(= (bitwise-and b #xE0) #xC0) 2]
                       [(= (bitwise-and b #xF0) #xE0) 3]
                       [(= (bitwise-and b #xF8) #xF0) 4]
                       [else (error 'buffered-read-char
                                    "invalid UTF-8 lead byte" b)])]
                [cp (bitwise-and b (case len
                                     [(2) #x1F] [(3) #x0F] [(4) #x07]))])
           (do ([i 1 (+ i 1)]
                [cp cp (let ([cb (buffered-read-byte bi)])
                         (when (eof-object? cb)
                           (error 'buffered-read-char
                                  "unexpected EOF in UTF-8 sequence"))
                         (bitwise-ior (bitwise-arithmetic-shift-left cp 6)
                                      (bitwise-and cb #x3F)))])
             ((= i len) (integer->char cp))))])))

  (define (buffered-peek-char bi)
    (let ([b (buffered-peek-byte bi)])
      (cond
        [(eof-object? b) (eof-object)]
        [(< b #x80) (integer->char b)]
        [else
         ;; For peek, read the char then unread the bytes.
         ;; Simpler: read char, then push back. But we can only unread 1 byte.
         ;; Instead, just decode without consuming by saving/restoring state.
         (let ([saved-pos (bi-pos bi)]
               [saved-limit (bi-limit bi)]
               [saved-unread (bi-unread bi)])
           (let ([ch (buffered-read-char bi)])
             ;; Restore state
             (set-bi-pos! bi saved-pos)
             (set-bi-limit! bi saved-limit)
             (set-bi-unread! bi saved-unread)
             ch))])))

  (define (buffered-read-bytes bi count)
    ;; Read exactly count bytes, returning a bytevector.
    ;; Returns shorter bytevector or eof-object if EOF before any bytes.
    (let ([result (make-bytevector count)]
          [got 0])
      ;; First, consume unread byte if any
      (when (and (bi-unread bi) (< got count))
        (bytevector-u8-set! result 0 (bi-unread bi))
        (set-bi-unread! bi #f)
        (set! got 1))
      ;; Then consume from buffer and refill as needed
      (let loop ()
        (when (< got count)
          (let ([avail (- (bi-limit bi) (bi-pos bi))])
            (cond
              [(> avail 0)
               (let ([take (min avail (- count got))])
                 (bytevector-copy! (bi-buf bi) (bi-pos bi) result got take)
                 (set-bi-pos! bi (+ (bi-pos bi) take))
                 (set! got (+ got take))
                 (loop))]
              [else
               (let ([n (bi-refill! bi)])
                 (unless (zero? n)
                   (loop)))]))))
      (cond
        [(zero? got) (eof-object)]
        [(= got count) result]
        [else
         (let ([short (make-bytevector got)])
           (bytevector-copy! result 0 short 0 got)
           short)])))

  (define (buffered-read-line bi)
    ;; Read until LF or CRLF, return string (without line ending).
    ;; Returns eof-object at EOF.
    (let loop ([chars '()])
      (let ([b (buffered-read-byte bi)])
        (cond
          [(eof-object? b)
           (if (null? chars)
               (eof-object)
               (list->string (reverse chars)))]
          [(= b 10) ; LF
           (list->string (reverse chars))]
          [(= b 13) ; CR — check for CRLF
           (let ([next (buffered-peek-byte bi)])
             (when (and (not (eof-object? next)) (= next 10))
               (buffered-read-byte bi))  ; consume the LF
             (list->string (reverse chars)))]
          [else
           (loop (cons (integer->char b) chars))]))))

  ;; ========== Buffered output ==========

  (define-record-type buffered-output
    (fields
      (immutable port bo-port)                   ; underlying binary output port
      (mutable buf  bo-buf  set-bo-buf!)          ; bytevector buffer
      (mutable pos  bo-pos  set-bo-pos!))         ; current write position in buffer
    (protocol
      (lambda (new)
        (lambda (port . rest)
          (let ([size (if (pair? rest) (car rest) 8192)])
            (unless (and (binary-port? port) (output-port? port))
              (error 'make-buffered-output "expected binary output port" port))
            (new port (make-bytevector size) 0))))))

  (define (buffered-flush bo)
    (let ([pos (bo-pos bo)])
      (when (> pos 0)
        (put-bytevector (bo-port bo) (bo-buf bo) 0 pos)
        (flush-output-port (bo-port bo))
        (set-bo-pos! bo 0))))

  (define (bo-ensure-space! bo count)
    ;; Flush if not enough room for count bytes.
    (when (> (+ (bo-pos bo) count) (bytevector-length (bo-buf bo)))
      (buffered-flush bo)))

  (define (buffered-write-byte bo byte)
    (bo-ensure-space! bo 1)
    (bytevector-u8-set! (bo-buf bo) (bo-pos bo) byte)
    (set-bo-pos! bo (+ (bo-pos bo) 1)))

  (define (buffered-write-bytes bo bv)
    (let ([len (bytevector-length bv)]
          [buf-size (bytevector-length (bo-buf bo))])
      (let loop ([offset 0])
        (when (< offset len)
          (let* ([remaining (- len offset)]
                 [space (- buf-size (bo-pos bo))]
                 [chunk (min remaining space)])
            (bytevector-copy! bv offset (bo-buf bo) (bo-pos bo) chunk)
            (set-bo-pos! bo (+ (bo-pos bo) chunk))
            (when (= (bo-pos bo) buf-size)
              (buffered-flush bo))
            (loop (+ offset chunk)))))))

  (define (buffered-write-string bo str)
    (buffered-write-bytes bo (string->utf8 str)))

  (define (buffered-write-line bo str)
    (buffered-write-string bo str)
    (buffered-write-byte bo 10))  ; LF

  (define (buffered-close bo/bi)
    (cond
      [(buffered-output? bo/bi)
       (buffered-flush bo/bi)
       (close-port (bo-port bo/bi))]
      [(buffered-input? bo/bi)
       (close-port (bi-port bo/bi))]
      [else
       (error 'buffered-close "expected buffered-input or buffered-output" bo/bi)]))

) ;; end library
