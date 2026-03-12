#!chezscheme
;;; (std db query-compile) — SQL Query Builder/Compiler

(library (std db query-compile)
  (export
    ;; Query construction
    make-query query?
    from where select limit offset order-by
    ;; Compilation
    compile-query
    ;; Macros
    define-query
    ;; Parameter binding
    query-param query-param-name query-param-value
    ;; Utilities
    query->string)

  (import (chezscheme))

  ;; ========== Query Record ==========
  ;;
  ;; A query is a record tracking:
  ;;   table    : string (FROM clause)
  ;;   columns  : list of column names or * (SELECT clause)
  ;;   cond     : s-expr condition (WHERE clause) or #f
  ;;   limit-n  : integer or #f
  ;;   offset-n : integer or #f
  ;;   order    : list of (col . dir) pairs — dir is 'asc or 'desc

  (define-record-type query-rec
    (fields (immutable table   query-table)
            (immutable columns query-columns)
            (immutable cond    query-cond)
            (immutable limit-n query-limit)
            (immutable offset-n query-offset)
            (immutable order   query-order))
    (protocol
      (lambda (new)
        (lambda (table columns cond limit-n offset-n order)
          (new table columns cond limit-n offset-n order)))))

  (define (query? x) (query-rec? x))

  (define (make-query table)
    (make-query-rec table '* #f #f #f '()))

  ;; ========== Named Parameters ==========

  (define-record-type query-param-rec
    (fields (immutable name  query-param-name)
            (immutable value query-param-value))
    (protocol
      (lambda (new)
        (lambda (name value)
          (new name value)))))

  (define (query-param name value)
    (make-query-param-rec name value))

  ;; ========== Query Builder Combinators ==========

  ;; from: (from table . clauses) — creates a new query and applies clauses
  ;; When called as a function: (from "users") => base query
  ;; Clauses like (where ...) (select ...) etc. are applied via functional composition

  (define (from table . clauses)
    (let ([q (make-query table)])
      (let loop ([q q] [cs clauses])
        (if (null? cs)
            q
            (loop ((car cs) q) (cdr cs))))))

  (define (select cols)
    (lambda (q)
      (make-query-rec
        (query-table q)
        cols
        (query-cond q)
        (query-limit q)
        (query-offset q)
        (query-order q))))

  (define (where cond-expr)
    (lambda (q)
      (make-query-rec
        (query-table q)
        (query-columns q)
        cond-expr
        (query-limit q)
        (query-offset q)
        (query-order q))))

  (define (limit n)
    (lambda (q)
      (make-query-rec
        (query-table q)
        (query-columns q)
        (query-cond q)
        n
        (query-offset q)
        (query-order q))))

  (define (offset n)
    (lambda (q)
      (make-query-rec
        (query-table q)
        (query-columns q)
        (query-cond q)
        (query-limit q)
        n
        (query-order q))))

  (define (order-by col . dir-args)
    (let ([dir (if (null? dir-args) 'asc (car dir-args))])
      (lambda (q)
        (make-query-rec
          (query-table q)
          (query-columns q)
          (query-cond q)
          (query-limit q)
          (query-offset q)
          (append (query-order q) (list (cons col dir)))))))

  ;; ========== Condition Compilation ==========
  ;;
  ;; Condition expressions are S-expressions:
  ;;   (= col val)      => "col = ?"
  ;;   (< col val)      => "col < ?"
  ;;   (<= col val)     => "col <= ?"
  ;;   (> col val)      => "col > ?"
  ;;   (>= col val)     => "col >= ?"
  ;;   (!= col val)     => "col != ?"
  ;;   (and e1 e2 ...) => "e1 AND e2 AND ..."
  ;;   (or  e1 e2 ...) => "e1 OR e2 OR ..."
  ;;   (not e)          => "NOT (e)"
  ;;   (in col vals)    => "col IN (?,?,?)"
  ;;   (is-null col)    => "col IS NULL"
  ;;   (is-not-null col) => "col IS NOT NULL"
  ;;   (like col pat)   => "col LIKE ?"

  (define *params* '())

  (define (add-param! val)
    (set! *params* (append *params* (list val)))
    "?")

  (define (col->sql col)
    (cond
      [(symbol? col) (symbol->string col)]
      [(string? col) col]
      [else (error 'compile-query "invalid column reference" col)]))

  (define (op->sql op)
    (case op
      [(=)  "="]
      [(<)  "<"]
      [(<=) "<="]
      [(>)  ">"]
      [(>=) ">="]
      [(!=) "!="]
      [else (error 'compile-query "unknown operator" op)]))

  (define (compile-cond expr)
    (cond
      [(not (pair? expr))
       (error 'compile-query "invalid condition" expr)]
      [(eq? (car expr) 'and)
       (let ([parts (map compile-cond (cdr expr))])
         (string-append "(" (string-join parts " AND ") ")"))]
      [(eq? (car expr) 'or)
       (let ([parts (map compile-cond (cdr expr))])
         (string-append "(" (string-join parts " OR ") ")"))]
      [(eq? (car expr) 'not)
       (string-append "NOT (" (compile-cond (cadr expr)) ")")]
      [(eq? (car expr) 'in)
       (let* ([col  (col->sql (cadr expr))]
              [vals (caddr expr)]
              [placeholders (map (lambda (v) (add-param! v)) vals)])
         (string-append col " IN (" (string-join placeholders ", ") ")"))]
      [(eq? (car expr) 'is-null)
       (string-append (col->sql (cadr expr)) " IS NULL")]
      [(eq? (car expr) 'is-not-null)
       (string-append (col->sql (cadr expr)) " IS NOT NULL")]
      [(eq? (car expr) 'like)
       (let ([col (col->sql (cadr expr))]
             [pat (caddr expr)])
         (string-append col " LIKE " (add-param! pat)))]
      [(memq (car expr) '(= < <= > >= !=))
       (let* ([op  (op->sql (car expr))]
              [col (col->sql (cadr expr))]
              [val (caddr expr)]
              [placeholder (add-param! val)])
         (string-append col " " op " " placeholder))]
      [else
       (error 'compile-query "unknown condition operator" (car expr))]))

  (define (string-join strs sep)
    (if (null? strs)
        ""
        (let loop ([rest (cdr strs)] [acc (car strs)])
          (if (null? rest)
              acc
              (loop (cdr rest) (string-append acc sep (car rest)))))))

  ;; ========== Query Compilation ==========

  (define (compile-query q)
    (unless (query? q)
      (error 'compile-query "not a query" q))
    ;; Reset parameter accumulator
    (set! *params* '())
    (let* ([table    (query-table q)]
           [cols     (query-columns q)]
           [whr-cond (query-cond q)]
           [lim      (query-limit q)]
           [off      (query-offset q)]
           [ord      (query-order q)]
           ;; SELECT clause
           [sel-str  (if (or (eq? cols '*) (equal? cols '(*)))
                         "*"
                         (string-join
                           (map (lambda (c)
                                  (if (symbol? c) (symbol->string c)
                                      (if (string? c) c (format #f "~a" c))))
                                (if (list? cols) cols (list cols)))
                           ", "))]
           ;; FROM clause
           [from-str (string-append "SELECT " sel-str " FROM " table)]
           ;; WHERE clause
           [where-str (if whr-cond
                          (string-append " WHERE " (compile-cond whr-cond))
                          "")]
           ;; ORDER BY clause
           [order-str (if (null? ord)
                          ""
                          (string-append
                            " ORDER BY "
                            (string-join
                              (map (lambda (pair)
                                     (string-append
                                       (col->sql (car pair))
                                       (if (eq? (cdr pair) 'desc) " DESC" " ASC")))
                                   ord)
                              ", ")))]
           ;; LIMIT clause
           [limit-str  (if lim  (string-append " LIMIT "  (number->string lim))  "")]
           ;; OFFSET clause
           [offset-str (if off  (string-append " OFFSET " (number->string off)) "")]
           [sql (string-append from-str where-str order-str limit-str offset-str)]
           [params *params*])
      (set! *params* '())
      (cons sql params)))

  (define (query->string q)
    (car (compile-query q)))

  ;; ========== Macro ==========

  (define-syntax define-query
    (syntax-rules (from where select limit offset order-by)
      [(_ name (from table) clause ...)
       (define name
         (apply-query-clauses (make-query table) (list clause ...)))]))

  ;; Helper for define-query — apply a list of transformer lambdas
  (define (apply-query-clauses q clauses)
    (let loop ([q q] [cs clauses])
      (if (null? cs)
          q
          (loop ((car cs) q) (cdr cs)))))

) ;; end library
