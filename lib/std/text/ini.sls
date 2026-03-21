#!chezscheme
;;; (std text ini) — INI/config file parser
;;;
;;; Parse and write INI-format configuration files.
;;; Supports sections [name], key=value pairs, and # ; comments.

(library (std text ini)
  (export ini-read ini-write ini-ref ini-set)

  (import (chezscheme))

  ;; Parse INI file to alist of (section . ((key . value) ...))
  ;; Global (section-less) entries go under ""
  (define (ini-read port-or-path)
    (define (parse port)
      (let loop ([sections '()]
                 [current-section ""]
                 [current-entries '()])
        (let ([line (get-line port)])
          (if (eof-object? line)
              ;; Finalize
              (let ([sections (cons (cons current-section (reverse current-entries))
                                    sections)])
                (reverse sections))
              (let ([trimmed (string-trim line)])
                (cond
                  ;; Empty line or comment
                  [(or (string=? trimmed "")
                       (and (> (string-length trimmed) 0)
                            (memv (string-ref trimmed 0) '(#\# #\;))))
                   (loop sections current-section current-entries)]
                  ;; Section header [name]
                  [(and (> (string-length trimmed) 0)
                        (char=? (string-ref trimmed 0) #\[))
                   (let ([end (string-index trimmed #\])])
                     (if end
                         (let ([name (substring trimmed 1 end)])
                           (loop (cons (cons current-section (reverse current-entries))
                                       sections)
                                 name
                                 '()))
                         (loop sections current-section current-entries)))]
                  ;; Key=value pair
                  [(string-index trimmed #\=)
                   => (lambda (eq-pos)
                        (let ([key (string-trim (substring trimmed 0 eq-pos))]
                              [val (string-trim (substring trimmed (+ eq-pos 1)
                                                           (string-length trimmed)))])
                          (loop sections current-section
                                (cons (cons key val) current-entries))))]
                  ;; Unknown line — skip
                  [else (loop sections current-section current-entries)]))))))

    (if (string? port-or-path)
        (call-with-input-file port-or-path parse)
        (parse port-or-path)))

  ;; Write alist to INI format
  (define (ini-write data port-or-path)
    (define (write-ini port)
      (for-each
        (lambda (section)
          (let ([name (car section)]
                [entries (cdr section)])
            (unless (string=? name "")
              (fprintf port "[~a]\n" name))
            (for-each
              (lambda (entry)
                (fprintf port "~a=~a\n" (car entry) (cdr entry)))
              entries)
            (newline port)))
        data))

    (if (string? port-or-path)
        (call-with-output-file port-or-path write-ini 'replace)
        (write-ini port-or-path)))

  ;; Lookup section.key
  (define ini-ref
    (case-lambda
      [(data section key) (ini-ref data section key #f)]
      [(data section key default)
       (let ([sec (assoc section data)])
         (if sec
             (let ([entry (assoc key (cdr sec))])
               (if entry (cdr entry) default))
             default))]))

  ;; Functional update: return new alist with section.key set
  (define (ini-set data section key value)
    (let loop ([rest data] [found #f] [acc '()])
      (cond
        [(null? rest)
         (if found
             (reverse acc)
             ;; Section not found — add new section
             (reverse (cons (cons section (list (cons key value))) acc)))]
        [(string=? (caar rest) section)
         (let* ([entries (cdar rest)]
                [new-entries (let eset ([e entries] [efound #f] [eacc '()])
                               (cond
                                 [(null? e)
                                  (if efound
                                      (reverse eacc)
                                      (reverse (cons (cons key value) eacc)))]
                                 [(string=? (caar e) key)
                                  (eset (cdr e) #t (cons (cons key value) eacc))]
                                 [else
                                  (eset (cdr e) efound (cons (car e) eacc))]))])
           (loop (cdr rest) #t (cons (cons section new-entries) acc)))]
        [else
         (loop (cdr rest) found (cons (car rest) acc))])))

  ;; Helper: trim whitespace
  (define (string-trim str)
    (let* ([len (string-length str)]
           [start (let loop ([i 0])
                    (if (and (< i len) (char-whitespace? (string-ref str i)))
                        (loop (+ i 1)) i))]
           [end (let loop ([i len])
                  (if (and (> i start) (char-whitespace? (string-ref str (- i 1))))
                      (loop (- i 1)) i))])
      (substring str start end)))

  ;; Helper: find char in string
  (define (string-index str ch)
    (let ([len (string-length str)])
      (let loop ([i 0])
        (cond
          [(= i len) #f]
          [(char=? (string-ref str i) ch) i]
          [else (loop (+ i 1))]))))

) ;; end library
