;; Round 14 — Clojure-style defprotocol
(import (jerboa prelude))
(import (std clojure protocol))

(def test-count 0)
(def pass-count 0)

(defrule (test name body ...)
  (begin
    (set! test-count (+ test-count 1))
    (guard (exn [#t
      (displayln (str "FAIL: " name))
      (displayln (str "  Error: "
                      (if (message-condition? exn)
                          (condition-message exn) exn)))])
      body ...
      (set! pass-count (+ pass-count 1))
      (displayln (str "PASS: " name)))))

(defrule (assert-equal got expected msg)
  (unless (equal? got expected)
    (error 'assert msg (list 'got: got 'expected: expected))))

(defrule (assert-true val msg)
  (unless val (error 'assert msg)))

(defrule (assert-false val msg)
  (when val (error 'assert msg)))

;; -------------------------------------------------------------------------
;; A simple Greetable protocol with two methods.
;; -------------------------------------------------------------------------

(defprotocol Greetable
  (greet [this])
  (farewell [this name]))

(test "newly defined protocol satisfies? is false everywhere"
  (assert-false (satisfies? Greetable "x") "no impl yet")
  (assert-false (satisfies? Greetable 42)  "no impl yet"))

(test "calling unimplemented method raises protocol-not-satisfied"
  (let ([raised #f])
    (guard (e [#t (set! raised #t)])
      (greet "anything"))
    (assert-true raised "raised on missing impl")))

;; -------------------------------------------------------------------------
;; Extend Greetable for strings and numbers.
;; -------------------------------------------------------------------------

(extend-type String? Greetable
  (greet [this] (string-append "Hello, " this))
  (farewell [this name] (string-append "Bye " name " from " this)))

(extend-type Number? Greetable
  (greet [this] (str "Hello, number " this))
  (farewell [this name] (str "Bye " name " from " this)))

(test "extend-type makes satisfies? truthful"
  (assert-true  (satisfies? Greetable "world") "string ok")
  (assert-true  (satisfies? Greetable 42)      "number ok")
  (assert-false (satisfies? Greetable #t)      "boolean still no"))

(test "method dispatches by predicate"
  (assert-equal (greet "world") "Hello, world" "string greet")
  (assert-equal (greet 7) "Hello, number 7" "number greet"))

(test "multi-arg method dispatches on first arg"
  (assert-equal (farewell "Earth" "Alice")
                "Bye Alice from Earth" "string farewell")
  (assert-equal (farewell 42 "Alice")
                "Bye Alice from 42" "number farewell"))

(test "extends? checks predicate registration"
  (assert-true  (extends? Greetable String?)  "extends string?")
  (assert-true  (extends? Greetable Number?)  "extends number?")
  (assert-false (extends? Greetable Boolean?) "no boolean ext"))

;; -------------------------------------------------------------------------
;; Multi-type extend-protocol form
;; -------------------------------------------------------------------------

(defprotocol Sizeable
  (sz [this]))

(extend-protocol Sizeable
  String? (sz [this] (string-length this))
  Vector? (sz [this] (vector-length this))
  List?   (sz [this] (length this))
  Hash?   (sz [this] (hashtable-size this)))

(test "extend-protocol multi-type registers all"
  (assert-true (satisfies? Sizeable "abc") "string")
  (assert-true (satisfies? Sizeable (vector 1 2 3)) "vector")
  (assert-true (satisfies? Sizeable '(a b c d)) "list")
  (let ([h (make-hash-table)])
    (hash-put! h 'k 1)
    (assert-true (satisfies? Sizeable h) "hash")))

(test "extend-protocol dispatches correctly"
  (assert-equal (sz "hello") 5 "string sz")
  (assert-equal (sz (vector 1 2 3)) 3 "vector sz")
  (assert-equal (sz '(a b c d)) 4 "list sz"))

;; -------------------------------------------------------------------------
;; defrecord + extend-type
;; -------------------------------------------------------------------------

(defrecord person (name age))

(extend-type person? Greetable
  (greet [this] (str "Hi, I'm " (person-name this)))
  (farewell [this who] (str who ", from " (person-name this))))

(test "defrecord can be extended manually"
  (let ([p (make-person "Alice" 30)])
    (assert-true (satisfies? Greetable p) "person satisfies")
    (assert-equal (greet p) "Hi, I'm Alice" "person greet")
    (assert-equal (farewell p "Bob") "Bob, from Alice" "person farewell")))

;; -------------------------------------------------------------------------
;; Re-extending a type updates the implementation (idempotent)
;; -------------------------------------------------------------------------

(extend-type Number? Greetable
  (greet [this] (str "Number: " this))
  (farewell [this name] (str "Goodbye " name)))

(test "re-extending replaces previous impl"
  (assert-equal (greet 42) "Number: 42" "new greet wins")
  (assert-equal (farewell 7 "Alice") "Goodbye Alice" "new farewell wins"))

;; -------------------------------------------------------------------------
;; Protocol metadata
;; -------------------------------------------------------------------------

(test "protocol metadata accessors"
  (assert-true (protocol? Greetable) "Greetable is a protocol")
  (assert-equal (protocol-name Greetable) 'Greetable "name")
  (assert-equal (sort (protocol-methods Greetable)
                      (lambda (a b) (string<? (symbol->string a)
                                              (symbol->string b))))
                '(farewell greet) "methods"))

;; -------------------------------------------------------------------------
;; Summary
;; -------------------------------------------------------------------------
(newline)
(displayln (str "========================================="))
(displayln (str "Round 14 results: " pass-count "/" test-count " passed"))
(displayln (str "========================================="))
(when (< pass-count test-count)
  (exit 1))
