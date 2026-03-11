#!chezscheme
;;; Tests for (std net dns) -- DNS message format

(import (chezscheme) (std net dns))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(printf "--- Phase 3b: DNS ---~%~%")

;;; ======== RR type constants ========

(test "rr-type-a"     dns-rr-type-a     1)
(test "rr-type-ns"    dns-rr-type-ns    2)
(test "rr-type-cname" dns-rr-type-cname 5)
(test "rr-type-mx"    dns-rr-type-mx    15)
(test "rr-type-txt"   dns-rr-type-txt   16)
(test "rr-type-aaaa"  dns-rr-type-aaaa  28)

;;; ======== Name encoding ========

(test "encode-name-first-byte"
  ;; "www.example.com" -> first label is "www" (len=3)
  (bytevector-u8-ref (dns-encode-name "www.example.com") 0)
  3)

(test "encode-name-null-terminator"
  ;; Last byte of encoded name should be 0
  (let* ([enc (dns-encode-name "example.com")]
         [len (bytevector-length enc)])
    (bytevector-u8-ref enc (- len 1)))
  0)

(test "encode-name-total-length"
  ;; "a.bc" -> #u8(1 97 2 98 99 0) = 6 bytes
  (bytevector-length (dns-encode-name "a.bc"))
  6)

;;; ======== Name decoding ========

(test "decode-name-simple"
  (let* ([enc (dns-encode-name "example.com")]
         [dec (dns-decode-name enc 0)])
    (car dec))
  "example.com")

(test "decode-name-subdomain"
  (let* ([enc (dns-encode-name "www.example.com")]
         [dec (dns-decode-name enc 0)])
    (car dec))
  "www.example.com")

(test "decode-name-next-offset"
  ;; "abc.def" -> 1+3 + 1+3 + 1(null) = 9 bytes, next pos = 9
  (let* ([enc (dns-encode-name "abc.def")]
         [dec (dns-decode-name enc 0)])
    (cdr dec))
  9)

;;; ======== Name round-trip ========

(test "name-roundtrip"
  (let* ([name "mail.example.org"]
         [enc  (dns-encode-name name)]
         [dec  (dns-decode-name enc 0)])
    (car dec))
  "mail.example.org")

;;; ======== Query construction ========

(test "make-query-transaction-id"
  (dns-transaction-id (dns-make-query 9999 "example.com" dns-rr-type-a))
  9999)

(test "make-query-not-response"
  (dns-response? (dns-make-query 1 "example.com" dns-rr-type-a))
  #f)

(test "encode-query-id"
  (let* ([msg (dns-make-query 1234 "example.com" dns-rr-type-a)]
         [enc (dns-encode-query msg)])
    (bitwise-ior
      (bitwise-arithmetic-shift-left (bytevector-u8-ref enc 0) 8)
      (bytevector-u8-ref enc 1)))
  1234)

(test "encode-query-qdcount"
  (let* ([msg (dns-make-query 1 "example.com" dns-rr-type-a)]
         [enc (dns-encode-query msg)])
    ;; Bytes 4-5 = QDCOUNT
    (bitwise-ior
      (bitwise-arithmetic-shift-left (bytevector-u8-ref enc 4) 8)
      (bytevector-u8-ref enc 5)))
  1)

;;; ======== Answer record ========

(test "answer-name"
  (dns-answer-name (dns-answer "example.com" dns-rr-type-a 300 "1.2.3.4"))
  "example.com")

(test "answer-type"
  (dns-answer-type (dns-answer "example.com" dns-rr-type-a 300 "1.2.3.4"))
  dns-rr-type-a)

(test "answer-ttl"
  (dns-answer-ttl (dns-answer "example.com" dns-rr-type-a 3600 "1.2.3.4"))
  3600)

(test "answer-data"
  (dns-answer-data (dns-answer "example.com" dns-rr-type-a 300 "1.2.3.4"))
  "1.2.3.4")

;;; ======== Response decoding ========

;; Build a minimal synthetic DNS response
(define (make-test-response id name ip)
  (let* ([name-enc (dns-encode-name name)]
         [nlen     (bytevector-length name-enc)]
         [total    (+ 12 nlen 4 nlen 14)]
         [bv       (make-bytevector total 0)])
    ;; ID
    (bytevector-u8-set! bv 0 (bitwise-arithmetic-shift-right id 8))
    (bytevector-u8-set! bv 1 (bitwise-and id #xFF))
    ;; FLAGS: QR=1, RD=1
    (bytevector-u8-set! bv 2 #x81) (bytevector-u8-set! bv 3 0)
    ;; QDCOUNT=1, ANCOUNT=1
    (bytevector-u8-set! bv 5 1) (bytevector-u8-set! bv 7 1)
    ;; Question name
    (bytevector-copy! name-enc 0 bv 12 nlen)
    ;; TYPE A + CLASS IN
    (bytevector-u8-set! bv (+ 12 nlen 1) 1)
    (bytevector-u8-set! bv (+ 12 nlen 3) 1)
    ;; Answer name
    (let ([aoff (+ 12 nlen 4)])
      (bytevector-copy! name-enc 0 bv aoff nlen)
      (let ([off (+ aoff nlen)])
        ;; TYPE A, CLASS IN
        (bytevector-u8-set! bv (+ off 1) 1)
        (bytevector-u8-set! bv (+ off 3) 1)
        ;; TTL = 300
        (bytevector-u8-set! bv (+ off 6) 1) (bytevector-u8-set! bv (+ off 7) 44)
        ;; RDLENGTH = 4
        (bytevector-u8-set! bv (+ off 9) 4)
        ;; IPv4
        (let ([parts (map string->number (string-split ip #\.))])
          (bytevector-u8-set! bv (+ off 10) (list-ref parts 0))
          (bytevector-u8-set! bv (+ off 11) (list-ref parts 1))
          (bytevector-u8-set! bv (+ off 12) (list-ref parts 2))
          (bytevector-u8-set! bv (+ off 13) (list-ref parts 3)))))
    bv))

(define (string-split str delim)
  (let loop ([i 0] [start 0] [acc '()])
    (cond
      [(= i (string-length str)) (reverse (cons (substring str start i) acc))]
      [(char=? (string-ref str i) delim)
       (loop (+ i 1) (+ i 1) (cons (substring str start i) acc))]
      [else (loop (+ i 1) start acc)])))

(test "response-decode-id"
  (dns-transaction-id (dns-decode-response (make-test-response 42 "example.com" "1.2.3.4")))
  42)

(test "response-decode-is-response"
  (dns-response? (dns-decode-response (make-test-response 1 "example.com" "10.0.0.1")))
  #t)

(test "response-decode-answer-count"
  (length (dns-answers (dns-decode-response (make-test-response 1 "test.com" "5.6.7.8"))))
  1)

(test "response-decode-a-data"
  (let* ([bv  (make-test-response 1 "example.com" "192.168.1.1")]
         [msg (dns-decode-response bv)]
         [ans (car (dns-answers msg))])
    (dns-answer-data ans))
  "192.168.1.1")

(test "response-decode-name"
  (let* ([bv  (make-test-response 1 "example.com" "1.1.1.1")]
         [msg (dns-decode-response bv)]
         [ans (car (dns-answers msg))])
    (dns-answer-name ans))
  "example.com")

;;; Summary

(printf "~%DNS tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
