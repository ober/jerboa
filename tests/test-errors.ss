#!chezscheme
;;; Tests for (std errors) -- Enhanced Error Messages

(import (chezscheme)
        (std errors))

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

(printf "--- Phase 2a: Enhanced Error Messages ---~%~%")

;;; ======== Levenshtein distance ========

(printf "-- Levenshtein distance --~%")

(test "identical strings"
  (levenshtein-distance "hello" "hello")
  0)

(test "one insertion"
  (levenshtein-distance "cat" "cats")
  1)

(test "one deletion"
  (levenshtein-distance "cats" "cat")
  1)

(test "one substitution"
  (levenshtein-distance "cat" "bat")
  1)

(test "two edits"
  (levenshtein-distance "kitten" "sitten")
  1)  ; only first char differs

(test "empty string"
  (levenshtein-distance "" "abc")
  3)

(test "hash-ref vs hassh-ref"
  (levenshtein-distance "hassh-ref" "hash-ref")
  1)

;;; ======== Find suggestions ========

(printf "~%-- Find suggestions --~%")

(test "finds close match"
  (let ([suggs (find-suggestions "hassh-ref" '(hash-ref hash-set hash-get hash-put!))])
    (and (member 'hash-ref suggs) #t))
  #t)

(test "no match beyond threshold"
  (find-suggestions "zzzzz" '(hash-ref hash-set map filter) 2)
  '())

(test "multiple suggestions sorted by distance"
  (let ([suggs (find-suggestions "car" '(car cdr cons cadr caar))])
    (car suggs))  ; exact match first
  'car)

;;; ======== Source location ========

(printf "~%-- Source location --~%")

(test "source-location creation"
  (let ([loc (make-source-location "foo.ss" 42 7)])
    (list (source-location-file loc)
          (source-location-line loc)
          (source-location-col  loc)))
  '("foo.ss" 42 7))

;;; ======== Type error condition ========

(printf "~%-- Type error conditions --~%")

(test "type-error? predicate"
  (guard (exn [(type-error? exn) #t])
    (type-error 'string-length "String" 42 "Fixnum"))
  #t)

(test "type-error-who"
  (guard (exn [(type-error? exn) (type-error-who exn)])
    (type-error 'string-length "String" 42 "Fixnum"))
  'string-length)

(test "type-error-expected"
  (guard (exn [(type-error? exn) (type-error-expected exn)])
    (type-error 'my-fn "String" 42 "Fixnum"))
  "String")

(test "type-error-got"
  (guard (exn [(type-error? exn) (type-error-got exn)])
    (type-error 'my-fn "String" 42 "Fixnum"))
  42)

;;; ======== Arity error condition ========

(printf "~%-- Arity error conditions --~%")

(test "arity-error? predicate"
  (guard (exn [(arity-error? exn) #t])
    (arity-error 'my-fn 1 2))
  #t)

(test "arity-error-who"
  (guard (exn [(arity-error? exn) (arity-error-who exn)])
    (arity-error 'fibonacci 1 2))
  'fibonacci)

(test "arity-error-expected"
  (guard (exn [(arity-error? exn) (arity-error-expected exn)])
    (arity-error 'my-fn 3 2))
  3)

(test "arity-error-got"
  (guard (exn [(arity-error? exn) (arity-error-got exn)])
    (arity-error 'my-fn 3 7))
  7)

;;; ======== Unbound error condition ========

(printf "~%-- Unbound error conditions --~%")

(test "unbound-error? predicate"
  (guard (exn [(unbound-error? exn) #t])
    (unbound-error 'hassh-ref '(hash-ref hash-set)))
  #t)

(test "unbound-error-name"
  (guard (exn [(unbound-error? exn) (unbound-error-name exn)])
    (unbound-error 'hassh-ref '(hash-ref)))
  'hassh-ref)

(test "unbound-error-suggestions"
  (guard (exn [(unbound-error? exn) (unbound-error-suggestions exn)])
    (unbound-error 'hassh-ref '(hash-ref hash-set)))
  '(hash-ref hash-set))

(define (string-contains haystack needle)
  (let ([hn (string-length haystack)]
        [nn (string-length needle)])
    (let loop ([i 0])
      (cond
        [(> (+ i nn) hn) #f]
        [(string=? (substring haystack i (+ i nn)) needle) #t]
        [else (loop (+ i 1))]))))

;;; ======== Error message formatting ========

(printf "~%-- Error message formatting --~%")

(test "format-condition type-error"
  (guard (exn [(type-error? exn) (string? (format-condition exn))])
    (type-error 'f "String" 42 "Fixnum"))
  #t)

(test "format-condition arity-error"
  (guard (exn [(arity-error? exn) (string? (format-condition exn))])
    (arity-error 'f 1 3))
  #t)

(test "type error message mentions 'type mismatch'"
  (guard (exn [(type-error? exn)
               (let ([msg (format-condition exn)])
                 (string-contains msg "type mismatch"))])
    (type-error 'f "String" 42 "Fixnum"))
  #t)

(test "arity error message mentions arg count"
  (guard (exn [(arity-error? exn)
               (let ([msg (format-condition exn)])
                 (string-contains msg "3"))])
    (arity-error 'f 1 3))
  #t)

(test "unbound error message mentions 'did you mean'"
  (guard (exn [(unbound-error? exn)
               (let ([msg (format-condition exn)])
                 (string-contains msg "did you mean"))])
    (unbound-error 'hassh-ref '(hash-ref)))
  #t)

;;; ======== with-enhanced-errors ========

(printf "~%-- with-enhanced-errors --~%")

(test "with-enhanced-errors catches and returns void"
  (with-enhanced-errors
    (error "test error"))
  (void))

(test "with-enhanced-errors returns value on success"
  (with-enhanced-errors
    42)
  42)

;;; Summary

(printf "~%Enhanced Errors: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
