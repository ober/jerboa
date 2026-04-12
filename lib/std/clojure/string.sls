#!chezscheme
;;; (std clojure string) — clojure.string compatibility
;;;
;;; Provides Clojure's clojure.string API names mapped to Jerboa
;;; equivalents. Import as:
;;;   (import (prefix (std clojure string) str:))
;;;   (str:split "a,b,c" #\,)  ;; => ("a" "b" "c")

(library (std clojure string)
  (export
    ;; clojure.string names
    blank?
    capitalize
    ends-with?
    escape
    includes?
    clj-index-of
    join
    lower-case
    upper-case
    replace
    replace-first
    re-quote-replacement
    reverse
    split
    split-lines
    starts-with?
    trim
    trim-newline
    triml
    trimr)

  (import (except (chezscheme) reverse)
          (only (jerboa runtime)
                keyword? keyword->string))

  ;; blank? — true if nil, empty, or only whitespace
  (define (blank? s)
    (or (not s)
        (and (string? s)
             (let loop ([i 0])
               (or (= i (string-length s))
                   (and (char-whitespace? (string-ref s i))
                        (loop (+ i 1))))))))

  ;; capitalize — upper-case first char, lower-case rest
  (define (capitalize s)
    (if (or (not s) (zero? (string-length s)))
        s
        (string-append
          (string (char-upcase (string-ref s 0)))
          (string-downcase (substring s 1 (string-length s))))))

  ;; ends-with? — does s end with substr?
  (define (ends-with? s substr)
    (let ([slen (string-length s)]
          [sublen (string-length substr)])
      (and (>= slen sublen)
           (string=? (substring s (- slen sublen) slen) substr))))

  ;; escape — replace chars in s using a char-map (alist of char -> string)
  (define (escape s cmap)
    (let ([out (open-output-string)])
      (let loop ([i 0])
        (when (< i (string-length s))
          (let* ([c (string-ref s i)]
                 [replacement (assv c cmap)])
            (if replacement
                (put-string out (cdr replacement))
                (put-char out c))
            (loop (+ i 1)))))
      (get-output-string out)))

  ;; includes? — does s contain substr?
  (define (includes? s substr)
    (let ([slen (string-length s)]
          [sublen (string-length substr)])
      (if (> sublen slen)
          #f
          (let loop ([i 0])
            (cond
              [(> (+ i sublen) slen) #f]
              [(string=? (substring s i (+ i sublen)) substr) #t]
              [else (loop (+ i 1))])))))

  ;; index-of — index of substr in s, or #f
  (define clj-index-of
    (case-lambda
      [(s value)
       (clj-index-of s value 0)]
      [(s value from-index)
       (cond
         [(char? value)
          (let loop ([i from-index])
            (cond
              [(>= i (string-length s)) #f]
              [(char=? (string-ref s i) value) i]
              [else (loop (+ i 1))]))]
         [(string? value)
          (let ([sublen (string-length value)])
            (let loop ([i from-index])
              (cond
                [(> (+ i sublen) (string-length s)) #f]
                [(string=? (substring s i (+ i sublen)) value) i]
                [else (loop (+ i 1))])))]
         [else #f])]))

  ;; join — join strings with separator
  (define join
    (case-lambda
      [(coll)
       (apply string-append
              (map (lambda (x) (if (string? x) x (format "~a" x))) coll))]
      [(separator coll)
       (let ([strs (map (lambda (x) (if (string? x) x (format "~a" x))) coll)])
         (if (null? strs)
             ""
             (let loop ([rest (cdr strs)] [acc (car strs)])
               (if (null? rest)
                   acc
                   (loop (cdr rest)
                         (string-append acc separator (car rest)))))))]))

  ;; lower-case / upper-case
  (define (lower-case s) (string-downcase s))
  (define (upper-case s) (string-upcase s))

  ;; replace — replace all occurrences of match with replacement
  (define (replace s match replacement)
    (cond
      [(char? match)
       (let ([out (open-output-string)])
         (let loop ([i 0])
           (when (< i (string-length s))
             (let ([c (string-ref s i)])
               (if (char=? c match)
                   (put-string out (if (char? replacement)
                                       (string replacement)
                                       replacement))
                   (put-char out c))
               (loop (+ i 1)))))
         (get-output-string out))]
      [(string? match)
       (let ([mlen (string-length match)]
             [out (open-output-string)])
         (let loop ([i 0])
           (cond
             [(>= i (string-length s))
              (get-output-string out)]
             [(and (<= (+ i mlen) (string-length s))
                   (string=? (substring s i (+ i mlen)) match))
              (put-string out replacement)
              (loop (+ i mlen))]
             [else
              (put-char out (string-ref s i))
              (loop (+ i 1))])))]
      [else (error 'replace "match must be a string or char" match)]))

  ;; replace-first — replace first occurrence only
  (define (replace-first s match replacement)
    (cond
      [(char? match)
       (let ([idx (clj-index-of s match)])
         (if (not idx)
             s
             (string-append
               (substring s 0 idx)
               (if (char? replacement) (string replacement) replacement)
               (substring s (+ idx 1) (string-length s)))))]
      [(string? match)
       (let ([idx (clj-index-of s match)])
         (if (not idx)
             s
             (string-append
               (substring s 0 idx)
               replacement
               (substring s (+ idx (string-length match)) (string-length s)))))]
      [else (error 'replace-first "match must be a string or char" match)]))

  ;; re-quote-replacement — escape special chars in replacement string
  (define (re-quote-replacement replacement)
    (replace (replace replacement "\\" "\\\\") "$" "\\$"))

  ;; reverse
  (define (reverse s)
    (list->string (clj-reverse-list (string->list s))))

  (define (clj-reverse-list lst)
    (let loop ([l lst] [acc '()])
      (if (null? l) acc (loop (cdr l) (cons (car l) acc)))))

  ;; split — split string by char or string delimiter
  (define split
    (case-lambda
      [(s re)
       (split s re -1)]
      [(s re limit)
       (cond
         [(char? re)
          (%split-by-char s re limit)]
         [(string? re)
          (if (= (string-length re) 1)
              (%split-by-char s (string-ref re 0) limit)
              (%split-by-string s re limit))]
         [else (error 'split "separator must be a string or char" re)])]))

  (define (%split-by-char s ch limit)
    (let ([slen (string-length s)])
      (let loop ([i 0] [start 0] [parts '()] [count 1])
        (cond
          [(and (> limit 0) (= count limit))
           (clj-reverse-list (cons (substring s start slen) parts))]
          [(= i slen)
           (clj-reverse-list (cons (substring s start slen) parts))]
          [(char=? (string-ref s i) ch)
           (loop (+ i 1) (+ i 1)
                 (cons (substring s start i) parts)
                 (+ count 1))]
          [else
           (loop (+ i 1) start parts count)]))))

  (define (%split-by-string s sep limit)
    (let ([slen (string-length s)]
          [seplen (string-length sep)])
      (let loop ([i 0] [start 0] [parts '()] [count 1])
        (cond
          [(and (> limit 0) (= count limit))
           (clj-reverse-list (cons (substring s start slen) parts))]
          [(> (+ i seplen) slen)
           (clj-reverse-list (cons (substring s start slen) parts))]
          [(string=? (substring s i (+ i seplen)) sep)
           (loop (+ i seplen) (+ i seplen)
                 (cons (substring s start i) parts)
                 (+ count 1))]
          [else
           (loop (+ i 1) start parts count)]))))

  ;; split-lines — split on newlines
  (define (split-lines s)
    (split (replace s "\r\n" "\n") "\n"))

  ;; starts-with?
  (define (starts-with? s substr)
    (let ([slen (string-length s)]
          [sublen (string-length substr)])
      (and (>= slen sublen)
           (string=? (substring s 0 sublen) substr))))

  ;; trim — remove leading and trailing whitespace
  (define (trim s)
    (let* ([slen (string-length s)]
           [start (let loop ([i 0])
                    (if (and (< i slen) (char-whitespace? (string-ref s i)))
                        (loop (+ i 1))
                        i))]
           [end (let loop ([i slen])
                  (if (and (> i start) (char-whitespace? (string-ref s (- i 1))))
                      (loop (- i 1))
                      i))])
      (substring s start end)))

  ;; trim-newline — remove trailing newlines and carriage returns
  (define (trim-newline s)
    (let ([slen (string-length s)])
      (let loop ([i slen])
        (if (and (> i 0)
                 (let ([c (string-ref s (- i 1))])
                   (or (char=? c #\newline) (char=? c #\return))))
            (loop (- i 1))
            (substring s 0 i)))))

  ;; triml — remove leading whitespace
  (define (triml s)
    (let ([slen (string-length s)])
      (let loop ([i 0])
        (if (and (< i slen) (char-whitespace? (string-ref s i)))
            (loop (+ i 1))
            (substring s i slen)))))

  ;; trimr — remove trailing whitespace
  (define (trimr s)
    (let ([slen (string-length s)])
      (let loop ([i slen])
        (if (and (> i 0) (char-whitespace? (string-ref s (- i 1))))
            (loop (- i 1))
            (substring s 0 i)))))

) ;; end library
