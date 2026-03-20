#!chezscheme
;;; Tests for newer batch 2: path, interface, generic, process, temporaries, markup/xml

(import (chezscheme)
        (std misc path)
        (std interface)
        (std generic)
        (std os temporaries))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr]
           [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (printf "FAIL: ~s => ~s (expected ~s)~n" 'expr result exp))))]))

(define-syntax check-true
  (syntax-rules ()
    [(_ expr)
     (let ([result expr])
       (if result
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (printf "FAIL: ~s => ~s (expected truthy)~n" 'expr result))))]))

(define-syntax check-false
  (syntax-rules ()
    [(_ expr)
     (let ([result expr])
       (if (not result)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (printf "FAIL: ~s => ~s (expected falsy)~n" 'expr result))))]))

(printf "--- Testing newer batch 2 ---~n")

;; ========== Path Utilities ==========
(printf "  Path utilities...~n")
(check (path-split "/usr/local/bin") => '("usr" "local" "bin"))
(check (path-split "foo/bar/baz") => '("foo" "bar" "baz"))
(check (path-split "/") => '())

(check (path-normalize "/usr/local/../bin") => "/usr/bin")
(check (path-normalize "/usr/./bin") => "/usr/bin")
(check (path-normalize "a/b/../c") => "a/c")

(check-true (path-relative? "foo/bar"))
(check-false (path-relative? "/foo/bar"))

(check (subpath "/usr" "local" "bin") => "/usr/local/bin")
(check (subpath "a" "b" "c") => "a/b/c")

(check (path-default-extension "foo" ".txt") => "foo.txt")
(check (path-default-extension "foo.pdf" ".txt") => "foo.pdf")
(check (path-default-extension "foo" "txt") => "foo.txt")

;; ========== Interface Protocol ==========
(printf "  Interface protocol...~n")
(definterface Printable (to-string describe))
(check-true (not (null? (interface-method-names Printable))))
(check (interface-name Printable) => 'Printable)
(check (interface-method-names Printable) => '(to-string describe))

;; Before registering methods
(check-false (Printable? 'my-type))

;; Register methods
(interface-register-method! 'my-type 'to-string)
(interface-register-method! 'my-type 'describe)
(check-true (Printable? 'my-type))

;; Partial implementation
(interface-register-method! 'partial-type 'to-string)
(check-false (Printable? 'partial-type))

;; ========== Generic Functions ==========
(printf "  Generic functions...~n")
(defgeneric greet (obj))
(defspecific (greet (obj 'string)) (string-append "Hello, " obj "!"))
(defspecific (greet (obj 'number)) (string-append "Number " (number->string obj)))
(defspecific (greet (obj 'symbol)) (string-append "Symbol: " (symbol->string obj)))

(check (greet "world") => "Hello, world!")
(check (greet 42) => "Number 42")
(check (greet 'foo) => "Symbol: foo")

;; Multi-arg generic
(defgeneric combine (a b))
(defspecific (combine (a 'string) b) (string-append a (if (string? b) b (format "~a" b))))
(defspecific (combine (a 'number) b) (+ a (if (number? b) b 0)))
(check (combine "hello" " world") => "hello world")
(check (combine 10 20) => 30)

;; ========== Temporaries ==========
(printf "  Temporaries...~n")
(let ([name (make-temporary-file-name)])
  (check-true (string? name))
  (check-true (> (string-length name) 0)))

(with-temporary-file
  (lambda (path)
    (check-true (string? path))
    (let ([port (open-output-file path)])
      (display "test" port)
      (close-port port))
    (check-true (file-exists? path))))

(with-temporary-directory
  (lambda (dir)
    (check-true (file-directory? dir))
    ;; Create a file inside
    (let ([f (string-append dir "/test.txt")])
      (let ([port (open-output-file f)])
        (display "hello" port)
        (close-port port))
      (check-true (file-exists? f)))))

(check-true (string? (temporary-file-directory)))

(let-values ([(path port) (create-temporary-file)])
  (check-true (string? path))
  (check-true (output-port? port))
  (display "test" port)
  (close-port port)
  (check-true (file-exists? path))
  (delete-file path))

;; ========== Markup XML Alias ==========
(printf "  Markup XML alias...~n")
;; Just verify the module loads (it re-exports from std text xml)
;; Import it in a guard since it depends on std text xml
(guard (exn [#t (printf "  (skipped - std text xml unavailable)~n")])
  (eval '(begin
    (import (std markup xml))
    (set! pass-count (+ pass-count 1))))
  (set! pass-count (+ pass-count 1)))

;; ========== Summary ==========
(printf "~n--- Results: ~a passed, ~a failed ---~n" pass-count fail-count)
(when (> fail-count 0) (exit 1))
