#!chezscheme
;;; :std/interpolate -- Compile-time string interpolation
;;;
;;; Usage:
;;;   (interpolate "Hello ${name}, you have ${count} items")
;;; Expands to:
;;;   (string-append "Hello " (<to-string> name) ", you have " (<to-string> count) " items")
;;;
;;; Limitation: expressions inside ${} must not contain nested braces.

(library (std interpolate)
  (export interpolate)
  (import (chezscheme))

  (define-syntax interpolate
    (lambda (stx)

      ;; Parse template string into list of (literal . "text") | (expr . "code")
      (define (parse-template str)
        (let ([len (string-length str)])
          (let loop ([i 0] [start 0] [acc '()])
            (cond
              [(>= i len)
               (reverse
                (if (> i start)
                    (cons (cons 'literal (substring str start i)) acc)
                    acc))]
              [(and (char=? (string-ref str i) #\$)
                    (< (+ i 1) len)
                    (char=? (string-ref str (+ i 1)) #\{))
               (let ([acc (if (> i start)
                              (cons (cons 'literal (substring str start i)) acc)
                              acc)])
                 (let brace-loop ([j (+ i 2)])
                   (cond
                     [(>= j len)
                      (syntax-violation 'interpolate
                        "unterminated ${...} in template" stx)]
                     [(char=? (string-ref str j) #\})
                      (let ([expr-text (substring str (+ i 2) j)])
                        (when (string=? expr-text "")
                          (syntax-violation 'interpolate
                            "empty ${} in template" stx))
                        (loop (+ j 1) (+ j 1)
                              (cons (cons 'expr expr-text) acc)))]
                     [else (brace-loop (+ j 1))])))]
              [else (loop (+ i 1) start acc)]))))

      (define (read-expr-string s)
        (let* ([p (open-input-string s)]
               [expr (read p)])
          (when (eof-object? expr)
            (syntax-violation 'interpolate
              (string-append "failed to read expression: " s) stx))
          expr))

      (syntax-case stx ()
        [(k tmpl)
         (string? (syntax->datum #'tmpl))
         (let ([segments (parse-template (syntax->datum #'tmpl))])
           (if (and (= (length segments) 1)
                    (eq? (caar segments) 'literal))
               #'tmpl
               (let ([parts
                      (map (lambda (seg)
                             (if (eq? (car seg) 'literal)
                                 (cdr seg)
                                 (let ([expr (read-expr-string (cdr seg))])
                                   `(let ([v ,expr])
                                      (if (string? v)
                                          v
                                          (call-with-string-output-port
                                           (lambda (p) (display v p))))))))
                           segments)])
                 (datum->syntax #'k
                   `(string-append ,@parts)))))])))

) ; end library
