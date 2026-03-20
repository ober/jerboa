#!chezscheme
;;; (std repl notebook) -- Literate REPL Sessions
;;;
;;; Save and replay REPL sessions as executable Scheme files with
;;; markdown documentation. Like Jupyter notebooks for Scheme.
;;;
;;; File format (.ss.nb):
;;;   ;; # Title
;;;   ;; Description in markdown
;;;
;;;   ;;; --- cell ---
;;;   ;; Markdown documentation for this cell
;;;   (define x 42)
;;;   ;;; => 42
;;;   ;;; type: Fixnum
;;;
;;; Commands:
;;;   (notebook-save path entries)     — save entries to file
;;;   (notebook-load path)             — load entries from file
;;;   (notebook-run path env)          — execute all cells
;;;   (notebook-export-html path)      — export to HTML
;;;
;;; REPL integration (via ,notebook commands):
;;;   ,notebook new title     — start recording a new notebook
;;;   ,notebook add           — add current cell (last input/output)
;;;   ,notebook note text     — add a markdown note
;;;   ,notebook save path     — save notebook to file
;;;   ,notebook show          — display current notebook
;;;   ,notebook run path      — run a notebook file
;;;   ,notebook stop          — stop recording

(library (std repl notebook)
  (export
    ;; Notebook record
    make-notebook
    notebook?
    notebook-title
    notebook-cells

    ;; Cell record
    make-cell
    cell?
    cell-type     ; 'code or 'markdown
    cell-content  ; string
    cell-output   ; string or #f (for code cells)

    ;; Operations
    notebook-add-cell!
    notebook-save
    notebook-load
    notebook-run
    notebook-export-markdown
    notebook-export-html

    ;; REPL session recording
    *current-notebook*
    notebook-recording?
    notebook-start!
    notebook-stop!)

  (import (chezscheme))

  ;; ========== Cell Record ==========
  (define-record-type cell
    (fields (immutable type cell-type)         ;; 'code or 'markdown
            (immutable content cell-content)    ;; string: source or markdown text
            (immutable output cell-output))     ;; string or #f
    (protocol (lambda (new)
      (lambda (type content output)
        (new type content output)))))

  ;; ========== Notebook Record ==========
  (define-record-type notebook
    (fields (immutable title notebook-title)
            (mutable cells notebook-cells set-notebook-cells!))
    (protocol (lambda (new)
      (lambda (title)
        (new title '())))))

  ;; ========== Session State ==========
  (define *current-notebook* (make-parameter #f))

  (define (notebook-recording?)
    (and (*current-notebook*) #t))

  (define (notebook-start! title)
    (*current-notebook* (make-notebook title)))

  (define (notebook-stop!)
    (let ([nb (*current-notebook*)])
      (*current-notebook* #f)
      nb))

  ;; ========== Cell Operations ==========
  (define (notebook-add-cell! nb cell)
    (set-notebook-cells! nb (append (notebook-cells nb) (list cell))))

  ;; ========== Save to File ==========
  (define (notebook-save path nb)
    (call-with-output-file path
      (lambda (port)
        ;; Header
        (fprintf port ";;; Jerboa Notebook: ~a~n" (notebook-title nb))
        (fprintf port ";;; Generated: ~a~n" (date-and-time))
        (newline port)

        ;; Cells
        (for-each
          (lambda (c)
            (fprintf port ";;; --- cell ---~n")
            (case (cell-type c)
              [(markdown)
               (for-each (lambda (line)
                           (fprintf port ";; ~a~n" line))
                         (string-split-lines (cell-content c)))]
              [(code)
               (display (cell-content c) port)
               (newline port)
               (when (cell-output c)
                 (for-each (lambda (line)
                             (fprintf port ";;; => ~a~n" line))
                           (string-split-lines (cell-output c))))])
            (newline port))
          (notebook-cells nb)))
      'replace))

  ;; ========== Load from File ==========
  (define (notebook-load path)
    ;; Two-pass: first read all lines, then parse into cells
    (let* ([lines (call-with-input-file path
                    (lambda (port)
                      (let loop ([acc '()])
                        (let ([line (get-line port)])
                          (if (eof-object? line)
                            (reverse acc)
                            (loop (cons line acc)))))))]
           [title "Untitled"]
           [cells '()])

      ;; Extract title
      (for-each (lambda (line)
                  (when (string-starts-with? line ";;; Jerboa Notebook: ")
                    (set! title (substring line 21 (string-length line)))))
                lines)

      ;; Split into cell groups by ";;; --- cell ---" separator
      (let ([groups (split-by-separator lines ";;; --- cell ---")])
        (for-each
          (lambda (group)
            ;; Classify cell: all lines start with ;; => markdown, else code
            (let* ([content-lines (filter (lambda (l)
                                            (and (not (string=? (string-trim* l) ""))
                                                 (not (string-starts-with? l ";;; =>"))
                                                 (not (string-starts-with? l ";;; Jerboa"))
                                                 (not (string-starts-with? l ";;; Generated"))))
                                          group)]
                   [output-lines (filter-map
                                   (lambda (l)
                                     (and (string-starts-with? l ";;; => ")
                                          (substring l 7 (string-length l))))
                                   group)])
              (when (pair? content-lines)
                (let ([is-markdown (every-string-starts-with? content-lines ";; ")])
                  (if is-markdown
                    (set! cells
                      (append cells
                        (list (make-cell 'markdown
                                (string-join-lines
                                  (map (lambda (l)
                                         (if (>= (string-length l) 3)
                                           (substring l 3 (string-length l))
                                           ""))
                                       content-lines))
                                #f))))
                    (set! cells
                      (append cells
                        (list (make-cell 'code
                                (string-join-lines content-lines)
                                (if (null? output-lines) #f
                                  (string-join-lines output-lines)))))))))))
          groups))

      (let ([nb (make-notebook title)])
        (set-notebook-cells! nb cells)
        nb)))

  (define (split-by-separator lines sep)
    (let loop ([lines lines] [current '()] [groups '()])
      (cond
        [(null? lines)
         (reverse (if (null? current) groups (cons (reverse current) groups)))]
        [(string=? (string-trim* (car lines)) sep)
         (loop (cdr lines) '()
               (if (null? current) groups (cons (reverse current) groups)))]
        [else
         (loop (cdr lines) (cons (car lines) current) groups)])))

  (define (every-string-starts-with? lst prefix)
    (or (null? lst)
        (and (string-starts-with? (car lst) prefix)
             (every-string-starts-with? (cdr lst) prefix))))

  (define (filter-map proc lst)
    (let loop ([l lst] [acc '()])
      (if (null? l) (reverse acc)
        (let ([result (proc (car l))])
          (loop (cdr l) (if result (cons result acc) acc))))))
  ;; ========== Run a Notebook ==========
  (define (notebook-run path env)
    (let ([nb (notebook-load path)])
      (display (format "Running notebook: ~a (~a cells)\n"
        (notebook-title nb) (length (notebook-cells nb))))
      (let loop ([cells (notebook-cells nb)] [results '()])
        (if (null? cells)
          (reverse results)
          (let ([c (car cells)])
            (case (cell-type c)
              [(markdown)
               (display (format "## ~a\n" (cell-content c)))
               (loop (cdr cells) results)]
              [(code)
               (display (format "> ~a\n" (cell-content c)))
               (guard (exn [#t
                            (display (format "ERROR: ~a\n"
                              (if (message-condition? exn)
                                (condition-message exn)
                                exn)))
                            (loop (cdr cells) (cons 'error results))])
                 (let ([result (eval (with-input-from-string (cell-content c) read) env)])
                   (unless (eq? result (void))
                     (display (format "=> ~s\n" result)))
                   (loop (cdr cells) (cons result results))))]))))))

  ;; ========== Export to Markdown ==========
  (define (notebook-export-markdown nb)
    (with-output-to-string
      (lambda ()
        (fprintf (current-output-port) "# ~a\n\n" (notebook-title nb))
        (for-each
          (lambda (c)
            (case (cell-type c)
              [(markdown)
               (display (cell-content c))
               (display "\n\n")]
              [(code)
               (display "```scheme\n")
               (display (cell-content c))
               (display "\n```\n")
               (when (cell-output c)
                 (display "```\n")
                 (display (cell-output c))
                 (display "\n```\n"))
               (newline)]))
          (notebook-cells nb)))))

  ;; ========== Export to HTML ==========
  (define (notebook-export-html nb)
    (with-output-to-string
      (lambda ()
        (display "<!DOCTYPE html>\n<html><head>\n")
        (display "<meta charset=\"utf-8\">\n")
        (fprintf (current-output-port) "<title>~a</title>\n" (html-escape (notebook-title nb)))
        (display "<style>\n")
        (display "body { font-family: -apple-system, sans-serif; max-width: 800px; margin: 40px auto; padding: 0 20px; }\n")
        (display "pre { background: #f6f8fa; padding: 16px; border-radius: 6px; overflow-x: auto; }\n")
        (display ".code { border-left: 3px solid #0366d6; }\n")
        (display ".output { border-left: 3px solid #28a745; background: #f0fff0; }\n")
        (display "h1, h2, h3 { color: #24292e; }\n")
        (display "</style>\n</head><body>\n")
        (fprintf (current-output-port) "<h1>~a</h1>\n" (html-escape (notebook-title nb)))

        (for-each
          (lambda (c)
            (case (cell-type c)
              [(markdown)
               (fprintf (current-output-port) "<p>~a</p>\n" (html-escape (cell-content c)))]
              [(code)
               (fprintf (current-output-port) "<pre class=\"code\"><code>~a</code></pre>\n"
                 (html-escape (cell-content c)))
               (when (cell-output c)
                 (fprintf (current-output-port) "<pre class=\"output\"><code>~a</code></pre>\n"
                   (html-escape (cell-output c))))]))
          (notebook-cells nb))

        (display "</body></html>\n"))))

  ;; ========== Helpers ==========
  (define (string-split-lines str)
    (let ([len (string-length str)])
      (let loop ([i 0] [start 0] [acc '()])
        (cond
          [(= i len)
           (reverse (cons (substring str start len) acc))]
          [(char=? (string-ref str i) #\newline)
           (loop (+ i 1) (+ i 1)
                 (cons (substring str start i) acc))]
          [else (loop (+ i 1) start acc)]))))

  (define (string-join-lines lines)
    (if (null? lines) ""
      (let loop ([rest (cdr lines)] [acc (car lines)])
        (if (null? rest) acc
          (loop (cdr rest) (string-append acc "\n" (car rest)))))))

  (define (string-starts-with? str prefix)
    (and (>= (string-length str) (string-length prefix))
         (string=? (substring str 0 (string-length prefix)) prefix)))

  (define (string-trim* str)
    (let* ([n (string-length str)]
           [s (let loop ([i 0])
                (if (or (= i n) (not (char-whitespace? (string-ref str i)))) i
                  (loop (+ i 1))))]
           [e (let loop ([i (- n 1)])
                (if (or (< i 0) (not (char-whitespace? (string-ref str i)))) (+ i 1)
                  (loop (- i 1))))])
      (if (>= s e) "" (substring str s e))))

  (define (html-escape str)
    (let ([out (open-output-string)])
      (string-for-each
        (lambda (c)
          (cond
            [(char=? c #\<) (display "&lt;" out)]
            [(char=? c #\>) (display "&gt;" out)]
            [(char=? c #\&) (display "&amp;" out)]
            [(char=? c #\") (display "&quot;" out)]
            [else (display c out)]))
        str)
      (get-output-string out)))

) ;; end library
