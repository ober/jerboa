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
          string->json-object json-object->string)
  (import (except (chezscheme) make-hash-table hash-table? iota 1+ 1-)
          (jerboa runtime))

  ;;;; ---- Reader ----

  (define (read-json . args)
    (let ([port (if (null? args) (current-input-port) (car args))])
      (json-read-value port)))

  (define (string->json-object str)
    (let ([port (open-input-string str)])
      (json-read-value port)))

  (define (json-skip-whitespace port)
    (let loop ()
      (let ([ch (peek-char port)])
        (when (and (char? ch) (char-whitespace? ch))
          (read-char port)
          (loop)))))

  (define (json-read-value port)
    (json-skip-whitespace port)
    (let ([ch (peek-char port)])
      (cond
        [(eof-object? ch) (error 'read-json "unexpected EOF")]
        [(char=? ch #\") (json-read-string port)]
        [(char=? ch #\{) (json-read-object port)]
        [(char=? ch #\[) (json-read-array port)]
        [(char=? ch #\t) (json-read-literal port "true" #t)]
        [(char=? ch #\f) (json-read-literal port "false" #f)]
        [(char=? ch #\n) (json-read-literal port "null" (void))]
        [(or (char=? ch #\-) (char-numeric? ch)) (json-read-number port)]
        [else (error 'read-json "unexpected character" ch)])))

  (define (json-read-string port)
    (read-char port) ;; consume opening "
    (let loop ([chars '()])
      (let ([ch (read-char port)])
        (cond
          [(eof-object? ch) (error 'read-json "unterminated string")]
          [(char=? ch #\") (list->string (reverse chars))]
          [(char=? ch #\\)
           (let ([esc (read-char port)])
             (cond
               [(char=? esc #\") (loop (cons #\" chars))]
               [(char=? esc #\\) (loop (cons #\\ chars))]
               [(char=? esc #\/) (loop (cons #\/ chars))]
               [(char=? esc #\n) (loop (cons #\newline chars))]
               [(char=? esc #\t) (loop (cons #\tab chars))]
               [(char=? esc #\r) (loop (cons #\return chars))]
               [(char=? esc #\b) (loop (cons #\backspace chars))]
               [(char=? esc #\f) (loop (cons #\xC chars))]  ;; formfeed
               [(char=? esc #\u)
                (let* ([hex (string (read-char port) (read-char port)
                                    (read-char port) (read-char port))]
                       [cp (string->number hex 16)])
                  (loop (cons (integer->char cp) chars)))]
               [else (loop (cons esc chars))]))]
          [else (loop (cons ch chars))]))))

  (define (json-read-object port)
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
            (let ([val (json-read-value port)])
              (hash-put! ht key val)
              (json-skip-whitespace port)
              (let ([ch (read-char port)])
                (cond
                  [(char=? ch #\}) ht]
                  [(char=? ch #\,) (loop)]
                  [else (error 'read-json "expected ',' or '}'" ch)]))))))))

  (define (json-read-array port)
    (read-char port) ;; consume [
    (json-skip-whitespace port)
    (if (char=? (peek-char port) #\])
      (begin (read-char port) '())
      (let loop ([acc '()])
        (let ([val (json-read-value port)])
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
          (let ([s (list->string (reverse chars))])
            (or (string->number s)
                (error 'read-json "invalid number" s)))))))

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
    (if (and (integer? n) (exact? n))
      (display n port)
      (display (format "~a" (inexact n)) port)))

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
