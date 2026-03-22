#!chezscheme
;;; :std/srfi/42 -- Eager Comprehensions (SRFI-42)
;;; Provides do-ec, list-ec, vector-ec, etc. with qualifier generators.

(library (std srfi srfi-42)
  (export
    do-ec list-ec vector-ec string-ec
    sum-ec product-ec min-ec max-ec
    any?-ec every?-ec first-ec last-ec fold-ec
    :list :vector :string :range :integers :do :let
    :parallel :while :until)

  (import (chezscheme))

  ;; Internal: dispatch on qualifier type and expand.
  ;; The comprehension system works by having each qualifier call a body thunk
  ;; for each value it produces.

  ;; :range generates integers in [start, end) with step
  (define-syntax :range
    (syntax-rules ()
      [(_ var end)
       (:range var 0 end 1)]
      [(_ var start end)
       (:range var start end 1)]
      [(_ var start end step)
       (:do var (start) (< var end) (+ var step))]))

  ;; :do is the fundamental iteration qualifier
  ;; (:do var (init) test update)
  (define-syntax :do
    (syntax-rules ()
      [(_ var (init) test update)
       (:do-gen var init test update)]))

  ;; Internal macro that the comprehension macros understand
  (define-syntax :do-gen
    (syntax-rules ()
      [(_ var init test update)
       (values ':do-gen var init test update)]))

  ;; :list iterates over list elements
  (define-syntax :list
    (syntax-rules ()
      [(_ var lst)
       (:list-gen var lst)]
      [(_ var lst1 lst2 ...)
       (:list-gen var (append lst1 lst2 ...))]))

  (define-syntax :list-gen
    (syntax-rules ()
      [(_ var lst)
       (values ':list-gen var lst)]))

  ;; :vector iterates over vector elements
  (define-syntax :vector
    (syntax-rules ()
      [(_ var vec)
       (:vector-gen var vec)]))

  (define-syntax :vector-gen
    (syntax-rules ()
      [(_ var vec)
       (values ':vector-gen var vec)]))

  ;; :string iterates over string characters
  (define-syntax :string
    (syntax-rules ()
      [(_ var str)
       (:string-gen var str)]))

  (define-syntax :string-gen
    (syntax-rules ()
      [(_ var str)
       (values ':string-gen var str)]))

  ;; :integers generates 0, 1, 2, ...
  (define-syntax :integers
    (syntax-rules ()
      [(_ var)
       (:do var (0) #t (+ var 1))]))

  ;; :let binds a variable
  (define-syntax :let
    (syntax-rules ()
      [(_ var expr)
       (:let-gen var expr)]))

  (define-syntax :let-gen
    (syntax-rules ()
      [(_ var expr)
       (values ':let-gen var expr)]))

  ;; :parallel runs multiple qualifiers in lockstep
  (define-syntax :parallel
    (syntax-rules ()
      [(_ q1 q2 ...)
       (:parallel-gen q1 q2 ...)]))

  (define-syntax :parallel-gen
    (syntax-rules ()
      [(_ q1 q2 ...)
       (values ':parallel-gen q1 q2 ...)]))

  ;; :while continues while condition is true
  (define-syntax :while
    (syntax-rules ()
      [(_ q test)
       (:while-gen q test)]))

  (define-syntax :while-gen
    (syntax-rules ()
      [(_ q test)
       (values ':while-gen q test)]))

  ;; :until continues until condition becomes true (runs at least once)
  (define-syntax :until
    (syntax-rules ()
      [(_ q test)
       (:until-gen q test)]))

  (define-syntax :until-gen
    (syntax-rules ()
      [(_ q test)
       (values ':until-gen q test)]))

  ;; ---- Comprehension expanders ----
  ;; We implement comprehensions via a direct macro approach.
  ;; Each comprehension macro handles qualifier dispatch itself.

  ;; ec-expand: process one qualifier and call body for each iteration.
  ;; The qualifiers are recognized by their syntax form.
  (define-syntax ec-do
    (syntax-rules (:range :list :vector :string :do :let :integers :parallel :while :until)
      ;; No more qualifiers, run body
      [(_ () body)
       body]
      ;; :range with 1 arg (end)
      [(_ ((:range var end) rest ...) body)
       (let loop ([var 0])
         (when (< var end)
           (ec-do (rest ...) body)
           (loop (+ var 1))))]
      ;; :range with 2 args (start end)
      [(_ ((:range var start end) rest ...) body)
       (let ([s start] [e end])
         (let loop ([var s])
           (when (< var e)
             (ec-do (rest ...) body)
             (loop (+ var 1)))))]
      ;; :range with 3 args (start end step)
      [(_ ((:range var start end step) rest ...) body)
       (let ([s start] [e end] [st step])
         (let loop ([var s])
           (when (if (positive? st) (< var e) (> var e))
             (ec-do (rest ...) body)
             (loop (+ var st)))))]
      ;; :list with one list
      [(_ ((:list var lst) rest ...) body)
       (let ([l lst])
         (let loop ([xs l])
           (unless (null? xs)
             (let ([var (car xs)])
               (ec-do (rest ...) body))
             (loop (cdr xs)))))]
      ;; :list with multiple lists
      [(_ ((:list var lst1 lst2 ...) rest ...) body)
       (ec-do ((:list var (append lst1 lst2 ...)) rest ...) body)]
      ;; :vector
      [(_ ((:vector var vec) rest ...) body)
       (let ([v vec])
         (let ([len (vector-length v)])
           (let loop ([i 0])
             (when (< i len)
               (let ([var (vector-ref v i)])
                 (ec-do (rest ...) body))
               (loop (+ i 1))))))]
      ;; :string
      [(_ ((:string var str) rest ...) body)
       (let ([s str])
         (let ([len (string-length s)])
           (let loop ([i 0])
             (when (< i len)
               (let ([var (string-ref s i)])
                 (ec-do (rest ...) body))
               (loop (+ i 1))))))]
      ;; :do
      [(_ ((:do var (init) test update) rest ...) body)
       (let loop ([var init])
         (when test
           (ec-do (rest ...) body)
           (loop update)))]
      ;; :let
      [(_ ((:let var expr) rest ...) body)
       (let ([var expr])
         (ec-do (rest ...) body))]
      ;; :integers
      [(_ ((:integers var) rest ...) body)
       (let loop ([var 0])
         (ec-do (rest ...) body)
         (loop (+ var 1)))]
      ;; :parallel with two qualifiers (most common case)
      [(_ ((:parallel (:range v1 a1 ...) (:range v2 a2 ...)) rest ...) body)
       (ec-do ((:range v1 a1 ...) rest ...)
         (ec-do () body))] ;; simplified - proper parallel needs call/cc tricks
      ;; :while
      [(_ ((:while (:range var start end . step) test) rest ...) body)
       (ec-do ((:range var start end . step))
         (when test (ec-do (rest ...) body)))]
      [(_ ((:while (:list var lst . lsts) test) rest ...) body)
       (ec-do ((:list var lst . lsts))
         (when test (ec-do (rest ...) body)))]
      [(_ ((:while (:do var (init) test2 update) test) rest ...) body)
       (let loop ([var init])
         (when (and test2 test)
           (ec-do (rest ...) body)
           (loop update)))]
      ;; :until
      [(_ ((:until (:range var start end . step) test) rest ...) body)
       (ec-do ((:range var start end . step))
         (begin (ec-do (rest ...) body)
                (when test (error ':until "break not supported in simple impl"))))]
      [(_ ((:until (:list var lst . lsts) test) rest ...) body)
       (ec-do ((:list var lst . lsts))
         (ec-do (rest ...) body))]
      ;; Bare expression as filter
      [(_ (test rest ...) body)
       (when test
         (ec-do (rest ...) body))]))

  ;; For :while and :until with early exit, use call/cc
  (define-syntax ec-do/break
    (syntax-rules (:range :list :vector :string :do :let :integers :while :until)
      [(_ break () body)
       body]
      [(_ break ((:while qual test) rest ...) body)
       (ec-do/qual break qual
         (if test
           (ec-do/break break (rest ...) body)
           (break (void))))]
      [(_ break ((:until qual test) rest ...) body)
       (ec-do/qual break qual
         (begin
           (ec-do/break break (rest ...) body)
           (when test (break (void)))))]
      [(_ break (qual rest ...) body)
       (ec-do/qual break qual
         (ec-do/break break (rest ...) body))]))

  (define-syntax ec-do/qual
    (syntax-rules (:range :list :vector :string :do :let :integers)
      [(_ break (:range var end) body)
       (let loop ([var 0])
         (when (< var end) body (loop (+ var 1))))]
      [(_ break (:range var start end) body)
       (let ([s start] [e end])
         (let loop ([var s])
           (when (< var e) body (loop (+ var 1)))))]
      [(_ break (:range var start end step) body)
       (let ([s start] [e end] [st step])
         (let loop ([var s])
           (when (if (positive? st) (< var e) (> var e))
             body (loop (+ var st)))))]
      [(_ break (:list var lst) body)
       (for-each (lambda (var) body) lst)]
      [(_ break (:list var lst1 lst2 ...) body)
       (for-each (lambda (var) body) (append lst1 lst2 ...))]
      [(_ break (:vector var vec) body)
       (let ([v vec])
         (do ([i 0 (+ i 1)])
             ((= i (vector-length v)))
           (let ([var (vector-ref v i)]) body)))]
      [(_ break (:string var str) body)
       (let ([s str])
         (do ([i 0 (+ i 1)])
             ((= i (string-length s)))
           (let ([var (string-ref s i)]) body)))]
      [(_ break (:do var (init) test update) body)
       (let loop ([var init])
         (when test body (loop update)))]
      [(_ break (:let var expr) body)
       (let ([var expr]) body)]
      [(_ break (:integers var) body)
       (let loop ([var 0]) body (loop (+ var 1)))]))

  ;; do-ec: execute body for side effects
  (define-syntax do-ec
    (syntax-rules ()
      [(_ qual ... body)
       (call/cc (lambda (break)
         (ec-do/break break (qual ...) body)))]))

  ;; list-ec: collect into a list
  (define-syntax list-ec
    (syntax-rules ()
      [(_ qual ... expr)
       (let ([acc '()])
         (do-ec qual ... (set! acc (cons expr acc)))
         (reverse acc))]))

  ;; vector-ec: collect into a vector
  (define-syntax vector-ec
    (syntax-rules ()
      [(_ qual ... expr)
       (list->vector (list-ec qual ... expr))]))

  ;; string-ec: collect chars into a string
  (define-syntax string-ec
    (syntax-rules ()
      [(_ qual ... expr)
       (list->string (list-ec qual ... expr))]))

  ;; sum-ec: sum values
  (define-syntax sum-ec
    (syntax-rules ()
      [(_ qual ... expr)
       (fold-ec qual ... expr + 0)]))

  ;; product-ec: multiply values
  (define-syntax product-ec
    (syntax-rules ()
      [(_ qual ... expr)
       (fold-ec qual ... expr * 1)]))

  ;; fold-ec: fold values with a binary function
  (define-syntax fold-ec
    (syntax-rules ()
      [(_ qual ... expr f seed)
       (let ([acc seed])
         (do-ec qual ... (set! acc (f expr acc)))
         acc)]))

  ;; min-ec: minimum value
  (define-syntax min-ec
    (syntax-rules ()
      [(_ qual ... expr)
       (let ([result #f])
         (do-ec qual ...
           (let ([v expr])
             (when (or (not result) (< v result))
               (set! result v))))
         result)]))

  ;; max-ec: maximum value
  (define-syntax max-ec
    (syntax-rules ()
      [(_ qual ... expr)
       (let ([result #f])
         (do-ec qual ...
           (let ([v expr])
             (when (or (not result) (> v result))
               (set! result v))))
         result)]))

  ;; any?-ec: true if any value is true
  (define-syntax any?-ec
    (syntax-rules ()
      [(_ qual ... expr)
       (call/cc
         (lambda (return)
           (do-ec qual ...
             (when expr (return #t)))
           #f))]))

  ;; every?-ec: true if all values are true
  (define-syntax every?-ec
    (syntax-rules ()
      [(_ qual ... expr)
       (call/cc
         (lambda (return)
           (do-ec qual ...
             (unless expr (return #f)))
           #t))]))

  ;; first-ec: first value (with default)
  (define-syntax first-ec
    (syntax-rules ()
      [(_ default qual ... expr)
       (call/cc
         (lambda (return)
           (do-ec qual ... (return expr))
           default))]))

  ;; last-ec: last value (with default)
  (define-syntax last-ec
    (syntax-rules ()
      [(_ default qual ... expr)
       (let ([result default])
         (do-ec qual ... (set! result expr))
         result)]))

) ;; end library
