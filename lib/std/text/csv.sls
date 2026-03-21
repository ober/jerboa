#!chezscheme
;;; :std/text/csv -- CSV parsing and writing

(library (std text csv)
  (export
    read-csv
    read-csv-records
    write-csv
    write-csv-record
    csv-read
    csv-write
    *csv-strict-quotes*
    *csv-max-field-length*)

  (import (chezscheme))

  (define *csv-strict-quotes* (make-parameter #t))
  (define *csv-max-field-length* (make-parameter (* 1 1024 1024)))  ;; 1MB default

  (define (read-csv port . rest)
    ;; Read all CSV records from port
    ;; Returns a list of lists of strings
    (let ((separator (if (pair? rest) (car rest) #\,)))
      (let lp ((records '()))
        (let ((record (read-csv-record port separator)))
          (if (not record)
            (reverse records)
            (lp (cons record records)))))))

  (define (read-csv-records port . rest)
    (apply read-csv port rest))

  (define (read-csv-record port . rest)
    ;; Read a single CSV record (one line) from port
    ;; Returns a list of strings, or #f at EOF
    (let ((separator (if (pair? rest) (car rest) #\,)))
      (let ((line (get-line port)))
        (if (eof-object? line)
          #f
          (parse-csv-line line separator)))))

  (define (parse-csv-line line separator)
    ;; Parse a CSV line into fields
    (let ((len (string-length line)))
      (let lp ((i 0) (fields '()) (current '()))
        (cond
          ((>= i len)
           (reverse (cons (list->string (reverse current)) fields)))
          ((char=? (string-ref line i) #\")
           ;; Quoted field
           (let lp2 ((j (+ i 1)) (chars '()))
             (cond
               ((>= j len)
                (if (*csv-strict-quotes*)
                  (error 'parse-csv-line "unterminated quoted field")
                  (reverse (cons (list->string (reverse chars)) fields))))
               ((char=? (string-ref line j) #\")
                (if (and (< (+ j 1) len) (char=? (string-ref line (+ j 1)) #\"))
                  ;; Escaped quote
                  (lp2 (+ j 2) (cons #\" chars))
                  ;; End of quoted field
                  (let ((k (+ j 1)))
                    (if (or (>= k len) (char=? (string-ref line k) separator))
                      (lp (+ k 1) (cons (list->string (reverse chars)) fields) '())
                      (lp k fields (reverse chars))))))
               (else
                (when (> (length chars) (*csv-max-field-length*))
                  (error 'parse-csv-line "field exceeds maximum length"
                         (length chars) (*csv-max-field-length*)))
                (lp2 (+ j 1) (cons (string-ref line j) chars))))))
          ((char=? (string-ref line i) separator)
           (lp (+ i 1) (cons (list->string (reverse current)) fields) '()))
          (else
           (lp (+ i 1) fields (cons (string-ref line i) current)))))))

  (define (write-csv records port . rest)
    ;; Write a list of records to port
    (let ((separator (if (pair? rest) (car rest) #\,)))
      (for-each
        (lambda (record)
          (write-csv-record record port separator))
        records)))

  (define (write-csv-record record port . rest)
    ;; Write a single CSV record
    (let ((separator (if (pair? rest) (car rest) #\,)))
      (let lp ((fields record) (first? #t))
        (unless (null? fields)
          (unless first?
            (write-char separator port))
          (write-csv-field (car fields) port separator)
          (lp (cdr fields) #f)))
      (newline port)))

  (define (write-csv-field field port separator)
    (let ((s (if (string? field) field (format "~a" field))))
      (if (or (string-contains? s (string separator))
              (string-contains? s "\"")
              (string-contains? s "\n"))
        ;; Quote the field
        (begin
          (write-char #\" port)
          (string-for-each
            (lambda (c)
              (when (char=? c #\")
                (write-char #\" port))
              (write-char c port))
            s)
          (write-char #\" port))
        (display s port))))

  (define (string-contains? s sub)
    (let ((slen (string-length s))
          (sublen (string-length sub)))
      (let lp ((i 0))
        (cond
          ((> (+ i sublen) slen) #f)
          ((string=? (substring s i (+ i sublen)) sub) #t)
          (else (lp (+ i 1)))))))

  ;; Aliases
  (define csv-read read-csv)
  (define csv-write write-csv)

  ) ;; end library
