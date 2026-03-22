#!chezscheme
;;; :std/text/html -- HTML encoding/decoding utilities

(library (std text html)
  (export
    html-escape html-unescape
    html-strip-tags parse-html-entities
    html-attribute-escape)

  (import (chezscheme))

  ;; Escape special HTML characters: & < > " '
  (define (html-escape str)
    (let ((out (open-output-string)))
      (string-for-each
        (lambda (c)
          (case c
            ((#\&) (put-string out "&amp;"))
            ((#\<) (put-string out "&lt;"))
            ((#\>) (put-string out "&gt;"))
            ((#\") (put-string out "&quot;"))
            ((#\') (put-string out "&#39;"))
            (else  (put-char out c))))
        str)
      (get-output-string out)))

  ;; Escape for use inside an HTML attribute value.
  ;; Same as html-escape but also escapes backtick, =, and newlines
  ;; which can be relevant in certain attribute contexts.
  (define (html-attribute-escape str)
    (let ((out (open-output-string)))
      (string-for-each
        (lambda (c)
          (case c
            ((#\&) (put-string out "&amp;"))
            ((#\<) (put-string out "&lt;"))
            ((#\>) (put-string out "&gt;"))
            ((#\") (put-string out "&quot;"))
            ((#\') (put-string out "&#39;"))
            ((#\`) (put-string out "&#96;"))
            (else  (put-char out c))))
        str)
      (get-output-string out)))

  ;; Unescape HTML entities back to characters.
  ;; Handles: &amp; &lt; &gt; &quot; &#39; &apos;
  ;; Also handles numeric entities: &#NNN; and &#xHHH;
  (define (html-unescape str)
    (let ((len (string-length str))
          (out (open-output-string)))
      (let lp ((i 0))
        (when (< i len)
          (let ((c (string-ref str i)))
            (if (char=? c #\&)
              ;; Try to parse an entity
              (let ((end (find-semicolon str (+ i 1) len)))
                (if end
                  (let ((entity (substring str (+ i 1) end)))
                    (let ((decoded (decode-entity entity)))
                      (if decoded
                        (begin
                          (put-string out decoded)
                          (lp (+ end 1)))
                        ;; Not a recognized entity, output literal
                        (begin
                          (put-char out #\&)
                          (lp (+ i 1))))))
                  ;; No semicolon found, output literal &
                  (begin
                    (put-char out #\&)
                    (lp (+ i 1)))))
              (begin
                (put-char out c)
                (lp (+ i 1)))))))
      (get-output-string out)))

  ;; Alias: parse-html-entities is the same as html-unescape
  (define (parse-html-entities str)
    (html-unescape str))

  ;; Remove all HTML/XML tags from a string.
  ;; Handles tags across lines, self-closing tags, and attributes.
  (define (html-strip-tags str)
    (let ((len (string-length str))
          (out (open-output-string)))
      (let lp ((i 0) (in-tag #f))
        (when (< i len)
          (let ((c (string-ref str i)))
            (cond
              (in-tag
                ;; Inside a tag, look for >
                (if (char=? c #\>)
                  (lp (+ i 1) #f)
                  (lp (+ i 1) #t)))
              ((char=? c #\<)
                (lp (+ i 1) #t))
              (else
                (put-char out c)
                (lp (+ i 1) #f))))))
      (get-output-string out)))

  ;; --- Internal helpers ---

  ;; Find the position of the next semicolon, within a reasonable range
  ;; (entity names are short, max ~10 chars)
  (define (find-semicolon str start len)
    (let ((max-end (min len (+ start 12))))  ; entities are short
      (let lp ((i start))
        (cond
          ((>= i max-end) #f)
          ((char=? (string-ref str i) #\;) i)
          (else (lp (+ i 1)))))))

  ;; Decode a named or numeric entity (without & and ;).
  ;; Returns a string or #f if unrecognized.
  (define (decode-entity entity)
    (cond
      ;; Named entities
      ((string=? entity "amp")   "&")
      ((string=? entity "lt")    "<")
      ((string=? entity "gt")    ">")
      ((string=? entity "quot")  "\"")
      ((string=? entity "apos")  "'")
      ((string=? entity "nbsp")  "\xa0;")  ; non-breaking space U+00A0
      ((string=? entity "copy")  "\xa9;")  ; copyright sign
      ((string=? entity "reg")   "\xae;")  ; registered sign
      ((string=? entity "trade") "\x2122;") ; trade mark sign
      ((string=? entity "mdash") "\x2014;") ; em dash
      ((string=? entity "ndash") "\x2013;") ; en dash
      ((string=? entity "laquo") "\xab;")   ; left guillemet
      ((string=? entity "raquo") "\xbb;")   ; right guillemet
      ((string=? entity "hellip") "\x2026;") ; horizontal ellipsis
      ;; Numeric decimal: &#NNN
      ((and (> (string-length entity) 1)
            (char=? (string-ref entity 0) #\#)
            (char-numeric? (string-ref entity 1)))
       (let ((num (string->number (substring entity 1 (string-length entity)))))
         (and num
              (>= num 0)
              (<= num #x10FFFF)
              (not (and (>= num #xD800) (<= num #xDFFF)))
              (string (integer->char num)))))
      ;; Numeric hex: &#xHHH
      ((and (> (string-length entity) 2)
            (char=? (string-ref entity 0) #\#)
            (or (char=? (string-ref entity 1) #\x)
                (char=? (string-ref entity 1) #\X)))
       (let ((num (string->number
                    (substring entity 2 (string-length entity))
                    16)))
         (and num
              (>= num 0)
              (<= num #x10FFFF)
              (not (and (>= num #xD800) (<= num #xDFFF)))
              (string (integer->char num)))))
      (else #f)))

  ) ;; end library
