#!chezscheme
;;; std/doc/generator.sls -- Documentation generator from docstring comments

(library (std doc generator)
  (export
    extract-docs generate-markdown generate-html
    make-doc-entry doc-entry-name doc-entry-type doc-entry-doc doc-entry-examples
    parse-docstring format-signature
    doc-module doc-procedure doc-syntax doc-value
    write-docs)

  (import (chezscheme))

  ;; ---- Doc entry record ----

  (define-record-type doc-entry
    (fields name type doc examples signature)
    (protocol
      (lambda (new)
        (lambda (name type doc examples . sig)
          (new name type doc examples (if (null? sig) #f (car sig)))))))

  ;; ---- Doc type constructors (return doc-entry) ----

  (define (doc-module name doc . examples)
    (make-doc-entry name 'module doc examples))

  (define (doc-procedure name sig doc . examples)
    (make-doc-entry name 'procedure doc examples sig))

  (define (doc-syntax name sig doc . examples)
    (make-doc-entry name 'syntax doc examples sig))

  (define (doc-value name doc . examples)
    (make-doc-entry name 'value doc examples))

  ;; ---- format-signature ----

  (define (format-signature entry)
    (let ([sig (doc-entry-signature entry)]
          [name (doc-entry-name entry)])
      (if sig
          (format "(~a ~a)" name sig)
          (format "~a" name))))

  ;; ---- parse-docstring ----
  ;; Parses a string looking for "Doc: ..." lines, "Example: ..." lines
  ;; Returns an association list: ((doc . "...") (examples . ("..." ...)))

  (define (parse-docstring text)
    (let ([lines (string-split-lines text)])
      (let loop ([ls lines] [doc-lines '()] [examples '()] [in-doc #f])
        (if (null? ls)
            (list (cons 'doc (string-join (reverse doc-lines) "\n"))
                  (cons 'examples (reverse examples)))
            (let ([line (string-trim (car ls))])
              (cond
                [(string-prefix? "Doc:" line)
                 (loop (cdr ls)
                       (cons (string-trim (substring line 4 (string-length line)))
                             doc-lines)
                       examples #t)]
                [(string-prefix? ";; Doc:" line)
                 (let ([txt (string-trim (substring line 7 (string-length line)))])
                   (loop (cdr ls) (cons txt doc-lines) examples #t))]
                [(string-prefix? "Example:" line)
                 (let ([ex (string-trim (substring line 8 (string-length line)))])
                   (loop (cdr ls) doc-lines (cons ex examples) in-doc))]
                [(string-prefix? ";; Example:" line)
                 (let ([ex (string-trim (substring line 11 (string-length line)))])
                   (loop (cdr ls) doc-lines (cons ex examples) in-doc))]
                [else
                 (loop (cdr ls) doc-lines examples in-doc)]))))))

  ;; ---- String utilities ----

  (define (string-split-lines s)
    (let loop ([i 0] [start 0] [acc '()])
      (cond
        [(= i (string-length s))
         (reverse (cons (substring s start i) acc))]
        [(char=? (string-ref s i) #\newline)
         (loop (+ i 1) (+ i 1) (cons (substring s start i) acc))]
        [else
         (loop (+ i 1) start acc)])))

  (define (string-trim s)
    (let ([len (string-length s)])
      (let lloop ([start 0])
        (if (and (< start len) (char-whitespace? (string-ref s start)))
            (lloop (+ start 1))
            (let rloop ([end len])
              (if (and (> end start) (char-whitespace? (string-ref s (- end 1))))
                  (rloop (- end 1))
                  (substring s start end)))))))

  (define (string-prefix? prefix s)
    (and (>= (string-length s) (string-length prefix))
         (string=? (substring s 0 (string-length prefix)) prefix)))

  (define (string-join strs sep)
    (if (null? strs)
        ""
        (fold-left (lambda (acc s) (string-append acc sep s))
                   (car strs)
                   (cdr strs))))

  ;; ---- HTML escaping ----

  (define (html-escape s)
    (let loop ([i 0] [acc '()])
      (if (= i (string-length s))
          (apply string-append (reverse acc))
          (let ([c (string-ref s i)])
            (loop (+ i 1)
                  (cons (case c
                          [(#\<) "&lt;"]
                          [(#\>) "&gt;"]
                          [(#\&) "&amp;"]
                          [(#\") "&quot;"]
                          [else  (string c)])
                        acc))))))

  ;; ---- extract-docs ----
  ;; Reads a source file and extracts doc entries from `;; Doc:` comment blocks
  ;; Returns a list of doc-entry records

  (define (extract-docs file-path)
    (if (file-exists? file-path)
        (let ([text (call-with-input-file file-path
                      (lambda (p) (read-string-all p)))])
          (extract-from-text text))
        '()))

  (define (read-string-all port)
    (let loop ([acc '()])
      (let ([c (read-char port)])
        (if (eof-object? c)
            (list->string (reverse acc))
            (loop (cons c acc))))))

  ;; Parse doc entries from text
  (define (extract-from-text text)
    (let ([lines (string-split-lines text)])
      (let loop ([ls lines] [acc '()] [current-doc #f] [current-name #f] [current-type #f])
        (if (null? ls)
            (reverse acc)
            (let ([line (string-trim (car ls))])
              (cond
                ;; Start of doc block: ;; Doc: name (type): description
                [(and (string-prefix? ";; Doc:" line))
                 (let* ([rest (string-trim (substring line 7 (string-length line)))]
                        [parsed (parse-doc-header rest)])
                   (if parsed
                       (loop (cdr ls) acc
                             (cadr parsed) (car parsed) (caddr parsed))
                       (loop (cdr ls) acc rest #f 'procedure)))]
                ;; Additional doc lines
                [(and current-name (string-prefix? ";;" line) (not (string=? line ";;")))
                 (let ([more (string-trim (substring line 2 (string-length line)))])
                   (loop (cdr ls) acc
                         (if current-doc
                             (string-append current-doc " " more)
                             more)
                         current-name current-type))]
                ;; Blank comment or non-comment ends block, emit entry
                [else
                 (let ([new-acc (if current-name
                                    (cons (make-doc-entry current-name
                                                          (or current-type 'value)
                                                          (or current-doc "")
                                                          '())
                                          acc)
                                    acc)])
                   (loop (cdr ls) new-acc #f #f #f))]))))))

  (define (parse-doc-header text)
    ;; "name (type): doc..." -> (name doc type)
    ;; Find first space to get name, then look for (type) qualifier
    (let* ([len (string-length text)]
           [sp  (let scan ([i 0])
                  (if (or (= i len) (char=? (string-ref text i) #\space))
                      i
                      (scan (+ i 1))))])
      (if (= sp len)
          ;; No space: whole text is name
          (list text "" 'procedure)
          (let* ([name (substring text 0 sp)]
                 [rest (string-trim (substring text sp len))]
                 [rlen (string-length rest)])
            (if (and (> rlen 0) (char=? (string-ref rest 0) (integer->char 40)))
                ;; Has (type) qualifier
                (let find-close ([j 1])
                  (cond
                    [(= j rlen)
                     (list name "" 'procedure)]
                    [(char=? (string-ref rest j) (integer->char 41))
                     (let* ([type-str (substring rest 1 j)]
                            [type     (string->symbol type-str)]
                            [doc-rest (if (< (+ j 1) rlen)
                                          (string-trim (substring rest (+ j 1) rlen))
                                          "")])
                       (list name doc-rest type))]
                    [else
                     (find-close (+ j 1))]))
                ;; No (type): rest is the doc
                (list name rest 'procedure))))))

  ;; ---- generate-markdown ----

  (define (generate-markdown entries)
    (let ([out (open-output-string)])
      (for-each
        (lambda (entry)
          (let ([name (doc-entry-name entry)]
                [type (doc-entry-type entry)]
                [doc  (doc-entry-doc entry)]
                [exs  (doc-entry-examples entry)])
            (display (format "## `~a`\n\n" name) out)
            (display (format "**Type:** ~a\n\n" type) out)
            (display (format "~a\n\n" doc) out)
            (unless (null? exs)
              (display "**Examples:**\n\n" out)
              (for-each
                (lambda (ex)
                  (display (format "```scheme\n~a\n```\n\n" ex) out))
                exs))))
        entries)
      (get-output-string out)))

  ;; ---- generate-html ----

  (define (generate-html entries)
    (let ([out (open-output-string)])
      (display "<!DOCTYPE html>\n<html>\n<head>\n" out)
      (display "<meta charset=\"UTF-8\">\n" out)
      (display "<style>body{font-family:monospace;max-width:800px;margin:auto;padding:2em}</style>\n" out)
      (display "</head>\n<body>\n" out)
      (for-each
        (lambda (entry)
          (let ([name (doc-entry-name entry)]
                [type (doc-entry-type entry)]
                [doc  (doc-entry-doc entry)]
                [exs  (doc-entry-examples entry)])
            (display (format "<section>\n<h2><code>~a</code></h2>\n" (html-escape name)) out)
            (display (format "<p><strong>Type:</strong> ~a</p>\n" type) out)
            (display (format "<p>~a</p>\n" (html-escape doc)) out)
            (unless (null? exs)
              (display "<p><strong>Examples:</strong></p>\n" out)
              (for-each
                (lambda (ex)
                  (display (format "<pre><code>~a</code></pre>\n" (html-escape ex)) out))
                exs))
            (display "</section>\n" out)))
        entries)
      (display "</body>\n</html>\n" out)
      (get-output-string out)))

  ;; ---- write-docs ----

  (define (write-docs entries output-file format)
    (let ([content (case format
                     [(markdown md) (generate-markdown entries)]
                     [(html)        (generate-html entries)]
                     [else          (generate-markdown entries)])])
      (call-with-output-file output-file
        (lambda (p) (display content p))
        'truncate)))

  ) ;; end library
