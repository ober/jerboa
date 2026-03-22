#!/usr/bin/env scheme-script
#!chezscheme
;;; Tests for roundtrip YAML parser/emitter

(import (chezscheme)
        (std text yaml))

(define pass-count 0)
(define fail-count 0)
(define test-count 0)

(define-syntax test
  (syntax-rules (=>)
    [(_ name expr => expected)
     (begin
       (set! test-count (+ test-count 1))
       (guard (e [#t (set! fail-count (+ fail-count 1))
                     (display "FAIL: ") (display name)
                     (display " — exception: ")
                     (display (condition-message e))
                     (newline)])
         (let ([result expr] [exp expected])
           (if (equal? result exp)
               (begin (set! pass-count (+ pass-count 1))
                      (display "  ok: ") (display name) (newline))
               (begin (set! fail-count (+ fail-count 1))
                      (display "FAIL: ") (display name) (newline)
                      (display "  expected: ") (write exp) (newline)
                      (display "  got:      ") (write result) (newline))))))]))

(define-syntax test-roundtrip
  (syntax-rules ()
    [(_ name input)
     (begin
       (set! test-count (+ test-count 1))
       (guard (e [#t (set! fail-count (+ fail-count 1))
                     (display "FAIL: ") (display name)
                     (display " — exception: ")
                     (display (condition-message e))
                     (newline)])
         (let* ([doc (yaml-read-string input)]
                [output (yaml-write-string doc)])
           (if (string=? output input)
               (begin (set! pass-count (+ pass-count 1))
                      (display "  ok: ") (display name) (newline))
               (begin (set! fail-count (+ fail-count 1))
                      (display "FAIL: ") (display name) (newline)
                      (display "  input:  ") (write input) (newline)
                      (display "  output: ") (write output) (newline))))))]))

(display "=== YAML Roundtrip Tests ===") (newline)

;; ---------------------------------------------------------------------------
;; Basic parsing (simple mode)
;; ---------------------------------------------------------------------------
(display "--- Simple mode parsing ---") (newline)

(test "plain scalar"
  (yaml-load-string "hello")
  => "hello")

(test "integer"
  (yaml-load-string "42")
  => 42)

(test "float"
  (yaml-load-string "3.14")
  => 3.14)

