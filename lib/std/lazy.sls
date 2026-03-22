#!chezscheme
;;; (std lazy) — Lazy streams (SRFI-41 style, simplified)
;;;
;;; Lazy lists where the head is eager and the tail is delayed.
;;; Uses explicit promise records for laziness.
;;;
;;; API:
;;;   (delay expr)             — create a promise (syntax)
;;;   (force p)                — force a promise
;;;   (lazy expr)              — create a lazy promise (for iterative forcing)
;;;   (lcons head tail-expr)   — lazy pair: head eager, tail delayed
;;;   (lcar s)                 — head of lazy list
;;;   (lcdr s)                 — force and return tail
;;;   lnull                    — the empty lazy list
;;;   (lnull? s)               — test for empty
;;;   (ltake s n)              — take n elements as a regular list
;;;   (ldrop s n)              — drop n elements, return lazy list
;;;   (lmap f s)               — lazy map
;;;   (lfilter pred s)         — lazy filter
;;;   (lfold f init s)         — eager left fold over lazy list
;;;   (lappend s1 s2)          — lazy append
;;;   (list->llist ls)         — convert list to lazy list
;;;   (llist->list s)          — convert lazy list to list (forces all)
;;;   (literate f x)           — infinite lazy list: x, (f x), (f (f x)), ...
;;;   (lrange start)           — infinite lazy list: start, start+1, ...
;;;   (lrange start end)       — finite lazy list: start ... end-1
;;;   (lrange start end step)  — finite lazy list with step

(library (std lazy)
  (export lazy delay force
          lcons lcar lcdr lnull lnull? ltake ldrop
          lmap lfilter lfold lappend
          list->llist llist->list literate lrange)

  (import (except (chezscheme) delay force))

  ;; ========== Promise infrastructure ==========
  ;;
  ;; We use our own promise type rather than Chez's built-in delay/force
  ;; so we can support the `lazy` form (SRFI-45 iterative forcing) which
  ;; prevents stack overflow on deeply nested lazy structures.
  ;;
  ;; A promise is a mutable record holding either:
  ;;   - tag 'eager, val = the forced value
  ;;   - tag 'lazy,  val = a thunk that returns a promise
  ;;   - tag 'delay, val = a thunk that returns a value

  (define-record-type promise
    (nongenerative std-lazy-promise)
    (fields (mutable tag) (mutable val))
    (protocol
      (lambda (new)
        (case-lambda
          [(tag val) (new tag val)]))))

  ;; (delay expr) — standard delay: wraps expr in a thunk, tagged 'delay.
  (define-syntax delay
    (syntax-rules ()
      [(_ expr)
       (make-promise 'delay (lambda () expr))]))

  ;; (lazy expr) — lazy promise: expr must evaluate to a promise.
  ;; Enables iterative forcing (SRFI-45).
  (define-syntax lazy
    (syntax-rules ()
      [(_ expr)
       (make-promise 'lazy (lambda () expr))]))

  ;; (force p) — force a promise, with iterative convergence for 'lazy.
  ;; Non-promise values are returned as-is for convenience.
  (define (force p)
    (if (not (promise? p))
        p
        (case (promise-tag p)
          [(eager) (promise-val p)]
          [(delay)
           (let ([val ((promise-val p))])
             (when (eq? (promise-tag p) 'delay)  ; check not yet forced by reentrant force
               (promise-tag-set! p 'eager)
               (promise-val-set! p val))
             (force p))]
          [(lazy)
           (let ([inner ((promise-val p))])
             (when (eq? (promise-tag p) 'lazy)
               (promise-tag-set! p (promise-tag inner))
               (promise-val-set! p (promise-val inner)))
             (force p))]
          [else (error 'force "invalid promise tag" (promise-tag p))])))

  ;; ========== Lazy list primitives ==========

  ;; Sentinel for the empty lazy list.
  (define lnull (make-promise 'eager 'lnull-sentinel))

  (define (lnull? s)
    (and (promise? s)
         (eq? (promise-tag s) 'eager)
         (eq? (promise-val s) 'lnull-sentinel)))

  ;; A lazy pair: (eager-head . delayed-tail)
  ;; Represented as a promise wrapping a cons cell.
  (define-syntax lcons
    (syntax-rules ()
      [(_ head tail-expr)
       (make-promise 'eager (cons head (delay tail-expr)))]))

  (define (lcar s)
    (let ([v (force s)])
      (if (pair? v)
          (car v)
          (error 'lcar "not a lazy pair" s))))

  (define (lcdr s)
    (let ([v (force s)])
      (if (pair? v)
          (force (cdr v))
          (error 'lcdr "not a lazy pair" s))))

  ;; ========== Derived operations ==========

  ;; Take up to n elements as a regular list.
  (define (ltake s n)
    (if (or (<= n 0) (lnull? s))
        '()
        (cons (lcar s)
              (ltake (lcdr s) (- n 1)))))

  ;; Drop n elements, return the resulting lazy list.
  (define (ldrop s n)
    (if (or (<= n 0) (lnull? s))
        s
        (ldrop (lcdr s) (- n 1))))

  ;; Lazy map.
  (define (lmap f s)
    (if (lnull? s)
        lnull
        (lcons (f (lcar s))
               (lmap f (lcdr s)))))

  ;; Lazy filter.
  (define (lfilter pred s)
    (if (lnull? s)
        lnull
        (let ([head (lcar s)])
          (if (pred head)
              (lcons head (lfilter pred (lcdr s)))
              (lfilter pred (lcdr s))))))

  ;; Eager left fold.
  (define (lfold f init s)
    (if (lnull? s)
        init
        (lfold f (f init (lcar s)) (lcdr s))))

  ;; Lazy append.
  (define (lappend s1 s2)
    (if (lnull? s1)
        s2
        (lcons (lcar s1)
               (lappend (lcdr s1) s2))))

  ;; Convert a regular list to a lazy list.
  (define (list->llist ls)
    (if (null? ls)
        lnull
        (lcons (car ls) (list->llist (cdr ls)))))

  ;; Convert a lazy list to a regular list (forces everything).
  (define (llist->list s)
    (if (lnull? s)
        '()
        (cons (lcar s) (llist->list (lcdr s)))))

  ;; Infinite lazy list: x, (f x), (f (f x)), ...
  (define (literate f x)
    (lcons x (literate f (f x))))

  ;; (lrange start) — infinite: start, start+1, ...
  ;; (lrange start end) — finite: start ... end-1
  ;; (lrange start end step) — finite with step
  (define lrange
    (case-lambda
      [(start)
       (literate (lambda (n) (+ n 1)) start)]
      [(start end)
       (lrange start end 1)]
      [(start end step)
       (if (if (positive? step)
               (>= start end)
               (<= start end))
           lnull
           (lcons start (lrange (+ start step) end step)))]))

) ;; end library
