#!chezscheme
;;; :std/net/smtp -- SMTP email client
;;;
;;; Simple SMTP client for sending email over plain TCP.
;;; No TLS support — use stunnel or port 587 with STARTTLS as future work.
;;; Supports PLAIN authentication via base64.

(library (std net smtp)
  (export
    send-email make-email email?
    email-from email-to email-subject email-body
    smtp-connect smtp-send smtp-disconnect
    make-smtp-config smtp-config?)

  (import (chezscheme)
          (std net tcp)
          (std text base64))

  ;; ========== Records ==========

  (define-record-type smtp-config
    (fields host port username password)
    (protocol
      (lambda (new)
        (case-lambda
          [(host port) (new host port #f #f)]
          [(host port username password) (new host port username password)])))
    (sealed #t))

  (define-record-type email
    (fields from to subject body)
    (sealed #t))

  ;; make-email: (make-email from to subject body)
  ;; The record constructor already provides this.

  ;; ========== SMTP Connection ==========

  (define-record-type smtp-connection
    (fields in out config)
    (sealed #t))

  (define (smtp-connect config)
    ;; Connect to SMTP server and perform EHLO handshake.
    (let-values ([(in out) (tcp-connect (smtp-config-host config)
                                        (smtp-config-port config))])
      (let ([conn (make-smtp-connection in out config)])
        ;; Read greeting
        (smtp-read-reply conn)
        ;; EHLO
        (smtp-command conn (format "EHLO localhost\r\n"))
        ;; AUTH if credentials provided
        (when (smtp-config-username config)
          (smtp-auth conn))
        conn)))

  (define (smtp-disconnect conn)
    (smtp-command conn "QUIT\r\n")
    (close-port (smtp-connection-in conn))
    (close-port (smtp-connection-out conn)))

  ;; ========== Sending ==========

  (define (smtp-send conn email)
    ;; Send an email over an established SMTP connection.
    (smtp-command conn
      (format "MAIL FROM:<~a>\r\n" (email-from email)))
    ;; Handle single recipient or list
    (let ([recipients (let ([to (email-to email)])
                        (if (list? to) to (list to)))])
      (for-each
        (lambda (rcpt)
          (smtp-command conn
            (format "RCPT TO:<~a>\r\n" rcpt)))
        recipients))
    ;; DATA
    (smtp-command conn "DATA\r\n")
    ;; Send headers and body
    (let ([out (smtp-connection-out conn)])
      (display (format "From: ~a\r\n" (email-from email)) out)
      (display (format "To: ~a\r\n"
                 (let ([to (email-to email)])
                   (if (list? to)
                     (apply string-append
                       (let lp ([rest to] [first #t])
                         (if (null? rest) '()
                           (cons (if first (car rest)
                                   (string-append ", " (car rest)))
                                 (lp (cdr rest) #f)))))
                     to)))
               out)
      (display (format "Subject: ~a\r\n" (email-subject email)) out)
      (display "MIME-Version: 1.0\r\n" out)
      (display "Content-Type: text/plain; charset=UTF-8\r\n" out)
      (display "\r\n" out)
      ;; Body — dot-stuff lines starting with "."
      (let ([lines (string-split (email-body email) #\newline)])
        (for-each
          (lambda (line)
            (when (and (> (string-length line) 0)
                       (char=? (string-ref line 0) #\.))
              (display "." out))
            (display line out)
            (display "\r\n" out))
          lines))
      ;; End of data
      (display ".\r\n" out)
      (flush-output-port out))
    (smtp-read-reply conn))

  (define (send-email config email)
    ;; One-shot: connect, send, disconnect.
    (let ([conn (smtp-connect config)])
      (dynamic-wind
        (lambda () (void))
        (lambda () (smtp-send conn email))
        (lambda () (smtp-disconnect conn)))))

  ;; ========== AUTH ==========

  (define (smtp-auth conn)
    ;; PLAIN auth: base64("\0username\0password")
    (let* ([user (smtp-config-username (smtp-connection-config conn))]
           [pass (smtp-config-password (smtp-connection-config conn))]
           [auth-str (string-append "\x0;" user "\x0;" pass)]
           [encoded (base64-encode (string->utf8 auth-str))])
      (smtp-command conn (format "AUTH PLAIN ~a\r\n" encoded))))

  ;; ========== Protocol helpers ==========

  (define (smtp-command conn cmd)
    (let ([out (smtp-connection-out conn)])
      (display cmd out)
      (flush-output-port out))
    (smtp-read-reply conn))

  (define (smtp-read-reply conn)
    ;; Read SMTP reply lines. Returns the last line.
    ;; Multi-line replies have "-" after code, last line has " ".
    (let ([in (smtp-connection-in conn)])
      (let loop ()
        (let ([line (read-line in)])
          (when (eof-object? line)
            (error 'smtp-read-reply "unexpected EOF from SMTP server"))
          (let ([code (and (>= (string-length line) 3)
                           (string->number (substring line 0 3)))])
            (when (and code (>= code 400))
              (error 'smtp "server error" line))
            ;; Continue if multi-line (char at pos 3 is "-")
            (if (and (> (string-length line) 3)
                     (char=? (string-ref line 3) #\-))
              (loop)
              line))))))

  ;; ========== Utilities ==========

  (define (string-split str ch)
    (let ([len (string-length str)])
      (let lp ([i 0] [start 0] [acc '()])
        (cond
          [(= i len)
           (reverse (cons (substring str start len) acc))]
          [(char=? (string-ref str i) ch)
           (lp (+ i 1) (+ i 1)
               (cons (substring str start i) acc))]
          [else (lp (+ i 1) start acc)]))))

  (define (read-line port)
    (let loop ([chars '()])
      (let ([ch (read-char port)])
        (cond
          [(eof-object? ch)
           (if (null? chars) ch (list->string (reverse chars)))]
          [(char=? ch #\newline)
           (list->string (reverse chars))]
          [(char=? ch #\return) (loop chars)]
          [else (loop (cons ch chars))]))))

  ) ;; end library
