#!chezscheme
;;; (std text template) -- Simple String Template Engine
;;;
;;; Mustache-inspired template engine for code generation and formatting.
;;;
;;; Syntax:
;;;   {{name}}         — variable substitution
;;;   {{#cond}}...{{/cond}}  — conditional section (truthy)
;;;   {{^cond}}...{{/cond}}  — inverted section (falsy)
;;;   {{#list}}...{{/list}}  — iteration (if list value)
;;;   {{!comment}}     — comment (removed)
;;;   {{>partial}}     — partial/include
;;;
;;; Usage:
;;;   (import (std text template))
;;;   (template-render "Hello {{name}}!" '((name . "world")))
;;;   ; => "Hello world!"
;;;
;;;   (define tpl (template-compile "{{#items}}* {{.}}\n{{/items}}"))
;;;   (tpl '((items "a" "b" "c")))
;;;   ; => "* a\n* b\n* c\n"

(library (std text template)
  (export
    template-render
    template-compile
    template-render-file
    template-escape-html
    make-template-env
    template-env-set!
    template-env-ref)

  (import (chezscheme))

  ;; ========== Template Environment ==========
  (define (make-template-env . pairs)
    ;; Create from alternating key value pairs or alist
    (if (and (= (length pairs) 1) (list? (car pairs)))
      (car pairs)  ;; already an alist
      (let loop ([p pairs] [acc '()])
        (if (or (null? p) (null? (cdr p)))
          (reverse acc)
          (loop (cddr p) (cons (cons (car p) (cadr p)) acc))))))

  (define (template-env-set! env key val)
    (cons (cons key val) env))

  (define (template-env-ref env key . default)
    ;; key can be string or symbol; try both
    (let ([pair (or (assoc key env)
                    (and (string? key)
                         (assoc (string->symbol key) env))
                    (and (symbol? key)
                         (assoc (symbol->string key) env)))])
      (if pair (cdr pair)
        (if (null? default) "" (car default)))))

  ;; ========== Compile ==========
  (define (template-compile template-str)
    ;; Returns a procedure: (lambda (env) -> string)
    (let ([tokens (tokenize template-str)])
      (let-values ([(tree rest) (parse-tokens tokens)])
        (lambda (env)
          (render-tree tree env '())))))

  ;; ========== Render ==========
  (define (template-render template-str env)
    ((template-compile template-str) env))

  (define (template-render-file path env)
    (let ([content (call-with-input-file path
                     (lambda (p) (read-all-string p)))])
      (template-render content env)))

  ;; ========== HTML Escaping ==========
  (define (template-escape-html s)
    (let ([out (open-output-string)])
      (string-for-each
        (lambda (c)
          (cond
            [(char=? c #\<) (display "&lt;" out)]
            [(char=? c #\>) (display "&gt;" out)]
            [(char=? c #\&) (display "&amp;" out)]
            [(char=? c #\") (display "&quot;" out)]
            [else (display c out)]))
        s)
      (get-output-string out)))

  ;; ========== Tokenizer ==========
  ;; Token types: (text . "str") | (var . "name") | (section . "name")
  ;;            | (invert . "name") | (end . "name") | (comment . "text")
  ;;            | (partial . "name")

  (define (tokenize str)
    (let ([n (string-length str)])
      (let loop ([i 0] [tokens '()])
        (if (>= i n)
          (reverse tokens)
          (let ([open-pos (find-substring str "{{" i)])
            (if (not open-pos)
              ;; Rest is text
              (reverse (cons (cons 'text (substring str i n)) tokens))
              (let ([close-pos (find-substring str "}}" (+ open-pos 2))])
                (if (not close-pos)
                  ;; Unclosed — treat rest as text
                  (reverse (cons (cons 'text (substring str i n)) tokens))
                  (let* ([before (if (> open-pos i)
                                   (list (cons 'text (substring str i open-pos)))
                                   '())]
                         [tag-content (string-trim* (substring str (+ open-pos 2) close-pos))]
                         [token (classify-tag tag-content)])
                    (loop (+ close-pos 2)
                          (append (if token (list token) '())
                                  before tokens)))))))))))

  (define (classify-tag content)
    (cond
      [(string=? content "") #f]
      [(char=? (string-ref content 0) #\!)
       (cons 'comment (substring content 1 (string-length content)))]
      [(char=? (string-ref content 0) #\#)
       (cons 'section (string-trim* (substring content 1 (string-length content))))]
      [(char=? (string-ref content 0) #\^)
       (cons 'invert (string-trim* (substring content 1 (string-length content))))]
      [(char=? (string-ref content 0) #\/)
       (cons 'end (string-trim* (substring content 1 (string-length content))))]
      [(char=? (string-ref content 0) #\>)
       (cons 'partial (string-trim* (substring content 1 (string-length content))))]
      [else (cons 'var content)]))

  ;; ========== Parser ==========
  ;; Builds a tree: list of (text . str) | (var . name)
  ;;              | (section name . children) | (invert name . children)

  (define (parse-tokens tokens)
    (let loop ([tokens tokens] [tree '()])
      (cond
        [(null? tokens)
         (values (reverse tree) '())]
        [(eq? (caar tokens) 'end)
         (values (reverse tree) (cdr tokens))]
        [(eq? (caar tokens) 'section)
         (let-values ([(children rest) (parse-tokens (cdr tokens))])
           (loop rest (cons (cons 'section (cons (cdar tokens) children)) tree)))]
        [(eq? (caar tokens) 'invert)
         (let-values ([(children rest) (parse-tokens (cdr tokens))])
           (loop rest (cons (cons 'invert (cons (cdar tokens) children)) tree)))]
        [(eq? (caar tokens) 'comment)
         (loop (cdr tokens) tree)]
        [else
         (loop (cdr tokens) (cons (car tokens) tree))])))

  ;; ========== Renderer ==========
  (define (render-tree tree env partials)
    (let ([out (open-output-string)])
      (for-each
        (lambda (node)
          (case (car node)
            [(text)
             (display (cdr node) out)]
            [(var)
             (display (lookup-var (cdr node) env) out)]
            [(section)
             (let* ([name (cadr node)]
                    [children (cddr node)]
                    [found (lookup-var-raw name env)]
                    [val (if found (cdr found) #f)])
               (cond
                 [(not found) (void)]  ;; missing key — skip
                 [(and (list? val) (not (null? val)))
                  ;; Iterate over list
                  (for-each
                    (lambda (item)
                      (let ([sub-env (if (and (pair? item) (pair? (car item)))
                                       (append item env)
                                       (cons (cons "." item) env))])
                        (display (render-tree children sub-env partials) out)))
                    val)]
                 [(and (list? val) (null? val))
                  (void)]  ;; empty list — skip
                 [(eq? val #f) (void)]  ;; falsy — skip
                 [else
                  ;; Truthy — render once
                  (display (render-tree children env partials) out)]))]
            [(invert)
             (let* ([name (cadr node)]
                    [children (cddr node)]
                    [found (lookup-var-raw name env)]
                    [val (if found (cdr found) #t)])  ;; missing = truthy for invert? No, missing = render
               ;; Render if falsy or empty list or not found
               (when (or (not found)
                         (eq? val #f)
                         (and (list? val) (null? val)))
                 (display (render-tree children env partials) out)))]))
        tree)
      (get-output-string out)))

  (define (lookup-var-raw name env)
    ;; Look up name in env, return (found . value) or #f
    (let ([sym-pair (assoc (string->symbol name) env)]
          [str-pair (assoc name env)])
      (cond
        [sym-pair (cons #t (cdr sym-pair))]
        [str-pair (cons #t (cdr str-pair))]
        [else #f])))

  (define (lookup-var name env)
    ;; Look up and format as string for {{var}} interpolation
    (let ([found (lookup-var-raw name env)])
      (if (not found) ""
        (let ([val (cdr found)])
          (cond
            [(string? val) val]
            [(number? val) (number->string val)]
            [(boolean? val) (if val "true" "false")]
            [(symbol? val) (symbol->string val)]
            [(list? val) ""]  ;; lists rendered via sections
            [else (format "~a" val)])))))

  ;; ========== Helpers ==========
  (define (find-substring str sub start)
    (let ([slen (string-length str)]
          [sublen (string-length sub)])
      (let loop ([i start])
        (cond
          [(> (+ i sublen) slen) #f]
          [(string=? (substring str i (+ i sublen)) sub) i]
          [else (loop (+ i 1))]))))

  (define (string-trim* str)
    (let* ([n (string-length str)]
           [s (let loop ([i 0])
                (if (or (= i n) (not (char-whitespace? (string-ref str i)))) i
                  (loop (+ i 1))))]
           [e (let loop ([i (- n 1)])
                (if (or (< i 0) (not (char-whitespace? (string-ref str i)))) (+ i 1)
                  (loop (- i 1))))])
      (if (>= s e) "" (substring str s e))))

  (define (read-all-string port)
    (let loop ([chunks '()])
      (let ([buf (get-string-n port 4096)])
        (if (eof-object? buf)
          (if (null? chunks) "" (apply string-append (reverse chunks)))
          (loop (cons buf chunks))))))

) ;; end library
