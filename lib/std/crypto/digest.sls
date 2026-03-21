#!chezscheme
;;; :std/crypto/digest -- Cryptographic hash functions via openssl CLI
;;;
;;; HARDENED: Data piped via stdin — no temp files, no command injection.
;;; Command string contains only hardcoded algorithm names.

(library (std crypto digest)
  (export
    md5 sha1 sha224 sha256 sha384 sha512
    digest->hex-string digest->u8vector)

  (import (chezscheme))

  (define (compute-digest algo data)
    ;; data can be string or bytevector
    (let* ([input (if (bytevector? data) data (string->utf8 data))]
           [algo-name (case algo
                        [(md5) "md5"]
                        [(sha1) "sha1"]
                        [(sha224) "sha224"]
                        [(sha256) "sha256"]
                        [(sha384) "sha384"]
                        [(sha512) "sha512"]
                        [else (error 'compute-digest "unknown algorithm" algo)])])
      ;; Pipe data via stdin — no temp files, no user input in command string
      (let-values ([(to-stdin from-stdout from-stderr pid)
                    (open-process-ports
                      (string-append "openssl dgst -" algo-name " -hex")
                      (buffer-mode block)
                      #f)])  ;; #f = binary mode for stdin
        (put-bytevector to-stdin input)
        (close-port to-stdin)
        (let* ([stdout-transcoded (transcoded-port from-stdout (native-transcoder))]
               [output (get-string-all stdout-transcoded)])
          (close-port stdout-transcoded)
          (close-port from-stderr)
          ;; openssl output: "(stdin)= hexstring\n"
          (let ([eq-pos (let lp ([i 0])
                          (cond
                            [(>= i (string-length output)) #f]
                            [(char=? (string-ref output i) #\=) i]
                            [else (lp (+ i 1))]))])
            (if eq-pos
              (string-trim (substring output (+ eq-pos 1) (string-length output)))
              (string-trim output)))))))

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
  (define (md5 data) (compute-digest 'md5 data))
  (define (sha1 data) (compute-digest 'sha1 data))
  (define (sha224 data) (compute-digest 'sha224 data))
  (define (sha256 data) (compute-digest 'sha256 data))
  (define (sha384 data) (compute-digest 'sha384 data))
  (define (sha512 data) (compute-digest 'sha512 data))

  (define (digest->hex-string digest-result)
    digest-result)  ;; already a hex string

  (define (digest->u8vector digest-result)
    (hex-string->u8vector digest-result))

  ) ;; end library
