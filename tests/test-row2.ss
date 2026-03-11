#!chezscheme
;;; Tests for (std typed row2) — Enhanced row polymorphism

(import (chezscheme) (std typed row2))

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

(define-syntax test-error
  (syntax-rules ()
    [(_ name expr)
     (guard (exn [#t (set! pass (+ pass 1)) (printf "  ok ~a~%" name)])
       expr
       (set! fail (+ fail 1))
       (printf "FAIL ~a: expected error but got none~%" name))]))

(printf "--- (std typed row2) tests ---~%~%")

;; ===== Open Record Construction =====

(printf "-- open-record construction --~%")

(test "make-open-record dotted pair"
  (let ([r (make-open-record '((name . "Alice") (age . 30)))])
    (open-record? r))
  #t)

(test "make-open-record two-element list"
  (let ([r (make-open-record '((name "Bob") (age 25)))])
    (open-record? r))
  #t)

(test "make-open-record empty"
  (let ([r (make-open-record '())])
    (open-record? r))
  #t)

(test "open-record? false for non-record"
  (open-record? '((name . "Alice")))
  #f)

(test "open-record? false for vector"
  (open-record? (vector 1 2 3))
  #f)

;; ===== Field Access =====

(printf "~%-- field access --~%")

(define r1 (make-open-record '((name . "Alice") (age . 30) (active . #t))))

(test "open-record-get string field"
  (open-record-get r1 'name)
  "Alice")

(test "open-record-get number field"
  (open-record-get r1 'age)
  30)

(test "open-record-get boolean field"
  (open-record-get r1 'active)
  #t)

(test "open-record-get missing field returns #f"
  (open-record-get r1 'email)
  #f)

(test "open-record-has? existing field"
  (open-record-has? r1 'name)
  #t)

(test "open-record-has? missing field"
  (open-record-has? r1 'phone)
  #f)

(test "open-record-fields"
  (open-record-fields r1)
  '(name age active))

(test "open-record-alist"
  (open-record-alist r1)
  '((name . "Alice") (age . 30) (active . #t)))

;; ===== Record Operations =====

(printf "~%-- record operations --~%")

(test "open-record-set new field"
  (let ([r2 (open-record-set r1 'email "alice@example.com")])
    (open-record-get r2 'email))
  "alice@example.com")

(test "open-record-set does not mutate original"
  (begin
    (open-record-set r1 'email "test@test.com")
    (open-record-has? r1 'email))
  #f)

(test "open-record-set replaces existing field"
  (let ([r2 (open-record-set r1 'age 31)])
    (open-record-get r2 'age))
  31)

(test "record-extend adds field"
  (let ([r2 (record-extend r1 'city "NYC")])
    (open-record-get r2 'city))
  "NYC")

(test "record-restrict removes field"
  (let ([r2 (record-restrict r1 'age)])
    (open-record-has? r2 'age))
  #f)

(test "record-restrict preserves other fields"
  (let ([r2 (record-restrict r1 'age)])
    (open-record-get r2 'name))
  "Alice")

(test "record-merge right wins on conflict"
  (let* ([ra (make-open-record '((x . 1) (y . 2)))]
         [rb (make-open-record '((y . 99) (z . 3)))]
         [rm (record-merge ra rb)])
    (open-record-get rm 'y))
  99)

(test "record-merge keeps left-only fields"
  (let* ([ra (make-open-record '((x . 1) (y . 2)))]
         [rb (make-open-record '((z . 3)))]
         [rm (record-merge ra rb)])
    (open-record-get rm 'x))
  1)

(test "record-merge all fields present"
  (let* ([ra (make-open-record '((x . 1)))]
         [rb (make-open-record '((y . 2)))]
         [rm (record-merge ra rb)])
    (list (open-record-get rm 'x) (open-record-get rm 'y)))
  '(1 2))

;; ===== Row Types =====

(printf "~%-- row types --~%")

(test "make-row-type creates row-type"
  (row-type? (make-row-type '((name . string) (age . fixnum))))
  #t)

(test "row-type? false for non-row"
  (row-type? '((name . string)))
  #f)

(test "row-type-fields"
  (row-type-fields (make-row-type '((name . string) (age . fixnum))))
  '((name . string) (age . fixnum)))

(test "row-type-rest #f for closed row"
  (row-type-rest (make-row-type '((name . string))))
  #f)

(test "row-type-rest symbol for open row"
  (row-type-rest (make-row-type '((name . string)) 'r))
  'r)

;; Row macro
(test "Row macro creates row-type"
  (row-type? (Row name: string age: fixnum))
  #t)

(test "Row macro fields"
  (row-type-fields (Row name: string age: fixnum))
  '((name . string) (age . fixnum)))

(test "Row macro with rest variable"
  (row-type-rest (Row name: string rest: r))
  'r)

(test "Row macro empty"
  (row-type? (Row))
  #t)

;; check-row-type!
(test "check-row-type! passes when all fields present"
  (let ([r (make-open-record '((name . "Alice") (age . 30)))]
        [rt (make-row-type '((name . string) (age . fixnum)))])
    (check-row-type! 'test r rt)
    'ok)
  'ok)

(test-error "check-row-type! raises on missing field"
  (let ([r (make-open-record '((name . "Alice")))]
        [rt (make-row-type '((name . string) (age . fixnum)))])
    (check-row-type! 'test r rt)))

;; ===== Row Combinators =====

(printf "~%-- row combinators --~%")

(define num-rec (make-open-record '((x . 10) (y . 20) (z . 30))))
(define str-rec (make-open-record '((a . "foo") (b . "bar"))))

(test "row-map applies function to values"
  (let ([r2 (row-map (lambda (v) (* v 2)) num-rec)])
    (list (open-record-get r2 'x)
          (open-record-get r2 'y)
          (open-record-get r2 'z)))
  '(20 40 60))

(test "row-map string-upcase"
  (let ([r2 (row-map string-upcase str-rec)])
    (open-record-get r2 'a))
  "FOO")

(test "row-filter keeps matching fields"
  (let* ([r (make-open-record '((x . 10) (name . "hi") (y . 20)))]
         [r2 (row-filter (lambda (k v) (number? v)) r)])
    (open-record-fields r2))
  '(x y))

(test "row-filter by field name"
  (let* ([r (make-open-record '((keep . 1) (drop . 2) (keep2 . 3)))]
         [r2 (row-filter (lambda (k v) (not (eq? k 'drop))) r)])
    (open-record-fields r2))
  '(keep keep2))

(test "row-fold sums numbers"
  (row-fold (lambda (acc k v) (+ acc v)) 0 num-rec)
  60)

(test "row-fold builds list of keys"
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b)))
             (row-fold (lambda (acc k v) (cons k acc)) '() num-rec))
  '(x y z))

(test "row-keys returns field names"
  (row-keys num-rec)
  '(x y z))

(test "row-values returns field values"
  (row-values num-rec)
  '(10 20 30))

;; define/row
(printf "~%-- define/row --~%")

(define/row (get-name [rec : (Row name: string)])
  (open-record-get rec 'name))

(test "define/row basic usage"
  (let ([person (make-open-record '((name . "Charlie") (age . 40)))])
    (get-name person))
  "Charlie")

(define/row (add-fields rec extra)
  (record-merge rec extra))

(test "define/row without type annotation"
  (let ([r (add-fields (make-open-record '((a . 1)))
                       (make-open-record '((b . 2))))])
    (list (open-record-get r 'a) (open-record-get r 'b)))
  '(1 2))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
