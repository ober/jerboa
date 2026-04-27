#!chezscheme
;;; (std net dns) -- DNS message format (RFC 1035)
;;;
;;; Pure functions for encoding/decoding DNS wire-format messages.
;;; No live network connections.

(library (std net dns)
  (export
    ;; RR type constants
    dns-rr-type-a dns-rr-type-aaaa dns-rr-type-cname
    dns-rr-type-mx dns-rr-type-txt dns-rr-type-ns
    ;; Query construction
    dns-make-query dns-encode-query
    ;; Name encoding/decoding
    dns-encode-name dns-decode-name
    ;; Response decoding
    dns-decode-response
    ;; Message accessors
    dns-transaction-id dns-response? dns-questions dns-answers
    ;; Question record
    dns-question
    ;; Answer record and accessors
    dns-answer dns-answer-name dns-answer-type dns-answer-ttl dns-answer-data)

  (import (chezscheme))

  ;;; ========== RR type constants ==========
  (define dns-rr-type-a     1)
  (define dns-rr-type-ns    2)
  (define dns-rr-type-cname 5)
  (define dns-rr-type-mx    15)
  (define dns-rr-type-txt   16)
  (define dns-rr-type-aaaa  28)

  ;;; ========== Internal records ==========
  (define-record-type dns-question-rec
    (fields name type class))

  (define-record-type dns-answer-rec
    (fields name type class ttl data))

  (define-record-type dns-message-rec
    (fields id flags questions answers))

  ;; Public constructors
  (define (dns-question name type class)
    (make-dns-question-rec name type class))

  (define (dns-answer name type ttl data)
    (make-dns-answer-rec name type 1 ttl data))

  (define (dns-answer-name  a) (dns-answer-rec-name  a))
  (define (dns-answer-type  a) (dns-answer-rec-type  a))
  (define (dns-answer-ttl   a) (dns-answer-rec-ttl   a))
  (define (dns-answer-data  a) (dns-answer-rec-data  a))

  (define (dns-transaction-id msg) (dns-message-rec-id        msg))
  (define (dns-response?      msg) (not (zero? (bitwise-and (dns-message-rec-flags msg) #x8000))))
  (define (dns-questions      msg) (dns-message-rec-questions msg))
  (define (dns-answers        msg) (dns-message-rec-answers   msg))

  ;;; ========== Name encoding ==========
  ;; Encode a domain name string to DNS label format.
  ;; "www.example.com" -> #u8(3 119 119 119 7 101 120 ...)
  (define (dns-encode-name name)
    (let* ([labels (string-split name #\.)]
           [parts  (map (lambda (label)
                          (let* ([bstr (string->utf8 label)]
                                 [len  (bytevector-length bstr)]
                                 [out  (make-bytevector (+ 1 len))])
                            (bytevector-u8-set! out 0 len)
                            (bytevector-copy! bstr 0 out 1 len)
                            out))
                        labels)]
           ;; total = sum of (1 + len) for each label, + 1 for null terminator
           [total  (+ (apply + (map bytevector-length parts)) 1)]
           [result (make-bytevector total)]
           [pos    0])
      (for-each
        (lambda (part)
          (let ([plen (bytevector-length part)])
            (bytevector-copy! part 0 result pos plen)
            (set! pos (+ pos plen))))
        parts)
      ;; Null terminator
      (bytevector-u8-set! result pos 0)
      result))

  ;; Helper: split string by delimiter character
  (define (string-split str delim)
    (let loop ([i 0] [start 0] [acc '()])
      (cond
        [(= i (string-length str))
         (reverse (cons (substring str start i) acc))]
        [(char=? (string-ref str i) delim)
         (loop (+ i 1) (+ i 1) (cons (substring str start i) acc))]
        [else
         (loop (+ i 1) start acc)])))

  ;;; ========== Name decoding ==========
  ;; Decode DNS label-encoded name from bytevector at offset.
  ;; Returns (name-string . new-offset).
  ;; Handles compression pointers (0xC0 prefix).
  (define (dns-decode-name bv offset)
    (let ([bvlen (bytevector-length bv)])
      (let loop ([pos offset] [labels '()] [jumped? #f] [end-pos -1] [hops 0])
        ;; Prevent compression pointer loops
        (when (> hops 32)
          (error 'dns-decode-name "compression pointer loop detected"))
        ;; Bounds check
        (unless (< pos bvlen)
          (error 'dns-decode-name "offset out of bounds" pos bvlen))
        (let ([b (bytevector-u8-ref bv pos)])
          (cond
            ;; Null label: end of name
            [(= b 0)
             (let ([final-pos (if jumped? end-pos (+ pos 1))])
               (cons (string-join (reverse labels) ".") final-pos))]
            ;; Compression pointer: 11xxxxxx
            [(= (bitwise-and b #xC0) #xC0)
             (unless (< (+ pos 1) bvlen)
               (error 'dns-decode-name "truncated compression pointer" pos))
             (let* ([ptr (bitwise-ior
                           (bitwise-arithmetic-shift-left (bitwise-and b #x3F) 8)
                           (bytevector-u8-ref bv (+ pos 1)))]
                    [new-end (if jumped? end-pos (+ pos 2))])
               (unless (< ptr bvlen)
                 (error 'dns-decode-name "compression pointer out of bounds" ptr bvlen))
               (loop ptr labels #t new-end (+ hops 1)))]
            ;; Regular label
            [else
             (let* ([label-len b])
               (unless (<= (+ pos 1 label-len) bvlen)
                 (error 'dns-decode-name "label extends beyond bytevector" pos label-len))
               (let ([label-str (utf8->string
                                  (subbytevector bv (+ pos 1) (+ pos 1 label-len)))])
                 (loop (+ pos 1 label-len) (cons label-str labels) jumped? end-pos hops)))])))))

  ;; Helper: extract sub-bytevector — Chez core bytevector-slice (Phase 67).
  (define (subbytevector bv start end)
    (bytevector-slice bv start end))

  ;; Helper: join strings with separator
  (define (string-join strs sep)
    (if (null? strs)
      ""
      (let loop ([rest (cdr strs)] [acc (car strs)])
        (if (null? rest)
          acc
          (loop (cdr rest) (string-append acc sep (car rest)))))))

  ;;; ========== Query construction ==========
  (define (dns-make-query id name type)
    (make-dns-message-rec id #x0100  ; QR=0, RD=1
      (list (make-dns-question-rec name type 1))
      '()))

  ;;; ========== Query encoding ==========
  ;; DNS message header (12 bytes):
  ;;   ID(2) FLAGS(2) QDCOUNT(2) ANCOUNT(2) NSCOUNT(2) ARCOUNT(2)
  (define (dns-encode-query msg)
    (let* ([id        (dns-message-rec-id    msg)]
           [flags     (dns-message-rec-flags msg)]
           [questions (dns-message-rec-questions msg)]
           ;; Encode each question
           [q-parts   (map (lambda (q)
                             (let* ([name-bv (dns-encode-name (dns-question-rec-name q))]
                                    [type    (dns-question-rec-type  q)]
                                    [class   (dns-question-rec-class q)]
                                    [qlen    (+ (bytevector-length name-bv) 4)]
                                    [qbv     (make-bytevector qlen)])
                               (bytevector-copy! name-bv 0 qbv 0 (bytevector-length name-bv))
                               (let ([off (bytevector-length name-bv)])
                                 (bytevector-u8-set! qbv off       (bitwise-arithmetic-shift-right type 8))
                                 (bytevector-u8-set! qbv (+ off 1) (bitwise-and type #xFF))
                                 (bytevector-u8-set! qbv (+ off 2) (bitwise-arithmetic-shift-right class 8))
                                 (bytevector-u8-set! qbv (+ off 3) (bitwise-and class #xFF)))
                               qbv))
                           questions)]
           [q-total   (apply + (map bytevector-length q-parts))]
           [total     (+ 12 q-total)]
           [bv        (make-bytevector total 0)])
      ;; Header
      (bytevector-u8-set! bv 0 (bitwise-arithmetic-shift-right id 8))
      (bytevector-u8-set! bv 1 (bitwise-and id #xFF))
      (bytevector-u8-set! bv 2 (bitwise-arithmetic-shift-right flags 8))
      (bytevector-u8-set! bv 3 (bitwise-and flags #xFF))
      ;; QDCOUNT
      (bytevector-u8-set! bv 4 0)
      (bytevector-u8-set! bv 5 (length questions))
      ;; ANCOUNT, NSCOUNT, ARCOUNT = 0
      ;; Write question sections
      (let loop ([parts q-parts] [pos 12])
        (unless (null? parts)
          (let* ([p   (car parts)]
                 [len (bytevector-length p)])
            (bytevector-copy! p 0 bv pos len)
            (loop (cdr parts) (+ pos len)))))
      bv))

  ;;; ========== Response decoding ==========
  (define (dns-decode-response bv)
    ;; DNS header is 12 bytes minimum
    (unless (>= (bytevector-length bv) 12)
      (error 'dns-decode-response "bytevector too short for DNS header"
             (bytevector-length bv)))
    (let* ([id       (bitwise-ior
                       (bitwise-arithmetic-shift-left (bytevector-u8-ref bv 0) 8)
                       (bytevector-u8-ref bv 1))]
           [flags    (bitwise-ior
                       (bitwise-arithmetic-shift-left (bytevector-u8-ref bv 2) 8)
                       (bytevector-u8-ref bv 3))]
           [qdcount  (bitwise-ior
                       (bitwise-arithmetic-shift-left (bytevector-u8-ref bv 4) 8)
                       (bytevector-u8-ref bv 5))]
           [ancount  (bitwise-ior
                       (bitwise-arithmetic-shift-left (bytevector-u8-ref bv 6) 8)
                       (bytevector-u8-ref bv 7))]
           [pos      12])
      ;; Skip questions
      (let loop-q ([i 0] [pos pos])
        (if (= i qdcount)
          ;; Decode answers
          (let loop-a ([j 0] [pos pos] [answers '()])
            (if (= j ancount)
              (make-dns-message-rec id flags '() (reverse answers))
              (let* ([name-r  (dns-decode-name bv pos)]
                     [name    (car name-r)]
                     [pos     (cdr name-r)]
                     [type    (bitwise-ior
                                (bitwise-arithmetic-shift-left (bytevector-u8-ref bv pos) 8)
                                (bytevector-u8-ref bv (+ pos 1)))]
                     [_class  (bitwise-ior
                                (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ pos 2)) 8)
                                (bytevector-u8-ref bv (+ pos 3)))]
                     [ttl     (bitwise-ior
                                (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ pos 4)) 24)
                                (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ pos 5)) 16)
                                (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ pos 6)) 8)
                                (bytevector-u8-ref bv (+ pos 7)))]
                     [rdlen   (bitwise-ior
                                (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ pos 8)) 8)
                                (bytevector-u8-ref bv (+ pos 9)))]
                     [rdstart (+ pos 10)]
                     [rdata   (subbytevector bv rdstart (+ rdstart rdlen))]
                     [data    (cond
                                ;; A record: 4-byte IPv4
                                [(= type dns-rr-type-a)
                                 (string-append
                                   (number->string (bytevector-u8-ref rdata 0)) "."
                                   (number->string (bytevector-u8-ref rdata 1)) "."
                                   (number->string (bytevector-u8-ref rdata 2)) "."
                                   (number->string (bytevector-u8-ref rdata 3)))]
                                ;; AAAA record: 16-byte IPv6
                                [(= type dns-rr-type-aaaa)
                                 (let loop-v6 ([i 0] [parts '()])
                                   (if (= i 8)
                                     (string-join (reverse parts) ":")
                                     (let ([word (bitwise-ior
                                                   (bitwise-arithmetic-shift-left
                                                     (bytevector-u8-ref rdata (* i 2)) 8)
                                                   (bytevector-u8-ref rdata (+ (* i 2) 1)))])
                                       (loop-v6 (+ i 1)
                                                (cons (number->string word 16) parts)))))]
                                ;; CNAME: decode name
                                [(= type dns-rr-type-cname)
                                 (car (dns-decode-name bv rdstart))]
                                ;; TXT: first byte is length, rest is text
                                [(= type dns-rr-type-txt)
                                 (let ([tlen (bytevector-u8-ref rdata 0)])
                                   (utf8->string (subbytevector rdata 1 (+ 1 tlen))))]
                                ;; Default: raw bytevector
                                [else rdata])])
                (loop-a (+ j 1)
                        (+ rdstart rdlen)
                        (cons (make-dns-answer-rec name type 1 ttl data) answers)))))
          ;; Skip question: decode name, skip 4 bytes (type + class)
          (let* ([name-r (dns-decode-name bv pos)]
                 [new-pos (+ (cdr name-r) 4)])
            (loop-q (+ i 1) new-pos))))))

) ;; end library
