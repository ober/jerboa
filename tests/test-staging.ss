#!chezscheme
;;; Tests for (std staging) — Metaprogramming and Staging

(import (chezscheme) (std staging))

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

(printf "--- (std staging) tests ---~%")

;;; ======== Step 25: at-compile-time ========

(printf "~%-- at-compile-time --~%")

;; Simple compile-time arithmetic
(define ct-sum (at-compile-time (+ 1 2 3 4 5)))
(test "at-compile-time: arithmetic"
  ct-sum
  15)

;; Compile-time string manipulation
(define ct-greeting (at-compile-time (string-append "Hello" ", " "World")))
(test "at-compile-time: string-append"
  ct-greeting
  "Hello, World")

;; Compile-time list
(define ct-list (at-compile-time (list 1 2 3)))
(test "at-compile-time: list"
  ct-list
  '(1 2 3))

;; Compile-time pi approximation
(define ct-pi (at-compile-time (acos -1.0)))
(test "at-compile-time: acos"
  (< 3.14 ct-pi 3.15)
  #t)

;;; ======== Step 25: define/ct ========

(printf "~%-- define/ct --~%")

(define/ct max-count 100)
(test "define/ct: constant"
  max-count
  100)

(define/ct port-range (list 80 443 8080))
(test "define/ct: list"
  port-range
  '(80 443 8080))

;;; ======== Step 26: format-id ========

(printf "~%-- format-id --~%")

;; format-id creates a new identifier
(define-syntax make-getter
  (lambda (stx)
    (syntax-case stx ()
      [(_ name)
       (let ([getter (format-id #'name "get-~a" #'name)])
         #`(define (#,getter x) x))])))

(make-getter value)
(test "format-id: generated getter"
  (get-value 42)
  42)

;; format-id with string arg
(define-syntax make-counter
  (lambda (stx)
    (syntax-case stx ()
      [(_ base)
       (let ([counter-name (format-id #'base "~a-count" "total")])
         #`(define #,counter-name 0))])))

(make-counter foo)
(test "format-id: string arg"
  total-count
  0)

;;; ======== Step 26: struct-fields + derive-serializer ========

(printf "~%-- define-staging-type / derive-serializer --~%")

;; Register a simple struct
(define-record-type (vec2 make-vec2 vec2?)
  (fields (immutable x vec2-x)
          (immutable y vec2-y)))

(define-staging-type vec2 vec2? (x y) (vec2-x vec2-y))

(test "struct-fields: returns field names"
  (struct-fields 'vec2)
  '(x y))

(test "struct-fields: unknown returns empty"
  (struct-fields 'nosuchthing)
  '())

;; derive-serializer (fields/accessors given explicitly)
(derive-serializer vec2 (x y) (vec2-x vec2-y))

(test "derive-serializer: serializes to pairs"
  (let ([out (open-output-string)])
    (serialize-vec2 (make-vec2 3 4) out)
    (get-output-string out))
  "(x . 3)(y . 4)")

;;; ======== Step 26: derive-printer ========

(printf "~%-- derive-printer --~%")

(define-record-type (color make-color color?)
  (fields (immutable r color-r)
          (immutable g color-g)
          (immutable b color-b)))

(define-staging-type color color? (r g b) (color-r color-g color-b))

(derive-printer color (r g b) (color-r color-g color-b))

(test "derive-printer: formats as #<name field=val ...>"
  (print-color (make-color 255 0 128))
  "#<color r=255 g=0 b=128>")

;;; ======== Step 26: with-gensyms ========

(printf "~%-- with-gensyms --~%")

(define-syntax swap!
  (lambda (stx)
    (syntax-case stx ()
      [(_ a b)
       (with-gensyms (tmp)
         #`(let ([#,tmp a])
             (set! a b)
             (set! b #,tmp)))])))

(test "with-gensyms: swap"
  (let ([x 1] [y 2])
    (swap! x y)
    (list x y))
  '(2 1))

;;; ======== Step 26: quasigen ========

(printf "~%-- quasigen --~%")

;; quasigen creates a code-generating lambda
(define gen-add
  (quasigen ctx
    #`(define (#,(format-id ctx "add-~a" ctx) a b) (+ a b))))

;; Apply the generator with a context identifier
(define-syntax make-adder
  (lambda (stx)
    (syntax-case stx ()
      [(_ name)
       (gen-add #'name)])))

(make-adder nums)
(test "quasigen: generated adder"
  (add-nums 3 4)
  7)

;;; ======== Step 27: defrule/guard ========

(printf "~%-- defrule/guard --~%")

;; defrule/guard without guard (same as defrule)
(defrule/guard (my-and a b)
  (if a b #f))

(test "defrule/guard: no guard"
  (my-and #t 42)
  42)

(test "defrule/guard: no guard false"
  (my-and #f 42)
  #f)

;;; ======== Step 27: syntax-walk ========

(printf "~%-- syntax-walk --~%")

;; syntax-walk processes a tree
(test "syntax-walk: identity (no replacements)"
  (let ([walked (syntax-walk #'(+ 1 2) (lambda (stx) #f))])
    (syntax->datum walked))
  '(+ 1 2))

(test "syntax-walk: returns #f on leaf without match"
  (let ([walked (syntax-walk #'42 (lambda (stx) #f))])
    (syntax->datum walked))
  42)

;;; ======== Integration: compile-time table ========

(printf "~%-- integration: compile-time lookup table --~%")

;; Build a lookup table at compile time using at-compile-time
(define/ct factorial-10 (let loop ([i 1] [acc 1])
                           (if (> i 10) acc (loop (+ i 1) (* acc i)))))

(test "compile-time factorial"
  factorial-10
  3628800)

;; Macro that generates definitions via format-id + quasigen
(define-syntax define-pair-ops
  (lambda (stx)
    (syntax-case stx ()
      [(_ name a b)
       (let ([fst-id (datum->syntax #'name
                       (string->symbol (string-append (symbol->string (syntax->datum #'name)) "-fst")))]
             [snd-id (datum->syntax #'name
                       (string->symbol (string-append (symbol->string (syntax->datum #'name)) "-snd")))])
         #`(begin
             (define (#,fst-id) a)
             (define (#,snd-id) b)))])))

(define-pair-ops coords 10 20)


(test "macro code gen: pair ops"
  (list (coords-fst) (coords-snd))
  '(10 20))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
