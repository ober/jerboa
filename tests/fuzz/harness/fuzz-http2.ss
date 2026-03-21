#!/usr/bin/env scheme-script
#!chezscheme
;;; fuzz-http2.ss -- Fuzzer for std/net/http2
;;;
;;; Targets: http2-frame-decode, hpack-decode
;;; Bug classes: OOB, memory exhaustion, frame confusion

(import (chezscheme)
        (std net http2)
        (std test fuzz))

;;; ========== Seed corpus: valid frames ==========

(define (make-seed-data-frame)
  ;; Valid DATA frame: stream 1, 5 bytes payload
  (http2-frame-encode
    (make-http2-data-frame 1 (string->utf8 "hello"))))

(define (make-seed-headers-frame)
  ;; Valid HEADERS frame with HPACK
  (let ([ctx (make-hpack-context)])
    (http2-frame-encode
      (make-http2-headers-frame 1
        (hpack-encode ctx '((":method" . "GET") (":path" . "/")))))))

(define (make-seed-settings-frame)
  (http2-frame-encode (make-http2-settings-frame (make-bytevector 0))))

(define (make-seed-ping-frame)
  (http2-frame-encode (make-http2-ping-frame (make-bytevector 8 0))))

(define http2-seeds
  (list (make-seed-data-frame)
        (make-seed-headers-frame)
        (make-seed-settings-frame)
        (make-seed-ping-frame)))

;;; ========== Generators ==========

(define (gen-random-frame)
  (case (random 8)
    [(0) ;; too short for header
     (random-bytevector (random 9))]
    [(1) ;; valid header, payload length mismatch
     (let ([bv (make-bytevector 9 0)])
       ;; Set length to 100 but only 0 bytes of payload
       (bytevector-u8-set! bv 2 100)
       (bytevector-u8-set! bv 3 (random 10))  ;; random type
       bv)]
    [(2) ;; huge length field (16MB)
     (let ([bv (make-bytevector 9 0)])
       (bytevector-u8-set! bv 0 #xFF)
       (bytevector-u8-set! bv 1 #xFF)
       (bytevector-u8-set! bv 2 #xFF)
       bv)]
    [(3) ;; unknown frame type
     (let ([bv (make-bytevector 9 0)])
       (bytevector-u8-set! bv 3 #xFF)
       bv)]
    [(4) ;; reserved bit set in stream ID
     (let ([bv (make-bytevector 9 0)])
       (bytevector-u8-set! bv 5 #x80)
       bv)]
    [(5) ;; valid frame, mutated
     (mutate-bytevector (random-element http2-seeds))]
    [(6) ;; SETTINGS frame with random settings
     (let* ([n-settings (+ 1 (random 10))]
            [payload (random-bytevector (* n-settings 6))]
            [frame (make-http2-settings-frame payload)])
       (mutate-bytevector (http2-frame-encode frame)))]
    [(7) ;; pure random
     (random-bytevector (+ 1 (random (fuzz-max-size))))]))

;;; ========== HPACK fuzz ==========

(define (gen-random-hpack)
  (case (random 5)
    [(0) ;; empty
     (make-bytevector 0)]
    [(1) ;; indexed header with bad index
     (let ([bv (make-bytevector 1)])
       (bytevector-u8-set! bv 0 (bitwise-ior #x80 (+ 62 (random 60))))
       bv)]
    [(2) ;; literal with name index > static table
     (let ([bv (make-bytevector 3 0)])
       (bytevector-u8-set! bv 0 (+ 62 (random 60)))
       bv)]
    [(3) ;; mutated valid HPACK
     (let ([ctx (make-hpack-context)])
       (mutate-bytevector
         (hpack-encode ctx '((":method" . "GET") ("host" . "example.com")))))]
    [(4) ;; random
     (random-bytevector (+ 1 (random 100)))]))

(define hpack-stats
  (fuzz-run "hpack-decode"
    (lambda (input)
      (guard (exn [#t (void)])
        (let ([ctx (make-hpack-context)])
          (hpack-decode ctx input))))
    gen-random-hpack))

;;; ========== Frame decode fuzz ==========

(define http2-stats
  (fuzz-run "http2-frame-decode"
    (lambda (input)
      (guard (exn [#t (void)])
        (http2-frame-decode input)))
    gen-random-frame))

;; Roundtrip: encode then decode using public constructors
(define http2-rt-stats
  (fuzz-run "http2-roundtrip"
    (lambda (_)
      (let* ([stream-id (+ 1 (random #x7FFFFF))]
             [payload (random-bytevector (random 100))]
             [frame (make-http2-data-frame stream-id payload)]
             [encoded (http2-frame-encode frame)]
             [decoded (http2-frame-decode encoded)])
        (unless (and (= (http2-frame-type decoded) http2-frame-type-data)
                     (= (http2-frame-stream-id decoded) stream-id)
                     (equal? (http2-frame-payload decoded) payload))
          (error 'http2-roundtrip "mismatch"))))
    (lambda () #f)
    (quotient (fuzz-iterations) 4)))

(when (or (> (fuzz-stats-crashes http2-stats) 0)
          (> (fuzz-stats-crashes hpack-stats) 0)
          (> (fuzz-stats-crashes http2-rt-stats) 0))
  (exit 1))
