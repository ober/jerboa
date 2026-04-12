#!chezscheme
;;; (std clojure reducers) — Parallel reducers (clojure.core.reducers)
;;;
;;; Provides fork/join style parallel fold over collections.
;;; Splits collections at midpoints, farms halves to threads,
;;; and combines results.
;;;
;;; Usage:
;;;   (import (std clojure reducers))
;;;   (r-fold + 0 (persistent-vector 1 2 3 4 5))  ;; => 15 (parallelized)
;;;
;;; Key functions:
;;;   r-fold     — parallel fold with combinef + reducef
;;;   r-map      — lazy reducing transform
;;;   r-filter   — lazy reducing filter
;;;   r-mapcat   — lazy reducing mapcat
;;;   r-flatten  — lazy reducing flatten
;;;   r-take     — reducing take
;;;   r-drop     — reducing drop
;;;   r-foldcat  — fold into a concatenated result

(library (std clojure reducers)
  (export
    r-fold r-map r-filter r-remove
    r-take r-drop r-take-while
    r-mapcat r-flatten
    r-foldcat
    r-reduce)

  (import (except (chezscheme)
                  make-hash-table hash-table? iota 1+ 1-
                  partition)
          (std pvec))

  ;; ================================================================
  ;; Configuration
  ;; ================================================================

  ;; Minimum chunk size before parallelism kicks in.
  ;; Below this threshold, we just reduce sequentially.
  (define *fold-chunk-size* 512)

  ;; ================================================================
  ;; Thread infrastructure: spawn-worker / join-worker
  ;;
  ;; Chez's fork-thread does not return a joinable handle, so we
  ;; build one from a mutex + condition variable.
  ;; ================================================================

  (define-record-type join-handle
    (fields (mutable value)
            (mutable done?)
            mutex
            condvar)
    (protocol (lambda (new)
                (lambda ()
                  (new (void) #f (make-mutex) (make-condition))))))

  (define (spawn-worker thunk)
    (let ([handle (make-join-handle)])
      (fork-thread
        (lambda ()
          (let ([v (thunk)])
            (with-mutex (join-handle-mutex handle)
              (join-handle-value-set! handle v)
              (join-handle-done?-set! handle #t)
              (condition-signal (join-handle-condvar handle))))))
      handle))

  (define (join-worker handle)
    (with-mutex (join-handle-mutex handle)
      (let lp ()
        (if (join-handle-done? handle)
            (join-handle-value handle)
            (begin
              (condition-wait (join-handle-condvar handle)
                              (join-handle-mutex handle))
              (lp))))))

  ;; ================================================================
  ;; Core: r-fold — parallel fold
  ;;
  ;; (r-fold f init coll)            — simple: f is both combiner & reducer
  ;; (r-fold combinef reducef coll)  — Clojure-style: (combinef) → seed
  ;; (r-fold combinef reducef init coll) — explicit seed
  ;;
  ;; combinef: () → identity, (a b) → combine two results
  ;; reducef:  (acc x) → accumulate one element
  ;;
  ;; For simple cases: (r-fold + 0 coll) uses + as both combine and reduce.
  ;; ================================================================

  (define r-fold
    (case-lambda
      [(f-or-combinef reducef-or-init coll)
       ;; Disambiguate: if second arg is a procedure, it's (combinef reducef coll).
       ;; Otherwise it's (f init coll) — the simple form.
       (if (procedure? reducef-or-init)
           ;; Clojure-style: (combinef reducef coll), seed = (combinef)
           (r-fold f-or-combinef reducef-or-init (f-or-combinef) coll)
           ;; Simple: (f init coll), f is both combiner and reducer
           (r-fold f-or-combinef f-or-combinef reducef-or-init coll))]
      [(combinef reducef init coll)
       (cond
         [(persistent-vector? coll)
          (pvec-fold combinef reducef init coll)]
         [(pair? coll)
          (list-fold combinef reducef init coll)]
         [(vector? coll)
          (vector-fold combinef reducef init coll)]
         [else
          ;; Fallback: sequential
          (sequential-fold reducef init coll)])]))

  ;; ---- Parallel fold over persistent vectors ----
  ;; Split at midpoint, recurse, combine.
  (define (pvec-fold combinef reducef init v)
    (let ([n (persistent-vector-length v)])
      (if (<= n *fold-chunk-size*)
          ;; Sequential
          (pvec-reduce reducef init v 0 n)
          ;; Parallel: split at midpoint
          (let* ([mid (quotient n 2)]
                 [handle (spawn-worker
                           (lambda ()
                             (pvec-fold combinef reducef init
                               (persistent-vector-slice v 0 mid))))]
                 [right (pvec-fold combinef reducef init
                          (persistent-vector-slice v mid n))])
            (combinef (join-worker handle) right)))))

  ;; Sequential reduce over a pvec range
  (define (pvec-reduce f init v start end)
    (let lp ([i start] [acc init])
      (if (= i end) acc
          (lp (+ i 1) (f acc (persistent-vector-ref v i))))))

  ;; ---- Parallel fold over lists ----
  ;; Split list in half using length.
  (define (list-fold combinef reducef init lst)
    (let ([n (length lst)])
      (if (<= n *fold-chunk-size*)
          (fold-left reducef init lst)
          (let-values ([(left right) (split-list lst (quotient n 2))])
            (let* ([handle (spawn-worker
                             (lambda ()
                               (list-fold combinef reducef init left)))]
                   [right-val (list-fold combinef reducef init right)])
              (combinef (join-worker handle) right-val))))))

  ;; ---- Parallel fold over Chez vectors ----
  (define (vector-fold combinef reducef init vec)
    (let ([n (vector-length vec)])
      (if (<= n *fold-chunk-size*)
          (let lp ([i 0] [acc init])
            (if (= i n) acc
                (lp (+ i 1) (reducef acc (vector-ref vec i)))))
          (let* ([mid (quotient n 2)]
                 [handle (spawn-worker
                           (lambda ()
                             (let lp ([i 0] [acc init])
                               (if (= i mid) acc
                                   (lp (+ i 1) (reducef acc (vector-ref vec i)))))))]
                 [right-val
                   (let lp ([i mid] [acc init])
                     (if (= i n) acc
                         (lp (+ i 1) (reducef acc (vector-ref vec i)))))])
            (combinef (join-worker handle) right-val)))))

  ;; Sequential fallback
  (define (sequential-fold f init coll)
    (cond
      [(null? coll) init]
      [(pair? coll) (fold-left f init coll)]
      [else (error 'r-fold "unsupported collection" coll)]))

  ;; ---- Helper: split a list ----
  (define (split-list lst n)
    (let lp ([rest lst] [left '()] [count n])
      (if (or (zero? count) (null? rest))
          (values (reverse left) rest)
          (lp (cdr rest) (cons (car rest) left) (- count 1)))))

  ;; ================================================================
  ;; Reducing Transforms (lazy, composable)
  ;; For simplicity, these eagerly transform then return the result.
  ;; The returned collections are still foldable by r-fold.
  ;; ================================================================

  (define (r-map f coll)
    (cond
      [(pair? coll) (map f coll)]
      [(persistent-vector? coll)
       (let ([n (persistent-vector-length coll)])
         (let lp ([i 0] [acc '()])
           (if (= i n) (reverse acc)
               (lp (+ i 1) (cons (f (persistent-vector-ref coll i)) acc)))))]
      [(vector? coll)
       (let ([n (vector-length coll)])
         (let lp ([i 0] [acc '()])
           (if (= i n) (reverse acc)
               (lp (+ i 1) (cons (f (vector-ref coll i)) acc)))))]
      [else (error 'r-map "unsupported collection" coll)]))

  (define (r-filter pred coll)
    (cond
      [(pair? coll) (filter pred coll)]
      [(persistent-vector? coll)
       (let ([n (persistent-vector-length coll)])
         (let lp ([i 0] [acc '()])
           (if (= i n) (reverse acc)
               (let ([x (persistent-vector-ref coll i)])
                 (lp (+ i 1) (if (pred x) (cons x acc) acc))))))]
      [(vector? coll)
       (let ([n (vector-length coll)])
         (let lp ([i 0] [acc '()])
           (if (= i n) (reverse acc)
               (let ([x (vector-ref coll i)])
                 (lp (+ i 1) (if (pred x) (cons x acc) acc))))))]
      [else (error 'r-filter "unsupported collection" coll)]))

  (define (r-remove pred coll)
    (r-filter (lambda (x) (not (pred x))) coll))

  (define (r-take n coll)
    (cond
      [(pair? coll)
       (let lp ([lst coll] [n n] [acc '()])
         (if (or (zero? n) (null? lst)) (reverse acc)
             (lp (cdr lst) (- n 1) (cons (car lst) acc))))]
      [else (r-take n (to-list coll))]))

  (define (r-drop n coll)
    (cond
      [(pair? coll)
       (let lp ([lst coll] [n n])
         (if (or (zero? n) (null? lst)) lst
             (lp (cdr lst) (- n 1))))]
      [else (r-drop n (to-list coll))]))

  (define (r-take-while pred coll)
    (let lp ([lst (to-list coll)] [acc '()])
      (if (or (null? lst) (not (pred (car lst))))
          (reverse acc)
          (lp (cdr lst) (cons (car lst) acc)))))

  (define (r-mapcat f coll)
    (apply append (r-map f coll)))

  (define (r-flatten coll)
    (let lp ([lst (to-list coll)] [acc '()])
      (if (null? lst) (reverse acc)
          (let ([x (car lst)])
            (if (pair? x)
                (lp (cdr lst) (append (reverse (lp x '())) acc))
                (lp (cdr lst) (cons x acc)))))))

  ;; r-foldcat — fold into a concatenated list
  (define (r-foldcat coll)
    (r-fold append (lambda (acc x) (append acc (list x))) '() coll))

  ;; r-reduce — sequential reduce (non-parallel, for compatibility)
  (define r-reduce
    (case-lambda
      [(f coll)
       (let ([lst (to-list coll)])
         (if (null? lst) (f)
             (fold-left f (car lst) (cdr lst))))]
      [(f init coll)
       (fold-left f init (to-list coll))]))

  ;; ---- to-list helper ----
  (define (to-list coll)
    (cond
      [(pair? coll) coll]
      [(null? coll) '()]
      [(persistent-vector? coll) (persistent-vector->list coll)]
      [(vector? coll) (vector->list coll)]
      [else (error 'to-list "unsupported collection" coll)]))

) ;; end library
