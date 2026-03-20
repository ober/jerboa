#!chezscheme
;;; (std misc validate) -- Data Validation Combinators
;;;
;;; Composable validators that return structured error messages.
;;; Each validator is (lambda (value) -> (values valid? errors))
;;;
;;; Usage:
;;;   (import (std misc validate))
;;;
;;;   (define check-age
;;;     (v-and (v-required "age")
;;;            (v-integer "age")
;;;            (v-range "age" 0 150)))
;;;
;;;   (check-age 25)    ; => (values #t '())
;;;   (check-age -1)    ; => (values #f '("age: must be between 0 and 150"))
;;;   (check-age #f)    ; => (values #f '("age: is required"))
;;;
;;;   ;; Validate a record/alist
;;;   (define check-user
;;;     (v-record
;;;       (list (cons "name"  (v-and (v-required "name") (v-min-length "name" 1)))
;;;             (cons "email" (v-and (v-required "email") (v-pattern "email" "@"))))))
;;;
;;;   (check-user '((name . "Alice") (email . "alice@example.com")))

(library (std misc validate)
  (export
    ;; Core
    v-ok v-fail
    v-and v-or

    ;; Type validators
    v-required
    v-type
    v-string v-number v-integer v-symbol v-boolean v-list v-pair

    ;; String validators
    v-min-length v-max-length v-exact-length
    v-pattern v-not-empty

    ;; Number validators
    v-range v-min v-max v-positive v-non-negative

    ;; Collection validators
    v-member v-not-member
    v-each

    ;; Record/alist validation
    v-record
    v-field

    ;; Custom
    v-predicate
    validate)

  (import (chezscheme))

  ;; ========== Core ==========
  (define (v-ok) (values #t '()))
  (define (v-fail msg) (values #f (list msg)))

  (define (v-and . validators)
    ;; All must pass; collect all errors
    (lambda (value)
      (let loop ([vs validators] [errors '()])
        (if (null? vs)
          (values (null? errors) (reverse errors))
          (let-values ([(ok? errs) ((car vs) value)])
            (loop (cdr vs) (append (reverse errs) errors)))))))

  (define (v-or . validators)
    ;; At least one must pass
    (lambda (value)
      (let loop ([vs validators] [all-errors '()])
        (if (null? vs)
          (values #f (reverse all-errors))
          (let-values ([(ok? errs) ((car vs) value)])
            (if ok?
              (values #t '())
              (loop (cdr vs) (append (reverse errs) all-errors))))))))

  ;; ========== Required ==========
  (define (v-required field)
    (lambda (value)
      (if (or (not value)
              (and (string? value) (= (string-length value) 0)))
        (values #f (list (string-append field ": is required")))
        (values #t '()))))

  ;; ========== Type Validators ==========
  (define (v-type field type-name pred)
    (lambda (value)
      (if (pred value)
        (values #t '())
        (values #f (list (string-append field ": must be a " type-name))))))

  (define (v-string field) (v-type field "string" string?))
  (define (v-number field) (v-type field "number" number?))
  (define (v-integer field) (v-type field "integer" (lambda (v) (and (integer? v) (exact? v)))))
  (define (v-symbol field) (v-type field "symbol" symbol?))
  (define (v-boolean field) (v-type field "boolean" boolean?))
  (define (v-list field) (v-type field "list" list?))
  (define (v-pair field) (v-type field "pair" pair?))

  ;; ========== String Validators ==========
  (define (v-min-length field n)
    (lambda (value)
      (if (and (string? value) (>= (string-length value) n))
        (values #t '())
        (values #f (list (format "~a: must be at least ~a characters" field n))))))

  (define (v-max-length field n)
    (lambda (value)
      (if (and (string? value) (<= (string-length value) n))
        (values #t '())
        (values #f (list (format "~a: must be at most ~a characters" field n))))))

  (define (v-exact-length field n)
    (lambda (value)
      (if (and (string? value) (= (string-length value) n))
        (values #t '())
        (values #f (list (format "~a: must be exactly ~a characters" field n))))))

  (define (v-pattern field pattern-str)
    (lambda (value)
      (if (and (string? value)
               (string-contains? value pattern-str))
        (values #t '())
        (values #f (list (format "~a: must match pattern '~a'" field pattern-str))))))

  (define (v-not-empty field)
    (lambda (value)
      (cond
        [(and (string? value) (> (string-length value) 0)) (values #t '())]
        [(and (list? value) (pair? value)) (values #t '())]
        [else (values #f (list (string-append field ": must not be empty")))])))

  ;; ========== Number Validators ==========
  (define (v-range field lo hi)
    (lambda (value)
      (if (and (number? value) (>= value lo) (<= value hi))
        (values #t '())
        (values #f (list (format "~a: must be between ~a and ~a" field lo hi))))))

  (define (v-min field lo)
    (lambda (value)
      (if (and (number? value) (>= value lo))
        (values #t '())
        (values #f (list (format "~a: must be at least ~a" field lo))))))

  (define (v-max field hi)
    (lambda (value)
      (if (and (number? value) (<= value hi))
        (values #t '())
        (values #f (list (format "~a: must be at most ~a" field hi))))))

  (define (v-positive field)
    (lambda (value)
      (if (and (number? value) (> value 0))
        (values #t '())
        (values #f (list (string-append field ": must be positive"))))))

  (define (v-non-negative field)
    (lambda (value)
      (if (and (number? value) (>= value 0))
        (values #t '())
        (values #f (list (string-append field ": must be non-negative"))))))

  ;; ========== Collection Validators ==========
  (define (v-member field allowed)
    (lambda (value)
      (if (member value allowed)
        (values #t '())
        (values #f (list (format "~a: must be one of ~a" field allowed))))))

  (define (v-not-member field disallowed)
    (lambda (value)
      (if (not (member value disallowed))
        (values #t '())
        (values #f (list (format "~a: must not be ~a" field value))))))

  (define (v-each field item-validator)
    ;; Validate each element of a list
    (lambda (value)
      (if (not (list? value))
        (values #f (list (string-append field ": must be a list")))
        (let loop ([items value] [i 0] [errors '()])
          (if (null? items)
            (values (null? errors) (reverse errors))
            (let-values ([(ok? errs) (item-validator (car items))])
              (loop (cdr items) (+ i 1)
                    (append (reverse
                              (map (lambda (e)
                                     (format "~a[~a]: ~a" field i e))
                                   errs))
                            errors))))))))

  ;; ========== Record/Alist Validation ==========
  (define (v-field field-name validator)
    ;; Extract field from alist and validate
    (lambda (record)
      (let ([pair (assoc field-name record)])
        (if pair
          (validator (cdr pair))
          (validator #f)))))

  (define (v-record field-specs)
    ;; field-specs: list of (field-name . validator)
    ;; Validates an alist record
    (lambda (record)
      (let loop ([specs field-specs] [errors '()])
        (if (null? specs)
          (values (null? errors) (reverse errors))
          (let* ([field-name (caar specs)]
                 [validator (cdar specs)]
                 [pair (assoc field-name record)])
            (let-values ([(ok? errs) (validator (if pair (cdr pair) #f))])
              (loop (cdr specs) (append (reverse errs) errors))))))))

  ;; ========== Custom ==========
  (define (v-predicate field pred msg)
    (lambda (value)
      (if (pred value)
        (values #t '())
        (values #f (list (format "~a: ~a" field msg))))))

  ;; ========== Convenience ==========
  (define (validate validator value)
    ;; Returns (values ok? errors) - same as calling validator directly
    (validator value))

  ;; ========== Helpers ==========
  (define (string-contains? haystack needle)
    (let ([hn (string-length haystack)]
          [nn (string-length needle)])
      (let loop ([i 0])
        (cond
          [(> (+ i nn) hn) #f]
          [(string=? (substring haystack i (+ i nn)) needle) #t]
          [else (loop (+ i 1))]))))

) ;; end library
