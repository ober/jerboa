#!chezscheme
;;; (std net http2) -- HTTP/2 framing and HPACK (simplified)
;;;
;;; HTTP/2 frame format (RFC 7540):
;;;   3 bytes length, 1 byte type, 1 byte flags, 4 bytes stream-id (31-bit), payload
;;;
;;; HPACK (RFC 7541):
;;;   Simplified static-table encode/decode for common headers.

(library (std net http2)
  (export
    ;; Frame type constants
    http2-frame-type-data http2-frame-type-headers http2-frame-type-settings
    http2-frame-type-ping http2-frame-type-goaway http2-frame-type-rst-stream
    http2-frame-type-window-update http2-frame-type-priority
    http2-frame-type-push-promise http2-frame-type-continuation
    ;; Frame record accessors
    http2-frame-type http2-frame-flags http2-frame-stream-id http2-frame-payload
    ;; Frame encode/decode
    http2-frame-encode http2-frame-decode
    ;; Frame constructors
    make-http2-data-frame make-http2-headers-frame make-http2-settings-frame
    make-http2-ping-frame make-http2-goaway-frame make-http2-rst-stream-frame
    make-http2-window-update-frame
    ;; HPACK
    make-hpack-context hpack-context? hpack-encode hpack-decode)

  (import (chezscheme))

  ;;; ========== Frame type constants ==========
  (define http2-frame-type-data          #x0)
  (define http2-frame-type-headers       #x1)
  (define http2-frame-type-priority      #x2)
  (define http2-frame-type-rst-stream    #x3)
  (define http2-frame-type-settings      #x4)
  (define http2-frame-type-push-promise  #x5)
  (define http2-frame-type-ping          #x6)
  (define http2-frame-type-goaway        #x7)
  (define http2-frame-type-window-update #x8)
  (define http2-frame-type-continuation  #x9)

  ;;; ========== Frame record ==========
  (define-record-type http2-frame-rec
    (fields type flags stream-id payload))

  (define (http2-frame-type      f) (http2-frame-rec-type      f))
  (define (http2-frame-flags     f) (http2-frame-rec-flags     f))
  (define (http2-frame-stream-id f) (http2-frame-rec-stream-id f))
  (define (http2-frame-payload   f) (http2-frame-rec-payload   f))

  ;;; ========== Frame encoding ==========
  ;; Wire: [length:3][type:1][flags:1][stream-id:4][payload:N]
  ;; stream-id is 31-bit (top bit reserved, always 0)
  (define (http2-frame-encode frame)
    (let* ([type      (http2-frame-rec-type      frame)]
           [flags     (http2-frame-rec-flags     frame)]
           [stream-id (http2-frame-rec-stream-id frame)]
           [payload   (http2-frame-rec-payload   frame)]
           [plen      (bytevector-length payload)]
           [total     (+ 9 plen)]
           [bv        (make-bytevector total 0)])
      ;; 3-byte length
      (bytevector-u8-set! bv 0 (bitwise-and (bitwise-arithmetic-shift-right plen 16) #xFF))
      (bytevector-u8-set! bv 1 (bitwise-and (bitwise-arithmetic-shift-right plen 8)  #xFF))
      (bytevector-u8-set! bv 2 (bitwise-and plen #xFF))
      ;; type, flags
      (bytevector-u8-set! bv 3 type)
      (bytevector-u8-set! bv 4 flags)
      ;; 4-byte stream id (31-bit, big-endian)
      (bytevector-u8-set! bv 5 (bitwise-and (bitwise-arithmetic-shift-right stream-id 24) #x7F))
      (bytevector-u8-set! bv 6 (bitwise-and (bitwise-arithmetic-shift-right stream-id 16) #xFF))
      (bytevector-u8-set! bv 7 (bitwise-and (bitwise-arithmetic-shift-right stream-id 8)  #xFF))
      (bytevector-u8-set! bv 8 (bitwise-and stream-id #xFF))
      ;; payload
      (bytevector-copy! payload 0 bv 9 plen)
      bv))

  ;;; ========== Frame decoding ==========

  (define *http2-max-frame-size* (make-parameter (* 1 1024 1024)))  ;; 1MB default

  (define (http2-frame-decode bv)
    ;; Validate minimum frame header size
    (unless (>= (bytevector-length bv) 9)
      (error 'http2-frame-decode "bytevector too short for frame header"
             (bytevector-length bv)))
    (let* ([plen (bitwise-ior
                   (bitwise-arithmetic-shift-left (bytevector-u8-ref bv 0) 16)
                   (bitwise-arithmetic-shift-left (bytevector-u8-ref bv 1) 8)
                   (bytevector-u8-ref bv 2))]
           [type  (bytevector-u8-ref bv 3)]
           [flags (bytevector-u8-ref bv 4)]
           [sid   (bitwise-ior
                    (bitwise-arithmetic-shift-left
                      (bitwise-and (bytevector-u8-ref bv 5) #x7F) 24)
                    (bitwise-arithmetic-shift-left (bytevector-u8-ref bv 6) 16)
                    (bitwise-arithmetic-shift-left (bytevector-u8-ref bv 7) 8)
                    (bytevector-u8-ref bv 8))])
      ;; Validate payload size against cap
      (when (> plen (*http2-max-frame-size*))
        (error 'http2-frame-decode "frame payload exceeds maximum size"
               plen (*http2-max-frame-size*)))
      ;; Validate bytevector contains full payload
      (unless (>= (bytevector-length bv) (+ 9 plen))
        (error 'http2-frame-decode "bytevector too short for payload"
               (bytevector-length bv) (+ 9 plen)))
      (let ([payload (let ([p (make-bytevector plen)])
                       (bytevector-copy! bv 9 p 0 plen)
                       p)])
        (make-http2-frame-rec type flags sid payload))))

  ;;; ========== Frame constructors ==========
  (define (make-http2-data-frame stream-id payload . flags)
    (make-http2-frame-rec http2-frame-type-data
                          (if (null? flags) 0 (car flags))
                          stream-id payload))

  (define (make-http2-headers-frame stream-id payload . flags)
    (make-http2-frame-rec http2-frame-type-headers
                          (if (null? flags) 4 (car flags))  ; END_HEADERS=0x4
                          stream-id payload))

  (define (make-http2-settings-frame payload . flags)
    (make-http2-frame-rec http2-frame-type-settings
                          (if (null? flags) 0 (car flags))
                          0 payload))

  (define (make-http2-ping-frame payload . flags)
    (make-http2-frame-rec http2-frame-type-ping
                          (if (null? flags) 0 (car flags))
                          0 payload))

  (define (make-http2-goaway-frame last-stream-id error-code)
    (let ([bv (make-bytevector 8 0)])
      (bytevector-u8-set! bv 0 (bitwise-and (bitwise-arithmetic-shift-right last-stream-id 24) #x7F))
      (bytevector-u8-set! bv 1 (bitwise-and (bitwise-arithmetic-shift-right last-stream-id 16) #xFF))
      (bytevector-u8-set! bv 2 (bitwise-and (bitwise-arithmetic-shift-right last-stream-id 8)  #xFF))
      (bytevector-u8-set! bv 3 (bitwise-and last-stream-id #xFF))
      (bytevector-u8-set! bv 4 (bitwise-and (bitwise-arithmetic-shift-right error-code 24) #xFF))
      (bytevector-u8-set! bv 5 (bitwise-and (bitwise-arithmetic-shift-right error-code 16) #xFF))
      (bytevector-u8-set! bv 6 (bitwise-and (bitwise-arithmetic-shift-right error-code 8)  #xFF))
      (bytevector-u8-set! bv 7 (bitwise-and error-code #xFF))
      (make-http2-frame-rec http2-frame-type-goaway 0 0 bv)))

  (define (make-http2-rst-stream-frame stream-id error-code)
    (let ([bv (make-bytevector 4 0)])
      (bytevector-u8-set! bv 0 (bitwise-and (bitwise-arithmetic-shift-right error-code 24) #xFF))
      (bytevector-u8-set! bv 1 (bitwise-and (bitwise-arithmetic-shift-right error-code 16) #xFF))
      (bytevector-u8-set! bv 2 (bitwise-and (bitwise-arithmetic-shift-right error-code 8)  #xFF))
      (bytevector-u8-set! bv 3 (bitwise-and error-code #xFF))
      (make-http2-frame-rec http2-frame-type-rst-stream 0 stream-id bv)))

  (define (make-http2-window-update-frame stream-id increment)
    (let ([bv (make-bytevector 4 0)])
      (bytevector-u8-set! bv 0 (bitwise-and (bitwise-arithmetic-shift-right increment 24) #x7F))
      (bytevector-u8-set! bv 1 (bitwise-and (bitwise-arithmetic-shift-right increment 16) #xFF))
      (bytevector-u8-set! bv 2 (bitwise-and (bitwise-arithmetic-shift-right increment 8)  #xFF))
      (bytevector-u8-set! bv 3 (bitwise-and increment #xFF))
      (make-http2-frame-rec http2-frame-type-window-update 0 stream-id bv)))

  ;;; ========== HPACK ==========
  ;; Simplified HPACK static table (RFC 7541 Appendix A, first 10 entries)
  ;; Index  Name              Value
  ;;   1    :authority        ""
  ;;   2    :method           GET
  ;;   3    :method           POST
  ;;   4    :path             /
  ;;   5    :path             /index.html
  ;;   6    :scheme           http
  ;;   7    :scheme           https
  ;;   8    :status           200
  ;;   9    :status           204
  ;;  10    :status           206

  (define hpack-static-table
    '#(("" . "")                          ; index 0 unused
       (":authority" . "")
       (":method"    . "GET")
       (":method"    . "POST")
       (":path"      . "/")
       (":path"      . "/index.html")
       (":scheme"    . "http")
       (":scheme"    . "https")
       (":status"    . "200")
       (":status"    . "204")
       (":status"    . "206")
       (":status"    . "304")
       (":status"    . "400")
       (":status"    . "404")
       (":status"    . "500")
       ("accept-charset"    . "")
       ("accept-encoding"   . "gzip, deflate")
       ("accept-language"   . "")
       ("accept-ranges"     . "")
       ("accept"            . "")
       ("access-control-allow-origin" . "")
       ("age"               . "")
       ("allow"             . "")
       ("authorization"     . "")
       ("cache-control"     . "")
       ("content-disposition" . "")
       ("content-encoding"  . "")
       ("content-language"  . "")
       ("content-length"    . "")
       ("content-location"  . "")
       ("content-range"     . "")
       ("content-type"      . "")
       ("cookie"            . "")
       ("date"              . "")
       ("etag"              . "")
       ("expect"            . "")
       ("expires"           . "")
       ("from"              . "")
       ("host"              . "")
       ("if-match"          . "")
       ("if-modified-since" . "")
       ("if-none-match"     . "")
       ("if-range"          . "")
       ("if-unmodified-since" . "")
       ("last-modified"     . "")
       ("link"              . "")
       ("location"          . "")
       ("max-forwards"      . "")
       ("proxy-authenticate" . "")
       ("proxy-authorization" . "")
       ("range"             . "")
       ("referer"           . "")
       ("refresh"           . "")
       ("retry-after"       . "")
       ("server"            . "")
       ("set-cookie"        . "")
       ("strict-transport-security" . "")
       ("transfer-encoding" . "")
       ("user-agent"        . "")
       ("vary"              . "")
       ("via"               . "")
       ("www-authenticate"  . "")))

  ;; Find static table index for (name . value) pair (1-based, 0 = not found)
  (define (hpack-static-index name value)
    (let loop ([i 1])
      (if (> i 61)
        0
        (let ([entry (vector-ref hpack-static-table i)])
          (if (and (string=? (car entry) name)
                   (string=? (cdr entry) value))
            i
            (loop (+ i 1)))))))

  ;; Find static table index for name only (value doesn't matter)
  (define (hpack-static-name-index name)
    (let loop ([i 1])
      (if (> i 61)
        0
        (if (string=? (car (vector-ref hpack-static-table i)) name)
          i
          (loop (+ i 1))))))

  ;; Encode a string as HPACK literal (length-prefixed, no Huffman)
  ;; Format: 0xxxxxxx length, then ASCII bytes
  (define (hpack-encode-string str)
    (let* ([bstr (string->utf8 str)]
           [len  (bytevector-length bstr)]
           [out  (make-bytevector (+ 1 len))])
      (bytevector-u8-set! out 0 len)  ; H=0 (no Huffman), length in 7 bits
      (bytevector-copy! bstr 0 out 1 len)
      out))

  ;; Decode a string from HPACK literal at offset, returns (string . new-offset)
  (define (hpack-decode-string bv offset)
    (let* ([b   (bytevector-u8-ref bv offset)]
           [_huff? (not (zero? (bitwise-and b #x80)))]
           [len (bitwise-and b #x7F)]
           [str (utf8->string (subbytevector bv (+ offset 1) (+ offset 1 len)))])
      (cons str (+ offset 1 len))))

  ;; Helper: extract sub-bytevector
  (define (subbytevector bv start end)
    (let* ([len (- end start)]
           [out (make-bytevector len)])
      (bytevector-copy! bv start out 0 len)
      out))

  ;; HPACK context (dynamic table as alist, max size)
  (define-record-type hpack-context-rec
    (fields (mutable dynamic-table) (mutable table-size) max-size)
    (protocol
      (lambda (new)
        (lambda (max-size)
          (new '() 0 max-size)))))

  (define (hpack-context? x) (hpack-context-rec? x))

  (define (make-hpack-context . args)
    (let ([max-size (if (null? args) 4096 (car args))])
      (make-hpack-context-rec max-size)))

  ;; Encode a list of (name . value) pairs using HPACK.
  ;; Strategy: indexed if in static table, literal with name-index if name matches,
  ;;           else literal with name string.
  (define (hpack-encode ctx headers)
    (let ([parts '()])
      (for-each
        (lambda (header)
          (let* ([name  (car header)]
                 [value (cdr header)]
                 [idx   (hpack-static-index name value)])
            (if (> idx 0)
              ;; Indexed header field: 1xxxxxxx
              (set! parts (cons (make-bytevector 1 (bitwise-ior #x80 idx)) parts))
              ;; Literal header field without indexing: 0000xxxx
              (let ([name-idx (hpack-static-name-index name)])
                (if (> name-idx 0)
                  ;; Name indexed, value literal: 0000nnnn + value
                  (let* ([name-bv (make-bytevector 1 name-idx)]
                         [val-bv  (hpack-encode-string value)])
                    (set! parts (cons val-bv (cons name-bv parts))))
                  ;; Both name and value literal: 00000000 + name + value
                  (let* ([prefix-bv (make-bytevector 1 0)]
                         [name-bv   (hpack-encode-string name)]
                         [val-bv    (hpack-encode-string value)])
                    (set! parts (cons val-bv (cons name-bv (cons prefix-bv parts))))))))))
        headers)
      ;; Concatenate all parts
      (let* ([reversed (reverse parts)]
             [total (apply + (map bytevector-length reversed))]
             [out   (make-bytevector total)]
             [pos   0])
        (for-each
          (lambda (bv)
            (let ([len (bytevector-length bv)])
              (bytevector-copy! bv 0 out pos len)
              (set! pos (+ pos len))))
          reversed)
        out)))

  ;; Decode HPACK-encoded bytevector into list of (name . value) pairs.
  (define (hpack-decode ctx bv)
    (let ([len (bytevector-length bv)]
          [result '()])
      (let loop ([pos 0])
        (when (< pos len)
          (let ([b (bytevector-u8-ref bv pos)])
            (cond
              ;; Indexed header field: 1xxxxxxx
              [(not (zero? (bitwise-and b #x80)))
               (let* ([idx   (bitwise-and b #x7F)]
                      [entry (if (and (> idx 0) (<= idx 61))
                               (vector-ref hpack-static-table idx)
                               (cons "" ""))])
                 (set! result (cons entry result))
                 (loop (+ pos 1)))]
              ;; Literal with incremental indexing: 01xxxxxx (skip for simplicity)
              [(not (zero? (bitwise-and b #x40)))
               (let* ([name-idx (bitwise-and b #x3F)]
                      [pos1 (+ pos 1)])
                 (if (> name-idx 0)
                   ;; Name from static table
                   (let* ([name  (car (vector-ref hpack-static-table name-idx))]
                          [val-r (hpack-decode-string bv pos1)]
                          [value (car val-r)]
                          [pos2  (cdr val-r)])
                     (set! result (cons (cons name value) result))
                     (loop pos2))
                   ;; Literal name
                   (let* ([name-r (hpack-decode-string bv pos1)]
                          [name   (car name-r)]
                          [pos2   (cdr name-r)]
                          [val-r  (hpack-decode-string bv pos2)]
                          [value  (car val-r)]
                          [pos3   (cdr val-r)])
                     (set! result (cons (cons name value) result))
                     (loop pos3))))]
              ;; Literal without indexing or never-indexed: 0000xxxx
              [else
               (let* ([name-idx (bitwise-and b #x0F)]
                      [pos1 (+ pos 1)])
                 (if (> name-idx 0)
                   ;; Name from static table
                   (let* ([name  (car (vector-ref hpack-static-table name-idx))]
                          [val-r (hpack-decode-string bv pos1)]
                          [value (car val-r)]
                          [pos2  (cdr val-r)])
                     (set! result (cons (cons name value) result))
                     (loop pos2))
                   ;; Literal name
                   (let* ([name-r (hpack-decode-string bv pos1)]
                          [name   (car name-r)]
                          [pos2   (cdr name-r)]
                          [val-r  (hpack-decode-string bv pos2)]
                          [value  (car val-r)]
                          [pos3   (cdr val-r)])
                     (set! result (cons (cons name value) result))
                     (loop pos3))))]))
        (reverse result)))))

) ;; end library
