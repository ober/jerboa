#!chezscheme
;;; (std io strio) — String-based I/O with readers/writers
;;;
;;; Provides cursor-based string readers with position/line/column tracking,
;;; and accumulating string writers.

(library (std io strio)
  (export
    make-string-reader string-reader?
    reader-read-char reader-peek-char
    reader-read-line reader-read-while reader-read-until
    reader-position reader-line reader-column
    reader-eof?
    make-string-writer string-writer?
    writer-write-char writer-write-string
    writer-get-string)

  (import (chezscheme))

  ;; ========== String Reader ==========

  (define-record-type string-reader
    (fields
      (immutable str sr-str)                  ; source string
      (immutable len sr-len)                  ; string length (cached)
      (mutable pos  sr-pos  set-sr-pos!)       ; current character position
      (mutable line sr-line set-sr-line!)       ; current line number (1-based)
      (mutable col  sr-col  set-sr-col!))      ; current column number (0-based)
    (protocol
      (lambda (new)
        (lambda (str)
          (unless (string? str)
            (error 'make-string-reader "expected string" str))
          (new str (string-length str) 0 1 0)))))

  (define (reader-position sr)
    (sr-pos sr))

  (define (reader-line sr)
    (sr-line sr))

  (define (reader-column sr)
    (sr-col sr))

  (define (reader-eof? sr)
    (>= (sr-pos sr) (sr-len sr)))

  (define (reader-read-char sr)
    (if (reader-eof? sr)
        (eof-object)
        (let ([ch (string-ref (sr-str sr) (sr-pos sr))])
          (set-sr-pos! sr (+ (sr-pos sr) 1))
          (cond
            [(char=? ch #\newline)
             (set-sr-line! sr (+ (sr-line sr) 1))
             (set-sr-col! sr 0)]
            [else
             (set-sr-col! sr (+ (sr-col sr) 1))])
          ch)))

  (define (reader-peek-char sr)
    (if (reader-eof? sr)
        (eof-object)
        (string-ref (sr-str sr) (sr-pos sr))))

  (define (reader-read-line sr)
    ;; Read until newline or EOF. Returns string without the newline.
    ;; Returns eof-object if already at EOF.
    (if (reader-eof? sr)
        (eof-object)
        (let ([str (sr-str sr)]
              [len (sr-len sr)]
              [start (sr-pos sr)])
          (let loop ([i start])
            (cond
              [(>= i len)
               ;; EOF before newline
               (set-sr-pos! sr i)
               (set-sr-col! sr (+ (sr-col sr) (- i start)))
               (substring str start i)]
              [(char=? (string-ref str i) #\newline)
               (set-sr-pos! sr (+ i 1))
               (set-sr-line! sr (+ (sr-line sr) 1))
               (set-sr-col! sr 0)
               ;; Handle CRLF: strip trailing CR
               (let ([end (if (and (> i start)
                                   (char=? (string-ref str (- i 1)) #\return))
                              (- i 1)
                              i)])
                 (substring str start end))]
              [else (loop (+ i 1))])))))

  (define (reader-read-while sr pred)
    ;; Read characters while pred returns true. Returns string of matched chars.
    (let ([start (sr-pos sr)]
          [str (sr-str sr)]
          [len (sr-len sr)])
      (let loop ([i start])
        (if (and (< i len) (pred (string-ref str i)))
            (loop (+ i 1))
            (begin
              ;; Update position tracking for each consumed character
              (do ([j start (+ j 1)])
                ((= j i))
                (if (char=? (string-ref str j) #\newline)
                    (begin
                      (set-sr-line! sr (+ (sr-line sr) 1))
                      (set-sr-col! sr 0))
                    (set-sr-col! sr (+ (sr-col sr) 1))))
              (set-sr-pos! sr i)
              (substring str start i))))))

  (define (reader-read-until sr pred)
    ;; Read characters until pred returns true (or EOF). Returns string.
    ;; The delimiter character is NOT consumed.
    (reader-read-while sr (lambda (ch) (not (pred ch)))))

  ;; ========== String Writer ==========

  (define-record-type string-writer
    (fields
      (mutable chunks    sw-chunks    set-sw-chunks!)       ; list of strings (reverse order)
      (mutable total-len sw-total-len set-sw-total-len!))   ; total accumulated length
    (protocol
      (lambda (new)
        (lambda ()
          (new '() 0)))))

  (define (writer-write-char sw ch)
    (set-sw-chunks! sw (cons (string ch) (sw-chunks sw)))
    (set-sw-total-len! sw (+ (sw-total-len sw) 1)))

  (define (writer-write-string sw str)
    (unless (zero? (string-length str))
      (set-sw-chunks! sw (cons str (sw-chunks sw)))
      (set-sw-total-len! sw (+ (sw-total-len sw) (string-length str)))))

  (define (writer-get-string sw)
    ;; Concatenate all chunks into a single string.
    (let ([total (sw-total-len sw)])
      (if (zero? total)
          ""
          (let ([result (make-string total)])
            (let loop ([chunks (sw-chunks sw)] [pos total])
              (if (null? chunks)
                  result
                  (let* ([s (car chunks)]
                         [len (string-length s)]
                         [start (- pos len)])
                    (string-copy! s 0 result start len)
                    (loop (cdr chunks) start))))))))

) ;; end library
