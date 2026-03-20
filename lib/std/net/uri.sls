#!chezscheme
;;; :std/net/uri -- URI parsing and encoding

(library (std net uri)
  (export uri-parse
          uri-scheme uri-host uri-port uri-path
          uri-query uri-fragment uri-userinfo
          uri-encode uri-decode
          uri->string
          query-string->alist
          alist->query-string)
  (import (chezscheme))

  ;; URI record
  (define-record-type uri
    (fields scheme userinfo host port path query fragment)
    (protocol
      (lambda (new)
        (lambda (scheme userinfo host port path query fragment)
          (new scheme userinfo host port path query fragment)))))

  ;; Parse a URI string into a uri record.
  ;; Format: scheme://userinfo@host:port/path?query#fragment
  (define (uri-parse str)
    (let* ([len (string-length str)]
           [pos 0]
           [scheme #f] [userinfo #f] [host #f]
           [port #f] [path ""] [query #f] [fragment #f])
      ;; helper: find char starting at i, return index or #f
      (define (find-char c i)
        (let lp ([j i])
          (cond [(>= j len) #f]
                [(char=? (string-ref str j) c) j]
                [else (lp (+ j 1))])))
      ;; helper: substring
      (define (sub start end)
        (substring str start end))

      ;; Parse fragment (from end)
      (let ([hash-pos (find-char #\# pos)])
        (when hash-pos
          (set! fragment (sub (+ hash-pos 1) len))
          (set! len hash-pos)))

      ;; Parse query
      (let ([q-pos (find-char #\? pos)])
        (when q-pos
          (set! query (sub (+ q-pos 1) len))
          (set! len q-pos)))

      ;; Parse scheme
      (let ([colon-pos (find-char #\: pos)])
        (when (and colon-pos
                   (< (+ colon-pos 2) len)
                   (char=? (string-ref str (+ colon-pos 1)) #\/)
                   (char=? (string-ref str (+ colon-pos 2)) #\/))
          (set! scheme (sub pos colon-pos))
          (set! pos (+ colon-pos 3))))

      ;; If we had a scheme, parse authority
      (when scheme
        ;; Find end of authority (next / or end)
        (let ([slash-pos (find-char #\/ pos)])
          (let* ([auth-end (or slash-pos len)]
                 [auth (sub pos auth-end)])
            ;; Parse userinfo@
            (let ([at-pos (let lp ([j 0])
                            (cond [(>= j (string-length auth)) #f]
                                  [(char=? (string-ref auth j) #\@) j]
                                  [else (lp (+ j 1))]))])
              (let ([host-start (if at-pos
                                  (begin
                                    (set! userinfo (substring auth 0 at-pos))
                                    (+ at-pos 1))
                                  0)])
                ;; Parse host:port
                (let ([colon (let lp ([j host-start])
                               (cond [(>= j (string-length auth)) #f]
                                     [(char=? (string-ref auth j) #\:) j]
                                     [else (lp (+ j 1))]))])
                  (if colon
                    (begin
                      (set! host (substring auth host-start colon))
                      (set! port (string->number
                                   (substring auth (+ colon 1)
                                              (string-length auth)))))
                    (set! host (substring auth host-start
                                          (string-length auth)))))))
            ;; Remaining is path
            (when slash-pos
              (set! path (sub slash-pos len))))))

      ;; No scheme -- treat entire remaining as path
      (unless scheme
        (set! path (sub pos len)))

      (make-uri scheme userinfo host port path query fragment)))

  ;; Percent-encoding
  (define (unreserved-char? c)
    (or (char-alphabetic? c)
        (char-numeric? c)
        (memv c '(#\- #\_ #\. #\~))))

  (define (uri-encode str)
    (let ([out (open-output-string)])
      (string-for-each
        (lambda (c)
          (if (unreserved-char? c)
            (write-char c out)
            (let ([b (char->integer c)])
              (if (< b 128)
                (begin
                  (write-char #\% out)
                  (let ([hex (number->string b 16)])
                    (when (< b 16) (write-char #\0 out))
                    (display (string-upcase hex) out)))
                ;; Multi-byte: encode UTF-8 bytes
                (let ([bv (string->utf8 (string c))])
                  (let lp ([i 0])
                    (when (< i (bytevector-length bv))
                      (write-char #\% out)
                      (let ([hex (number->string (bytevector-u8-ref bv i) 16)])
                        (when (< (bytevector-u8-ref bv i) 16)
                          (write-char #\0 out))
                        (display (string-upcase hex) out))
                      (lp (+ i 1)))))))))
        str)
      (get-output-string out)))

  (define (hex-digit? c)
    (or (char-numeric? c)
        (memv (char-downcase c) '(#\a #\b #\c #\d #\e #\f))))

  (define (hex-value c)
    (let ([n (char->integer (char-downcase c))])
      (if (>= n (char->integer #\a))
        (+ 10 (- n (char->integer #\a)))
        (- n (char->integer #\0)))))

  (define (uri-decode str)
    (let ([out (open-output-string)]
          [len (string-length str)])
      (let lp ([i 0])
        (when (< i len)
          (let ([c (string-ref str i)])
            (cond
              [(and (char=? c #\%)
                    (< (+ i 2) len)
                    (hex-digit? (string-ref str (+ i 1)))
                    (hex-digit? (string-ref str (+ i 2))))
               (write-char
                 (integer->char
                   (+ (* 16 (hex-value (string-ref str (+ i 1))))
                      (hex-value (string-ref str (+ i 2)))))
                 out)
               (lp (+ i 3))]
              [(char=? c #\+)
               (write-char #\space out)
               (lp (+ i 1))]
              [else
               (write-char c out)
               (lp (+ i 1))]))))
      (get-output-string out)))

  ;; Reconstruct URI string from record
  (define (uri->string u)
    (let ([out (open-output-string)])
      (when (uri-scheme u)
        (display (uri-scheme u) out)
        (display "://" out))
      (when (uri-userinfo u)
        (display (uri-userinfo u) out)
        (display "@" out))
      (when (uri-host u)
        (display (uri-host u) out))
      (when (uri-port u)
        (display ":" out)
        (display (uri-port u) out))
      (display (uri-path u) out)
      (when (uri-query u)
        (display "?" out)
        (display (uri-query u) out))
      (when (uri-fragment u)
        (display "#" out)
        (display (uri-fragment u) out))
      (get-output-string out)))

  ;; Query string parsing
  (define (query-string->alist qs)
    (if (or (not qs) (string=? qs ""))
      '()
      (let lp ([pairs (string-split qs #\&)]
               [acc '()])
        (if (null? pairs)
          (reverse acc)
          (let* ([pair (car pairs)]
                 [eq-pos (let scan ([j 0])
                           (cond [(>= j (string-length pair)) #f]
                                 [(char=? (string-ref pair j) #\=) j]
                                 [else (scan (+ j 1))]))])
            (lp (cdr pairs)
                (cons (if eq-pos
                        (cons (uri-decode (substring pair 0 eq-pos))
                              (uri-decode (substring pair (+ eq-pos 1)
                                                     (string-length pair))))
                        (cons (uri-decode pair) ""))
                      acc)))))))

  ;; Helper: split string by separator character
  (define (string-split str sep)
    (let ([len (string-length str)])
      (let lp ([i 0] [start 0] [acc '()])
        (cond
          [(>= i len)
           (reverse (cons (substring str start len) acc))]
          [(char=? (string-ref str i) sep)
           (lp (+ i 1) (+ i 1)
               (cons (substring str start i) acc))]
          [else (lp (+ i 1) start acc)]))))

  (define (alist->query-string alist)
    (let ([out (open-output-string)])
      (let lp ([pairs alist] [first? #t])
        (unless (null? pairs)
          (unless first? (display "&" out))
          (display (uri-encode (car (car pairs))) out)
          (display "=" out)
          (display (uri-encode (cdr (car pairs))) out)
          (lp (cdr pairs) #f)))
      (get-output-string out)))

  ) ;; end library
