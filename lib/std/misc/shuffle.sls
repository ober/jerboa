#!chezscheme
;;; :std/misc/shuffle -- List and vector shuffling

(library (std misc shuffle)
  (export shuffle shuffle!)

  (import (chezscheme))

  (define (shuffle! v)
    ;; Fisher-Yates in-place shuffle of a vector
    (let ((n (vector-length v)))
      (let loop ((i (- n 1)))
        (when (> i 0)
          (let* ((j (random (+ i 1)))
                 (tmp (vector-ref v i)))
            (vector-set! v i (vector-ref v j))
            (vector-set! v j tmp)
            (loop (- i 1)))))
      v))

  (define (shuffle lst)
    ;; Shuffle a list, returning a new list
    (let* ((v (list->vector lst)))
      (shuffle! v)
      (vector->list v)))

) ;; end library
