#!chezscheme
;;; :std/text/json -- JSON reader/writer
;;;
;;; JSON ↔ Scheme mapping:
;;;   object  → hashtable
;;;   array   → list
;;;   string  → string
;;;   number  → number
;;;   true    → #t
;;;   false   → #f
;;;   null    → (void)

(library (std text json)
  (export read-json write-json
          string->json-object json-object->string
          *json-max-depth* *json-max-string-length*)
  (import (except (chezscheme) make-hash-table hash-table? iota 1+ 1-)
          (jerboa runtime))

  ;;;; ---- Reader ----

  (define *json-max-depth* (make-parameter 512))
  (define *json-max-string-length* (make-parameter (* 10 1024 1024)))  ;; 10MB

  (define (read-json . args)
    (let ([port (if (null? args) (current-input-port) (car args))])
      (json-read-value port 0)))

  (define (string->json-object str)
    (let ([port (open-input-string str)])
      (json-read-value port 0)))

  (define (json-skip-whitespace port)
    (let loop ()
      (let ([ch (peek-char port)])
        (when (and (char? ch) (char-whitespace? ch))
          (read-char port)
          (loop)))))

  (define (json-read-value port depth)
    (when (> depth (*json-max-depth*))
      (error 'read-json "maximum nesting depth exceeded" depth))
    (json-skip-whitespace port)
    (let ([ch (peek-char port)])
      (cond
        [(eof-object? ch) (error 'read-json "unexpected EOF")]
        [(char=? ch #\") (json-read-string port)]
        [(char=? ch #\{) (json-read-object port depth)]
        [(char=? ch #\[) (json-read-array port depth)]
        [(char=? ch #\t) (json-read-literal port "true" #t)]
        [(char=? ch #\f) (json-read-literal port "false" #f)]
        [(char=? ch #\n) (json-read-literal port "null" (void))]
        [(or (char=? ch #\-) (char-numeric? ch)) (json-read-number port)]
        [else (error 'read-json "unexpected character" ch)])))

  (define (json-read-string port)
    (read-char port) ;; consume opening "
    (let loop ([chars '()] [len 0])
      (when (> len (*json-max-string-length*))
        (error 'read-json "string exceeds maximum length" len))
      (let ([ch (read-char port)])
        (cond
          [(eof-object? ch) (error 'read-json "unterminated string")]
          [(char=? ch #\") (list->string (reverse chars))]
          [(char=? ch #\\)
           (let ([esc (read-char port)])
             (cond
               [(char=? esc #\") (loop (cons #\" chars) (+ len 1))]
               [(char=? esc #\\) (loop (cons #\\ chars) (+ len 1))]
               [(char=? esc #\/) (loop (cons #\/ chars) (+ len 1))]
               [(char=? esc #\n) (loop (cons #\newline chars) (+ len 1))]
               [(char=? esc #\t) (loop (cons #\tab chars) (+ len 1))]
               [(char=? esc #\r) (loop (cons #\return chars) (+ len 1))]
               [(char=? esc #\b) (loop (cons #\backspace chars) (+ len 1))]
               [(char=? esc #\f) (loop (cons #\xC chars) (+ len 1))]  ;; formfeed
               [(char=? esc #\u)
                ;; Read 4 hex digits with EOF and validity checks
                (let* ([c1 (read-char port)] [c2 (read-char port)]
                       [c3 (read-char port)] [c4 (read-char port)])
                  (when (or (eof-object? c1) (eof-object? c2)
                            (eof-object? c3) (eof-object? c4))
                    (error 'read-json "truncated \\uXXXX escape"))
                  (let* ([hex (string c1 c2 c3 c4)]
                         [cp (string->number hex 16)])
                    (unless cp
                      (error 'read-json "invalid hex in \\uXXXX escape" hex))
                    ;; Handle UTF-16 surrogate pairs (U+D800..U+DBFF high, U+DC00..U+DFFF low)
                    (if (and (>= cp #xD800) (<= cp #xDBFF))
                      ;; High surrogate — expect \uDCxx low surrogate
                      (let ([bs1 (read-char port)] [bs2 (read-char port)])
                        (unless (and (char? bs1) (char=? bs1 #\\)
                                     (char? bs2) (char=? bs2 #\u))
                          (error 'read-json "expected low surrogate after high surrogate"))
                        (let* ([lc1 (read-char port)] [lc2 (read-char port)]
                               [lc3 (read-char port)] [lc4 (read-char port)])
                          (when (or (eof-object? lc1) (eof-object? lc2)
                                    (eof-object? lc3) (eof-object? lc4))
                            (error 'read-json "truncated low surrogate"))
                          (let* ([lhex (string lc1 lc2 lc3 lc4)]
                                 [low (string->number lhex 16)])
                            (unless (and low (>= low #xDC00) (<= low #xDFFF))
                              (error 'read-json "invalid low surrogate" lhex))
                            (let ([full-cp (+ #x10000
                                              (* (- cp #xD800) #x400)
                                              (- low #xDC00))])
                              (loop (cons (integer->char full-cp) chars) (+ len 1))))))
                      ;; Reject lone low surrogates
                      (if (and (>= cp #xDC00) (<= cp #xDFFF))
                        (error 'read-json "unexpected low surrogate without high surrogate" hex)
                        (loop (cons (integer->char cp) chars) (+ len 1))))))]
               [else (loop (cons esc chars) (+ len 1))]))]
          [else (loop (cons ch chars) (+ len 1))]))))

  (define (json-read-object port depth)
    (read-char port) ;; consume {
    (json-skip-whitespace port)
    (let ([ht (make-hash-table)])
      (if (char=? (peek-char port) #\})
        (begin (read-char port) ht)
        (let loop ()
          (json-skip-whitespace port)
          (let ([key (json-read-string port)])
            (json-skip-whitespace port)
            (let ([colon (read-char port)])
              (unless (char=? colon #\:)
                (error 'read-json "expected ':'" colon)))
            (let ([val (json-read-value port (+ depth 1))])
              (hash-put! ht key val)
              (json-skip-whitespace port)
              (let ([ch (read-char port)])
                (cond
                  [(char=? ch #\}) ht]
                  [(char=? ch #\,) (loop)]
                  [else (error 'read-json "expected ',' or '}'" ch)]))))))))

  (define (json-read-array port depth)
    (read-char port) ;; consume [
    (json-skip-whitespace port)
    (if (char=? (peek-char port) #\])
      (begin (read-char port) '())
      (let loop ([acc '()])
        (let ([val (json-read-value port (+ depth 1))])
          (json-skip-whitespace port)
          (let ([ch (read-char port)])
            (cond
              [(char=? ch #\]) (reverse (cons val acc))]
              [(char=? ch #\,) (loop (cons val acc))]
              [else (error 'read-json "expected ',' or ']'" ch)]))))))

  (define (json-read-literal port expected value)
    (let ([n (string-length expected)])
      (let loop ([i 0])
        (if (= i n) value
          (let ([ch (read-char port)])
            (if (char=? ch (string-ref expected i))
              (loop (+ i 1))
              (error 'read-json "unexpected literal" ch)))))))

  (define (json-read-number port)
    (let loop ([chars '()])
      (let ([ch (peek-char port)])
        (if (and (char? ch)
                 (or (char-numeric? ch)
                     (memv ch '(#\. #\- #\+ #\e #\E))))
          (begin (read-char port) (loop (cons ch chars)))
          (let* ([s (list->string (reverse chars))]
                 [n (string->number s)])
            ;; Validate: must be a real number (reject complex like 1+2i),
            ;; must not have leading + (invalid JSON), and must not have
            ;; leading zeros (except 0 itself or 0.xxx).
            (unless (and n (real? n))
              (error 'read-json "invalid number" s))
            (when (and (> (string-length s) 0)
                       (char=? (string-ref s 0) #\+))
              (error 'read-json "leading + not allowed in JSON numbers" s))
            (when (and (>= (string-length s) 2)
                       (char=? (string-ref s 0) #\0)
                       (char-numeric? (string-ref s 1)))
              (error 'read-json "leading zeros not allowed in JSON numbers" s))
            n)))))

  ;;;; ---- Writer ----

  (define (write-json val . args)
    (let ([port (if (null? args) (current-output-port) (car args))])
      (json-write-value val port)))

  (define (json-object->string val)
    (let ([port (open-output-string)])
      (json-write-value val port)
      (get-output-string port)))

  (define (json-write-value val port)
    (cond
      [(string? val) (json-write-string val port)]
      [(number? val) (json-write-number val port)]
      [(eq? val #t) (display "true" port)]
      [(eq? val #f) (display "false" port)]
      [(eq? val (void)) (display "null" port)]
      [(hashtable? val) (json-write-object val port)]
      [(list? val) (json-write-array val port)]
      [(symbol? val) (json-write-string (symbol->string val) port)]
      [else (error 'write-json "cannot serialize" val)]))

  (define (json-write-string str port)
    (display #\" port)
    (string-for-each
      (lambda (ch)
        (cond
          [(char=? ch #\") (display "\\\"" port)]
          [(char=? ch #\\) (display "\\\\" port)]
          [(char=? ch #\newline) (display "\\n" port)]
          [(char=? ch #\tab) (display "\\t" port)]
          [(char=? ch #\return) (display "\\r" port)]
          [(char<? ch #\space)
           (display (format "\\u~4,'0x" (char->integer ch)) port)]
          [else (display ch port)]))
      str)
    (display #\" port))

  (define (json-write-number n port)
    (cond
      [(and (integer? n) (exact? n))
       (display n port)]
      [else
       (let ([x (inexact n)])
         ;; JSON does not support Infinity or NaN — error instead of
         ;; producing invalid JSON that downstream parsers would reject.
         (when (or (infinite? x) (nan? x))
           (error 'write-json "cannot serialize non-finite number to JSON" n))
         (display (format "~a" x) port))]))

  (define (json-write-object ht port)
    (display "{" port)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let ([len (vector-length keys)])
        (let loop ([i 0])
          (when (< i len)
            (when (> i 0) (display "," port))
            (json-write-string
              (let ([k (vector-ref keys i)])
                (if (string? k) k (format "~a" k)))
              port)
            (display ":" port)
            (json-write-value (vector-ref vals i) port)
            (loop (+ i 1))))))
    (display "}" port))

  (define (json-write-array lst port)
    (display "[" port)
    (let loop ([rest lst] [first #t])
      (when (pair? rest)
        (unless first (display "," port))
        (json-write-value (car rest) port)
        (loop (cdr rest) #f)))
    (display "]" port))

  ) ;; end library
