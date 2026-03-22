#!chezscheme
;;; (std io delimited) — Delimited text I/O
;;;
;;; Utilities for reading and writing text delimited by specific characters
;;; or patterns. Works with textual ports.

(library (std io delimited)
  (export
    read-delimited read-until read-line*
    read-paragraph write-delimited
    read-fields read-record)

  (import (chezscheme))

  (define (read-delimited port delimiters)
    ;; Read from textual port until any char in delimiter string is found.
    ;; Returns (values accumulated-string delimiter-char-found).
    ;; delimiter-char-found is #f at EOF.
    (let loop ([chars '()])
      (let ([ch (read-char port)])
        (cond
          [(eof-object? ch)
           (if (null? chars)
               (values (eof-object) #f)
               (values (list->string (reverse chars)) #f))]
          [(string-contains-char? delimiters ch)
           (values (list->string (reverse chars)) ch)]
          [else
           (loop (cons ch chars))]))))

  (define (string-contains-char? str ch)
    ;; Check if string contains the given character.
    (let ([len (string-length str)])
      (let loop ([i 0])
        (cond
          [(>= i len) #f]
          [(char=? (string-ref str i) ch) #t]
          [else (loop (+ i 1))]))))

  (define (read-until port delimiter-char)
    ;; Read from textual port until specific char is found.
    ;; Returns the accumulated string (delimiter is consumed but not included).
    ;; Returns eof-object if EOF reached without finding delimiter.
    (let loop ([chars '()])
      (let ([ch (read-char port)])
        (cond
          [(eof-object? ch)
           (if (null? chars)
               (eof-object)
               (list->string (reverse chars)))]
          [(char=? ch delimiter-char)
           (list->string (reverse chars))]
          [else
           (loop (cons ch chars))]))))

  (define (read-line* port)
    ;; Like read-line but returns #f at EOF instead of "".
    (let ([line (get-line port)])
      (if (eof-object? line)
          #f
          line)))

  (define (read-paragraph port)
    ;; Read lines until a blank line (or EOF).
    ;; A blank line is one that is empty or contains only whitespace.
    ;; Returns the paragraph as a single string with embedded newlines.
    ;; Returns eof-object if EOF at start.
    (let loop ([lines '()] [started? #f])
      (let ([line (get-line port)])
        (cond
          [(eof-object? line)
           (if (null? lines)
               (eof-object)
               (join-lines (reverse lines)))]
          [(blank-line? line)
           (if started?
               ;; End of paragraph
               (join-lines (reverse lines))
               ;; Skip leading blank lines
               (loop lines #f))]
          [else
           (loop (cons line lines) #t)]))))

  (define (blank-line? str)
    (let ([len (string-length str)])
      (let loop ([i 0])
        (cond
          [(>= i len) #t]
          [(char-whitespace? (string-ref str i)) (loop (+ i 1))]
          [else #f]))))

  (define (join-lines lines)
    ;; Join a list of strings with newline separator.
    (if (null? lines)
        ""
        (let loop ([rest (cdr lines)] [acc (car lines)])
          (if (null? rest)
              acc
              (loop (cdr rest)
                    (string-append acc (string #\newline) (car rest)))))))

  (define (write-delimited port strings delimiter)
    ;; Write strings separated by delimiter string to port.
    (unless (null? strings)
      (display (car strings) port)
      (for-each (lambda (s)
                  (display delimiter port)
                  (display s port))
                (cdr strings))))

  (define (read-fields port delimiter)
    ;; Read a single line from port and split it by delimiter char.
    ;; Returns a list of field strings, or eof-object at EOF.
    (let ([line (get-line port)])
      (if (eof-object? line)
          (eof-object)
          (split-string line delimiter))))

  (define (split-string str delimiter-char)
    ;; Split string by a delimiter character. Returns list of strings.
    (let ([len (string-length str)])
      (let loop ([i 0] [start 0] [fields '()])
        (cond
          [(>= i len)
           (reverse (cons (substring str start i) fields))]
          [(char=? (string-ref str i) delimiter-char)
           (loop (+ i 1) (+ i 1)
                 (cons (substring str start i) fields))]
          [else
           (loop (+ i 1) start fields)]))))

  (define (read-record port field-delimiter record-delimiter)
    ;; Read one record: characters until record-delimiter, then split by
    ;; field-delimiter. Returns list of field strings, or eof-object at EOF.
    (let loop ([chars '()])
      (let ([ch (read-char port)])
        (cond
          [(eof-object? ch)
           (if (null? chars)
               (eof-object)
               (split-string (list->string (reverse chars)) field-delimiter))]
          [(char=? ch record-delimiter)
           (split-string (list->string (reverse chars)) field-delimiter)]
          [else
           (loop (cons ch chars))]))))

) ;; end library
