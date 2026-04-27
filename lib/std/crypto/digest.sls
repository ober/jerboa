#!chezscheme
;;; :std/crypto/digest -- Cryptographic hash functions
;;;
;;; SHA-1 and SHA-256 use Chez core sha1-bytevector / sha256-bytevector
;;; (Phase 67, Round 12 — landed 2026-04-26 in ChezScheme).  No process
;;; spawn, no shell, no openssl dependency for those two.
;;;
;;; MD5, SHA-224, SHA-384, SHA-512 still shell out to `openssl dgst`
;;; with data piped via stdin (no temp files, no command injection).

(library (std crypto digest)
  (export
    md5 sha1 sha224 sha256 sha384 sha512
    digest->hex-string digest->u8vector)

  (import (chezscheme))

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

  ;; Public API: returns hex string
  (define (sha1 data)   (bv->hex (sha1-bytevector   (->bv data))))
  (define (sha256 data) (bv->hex (sha256-bytevector (->bv data))))

  (define (md5 data)    (compute-digest-openssl "md5"    data))
  (define (sha224 data) (compute-digest-openssl "sha224" data))
  (define (sha384 data) (compute-digest-openssl "sha384" data))
  (define (sha512 data) (compute-digest-openssl "sha512" data))

  (define (digest->hex-string digest-result) digest-result)
  (define (digest->u8vector digest-result)
    (hex-string->u8vector digest-result))

  )
