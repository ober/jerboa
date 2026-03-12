#!r6rs
;;; User-Defined cp0 Optimization Passes
;;; 
;;; Expose Chez Scheme's cp0 optimizer as a library, letting users write
;;; custom optimization passes that run during compilation.

(library (std compiler passes)
  (export
    ;; Core pass definition
    define-cp0-pass
    make-cp0-pass
    cp0-pass?
    cp0-pass-name
    cp0-pass-description
    cp0-pass-transformer
    cp0-pass-priority
    cp0-pass-enabled
    cp0-pass-name-set!
    cp0-pass-description-set!
    cp0-pass-transformer-set!
    cp0-pass-priority-set!
    cp0-pass-enabled-set!
    
    ;; Pass registration and management
    register-optimization-pass!
    unregister-optimization-pass!
    list-optimization-passes
    apply-optimization-passes
    
    ;; Pass composition
    compose-passes
    pass-priority
    
    ;; Debugging and introspection
    enable-pass-debug!
    disable-pass-debug!
    dump-ir-between-passes!
    pass-debug-enabled?
    
    ;; Built-in optimization passes
    pass:constant-fold
    pass:dead-code-eliminate
    pass:inline-small-functions
    pass:loop-unroll)
  
  (import
    (rnrs)
    (std match2)
    (std misc list)
    (std typed)
    (only (chezscheme) 
          compile-file compile-program compile-library
          current-eval optimize-level
          printf format))

  ;; Global registry of optimization passes
  (define *optimization-passes* '())
  (define *pass-debug-enabled* #f)
  (define *dump-ir* #f)
  
  ;; Pass record type
  (define-record-type cp0-pass
    (fields
      (mutable name)
      (mutable description)
      (mutable transformer) 
      (mutable priority)
      (mutable enabled))
    (protocol
      (lambda (new)
        (lambda (name description transformer priority enabled)
          (new name description transformer priority enabled)))))

  ;; Simplified macro for defining optimization passes
  (define-syntax define-cp0-pass
    (syntax-rules ()
      [(_ name description transformer)
       (define name
         (make-cp0-pass
           'name
           description
           transformer
           50  ; default priority
           #t))]
      
      [(_ name description transformer priority)
       (define name
         (make-cp0-pass
           'name
           description
           transformer
           priority
           #t))]))

  ;; Pass registration and management
  (define register-optimization-pass!
    (case-lambda
      [(pass) (register-optimization-pass! pass 50)]
      [(pass priority)
       "Register an optimization pass globally"
       (when (cp0-pass? pass)
         (when priority (cp0-pass-priority-set! pass priority))
         (set! *optimization-passes*
               (insert-sorted pass *optimization-passes* 
                 (lambda (p1 p2) 
                   (< (cp0-pass-priority p1) (cp0-pass-priority p2))))))
       #f]))

  (define (unregister-optimization-pass! pass-name)
    "Remove an optimization pass"
    (set! *optimization-passes*
          (filter (lambda (p) (not (eq? (cp0-pass-name p) pass-name)))
                  *optimization-passes*)))

  (define (list-optimization-passes)
    "List all registered passes with their priorities"
    (map (lambda (pass)
           (list (cp0-pass-name pass)
                 (cp0-pass-description pass)
                 (cp0-pass-priority pass)
                 (cp0-pass-enabled pass)))
         *optimization-passes*))

  ;; Pass composition
  (define (compose-passes . passes)
    "Compose multiple passes into a single pass"
    (lambda (expr)
      (let loop ([expr expr] [passes-left passes])
        (if (null? passes-left)
          expr
          (let* ([pass (car passes-left)]
                 [result ((cp0-pass-transformer pass) expr)])
            (loop (or result expr) (cdr passes-left)))))))

  (define (pass-priority pass)
    "Get the priority of a pass"
    (if (cp0-pass? pass)
      (cp0-pass-priority pass)
      0))

  ;; Debugging support
  (define (enable-pass-debug!)
    "Enable debugging output for pass execution"
    (set! *pass-debug-enabled* #t))

  (define (disable-pass-debug!)
    "Disable debugging output"
    (set! *pass-debug-enabled* #f))
    
  (define (pass-debug-enabled?)
    "Check if pass debugging is enabled"
    *pass-debug-enabled*)

  (define (dump-ir-between-passes! enable?)
    "Enable/disable dumping intermediate representations"
    (set! *dump-ir* enable?))

  (define (debug-print-pass pass expr result)
    "Print debug information about pass execution"
    (when *pass-debug-enabled*
      (printf "Pass: ~a~n" (cp0-pass-name pass))
      (printf "Input:  ~s~n" expr)
      (printf "Output: ~s~n" result)
      (printf "~n")))

  ;; Helper for sorted insertion
  (define (insert-sorted item lst cmp)
    "Insert item into sorted list maintaining order"
    (cond
      [(null? lst) (list item)]
      [(cmp item (car lst)) (cons item lst)]
      [else (cons (car lst) (insert-sorted item (cdr lst) cmp))]))

  ;; Apply all registered passes to an expression
  (define (apply-optimization-passes expr)
    "Apply all enabled optimization passes to expression"
    (fold-left (lambda (acc-expr pass)
                 (if (cp0-pass-enabled pass)
                   (let ([result ((cp0-pass-transformer pass) acc-expr)])
                     (when *pass-debug-enabled*
                       (debug-print-pass pass acc-expr result))
                     (or result acc-expr))
                   acc-expr))
               expr
               *optimization-passes*))

  ;; Built-in optimization passes using match2
  
  ;; Constant folding pass
  (define-cp0-pass pass:constant-fold
    "Fold constant expressions at compile time"
    (lambda (expr)
      (if (not (pair? expr))
        #f  ; Can't optimize non-list expressions  
        (match expr
          [(list '+ a b) 
           (if (and (number? a) (number? b)) (+ a b) #f)]
          [(list '- a b) 
           (if (and (number? a) (number? b)) (- a b) #f)]
          [(list '* a b) 
           (if (and (number? a) (number? b)) (* a b) #f)]
          [(list '/ a b) 
           (if (and (number? a) (number? b) (not (= b 0))) (/ a b) #f)]
          [(list '= a b) 
           (if (and (number? a) (number? b)) (= a b) #f)]
          [(list '< a b) 
           (if (and (number? a) (number? b)) (< a b) #f)]
          [(list 'string-append a b) 
           (if (and (string? a) (string? b)) (string-append a b) #f)]
          [(list 'string-length a) 
           (if (string? a) (string-length a) #f)]
          [_ #f])))
    10)

  ;; Dead code elimination pass  
  (define-cp0-pass pass:dead-code-eliminate
    "Remove unreachable code and unused bindings"
    (lambda (expr)
      (if (not (pair? expr))
        #f  ; Can't optimize non-list expressions
        (match expr
          [(list 'if #t then _) then]
          [(list 'if #f _ else) else]
          [(list 'when #f body) '(void)]
          [(list 'unless #t body) '(void)]
          [(list* 'and #f _) #f]
          [(list* 'or #t _) #t]
          [(list 'let (list (list var val)) body) 
           (if (not (occurs-in? var body)) body #f)]
          [_ #f])))
    20)

  ;; Small function inlining pass
  (define-cp0-pass pass:inline-small-functions
    "Inline functions with small bodies"
    (lambda (expr)
      (if (not (pair? expr))
        #f
        (match expr
          [(list 'let (list (list f (list 'lambda params body))) (list* f args))
           (if (< (expression-size body) 10)
             (substitute-parameters body params args)
             #f)]
          [_ #f])))
    30)

  ;; Loop unrolling pass
  (define-cp0-pass pass:loop-unroll
    "Unroll small loops with known iteration counts"
    (lambda (expr)
      (if (not (pair? expr))
        #f
        (match expr
          [(list 'let name (list (list 'i 0) (list 'acc init))
                 (list 'if (list '< 'i n)
                       (list name (list '+ 'i 1) (list op 'acc 'i))
                       'acc))
           (if (and (number? n) (< n 4))
             (unroll-loop name init op n)
             #f)]
          [_ #f])))
    40)

  ;; Helper functions for built-in passes
  
  (define (occurs-in? var expr)
    "Check if variable occurs in expression"
    (cond
      [(symbol? expr) (eq? var expr)]
      [(pair? expr) 
       (or (occurs-in? var (car expr))
           (occurs-in? var (cdr expr)))]
      [else #f]))

  (define (expression-size expr)
    "Estimate the size of an expression"
    (cond
      [(pair? expr) (+ 1 (expression-size (car expr)) 
                       (expression-size (cdr expr)))]
      [else 1]))

  (define (substitute-parameters body params args)
    "Substitute parameters with arguments in body"
    (if (null? params)
      body
      (substitute-one (car params) (car args)
        (substitute-parameters body (cdr params) (cdr args)))))

  (define (substitute-one var val expr)
    "Substitute one variable with value in expression"
    (cond
      [(eq? expr var) val]
      [(pair? expr)
       (cons (substitute-one var val (car expr))
             (substitute-one var val (cdr expr)))]
      [else expr]))

  (define (unroll-loop loop-name init op n)
    "Generate unrolled loop body"
    (let loop ([i 0] [acc init])
      (if (< i n)
        (loop (+ i 1) `(,op ,acc ,i))
        acc)))

  ;; Register built-in passes
  (register-optimization-pass! pass:constant-fold 10)
  (register-optimization-pass! pass:dead-code-eliminate 20)  
  (register-optimization-pass! pass:inline-small-functions 30)
  (register-optimization-pass! pass:loop-unroll 40))