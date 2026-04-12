(import (jerboa prelude))
(import (std text edn))

(def test-count 0)
(def pass-count 0)

(defrule (test name body ...)
  (begin
    (set! test-count (+ test-count 1))
    (guard (exn [#t
      (displayln (str "FAIL: " name))
      (displayln (str "  Error: " (if (message-condition? exn)
                                    (condition-message exn) exn)))])
      body ...
      (set! pass-count (+ pass-count 1))
      (displayln (str "PASS: " name)))))

(defrule (assert-equal got expected msg)
  (unless (equal? got expected)
    (error 'assert msg (list 'got: got 'expected: expected))))

(defrule (assert-true val msg)
  (unless val (error 'assert msg)))

;; =========================================================================
;; Reader tests
;; =========================================================================

(test "read integer"
  (assert-equal (string->edn "42") 42 "integer"))

(test "read negative integer"
  (assert-equal (string->edn "-7") -7 "negative"))

(test "read float"
  (assert-equal (string->edn "3.14") 3.14 "float"))

(test "read string"
  (assert-equal (string->edn "\"hello world\"") "hello world" "string"))

(test "read string with escapes"
  (assert-equal (string->edn "\"line\\nbreak\"") "line\nbreak" "escapes"))

(test "read true"
  (assert-equal (string->edn "true") #t "true"))

(test "read false"
  (assert-equal (string->edn "false") #f "false"))

(test "read nil"
  (assert-equal (string->edn "nil") 'nil "nil"))

(test "read symbol"
  (assert-equal (string->edn "foo") 'foo "symbol"))

(test "read keyword"
  (assert-equal (string->edn ":name") (string->symbol "#:name") "keyword"))

(test "read list"
  (assert-equal (string->edn "(1 2 3)") '(1 2 3) "list"))

(test "read nested list"
  (assert-equal (string->edn "(1 (2 3) 4)") '(1 (2 3) 4) "nested list"))

(test "read vector"
  (assert-equal (string->edn "[1 2 3]") (vector 1 2 3) "vector"))

(test "read map"
  (let ([m (string->edn "{:a 1, :b 2}")])
    (assert-true (hashtable? m) "is hashtable")
    (assert-equal (hashtable-ref m (string->symbol "#:a") #f) 1 "key :a")
    (assert-equal (hashtable-ref m (string->symbol "#:b") #f) 2 "key :b")))

(test "read set"
  (let ([s (string->edn "#{1 2 3}")])
    (assert-true (edn-set? s) "is edn-set")
    (assert-equal (length (edn-set-elements s)) 3 "3 elements")))

(test "read char literal"
  (assert-equal (string->edn "\\a") #\a "char a"))

(test "read named char"
  (assert-equal (string->edn "\\newline") #\newline "newline char"))

(test "read with comments"
  (assert-equal (string->edn ";; comment\n42") 42 "skip line comment"))

(test "read with discard"
  (assert-equal (string->edn "#_ foo 42") 42 "discard form"))

(test "read commas as whitespace"
  (assert-equal (string->edn "[1, 2, 3]") (vector 1 2 3) "commas ignored"))

(test "read tagged literal"
  (let ([v (string->edn "#myapp/person {:name \"Alice\"}")])
    (assert-true (tagged-value? v) "is tagged")
    (assert-equal (tagged-value-tag v) 'myapp/person "tag name")))

(test "read tagged with custom handler"
  (parameterize ([edn-tag-readers
                  (list (cons 'double (lambda (n) (* n 2))))])
    (assert-equal (string->edn "#double 21") 42 "custom tag handler")))

;; =========================================================================
;; Writer tests
;; =========================================================================

(test "write integer"
  (assert-equal (edn->string 42) "42" "integer"))

(test "write float"
  (assert-equal (edn->string 3.14) "3.14" "float"))

(test "write string"
  (assert-equal (edn->string "hello") "\"hello\"" "string"))

(test "write string with escapes"
  (assert-equal (edn->string "a\nb") "\"a\\nb\"" "escapes"))

(test "write boolean"
  (assert-equal (edn->string #t) "true" "true")
  (assert-equal (edn->string #f) "false" "false"))

(test "write nil"
  (assert-equal (edn->string 'nil) "nil" "nil"))

(test "write symbol"
  (assert-equal (edn->string 'foo) "foo" "symbol"))

(test "write list"
  (assert-equal (edn->string '(1 2 3)) "(1 2 3)" "list"))

(test "write vector"
  (assert-equal (edn->string (vector 1 2 3)) "[1 2 3]" "vector"))

(test "write set"
  (assert-equal (edn->string (make-edn-set '(1 2 3))) "#{1 2 3}" "set"))

(test "write tagged value"
  (assert-equal (edn->string (make-tagged-value 'inst "2026-01-01"))
    "#inst \"2026-01-01\"" "tagged"))

(test "write char"
  (assert-equal (edn->string #\a) "\\a" "char a")
  (assert-equal (edn->string #\newline) "\\newline" "newline"))

;; =========================================================================
;; Round-trip tests
;; =========================================================================

(test "round-trip integer"
  (assert-equal (string->edn (edn->string 42)) 42 "integer round-trip"))

(test "round-trip string"
  (assert-equal (string->edn (edn->string "hello \"world\""))
    "hello \"world\"" "string round-trip"))

(test "round-trip list"
  (assert-equal (string->edn (edn->string '(1 2 3))) '(1 2 3) "list round-trip"))

(test "round-trip vector"
  (assert-equal (string->edn (edn->string (vector 1 2 3)))
    (vector 1 2 3) "vector round-trip"))

(test "round-trip nested"
  (let ([data '(1 "two" (3 4))])
    (assert-equal (string->edn (edn->string data)) data "nested round-trip")))

;; =========================================================================
;; Summary
;; =========================================================================
(newline)
(displayln (str "========================================="))
(displayln (str "Results: " pass-count "/" test-count " passed"))
(displayln (str "========================================="))
(when (< pass-count test-count)
  (exit 1))
