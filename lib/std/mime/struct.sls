#!chezscheme
;;; :std/mime/struct -- MIME message structure
;;;
;;; Provides record types for MIME messages and parts,
;;; plus multipart encoding/decoding per RFC 2046.

(library (std mime struct)
  (export
    make-mime-message
    mime-message?
    mime-headers
    mime-body
    mime-content-type
    mime-boundary
    make-mime-part
    mime-part?
    mime-part-headers
    mime-part-body
    multipart-encode
    multipart-decode)

  (import (chezscheme))

  ;; ========== Record types ==========

  ;; A MIME message has headers (alist of (name . value)) and body (string or bytevector).
  (define-record-type mime-message
    (fields headers body)
    (protocol
      (lambda (new)
        (lambda (headers body)
          (unless (list? headers)
            (error 'make-mime-message "headers must be an alist" headers))
          (unless (or (string? body) (bytevector? body))
            (error 'make-mime-message "body must be a string or bytevector" body))
          (new headers body)))))

  ;; A MIME part within a multipart message.
  (define-record-type mime-part
    (fields headers body)
    (protocol
      (lambda (new)
        (lambda (headers body)
          (unless (list? headers)
            (error 'make-mime-part "headers must be an alist" headers))
          (unless (or (string? body) (bytevector? body))
            (error 'make-mime-part "body must be a string or bytevector" body))
          (new headers body)))))

  ;; Short aliases for the record accessors
  (define mime-headers mime-message-headers)
  (define mime-body mime-message-body)

  ;; ========== Header accessors ==========

  ;; Case-insensitive header lookup from an alist.
  (define (header-ref headers name)
    (let ((name-lower (string-downcase name)))
      (let lp ((h headers))
        (cond
          ((null? h) #f)
          ((string-ci=? (caar h) name) (cdar h))
          (else (lp (cdr h)))))))

  ;; Get Content-Type from a MIME message.
  (define (mime-content-type msg)
    (header-ref (mime-message-headers msg) "Content-Type"))

  ;; Extract the boundary parameter from the Content-Type of a MIME message.
  ;; e.g. "multipart/mixed; boundary=abc123" -> "abc123"
  (define (mime-boundary msg)
    (let ((ct (mime-content-type msg)))
      (and ct (extract-boundary ct))))

  ;; Parse boundary= from Content-Type value
  (define (extract-boundary ct)
    (let ((lower (string-downcase ct)))
      (let ((pos (string-search lower "boundary=")))
        (and pos
             (let* ((start (+ pos 9))  ;; length of "boundary="
                    (rest (substring ct start (string-length ct))))
               ;; Handle quoted boundary
               (if (and (> (string-length rest) 0)
                        (char=? (string-ref rest 0) #\"))
                   (let ((end (string-index rest #\" 1)))
                     (if end
                         (substring rest 1 end)
                         (strip-params rest)))
                   (strip-params rest)))))))

  ;; Remove trailing parameters (after ; or whitespace)
  (define (strip-params str)
    (let ((len (string-length str)))
      (let lp ((i 0))
        (cond
          ((>= i len) str)
          ((or (char=? (string-ref str i) #\;)
               (char=? (string-ref str i) #\space)
               (char=? (string-ref str i) #\tab)
               (char=? (string-ref str i) #\return)
               (char=? (string-ref str i) #\newline))
           (substring str 0 i))
          (else (lp (+ i 1)))))))

  ;; String search: find needle in haystack starting at position start.
  ;; Returns index or #f.
  (define (string-search haystack needle . opt-start)
    (let ((start (if (null? opt-start) 0 (car opt-start)))
          (hlen (string-length haystack))
          (nlen (string-length needle)))
      (if (> nlen hlen) #f
          (let lp ((i start))
            (cond
              ((> (+ i nlen) hlen) #f)
              ((string-match-at? haystack needle i) i)
              (else (lp (+ i 1))))))))

  (define (string-match-at? haystack needle pos)
    (let ((nlen (string-length needle)))
      (let lp ((j 0))
        (cond
          ((>= j nlen) #t)
          ((char=? (string-ref haystack (+ pos j))
                   (string-ref needle j))
           (lp (+ j 1)))
          (else #f)))))

  ;; Find char in string starting at given position
  (define (string-index str ch . opt-start)
    (let ((start (if (null? opt-start) 0 (car opt-start)))
          (len (string-length str)))
      (let lp ((i start))
        (cond
          ((>= i len) #f)
          ((char=? (string-ref str i) ch) i)
          (else (lp (+ i 1)))))))

  ;; ========== Header serialization ==========

  ;; Format a single header line
  (define (format-header name value)
    (string-append name ": " value "\r\n"))

  ;; Format all headers from an alist
  (define (format-headers headers)
    (apply string-append
           (map (lambda (h) (format-header (car h) (cdr h)))
                headers)))

  ;; ========== Multipart encoding ==========

  ;; Encode a list of mime-parts into a multipart body string.
  ;; boundary: the boundary string (without --)
  ;; parts: list of mime-part records
  ;; Returns the full multipart body as a string.
  (define (multipart-encode boundary parts)
    (unless (string? boundary)
      (error 'multipart-encode "boundary must be a string" boundary))
    (unless (list? parts)
      (error 'multipart-encode "parts must be a list" parts))
    (let ((delim (string-append "--" boundary "\r\n"))
          (final (string-append "--" boundary "--\r\n")))
      (apply string-append
             (append
               (map (lambda (part)
                      (string-append
                        delim
                        (format-headers (mime-part-headers part))
                        "\r\n"
                        (body->string (mime-part-body part))
                        "\r\n"))
                    parts)
               (list final)))))

  ;; Convert body to string for encoding
  (define (body->string body)
    (if (string? body)
        body
        ;; bytevector: convert to latin-1 string
        (let* ((len (bytevector-length body))
               (s (make-string len)))
          (let lp ((i 0))
            (when (< i len)
              (string-set! s i (integer->char (bytevector-u8-ref body i)))
              (lp (+ i 1))))
          s)))

  ;; ========== Multipart decoding ==========

  ;; Decode a multipart body string into a list of mime-parts.
  ;; boundary: the boundary string (without --)
  ;; body: the multipart body string
  ;; Returns list of mime-part records.
  (define (multipart-decode boundary body)
    (unless (string? boundary)
      (error 'multipart-decode "boundary must be a string" boundary))
    (unless (string? body)
      (error 'multipart-decode "body must be a string" body))
    (let ((delim (string-append "--" boundary))
          (final (string-append "--" boundary "--")))
      (let ((segments (split-by-boundary body delim final)))
        (filter-map parse-segment segments))))

  ;; Split body text by boundary delimiter.
  ;; Returns list of raw segment strings (text between boundaries).
  (define (split-by-boundary body delim final)
    (let ((segments '()))
      (let lp ((pos 0) (acc '()))
        (let ((next (string-search body delim pos)))
          (if (not next)
              ;; No more boundaries; done
              (reverse acc)
              ;; Found a boundary
              (let* ((after-delim (+ next (string-length delim)))
                     ;; Check if this is the final boundary
                     (is-final? (and (<= (+ next (string-length final))
                                         (string-length body))
                                     (string-match-at? body final next))))
                (if (= pos 0)
                    ;; Skip preamble before first boundary
                    (if is-final?
                        (reverse acc)
                        (lp (skip-to-line-end body after-delim) acc))
                    ;; Collect segment between previous boundary and this one
                    (let ((segment (substring body pos next)))
                      (if is-final?
                          (reverse (cons segment acc))
                          (lp (skip-to-line-end body after-delim)
                              (cons segment acc)))))))))))

  ;; Skip past the next CRLF or LF
  (define (skip-to-line-end body pos)
    (let ((len (string-length body)))
      (let lp ((i pos))
        (cond
          ((>= i len) len)
          ((and (char=? (string-ref body i) #\return)
                (< (+ i 1) len)
                (char=? (string-ref body (+ i 1)) #\newline))
           (+ i 2))
          ((char=? (string-ref body i) #\newline)
           (+ i 1))
          (else (lp (+ i 1)))))))

  ;; Parse a segment into a mime-part.
  ;; A segment has headers separated from body by a blank line.
  (define (parse-segment text)
    (let ((blank (find-blank-line text)))
      (if blank
          (let ((header-text (substring text 0 (car blank)))
                (body-text (strip-trailing-crlf
                            (substring text (cdr blank) (string-length text)))))
            (make-mime-part (parse-headers header-text) body-text))
          ;; No blank line: treat entire text as body with no headers
          (if (> (string-length (string-trim text)) 0)
              (make-mime-part '() (strip-trailing-crlf text))
              #f))))

  ;; Find the first blank line (CRLFCRLF or LFLF).
  ;; Returns (end-of-headers . start-of-body) or #f.
  (define (find-blank-line text)
    (let ((len (string-length text)))
      (let lp ((i 0))
        (cond
          ((>= i (- len 1)) #f)
          ;; CRLFCRLF
          ((and (<= (+ i 3) len)
                (char=? (string-ref text i) #\return)
                (char=? (string-ref text (+ i 1)) #\newline)
                (char=? (string-ref text (+ i 2)) #\return)
                (char=? (string-ref text (+ i 3)) #\newline))
           (cons i (+ i 4)))
          ;; LFLF
          ((and (<= (+ i 1) len)
                (char=? (string-ref text i) #\newline)
                (char=? (string-ref text (+ i 1)) #\newline))
           (cons i (+ i 2)))
          (else (lp (+ i 1)))))))

  ;; Strip trailing CRLF or LF from segment body
  (define (strip-trailing-crlf str)
    (let ((len (string-length str)))
      (cond
        ((and (>= len 2)
              (char=? (string-ref str (- len 2)) #\return)
              (char=? (string-ref str (- len 1)) #\newline))
         (substring str 0 (- len 2)))
        ((and (>= len 1)
              (char=? (string-ref str (- len 1)) #\newline))
         (substring str 0 (- len 1)))
        (else str))))

  ;; Parse header text into an alist.
  ;; Handles continuation lines (starting with space/tab).
  (define (parse-headers text)
    (let ((lines (split-lines text)))
      (let lp ((lines lines) (acc '()))
        (if (null? lines)
            (reverse acc)
            (let ((line (car lines)))
              (if (or (= (string-length line) 0)
                      (char=? (string-ref line 0) #\space)
                      (char=? (string-ref line 0) #\tab))
                  ;; Continuation line: append to previous header value
                  (if (null? acc)
                      (lp (cdr lines) acc)  ;; skip orphan continuation
                      (let ((prev (car acc)))
                        (lp (cdr lines)
                            (cons (cons (car prev)
                                        (string-append (cdr prev) " "
                                                       (string-trim line)))
                                  (cdr acc)))))
                  ;; New header
                  (let ((colon (string-index line #\:)))
                    (if colon
                        (lp (cdr lines)
                            (cons (cons (substring line 0 colon)
                                        (string-trim
                                          (substring line (+ colon 1)
                                                     (string-length line))))
                                  acc))
                        ;; Malformed header line, skip
                        (lp (cdr lines) acc)))))))))

  ;; Split string into lines by CRLF or LF
  (define (split-lines text)
    (let ((len (string-length text)))
      (let lp ((i 0) (start 0) (acc '()))
        (cond
          ((>= i len)
           (reverse (if (> i start)
                        (cons (substring text start i) acc)
                        acc)))
          ((and (char=? (string-ref text i) #\return)
                (< (+ i 1) len)
                (char=? (string-ref text (+ i 1)) #\newline))
           (lp (+ i 2) (+ i 2)
               (cons (substring text start i) acc)))
          ((char=? (string-ref text i) #\newline)
           (lp (+ i 1) (+ i 1)
               (cons (substring text start i) acc)))
          (else (lp (+ i 1) start acc))))))

  ;; Trim leading whitespace
  (define (string-trim str)
    (let ((len (string-length str)))
      (let lp ((i 0))
        (cond
          ((>= i len) "")
          ((or (char=? (string-ref str i) #\space)
               (char=? (string-ref str i) #\tab))
           (lp (+ i 1)))
          (else (substring str i len))))))

  ;; filter-map: map and filter #f results
  (define (filter-map f lst)
    (let lp ((lst lst) (acc '()))
      (if (null? lst)
          (reverse acc)
          (let ((v (f (car lst))))
            (if v
                (lp (cdr lst) (cons v acc))
                (lp (cdr lst) acc))))))

  ) ;; end library
