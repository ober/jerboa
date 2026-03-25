#!chezscheme
;;; (std csv) — CSV reader/writer per RFC 4180
;;;
;;; Handles: quoted fields, embedded commas, embedded newlines,
;;; escaped quotes (""), custom delimiters.

(library (std csv)
  (export
    ;; Reading
    read-csv read-csv-file csv-port->rows
    ;; Writing
    write-csv write-csv-file rows->csv-string
    ;; Alist conversion
    csv->alists alists->csv)

  (import (chezscheme))

  ;; --- Reading ---

  ;; Read CSV string into list of rows (each row is a list of strings)
  (define read-csv
    (case-lambda
      [(str) (read-csv str #\,)]
      [(str delim)
       (let ([port (open-input-string str)])
         (csv-port->rows port delim))]))

  ;; Read CSV file into list of rows
  (define read-csv-file
    (case-lambda
      [(path) (read-csv-file path #\,)]
      [(path delim)
       (call-with-input-file path
         (lambda (port) (csv-port->rows port delim)))]))

  ;; Read all rows from a port
  (define csv-port->rows
    (case-lambda
      [(port) (csv-port->rows port #\,)]
      [(port delim)
       (let loop ([acc '()])
         (let ([row (read-csv-row port delim)])
           (if (eof-object? row)
             (reverse acc)
             (loop (cons row acc)))))]))

  ;; Read one CSV row from port, returns list of strings or eof
  (define (read-csv-row port delim)
    (let ([ch (peek-char port)])
      (if (eof-object? ch)
        ch
        (let loop ([fields '()] [current (open-output-string)] [in-quote? #f])
          (let ([c (read-char port)])
            (cond
              ;; EOF
              [(eof-object? c)
               (reverse (cons (get-output-string current) fields))]
              ;; Inside quoted field
              [in-quote?
               (cond
                 [(char=? c #\")
                  (let ([next (peek-char port)])
                    (if (and (char? next) (char=? next #\"))
                      ;; Escaped quote ""
                      (begin (read-char port)
                             (write-char #\" current)
                             (loop fields current #t))
                      ;; End of quoted field
                      (loop fields current #f)))]
                 [else
                  (write-char c current)
                  (loop fields current #t)])]
              ;; Not in quote
              [(char=? c #\")
               (loop fields current #t)]
              [(char=? c delim)
               (loop (cons (get-output-string current) fields)
                     (open-output-string) #f)]
              [(char=? c #\newline)
               (reverse (cons (get-output-string current) fields))]
              [(char=? c #\return)
               ;; Skip CR, let LF end the row
               (when (and (char? (peek-char port)) (char=? (peek-char port) #\newline))
                 (read-char port))
               (reverse (cons (get-output-string current) fields))]
              [else
               (write-char c current)
               (loop fields current #f)]))))))

  ;; --- Writing ---

  ;; Write rows to CSV string
  (define rows->csv-string
    (case-lambda
      [(rows) (rows->csv-string rows #\,)]
      [(rows delim)
       (let ([port (open-output-string)])
         (write-csv-to-port rows port delim)
         (get-output-string port))]))

  ;; Write rows to file
  (define write-csv-file
    (case-lambda
      [(path rows) (write-csv-file path rows #\,)]
      [(path rows delim)
       (call-with-output-file path
         (lambda (port) (write-csv-to-port rows port delim))
         'replace)]))

  ;; Write rows to current-output-port or specified port
  (define write-csv
    (case-lambda
      [(rows) (write-csv-to-port rows (current-output-port) #\,)]
      [(rows port) (write-csv-to-port rows port #\,)]
      [(rows port delim) (write-csv-to-port rows port delim)]))

  (define (write-csv-to-port rows port delim)
    (for-each
      (lambda (row)
        (let loop ([fields row] [first? #t])
          (unless (null? fields)
            (unless first? (write-char delim port))
            (write-csv-field (car fields) port delim)
            (loop (cdr fields) #f)))
        (display "\r\n" port))  ;; RFC 4180: CRLF
      rows))

  (define (write-csv-field val port delim)
    (let ([s (if (string? val) val (format "~a" val))])
      (if (needs-quoting? s delim)
        (begin
          (write-char #\" port)
          (string-for-each
            (lambda (c)
              (when (char=? c #\") (write-char #\" port))  ;; escape quotes
              (write-char c port))
            s)
          (write-char #\" port))
        (display s port))))

  (define (needs-quoting? s delim)
    (let ([len (string-length s)])
      (let loop ([i 0])
        (and (< i len)
             (let ([c (string-ref s i)])
               (or (char=? c delim)
                   (char=? c #\")
                   (char=? c #\newline)
                   (char=? c #\return)
                   (loop (+ i 1))))))))

  ;; --- Alist conversion ---

  ;; Convert CSV (with header row) to list of alists
  ;; First row is treated as column names (symbols)
  (define csv->alists
    (case-lambda
      [(str) (csv->alists str #\,)]
      [(str delim)
       (let ([rows (read-csv str delim)])
         (if (null? rows) '()
           (let ([headers (map string->symbol (car rows))])
             (map (lambda (row)
                    (map cons headers row))
                  (cdr rows)))))]))

  ;; Convert list of alists to CSV string (with header row)
  (define alists->csv
    (case-lambda
      [(alists) (alists->csv alists #\,)]
      [(alists delim)
       (if (null? alists) ""
         (let* ([headers (map car (car alists))]
                [header-row (map symbol->string headers)]
                [data-rows (map (lambda (al)
                                  (map (lambda (h)
                                         (let ([pair (assq h al)])
                                           (if pair (format "~a" (cdr pair)) "")))
                                       headers))
                                alists)])
           (rows->csv-string (cons header-row data-rows) delim)))]))

  ) ;; end library
