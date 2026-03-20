#!chezscheme
;;; (std misc list-builder) — Efficient list accumulation macro
;;;
;;; Provides with-list-builder, which eliminates the reverse-accumulator
;;; pattern that litters imperative Scheme code.
;;;
;;; Usage:
;;;   (with-list-builder (push!)
;;;     (for-each (lambda (x)
;;;                 (when (> x 3) (push! x)))
;;;               '(1 5 2 7 3 8)))
;;;   ; => (5 7 8)
;;;
;;; The push! function appends to the end in O(1) using a tail pointer,
;;; so the result is in insertion order without needing reverse.

(library (std misc list-builder)
  (export with-list-builder)

  (import (chezscheme))

  ;; with-list-builder: bind a push! function that builds a list in order.
  ;; Uses a sentinel head node + tail pointer for O(1) append.
  (define-syntax with-list-builder
    (syntax-rules ()
      [(_ (push!))
       '()]
      [(_ (push!) body body* ...)
       (let* ([head (list 'sentinel)]
              [tail head])
         (define (push! val)
           (let ([new-pair (list val)])
             (set-cdr! tail new-pair)
             (set! tail new-pair)))
         body body* ...
         (cdr head))]
      ;; Two-arg form: (with-list-builder (push! peek) body ...)
      ;; peek returns the list built so far
      [(_ (push! peek) body body* ...)
       (let* ([head (list 'sentinel)]
              [tail head])
         (define (push! val)
           (let ([new-pair (list val)])
             (set-cdr! tail new-pair)
             (set! tail new-pair)))
         (define (peek) (cdr head))
         body body* ...
         (cdr head))]))

) ;; end library
