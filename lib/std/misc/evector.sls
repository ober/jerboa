#!chezscheme
;;; (std misc evector) -- Expandable Vectors
;;;
;;; Mutable, dynamically-growing vector backed by a fixed vector that
;;; doubles in capacity when full. O(1) amortized push, O(1) ref/set.
;;;
;;; Usage:
;;;   (import (std misc evector))
;;;   (define ev (make-evector))
;;;   (evector-push! ev 10)
;;;   (evector-push! ev 20)
;;;   (evector-push! ev 30)
;;;   (evector-ref ev 1)          ; => 20
;;;   (evector-length ev)         ; => 3
;;;   (evector-pop! ev)           ; => 30
;;;   (evector->list ev)          ; => (10 20)
;;;   (evector->vector ev)        ; => #(10 20)

(library (std misc evector)
  (export
    make-evector
    evector?
    evector-push!
    evector-pop!
    evector-ref
    evector-set!
    evector-length
    evector->vector
    evector->list
    evector-capacity)

  (import (chezscheme))

  (define-record-type evec-rec
    (fields (mutable buf)       ;; backing vector
            (mutable len))      ;; number of elements in use
    (protocol (lambda (new)
      (lambda (cap)
        (new (make-vector cap #f) 0)))))

  (define make-evector
    (case-lambda
      [() (make-evec-rec 16)]
      [(cap)
       (unless (and (fixnum? cap) (> cap 0))
         (error 'make-evector "capacity must be a positive integer" cap))
       (make-evec-rec cap)]))

  (define (evector? x) (evec-rec? x))

  (define (evector-capacity ev)
    (vector-length (evec-rec-buf ev)))

  (define (evector-length ev)
    (evec-rec-len ev))

  ;; Grow the backing vector by doubling capacity
  (define (grow! ev)
    (let* ([old-buf (evec-rec-buf ev)]
           [old-cap (vector-length old-buf)]
           [new-cap (* old-cap 2)]
           [new-buf (make-vector new-cap #f)])
      (let loop ([i 0])
        (when (< i old-cap)
          (vector-set! new-buf i (vector-ref old-buf i))
          (loop (+ i 1))))
      (evec-rec-buf-set! ev new-buf)))

  ;; Push a value onto the end, growing if needed
  (define (evector-push! ev val)
    (let ([len (evec-rec-len ev)]
          [cap (vector-length (evec-rec-buf ev))])
      (when (= len cap)
        (grow! ev))
      (vector-set! (evec-rec-buf ev) len val)
      (evec-rec-len-set! ev (+ len 1))))

  ;; Pop and return the last element
  (define (evector-pop! ev)
    (let ([len (evec-rec-len ev)])
      (when (= len 0)
        (error 'evector-pop! "evector is empty"))
      (let* ([idx (- len 1)]
             [val (vector-ref (evec-rec-buf ev) idx)])
        (vector-set! (evec-rec-buf ev) idx #f)  ;; help GC
        (evec-rec-len-set! ev idx)
        val)))

  ;; Access element at index
  (define (evector-ref ev i)
    (unless (and (fixnum? i) (>= i 0) (< i (evec-rec-len ev)))
      (error 'evector-ref "index out of range" i))
    (vector-ref (evec-rec-buf ev) i))

  ;; Set element at index
  (define (evector-set! ev i val)
    (unless (and (fixnum? i) (>= i 0) (< i (evec-rec-len ev)))
      (error 'evector-set! "index out of range" i))
    (vector-set! (evec-rec-buf ev) i val))

  ;; Return a fresh vector containing only the live elements
  (define (evector->vector ev)
    (let* ([len (evec-rec-len ev)]
           [v (make-vector len)])
      (let loop ([i 0])
        (when (< i len)
          (vector-set! v i (vector-ref (evec-rec-buf ev) i))
          (loop (+ i 1))))
      v))

  ;; Return a list of the live elements in order
  (define (evector->list ev)
    (let ([len (evec-rec-len ev)]
          [buf (evec-rec-buf ev)])
      (let loop ([i (- len 1)] [acc '()])
        (if (< i 0)
          acc
          (loop (- i 1) (cons (vector-ref buf i) acc))))))

) ;; end library
