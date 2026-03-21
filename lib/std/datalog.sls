#!chezscheme
;;; (std datalog) — Incremental Datalog for reactive queries
;;;
;;; Bottom-up Datalog with semi-naive evaluation. When facts change,
;;; queries update incrementally.
;;;
;;; API:
;;;   (make-datalog)                 — create a datalog database
;;;   (datalog-assert! db fact)      — assert a fact (ground tuple)
;;;   (datalog-retract! db fact)     — retract a fact
;;;   (datalog-rule! db head body)   — add a rule: head :- body1 body2 ...
;;;   (datalog-query db pattern)     — query with pattern (variables start with ?)
;;;   (datalog-facts db)             — all facts
;;;   (datalog-rules db)             — all rules

(library (std datalog)
  (export make-datalog datalog-assert! datalog-retract!
          datalog-rule! datalog-query datalog-facts datalog-rules
          datalog-clear!)

  (import (chezscheme))

  ;; ========== Database ==========

  (define-record-type datalog-db
    (fields
      (mutable facts)          ;; list of ground tuples
      (mutable rules)          ;; list of (head . body-list)
      (mutable dirty?))        ;; needs re-evaluation
    (protocol
      (lambda (new)
        (lambda () (new '() '() #f)))))

  ;; ========== Facts ==========

  (define (make-datalog) (make-datalog-db))

  (define (datalog-assert! db fact)
    (unless (member fact (datalog-db-facts db))
      (datalog-db-facts-set! db (cons fact (datalog-db-facts db)))
      (datalog-db-dirty?-set! db #t)))

  (define (datalog-retract! db fact)
    (datalog-db-facts-set! db
      (filter (lambda (f) (not (equal? f fact)))
              (datalog-db-facts db)))
    (datalog-db-dirty?-set! db #t))

  (define (datalog-clear! db)
    (datalog-db-facts-set! db '())
    (datalog-db-rules-set! db '())
    (datalog-db-dirty?-set! db #f))

  (define (datalog-facts db) (datalog-db-facts db))
  (define (datalog-rules db) (datalog-db-rules db))

  ;; ========== Rules ==========

  ;; A rule: (head body1 body2 ...)
  ;; head and body are patterns like (ancestor ?x ?y)
  ;; Variables are symbols starting with ?

  (define (datalog-rule! db head . body)
    (datalog-db-rules-set! db
      (cons (cons head body) (datalog-db-rules db)))
    (datalog-db-dirty?-set! db #t))

  ;; ========== Pattern matching / unification ==========

  (define (variable? x)
    (and (symbol? x)
         (> (string-length (symbol->string x)) 0)
         (char=? (string-ref (symbol->string x) 0) #\?)))

  (define (match-pattern pattern fact env)
    ;; Try to match pattern against fact, extending env.
    ;; Returns new env or #f.
    (cond
      [(and (null? pattern) (null? fact)) env]
      [(or (null? pattern) (null? fact)) #f]
      [(variable? (car pattern))
       (let ([binding (assq (car pattern) env)])
         (if binding
           ;; Already bound: check consistency
           (if (equal? (cdr binding) (car fact))
             (match-pattern (cdr pattern) (cdr fact) env)
             #f)
           ;; New binding
           (match-pattern (cdr pattern) (cdr fact)
             (cons (cons (car pattern) (car fact)) env))))]
      [(equal? (car pattern) (car fact))
       (match-pattern (cdr pattern) (cdr fact) env)]
      [else #f]))

  (define (substitute pattern env)
    (map (lambda (x)
           (if (variable? x)
             (let ([b (assq x env)])
               (if b (cdr b) x))
             x))
         pattern))

  ;; ========== Semi-naive evaluation ==========

  (define (evaluate-rules! db)
    (let ([changed #t])
      (let loop ()
        (when changed
          (set! changed #f)
          (for-each
            (lambda (rule)
              (let ([head (car rule)]
                    [body (cdr rule)])
                ;; Find all satisfying environments for the body
                (let ([envs (evaluate-body body (datalog-db-facts db) '(()))])
                  (for-each
                    (lambda (env)
                      (let ([new-fact (substitute head env)])
                        (unless (member new-fact (datalog-db-facts db))
                          (datalog-db-facts-set! db
                            (cons new-fact (datalog-db-facts db)))
                          (set! changed #t))))
                    envs))))
            (datalog-db-rules db))
          (loop)))))

  (define (evaluate-body body facts envs)
    ;; For each body pattern, filter/extend environments
    (if (null? body)
      envs
      (let ([pattern (car body)]
            [rest (cdr body)])
        (let ([new-envs
               (apply append
                 (map (lambda (env)
                        (filter-map
                          (lambda (fact)
                            (match-pattern pattern fact env))
                          facts))
                      envs))])
          (evaluate-body rest facts new-envs)))))

  (define (filter-map proc lst)
    (let loop ([l lst] [acc '()])
      (if (null? l)
        (reverse acc)
        (let ([v (proc (car l))])
          (if v
            (loop (cdr l) (cons v acc))
            (loop (cdr l) acc))))))

  ;; ========== Query ==========

  (define (datalog-query db pattern)
    ;; First, ensure all derived facts are computed
    (when (datalog-db-dirty? db)
      (evaluate-rules! db)
      (datalog-db-dirty?-set! db #f))
    ;; Then match pattern against all facts
    (let ([results '()])
      (for-each
        (lambda (fact)
          (let ([env (match-pattern pattern fact '())])
            (when env
              (let ([result (substitute pattern env)])
                (unless (member result results)
                  (set! results (cons result results)))))))
        (datalog-db-facts db))
      (reverse results)))

) ;; end library
