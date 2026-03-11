#!chezscheme
;;; Tests for (std derive) -- Derive System

(import (chezscheme)
        (jerboa core)
        (jerboa runtime)
        (std derive))

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

(printf "--- Phase 2a: Derive System ---~%~%")

;;; ======== Basic struct-info ========

(test "struct-info creation"
  (let ([info (make-struct-info 'point '(x y) #f #f #f '() '())])
    (struct-info-name info))
  'point)

;;; ======== Equal derivation ========

(printf "-- Equal derivation --~%")

;; Create a simple struct manually and test equal derivation
(define pt-rtd (make-record-type-descriptor 'point #f #f #f #f
                  '#((mutable x) (mutable y))))
(define pt-make
  (record-constructor (make-record-constructor-descriptor pt-rtd #f #f)))
(define pt? (record-predicate pt-rtd))
(define pt-x (record-accessor pt-rtd 0))
(define pt-y (record-accessor pt-rtd 1))
(define pt-x-set! (record-mutator pt-rtd 0))
(define pt-y-set! (record-mutator pt-rtd 1))

(define pt-info
  (make-struct-info 'point '(x y) pt-rtd pt-make pt?
    (list pt-x pt-y) (list pt-x-set! pt-y-set!)))

;; Apply equal derivation
(derive! pt-info '(equal hash print copy))

(test "equal derivation creates point=?"
  (let ([p1 (pt-make 3 4)]
        [p2 (pt-make 3 4)]
        [p3 (pt-make 1 2)])
    (list (point=? p1 p2)
          (point=? p1 p3)))
  '(#t #f))

(test "hash derivation creates point-hash"
  (let ([p1 (pt-make 3 4)]
        [p2 (pt-make 3 4)])
    ;; Same values → same hash
    (= (point-hash p1) (point-hash p2)))
  #t)

(test "print derivation creates point-print"
  (let ([p (pt-make 3 4)])
    (with-output-to-string (lambda () (point-print p))))
  "#<point x: 3 y: 4>")

(test "copy derivation creates point-copy"
  (let* ([p1 (pt-make 10 20)]
         [p2 (point-copy p1)])
    (and (pt? p2)
         (= (pt-x p2) 10)
         (= (pt-y p2) 20)
         (not (eq? p1 p2))))  ; different objects
  #t)

;;; ======== JSON derivation ========

(printf "~%-- JSON derivation --~%")

(derive! pt-info '(json))

(test "json->point creates record from alist"
  (let* ([p  (pt-make 5 6)]
         [j  (point->json p)]
         [p2 (json->point j)])
    (list (pt-x p2) (pt-y p2)))
  '(5 6))

(test "point->json returns alist"
  (let* ([p   (pt-make 3 4)]
         [j   (point->json p)]
         [x-p (assoc "x" j)]
         [y-p (assoc "y" j)])
    (list (cdr x-p) (cdr y-p)))
  '(3 4))

;;; ======== Comparable derivation ========

(printf "~%-- Comparable derivation --~%")

(define num-rtd (make-record-type-descriptor 'num-pair #f #f #f #f
                   '#((mutable a) (mutable b))))
(define num-make
  (record-constructor (make-record-constructor-descriptor num-rtd #f #f)))
(define num? (record-predicate num-rtd))
(define num-a (record-accessor num-rtd 0))
(define num-b (record-accessor num-rtd 1))
(define num-a-set! (record-mutator num-rtd 0))
(define num-b-set! (record-mutator num-rtd 1))

(define num-info
  (make-struct-info 'num-pair '(a b) num-rtd num-make num?
    (list num-a num-b) (list num-a-set! num-b-set!)))

(derive! num-info '(comparable))

(test "comparable: equal returns 0"
  (num-pair-compare (num-make 1 2) (num-make 1 2))
  0)

(test "comparable: less returns -1"
  (num-pair-compare (num-make 1 2) (num-make 2 2))
  -1)

(test "comparable: greater returns 1"
  (num-pair-compare (num-make 5 2) (num-make 3 2))
  1)

;;; ======== Serializable derivation ========

(printf "~%-- Serializable derivation --~%")

(derive! pt-info '(serializable))

(test "serialize/deserialize round-trip"
  (let* ([p  (pt-make 42 99)]
         [bv (point->bytes p)]
         [p2 (bytes->point bv)])
    (list (pt-x p2) (pt-y p2)))
  '(42 99))

;;; ======== Custom derivation ========

(printf "~%-- Custom derivation --~%")

(register-derivation! 'my-sum
  (lambda (info)
    (let* ([name     (struct-info-name info)]
           [accs     (struct-info-accessors info)]
           [sum-name (string->symbol (string-append (symbol->string name) "-sum"))])
      (list
        (cons sum-name
          (lambda (x) (apply + (map (lambda (acc) (acc x)) accs))))))))

(derive! pt-info '(my-sum))

(test "custom sum derivation"
  (point-sum (pt-make 10 20))
  30)

;;; ======== Struct-info accessors ========

(test "struct-info-fields"
  (struct-info-fields pt-info)
  '(x y))

(test "struct-info-name"
  (struct-info-name pt-info)
  'point)

;;; Summary

(printf "~%Derive System: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
