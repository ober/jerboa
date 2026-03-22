#!chezscheme
;;; (std text msgpack) — MessagePack encoder/decoder
;;; nil→#f, bool, int, float64, str, bin→bytevector, array→list, map→hashtable

(library (std text msgpack)
  (export msgpack-encode msgpack-decode msgpack-read msgpack-write)
  (import (chezscheme))

  ;; --- Encoder ---
  (define (msgpack-encode val)
    (let-values ([(p get) (open-bytevector-output-port)])
      (msgpack-write val p) (get)))

  (define (put-be port val n)
    (do ([i (- n 1) (- i 1)]) ((< i 0))
      (put-u8 port (bitwise-and (bitwise-arithmetic-shift-right val (* i 8)) #xff))))

  (define (msgpack-write val port)
    (cond
      [(eq? val 'null) (put-u8 port #xc0)]
      [(eq? val #t) (put-u8 port #xc3)]
      [(eq? val #f) (put-u8 port #xc2)]
      [(flonum? val)
       (put-u8 port #xcb)
       (let ([bv (make-bytevector 8)])
         (bytevector-ieee-double-set! bv 0 val (endianness big))
         (put-bytevector port bv))]
      [(and (integer? val) (exact? val)) (write-int port val)]
      [(string? val) (write-str port val)]
      [(bytevector? val) (write-bin port val)]
      [(list? val) (write-array port val)]
      [(hashtable? val) (write-map port val)]
      [else (error 'msgpack-write "unsupported type" val)]))

  (define (write-int port n)
    (cond
      [(and (>= n 0) (<= n 127)) (put-u8 port n)]
      [(and (>= n -32) (< n 0)) (put-u8 port (bitwise-and n #xff))]
      [(and (>= n 0) (<= n #xff)) (put-u8 port #xcc) (put-u8 port n)]
      [(and (>= n 0) (<= n #xffff)) (put-u8 port #xcd) (put-be port n 2)]
      [(and (>= n 0) (<= n #xffffffff)) (put-u8 port #xce) (put-be port n 4)]
      [(and (>= n 0) (<= n #xffffffffffffffff)) (put-u8 port #xcf) (put-be port n 8)]
      [(and (>= n -128) (< n 0)) (put-u8 port #xd0) (put-u8 port (bitwise-and n #xff))]
      [(and (>= n -32768) (< n 0))
       (put-u8 port #xd1) (put-be port (bitwise-and n #xffff) 2)]
      [(>= n (- (expt 2 31)))
       (put-u8 port #xd2) (put-be port (bitwise-and n #xffffffff) 4)]
      [(>= n (- (expt 2 63)))
       (put-u8 port #xd3) (put-be port (bitwise-and n #xffffffffffffffff) 8)]
      [else (error 'msgpack-write "integer out of range" n)]))

  (define (write-str port str)
    (let* ([bv (string->utf8 str)] [n (bytevector-length bv)])
      (cond [(<= n 31) (put-u8 port (bitwise-ior #xa0 n))]
            [(<= n #xff) (put-u8 port #xd9) (put-u8 port n)]
            [(<= n #xffff) (put-u8 port #xda) (put-be port n 2)]
            [else (put-u8 port #xdb) (put-be port n 4)])
      (put-bytevector port bv)))

  (define (write-bin port bv)
    (let ([n (bytevector-length bv)])
      (cond [(<= n #xff) (put-u8 port #xc4) (put-u8 port n)]
            [(<= n #xffff) (put-u8 port #xc5) (put-be port n 2)]
            [else (put-u8 port #xc6) (put-be port n 4)])
      (put-bytevector port bv)))

  (define (write-array port lst)
    (let ([n (length lst)])
      (cond [(<= n 15) (put-u8 port (bitwise-ior #x90 n))]
            [(<= n #xffff) (put-u8 port #xdc) (put-be port n 2)]
            [else (put-u8 port #xdd) (put-be port n 4)])
      (for-each (lambda (v) (msgpack-write v port)) lst)))

  (define (write-map port ht)
    (let ([keys (vector->list (hashtable-keys ht))])
      (let ([n (length keys)])
        (cond [(<= n 15) (put-u8 port (bitwise-ior #x80 n))]
              [(<= n #xffff) (put-u8 port #xde) (put-be port n 2)]
              [else (put-u8 port #xdf) (put-be port n 4)])
        (for-each (lambda (k) (msgpack-write k port)
                    (msgpack-write (hashtable-ref ht k #f) port)) keys))))

  ;; --- Decoder ---
  (define (msgpack-decode bv) (msgpack-read (open-bytevector-input-port bv)))

  (define (get-bv port n)
    (let ([bv (get-bytevector-n port n)])
      (when (or (eof-object? bv) (< (bytevector-length bv) n))
        (error 'msgpack-read "unexpected EOF"))
      bv))

  (define (read-uint port n)
    (let ([bv (get-bv port n)])
      (do ([i 0 (+ i 1)]
           [v 0 (+ (bitwise-arithmetic-shift-left v 8) (bytevector-u8-ref bv i))])
          ((= i n) v))))

  (define (read-sint port n)
    (let ([u (read-uint port n)])
      (if (>= u (expt 2 (- (* n 8) 1))) (- u (expt 2 (* n 8))) u)))

  (define (read-str port n) (utf8->string (get-bv port n)))

  (define (read-array port n)
    (do ([i 0 (+ i 1)] [acc '() (cons (msgpack-read port) acc)])
        ((= i n) (reverse acc))))

  (define (read-map port n)
    (let ([ht (make-hashtable equal-hash equal?)])
      (do ([i 0 (+ i 1)]) ((= i n) ht)
        (let* ([k (msgpack-read port)] [v (msgpack-read port)])
          (hashtable-set! ht k v)))))

  (define (msgpack-read port)
    (let ([b (get-u8 port)])
      (when (eof-object? b) (error 'msgpack-read "unexpected EOF"))
      (cond
        [(<= b #x7f) b]                                          ;; positive fixint
        [(= (bitwise-and b #xf0) #x80) (read-map port (bitwise-and b #x0f))]
        [(= (bitwise-and b #xf0) #x90) (read-array port (bitwise-and b #x0f))]
        [(= (bitwise-and b #xe0) #xa0) (read-str port (bitwise-and b #x1f))]
        [(= b #xc0) #f]                                          ;; nil
        [(= b #xc2) #f] [(= b #xc3) #t]                          ;; bool
        [(= b #xc4) (get-bv port (read-uint port 1))]            ;; bin 8
        [(= b #xc5) (get-bv port (read-uint port 2))]            ;; bin 16
        [(= b #xc6) (get-bv port (read-uint port 4))]            ;; bin 32
        [(= b #xca) (let ([bv (get-bv port 4)])                   ;; float 32
                      (bytevector-ieee-single-ref bv 0 (endianness big)))]
        [(= b #xcb) (let ([bv (get-bv port 8)])                   ;; float 64
                      (bytevector-ieee-double-ref bv 0 (endianness big)))]
        [(= b #xcc) (read-uint port 1)] [(= b #xcd) (read-uint port 2)]
        [(= b #xce) (read-uint port 4)] [(= b #xcf) (read-uint port 8)]
        [(= b #xd0) (read-sint port 1)] [(= b #xd1) (read-sint port 2)]
        [(= b #xd2) (read-sint port 4)] [(= b #xd3) (read-sint port 8)]
        [(= b #xd9) (read-str port (read-uint port 1))]
        [(= b #xda) (read-str port (read-uint port 2))]
        [(= b #xdb) (read-str port (read-uint port 4))]
        [(= b #xdc) (read-array port (read-uint port 2))]
        [(= b #xdd) (read-array port (read-uint port 4))]
        [(= b #xde) (read-map port (read-uint port 2))]
        [(= b #xdf) (read-map port (read-uint port 4))]
        [(>= b #xe0) (- b 256)]                                  ;; negative fixint
        [else (error 'msgpack-read "unknown format byte" b)])))

  ) ;; end library
