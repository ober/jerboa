#!chezscheme
;;; Tests for (std text json-schema) — JSON Schema Validation

(import (chezscheme) (std text json-schema))

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
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(define-syntax test-pred
  (syntax-rules ()
    [(_ name expr pred)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (pred got)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: value ~s failed predicate~%" name got)))))]))

(printf "--- (std text json-schema) tests ---~%")

;; ========== Schema Types ==========

(test "schema-type-string/value"   schema-type-string  'string)
(test "schema-type-number/value"   schema-type-number  'number)
(test "schema-type-boolean/value"  schema-type-boolean 'boolean)
(test "schema-type-null/value"     schema-type-null    'null)
(test "schema-type-array/value"    schema-type-array   'array)
(test "schema-type-object/value"   schema-type-object  'object)

;; ========== make-schema / json-schema? ==========

(test "json-schema?/true for schema"
  (json-schema? (make-schema '#:type 'string))
  #t)

(test "json-schema?/false for plain value"
  (json-schema? "hello")
  #f)

(test "json-schema?/false for hashtable without marker"
  (json-schema? (make-hashtable equal-hash equal?))
  #f)

;; ========== validation-result? ==========

(test-pred "validation-result?/validate returns result"
  (validate-json "hello" (make-schema '#:type 'string))
  validation-result?)

;; ========== Type validation ==========

(test "validate-json/string-valid"
  (validation-valid? (validate-json "hello" (make-schema '#:type 'string)))
  #t)

(test "validate-json/string-invalid"
  (validation-valid? (validate-json 42 (make-schema '#:type 'string)))
  #f)

(test "validate-json/number-valid"
  (validation-valid? (validate-json 3.14 (make-schema '#:type 'number)))
  #t)

(test "validate-json/number-invalid"
  (validation-valid? (validate-json "not-a-number" (make-schema '#:type 'number)))
  #f)

(test "validate-json/boolean-valid"
  (validation-valid? (validate-json #t (make-schema '#:type 'boolean)))
  #t)

(test "validate-json/boolean-false-valid"
  (validation-valid? (validate-json #f (make-schema '#:type 'boolean)))
  #t)

(test "validate-json/null-valid"
  (validation-valid? (validate-json (void) (make-schema '#:type 'null)))
  #t)

(test "validate-json/array-valid"
  (validation-valid? (validate-json '(1 2 3) (make-schema '#:type 'array)))
  #t)

(test "validate-json/object-valid"
  (validation-valid? (validate-json (make-hashtable equal-hash equal?) (make-schema '#:type 'object)))
  #t)

;; ========== String constraints ==========

(test "validate-json/min-length-pass"
  (validation-valid? (validate-json "hello" (make-schema '#:min-length 3)))
  #t)

(test "validate-json/min-length-fail"
  (validation-valid? (validate-json "hi" (make-schema '#:min-length 5)))
  #f)

(test "validate-json/max-length-pass"
  (validation-valid? (validate-json "hi" (make-schema '#:max-length 5)))
  #t)

(test "validate-json/max-length-fail"
  (validation-valid? (validate-json "toolong" (make-schema '#:max-length 4)))
  #f)

(test "validate-json/pattern-pass"
  (validation-valid? (validate-json "hello123" (make-schema '#:pattern "^[a-z0-9]+$")))
  #t)

(test "validate-json/pattern-fail"
  (validation-valid? (validate-json "Hello!" (make-schema '#:pattern "^[a-z0-9]+$")))
  #f)

;; ========== Numeric constraints ==========

(test "validate-json/minimum-pass"
  (validation-valid? (validate-json 10 (make-schema '#:minimum 5)))
  #t)

(test "validate-json/minimum-fail"
  (validation-valid? (validate-json 3 (make-schema '#:minimum 5)))
  #f)

(test "validate-json/maximum-pass"
  (validation-valid? (validate-json 4 (make-schema '#:maximum 10)))
  #t)

(test "validate-json/maximum-fail"
  (validation-valid? (validate-json 15 (make-schema '#:maximum 10)))
  #f)

;; ========== Enum constraint ==========

(test "validate-json/enum-pass"
  (validation-valid? (validate-json "red" (make-schema '#:enum '("red" "green" "blue"))))
  #t)

(test "validate-json/enum-fail"
  (validation-valid? (validate-json "purple" (make-schema '#:enum '("red" "green" "blue"))))
  #f)

;; ========== Array items ==========

(test "validate-json/items-all-valid"
  (validation-valid?
    (validate-json '(1 2 3)
      (make-schema '#:type 'array '#:items (make-schema '#:type 'number))))
  #t)

(test "validate-json/items-some-invalid"
  (validation-valid?
    (validate-json '(1 "two" 3)
      (make-schema '#:type 'array '#:items (make-schema '#:type 'number))))
  #f)

;; ========== Object properties and required ==========

(test "validate-json/required-present"
  (let ([ht (make-hashtable equal-hash equal?)])
    (hashtable-set! ht "name" "Alice")
    (validation-valid?
      (validate-json ht (make-schema '#:required '("name")))))
  #t)

(test "validate-json/required-missing"
  (let ([ht (make-hashtable equal-hash equal?)])
    (validation-valid?
      (validate-json ht (make-schema '#:required '("name")))))
  #f)

(test "validate-json/properties-valid"
  (let ([ht (make-hashtable equal-hash equal?)]
        [props (make-hashtable equal-hash equal?)])
    (hashtable-set! ht "age" 25)
    (hashtable-set! props "age" (make-schema '#:type 'number '#:minimum 0))
    (validation-valid?
      (validate-json ht (make-schema '#:properties props))))
  #t)

(test "validate-json/properties-invalid"
  (let ([ht (make-hashtable equal-hash equal?)]
        [props (make-hashtable equal-hash equal?)])
    (hashtable-set! ht "age" -5)
    (hashtable-set! props "age" (make-schema '#:type 'number '#:minimum 0))
    (validation-valid?
      (validate-json ht (make-schema '#:properties props))))
  #f)

;; ========== Errors ==========

(test-pred "validation-errors/non-empty on failure"
  (validation-errors (validate-json 99 (make-schema '#:type 'string)))
  (lambda (e) (and (list? e) (> (length e) 0))))

(test "validation-errors/empty on success"
  (validation-errors (validate-json "ok" (make-schema '#:type 'string)))
  '())

;; ========== schema-valid? shorthand ==========

(test "schema-valid?/true"
  (schema-valid? 42 (make-schema '#:type 'number))
  #t)

(test "schema-valid?/false"
  (schema-valid? "no" (make-schema '#:type 'number))
  #f)

;; ========== define-json-schema macro ==========

(define-json-schema name-schema
  '#:type 'string
  '#:min-length 1
  '#:max-length 100)

(test "define-json-schema/creates schema"
  (json-schema? name-schema)
  #t)

(test "define-json-schema/validates correctly"
  (schema-valid? "Alice" name-schema)
  #t)

(test "define-json-schema/rejects empty"
  (schema-valid? "" name-schema)
  #f)

(test "define-json-schema/rejects wrong type"
  (schema-valid? 42 name-schema)
  #f)

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
