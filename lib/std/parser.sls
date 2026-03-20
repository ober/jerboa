#!chezscheme
(library (std parser)
  (export
    ;; Core types
    make-parse-result parse-result-value parse-result-rest parse-result?
    make-parse-failure parse-failure-message parse-failure-position parse-failure?
    parse-success?

    ;; Base parsers
    parse-char
    parse-literal
    parse-eof
    parse-satisfy
    parse-any-char

    ;; Combinators
    parse-seq
    parse-alt
    parse-many
    parse-many1
    parse-optional
    parse-between
    parse-sep-by
    parse-map

    ;; Running
    parse-string
    parse-string*)

  (import (chezscheme))

  ;;; -------------------------------------------------------------------------
  ;;; Core record types
  ;;; -------------------------------------------------------------------------

  (define-record-type parse-result
    (fields value rest))

  (define-record-type parse-failure
    (fields message position))

  ;; Alias: parse-success? is the same predicate as parse-result?
  (define parse-success? parse-result?)

  ;;; -------------------------------------------------------------------------
  ;;; Base parsers
  ;;;
  ;;; A parser is a procedure: (lambda (str pos) -> parse-result | parse-failure)
  ;;; where str is the input string and pos is the current index (fixnum).
  ;;; -------------------------------------------------------------------------

  ;; Match a single character satisfying predicate pred.
  (define (parse-char pred)
    (lambda (str pos)
      (if (< pos (string-length str))
          (let ((c (string-ref str pos)))
            (if (pred c)
                (make-parse-result c (+ pos 1))
                (make-parse-failure
                  (string-append "unexpected character: "
                                 (string c))
                  pos)))
          (make-parse-failure "unexpected end of input" pos))))

  ;; Alias for parse-char.
  (define parse-satisfy parse-char)

  ;; Match any single character.
  (define (parse-any-char)
    (parse-char (lambda (c) #t)))

  ;; Match the exact string literal lit.
  (define (parse-literal lit)
    (let ((len (string-length lit)))
      (lambda (str pos)
        (let ((end (+ pos len)))
          (if (and (<= end (string-length str))
                   (string=? lit (substring str pos end)))
              (make-parse-result lit end)
              (make-parse-failure
                (string-append "expected literal: " lit)
                pos))))))

  ;; Match end of input.
  (define (parse-eof)
    (lambda (str pos)
      (if (= pos (string-length str))
          (make-parse-result 'eof pos)
          (make-parse-failure "expected end of input" pos))))

  ;;; -------------------------------------------------------------------------
  ;;; Combinators
  ;;; -------------------------------------------------------------------------

  ;; Run parsers in sequence; return a list of their results.
  ;; Returns a failure as soon as any parser fails.
  (define (parse-seq . parsers)
    (lambda (str pos)
      (let loop ((ps parsers) (pos pos) (acc '()))
        (if (null? ps)
            (make-parse-result (reverse acc) pos)
            (let ((r ((car ps) str pos)))
              (if (parse-failure? r)
                  r
                  (loop (cdr ps)
                        (parse-result-rest r)
                        (cons (parse-result-value r) acc))))))))

  ;; Try each parser in order; return the first success.
  ;; Returns the failure from the last parser if all fail.
  (define (parse-alt . parsers)
    (lambda (str pos)
      (let loop ((ps parsers) (last-fail #f))
        (if (null? ps)
            (or last-fail
                (make-parse-failure "no alternatives" pos))
            (let ((r ((car ps) str pos)))
              (if (parse-result? r)
                  r
                  (loop (cdr ps) r)))))))

  ;; Zero or more repetitions of parser p; always succeeds.
  (define (parse-many p)
    (lambda (str pos)
      (let loop ((pos pos) (acc '()))
        (let ((r (p str pos)))
          (if (parse-failure? r)
              (make-parse-result (reverse acc) pos)
              (loop (parse-result-rest r)
                    (cons (parse-result-value r) acc)))))))

  ;; One or more repetitions of parser p; fails if p doesn't match at least once.
  (define (parse-many1 p)
    (lambda (str pos)
      (let ((first (p str pos)))
        (if (parse-failure? first)
            first
            (let loop ((pos (parse-result-rest first))
                       (acc (list (parse-result-value first))))
              (let ((r (p str pos)))
                (if (parse-failure? r)
                    (make-parse-result (reverse acc) pos)
                    (loop (parse-result-rest r)
                          (cons (parse-result-value r) acc)))))))))

  ;; Zero or one occurrence of p; returns default if p fails (without consuming input).
  (define (parse-optional p default)
    (lambda (str pos)
      (let ((r (p str pos)))
        (if (parse-failure? r)
            (make-parse-result default pos)
            r))))

  ;; Parse p bracketed by open and close parsers; returns value of p.
  (define (parse-between open close p)
    (lambda (str pos)
      (let ((r-open (open str pos)))
        (if (parse-failure? r-open)
            r-open
            (let ((r-p (p str (parse-result-rest r-open))))
              (if (parse-failure? r-p)
                  r-p
                  (let ((r-close (close str (parse-result-rest r-p))))
                    (if (parse-failure? r-close)
                        r-close
                        (make-parse-result (parse-result-value r-p)
                                           (parse-result-rest r-close))))))))))

  ;; Parse one or more occurrences of p separated by sep.
  ;; Returns a list of p's values (sep values are discarded).
  (define (parse-sep-by p sep)
    (lambda (str pos)
      (let ((first (p str pos)))
        (if (parse-failure? first)
            ;; Zero occurrences — return empty list as success.
            (make-parse-result '() pos)
            (let loop ((pos (parse-result-rest first))
                       (acc (list (parse-result-value first))))
              (let ((r-sep (sep str pos)))
                (if (parse-failure? r-sep)
                    (make-parse-result (reverse acc) pos)
                    (let ((r-p (p str (parse-result-rest r-sep))))
                      (if (parse-failure? r-p)
                          ;; sep matched but p did not — do not consume sep
                          (make-parse-result (reverse acc) pos)
                          (loop (parse-result-rest r-p)
                                (cons (parse-result-value r-p) acc)))))))))))

  ;; Transform the successful result of p with function f.
  (define (parse-map p f)
    (lambda (str pos)
      (let ((r (p str pos)))
        (if (parse-failure? r)
            r
            (make-parse-result (f (parse-result-value r))
                               (parse-result-rest r))))))

  ;;; -------------------------------------------------------------------------
  ;;; Running
  ;;; -------------------------------------------------------------------------

  ;; Run parser on string str starting at position 0.
  ;; Returns the parse-result on success or raises an error on failure.
  ;; Non-throwing: returns parse-result or parse-failure
  (define (parse-string* parser str)
    (parser str 0))

  ;; Throwing: raises error on failure
  (define (parse-string parser str)
    (let ((r (parser str 0)))
      (if (parse-failure? r)
          (error 'parse-string
                 (parse-failure-message r)
                 (parse-failure-position r))
          r)))

) ;; end library (std parser)
