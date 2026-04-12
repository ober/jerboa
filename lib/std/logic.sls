#!chezscheme
;;; (std logic) — miniKanren logic programming (core.logic equivalent)
;;;
;;; A minimal but complete implementation of miniKanren for Jerboa,
;;; providing the same core operations as Clojure's core.logic:
;;;
;;;   (run* (q) (membero q '(1 2 3)))   ;; => (1 2 3)
;;;   (run 2 (q) (membero q '(a b c)))  ;; => (a b)
;;;
;;; Core forms: run, run*, fresh, ==, conde, conso, caro, cdro,
;;;             appendo, membero, succeed, fail
;;;
;;; Based on the canonical microKanren/miniKanren design by
;;; Friedman, Byrd, and Kiselyov.

(library (std logic)
  (export
    ;; Core
    == run run* fresh conde conda condu
    succeed fail
    ;; Relations
    conso caro cdro nullo pairo
    appendo membero
    absento
    ;; Logic variable inspection
    (rename (new-lvar lvar)) lvar? reify)

  (import (chezscheme))

  ;; ================================================================
  ;; Logic Variables
  ;; ================================================================

  (define-record-type lvar
    (fields (immutable name) (immutable id))
    (protocol
      (lambda (new)
        (let ([counter 0])
          (lambda (name)
            (set! counter (+ counter 1))
            (new name counter))))))

  ;; User-facing constructor alias
  (define new-lvar make-lvar)

  (define (lvar=? x y)
    (and (lvar? x) (lvar? y)
         (= (lvar-id x) (lvar-id y))))

  ;; ================================================================
  ;; Substitutions (association list of lvar → value)
  ;; ================================================================

  (define empty-s '())

  (define (walk v s)
    (cond
      [(and (lvar? v) (assoc-lvar v s))
       => (lambda (binding) (walk (cdr binding) s))]
      [else v]))

  (define (assoc-lvar v s)
    (cond
      [(null? s) #f]
      [(lvar=? v (caar s)) (car s)]
      [else (assoc-lvar v (cdr s))]))

  (define (walk* v s)
    (let ([v (walk v s)])
      (cond
        [(lvar? v) v]
        [(pair? v) (cons (walk* (car v) s) (walk* (cdr v) s))]
        [else v])))

  (define (ext-s x v s)
    (cond
      [(occurs? x v s) #f]   ;; occurs check
      [else (cons (cons x v) s)]))

  (define (occurs? x v s)
    (let ([v (walk v s)])
      (cond
        [(lvar? v) (lvar=? v x)]
        [(pair? v) (or (occurs? x (car v) s) (occurs? x (cdr v) s))]
        [else #f])))

  ;; ================================================================
  ;; Unification
  ;; ================================================================

  (define (unify u v s)
    (let ([u (walk u s)]
          [v (walk v s)])
      (cond
        [(and (lvar? u) (lvar? v) (lvar=? u v)) s]
        [(lvar? u) (ext-s u v s)]
        [(lvar? v) (ext-s v u s)]
        [(and (pair? u) (pair? v))
         (let ([s (unify (car u) (car v) s)])
           (and s (unify (cdr u) (cdr v) s)))]
        [(equal? u v) s]
        [else #f])))

  ;; ================================================================
  ;; Goals and Streams
  ;;
  ;; A goal is: substitution → stream
  ;; A stream is: '() | (cons substitution stream) | (lambda () stream)
  ;; ================================================================

  ;; == — unification goal
  (define (== u v)
    (lambda (s)
      (let ([s2 (unify u v s)])
        (if s2 (list s2) '()))))

  ;; succeed / fail
  (define (succeed s) (list s))
  (define (fail s) '())

  ;; ---- Stream operations ----

  ;; mplus — interleaving merge of two streams
  (define (mplus s1 s2)
    (cond
      [(null? s1) s2]
      [(procedure? s1) (lambda () (mplus s2 (s1)))]
      [else (cons (car s1) (mplus (cdr s1) s2))]))

  ;; bind — flatmap over a stream
  (define (bind s g)
    (cond
      [(null? s) '()]
      [(procedure? s) (lambda () (bind (s) g))]
      [else (mplus (g (car s)) (bind (cdr s) g))]))

  ;; ---- Conjunction and disjunction ----

  (define (conj2 g1 g2)
    (lambda (s) (bind (g1 s) g2)))

  (define (disj2 g1 g2)
    (lambda (s) (mplus (g1 s) (g2 s))))

  ;; ---- take from a stream ----

  (define (take-stream n s)
    (cond
      [(and n (zero? n)) '()]
      [(null? s) '()]
      [(procedure? s) (take-stream n (s))]
      [else
       (cons (car s)
             (take-stream (and n (- n 1)) (cdr s)))]))

  ;; ================================================================
  ;; Macros: fresh, conde, conda, condu, run, run*
  ;; ================================================================

  ;; fresh — introduce fresh logic variables
  (define-syntax fresh
    (syntax-rules ()
      [(_ () g0 g ...)
       (conj* g0 g ...)]
      [(_ (x0 x ...) g0 g ...)
       (call/fresh 'x0
         (lambda (x0)
           (fresh (x ...) g0 g ...)))]))

  (define (call/fresh name f)
    (lambda (s)
      ((f (make-lvar name)) s)))

  ;; conj* — chain multiple goals in conjunction
  (define-syntax conj*
    (syntax-rules ()
      [(_ g) g]
      [(_ g0 g ...) (conj2 g0 (conj* g ...))]))

  ;; disj* — chain multiple goals in disjunction
  (define-syntax disj*
    (syntax-rules ()
      [(_ g) g]
      [(_ g0 g ...) (disj2 g0 (disj* g ...))]))

  ;; conde — each clause is a conjunction; clauses are disjoined
  (define-syntax conde
    (syntax-rules ()
      [(_ (g0 g ...) ...)
       (disj* (conj* g0 g ...) ...)]))

  ;; conda — soft-cut: commit to first clause that succeeds
  (define-syntax conda
    (syntax-rules ()
      [(_ (g0 g ...) ...)
       (lambda (s)
         (conda-helper s (g0 g ...) ...))]))

  (define-syntax conda-helper
    (syntax-rules ()
      [(_ s) '()]
      [(_ s (g0) rest ...)
       (let ([stream (g0 s)])
         (if (force-stream stream)
             stream
             (conda-helper s rest ...)))]
      [(_ s (g0 g ...) rest ...)
       (let ([stream (g0 s)])
         (if (force-stream stream)
             (bind stream (conj* g ...))
             (conda-helper s rest ...)))]))

  (define (force-stream s)
    (cond
      [(null? s) #f]
      [(procedure? s) (force-stream (s))]
      [else #t]))

  ;; condu — committed choice (like conda but takes at most one answer per clause)
  ;; Each clause commits and produces at most one result.
  (define-syntax condu
    (syntax-rules ()
      [(_ (g0 g ...) ...)
       (lambda (s)
         (condu-helper s (g0 g ...) ...))]))

  (define-syntax condu-helper
    (syntax-rules ()
      [(_ s) '()]
      [(_ s (g0) rest ...)
       (let ([stream (g0 s)])
         (if (force-stream stream)
             (take-stream 1 stream)
             (condu-helper s rest ...)))]
      [(_ s (g0 g ...) rest ...)
       (let ([stream (g0 s)])
         (if (force-stream stream)
             (take-stream 1 (bind stream (conj* g ...)))
             (condu-helper s rest ...)))]))

  ;; run — execute a logic program, returning at most n results
  (define-syntax run
    (syntax-rules ()
      [(_ n (q) g0 g ...)
       (let ([q (make-lvar 'q)])
         (map (reify q)
              (take-stream n
                ((conj* g0 g ...) empty-s))))]))

  ;; run* — execute returning all results
  (define-syntax run*
    (syntax-rules ()
      [(_ (q) g0 g ...)
       (let ([q (make-lvar 'q)])
         (map (reify q)
              (take-stream #f
                ((conj* g0 g ...) empty-s))))]))

  ;; ================================================================
  ;; Reification — turn logic variables into readable symbols
  ;; ================================================================

  (define (reify x)
    (lambda (s)
      (let* ([v (walk* x s)]
             [r (reify-s v empty-s)])
        (walk* v r))))

  (define (reify-s v s)
    (let ([v (walk v s)])
      (cond
        [(lvar? v)
         (let ([n (reify-name (length s))])
           (cons (cons v n) s))]
        [(pair? v) (reify-s (cdr v) (reify-s (car v) s))]
        [else s])))

  (define (reify-name n)
    (string->symbol
      (string-append "_." (number->string n))))

  ;; ================================================================
  ;; Built-in Relations
  ;; ================================================================

  ;; conso — (cons a d) == l
  (define (conso a d l)
    (== (cons a d) l))

  ;; caro — (car l) == a
  (define (caro l a)
    (fresh (d)
      (conso a d l)))

  ;; cdro — (cdr l) == d
  (define (cdro l d)
    (fresh (a)
      (conso a d l)))

  ;; nullo — l is null
  (define (nullo l)
    (== l '()))

  ;; pairo — l is a pair
  (define (pairo l)
    (fresh (a d)
      (conso a d l)))

  ;; appendo — (append l s) == out
  (define (appendo l s out)
    (conde
      [(nullo l) (== s out)]
      [(fresh (a d res)
         (conso a d l)
         (conso a res out)
         (appendo d s res))]))

  ;; membero — x is a member of l
  (define (membero x l)
    (conde
      [(caro l x)]
      [(fresh (d)
         (cdro l d)
         (membero x d))]))

  ;; absento — t does not appear anywhere in v
  ;; Simple version using disequality via negation
  (define (absento t v)
    (lambda (s)
      (let ([v (walk* v s)]
            [t (walk* t s)])
        (if (absent? t v)
            (list s)
            '()))))

  (define (absent? t v)
    (cond
      [(equal? t v) #f]
      [(pair? v) (and (absent? t (car v)) (absent? t (cdr v)))]
      [else #t]))

) ;; end library