(test "boolean true"
  (yaml-load-string "true")
  => #t)

(test "boolean false"
  (yaml-load-string "false")
  => #f)

(test "null"
  (yaml-load-string "null")
  => (void))

(test "null tilde"
  (yaml-load-string "~")
  => (void))

(test "hex integer"
  (yaml-load-string "0xFF")
  => 255)

(test "octal integer"
  (yaml-load-string "0o77")
  => 63)

(test "simple mapping"
  (yaml-load-string "name: John\nage: 30\n")
  => '(("name" . "John") ("age" . 30)))

(test "simple sequence"
  (yaml-load-string "- one\n- two\n- three\n")
  => '("one" "two" "three"))

(test "nested mapping"
  (yaml-load-string "person:\n  name: John\n  age: 30\n")
  => '(("person" . (("name" . "John") ("age" . 30)))))

(test "mapping with sequence value"
  (yaml-load-string "items:\n  - alpha\n  - beta\n")
  => '(("items" . ("alpha" "beta"))))

(test "sequence of mappings"
  (yaml-load-string "- name: a\n  val: 1\n- name: b\n  val: 2\n")
  => '((("name" . "a") ("val" . 1))
       (("name" . "b") ("val" . 2))))

(test "flow mapping"
  (yaml-load-string "{a: 1, b: 2}")
  => '(("a" . 1) ("b" . 2)))

(test "flow sequence"
  (yaml-load-string "[1, 2, 3]")
  => '(1 2 3))

(test "single quoted string"
  (yaml-load-string "name: 'John Doe'")
  => '(("name" . "John Doe")))

(test "double quoted string"
  (yaml-load-string "name: \"John Doe\"")
  => '(("name" . "John Doe")))

(test "double quoted with escapes"
  (yaml-load-string "msg: \"hello\\nworld\"")
  => '(("msg" . "hello\nworld")))

(test "empty value"
  (let ((result (yaml-load-string "key:")))
    (and (pair? result)
         (string=? (caar result) "key")
         (eq? (cdar result) (void))))
  => #t)

(test "symbol keys"
  (parameterize ([yaml-key-format 'symbol])
    (yaml-load-string "name: test"))
  => '((name . "test")))

;; ---------------------------------------------------------------------------
;; Roundtrip mode - node types
;; ---------------------------------------------------------------------------
(display "--- Roundtrip mode ---") (newline)

(test "read scalar node"
  (let ([doc (yaml-read-string "hello")])
    (and (yaml-document? doc)
         (yaml-scalar? (yaml-document-root doc))
         (yaml-scalar-value (yaml-document-root doc))))
  => "hello")

(test "read mapping node"
  (let* ([doc (yaml-read-string "a: 1\nb: 2\n")]
         [root (yaml-document-root doc)])
    (and (yaml-mapping? root)
         (length (yaml-mapping-pairs root))))
  => 2)

(test "mapping-ref"
  (let* ([doc (yaml-read-string "name: John\nage: 30\n")]
         [root (yaml-document-root doc)]
         [name-node (yaml-mapping-ref root "name")])
    (and (yaml-scalar? name-node)
         (yaml-scalar-value name-node)))
  => "John")

(test "yaml-ref multi-path"
  (let* ([doc (yaml-read-string "person:\n  name: John\n")]
         [node (yaml-ref doc "person" "name")])
    (and (yaml-scalar? node)
         (yaml-scalar-value node)))
  => "John")

;; ---------------------------------------------------------------------------
;; Roundtrip preservation
;; ---------------------------------------------------------------------------
(display "--- Roundtrip preservation ---") (newline)

(test-roundtrip "simple mapping roundtrip"
  "name: John\nage: 30\n")

(test-roundtrip "simple sequence roundtrip"
  "- one\n- two\n- three\n")

(test-roundtrip "nested mapping roundtrip"
  "person:\n  name: John\n  age: 30\n")

(test-roundtrip "flow mapping roundtrip"
  "{a: 1, b: 2}\n")

(test-roundtrip "flow sequence roundtrip"
  "[1, 2, 3]\n")

(test-roundtrip "quoted strings roundtrip"
  "name: 'John'\npath: \"C:\\\\Users\"\n")

;; ---------------------------------------------------------------------------
;; Comment preservation
;; ---------------------------------------------------------------------------
(display "--- Comment preservation ---") (newline)

(test-roundtrip "mapping with eol comments"
  "name: John  # person name\nage: 30  # years\n")

(test-roundtrip "mapping with comment lines"
  "# Header comment\nname: John\n# Between\nage: 30\n")

(test-roundtrip "sequence with comments"
  "# List header\n- one\n- two\n# Item comment\n- three\n")

;; ---------------------------------------------------------------------------
;; Modification then roundtrip
;; ---------------------------------------------------------------------------
(display "--- Modify + roundtrip ---") (newline)

(test "modify mapping value"
  (let* ([doc (yaml-read-string "name: John\nage: 30\n")]
         [root (yaml-document-root doc)])
    (yaml-mapping-set! root "name" "Jane")
    (yaml-write-string doc))
  => "name: Jane\nage: 30\n")

(test "add mapping key"
  (let* ([doc (yaml-read-string "name: John\n")]
         [root (yaml-document-root doc)])
    (yaml-mapping-set! root "age" (make-yaml-scalar "25" 'plain #f #f '() #f))
    (yaml-write-string doc))
  => "name: John\nage: 25\n")

(test "delete mapping key"
  (let* ([doc (yaml-read-string "name: John\nage: 30\ncity: NYC\n")]
         [root (yaml-document-root doc)])
    (yaml-mapping-delete! root "age")
    (yaml-write-string doc))
  => "name: John\ncity: NYC\n")

(test "append to sequence"
  (let* ([doc (yaml-read-string "- one\n- two\n")]
         [root (yaml-document-root doc)])
    (yaml-sequence-append! root "three")
    (yaml-write-string doc))
  => "- one\n- two\n- three\n")

;; ---------------------------------------------------------------------------
;; Block scalars
;; ---------------------------------------------------------------------------
(display "--- Block scalars ---") (newline)

(test "literal block scalar"
  (let ([doc (yaml-read-string "msg: |\n  hello\n  world\n")])
    (yaml->scheme (yaml-ref doc "msg")))
  => "hello\nworld\n")

(test "folded block scalar"
  (let ([doc (yaml-read-string "msg: >\n  hello\n  world\n")])
    (yaml->scheme (yaml-ref doc "msg")))
  => "hello world\n")

;; ---------------------------------------------------------------------------
;; Anchors and aliases
;; ---------------------------------------------------------------------------
(display "--- Anchors and aliases ---") (newline)

(test "anchor and alias"
  (let ([result (yaml-load-string "default: &def\n  x: 1\noverride: *def\n")])
    (equal? (cdr (assoc "default" result))
            (cdr (assoc "override" result))))
  => #t)

;; ---------------------------------------------------------------------------
;; Edge cases
;; ---------------------------------------------------------------------------
(display "--- Edge cases ---") (newline)

(test "empty document"
  (yaml-load-string "")
  => (void))

(test "comment-only document"
  (yaml-load-string "# just a comment\n")
  => (void))

(test "multiple documents not used here"
  (yaml-load-string "---\nhello\n")
  => "hello")

(test "mapping key with colon in value"
  (yaml-load-string "url: http://example.com\n")
  => '(("url" . "http://example.com")))

(test "yaml->scheme then scheme->yaml roundtrip"
  (let* ([val '(("name" . "John") ("items" . ("a" "b")))]
         [node (scheme->yaml val)]
         [back (yaml->scheme node)])
    back)
  => '(("name" . "John") ("items" . ("a" "b"))))

(test "deeply nested"
  (yaml-load-string "a:\n  b:\n    c:\n      d: deep\n")
  => '(("a" . (("b" . (("c" . (("d" . "deep")))))))))

(test "sequence of sequences"
  (yaml-load-string "-\n  - 1\n  - 2\n-\n  - 3\n  - 4\n")
  => '((1 2) (3 4)))

;; ---------------------------------------------------------------------------
;; Real-world roundtrip: modify config and preserve everything else
;; ---------------------------------------------------------------------------
(display "--- Real-world config edit ---") (newline)

(test "edit config preserving comments and structure"
  (let* ([input (string-append
                 "# Application configuration\n"
                 "app:\n"
                 "  name: myapp  # application name\n"
                 "  version: 1.0.0\n"
                 "  debug: false\n"
                 "\n"
                 "# Database settings\n"
                 "database:\n"
                 "  host: localhost\n"
                 "  port: 5432\n"
                 "  name: mydb\n")]
         [doc (yaml-read-string input)]
         [root (yaml-document-root doc)]
         ;; Change version
         [app (yaml-mapping-ref root "app")])
    (yaml-mapping-set! app "version" "2.0.0")
    (yaml-mapping-set! app "debug" #t)
    (yaml-write-string doc))
  => (string-append
      "# Application configuration\n"
      "app:\n"
      "  name: myapp  # application name\n"
      "  version: 2.0.0\n"
      "  debug: true\n"
      "\n"
      "# Database settings\n"
      "database:\n"
      "  host: localhost\n"
      "  port: 5432\n"
      "  name: mydb\n"))

(test "add new section to config"
  (let* ([input (string-append
                 "name: myapp\n"
                 "port: 8080\n")]
         [doc (yaml-read-string input)]
         [root (yaml-document-root doc)])
    (yaml-mapping-set! root "host" "0.0.0.0")
    (yaml-write-string doc))
  => (string-append
      "name: myapp\n"
      "port: 8080\n"
      "host: 0.0.0.0\n"))

(test "modify nested value via yaml-set!"
  (let* ([input "server:\n  host: localhost\n  port: 8080\n"]
         [doc (yaml-read-string input)])
    (yaml-set! doc "server" "port"
               (make-yaml-scalar "9090" 'plain #f #f '() #f))
    (yaml-write-string doc))
  => "server:\n  host: localhost\n  port: 9090\n")

(test "key ordering preserved"
  (let* ([input "z: 26\na: 1\nm: 13\n"]
         [doc (yaml-read-string input)])
    (yaml-write-string doc))
  => "z: 26\na: 1\nm: 13\n")

(test "mixed flow and block roundtrip"
  (let* ([input "items: [1, 2, 3]\nconfig:\n  key: val\n"]
         [doc (yaml-read-string input)])
    (yaml-write-string doc))
  => "items: [1, 2, 3]\nconfig:\n  key: val\n")

(test "sequence in mapping with comments roundtrip"
  (yaml-load-string "# fruits list\nfruits:\n  - apple\n  - banana\n  # citrus\n  - orange\n")
  => '(("fruits" . ("apple" "banana" "orange"))))

(test "boolean and null preservation in roundtrip"
  (let* ([input "enabled: true\ncount: null\nname: 'true'\n"]
         [doc (yaml-read-string input)])
    (yaml-write-string doc))
  => "enabled: true\ncount: null\nname: 'true'\n")

(test "mapping-keys"
  (let* ([doc (yaml-read-string "a: 1\nb: 2\nc: 3\n")]
         [root (yaml-document-root doc)])
    (yaml-mapping-keys root))
  => '("a" "b" "c"))

(test "mapping-has-key?"
  (let* ([doc (yaml-read-string "name: John\n")]
         [root (yaml-document-root doc)])
    (list (yaml-mapping-has-key? root "name")
          (yaml-mapping-has-key? root "age")))
  => '(#t #f))

(test "sequence-length and sequence-ref"
  (let* ([doc (yaml-read-string "- a\n- b\n- c\n")]
         [root (yaml-document-root doc)])
    (list (yaml-sequence-length root)
          (yaml-scalar-value (yaml-sequence-ref root 1))))
  => '(3 "b"))

;; ---------------------------------------------------------------------------
;; Summary
;; ---------------------------------------------------------------------------
(newline)
(display "=== Results: ")
(display pass-count) (display " passed, ")
(display fail-count) (display " failed, ")
(display test-count) (display " total ===")
(newline)

(when (> fail-count 0)
  (exit 1))
