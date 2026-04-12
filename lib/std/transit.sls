#!chezscheme
;;; (std transit) — Transit format encoding/decoding
;;;
;;; Transit is a JSON-compatible wire format that preserves rich types
;;; (keywords, symbols, sets, dates, UUIDs). Used heavily in the
;;; Clojure ecosystem for ClojureScript<->Clojure communication.
;;;
;;; Usage:
;;;   (import (std transit))
;;;   (transit-write obj port)     ;; write Transit JSON
;;;   (transit-read port)          ;; read Transit JSON
;;;   (transit->string obj)        ;; encode to string
;;;   (string->transit str)        ;; decode from string

(library (std transit)
  (export
    transit-write transit-read
    transit->string string->transit
    transit-encode transit-decode
    ;; Tagged value constructors
    transit-keyword transit-keyword?
    transit-symbol transit-symbol?
    transit-uuid transit-uuid?
    transit-instant transit-instant?
    transit-uri transit-uri?)

  (import (except (chezscheme)
                  make-hash-table hash-table? iota 1+ 1-)
          (jerboa runtime))

  ;; ================================================================
  ;; Tagged Value Types
  ;; ================================================================

  (define-record-type transit-keyword-rec
    (fields name))
  (define (transit-keyword name) (make-transit-keyword-rec name))
  (define transit-keyword? transit-keyword-rec?)

  (define-record-type transit-symbol-rec
    (fields name))
  (define (transit-symbol name) (make-transit-symbol-rec name))
  (define transit-symbol? transit-symbol-rec?)

  (define-record-type transit-uuid-rec
    (fields value))
  (define (transit-uuid value) (make-transit-uuid-rec value))
  (define transit-uuid? transit-uuid-rec?)

  (define-record-type transit-instant-rec
    (fields millis))
  (define (transit-instant millis) (make-transit-instant-rec millis))
  (define transit-instant? transit-instant-rec?)

  (define-record-type transit-uri-rec
    (fields value))
  (define (transit-uri value) (make-transit-uri-rec value))
  (define transit-uri? transit-uri-rec?)

  ;; ================================================================
  ;; Encoding: Scheme values -> Transit JSON
  ;; ================================================================

  ;; transit-encode: convert a Scheme value to a JSON-compatible
  ;; S-expression that follows Transit encoding rules.
  ;; The result can be passed to a JSON writer.
  (define (transit-encode v)
    (cond
      ;; nil/false
      [(eq? v #f) 'null]
      [(eq? v #t) #t]
      ;; Numbers
      [(and (integer? v) (exact? v) (or (> v (expt 2 53)) (< v (- (expt 2 53)))))
       (string-append "~i" (number->string v))]
      [(number? v) v]
      ;; Strings — escape if starts with ~, ^, or `
      [(string? v) (escape-string v)]
      ;; Keywords (Jerboa keyword? from runtime)
      [(keyword? v)
       (string-append "~:" (keyword->string v))]
      ;; Symbols
      [(symbol? v)
       (string-append "~$" (symbol->string v))]
      ;; Characters
      [(char? v)
       (string-append "~c" (string v))]
      ;; Transit tagged values
      [(transit-keyword? v)
       (string-append "~:" (transit-keyword-rec-name v))]
      [(transit-symbol? v)
       (string-append "~$" (transit-symbol-rec-name v))]
      [(transit-uuid? v)
       (string-append "~u" (transit-uuid-rec-value v))]
      [(transit-instant? v)
       (string-append "~m" (number->string (transit-instant-rec-millis v)))]
      [(transit-uri? v)
       (string-append "~r" (transit-uri-rec-value v))]
      ;; Vectors (Scheme vectors -> JSON arrays)
      [(vector? v)
       (vector-map transit-encode v)]
      ;; Lists -> Transit tagged list
      [(pair? v)
       (if (alist? v)
           ;; Alist -> JSON object
           (encode-map v)
           ;; Regular list -> tagged list
           (vector "~#list" (list->vector (map transit-encode v))))]
      [(null? v)
       (vector "~#list" (vector))]
      ;; Hash tables -> JSON objects (string keys) or cmap
      [(hash-table? v)
       (encode-hashtable v)]
      [else
       ;; Unknown: convert to string
       (format "~a" v)]))

  (define (escape-string s)
    (if (and (> (string-length s) 0)
             (let ([c (string-ref s 0)])
               (or (char=? c #\~) (char=? c #\^) (char=? c #\`))))
        (string-append "~" s)
        s))

  (define (alist? v)
    (and (pair? v) (pair? (car v))
         (or (null? (cdr v)) (alist? (cdr v)))))

  (define (encode-map alist)
    ;; If all keys are strings, use a JSON object
    ;; Otherwise use cmap
    (if (andmap (lambda (p) (string? (car p))) alist)
        (let ([ht (make-hashtable string-hash string=?)])
          (for-each (lambda (p)
                      (hashtable-set! ht (escape-string (car p))
                                     (transit-encode (cdr p))))
                    alist)
          ht)
        ;; cmap for non-string keys
        (let ([items '()])
          (for-each (lambda (p)
                      (set! items (cons (transit-encode (cdr p))
                                       (cons (transit-encode (car p))
                                             items))))
                    alist)
          (vector "~#cmap" (list->vector (reverse items))))))

  (define (encode-hashtable ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let ([n (vector-length keys)])
        (if (let lp ([i 0])
              (or (= i n)
                  (and (string? (vector-ref keys i))
                       (lp (+ i 1)))))
            ;; All string keys -> JSON object
            (let ([out (make-hashtable string-hash string=?)])
              (let lp ([i 0])
                (when (< i n)
                  (hashtable-set! out (escape-string (vector-ref keys i))
                                 (transit-encode (vector-ref vals i)))
                  (lp (+ i 1))))
              out)
            ;; Non-string keys -> cmap
            (let ([items '()])
              (let lp ([i 0])
                (when (< i n)
                  (set! items (cons (transit-encode (vector-ref vals i))
                                   (cons (transit-encode (vector-ref keys i))
                                         items)))
                  (lp (+ i 1))))
              (vector "~#cmap" (list->vector (reverse items))))))))

  ;; ================================================================
  ;; Decoding: Transit JSON -> Scheme values
  ;; ================================================================

  ;; transit-decode: convert a JSON-compatible S-expression (from a JSON parser)
  ;; back to rich Scheme types following Transit decoding rules.
  (define (transit-decode v)
    (cond
      [(eq? v 'null) #f]
      [(boolean? v) v]
      [(number? v) v]
      [(string? v) (decode-string v)]
      [(vector? v) (decode-vector v)]
      [(hash-table? v) (decode-object v)]
      [(hashtable? v) (decode-object v)]
      [else v]))

  (define (decode-string s)
    (cond
      [(< (string-length s) 2) s]
      [(string=? (substring s 0 2) "~:")
       ;; Keyword
       (string->symbol (string-append (substring s 2 (string-length s)) ":"))]
      [(string=? (substring s 0 2) "~$")
       ;; Symbol
       (string->symbol (substring s 2 (string-length s)))]
      [(string=? (substring s 0 2) "~u")
       ;; UUID
       (transit-uuid (substring s 2 (string-length s)))]
      [(string=? (substring s 0 2) "~m")
       ;; Instant (millis)
       (transit-instant (string->number (substring s 2 (string-length s))))]
      [(string=? (substring s 0 2) "~t")
       ;; Instant (ISO string — store as-is for now)
       (transit-instant (substring s 2 (string-length s)))]
      [(string=? (substring s 0 2) "~r")
       ;; URI
       (transit-uri (substring s 2 (string-length s)))]
      [(string=? (substring s 0 2) "~i")
       ;; Big integer
       (string->number (substring s 2 (string-length s)))]
      [(string=? (substring s 0 2) "~c")
       ;; Character
       (string-ref (substring s 2 (string-length s)) 0)]
      [(string=? (substring s 0 2) "~~")
       ;; Escaped ~
       (substring s 1 (string-length s))]
      [(string=? (substring s 0 2) "~^")
       ;; Escaped ^
       (substring s 1 (string-length s))]
      [(string=? (substring s 0 2) "~`")
       ;; Escaped `
       (substring s 1 (string-length s))]
      [else s]))

  (define (decode-vector v)
    (let ([n (vector-length v)])
      (cond
        ;; Tagged value: ["~#tag", value]
        [(and (= n 2)
              (string? (vector-ref v 0))
              (> (string-length (vector-ref v 0)) 2)
              (string=? (substring (vector-ref v 0) 0 2) "~#"))
         (let ([tag (substring (vector-ref v 0) 2 (string-length (vector-ref v 0)))]
               [payload (vector-ref v 1)])
           (cond
             [(string=? tag "set")
              ;; Set: decode elements
              (let ([elems (vector->list (if (vector? payload) payload (vector)))])
                (map transit-decode elems))]
             [(string=? tag "list")
              ;; List: decode elements
              (let ([elems (vector->list (if (vector? payload) payload (vector)))])
                (map transit-decode elems))]
             [(string=? tag "cmap")
              ;; Composite-key map
              (let ([items (vector->list payload)])
                (let lp ([rest items] [acc '()])
                  (if (or (null? rest) (null? (cdr rest)))
                      (reverse acc)
                      (lp (cddr rest)
                          (cons (cons (transit-decode (car rest))
                                      (transit-decode (cadr rest)))
                                acc)))))]
             [else
              ;; Unknown tag — return as tagged pair
              (cons (string->symbol tag) (transit-decode payload))]))]
        ;; Regular array
        [else (vector-map transit-decode v)])))

  (define (decode-object ht)
    (let ([result (make-hashtable equal-hash equal?)])
      (let-values ([(keys vals) (hashtable-entries ht)])
        (let ([n (vector-length keys)])
          (let lp ([i 0])
            (when (< i n)
              (hashtable-set! result
                (transit-decode (vector-ref keys i))
                (transit-decode (vector-ref vals i)))
              (lp (+ i 1))))))
      result))

  ;; ================================================================
  ;; High-level API: string/port I/O
  ;;
  ;; These use a minimal JSON writer/reader built-in to avoid
  ;; depending on (std text json) which may have import conflicts.
  ;; ================================================================

  ;; transit->string: encode a value to a Transit JSON string
  (define (transit->string v)
    (json-write-string (transit-encode v)))

  ;; string->transit: decode a Transit JSON string
  (define (string->transit s)
    (transit-decode (json-read-string s)))

  ;; transit-write: write Transit JSON to a port
  (define (transit-write v port)
    (put-string port (transit->string v)))

  ;; transit-read: read Transit JSON from a port
  (define (transit-read port)
    (string->transit (get-string-all port)))

  ;; ================================================================
  ;; Minimal JSON writer/reader
  ;; ================================================================

  (define (json-write-string v)
    (call-with-string-output-port
      (lambda (p) (json-write v p))))

  (define (json-write v p)
    (cond
      [(eq? v 'null) (put-string p "null")]
      [(eq? v #t) (put-string p "true")]
      [(eq? v #f) (put-string p "false")]
      [(and (integer? v) (exact? v)) (put-string p (number->string v))]
      [(number? v) (put-string p (number->string (inexact v)))]
      [(string? v) (json-write-str v p)]
      [(vector? v)
       (put-char p #\[)
       (let ([n (vector-length v)])
         (let lp ([i 0])
           (when (< i n)
             (when (> i 0) (put-char p #\,))
             (json-write (vector-ref v i) p)
             (lp (+ i 1)))))
       (put-char p #\])]
      [(hashtable? v)
       (put-char p #\{)
       (let-values ([(keys vals) (hashtable-entries v)])
         (let ([n (vector-length keys)])
           (let lp ([i 0])
             (when (< i n)
               (when (> i 0) (put-char p #\,))
               (json-write-str (if (string? (vector-ref keys i))
                                   (vector-ref keys i)
                                   (format "~a" (vector-ref keys i)))
                               p)
               (put-char p #\:)
               (json-write (vector-ref vals i) p)
               (lp (+ i 1))))))
       (put-char p #\})]
      [(pair? v)
       ;; Alist -> object
       (put-char p #\{)
       (let lp ([rest v] [first? #t])
         (unless (null? rest)
           (unless first? (put-char p #\,))
           (json-write-str (format "~a" (caar rest)) p)
           (put-char p #\:)
           (json-write (cdar rest) p)
           (lp (cdr rest) #f)))
       (put-char p #\})]
      [else (json-write-str (format "~a" v) p)]))

  (define (json-write-str s p)
    (put-char p #\")
    (let ([n (string-length s)])
      (let lp ([i 0])
        (when (< i n)
          (let ([c (string-ref s i)])
            (cond
              [(char=? c #\") (put-string p "\\\"")]
              [(char=? c #\\) (put-string p "\\\\")]
              [(char=? c #\newline) (put-string p "\\n")]
              [(char=? c #\return) (put-string p "\\r")]
              [(char=? c #\tab) (put-string p "\\t")]
              [else (put-char p c)]))
          (lp (+ i 1)))))
    (put-char p #\"))

  ;; Minimal JSON reader
  (define (json-read-string s)
    (let ([p (open-string-input-port s)])
      (json-read-value p)))

  (define (json-read-value p)
    (skip-ws p)
    (let ([c (lookahead-char p)])
      (cond
        [(eof-object? c) (error 'json-read "unexpected EOF")]
        [(char=? c #\{) (json-read-object p)]
        [(char=? c #\[) (json-read-array p)]
        [(char=? c #\") (json-read-str p)]
        [(or (char=? c #\-) (char-numeric? c)) (json-read-number p)]
        [(char=? c #\t) (read-literal p "true") #t]
        [(char=? c #\f) (read-literal p "false") #f]
        [(char=? c #\n) (read-literal p "null") 'null]
        [else (error 'json-read "unexpected char" c)])))

  (define (skip-ws p)
    (let lp ()
      (let ([c (lookahead-char p)])
        (when (and (not (eof-object? c)) (char-whitespace? c))
          (get-char p) (lp)))))

  (define (json-read-object p)
    (get-char p)  ;; consume {
    (let ([ht (make-hashtable string-hash string=?)])
      (skip-ws p)
      (unless (char=? (lookahead-char p) #\})
        (let lp ()
          (skip-ws p)
          (let ([key (json-read-str p)])
            (skip-ws p)
            (get-char p)  ;; consume :
            (let ([val (json-read-value p)])
              (hashtable-set! ht key val)
              (skip-ws p)
              (let ([c (lookahead-char p)])
                (when (char=? c #\,)
                  (get-char p) (lp)))))))
      (get-char p)  ;; consume }
      ht))

  (define (json-read-array p)
    (get-char p)  ;; consume [
    (let lp ([acc '()])
      (skip-ws p)
      (if (char=? (lookahead-char p) #\])
          (begin (get-char p)
                 (list->vector (reverse acc)))
          (let ([v (json-read-value p)])
            (skip-ws p)
            (when (char=? (lookahead-char p) #\,)
              (get-char p))
            (lp (cons v acc))))))

  (define (json-read-str p)
    (get-char p)  ;; consume "
    (let ([out (open-output-string)])
      (let lp ()
        (let ([c (get-char p)])
          (cond
            [(char=? c #\") (get-output-string out)]
            [(char=? c #\\)
             (let ([esc (get-char p)])
               (cond
                 [(char=? esc #\") (put-char out #\")]
                 [(char=? esc #\\) (put-char out #\\)]
                 [(char=? esc #\n) (put-char out #\newline)]
                 [(char=? esc #\r) (put-char out #\return)]
                 [(char=? esc #\t) (put-char out #\tab)]
                 [(char=? esc #\/) (put-char out #\/)]
                 [(char=? esc #\u)
                  (let ([hex (get-string-n p 4)])
                    (put-char out (integer->char (string->number hex 16))))]
                 [else (put-char out esc)]))
             (lp)]
            [else (put-char out c) (lp)])))))

  (define (json-read-number p)
    (let ([out (open-output-string)])
      (let lp ()
        (let ([c (lookahead-char p)])
          (when (and (not (eof-object? c))
                     (or (char-numeric? c)
                         (char=? c #\-)
                         (char=? c #\.)
                         (char=? c #\e)
                         (char=? c #\E)
                         (char=? c #\+)))
            (put-char out (get-char p))
            (lp))))
      (string->number (get-output-string out))))

  (define (read-literal p expected)
    (let ([n (string-length expected)])
      (let lp ([i 0])
        (when (< i n)
          (let ([c (get-char p)])
            (unless (char=? c (string-ref expected i))
              (error 'json-read "unexpected char in literal" c expected)))
          (lp (+ i 1))))))

) ;; end library
