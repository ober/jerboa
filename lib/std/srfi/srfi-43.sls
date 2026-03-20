#!chezscheme
;;; :std/srfi/43 -- Vector Library (SRFI-43 subset)
;;; Chez Scheme provides most vector operations natively.
;;; This module provides the remaining SRFI-43 functions.

(library (std srfi srfi-43)
  (export
    vector-unfold vector-unfold-right
    vector-copy! vector-reverse-copy!
    vector-append
    vector-concatenate
    vector-empty?
    vector-count
    vector-index vector-index-right
    vector-skip vector-skip-right
    vector-any vector-every
    vector-swap!
    vector-reverse!
    vector-fold vector-fold-right
    vector-map! vector-for-each)

  (import (except (chezscheme) vector-copy! vector-append))

  (define (vector-unfold f len . seeds)
    (let ([v (make-vector len)]
          [seed (if (pair? seeds) (car seeds) 0)])
      (let loop ([i 0] [s seed])
        (if (= i len) v
          (call-with-values
            (lambda () (f i s))
            (lambda (val . rest)
              (vector-set! v i val)
              (loop (+ i 1) (if (pair? rest) (car rest) (+ s 1)))))))))

  (define (vector-unfold-right f len . seeds)
    (let ([v (make-vector len)]
          [seed (if (pair? seeds) (car seeds) 0)])
      (let loop ([i (- len 1)] [s seed])
        (if (< i 0) v
          (call-with-values
            (lambda () (f i s))
            (lambda (val . rest)
              (vector-set! v i val)
              (loop (- i 1) (if (pair? rest) (car rest) (+ s 1)))))))))

  (define vector-copy!
    (case-lambda
      [(target tstart source)
       (vector-copy! target tstart source 0 (vector-length source))]
      [(target tstart source sstart)
       (vector-copy! target tstart source sstart (vector-length source))]
      [(target tstart source sstart send)
       (let loop ([i sstart] [j tstart])
         (when (< i send)
           (vector-set! target j (vector-ref source i))
           (loop (+ i 1) (+ j 1))))]))

  (define (vector-reverse-copy! target tstart source . rest)
    (let ([sstart (if (pair? rest) (car rest) 0)]
          [send (if (and (pair? rest) (pair? (cdr rest)))
                  (cadr rest) (vector-length source))])
      (let loop ([i (- send 1)] [j tstart])
        (when (>= i sstart)
          (vector-set! target j (vector-ref source i))
          (loop (- i 1) (+ j 1))))))

  (define (vector-append . vecs)
    (let* ([total (apply + (map vector-length vecs))]
           [result (make-vector total)])
      (let loop ([vecs vecs] [pos 0])
        (if (null? vecs) result
          (let ([v (car vecs)])
            (vector-copy! result pos v)
            (loop (cdr vecs) (+ pos (vector-length v))))))))

  (define (vector-concatenate vecs)
    (apply vector-append vecs))

  (define (vector-empty? v)
    (= (vector-length v) 0))

  (define (vector-count pred v)
    (let ([len (vector-length v)])
      (let loop ([i 0] [c 0])
        (if (= i len) c
          (loop (+ i 1) (if (pred (vector-ref v i)) (+ c 1) c))))))

  (define (vector-index pred v)
    (let ([len (vector-length v)])
      (let loop ([i 0])
        (cond
          [(= i len) #f]
          [(pred (vector-ref v i)) i]
          [else (loop (+ i 1))]))))

  (define (vector-index-right pred v)
    (let loop ([i (- (vector-length v) 1)])
      (cond
        [(< i 0) #f]
        [(pred (vector-ref v i)) i]
        [else (loop (- i 1))])))

  (define (vector-skip pred v)
    (vector-index (lambda (x) (not (pred x))) v))

  (define (vector-skip-right pred v)
    (vector-index-right (lambda (x) (not (pred x))) v))

  (define (vector-any pred v)
    (let ([len (vector-length v)])
      (let loop ([i 0])
        (cond
          [(= i len) #f]
          [(pred (vector-ref v i)) => (lambda (x) x)]
          [else (loop (+ i 1))]))))

  (define (vector-every pred v)
    (let ([len (vector-length v)])
      (let loop ([i 0] [last #t])
        (cond
          [(= i len) last]
          [(pred (vector-ref v i)) => (lambda (x) (loop (+ i 1) x))]
          [else #f]))))

  (define (vector-swap! v i j)
    (let ([tmp (vector-ref v i)])
      (vector-set! v i (vector-ref v j))
      (vector-set! v j tmp)))

  (define (vector-reverse! v)
    (let ([len (vector-length v)])
      (let loop ([i 0] [j (- len 1)])
        (when (< i j)
          (vector-swap! v i j)
          (loop (+ i 1) (- j 1))))))

  (define (vector-fold kons knil v)
    (let ([len (vector-length v)])
      (let loop ([i 0] [acc knil])
        (if (= i len) acc
          (loop (+ i 1) (kons i acc (vector-ref v i)))))))

  (define (vector-fold-right kons knil v)
    (let loop ([i (- (vector-length v) 1)] [acc knil])
      (if (< i 0) acc
        (loop (- i 1) (kons i acc (vector-ref v i))))))

  (define (vector-map! f v)
    (let ([len (vector-length v)])
      (let loop ([i 0])
        (when (< i len)
          (vector-set! v i (f (vector-ref v i)))
          (loop (+ i 1))))))

  ;; Re-export Chez's vector-for-each (already has correct signature)

) ;; end library
