#!chezscheme
;;; (std net websocket) -- WebSocket protocol (RFC 6455)
;;;
;;; Pure functions for frame encoding/decoding and handshake logic.
;;; No live network connections required for testing.

(library (std net websocket)
  (export
    ;; Opcode constants
    ws-opcode-continuation ws-opcode-text ws-opcode-binary
    ws-opcode-close ws-opcode-ping ws-opcode-pong
    ;; Frame construction
    make-ws-frame ws-close-frame ws-ping-frame ws-pong-frame
    ws-text-frame ws-binary-frame
    ;; Frame accessors
    ws-frame-fin? ws-frame-masked? ws-frame-opcode ws-frame-payload
    ;; Encode/decode
    ws-frame-encode ws-frame-decode
    ;; Masking
    ws-mask-payload ws-unmask-payload
    ;; Handshake
    ws-handshake-key ws-handshake-accept ws-handshake-valid?
    ;; Limits
    *ws-max-payload-size*)

  (import (chezscheme)
          (std crypto native-rust)
          (std text base64))

  ;; sha1-bytevector is now in (chezscheme) core (Phase 67, Round 12).
  ;; Falls back to FFI rust-sha1 only when the prim isn't available.

  ;;; ========== Opcode constants ==========
  (define ws-opcode-continuation #x0)
  (define ws-opcode-text         #x1)
  (define ws-opcode-binary       #x2)
  (define ws-opcode-close        #x8)
  (define ws-opcode-ping         #x9)
  (define ws-opcode-pong         #xA)

  ;;; ========== Frame record ==========
  (define-record-type ws-frame-rec
    (fields fin? masked? opcode payload mask-key)
    (protocol
      (lambda (new)
        (lambda (fin? masked? opcode payload . rest)
          (new fin? masked? opcode payload
               (if (null? rest) #f (car rest)))))))

  (define (make-ws-frame fin? masked? opcode payload . rest)
    (apply make-ws-frame-rec fin? masked? opcode payload rest))

  (define (ws-frame-fin?    f) (ws-frame-rec-fin?    f))
  (define (ws-frame-masked? f) (ws-frame-rec-masked? f))
  (define (ws-frame-opcode  f) (ws-frame-rec-opcode  f))
  (define (ws-frame-payload f) (ws-frame-rec-payload f))

  ;;; ========== Convenience constructors ==========
  (define (ws-text-frame payload)
    (make-ws-frame #t #f ws-opcode-text payload))

  (define (ws-binary-frame payload)
    (make-ws-frame #t #f ws-opcode-binary payload))

  (define (ws-close-frame)
    (make-ws-frame #t #f ws-opcode-close (make-bytevector 0)))

  (define (ws-ping-frame payload)
    (make-ws-frame #t #f ws-opcode-ping payload))

  (define (ws-pong-frame payload)
    (make-ws-frame #t #f ws-opcode-pong payload))

  ;;; ========== Masking ==========
  ;; XOR payload bytes with 4-byte mask key cyclically.
  (define (ws-mask-payload payload mask-key)
    (let* ([len (bytevector-length payload)]
           [result (make-bytevector len)])
      (do ([i 0 (+ i 1)])
          ((= i len) result)
        (bytevector-u8-set! result i
          (bitwise-xor (bytevector-u8-ref payload i)
                       (bytevector-u8-ref mask-key (modulo i 4)))))))

  ;; Unmasking is the same operation (XOR is its own inverse).
  (define ws-unmask-payload ws-mask-payload)

  ;;; ========== Frame encoding ==========
  ;; Encode a ws-frame-rec to a bytevector per RFC 6455.
  ;;
  ;; Wire format:
  ;;   Byte 0: FIN(1) RSV1(1) RSV2(1) RSV3(1) Opcode(4)
  ;;   Byte 1: MASK(1) Payload-length(7)
  ;;   Extended payload length (0, 2, or 8 bytes)
  ;;   Masking key (4 bytes, if MASK=1)
  ;;   Payload data
  (define (ws-frame-encode frame)
    (let* ([fin?    (ws-frame-rec-fin?    frame)]
           [masked? (ws-frame-rec-masked? frame)]
           [opcode  (ws-frame-rec-opcode  frame)]
           [payload (ws-frame-rec-payload frame)]
           [mask-key (ws-frame-rec-mask-key frame)]
           [plen    (bytevector-length payload)]
           ;; Determine extended length encoding
           [ext-bytes (cond [(< plen 126) 0]
                            [(< plen 65536) 2]
                            [else 8])]
           [len7 (cond [(< plen 126) plen]
                       [(< plen 65536) 126]
                       [else 127])]
           [header-size (+ 2 ext-bytes (if masked? 4 0))]
           [total-size  (+ header-size plen)]
           [bv (make-bytevector total-size 0)])
      ;; Byte 0: FIN + opcode
      (bytevector-u8-set! bv 0
        (bitwise-ior (if fin? #x80 0) (bitwise-and opcode #x0F)))
      ;; Byte 1: MASK + payload length (7-bit)
      (bytevector-u8-set! bv 1
        (bitwise-ior (if masked? #x80 0) len7))
      ;; Extended payload length
      (cond
        [(= ext-bytes 2)
         (bytevector-u8-set! bv 2 (bitwise-arithmetic-shift-right plen 8))
         (bytevector-u8-set! bv 3 (bitwise-and plen #xFF))]
        [(= ext-bytes 8)
         ;; Write 8-byte big-endian length (only 4 low bytes used in practice)
         (do ([i 0 (+ i 1)])
             ((= i 8))
           (bytevector-u8-set! bv (+ 2 i)
             (bitwise-and
               (bitwise-arithmetic-shift-right plen (* 8 (- 7 i)))
               #xFF)))])
      ;; Masking key (if present)
      (let ([key-offset (+ 2 ext-bytes)])
        (when (and masked? mask-key)
          (do ([i 0 (+ i 1)])
              ((= i 4))
            (bytevector-u8-set! bv (+ key-offset i)
              (bytevector-u8-ref mask-key i))))
        ;; Payload (possibly masked)
        (let ([data-offset (+ key-offset (if masked? 4 0))])
          (if (and masked? mask-key)
            (let ([masked-payload (ws-mask-payload payload mask-key)])
              (bytevector-copy! masked-payload 0 bv data-offset plen))
            (bytevector-copy! payload 0 bv data-offset plen))))
      bv))

  ;;; ========== Frame decoding ==========

  (define *ws-max-payload-size* (make-parameter (* 16 1024 1024)))  ;; 16MB default

  (define (ws-frame-decode bv)
    (let ([bvlen (bytevector-length bv)])
      ;; Minimum frame is 2 bytes
      (unless (>= bvlen 2)
        (error 'ws-frame-decode "bytevector too short for frame header" bvlen))
      (let* ([b0      (bytevector-u8-ref bv 0)]
             [b1      (bytevector-u8-ref bv 1)]
             [fin?    (not (zero? (bitwise-and b0 #x80)))]
             [opcode  (bitwise-and b0 #x0F)]
             [masked? (not (zero? (bitwise-and b1 #x80)))]
             [len7    (bitwise-and b1 #x7F)]
             [pos     2])
        ;; Determine payload length with bounds checks
        (let-values ([(plen pos)
                      (cond
                        [(< len7 126) (values len7 pos)]
                        [(= len7 126)
                         (unless (>= bvlen 4)
                           (error 'ws-frame-decode "too short for 16-bit length" bvlen))
                         (values
                           (bitwise-ior
                             (bitwise-arithmetic-shift-left (bytevector-u8-ref bv pos) 8)
                             (bytevector-u8-ref bv (+ pos 1)))
                           (+ pos 2))]
                        [else
                         (unless (>= bvlen 10)
                           (error 'ws-frame-decode "too short for 64-bit length" bvlen))
                         ;; 8-byte extended length
                         (let ([n (let loop ([i 0] [acc 0])
                                    (if (= i 8)
                                      acc
                                      (loop (+ i 1)
                                            (bitwise-ior
                                              (bitwise-arithmetic-shift-left acc 8)
                                              (bytevector-u8-ref bv (+ pos i))))))])
                           (values n (+ pos 8)))])])
          ;; Validate payload size against cap
          (when (> plen (*ws-max-payload-size*))
            (error 'ws-frame-decode "payload exceeds maximum size"
                   plen (*ws-max-payload-size*)))
          ;; Validate masking key fits
          (let ([data-offset (+ pos (if masked? 4 0))])
            (when masked?
              (unless (>= bvlen (+ pos 4))
                (error 'ws-frame-decode "too short for masking key" bvlen)))
            ;; Validate payload fits
            (unless (>= bvlen (+ data-offset plen))
              (error 'ws-frame-decode "bytevector too short for payload"
                     bvlen (+ data-offset plen)))
            ;; Read masking key (if present)
            (let* ([mask-key (if masked?
                               (let ([k (make-bytevector 4)])
                                 (do ([i 0 (+ i 1)])
                                     ((= i 4) k)
                                   (bytevector-u8-set! k i (bytevector-u8-ref bv (+ pos i)))))
                               #f)]
                   [raw-payload (let ([p (make-bytevector plen)])
                                  (bytevector-copy! bv data-offset p 0 plen)
                                  p)]
                   [payload (if (and masked? mask-key)
                              (ws-unmask-payload raw-payload mask-key)
                              raw-payload)])
              (make-ws-frame fin? masked? opcode payload mask-key)))))))

  ;;; ========== Handshake ==========
  ;; The WebSocket handshake uses SHA-1 of (key + GUID) then base64.
  ;; Since we can't easily do SHA-1 in pure Scheme without libraries,
  ;; we implement a simplified version for testing purposes:
  ;;   - ws-handshake-accept returns a known result for the RFC 6455 example key.
  ;;   - For general use, this is the structure; real code would call a SHA-1 lib.

  ;; RFC 6455 magic GUID
  (define ws-guid "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")

  ;; The RFC 6455 test vector:
  ;;   key    = "dGhlIHNhbXBsZSBub25jZQ=="
  ;;   accept = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
  (define ws-rfc-test-key    "dGhlIHNhbXBsZSBub25jZQ==")
  (define ws-rfc-test-accept "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

  ;; Compute the Sec-WebSocket-Accept from a client key.
  ;; Per RFC 6455: SHA1(key + GUID) then base64-encode.
  (define (ws-handshake-accept key)
    (let* ([combined (string->utf8 (string-append key ws-guid))]
           [hash-bv (sha1-bytevector combined)])
      (u8vector->base64-string hash-bv)))

  ;; Generate a random 16-byte WebSocket key (base64-encoded).
  (define (ws-handshake-key)
    (u8vector->base64-string (rust-random-bytes 16)))

  ;; Validate that the server's accept matches the expected value.
  (define (ws-handshake-valid? key accept)
    (string=? accept (ws-handshake-accept key)))

) ;; end library
