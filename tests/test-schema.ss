#!chezscheme
;;; Tests for (std schema) -- Data schema validation

(import (chezscheme)
        (std schema))

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

(printf "--- Phase 3d: Schema Validation ---~%~%")

;;; ---- Basic type validators ----

(test "s:string valid"
  (schema-valid? s:string "hello")
  #t)

(test "s:string invalid"
  (schema-valid? s:string 42)
  #f)

(test "s:integer valid"
  (schema-valid? s:integer 42)
  #t)

(test "s:integer float invalid"
  (schema-valid? s:integer 3.14)
  #f)

(test "s:number valid int"
  (schema-valid? s:number 42)
  #t)

(test "s:number valid float"
  (schema-valid? s:number 3.14)
  #t)

(test "s:number invalid"
  (schema-valid? s:number "hello")
  #f)

(test "s:boolean true"
  (schema-valid? s:boolean #t)
  #t)

(test "s:boolean false"
  (schema-valid? s:boolean #f)
  #t)

(test "s:boolean invalid"
  (schema-valid? s:boolean 0)
  #f)

(test "s:null valid"
  (schema-valid? s:null #f)
  #t)

(test "s:null invalid"
  (schema-valid? s:null "")
  #f)

(test "s:any always valid"
  (schema-valid? s:any 'anything)
  #t)

;;; ---- schema? ----

(test "schema? true"
  (schema? s:string)
  #t)

(test "schema? false"
  (schema? "not-a-schema")
  #f)

;;; ---- s:list ----

(test "s:list valid"
  (schema-valid? (s:list s:integer) '(1 2 3))
  #t)

(test "s:list invalid element"
  (schema-valid? (s:list s:integer) '(1 "two" 3))
  #f)

(test "s:list empty"
  (schema-valid? (s:list s:string) '())
  #t)

(test "s:list not a list"
  (schema-valid? (s:list s:string) "hello")
  #f)

;;; ---- s:hash ----

(test "s:hash valid"
  (let ([h (make-hashtable equal-hash equal?)]
        [schema (s:hash (list (cons 'name s:string) (cons 'age s:integer)))])
    (hashtable-set! h 'name "Alice")
    (hashtable-set! h 'age 30)
    (schema-valid? schema h))
  #t)

(test "s:hash invalid field"
  (let ([h (make-hashtable equal-hash equal?)]
        [schema (s:hash (list (cons 'name s:string) (cons 'age s:integer)))])
    (hashtable-set! h 'name "Alice")
    (hashtable-set! h 'age "thirty")  ; should be integer
    (schema-valid? schema h))
  #f)

(test "s:hash not hashtable"
  (schema-valid? (s:hash '()) '(1 2 3))
  #f)

;;; ---- s:enum ----

(test "s:enum valid"
  (schema-valid? (s:enum 'red 'green 'blue) 'green)
  #t)

(test "s:enum invalid"
  (schema-valid? (s:enum 'red 'green 'blue) 'yellow)
  #f)

;;; ---- s:union ----

(test "s:union first matches"
  (schema-valid? (s:union s:string s:integer) "hello")
  #t)

(test "s:union second matches"
  (schema-valid? (s:union s:string s:integer) 42)
  #t)

(test "s:union none match"
  (schema-valid? (s:union s:string s:integer) #t)
  #f)

;;; ---- s:optional / s:required ----

(test "s:optional with #f"
  (schema-valid? (s:optional s:string) #f)
  #t)

(test "s:optional with value"
  (schema-valid? (s:optional s:string) "hello")
  #t)

(test "s:required with value"
  (schema-valid? (s:required s:string) "hello")
  #t)

(test "s:required with #f"
  (schema-valid? (s:required s:string) #f)
  #f)

;;; ---- s:min-length / s:max-length ----

(test "s:min-length valid"
  (schema-valid? (s:min-length 3) "hello")
  #t)

(test "s:min-length invalid"
  (schema-valid? (s:min-length 10) "hi")
  #f)

(test "s:max-length valid"
  (schema-valid? (s:max-length 10) "hello")
  #t)

(test "s:max-length invalid"
  (schema-valid? (s:max-length 3) "hello")
  #f)

;;; ---- s:min / s:max ----

(test "s:min valid"
  (schema-valid? (s:min 0) 5)
  #t)

(test "s:min invalid"
  (schema-valid? (s:min 10) 5)
  #f)

(test "s:max valid"
  (schema-valid? (s:max 100) 50)
  #t)

(test "s:max invalid"
  (schema-valid? (s:max 10) 50)
  #f)

;;; ---- s:keys ----

(test "s:keys valid"
  (let ([h (make-hashtable equal-hash equal?)])
    (hashtable-set! h 'name "Alice")
    (hashtable-set! h 'age 30)
    (schema-valid? (s:keys '(name age)) h))
  #t)

(test "s:keys missing key"
  (let ([h (make-hashtable equal-hash equal?)])
    (hashtable-set! h 'name "Alice")
    ; 'age is missing
    (schema-valid? (s:keys '(name age)) h))
  #f)

;;; ---- schema-errors returns details ----

(test "schema-errors not empty on failure"
  (let ([errors (schema-errors s:string 42)])
    (> (length errors) 0))
  #t)

(test "validation-error? true"
  (let ([errors (schema-errors s:string 42)])
    (validation-error? (car errors)))
  #t)

(test "validation-error-message"
  (let* ([errors (schema-errors s:string 42)]
         [e (car errors)])
    (string? (validation-error-message e)))
  #t)

(test "validation-error-value"
  (let* ([errors (schema-errors s:string 42)]
         [e (car errors)])
    (validation-error-value e))
  42)

(printf "~%Schema tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
