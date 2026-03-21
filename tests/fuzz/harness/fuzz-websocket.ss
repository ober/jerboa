#!/usr/bin/env scheme-script
#!chezscheme
;;; fuzz-websocket.ss -- Fuzzer for std/net/websocket
;;;
;;; Targets: ws-frame-decode, ws-frame-encode
;;; Bug classes: OOB, memory exhaustion, signedness bugs

(import (chezscheme)
        (std net websocket)
        (std test fuzz))

;;; ========== Seed corpus ==========

(define ws-seeds
  (list
    ;; Valid text frame, unmasked, "hello"
    (ws-frame-encode (ws-text-frame (string->utf8 "hello")))
    ;; Valid binary frame
    (ws-frame-encode (ws-binary-frame (make-bytevector 10 #xAB)))
    ;; Ping
    (ws-frame-encode (ws-ping-frame (make-bytevector 0)))
    ;; Close
    (ws-frame-encode (ws-close-frame))
    ;; Masked frame
    (ws-frame-encode
      (make-ws-frame #t #t ws-opcode-text (string->utf8 "masked")
                     #vu8(1 2 3 4)))))

;;; ========== Generators ==========

(define (gen-random-ws-frame)
  (case (random 10)
    [(0) ;; 0 bytes
     (make-bytevector 0)]
    [(1) ;; 1 byte only (no length byte)
     (make-bytevector 1 (random 256))]
    [(2) ;; 2 bytes: extended 16-bit length, too short
     (let ([bv (make-bytevector 3 0)])
       (bytevector-u8-set! bv 0 #x81)  ;; FIN + text
       (bytevector-u8-set! bv 1 126)    ;; 16-bit extended
       bv)]
    [(3) ;; 2 bytes: extended 64-bit length, too short
     (let ([bv (make-bytevector 5 0)])
       (bytevector-u8-set! bv 0 #x81)
       (bytevector-u8-set! bv 1 127)    ;; 64-bit extended
       bv)]
    [(4) ;; 64-bit length with MSB set (2^63)
     (let ([bv (make-bytevector 10 0)])
       (bytevector-u8-set! bv 0 #x81)
       (bytevector-u8-set! bv 1 127)
       (bytevector-u8-set! bv 2 #x80)   ;; MSB set = negative in signed
       bv)]
    [(5) ;; mask bit set but data too short for mask key
     (let ([bv (make-bytevector 3 0)])
       (bytevector-u8-set! bv 0 #x81)
       (bytevector-u8-set! bv 1 #x81)   ;; MASK + length 1
       bv)]
    [(6) ;; RSV bits set
     (let ([bv (make-bytevector 2 0)])
       (bytevector-u8-set! bv 0 (bitwise-ior #xF0 ws-opcode-text))
       (bytevector-u8-set! bv 1 0)
       bv)]
    [(7) ;; large but valid frame, mutated
     (mutate-bytevector (random-element ws-seeds))]
    [(8) ;; payload length claims more than available
     (let ([bv (make-bytevector 10 0)])
       (bytevector-u8-set! bv 0 #x82)
       (bytevector-u8-set! bv 1 50)      ;; claims 50 bytes payload
       bv)]                               ;; but only 8 bytes available
    [(9) ;; pure random
     (random-bytevector (+ 1 (random (fuzz-max-size))))]))

;;; ========== Run ==========

(define ws-stats
  (fuzz-run "websocket-decode"
    (lambda (input)
      (guard (exn [#t (void)])
        (ws-frame-decode input)))
    gen-random-ws-frame))

;; Roundtrip: encode then decode
(define ws-rt-stats
  (fuzz-run "websocket-roundtrip"
    (lambda (_)
      (let* ([payload (random-bytevector (random 200))]
             [opcode (random-element (list ws-opcode-text ws-opcode-binary
                                           ws-opcode-ping ws-opcode-pong))]
             [frame (make-ws-frame #t #f opcode payload)]
             [encoded (ws-frame-encode frame)]
             [decoded (ws-frame-decode encoded)])
        (unless (and (ws-frame-fin? decoded)
                     (= (ws-frame-opcode decoded) opcode)
                     (equal? (ws-frame-payload decoded) payload))
          (error 'ws-roundtrip "mismatch"))))
    (lambda () #f)
    (quotient (fuzz-iterations) 4)))

(when (or (> (fuzz-stats-crashes ws-stats) 0)
          (> (fuzz-stats-crashes ws-rt-stats) 0))
  (exit 1))
