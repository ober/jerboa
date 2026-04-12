#!chezscheme
;;; (std text edn) — EDN (Extensible Data Notation) reader & writer
;;;
;;; EDN is Clojure's data serialization format. This implementation
;;; maps EDN types to Jerboa types:
;;;
;;;   EDN nil        → #f (or 'nil symbol)
;;;   EDN true/false → #t/#f
;;;   EDN integers   → exact integers
;;;   EDN floats     → flonums
;;;   EDN strings    → strings
;;;   EDN keywords   → keywords (:foo → #:foo)
;;;   EDN symbols    → symbols
;;;   EDN lists      → lists
;;;   EDN vectors    → vectors
;;;   EDN maps       → hash tables (equal-hash)
;;;   EDN sets       → lists with 'edn-set tag
;;;   EDN #tag val   → tagged values via extensible handlers
;;;   EDN comments   → skipped (;; and #_)

(library (std text edn)
  (export
    ;; Reader
    read-edn string->edn read-edn-string

    ;; Writer
    write-edn edn->string write-edn-string

    ;; Tagged literal handlers
    edn-tag-readers edn-default-tag-reader
    make-tagged-value tagged-value? tagged-value-tag tagged-value-value

    ;; EDN set type
    make-edn-set edn-set? edn-set-elements)

  (import (chezscheme))

  ;; =========================================================================
  ;; Tagged values (for unknown tags)
  ;; =========================================================================

  (define-record-type tagged-value
    (fields tag value)
    (sealed #t))

  ;; =========================================================================
  ;; EDN set
  ;; =========================================================================

  (define-record-type edn-set
    (fields elements)  ;; list of elements
    (sealed #t))

  ;; =========================================================================
  ;; Tag reader registry
  ;; =========================================================================

  ;; Parameter: alist of (tag-symbol . handler-proc)
  ;; handler-proc takes one argument (the tagged value) and returns
  ;; the Scheme representation.
  (define edn-tag-readers (make-parameter '()))

  ;; Default handler for unknown tags — wraps in tagged-value record
  (define edn-default-tag-reader
    (make-parameter (lambda (tag val) (make-tagged-value tag val))))

  ;; =========================================================================
  ;; Reader
  ;; =========================================================================

  (define (read-edn port)
    (skip-whitespace+comments port)
    (let ([c (peek-char port)])
      (cond
        [(eof-object? c) (eof-object)]
        [(char=? c #\() (read-edn-list port)]
        [(char=? c #\[) (read-edn-vector port)]
        [(char=? c #\{) (read-edn-map port)]
        [(char=? c #\") (read-edn-string-literal port)]
        [(char=? c #\:) (read-edn-keyword port)]
        [(char=? c #\\) (read-edn-char port)]
        [(char=? c #\#) (read-edn-dispatch port)]
        [(or (char-numeric? c) (char=? c #\-) (char=? c #\+))
         (read-edn-number-or-symbol port)]
        [else (read-edn-symbol port)])))

  (define (skip-whitespace+comments port)
    (let loop ()
      (let ([c (peek-char port)])
        (cond
          [(eof-object? c) (void)]
          [(or (char-whitespace? c) (char=? c #\,))
           (read-char port) (loop)]
          [(char=? c #\;)
           ;; Line comment
           (let cloop ()
             (let ([ch (read-char port)])
               (unless (or (eof-object? ch) (char=? ch #\newline))
                 (cloop))))
           (loop)]
          [else (void)]))))

  (define (read-edn-list port)
    (read-char port) ;; consume (
    (let loop ([acc '()])
      (skip-whitespace+comments port)
      (let ([c (peek-char port)])
        (cond
          [(eof-object? c) (error 'read-edn "unexpected EOF in list")]
          [(char=? c #\))
           (read-char port) (reverse acc)]
          [else (loop (cons (read-edn port) acc))]))))

  (define (read-edn-vector port)
    (read-char port) ;; consume [
    (let loop ([acc '()])
      (skip-whitespace+comments port)
      (let ([c (peek-char port)])
        (cond
          [(eof-object? c) (error 'read-edn "unexpected EOF in vector")]
          [(char=? c #\])
           (read-char port) (list->vector (reverse acc))]
          [else (loop (cons (read-edn port) acc))]))))

  (define (read-edn-map port)
    (read-char port) ;; consume {
    (let ([ht (make-hashtable equal-hash equal?)])
      (let loop ()
        (skip-whitespace+comments port)
        (let ([c (peek-char port)])
          (cond
            [(eof-object? c) (error 'read-edn "unexpected EOF in map")]
            [(char=? c #\})
             (read-char port) ht]
            [else
             (let* ([key (read-edn port)]
                    [val (read-edn port)])
               (hashtable-set! ht key val)
               (loop))])))))

  (define (read-edn-string-literal port)
    (read-char port) ;; consume opening "
    (let loop ([acc '()])
      (let ([c (read-char port)])
        (cond
          [(eof-object? c) (error 'read-edn "unexpected EOF in string")]
          [(char=? c #\")
           (list->string (reverse acc))]
          [(char=? c #\\)
           (let ([esc (read-char port)])
             (loop (cons
                     (case esc
                       [(#\n) #\newline]
                       [(#\t) #\tab]
                       [(#\r) #\return]
                       [(#\\) #\\]
                       [(#\") #\"]
                       [else (error 'read-edn "unknown escape" esc)])
                     acc)))]
          [else (loop (cons c acc))]))))

  (define (read-edn-keyword port)
    (read-char port) ;; consume :
    (let ([sym (read-edn-bare-symbol port)])
      (string->symbol (string-append "#:" (symbol->string sym)))))

  (define (read-edn-char port)
    (read-char port) ;; consume backslash
    (let ([c (read-char port)])
      (cond
        [(eof-object? c) (error 'read-edn "unexpected EOF after \\")]
        [(char-alphabetic? c)
         ;; Could be named char: newline, space, tab, return
         (let loop ([acc (list c)])
           (let ([next (peek-char port)])
             (if (and (char? next) (char-alphabetic? next))
               (begin (read-char port) (loop (cons next acc)))
               (let ([name (list->string (reverse acc))])
                 (cond
                   [(string=? name "newline") #\newline]
                   [(string=? name "space") #\space]
                   [(string=? name "tab") #\tab]
                   [(string=? name "return") #\return]
                   [(= (string-length name) 1) (string-ref name 0)]
                   [else (error 'read-edn "unknown char name" name)])))))]
        [else c])))

  (define (read-edn-dispatch port)
    (read-char port) ;; consume #
    (let ([c (peek-char port)])
      (cond
        [(char=? c #\{)
         ;; Set literal #{...}
         (read-char port)
         (let loop ([acc '()])
           (skip-whitespace+comments port)
           (let ([ch (peek-char port)])
             (cond
               [(eof-object? ch) (error 'read-edn "unexpected EOF in set")]
               [(char=? ch #\})
                (read-char port) (make-edn-set (reverse acc))]
               [else (loop (cons (read-edn port) acc))])))]
        [(char=? c #\_)
         ;; Discard form
         (read-char port)
         (read-edn port) ;; read and discard
         (read-edn port)] ;; read the next real value
        [else
         ;; Tagged literal: #tag value
         (let* ([tag (read-edn-bare-symbol port)]
                [val (read-edn port)]
                [handlers (edn-tag-readers)]
                [handler (assq tag handlers)])
           (if handler
             ((cdr handler) val)
             ((edn-default-tag-reader) tag val)))])))

  (define (symbol-start? c)
    (or (char-alphabetic? c)
        (memv c '(#\. #\* #\+ #\! #\- #\_ #\? #\$ #\% #\& #\= #\< #\> #\/ #\'))))

  (define (symbol-char? c)
    (or (symbol-start? c) (char-numeric? c) (char=? c #\#) (char=? c #\:)))

  (define (read-edn-bare-symbol port)
    (let loop ([acc '()])
      (let ([c (peek-char port)])
        (if (and (char? c) (symbol-char? c))
          (begin (read-char port) (loop (cons c acc)))
          (string->symbol (list->string (reverse acc)))))))

  (define (read-edn-number-or-symbol port)
    (let ([tok (read-edn-token port)])
      (cond
        [(string=? tok "true") #t]
        [(string=? tok "false") #f]
        [(string=? tok "nil") 'nil]
        [else
         (let ([n (string->number tok)])
           (if n n (string->symbol tok)))])))

  (define (read-edn-symbol port)
    (let ([tok (read-edn-token port)])
      (cond
        [(string=? tok "true") #t]
        [(string=? tok "false") #f]
        [(string=? tok "nil") 'nil]
        [else (string->symbol tok)])))

  (define (read-edn-token port)
    (let loop ([acc '()])
      (let ([c (peek-char port)])
        (if (and (char? c) (symbol-char? c))
          (begin (read-char port) (loop (cons c acc)))
          (list->string (reverse acc))))))

  ;; Convenience: read from string
  (define (string->edn str)
    (let ([p (open-input-string str)])
      (let ([result (read-edn p)])
        (close-port p)
        result)))

  (define (read-edn-string str)
    (string->edn str))

  ;; =========================================================================
  ;; Writer
  ;; =========================================================================

  (define (write-edn obj port)
    (cond
      [(eq? obj 'nil)    (put-string port "nil")]
      [(eq? obj #t)      (put-string port "true")]
      [(eq? obj #f)      (put-string port "false")]
      [(integer? obj)    (put-string port (number->string obj))]
      [(flonum? obj)     (put-string port (number->string obj))]
      [(rational? obj)   (put-string port (number->string (inexact obj)))]
      [(string? obj)     (write-edn-string-out obj port)]
      [(char? obj)       (write-edn-char-out obj port)]
      [(symbol? obj)
       (let ([s (symbol->string obj)])
         (if (and (> (string-length s) 2)
                  (string=? (substring s 0 2) "#:"))
           ;; keyword
           (begin (put-char port #\:) (put-string port (substring s 2 (string-length s))))
           (put-string port s)))]
      [(null? obj)       (put-string port "()")]
      [(pair? obj)       (write-edn-list obj port)]
      [(vector? obj)     (write-edn-vector obj port)]
      [(hashtable? obj)  (write-edn-map obj port)]
      [(edn-set? obj)    (write-edn-set obj port)]
      [(tagged-value? obj)
       (put-char port #\#)
       (put-string port (symbol->string (tagged-value-tag obj)))
       (put-char port #\space)
       (write-edn (tagged-value-value obj) port)]
      [else (put-string port (format "~s" obj))]))

  (define (write-edn-string-out str port)
    (put-char port #\")
    (string-for-each
      (lambda (c)
        (case c
          [(#\") (put-string port "\\\"")]
          [(#\\) (put-string port "\\\\")]
          [(#\newline) (put-string port "\\n")]
          [(#\tab) (put-string port "\\t")]
          [(#\return) (put-string port "\\r")]
          [else (put-char port c)]))
      str)
    (put-char port #\"))

  (define (write-edn-char-out c port)
    (put-char port #\\)
    (case c
      [(#\newline) (put-string port "newline")]
      [(#\space) (put-string port "space")]
      [(#\tab) (put-string port "tab")]
      [(#\return) (put-string port "return")]
      [else (put-char port c)]))

  (define (write-edn-list lst port)
    (put-char port #\()
    (let loop ([l lst] [first? #t])
      (unless (null? l)
        (unless first? (put-char port #\space))
        (write-edn (car l) port)
        (loop (cdr l) #f)))
    (put-char port #\)))

  (define (write-edn-vector vec port)
    (put-char port #\[)
    (let ([n (vector-length vec)])
      (do ([i 0 (+ i 1)]) ((= i n))
        (when (> i 0) (put-char port #\space))
        (write-edn (vector-ref vec i) port)))
    (put-char port #\]))

  (define (write-edn-map ht port)
    (put-char port #\{)
    (let ([pairs (hashtable-entries ht)]
          [first? #t])
      (let-values ([(keys vals) (hashtable-entries ht)])
        (do ([i 0 (+ i 1)]) ((= i (vector-length keys)))
          (unless (= i 0) (put-string port ", "))
          (write-edn (vector-ref keys i) port)
          (put-char port #\space)
          (write-edn (vector-ref vals i) port))))
    (put-char port #\}))

  (define (write-edn-set s port)
    (put-string port "#{")
    (let loop ([elts (edn-set-elements s)] [first? #t])
      (unless (null? elts)
        (unless first? (put-char port #\space))
        (write-edn (car elts) port)
        (loop (cdr elts) #f)))
    (put-char port #\}))

  ;; Convenience: write to string
  (define (edn->string obj)
    (let ([p (open-output-string)])
      (write-edn obj p)
      (get-output-string p)))

  (define (write-edn-string obj)
    (edn->string obj))

) ;; end library
