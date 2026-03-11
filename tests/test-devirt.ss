#!chezscheme
;;; Tests for (std dev devirt) -- Whole-Program Devirtualization

(import (except (chezscheme) 1+ 1- iota make-hash-table hash-table?)
        (jerboa prelude)
        (std dev devirt))

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

(printf "--- Phase 2b: Whole-Program Devirtualization ---~%~%")

;;; ======== Setup: define some types using Jerboa defstruct ========
;;; defstruct creates name::t (RTD), make-name, name?, name-field accessors

(defstruct circle (radius))
(defstruct rect (width height))

;;; ======== register-method-impl! ========

(define (circle-area-fn self) (* 3.14159 (circle-radius self) (circle-radius self)))
(define (rect-area-fn self) (* (rect-width self) (rect-height self)))

(register-method-impl! 'area circle::t circle? circle-area-fn)
(register-method-impl! 'area rect::t rect? rect-area-fn)

(test "register-method-impl! records implementations"
  (= (length (method-implementations 'area)) 2)
  #t)

;;; ======== method-implementations ========

(test "method-implementations returns list"
  (list? (method-implementations 'area))
  #t)

(test "method-implementations unknown method"
  (method-implementations 'no-such-method-xyz)
  '())

;;; ======== method-closed? / seal-method! ========

(test "method-closed? before seal"
  (method-closed? 'area)
  #f)

(seal-method! 'area)

(test "method-closed? after seal"
  (method-closed? 'area)
  #t)

;;; ======== all-sealed-methods ========

(test "all-sealed-methods includes area"
  (and (list? (all-sealed-methods))
       (not (not (memq 'area (all-sealed-methods)))))
  #t)

;;; ======== define-devirt-dispatch ========

(define-devirt-dispatch my-area 'area)

(test "define-devirt-dispatch creates procedure"
  (procedure? my-area)
  #t)

(test "define-devirt-dispatch circle"
  (let ([c (make-circle 2.0)])
    (< (abs (- (my-area c) (* 3.14159 4.0))) 0.001))
  #t)

(test "define-devirt-dispatch rect"
  (let ([r (make-rect 5 6)])
    (= (my-area r) 30))
  #t)

;;; ======== devirt-call ========

(test "devirt-call on circle"
  (let ([c (make-circle 1.0)])
    (< (abs (- (devirt-call 'area c) 3.14159)) 0.001))
  #t)

(test "devirt-call on rect"
  (let ([r (make-rect 2 3)])
    (= (devirt-call 'area r) 6))
  #t)

;;; ======== *method-registry* ========

(test "*method-registry* is a hashtable"
  (hashtable? *method-registry*)
  #t)

;;; ======== defmethod/tracked ========

;; defmethod/tracked uses type-name::t and type-name? automatically
(defmethod/tracked perimeter circle
  (lambda (self) (* 2 3.14159 (circle-radius self))))
(defmethod/tracked perimeter rect
  (lambda (self) (* 2 (+ (rect-width self) (rect-height self)))))

(test "defmethod/tracked registers implementations"
  (= (length (method-implementations 'perimeter)) 2)
  #t)

(define-devirt-dispatch perim-dispatch 'perimeter)

(test "defmethod/tracked circle perimeter"
  (let ([c (make-circle 1.0)])
    (< (abs (- (perim-dispatch c) (* 2 3.14159))) 0.001))
  #t)

(test "defmethod/tracked rect perimeter"
  (let ([r (make-rect 3 4)])
    (= (perim-dispatch r) 14))
  #t)

;;; ======== Summary ========

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
