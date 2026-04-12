#!chezscheme
;;; (std clojure io) — Unified I/O module (clojure.java.io equivalent)
;;;
;;; Provides polymorphic I/O functions that coerce between file paths
;;; (strings), ports, and bytevectors — matching the convenience of
;;; Clojure's clojure.java.io namespace.
;;;
;;; Usage:
;;;   (import (std clojure io))
;;;   (def contents (slurp "myfile.txt"))
;;;   (spit "output.txt" "hello world")
;;;   (with-open (p (reader "input.txt"))
;;;     (get-line p))

(library (std clojure io)
  (export
    ;; Core I/O
    reader writer
    input-stream output-stream
    ;; Convenience
    slurp spit
    ;; File operations
    file io-delete-file io-file-exists?
    make-parents
    ;; Resource management
    with-open
    ;; Copy
    io-copy
    ;; Line seq
    line-seq)

  (import (chezscheme))

  ;; ---- reader: open a textual input port ----
  ;; Accepts: string (file path), input-port (pass through)
  (define reader
    (case-lambda
      [(x) (reader x "utf-8")]
      [(x encoding)
       (cond
         [(and (port? x) (input-port? x) (textual-port? x)) x]
         [(string? x)
          (let ([codec (cond
                         [(string-ci=? encoding "utf-8") (utf-8-codec)]
                         [(string-ci=? encoding "latin-1") (latin-1-codec)]
                         [else (utf-8-codec)])])
            (open-file-input-port x (file-options)
              (buffer-mode block)
              (make-transcoder codec)))]
         [(and (port? x) (input-port? x) (binary-port? x))
          (let ([codec (cond
                         [(string-ci=? encoding "utf-8") (utf-8-codec)]
                         [(string-ci=? encoding "latin-1") (latin-1-codec)]
                         [else (utf-8-codec)])])
            (transcoded-port x (make-transcoder codec)))]
         [(bytevector? x)
          (let ([codec (cond
                         [(string-ci=? encoding "utf-8") (utf-8-codec)]
                         [(string-ci=? encoding "latin-1") (latin-1-codec)]
                         [else (utf-8-codec)])])
            (transcoded-port
              (open-bytevector-input-port x)
              (make-transcoder codec)))]
         [else (error 'reader "cannot create reader from" x)])]))

  ;; ---- writer: open a textual output port ----
  ;; Accepts: string (file path), output-port (pass through)
  (define writer
    (case-lambda
      [(x) (writer x "utf-8")]
      [(x encoding)
       (cond
         [(and (port? x) (output-port? x) (textual-port? x)) x]
         [(string? x)
          (let ([codec (cond
                         [(string-ci=? encoding "utf-8") (utf-8-codec)]
                         [(string-ci=? encoding "latin-1") (latin-1-codec)]
                         [else (utf-8-codec)])])
            (open-file-output-port x
              (file-options no-fail)
              (buffer-mode block)
              (make-transcoder codec)))]
         [(and (port? x) (output-port? x) (binary-port? x))
          (let ([codec (cond
                         [(string-ci=? encoding "utf-8") (utf-8-codec)]
                         [(string-ci=? encoding "latin-1") (latin-1-codec)]
                         [else (utf-8-codec)])])
            (transcoded-port x (make-transcoder codec)))]
         [else (error 'writer "cannot create writer from" x)])]))

  ;; ---- input-stream: open a binary input port ----
  (define (input-stream x)
    (cond
      [(and (port? x) (input-port? x) (binary-port? x)) x]
      [(string? x) (open-file-input-port x)]
      [(bytevector? x) (open-bytevector-input-port x)]
      [else (error 'input-stream "cannot create input-stream from" x)]))

  ;; ---- output-stream: open a binary output port ----
  (define (output-stream x)
    (cond
      [(and (port? x) (output-port? x) (binary-port? x)) x]
      [(string? x) (open-file-output-port x (file-options no-fail))]
      [else (error 'output-stream "cannot create output-stream from" x)]))

  ;; ---- slurp: read entire file/resource into a string ----
  (define slurp
    (case-lambda
      [(x) (slurp x "utf-8")]
      [(x encoding)
       (cond
         [(string? x)
          (let ([p (reader x encoding)])
            (dynamic-wind
              (lambda () #f)
              (lambda () (get-string-all p))
              (lambda () (close-port p))))]
         [(and (port? x) (input-port? x) (textual-port? x))
          (get-string-all x)]
         [(and (port? x) (input-port? x) (binary-port? x))
          (let ([p (transcoded-port x (make-transcoder (utf-8-codec)))])
            (get-string-all p))]
         [else (error 'slurp "cannot slurp from" x)])]))

  ;; ---- spit: write a string to a file ----
  (define spit
    (case-lambda
      [(f content) (spit f content "utf-8")]
      [(f content encoding)
       (let ([p (writer f encoding)])
         (dynamic-wind
           (lambda () #f)
           (lambda ()
             (put-string p (if (string? content) content (format "~a" content)))
             (flush-output-port p))
           (lambda () (close-port p))))]))

  ;; ---- file: just returns the path string (in Clojure it wraps java.io.File) ----
  (define (file . parts)
    (let loop ([rest parts] [acc ""])
      (if (null? rest)
          acc
          (let ([part (car rest)])
            (loop (cdr rest)
                  (if (string=? acc "")
                      part
                      (string-append acc "/" part)))))))

  ;; ---- delete-file ----
  (define (io-delete-file f)
    (when (file-exists? f)
      (delete-file f)
      #t))

  ;; ---- file-exists? ----
  (define (io-file-exists? f) (file-exists? f))

  ;; ---- path helpers (must precede make-parents) ----
  (define (%split-path path)
    (let ([len (string-length path)])
      (let loop ([i 0] [start 0] [parts '()])
        (cond
          [(= i len)
           (reverse (if (> i start)
                        (cons (substring path start i) parts)
                        parts))]
          [(char=? (string-ref path i) #\/)
           (loop (+ i 1) (+ i 1)
                 (if (> i start)
                     (cons (substring path start i) parts)
                     parts))]
          [else (loop (+ i 1) start parts)]))))

  (define (%path-parent path)
    (let ([parts (%split-path path)])
      (if (or (null? parts) (null? (cdr parts)))
          ""
          (let loop ([rest (reverse (cdr (reverse parts)))] [acc ""])
            (if (null? rest)
                acc
                (loop (cdr rest)
                      (if (string=? acc "")
                          (car rest)
                          (string-append acc "/" (car rest)))))))))

  ;; ---- make-parents: create parent directories ----
  (define (make-parents f)
    (let ([dir (%path-parent f)])
      (unless (or (string=? dir "") (string=? dir "/") (file-exists? dir))
        (%ensure-dir dir))))

  (define (%ensure-dir path)
    (unless (file-exists? path)
      (let ([parent (%path-parent path)])
        (unless (or (string=? parent "") (file-exists? parent))
          (%ensure-dir parent)))
      (mkdir path)))

  ;; ---- with-open: resource management macro ----
  ;; (with-open (p (reader "file.txt")) body ...)
  ;; Closes p when body completes or on exception.
  (define-syntax with-open
    (syntax-rules ()
      [(_ (var expr) body ...)
       (let ([var expr])
         (dynamic-wind
           (lambda () #f)
           (lambda () body ...)
           (lambda () (close-port var))))]
      [(_ (var1 expr1) (var2 expr2) body ...)
       (with-open (var1 expr1)
         (with-open (var2 expr2)
           body ...))]))

  ;; ---- copy: copy from input to output ----
  (define io-copy
    (case-lambda
      [(input output) (io-copy input output 4096)]
      [(input output buffer-size)
       (let ([in (if (string? input) (input-stream input) input)]
             [out (if (string? output) (output-stream output) output)]
             [buf (make-bytevector buffer-size)])
         (let loop ()
           (let ([n (get-bytevector-n! in buf 0 buffer-size)])
             (unless (eof-object? n)
               (put-bytevector out buf 0 n)
               (loop))))
         (flush-output-port out))]))

  ;; ---- line-seq: lazy sequence of lines from a reader ----
  ;; Returns a list (not truly lazy, but convenient)
  (define (line-seq port)
    (let loop ([acc '()])
      (let ([line (get-line port)])
        (if (eof-object? line)
            (reverse acc)
            (loop (cons line acc))))))

) ;; end library
