#!chezscheme
;;; (std net security-headers) — HTTP security response headers
;;;
;;; Middleware that adds standard security headers to HTTP responses.
;;; Prevents XSS, clickjacking, MIME sniffing, and other common attacks.

(library (std net security-headers)
  (export
    default-security-headers
    make-security-headers
    apply-security-headers
    with-security-headers
    csp-header
    hsts-header)

  (import (chezscheme))

  ;; ========== Default Headers ==========

  (define default-security-headers
    '(("X-Content-Type-Options" . "nosniff")
      ("X-Frame-Options" . "DENY")
      ("X-XSS-Protection" . "0")  ;; Disabled — CSP is the modern solution
      ("Referrer-Policy" . "strict-origin-when-cross-origin")
      ("Permissions-Policy" . "geolocation=(), camera=(), microphone=()")
      ("Cache-Control" . "no-store")
      ("Content-Security-Policy" . "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; frame-ancestors 'none'")))

  ;; ========== Custom Headers ==========

  (define (make-security-headers . opts)
    ;; Create a custom set of security headers.
    ;; opts: keyword list overriding defaults
    ;; e.g., (make-security-headers 'csp: "default-src 'none'" 'frame: "SAMEORIGIN")
    (let loop ([o opts] [headers default-security-headers])
      (if (or (null? o) (null? (cdr o)))
        headers
        (let ([key (car o)] [val (cadr o)])
          (loop (cddr o)
                (case key
                  [(csp:) (alist-set headers "Content-Security-Policy" val)]
                  [(frame:) (alist-set headers "X-Frame-Options" val)]
                  [(referrer:) (alist-set headers "Referrer-Policy" val)]
                  [(permissions:) (alist-set headers "Permissions-Policy" val)]
                  [(cache:) (alist-set headers "Cache-Control" val)]
                  [(hsts:) (alist-set headers "Strict-Transport-Security" val)]
                  [else headers]))))))

  ;; ========== Apply Headers ==========

  (define (apply-security-headers response-headers . opts)
    ;; Add security headers to an existing response header alist.
    ;; Does NOT override headers already present in response.
    (let ([sec-headers (if (pair? opts) (car opts) default-security-headers)])
      (fold-left
        (lambda (headers pair)
          (let ([name (car pair)] [val (cdr pair)])
            (if (assoc name headers)
              headers  ;; Don't override existing
              (cons pair headers))))
        response-headers
        sec-headers)))

  ;; ========== Middleware Wrapper ==========

  (define (with-security-headers handler . opts)
    ;; Wrap an HTTP handler to add security headers.
    ;; handler: (lambda (request) -> (status headers body))
    ;; Returns a new handler that adds security headers to the response.
    (let ([sec-headers (if (pair? opts) (car opts) default-security-headers)])
      (lambda (request)
        (let ([response (handler request)])
          (if (and (list? response) (>= (length response) 3))
            (let ([status (car response)]
                  [headers (cadr response)]
                  [body (caddr response)])
              (list status (apply-security-headers headers sec-headers) body))
            response)))))

  ;; ========== Content Security Policy Builder ==========

  (define (csp-header . directives)
    ;; Build a Content-Security-Policy header value.
    ;; directives: flat keyword list
    ;; e.g., (csp-header 'default-src: "'self'" 'script-src: "'self' cdn.example.com")
    (let loop ([d directives] [parts '()])
      (if (or (null? d) (null? (cdr d)))
        (string-join-parts (reverse parts) "; ")
        (let* ([key (car d)]
               [val (cadr d)]
               [name (let ([s (symbol->string key)])
                       (if (and (> (string-length s) 0)
                                (char=? (string-ref s (- (string-length s) 1)) #\:))
                         (substring s 0 (- (string-length s) 1))
                         s))])
          (loop (cddr d) (cons (string-append name " " val) parts))))))

  ;; ========== HSTS Header Builder ==========

  (define (hsts-header max-age . opts)
    ;; Build a Strict-Transport-Security header value.
    (let ([include-subdomains (memq 'include-subdomains opts)]
          [preload (memq 'preload opts)])
      (string-append "max-age=" (number->string max-age)
        (if include-subdomains "; includeSubDomains" "")
        (if preload "; preload" ""))))

  ;; ========== Helpers ==========

  (define (alist-set alist key val)
    (cons (cons key val)
          (remove-matching (lambda (pair) (string=? (car pair) key)) alist)))

  (define (remove-matching pred lst)
    (let loop ([l lst] [acc '()])
      (if (null? l) (reverse acc)
        (loop (cdr l) (if (pred (car l)) acc (cons (car l) acc))))))

  (define (string-join-parts lst sep)
    (cond
      [(null? lst) ""]
      [(null? (cdr lst)) (car lst)]
      [else (let loop ([rest (cdr lst)] [acc (car lst)])
              (if (null? rest) acc
                (loop (cdr rest) (string-append acc sep (car rest)))))]))

  ) ;; end library
