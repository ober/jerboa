#!chezscheme
;;; :std/text/base64 — pure-Scheme RFC 4648 port
;;;
;;; Override for static jsh builds. The upstream (std text base64) is a
;;; thin wrapper over Chez core base64-encode/base64-decode (Round 12
;;; Phase 66). Some Chez builds — notably the ober/ChezScheme tree
;;; cloned inside jerboa21/jerboa — ship boot files that predate Phase
;;; 66, so the host scheme has the prims but the container scheme does
;;; not. Rather than chase boot-file regen across hosts, this file
;;; provides a self-contained implementation so the build works on any
;;; Chez >= 9.5 regardless of whether base64-encode is a core prim.

(library (std text base64)
  ;; Define under internal names (b64-encode, b64-decode) and rename on
  ;; export. This sidesteps both failure modes:
  ;;   - On host Chez where base64-encode is a builtin, defining it
  ;;     locally would error with "multiple definitions".
  ;;   - On container Chez where base64-encode does NOT exist, using
  ;;     `(except (chezscheme) base64-encode ...)` errors because Chez
  ;;     requires excepted names to actually be exported.
  ;; Rename-on-export works in both because we never collide with, nor
  ;; reference, the built-in name in the library body.
  (export
    (rename (b64-encode base64-encode)
            (b64-decode base64-decode))
    u8vector->base64-string base64-string->u8vector)

  (import (chezscheme))

  (define +alphabet-std+
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
  (define +alphabet-url+
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

  (define (encode bv url-safe? pad?)
    (let* ([alpha (if url-safe? +alphabet-url+ +alphabet-std+)]
           [n (bytevector-length bv)]
           [full (quotient n 3)]
           [rem (- n (* full 3))]
           [out-len (+ (* full 4)
                       (cond [(= rem 0) 0]
                             [pad?      4]
                             [(= rem 1) 2]
                             [else      3]))]
           [out (make-string out-len)])
      (let loop ([i 0] [j 0])
        (cond
         [(< i (* full 3))
          (let ([b0 (bytevector-u8-ref bv i)]
                [b1 (bytevector-u8-ref bv (+ i 1))]
                [b2 (bytevector-u8-ref bv (+ i 2))])
            (string-set! out j
              (string-ref alpha (bitwise-arithmetic-shift-right b0 2)))
            (string-set! out (+ j 1)
              (string-ref alpha
                (bitwise-and #x3f
                  (bitwise-ior (bitwise-arithmetic-shift-left b0 4)
                               (bitwise-arithmetic-shift-right b1 4)))))
            (string-set! out (+ j 2)
              (string-ref alpha
                (bitwise-and #x3f
                  (bitwise-ior (bitwise-arithmetic-shift-left b1 2)
                               (bitwise-arithmetic-shift-right b2 6)))))
            (string-set! out (+ j 3)
              (string-ref alpha (bitwise-and b2 #x3f)))
            (loop (+ i 3) (+ j 4)))]
         [(= rem 1)
          (let ([b0 (bytevector-u8-ref bv i)])
            (string-set! out j
              (string-ref alpha (bitwise-arithmetic-shift-right b0 2)))
            (string-set! out (+ j 1)
              (string-ref alpha
                (bitwise-and #x3f (bitwise-arithmetic-shift-left b0 4))))
            (when pad?
              (string-set! out (+ j 2) #\=)
              (string-set! out (+ j 3) #\=)))]
         [(= rem 2)
          (let ([b0 (bytevector-u8-ref bv i)]
                [b1 (bytevector-u8-ref bv (+ i 1))])
            (string-set! out j
              (string-ref alpha (bitwise-arithmetic-shift-right b0 2)))
            (string-set! out (+ j 1)
              (string-ref alpha
                (bitwise-and #x3f
                  (bitwise-ior (bitwise-arithmetic-shift-left b0 4)
                               (bitwise-arithmetic-shift-right b1 4)))))
            (string-set! out (+ j 2)
              (string-ref alpha
                (bitwise-and #x3f (bitwise-arithmetic-shift-left b1 2))))
            (when pad?
              (string-set! out (+ j 3) #\=)))]))
      out))

  (define b64-encode
    (case-lambda
      [(bv)                (encode bv #f #t)]
      [(bv url-safe?)      (encode bv url-safe? #t)]
      [(bv url-safe? pad?) (encode bv url-safe? pad?)]))

  (define (decode-char c)
    (cond
     [(and (char>=? c #\A) (char<=? c #\Z)) (- (char->integer c) (char->integer #\A))]
     [(and (char>=? c #\a) (char<=? c #\z)) (+ 26 (- (char->integer c) (char->integer #\a)))]
     [(and (char>=? c #\0) (char<=? c #\9)) (+ 52 (- (char->integer c) (char->integer #\0)))]
     [(or (char=? c #\+) (char=? c #\-))    62]
     [(or (char=? c #\/) (char=? c #\_))    63]
     [else #f]))

  (define (b64-decode str)
    (let* ([raw-len (string-length str)]
           [end (let loop ([k raw-len])
                  (if (and (> k 0) (char=? (string-ref str (- k 1)) #\=))
                      (loop (- k 1))
                      k))])
      (when (= 1 (modulo end 4))
        (errorf 'base64-decode "invalid base64 length (mod 4 = 1)"))
      (let* ([q (quotient end 4)]
             [r (- end (* q 4))]
             [out-len (case r
                        [(0) (* q 3)]
                        [(2) (+ (* q 3) 1)]
                        [(3) (+ (* q 3) 2)])]
             [out (make-bytevector out-len)])
        (let loop ([i 0] [j 0])
          (cond
           [(>= i end) out]
           [else
            (let* ([n (min 4 (- end i))]
                   [c0 (decode-char (string-ref str i))]
                   [c1 (and (>= n 2) (decode-char (string-ref str (+ i 1))))]
                   [c2 (and (>= n 3) (decode-char (string-ref str (+ i 2))))]
                   [c3 (and (>= n 4) (decode-char (string-ref str (+ i 3))))])
              (unless c0 (errorf 'base64-decode "invalid char at index ~a" i))
              (when (and (>= n 2) (not c1)) (errorf 'base64-decode "invalid char at index ~a" (+ i 1)))
              (when (and (>= n 3) (not c2)) (errorf 'base64-decode "invalid char at index ~a" (+ i 2)))
              (when (and (>= n 4) (not c3)) (errorf 'base64-decode "invalid char at index ~a" (+ i 3)))
              (when (>= n 2)
                (bytevector-u8-set! out j
                  (bitwise-and #xff
                    (bitwise-ior (bitwise-arithmetic-shift-left c0 2)
                                 (bitwise-arithmetic-shift-right c1 4)))))
              (when (>= n 3)
                (bytevector-u8-set! out (+ j 1)
                  (bitwise-and #xff
                    (bitwise-ior (bitwise-arithmetic-shift-left c1 4)
                                 (bitwise-arithmetic-shift-right c2 2)))))
              (when (>= n 4)
                (bytevector-u8-set! out (+ j 2)
                  (bitwise-and #xff
                    (bitwise-ior (bitwise-arithmetic-shift-left c2 6) c3))))
              (loop (+ i 4) (+ j 3)))])))))

  (define u8vector->base64-string b64-encode)
  (define base64-string->u8vector b64-decode))
