#!chezscheme
;;; (std misc vector-more) — Extended vector operations
;;;
;;; Vector utilities matching Gerbil patterns.

(library (std misc vector-more)
  (export vector-filter vector-fold
          vector-copy* vector-count
          vector-any vector-every vector-index)

  (import (chezscheme))

  ;; Filter elements by predicate → new vector
  (define (vector-filter pred vec)
    (list->vector
      (filter pred (vector->list vec))))

  ;; Fold over vector elements
  (define (vector-fold proc init vec)
    (let ([len (vector-length vec)])
      (let loop ([i 0] [acc init])
        (if (= i len) acc
            (loop (+ i 1) (proc acc (vector-ref vec i)))))))

  ;; vector-append is a Chez built-in, re-exported via chezscheme import

  ;; Copy with optional start/end (extends R6RS vector-copy)
  (define vector-copy*
    (case-lambda
      [(vec) (vector-copy vec)]
      [(vec start) (vector-copy* vec start (vector-length vec))]
      [(vec start end)
       (let* ([len (- end start)]
              [result (make-vector len)])
         (do ([i 0 (+ i 1)])
             ((= i len) result)
           (vector-set! result i (vector-ref vec (+ start i)))))]))

  ;; Count elements satisfying predicate
  (define (vector-count pred vec)
    (let ([len (vector-length vec)])
      (let loop ([i 0] [n 0])
        (if (= i len) n
            (loop (+ i 1) (if (pred (vector-ref vec i)) (+ n 1) n))))))

  ;; Any element satisfies predicate?
  (define (vector-any pred vec)
    (let ([len (vector-length vec)])
      (let loop ([i 0])
        (and (< i len)
             (or (pred (vector-ref vec i))
                 (loop (+ i 1)))))))

  ;; Every element satisfies predicate?
  (define (vector-every pred vec)
    (let ([len (vector-length vec)])
      (let loop ([i 0])
        (or (= i len)
            (and (pred (vector-ref vec i))
                 (loop (+ i 1)))))))

  ;; Find index of first element satisfying predicate (or #f)
  (define (vector-index pred vec)
    (let ([len (vector-length vec)])
      (let loop ([i 0])
        (cond
          [(= i len) #f]
          [(pred (vector-ref vec i)) i]
          [else (loop (+ i 1))]))))

) ;; end library
