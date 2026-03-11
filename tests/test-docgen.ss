#!chezscheme
;;; tests/test-docgen.ss -- Tests for (std doc generator)

(import (chezscheme) (std doc generator))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(printf "--- Phase 2e: Doc Generator ---~%~%")

;; ---- helper ----
(define (string-contains haystack needle)
  (let ([hlen (string-length haystack)]
        [nlen (string-length needle)])
    (let loop ([i 0])
      (cond
        [(> (+ i nlen) hlen) #f]
        [(string=? (substring haystack i (+ i nlen)) needle) #t]
        [else (loop (+ i 1))]))))

;; ---- 1. make-doc-entry and accessors ----
(let ([e (make-doc-entry "my-func" 'procedure "Does something useful" '("(my-func 42) => 42"))])
  (test "doc-entry-name"    (doc-entry-name e)     "my-func")
  (test "doc-entry-type"    (doc-entry-type e)     'procedure)
  (test "doc-entry-doc"     (doc-entry-doc e)      "Does something useful")
  (test "doc-entry-examples" (doc-entry-examples e) '("(my-func 42) => 42")))

;; ---- 2. doc-procedure / doc-syntax / doc-value / doc-module ----
(let ([p (doc-procedure "add" "a b" "Adds two numbers")]
      [s (doc-syntax "when" "test body ..." "Conditional expression")]
      [v (doc-value "pi" "Mathematical pi constant")]
      [m (doc-module "mymod" "My module")])
  (test "doc-procedure-type" (doc-entry-type p) 'procedure)
  (test "doc-syntax-type"    (doc-entry-type s) 'syntax)
  (test "doc-value-type"     (doc-entry-type v) 'value)
  (test "doc-module-type"    (doc-entry-type m) 'module)
  (test "doc-procedure-name" (doc-entry-name p) "add"))

;; ---- 3. format-signature ----
(let ([e (doc-procedure "greet" "name" "Greets a person")])
  (test "format-signature" (format-signature e) "(greet name)"))
(let ([e (doc-value "answer" "The answer to everything")])
  (test "format-signature-no-sig" (format-signature e) "answer"))

;; ---- 4. parse-docstring ----
(let* ([text ";; Doc: A useful function\n;; Example: (foo 1 2)\n"]
       [parsed (parse-docstring text)])
  (test "parse-docstring-doc"
        (cdr (assq 'doc parsed))
        "A useful function")
  (test "parse-docstring-examples"
        (cdr (assq 'examples parsed))
        '("(foo 1 2)")))

;; ---- 5. generate-markdown ----
(let* ([entries (list (make-doc-entry "square" 'procedure "Squares a number"
                                      '("(square 5) => 25"))
                      (make-doc-entry "cube" 'procedure "Cubes a number" '()))]
       [md (generate-markdown entries)])
  (test "markdown-contains-square"
        (string-contains md "## `square`")
        #t)
  (test "markdown-contains-type"
        (string-contains md "**Type:** procedure")
        #t)
  (test "markdown-contains-example"
        (string-contains md "(square 5) => 25")
        #t)
  (test "markdown-contains-cube"
        (string-contains md "## `cube`")
        #t))

;; ---- 6. generate-html ----
(let* ([entries (list (make-doc-entry "foo" 'procedure "Foo function" '()))]
       [html (generate-html entries)])
  (test "html-doctype"         (string-contains html "<!DOCTYPE html>") #t)
  (test "html-contains-foo"    (string-contains html "<code>foo</code>") #t)
  (test "html-contains-type"   (string-contains html "procedure") #t))

;; ---- 7. HTML escaping ----
(let* ([e (make-doc-entry "<b>tricky</b>" 'value "Has <html> & chars" '())]
       [html (generate-html (list e))])
  (test "html-escapes-name"   (string-contains html "&lt;b&gt;tricky&lt;/b&gt;") #t)
  (test "html-escapes-doc"    (string-contains html "&lt;html&gt; &amp; chars")  #t))

;; ---- 8. write-docs creates a file ----
(let* ([entries (list (make-doc-entry "test-fn" 'procedure "Test" '()))]
       [tmpfile "/tmp/test-docgen-output.md"])
  (when (file-exists? tmpfile) (delete-file tmpfile))
  (write-docs entries tmpfile 'markdown)
  (test "write-docs-creates-file" (file-exists? tmpfile) #t)
  (let ([content (call-with-input-file tmpfile
                   (lambda (p) (let loop ([acc '()])
                     (let ([c (read-char p)])
                       (if (eof-object? c) (list->string (reverse acc))
                           (loop (cons c acc)))))))])
    (test "write-docs-content" (string-contains content "test-fn") #t))
  (delete-file tmpfile))

;; ---- 9. extract-docs from a temp file ----
(let* ([tmpfile "/tmp/test-docgen-src.ss"]
       [src ";; Doc: square (procedure): Squares its argument\n(define (square x) (* x x))\n"])
  (call-with-output-file tmpfile
    (lambda (p) (display src p))
    'truncate)
  (let ([docs (extract-docs tmpfile)])
    (test "extract-docs-count" (>= (length docs) 1) #t)
    (when (>= (length docs) 1)
      (let ([e (car docs)])
        (test "extract-docs-name" (doc-entry-name e) "square")
        (test "extract-docs-type" (doc-entry-type e) 'procedure))))
  (delete-file tmpfile))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
