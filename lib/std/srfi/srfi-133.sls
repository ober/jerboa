#!chezscheme
;;; :std/srfi/133 -- Vector Library (SRFI-133)
;;; Extended vector operations beyond R6RS.

(library (std srfi srfi-133)
  (export
    vector-unfold vector-unfold-right
    vector-copy vector-reverse-copy
    vector-append vector-concatenate
    vector-map vector-for-each
    vector-fold vector-fold-right
    vector-count vector-index vector-index-right
    vector-skip vector-skip-right
    vector-any vector-every
    vector-swap! vector-reverse!
    vector-cumulate)

  (import (except (chezscheme)
            vector-copy vector-map vector-for-each vector-append))

  ;; vector-unfold: build vector from seed
  ;; (vector-unfold f length seed) where f: index seed -> value new-seed
  (define (vector-unfold f len . seeds)
    (let ([v (make-vector len)]
          [seed (if (pair? seeds) (car seeds) #f)])
      (let loop ([i 0] [s seed])
        (if (= i len)
          v
          (call-with-values
            (lambda () (f i s))
            (lambda (val . rest)
              (vector-set! v i val)
              (loop (+ i 1) (if (pair? rest) (car rest) s))))))))

  ;; vector-unfold-right: same but fills right to left
  (define (vector-unfold-right f len . seeds)
    (let ([v (make-vector len)]
          [seed (if (pair? seeds) (car seeds) #f)])
      (let loop ([i (- len 1)] [s seed])
        (if (< i 0)
          v
          (call-with-values
            (lambda () (f i s))
            (lambda (val . rest)
              (vector-set! v i val)
              (loop (- i 1) (if (pair? rest) (car rest) s))))))))

  ;; vector-copy with optional start/end
  (define (vector-copy vec . args)
    (let ([start (if (pair? args) (car args) 0)]
          [end (if (and (pair? args) (pair? (cdr args)))
                   (cadr args) (vector-length vec))])
      (let* ([len (- end start)]
             [result (make-vector len)])
        (do ([i 0 (+ i 1)])
            ((= i len) result)
          (vector-set! result i (vector-ref vec (+ start i)))))))

  ;; vector-reverse-copy
  (define (vector-reverse-copy vec . args)
    (let ([start (if (pair? args) (car args) 0)]
          [end (if (and (pair? args) (pair? (cdr args)))
                   (cadr args) (vector-length vec))])
      (let* ([len (- end start)]
             [result (make-vector len)])
        (do ([i 0 (+ i 1)])
            ((= i len) result)
          (vector-set! result i (vector-ref vec (+ start (- len 1 i))))))))

  ;; vector-append
  (define (vector-append . vecs)
    (vector-concatenate vecs))

  ;; vector-concatenate
  (define (vector-concatenate vecs)
    (let* ([total (fold-left + 0 (map vector-length vecs))]
           [result (make-vector total)])
      (let loop ([vecs vecs] [pos 0])
        (if (null? vecs)
          result
          (let ([v (car vecs)]
                [n (vector-length (car vecs))])
            (do ([i 0 (+ i 1)])
                ((= i n))
              (vector-set! result (+ pos i) (vector-ref v i)))
            (loop (cdr vecs) (+ pos n)))))))

  ;; vector-map: SRFI-133 version takes vec as second arg
  (define (vector-map f vec . rest)
    (if (null? rest)
      (let* ([len (vector-length vec)]
             [result (make-vector len)])
        (do ([i 0 (+ i 1)])
            ((= i len) result)
          (vector-set! result i (f (vector-ref vec i)))))
      (let* ([vecs (cons vec rest)]
             [len (apply min (map vector-length vecs))]
             [result (make-vector len)])
        (do ([i 0 (+ i 1)])
            ((= i len) result)
          (vector-set! result i
            (apply f (map (lambda (v) (vector-ref v i)) vecs)))))))

  ;; vector-for-each
  (define (vector-for-each f vec . rest)
    (if (null? rest)
      (let ([len (vector-length vec)])
        (do ([i 0 (+ i 1)])
            ((= i len))
          (f (vector-ref vec i))))
      (let* ([vecs (cons vec rest)]
             [len (apply min (map vector-length vecs))])
        (do ([i 0 (+ i 1)])
            ((= i len))
          (apply f (map (lambda (v) (vector-ref v i)) vecs))))))

  ;; vector-fold: left fold over vector
  (define (vector-fold f seed vec . rest)
    (if (null? rest)
      (let ([len (vector-length vec)])
        (let loop ([i 0] [acc seed])
          (if (= i len)
            acc
            (loop (+ i 1) (f acc (vector-ref vec i))))))
      (let* ([vecs (cons vec rest)]
             [len (apply min (map vector-length vecs))])
        (let loop ([i 0] [acc seed])
          (if (= i len)
            acc
            (loop (+ i 1)
              (apply f acc (map (lambda (v) (vector-ref v i)) vecs))))))))

  ;; vector-fold-right
  (define (vector-fold-right f seed vec . rest)
    (if (null? rest)
      (let ([len (vector-length vec)])
        (let loop ([i (- len 1)] [acc seed])
          (if (< i 0)
            acc
            (loop (- i 1) (f acc (vector-ref vec i))))))
      (let* ([vecs (cons vec rest)]
             [len (apply min (map vector-length vecs))])
        (let loop ([i (- len 1)] [acc seed])
          (if (< i 0)
            acc
            (loop (- i 1)
              (apply f acc (map (lambda (v) (vector-ref v i)) vecs))))))))

  ;; vector-count: count elements satisfying pred
  (define (vector-count pred vec . rest)
    (if (null? rest)
      (let ([len (vector-length vec)])
        (let loop ([i 0] [count 0])
          (if (= i len)
            count
            (loop (+ i 1)
              (if (pred (vector-ref vec i)) (+ count 1) count)))))
      (let* ([vecs (cons vec rest)]
             [len (apply min (map vector-length vecs))])
        (let loop ([i 0] [count 0])
          (if (= i len)
            count
            (loop (+ i 1)
              (if (apply pred (map (lambda (v) (vector-ref v i)) vecs))
                (+ count 1) count)))))))

  ;; vector-index: index of first element matching pred
  (define (vector-index pred vec . rest)
    (if (null? rest)
      (let ([len (vector-length vec)])
        (let loop ([i 0])
          (cond
            [(= i len) #f]
            [(pred (vector-ref vec i)) i]
            [else (loop (+ i 1))])))
      (let* ([vecs (cons vec rest)]
             [len (apply min (map vector-length vecs))])
        (let loop ([i 0])
          (cond
            [(= i len) #f]
            [(apply pred (map (lambda (v) (vector-ref v i)) vecs)) i]
            [else (loop (+ i 1))])))))

  ;; vector-index-right
  (define (vector-index-right pred vec . rest)
    (if (null? rest)
      (let loop ([i (- (vector-length vec) 1)])
        (cond
          [(< i 0) #f]
          [(pred (vector-ref vec i)) i]
          [else (loop (- i 1))]))
      (let* ([vecs (cons vec rest)]
             [len (apply min (map vector-length vecs))])
        (let loop ([i (- len 1)])
          (cond
            [(< i 0) #f]
            [(apply pred (map (lambda (v) (vector-ref v i)) vecs)) i]
            [else (loop (- i 1))])))))

  ;; vector-skip: index of first element NOT matching pred
  (define (vector-skip pred vec . rest)
    (apply vector-index (lambda args (not (apply pred args))) vec rest))

  ;; vector-skip-right
  (define (vector-skip-right pred vec . rest)
    (apply vector-index-right (lambda args (not (apply pred args))) vec rest))

  ;; vector-any: return first true value from pred
  (define (vector-any pred vec . rest)
    (if (null? rest)
      (let ([len (vector-length vec)])
        (let loop ([i 0])
          (cond
            [(= i len) #f]
            [(pred (vector-ref vec i)) => values]
            [else (loop (+ i 1))])))
      (let* ([vecs (cons vec rest)]
             [len (apply min (map vector-length vecs))])
        (let loop ([i 0])
          (cond
            [(= i len) #f]
            [(apply pred (map (lambda (v) (vector-ref v i)) vecs)) => values]
            [else (loop (+ i 1))])))))

  ;; vector-every: return last true value or #f
  (define (vector-every pred vec . rest)
    (if (null? rest)
      (let ([len (vector-length vec)])
        (if (= len 0)
          #t
          (let loop ([i 0])
            (let ([result (pred (vector-ref vec i))])
              (cond
                [(not result) #f]
                [(= i (- len 1)) result]
                [else (loop (+ i 1))])))))
      (let* ([vecs (cons vec rest)]
             [len (apply min (map vector-length vecs))])
        (if (= len 0)
          #t
          (let loop ([i 0])
            (let ([result (apply pred (map (lambda (v) (vector-ref v i)) vecs))])
              (cond
                [(not result) #f]
                [(= i (- len 1)) result]
                [else (loop (+ i 1))])))))))

  ;; vector-swap!
  (define (vector-swap! vec i j)
    (let ([tmp (vector-ref vec i)])
      (vector-set! vec i (vector-ref vec j))
      (vector-set! vec j tmp)))

  ;; vector-reverse!
  (define (vector-reverse! vec . args)
    (let ([start (if (pair? args) (car args) 0)]
          [end (if (and (pair? args) (pair? (cdr args)))
                   (cadr args) (vector-length vec))])
      (let loop ([i start] [j (- end 1)])
        (when (< i j)
          (vector-swap! vec i j)
          (loop (+ i 1) (- j 1))))))

  ;; vector-cumulate: cumulative fold
  ;; (vector-cumulate f seed vec) returns a vector where element i is
  ;; (f ... (f (f seed v0) v1) ... vi)
  (define (vector-cumulate f seed vec)
    (let* ([len (vector-length vec)]
           [result (make-vector len)])
      (let loop ([i 0] [acc seed])
        (if (= i len)
          result
          (let ([new-acc (f acc (vector-ref vec i))])
            (vector-set! result i new-acc)
            (loop (+ i 1) new-acc))))))

) ;; end library
