#!chezscheme
;;; (std logic) — Embedded logic programming (miniKanren)
;;;
;;; Full relational programming with unification, backtracking, and search.
;;; Leverages Chez's native first-class continuations for efficient search.
;;;
;;; API:
;;;   (run n (q) goal ...)         — find up to n solutions for q
;;;   (run* (q) goal ...)          — find all solutions for q
;;;   (fresh (x ...) goal ...)     — introduce fresh logic variables
;;;   (== u v)                     — unify u and v
;;;   (=/= u v)                    — disequality constraint
;;;   (conde [goal ...] ...)       — disjunction (or)
;;;   (conj goal ...)              — conjunction (and)
;;;   (membero x lst)              — relational list membership
;;;   (appendo l1 l2 out)          — relational list append
;;;   (var x)                      — create a fresh logic variable named x
;;;   (var? x)                     — test for logic variable

(library (std logic)
  (export run run* fresh == =/= conde conj
          membero appendo caro cdro conso nullo pairo
          var var? reify)

  (import (chezscheme))

  ;; ========== Logic variables ==========

  (define-record-type lvar
    (fields (immutable name) (immutable idx))
    (sealed #t))

  (define var-counter 0)

  (define (var name)
    (set! var-counter (+ var-counter 1))
    (make-lvar name var-counter))

  (define (var? x) (lvar? x))

  ;; ========== Substitution (association list) ==========

  (define empty-subst '())

  (define (walk v s)
    (cond
      [(and (var? v)
            (assq v s))
       => (lambda (a) (walk (cdr a) s))]
      [else v]))

  (define (walk* v s)
    (let ([v (walk v s)])
      (cond
        [(var? v) v]
        [(pair? v) (cons (walk* (car v) s) (walk* (cdr v) s))]
        [else v])))

  (define (ext-s x v s)
    (cons (cons x v) s))

  ;; ========== Occurs check ==========

  (define (occurs? x v s)
    (let ([v (walk v s)])
      (cond
        [(var? v) (eq? x v)]
        [(pair? v) (or (occurs? x (car v) s)
                       (occurs? x (cdr v) s))]
        [else #f])))

  ;; ========== Unification ==========

  (define (unify u v s)
    (let ([u (walk u s)]
          [v (walk v s)])
      (cond
        [(eq? u v) s]
        [(var? u) (if (occurs? u v s) #f (ext-s u v s))]
        [(var? v) (if (occurs? v u s) #f (ext-s v u s))]
        [(and (pair? u) (pair? v))
         (let ([s (unify (car u) (car v) s)])
           (and s (unify (cdr u) (cdr v) s)))]
        [(equal? u v) s]
        [else #f])))

  ;; ========== Streams (lazy search via thunks) ==========
  ;; A stream is:
  ;;   '()          — empty
  ;;   (cons s rest) — a substitution s followed by more results
  ;;   (lambda () stream) — a thunk (suspension for interleaving)

  (define mzero '())

  (define (unit s/c) (cons s/c mzero))

  (define (mplus $1 $2)
    (cond
      [(null? $1) $2]
      [(procedure? $1) (lambda () (mplus $2 ($1)))]  ;; interleave
      [else (cons (car $1) (mplus (cdr $1) $2))]))

  (define (bind $ g)
    (cond
      [(null? $) mzero]
      [(procedure? $) (lambda () (bind ($) g))]
      [else (mplus (g (car $)) (bind (cdr $) g))]))

  ;; ========== State: (subst . constraint-store) ==========

  (define (make-state s cs) (cons s cs))
  (define (state-subst s/c) (car s/c))
  (define (state-constraints s/c) (cdr s/c))

  (define empty-state (make-state empty-subst '()))

  ;; ========== Goals ==========

  (define (== u v)
    (lambda (s/c)
      (let ([s (unify u v (state-subst s/c))])
        (if s
          (unit (make-state s (state-constraints s/c)))
          mzero))))

  ;; Disequality constraint
  (define (=/= u v)
    (lambda (s/c)
      (let ([s (unify u v (state-subst s/c))])
        (cond
          [(not s) (unit s/c)]  ;; already different, constraint trivially holds
          [(equal? s (state-subst s/c)) mzero]  ;; they unified without extension => equal
          [else
           ;; Record the constraint (extensions needed to make them equal)
           (let ([new-cs (cons (cons u v) (state-constraints s/c))])
             (unit (make-state (state-subst s/c) new-cs)))]))))

  (define (conj . goals)
    (if (null? goals)
      (lambda (s/c) (unit s/c))
      (let loop ([gs goals])
        (if (null? (cdr gs))
          (car gs)
          (lambda (s/c) (bind ((car gs) s/c) (loop (cdr gs))))))))

  ;; ========== conde macro ==========

  (define-syntax conde
    (syntax-rules ()
      [(_ [g0 g ...] ...)
       (disj* (conj* g0 g ...) ...)]))

  (define-syntax conj*
    (syntax-rules ()
      [(_ g) g]
      [(_ g0 g ...)
       (lambda (s/c) (bind (g0 s/c) (conj* g ...)))]))

  (define-syntax disj*
    (syntax-rules ()
      [(_ g) g]
      [(_ g0 g ...)
       (lambda (s/c) (mplus (g0 s/c) ((disj* g ...) s/c)))]))

  ;; ========== fresh macro ==========

  (define-syntax fresh
    (syntax-rules ()
      [(_ () g0 g ...)
       (conj* g0 g ...)]
      [(_ (x0 x ...) g0 g ...)
       (lambda (s/c)
         (let ([x0 (var 'x0)])
           ((fresh (x ...) g0 g ...) s/c)))]))

  ;; ========== Reification ==========

  (define (reify-name n)
    (string->symbol (string-append "_." (number->string n))))

  (define (reify v s)
    (let ([v (walk* v s)])
      (let loop ([v v] [r '()] [n 0])
        (cond
          [(var? v)
           (let ([a (assq v r)])
             (if a
               (values (cdr a) r n)
               (let ([name (reify-name n)])
                 (values name (cons (cons v name) r) (+ n 1)))))]
          [(pair? v)
           (let-values ([(car-v r n) (loop (car v) r n)])
             (let-values ([(cdr-v r n) (loop (cdr v) r n)])
               (values (cons car-v cdr-v) r n)))]
          [else (values v r n)]))))

  (define (reify-state/1st-var s/c)
    (let ([v (walk* (var 'q) (state-subst s/c))])
      ;; Walk to find the first variable — we pass through reify for display
      (let-values ([(rv _r _n) (reify v '())])
        rv)))

  ;; ========== take ==========

  (define (take n $)
    (cond
      [(and n (zero? n)) '()]
      [(null? $) '()]
      [(procedure? $) (take n ($))]
      [else (cons (car $) (take (and n (- n 1)) (cdr $)))]))

  ;; ========== run / run* macros ==========

  (define-syntax run
    (syntax-rules ()
      [(_ n (q) g0 g ...)
       (let ([q (var 'q)])
         (map (lambda (s/c)
                (let ([v (walk* q (state-subst s/c))])
                  (let-values ([(rv _r _n) (reify v '())])
                    rv)))
              (take n ((conj* g0 g ...) empty-state))))]))

  (define-syntax run*
    (syntax-rules ()
      [(_ (q) g0 g ...)
       (run #f (q) g0 g ...)]))

  ;; ========== Common relations ==========

  (define (caro p a)
    (fresh (d)
      (== (cons a d) p)))

  (define (cdro p d)
    (fresh (a)
      (== (cons a d) p)))

  (define (conso a d p)
    (== (cons a d) p))

  (define (nullo x)
    (== '() x))

  (define (pairo p)
    (fresh (a d)
      (== (cons a d) p)))

  (define (membero x lst)
    (fresh (head tail)
      (== (cons head tail) lst)
      (conde
        [(== x head)]
        [(membero x tail)])))

  (define (appendo l1 l2 out)
    (conde
      [(nullo l1) (== l2 out)]
      [(fresh (a d res)
         (conso a d l1)
         (conso a res out)
         (appendo d l2 res))]))

) ;; end library
