#!chezscheme
;;; (std text msgpack) — MessagePack serialization (msgpack.org spec)
;;;
;;; Type mappings:
;;;   nil           → (void)
;;;   boolean       → #t / #f
;;;   integers      → exact integers (auto-compact encoding)
;;;   float32/64    → flonums
;;;   str           → strings (UTF-8)
;;;   bin           → bytevectors
;;;   array         → vectors
;;;   map           → alists (list of (key . value) pairs)
;;;
;;; (msgpack-pack val)       → bytevector
;;; (msgpack-unpack bv)      → value
;;; (msgpack-pack-port val port)   → writes to binary output port
;;; (msgpack-unpack-port port)     → reads from binary input port

(library (std text msgpack)
  (export msgpack-pack msgpack-unpack msgpack-pack-port msgpack-unpack-port)
  (import (chezscheme))

  ;; ===== Encoder =====

  (define (msgpack-pack val)
    (let-values ([(port extract) (open-bytevector-output-port)])
      (msgpack-pack-port val port)
      (extract)))

  ;; Write a big-endian unsigned integer of n bytes
  (define (put-be port val n)
    (do ([i (- n 1) (- i 1)])
        ((< i 0))
      (put-u8 port (bitwise-and (bitwise-arithmetic-shift-right val (* i 8)) #xff))))

  (define (msgpack-pack-port val port)
    (cond
      ;; void → nil
      [(eq? val (void)) (put-u8 port #xc0)]
      ;; booleans
      [(eq? val #t) (put-u8 port #xc3)]
      [(eq? val #f) (put-u8 port #xc2)]
      ;; flonum
      [(flonum? val)
       (put-u8 port #xcb)
       (let ([bv (make-bytevector 8)])
         (bytevector-ieee-double-set! bv 0 val (endianness big))
         (put-bytevector port bv))]
      ;; exact integer
      [(and (integer? val) (exact? val))
       (write-int port val)]
      ;; string
      [(string? val) (write-str port val)]
      ;; bytevector → bin
      [(bytevector? val) (write-bin port val)]
      ;; vector → array
      [(vector? val) (write-array port val)]
      ;; pair that looks like an alist → map
      [(and (pair? val) (pair? (car val)) (alist? val))
       (write-map-alist port val)]
      ;; null list → nil
      [(null? val) (put-u8 port #xc0)]
      [else (error 'msgpack-pack-port "unsupported type" val)]))

  ;; Check if a value is an alist (list of pairs)
  (define (alist? val)
    (or (null? val)
        (and (pair? val)
             (pair? (car val))
             (alist? (cdr val)))))

  ;; Integer encoding — uses the most compact representation
  (define (write-int port n)
    (cond
      ;; positive fixint: 0xxxxxxx (0 to 127)
      [(and (>= n 0) (<= n 127))
       (put-u8 port n)]
      ;; negative fixint: 111xxxxx (-32 to -1)
      [(and (>= n -32) (< n 0))
       (put-u8 port (bitwise-and n #xff))]
      ;; uint 8
      [(and (>= n 0) (<= n #xff))
       (put-u8 port #xcc) (put-u8 port n)]
      ;; uint 16
      [(and (>= n 0) (<= n #xffff))
       (put-u8 port #xcd) (put-be port n 2)]
      ;; uint 32
      [(and (>= n 0) (<= n #xffffffff))
       (put-u8 port #xce) (put-be port n 4)]
      ;; uint 64
      [(and (>= n 0) (<= n #xffffffffffffffff))
       (put-u8 port #xcf) (put-be port n 8)]
      ;; int 8 (-128 to -33)
      [(and (>= n -128) (< n -32))
       (put-u8 port #xd0) (put-u8 port (bitwise-and n #xff))]
      ;; int 16 (-32768 to -129)
      [(and (>= n -32768) (< n -128))
       (put-u8 port #xd1) (put-be port (bitwise-and n #xffff) 2)]
      ;; int 32
      [(and (>= n (- (expt 2 31))) (< n -32768))
       (put-u8 port #xd2) (put-be port (bitwise-and n #xffffffff) 4)]
      ;; int 64
      [(and (>= n (- (expt 2 63))) (< n (- (expt 2 31))))
       (put-u8 port #xd3) (put-be port (bitwise-and n #xffffffffffffffff) 8)]
      [else (error 'msgpack-pack-port "integer out of range" n)]))

  ;; String encoding (UTF-8)
  (define (write-str port str)
    (let* ([bv (string->utf8 str)]
           [n (bytevector-length bv)])
      (cond
        [(<= n 31)    (put-u8 port (bitwise-ior #xa0 n))]
        [(<= n #xff)  (put-u8 port #xd9) (put-u8 port n)]
        [(<= n #xffff) (put-u8 port #xda) (put-be port n 2)]
        [else          (put-u8 port #xdb) (put-be port n 4)])
      (put-bytevector port bv)))

  ;; Binary encoding
  (define (write-bin port bv)
    (let ([n (bytevector-length bv)])
      (cond
        [(<= n #xff)    (put-u8 port #xc4) (put-u8 port n)]
        [(<= n #xffff)  (put-u8 port #xc5) (put-be port n 2)]
        [else            (put-u8 port #xc6) (put-be port n 4)])
      (put-bytevector port bv)))

  ;; Array encoding (from vector)
  (define (write-array port vec)
    (let ([n (vector-length vec)])
      (cond
        [(<= n 15)     (put-u8 port (bitwise-ior #x90 n))]
        [(<= n #xffff) (put-u8 port #xdc) (put-be port n 2)]
        [else           (put-u8 port #xdd) (put-be port n 4)])
      (do ([i 0 (+ i 1)])
          ((= i n))
        (msgpack-pack-port (vector-ref vec i) port))))

  ;; Map encoding (from alist)
  (define (write-map-alist port alist)
    (let ([n (length alist)])
      (cond
        [(<= n 15)     (put-u8 port (bitwise-ior #x80 n))]
        [(<= n #xffff) (put-u8 port #xde) (put-be port n 2)]
        [else           (put-u8 port #xdf) (put-be port n 4)])
      (for-each
        (lambda (pair)
          (msgpack-pack-port (car pair) port)
          (msgpack-pack-port (cdr pair) port))
        alist)))

  ;; ===== Decoder =====

  (define (msgpack-unpack bv)
    (msgpack-unpack-port (open-bytevector-input-port bv)))

  ;; Read exactly n bytes, error on short read
  (define (get-bv port n)
    (let ([bv (get-bytevector-n port n)])
      (when (or (eof-object? bv) (< (bytevector-length bv) n))
        (error 'msgpack-unpack-port "unexpected EOF"))
      bv))

  ;; Read big-endian unsigned integer of n bytes
  (define (read-uint port n)
    (let ([bv (get-bv port n)])
      (do ([i 0 (+ i 1)]
           [v 0 (+ (bitwise-arithmetic-shift-left v 8)
                    (bytevector-u8-ref bv i))])
          ((= i n) v))))

  ;; Read big-endian signed integer of n bytes (two's complement)
  (define (read-sint port n)
    (let ([u (read-uint port n)])
      (if (>= u (expt 2 (- (* n 8) 1)))
          (- u (expt 2 (* n 8)))
          u)))

  ;; Read n bytes as UTF-8 string
  (define (read-str port n)
    (utf8->string (get-bv port n)))

  ;; Read n elements as a vector
  (define (read-array port n)
    (let ([vec (make-vector n)])
      (do ([i 0 (+ i 1)])
          ((= i n) vec)
        (vector-set! vec i (msgpack-unpack-port port)))))

  ;; Read n key-value pairs as an alist
  (define (read-map port n)
    (let loop ([i 0] [acc '()])
      (if (= i n)
          (reverse acc)
          (let* ([k (msgpack-unpack-port port)]
                 [v (msgpack-unpack-port port)])
            (loop (+ i 1) (cons (cons k v) acc))))))

  (define (msgpack-unpack-port port)
    (let ([b (get-u8 port)])
      (when (eof-object? b)
        (error 'msgpack-unpack-port "unexpected EOF"))
      (cond
        ;; positive fixint: 0xxxxxxx
        [(<= b #x7f) b]
        ;; fixmap: 1000xxxx
        [(= (bitwise-and b #xf0) #x80)
         (read-map port (bitwise-and b #x0f))]
        ;; fixarray: 1001xxxx
        [(= (bitwise-and b #xf0) #x90)
         (read-array port (bitwise-and b #x0f))]
        ;; fixstr: 101xxxxx
        [(= (bitwise-and b #xe0) #xa0)
         (read-str port (bitwise-and b #x1f))]
        ;; nil
        [(= b #xc0) (void)]
        ;; (never used) #xc1
        ;; false
        [(= b #xc2) #f]
        ;; true
        [(= b #xc3) #t]
        ;; bin 8/16/32
        [(= b #xc4) (get-bv port (read-uint port 1))]
        [(= b #xc5) (get-bv port (read-uint port 2))]
        [(= b #xc6) (get-bv port (read-uint port 4))]
        ;; ext 8/16/32 — read and discard type byte, return data as bytevector
        [(= b #xc7) (let* ([n (read-uint port 1)] [_type (get-u8 port)]) (get-bv port n))]
        [(= b #xc8) (let* ([n (read-uint port 2)] [_type (get-u8 port)]) (get-bv port n))]
        [(= b #xc9) (let* ([n (read-uint port 4)] [_type (get-u8 port)]) (get-bv port n))]
        ;; float 32
        [(= b #xca)
         (let ([bv (get-bv port 4)])
           (bytevector-ieee-single-ref bv 0 (endianness big)))]
        ;; float 64
        [(= b #xcb)
         (let ([bv (get-bv port 8)])
           (bytevector-ieee-double-ref bv 0 (endianness big)))]
        ;; uint 8/16/32/64
        [(= b #xcc) (read-uint port 1)]
        [(= b #xcd) (read-uint port 2)]
        [(= b #xce) (read-uint port 4)]
        [(= b #xcf) (read-uint port 8)]
        ;; int 8/16/32/64
        [(= b #xd0) (read-sint port 1)]
        [(= b #xd1) (read-sint port 2)]
        [(= b #xd2) (read-sint port 4)]
        [(= b #xd3) (read-sint port 8)]
        ;; fixext 1/2/4/8/16 — read type byte + data
        [(= b #xd4) (get-u8 port) (get-bv port 1)]
        [(= b #xd5) (get-u8 port) (get-bv port 2)]
        [(= b #xd6) (get-u8 port) (get-bv port 4)]
        [(= b #xd7) (get-u8 port) (get-bv port 8)]
        [(= b #xd8) (get-u8 port) (get-bv port 16)]
        ;; str 8/16/32
        [(= b #xd9) (read-str port (read-uint port 1))]
        [(= b #xda) (read-str port (read-uint port 2))]
        [(= b #xdb) (read-str port (read-uint port 4))]
        ;; array 16/32
        [(= b #xdc) (read-array port (read-uint port 2))]
        [(= b #xdd) (read-array port (read-uint port 4))]
        ;; map 16/32
        [(= b #xde) (read-map port (read-uint port 2))]
        [(= b #xdf) (read-map port (read-uint port 4))]
        ;; negative fixint: 111xxxxx
        [(>= b #xe0) (- b 256)]
        [else (error 'msgpack-unpack-port "unknown format byte" b)])))

) ;; end library
