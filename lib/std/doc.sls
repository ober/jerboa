#!chezscheme
;;; (std doc) — Literate programming with executable examples (doc-tests)
;;;
;;; API:
;;;   (define/doc (name args ...) docstring body ...)  — define with doc
;;;   (get-doc name)                — retrieve docstring for a documented function
;;;   (run-doctests name)           — extract and run examples from docstring
;;;   (run-all-doctests)            — run all registered doctests
;;;   (doctest-summary)             — return (pass . fail) counts

(library (std doc)
  (export define/doc get-doc run-doctests run-all-doctests
          doctest-summary register-doc! list-documented
          *doctest-env*)

  (import (chezscheme))

  ;; ========== Doc registry ==========
  ;; Maps symbol -> (docstring . procedure)

  (define *doc-registry* (make-eq-hashtable))

  (define (register-doc! name docstring proc)
    (hashtable-set! *doc-registry* name (cons docstring proc)))

  (define (get-doc name)
    (let ([entry (hashtable-ref *doc-registry* name #f)])
      (and entry (car entry))))

  (define (list-documented)
    (vector->list (hashtable-keys *doc-registry*)))

  ;; ========== define/doc macro ==========

  (define-syntax define/doc
    (syntax-rules ()
      [(_ (name arg ...) docstring body ...)
       (begin
         (define (name arg ...) body ...)
         (register-doc! 'name docstring name))]
      [(_ name docstring expr)
       (begin
         (define name expr)
         (register-doc! 'name docstring name))]))

  ;; ========== Doctest parser ==========
  ;; Extracts lines matching: (expr) ;=> expected

  (define (parse-doctests docstring)
    (let ([lines (string-split-lines docstring)]
          [tests '()])
      (let loop ([ls lines] [acc '()])
        (cond
          [(null? ls) (reverse acc)]
          [else
           (let* ([line (string-trim-ws (car ls))]
                  [test (parse-doctest-line line)])
             (if test
               (loop (cdr ls) (cons test acc))
               (loop (cdr ls) acc)))]))))

  (define (parse-doctest-line line)
    ;; Match: (expr) ;=> expected  or  (expr) ; => expected
    (let ([pos (find-arrow line)])
      (and pos
           (let* ([expr-str (string-trim-ws (substring line 0 pos))]
                  [rest (substring line (+ pos (if (and (< (+ pos 1) (string-length line))
                                                        (char=? (string-ref line (+ pos 1)) #\>))
                                                  3  ;; ;=>
                                                  4)) ;; ; =>
                                   (string-length line))]
                  [expected-str (string-trim-ws rest)])
             (and (> (string-length expr-str) 0)
                  (> (string-length expected-str) 0)
                  (cons expr-str expected-str))))))

  (define (find-arrow str)
    ;; Find ";=>" or "; =>" in str
    (let ([len (string-length str)])
      (let loop ([i 0])
        (cond
          [(>= i len) #f]
          [(and (char=? (string-ref str i) #\;)
                (< (+ i 2) len)
                (char=? (string-ref str (+ i 1)) #\=)
                (char=? (string-ref str (+ i 2)) #\>))
           i]
          [(and (char=? (string-ref str i) #\;)
                (< (+ i 3) len)
                (char=? (string-ref str (+ i 1)) #\space)
                (char=? (string-ref str (+ i 2)) #\=)
                (char=? (string-ref str (+ i 3)) #\>))
           i]
          [else (loop (+ i 1))]))))

  (define (string-split-lines s)
    (let loop ([i 0] [start 0] [acc '()])
      (cond
        [(= i (string-length s))
         (reverse (cons (substring s start i) acc))]
        [(char=? (string-ref s i) #\newline)
         (loop (+ i 1) (+ i 1) (cons (substring s start i) acc))]
        [else (loop (+ i 1) start acc)])))

  (define (string-trim-ws s)
    (let* ([len (string-length s)]
           [start (let loop ([i 0])
                    (if (and (< i len) (char-whitespace? (string-ref s i)))
                      (loop (+ i 1))
                      i))]
           [end (let loop ([i len])
                  (if (and (> i start) (char-whitespace? (string-ref s (- i 1))))
                    (loop (- i 1))
                    i))])
      (substring s start end)))

  ;; ========== Doctest runner ==========

  (define *doctest-pass* 0)
  (define *doctest-fail* 0)

  (define *doctest-env* (make-thread-parameter #f))

  (define (run-doctests name . env-opt)
    (let ([entry (hashtable-ref *doc-registry* name #f)])
      (unless entry
        (error 'run-doctests "no documentation registered for" name))
      (let* ([docstring (car entry)]
             [proc (cdr entry)]
             [tests (parse-doctests docstring)]
             [env (if (pair? env-opt) (car env-opt)
                      (or (*doctest-env*)
                          (interaction-environment)))]
             [pass 0]
             [fail 0])
        (for-each
          (lambda (test)
            (let ([expr-str (car test)]
                  [expected-str (cdr test)])
              (guard (exn
                      [#t (set! fail (+ fail 1))
                          (set! *doctest-fail* (+ *doctest-fail* 1))
                          (printf "  FAIL ~a: ~a raised exception~n" name expr-str)])
                (let ([got (eval (read (open-input-string expr-str)) env)]
                      [expected (eval (read (open-input-string expected-str)) env)])
                  (if (equal? got expected)
                    (begin
                      (set! pass (+ pass 1))
                      (set! *doctest-pass* (+ *doctest-pass* 1)))
                    (begin
                      (set! fail (+ fail 1))
                      (set! *doctest-fail* (+ *doctest-fail* 1))
                      (printf "  FAIL ~a: ~a => ~s (expected ~s)~n"
                              name expr-str got expected)))))))
          tests)
        (cons pass fail))))

  (define (run-all-doctests)
    (set! *doctest-pass* 0)
    (set! *doctest-fail* 0)
    (let ([names (list-documented)])
      (for-each
        (lambda (name)
          (run-doctests name))
        names)
      (cons *doctest-pass* *doctest-fail*)))

  (define (doctest-summary)
    (cons *doctest-pass* *doctest-fail*))

) ;; end library
