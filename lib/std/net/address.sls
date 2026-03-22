#!chezscheme
;;; :std/net/address -- Network address parsing and formatting
;;;
;;; Parse and format host:port addresses. Supports IPv4, IPv6 ([::1]:port),
;;; and hostname:port formats.

(library (std net address)
  (export
    parse-address address->string
    address-host address-port
    make-address address?
    ipv4? ipv6? hostname?
    resolve-hostname)

  (import (chezscheme))

  ;; ========== Address record ==========

  (define-record-type address
    (fields host port)
    (sealed #t))

  ;; ========== Parsing ==========

  (define (parse-address str)
    ;; Parse "host:port", "[::1]:port", or "hostname:port"
    (cond
      ;; IPv6: [addr]:port
      [(and (> (string-length str) 0)
            (char=? (string-ref str 0) #\[))
       (let ([close (string-find str #\])])
         (unless close
           (error 'parse-address "missing ']' in IPv6 address" str))
         (let ([host (substring str 1 close)]
               [rest (substring str (+ close 1) (string-length str))])
           (if (and (> (string-length rest) 0)
                    (char=? (string-ref rest 0) #\:))
             (let ([port (string->number (substring rest 1 (string-length rest)))])
               (unless port
                 (error 'parse-address "invalid port" str))
               (make-address host port))
             (make-address host 0))))]
      ;; host:port — find last colon (handles IPv4 and hostnames)
      [else
       (let ([colon (string-find-last str #\:)])
         (if colon
           (let ([host (substring str 0 colon)]
                 [port (string->number
                         (substring str (+ colon 1) (string-length str)))])
             (unless port
               (error 'parse-address "invalid port" str))
             (make-address host port))
           (make-address str 0)))])) ;; close if, let, else-bracket, cond, define

  (define (address->string addr)
    (let ([host (address-host addr)]
          [port (address-port addr)])
      (if (ipv6? host)
        (format "[~a]:~a" host port)
        (format "~a:~a" host port))))

  ;; ========== Classification ==========

  (define (ipv4? str)
    ;; Simple check: contains dots and only digits/dots
    (and (string? str)
         (> (string-length str) 0)
         (string-find str #\.)
         (string-every (lambda (c) (or (char-numeric? c) (char=? c #\.))) str)))

  (define (ipv6? str)
    ;; Contains colons — distinguishes from hostname
    (and (string? str)
         (> (string-length str) 0)
         (string-find str #\:)))

  (define (hostname? str)
    (and (string? str)
         (> (string-length str) 0)
         (not (ipv4? str))
         (not (ipv6? str))))

  ;; ========== Resolution ==========

  (define (resolve-hostname host)
    ;; Placeholder: returns host as-is.
    ;; Full implementation would use getaddrinfo FFI.
    host)

  ;; ========== Helpers ==========

  (define (string-find str ch)
    (let ([len (string-length str)])
      (let lp ([i 0])
        (cond
          [(= i len) #f]
          [(char=? (string-ref str i) ch) i]
          [else (lp (+ i 1))]))))

  (define (string-find-last str ch)
    (let lp ([i (- (string-length str) 1)])
      (cond
        [(< i 0) #f]
        [(char=? (string-ref str i) ch) i]
        [else (lp (- i 1))])))

  (define (string-every pred str)
    (let ([len (string-length str)])
      (let lp ([i 0])
        (or (= i len)
            (and (pred (string-ref str i))
                 (lp (+ i 1)))))))

  ) ;; end library
