#!chezscheme
;;; (std crypto digest) — hex digest helpers
;;;
;;; Local override of upstream jerboa's (std crypto digest), which references
;;; Chez core prims `sha1-bytevector` and `sha256-bytevector` introduced in
;;; Round 12 Phase 67. Stock Chez Scheme 10.3 doesn't ship them, so this
;;; copy delegates to (std crypto native-rust) — the Rust ring-backed
;;; bindings already used elsewhere in jerboa-shell — for SHA-1/2 family
;;; digests. MD5 and SHA-224 still shell out to `openssl dgst` (no Rust
;;; binding for those).

(library (std crypto digest)
  (export
    md5 sha1 sha224 sha256 sha384 sha512
    digest->hex-string digest->u8vector)

  (import (chezscheme)
          (std crypto native-rust))

  (define hex-chars "0123456789abcdef")

  (define (bv->hex bv)
    (let* ([n (bytevector-length bv)]
           [out (make-string (fx* 2 n))])
      (let loop ([i 0])
        (when (fx< i n)
          (let ([b (bytevector-u8-ref bv i)])
            (string-set! out (fx* 2 i)
              (string-ref hex-chars (fxarithmetic-shift-right b 4)))
            (string-set! out (fx+ (fx* 2 i) 1)
              (string-ref hex-chars (fxand b #xf))))
          (loop (fx+ i 1))))
      out))

  (define (->bv data)
    (if (bytevector? data) data (string->utf8 data)))

  (define (compute-digest-openssl algo-name data)
    ;; Stdin pipe — no temp files, no user input in command string.
    (let-values ([(to-stdin from-stdout from-stderr pid)
                  (open-process-ports
                    (string-append "openssl dgst -" algo-name " -hex")
                    (buffer-mode block)
                    #f)])
      (put-bytevector to-stdin (->bv data))
      (close-port to-stdin)
      (let* ([stdout-transcoded (transcoded-port from-stdout (native-transcoder))]
             [output (get-string-all stdout-transcoded)])
        (close-port stdout-transcoded)
        (close-port from-stderr)
        (let ([eq-pos (let lp ([i 0])
                        (cond
                          [(>= i (string-length output)) #f]
                          [(char=? (string-ref output i) #\=) i]
                          [else (lp (+ i 1))]))])
          (if eq-pos
            (string-trim (substring output (+ eq-pos 1) (string-length output)))
            (string-trim output))))))

  (define (string-trim str)
    (let* ([len (string-length str)]
           [start (let lp ([i 0])
                    (if (or (>= i len) (not (char-whitespace? (string-ref str i))))
                      i (lp (+ i 1))))]
           [end (let lp ([i (- len 1)])
                  (if (or (< i start) (not (char-whitespace? (string-ref str i))))
                    (+ i 1) (lp (- i 1))))])
      (substring str start end)))

  (define (hex-string->u8vector str)
    (let* ([len (string-length str)]
           [out-len (quotient len 2)]
           [result (make-bytevector out-len)])
      (do ([i 0 (+ i 2)]
           [j 0 (+ j 1)])
          ((>= i len) result)
        (let ([hi (hex-char->int (string-ref str i))]
              [lo (hex-char->int (string-ref str (+ i 1)))])
          (bytevector-u8-set! result j
            (bitwise-ior (bitwise-arithmetic-shift-left hi 4) lo))))))

  (define (hex-char->int c)
    (cond
      [(char<=? #\0 c #\9) (- (char->integer c) (char->integer #\0))]
      [(char<=? #\a c #\f) (+ 10 (- (char->integer c) (char->integer #\a)))]
      [(char<=? #\A c #\F) (+ 10 (- (char->integer c) (char->integer #\A)))]
      [else 0]))

  ;; SHA family via Rust ring bindings (no Chez prim, no shell-out).
  (define (sha1   data) (bv->hex (rust-sha1   (->bv data))))
  (define (sha256 data) (bv->hex (rust-sha256 (->bv data))))
  (define (sha384 data) (bv->hex (rust-sha384 (->bv data))))
  (define (sha512 data) (bv->hex (rust-sha512 (->bv data))))

  ;; MD5 and SHA-224 still shell out (no Rust binding).
  (define (md5    data) (compute-digest-openssl "md5"    data))
  (define (sha224 data) (compute-digest-openssl "sha224" data))

  (define (digest->hex-string digest-result) digest-result)
  (define (digest->u8vector digest-result)
    (hex-string->u8vector digest-result))

  )
