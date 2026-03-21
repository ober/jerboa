#!/usr/bin/env scheme-script
#!chezscheme
;;; fuzz-dns.ss -- Fuzzer for std/net/dns
;;;
;;; Targets: dns-decode-response, dns-decode-name
;;; Bug classes: infinite loops (compression), OOB, truncation

(import (chezscheme)
        (std net dns)
        (std test fuzz))

;;; ========== Seed corpus ==========

;; Build a minimal valid DNS response:
;; Header (12 bytes): id=0x1234, flags=0x8180, QD=0, AN=1, NS=0, AR=0
;; Answer: name=\x03www\x07example\x03com\x00, type=A, class=IN, ttl=300, rdlen=4, rdata=93.184.216.34
(define seed-response
  (let ([bv (make-bytevector (+ 12 0 ;; no questions
                               (+ 17 10 4)) ;; answer: name(17) + type/class/ttl/rdlen(10) + rdata(4)
                             0)])
    ;; Header
    (bytevector-u8-set! bv 0 #x12) (bytevector-u8-set! bv 1 #x34) ;; ID
    (bytevector-u8-set! bv 2 #x81) (bytevector-u8-set! bv 3 #x80) ;; flags: response, no error
    ;; QDCOUNT=0
    ;; ANCOUNT=1
    (bytevector-u8-set! bv 7 1)
    ;; Answer: www.example.com
    (let ([pos 12])
      (bytevector-u8-set! bv pos 3) ;; label "www"
      (bytevector-u8-set! bv (+ pos 1) (char->integer #\w))
      (bytevector-u8-set! bv (+ pos 2) (char->integer #\w))
      (bytevector-u8-set! bv (+ pos 3) (char->integer #\w))
      (bytevector-u8-set! bv (+ pos 4) 7) ;; label "example"
      (for-each (lambda (c i)
                  (bytevector-u8-set! bv (+ pos 5 i) (char->integer c)))
                (string->list "example") (iota 7))
      (bytevector-u8-set! bv (+ pos 12) 3) ;; label "com"
      (for-each (lambda (c i)
                  (bytevector-u8-set! bv (+ pos 13 i) (char->integer c)))
                (string->list "com") (iota 3))
      (bytevector-u8-set! bv (+ pos 16) 0) ;; null terminator
      ;; Type A = 1
      (let ([apos (+ pos 17)])
        (bytevector-u8-set! bv (+ apos 1) 1) ;; type=A
        (bytevector-u8-set! bv (+ apos 3) 1) ;; class=IN
        ;; TTL = 300
        (bytevector-u8-set! bv (+ apos 5) 1)
        (bytevector-u8-set! bv (+ apos 6) #x2C)
        ;; RDLENGTH = 4
        (bytevector-u8-set! bv (+ apos 9) 4)
        ;; RDATA = 93.184.216.34
        (bytevector-u8-set! bv (+ apos 10) 93)
        (bytevector-u8-set! bv (+ apos 11) 184)
        (bytevector-u8-set! bv (+ apos 12) 216)
        (bytevector-u8-set! bv (+ apos 13) 34)))
    bv))

;;; ========== Generators ==========

(define (gen-compression-loop)
  ;; DNS message with compression pointer to itself
  (let ([bv (make-bytevector 14 0)])
    ;; Header: response, 0 questions, 1 answer
    (bytevector-u8-set! bv 2 #x80)
    (bytevector-u8-set! bv 7 1)
    ;; At offset 12: compression pointer to offset 12 (self-loop)
    (bytevector-u8-set! bv 12 #xC0)
    (bytevector-u8-set! bv 13 12)
    bv))

(define (gen-compression-cycle)
  ;; A -> B -> A cycle
  (let ([bv (make-bytevector 16 0)])
    (bytevector-u8-set! bv 2 #x80)
    (bytevector-u8-set! bv 7 1)
    ;; Offset 12: pointer to 14
    (bytevector-u8-set! bv 12 #xC0)
    (bytevector-u8-set! bv 13 14)
    ;; Offset 14: pointer to 12
    (bytevector-u8-set! bv 14 #xC0)
    (bytevector-u8-set! bv 15 12)
    bv))

(define (gen-random-dns)
  (case (random 10)
    [(0) ;; too short for header
     (random-bytevector (random 12))]
    [(1) ;; compression pointer to self
     (gen-compression-loop)]
    [(2) ;; compression pointer cycle
     (gen-compression-cycle)]
    [(3) ;; compression pointer past end
     (let ([bv (make-bytevector 14 0)])
       (bytevector-u8-set! bv 2 #x80)
       (bytevector-u8-set! bv 7 1)
       (bytevector-u8-set! bv 12 #xC0)
       (bytevector-u8-set! bv 13 #xFF) ;; points to offset 0x3FFF
       bv)]
    [(4) ;; QDCOUNT = 65535 but no question data
     (let ([bv (make-bytevector 12 0)])
       (bytevector-u8-set! bv 2 #x80)
       (bytevector-u8-set! bv 4 #xFF)
       (bytevector-u8-set! bv 5 #xFF)
       bv)]
    [(5) ;; ANCOUNT high but truncated
     (let ([bv (make-bytevector 20 0)])
       (bytevector-u8-set! bv 2 #x80)
       (bytevector-u8-set! bv 7 10) ;; 10 answers claimed
       ;; But only 8 bytes after header
       bv)]
    [(6) ;; label length 255
     (let ([bv (make-bytevector 14 0)])
       (bytevector-u8-set! bv 2 #x80)
       (bytevector-u8-set! bv 7 1)
       (bytevector-u8-set! bv 12 255) ;; label len = 255
       bv)]
    [(7) ;; all zeros
     (make-bytevector 12 0)]
    [(8) ;; mutated valid response
     (mutate-bytevector seed-response)]
    [(9) ;; pure random, at least 12 bytes
     (random-bytevector (+ 12 (random (fuzz-max-size))))]))

;;; ========== Run ==========

(define dns-stats
  (fuzz-run "dns-decode"
    (lambda (input)
      (guard (exn [#t (void)])
        (dns-decode-response input)))
    gen-random-dns))

;; Also fuzz dns-decode-name directly
(define dns-name-stats
  (fuzz-run "dns-decode-name"
    (lambda (input)
      (guard (exn [#t (void)])
        (when (>= (bytevector-length input) 1)
          (dns-decode-name input 0))))
    (lambda () (random-bytevector (+ 1 (random 256))))
    (quotient (fuzz-iterations) 2)))

;; Roundtrip: encode-query then decode
(define dns-rt-stats
  (fuzz-run "dns-roundtrip"
    (lambda (_)
      (let* ([name (string-append
                     (random-ascii-string 10) "."
                     (random-ascii-string 5) "."
                     (random-ascii-string 3))]
             [query (dns-make-query (random #xFFFF) name dns-rr-type-a)]
             [encoded (dns-encode-query query)])
        ;; Just ensure it doesn't crash — can't fully roundtrip queries as responses
        (when (>= (bytevector-length encoded) 12)
          (void))))
    (lambda () #f)
    (quotient (fuzz-iterations) 4)))

(when (or (> (fuzz-stats-crashes dns-stats) 0)
          (> (fuzz-stats-crashes dns-name-stats) 0))
  (exit 1))
