#!chezscheme
;;; Tests for (std pipeline) -- Data pipeline DSL

(import (chezscheme)
        (std pipeline))

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

(printf "--- Phase 3d: Data Pipeline ---~%~%")

;;; ---- Stage ----

(test "make-stage"
  (stage? (make-stage "double" (lambda (x) (* 2 x))))
  #t)

(test "stage-name"
  (stage-name (make-stage "my-stage" (lambda (x) x)))
  "my-stage")

(test "stage-fn"
  (let ([s (make-stage "inc" (lambda (x) (+ x 1)))])
    ((stage-fn s) 5))
  6)

(test "stage-result initially #f"
  (stage-result (make-stage "foo" (lambda (x) x)))
  #f)

;;; ---- Pipeline ----

(test "make-pipeline"
  (pipeline? (make-pipeline))
  #t)

(test "pipeline-run single stage"
  (let* ([p (make-pipeline)]
         [s (make-stage "double" (lambda (x) (* 2 x)))])
    (pipeline-add-stage! p s)
    (pipeline-run p 5))
  10)

(test "pipeline-run multiple stages"
  (let* ([p (make-pipeline)]
         [s1 (make-stage "double" (lambda (x) (* 2 x)))]
         [s2 (make-stage "add1" (lambda (x) (+ x 1)))]
         [s3 (make-stage "square" (lambda (x) (* x x)))])
    (pipeline-add-stage! p s1)
    (pipeline-add-stage! p s2)
    (pipeline-add-stage! p s3)
    (pipeline-run p 3))
  49)

(test "pipeline-result after run"
  (let* ([p (make-pipeline)]
         [s (make-stage "id" (lambda (x) x))])
    (pipeline-add-stage! p s)
    (pipeline-run p 42)
    (pipeline-result p))
  42)

(test "pipeline-stats"
  (let* ([p (make-pipeline)]
         [s (make-stage "test" (lambda (x) x))])
    (pipeline-add-stage! p s)
    (pipeline-run p 1)
    (let ([stats (pipeline-stats p)])
      (and (list? stats) (= (length stats) 1)
           (equal? (car (car stats)) "test"))))
  #t)

;;; ---- stage result after run ----

(test "stage-result after pipeline-run"
  (let* ([p (make-pipeline)]
         [s (make-stage "double" (lambda (x) (* 2 x)))])
    (pipeline-add-stage! p s)
    (pipeline-run p 7)
    (stage-result s))
  14)

;;; ---- |> threading macro (|> uses hex escape for the symbol name) ----

(test "|> single"
  (\x7C;\x3E; 5 (+ 1))
  6)

(test "|> multiple"
  (\x7C;\x3E; 3 (* 2) (+ 1) (* 10))
  70)

(test "|> with lambda"
  (\x7C;\x3E; '(1 2 3 4 5)
    ((lambda (lst) (filter even? lst)))
    ((lambda (lst) (map (lambda (x) (* x x)) lst))))
  '(4 16))

;;; ---- pipe ----

(test "pipe single"
  ((pipe (lambda (x) (* 2 x))) 5)
  10)

(test "pipe multiple"
  ((pipe (lambda (x) (* 2 x))
         (lambda (x) (+ x 1))
         (lambda (x) (* x x))) 3)
  49)

(test "pipe identity"
  ((pipe) 42)
  42)

;;; ---- pipeline-map ----

(test "pipeline-map"
  (let ([s (pipeline-map (lambda (x) (* 2 x)))])
    ((stage-fn s) '(1 2 3)))
  '(2 4 6))

;;; ---- pipeline-filter ----

(test "pipeline-filter"
  (let ([s (pipeline-filter even?)])
    ((stage-fn s) '(1 2 3 4 5 6)))
  '(2 4 6))

;;; ---- pipeline-reduce ----

(test "pipeline-reduce sum"
  (let ([s (pipeline-reduce + 0)])
    ((stage-fn s) '(1 2 3 4 5)))
  15)

(test "pipeline-reduce product"
  (let ([s (pipeline-reduce * 1)])
    ((stage-fn s) '(1 2 3 4 5)))
  120)

;;; ---- pipeline-tap ----

(test "pipeline-tap passthrough"
  (let* ([log '()]
         [s (pipeline-tap (lambda (v) (set! log (cons v log))))])
    (let ([result ((stage-fn s) 42)])
      (list result log)))
  '(42 (42)))

;;; ---- pipeline-catch ----

(test "pipeline-catch handles error"
  (let* ([s (pipeline-catch (lambda (exn val) 'recovered))]
         [result ((stage-fn s) 'anything)])
  result)
  'anything)

;;; ---- pipeline-compose ----

(test "pipeline-compose"
  (let* ([s1 (make-stage "double" (lambda (x) (* 2 x)))]
         [s2 (make-stage "inc" (lambda (x) (+ x 1)))]
         [composed (pipeline-compose s1 s2)])
    ((stage-fn composed) 5))
  11)

;;; ---- combined pipeline ----

(test "full data pipeline"
  (let* ([p (make-pipeline)]
         [s1 (pipeline-filter even?)]
         [s2 (pipeline-map (lambda (x) (* x x)))]
         [s3 (pipeline-reduce + 0)])
    (pipeline-add-stage! p s1)
    (pipeline-add-stage! p s2)
    (pipeline-add-stage! p s3)
    (pipeline-run p '(1 2 3 4 5 6)))
  56)

(printf "~%Pipeline tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
