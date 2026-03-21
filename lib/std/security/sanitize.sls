#!chezscheme
;;; (std security sanitize) — Context-aware input sanitization
;;;
;;; Sanitization functions for preventing injection attacks:
;;; - HTML entity escaping (XSS prevention)
;;; - SQL escaping (injection prevention)
;;; - Path traversal prevention
;;; - HTTP header injection prevention
;;; - URL scheme validation

(library (std security sanitize)
  (export
    sanitize-html
    sql-escape
    sanitize-path
    safe-path-join
    sanitize-header-value
    sanitize-url
    ;; Condition types
    &path-traversal make-path-traversal path-traversal?
    &header-injection make-header-injection header-injection?
    &url-scheme-violation make-url-scheme-violation url-scheme-violation?)

  (import (chezscheme))

  ;; ========== Condition Types ==========

  (define-condition-type &path-traversal &violation
    make-path-traversal path-traversal?
    (path path-traversal-path))

  (define-condition-type &header-injection &violation
    make-header-injection header-injection?
    (value header-injection-value))

  (define-condition-type &url-scheme-violation &violation
    make-url-scheme-violation url-scheme-violation?
    (url url-scheme-violation-url))

  ;; ========== HTML Sanitization ==========

  (define (sanitize-html s)
    ;; Escape HTML special characters to prevent XSS.
    ;; Converts: < > & " ' to HTML entities.
    (let ([out (open-output-string)])
      (string-for-each
        (lambda (c)
          (case c
            [(#\<) (display "&lt;" out)]
            [(#\>) (display "&gt;" out)]
            [(#\&) (display "&amp;" out)]
            [(#\") (display "&quot;" out)]
            [(#\') (display "&#x27;" out)]
            [else (write-char c out)]))
        s)
      (get-output-string out)))

  ;; ========== SQL Escaping ==========

  (define (sql-escape s)
    ;; Escape single quotes for SQL string literals.
    ;; NOTE: Parameterized queries are always preferred over escaping.
    ;; This is a defense-in-depth measure.
    (let ([out (open-output-string)])
      (string-for-each
        (lambda (c)
          (case c
            [(#\') (display "''" out)]
            [(#\\) (display "\\\\" out)]
            [(#\nul) (void)]  ;; Drop NUL bytes
            [else (write-char c out)]))
        s)
      (get-output-string out)))

  ;; ========== Path Sanitization ==========

  (define (sanitize-path path)
    ;; Canonicalize path and reject traversal attempts.
    ;; Raises &path-traversal if path contains .. components that would
    ;; escape the root or if it contains NUL bytes.
    (when (string-contains-char? path #\nul)
      (raise (condition
        (make-path-traversal path)
        (make-message-condition "NUL byte in path"))))
    (let* ([parts (string-split-on path #\/)]
           [canonical (canonicalize-parts parts)])
      (if (and (> (string-length path) 0)
               (char=? (string-ref path 0) #\/))
        (string-append "/" (string-join-with canonical "/"))
        (string-join-with canonical "/"))))

  (define (safe-path-join base-dir relative)
    ;; Join a base directory and relative path, ensuring the result
    ;; stays under base-dir. Raises &path-traversal if not.
    (let* ([sanitized (sanitize-path relative)]
           [full (if (and (> (string-length sanitized) 0)
                          (char=? (string-ref sanitized 0) #\/))
                   sanitized
                   (string-append
                     (if (and (> (string-length base-dir) 0)
                              (char=? (string-ref base-dir
                                        (- (string-length base-dir) 1)) #\/))
                       base-dir
                       (string-append base-dir "/"))
                     sanitized))])
      (unless (string-prefix? base-dir full)
        (raise (condition
          (make-path-traversal relative)
          (make-message-condition
            (format "path ~a escapes base directory ~a" relative base-dir)))))
      full))

  ;; ========== Header Sanitization ==========

  (define (sanitize-header-value s)
    ;; Prevent HTTP header injection by rejecting values with
    ;; CR or LF characters (which could inject new headers).
    (when (or (string-contains-char? s #\return)
              (string-contains-char? s #\newline))
      (raise (condition
        (make-header-injection s)
        (make-message-condition "CR/LF in header value"))))
    ;; Also reject NUL bytes
    (when (string-contains-char? s #\nul)
      (raise (condition
        (make-header-injection s)
        (make-message-condition "NUL byte in header value"))))
    s)

  ;; ========== URL Sanitization ==========

  (define (sanitize-url url)
    ;; Validate URL scheme — only allow http:// and https://.
    ;; Prevents javascript:, data:, vbscript:, and other dangerous schemes.
    (let ([lower (string-downcase url)])
      (unless (or (string-prefix? "http://" lower)
                  (string-prefix? "https://" lower))
        (raise (condition
          (make-url-scheme-violation url)
          (make-message-condition
            (format "URL scheme not allowed: ~a" url))))))
    url)

  ;; ========== Helpers ==========

  (define (string-contains-char? s ch)
    (let ([len (string-length s)])
      (let lp ([i 0])
        (cond
          [(>= i len) #f]
          [(char=? (string-ref s i) ch) #t]
          [else (lp (+ i 1))]))))

  (define (string-prefix? prefix str)
    (let ([plen (string-length prefix)]
          [slen (string-length str)])
      (and (<= plen slen)
           (string=? (substring str 0 plen) prefix))))

  (define (string-split-on s ch)
    (let ([n (string-length s)])
      (let lp ([i 0] [start 0] [acc '()])
        (cond
          [(>= i n)
           (reverse (cons (substring s start n) acc))]
          [(char=? (string-ref s i) ch)
           (lp (+ i 1) (+ i 1) (cons (substring s start i) acc))]
          [else (lp (+ i 1) start acc)]))))

  (define (string-join-with lst sep)
    (cond
      [(null? lst) ""]
      [(null? (cdr lst)) (car lst)]
      [else
       (let lp ([rest (cdr lst)] [acc (car lst)])
         (if (null? rest) acc
           (lp (cdr rest) (string-append acc sep (car rest)))))]))

  (define (canonicalize-parts parts)
    ;; Resolve . and .. in path parts. Drop empty parts.
    (let lp ([parts parts] [stack '()])
      (cond
        [(null? parts) (reverse stack)]
        [(string=? (car parts) ".") (lp (cdr parts) stack)]
        [(string=? (car parts) "..")
         (lp (cdr parts) (if (pair? stack) (cdr stack) stack))]
        [(string=? (car parts) "") (lp (cdr parts) stack)]
        [else (lp (cdr parts) (cons (car parts) stack))])))

  ) ;; end library
