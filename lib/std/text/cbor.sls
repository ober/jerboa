#!chezscheme
;;; (std text cbor) — CBOR encoder/decoder (RFC 8949)
;;;
;;; Major types:
;;;   0 = unsigned integer
;;;   1 = negative integer
;;;   2 = byte string
;;;   3 = text string
;;;   4 = array → list
;;;   5 = map → hashtable
;;;   6 = tag (read but tag number discarded, inner value returned)
;;;   7 = simple/float (#f, #t, null→'null, float)

(library (std text cbor)
  (export cbor-encode cbor-decode
          cbor-read cbor-write)
  (import (chezscheme))

  ;; --- Encoder ---

  (define (cbor-encode val)
    (let-values ([(port extract) (open-bytevector-output-port)])
      (cbor-write val port)
      (extract)))

  (define (cbor-write val port)
    (cond
      [(eq? val #f)   (put-u8 port #xf4)]  ;; false
      [(eq? val #t)   (put-u8 port #xf5)]  ;; true
      [(eq? val 'null) (put-u8 port #xf6)] ;; null
      [(flonum? val)  (write-float port val)]
      [(and (integer? val) (exact? val) (>= val 0))
       (write-head port 0 val)]
      [(and (integer? val) (exact? val) (< val 0))
       (write-head port 1 (- (- val) 1))]
      [(string? val)
       (let ([bv (string->utf8 val)])
         (write-head port 3 (bytevector-length bv))
         (put-bytevector port bv))]
      [(bytevector? val)
       (write-head port 2 (bytevector-length val))
       (put-bytevector port val)]
      [(list? val)
       (write-head port 4 (length val))
       (for-each (lambda (v) (cbor-write v port)) val)]
      [(hashtable? val)
       (let ([keys (vector->list (hashtable-keys val))])
         (write-head port 5 (length keys))
         (for-each (lambda (k)
                     (cbor-write k port)
                     (cbor-write (hashtable-ref val k #f) port))
                   keys))]
      [else (error 'cbor-write "unsupported type" val)]))

  (define (write-head port major val)
    (let ([hi (bitwise-arithmetic-shift-left major 5)])
      (cond
        [(<= val 23)
         (put-u8 port (bitwise-ior hi val))]
        [(<= val #xff)
         (put-u8 port (bitwise-ior hi 24))
         (put-u8 port val)]
        [(<= val #xffff)
         (put-u8 port (bitwise-ior hi 25))
         (put-be port val 2)]
        [(<= val #xffffffff)
         (put-u8 port (bitwise-ior hi 26))
         (put-be port val 4)]
        [else
         (put-u8 port (bitwise-ior hi 27))
         (put-be port val 8)])))

  (define (put-be port val nbytes)
    (do ([i (- nbytes 1) (- i 1)])
        ((< i 0))
      (put-u8 port (bitwise-and
                     (bitwise-arithmetic-shift-right val (* i 8))
                     #xff))))

  (define (write-float port val)
    (put-u8 port #xfb)  ;; float64
    (let ([bv (make-bytevector 8)])
      (bytevector-ieee-double-set! bv 0 val (endianness big))
      (put-bytevector port bv)))

  ;; --- Decoder ---

  (define (cbor-decode bv)
    (let ([port (open-bytevector-input-port bv)])
      (cbor-read port)))

  (define (cbor-read port)
    (let* ([b (get-u8 port)]
           [_ (when (eof-object? b) (error 'cbor-read "unexpected EOF"))]
           [major (bitwise-arithmetic-shift-right b 5)]
           [info  (bitwise-and b #x1f)])
      (case major
        [(0) (read-arg port info)]             ;; unsigned int
        [(1) (- -1 (read-arg port info))]      ;; negative int
        [(2) (read-bytes port info)]           ;; byte string
        [(3) (utf8->string (read-bytes port info))] ;; text string
        [(4) (read-array port info)]           ;; array
        [(5) (read-map port info)]             ;; map
        [(6) ;; tag — read tag number then inner value
         (read-arg port info)  ;; discard tag number
         (cbor-read port)]
        [(7) (read-simple port info)]          ;; simple/float
        [else (error 'cbor-read "unknown major type" major)])))

  (define (read-arg port info)
    (cond
      [(<= info 23) info]
      [(= info 24) (get-u8* port)]
      [(= info 25) (read-uint port 2)]
      [(= info 26) (read-uint port 4)]
      [(= info 27) (read-uint port 8)]
      [else (error 'cbor-read "invalid additional info" info)]))

  (define (get-u8* port)
    (let ([b (get-u8 port)])
      (when (eof-object? b) (error 'cbor-read "unexpected EOF"))
      b))

  (define (read-uint port n)
    (do ([i 0 (+ i 1)]
         [val 0 (+ (bitwise-arithmetic-shift-left val 8) (get-u8* port))])
        ((= i n) val)))

  (define (read-bytes port info)
    (let* ([n (read-arg port info)]
           [bv (get-bytevector-n port n)])
      (when (or (eof-object? bv) (< (bytevector-length bv) n))
        (error 'cbor-read "unexpected EOF in bytes"))
      bv))

  (define (read-array port info)
    (let ([n (read-arg port info)])
      (do ([i 0 (+ i 1)]
           [acc '() (cons (cbor-read port) acc)])
          ((= i n) (reverse acc)))))

  (define (read-map port info)
    (let ([n (read-arg port info)]
          [ht (make-hashtable equal-hash equal?)])
      (do ([i 0 (+ i 1)])
          ((= i n) ht)
        (let* ([k (cbor-read port)]
               [v (cbor-read port)])
          (hashtable-set! ht k v)))))

  (define (read-simple port info)
    (cond
      [(= info 20) #f]     ;; false
      [(= info 21) #t]     ;; true
      [(= info 22) 'null]  ;; null
      [(= info 23) 'null]  ;; undefined → null
      [(= info 25)         ;; float16 — decode as float64
       (let* ([bv (get-bytevector-n port 2)]
              [bits (+ (bitwise-arithmetic-shift-left (bytevector-u8-ref bv 0) 8)
                       (bytevector-u8-ref bv 1))]
              [sign (if (> (bitwise-and bits #x8000) 0) -1.0 1.0)]
              [exp  (bitwise-and (bitwise-arithmetic-shift-right bits 10) #x1f)]
              [mant (bitwise-and bits #x3ff)])
         (cond
           [(= exp 0)
            (if (= mant 0) (* sign 0.0)
                (* sign (expt 2.0 -14) (/ mant 1024.0)))]
           [(= exp 31)
            (if (= mant 0) (* sign +inf.0) +nan.0)]
           [else (* sign (expt 2.0 (- exp 15)) (+ 1.0 (/ mant 1024.0)))]))]
      [(= info 26)         ;; float32
       (let ([bv (get-bytevector-n port 4)])
         (bytevector-ieee-single-ref bv 0 (endianness big)))]
      [(= info 27)         ;; float64
       (let ([bv (get-bytevector-n port 8)])
         (bytevector-ieee-double-ref bv 0 (endianness big)))]
      [else (error 'cbor-read "unknown simple value" info)]))

  ) ;; end library
