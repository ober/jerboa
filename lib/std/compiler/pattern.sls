#!r6rs
;;; Pattern Language Support for cp0 Optimization Passes
;;; 
;;; Advanced pattern matching for compile-time code transformation

(library (std compiler pattern)
  (export
    ;; Core pattern matching
    pattern-match*
    pattern-compile
    pattern-match-lambda
    
    ;; Pattern combinators
    pattern-and
    pattern-or
    pattern-not
    pattern-when
    pattern-unless
    
    ;; Advanced patterns
    pattern-ellipsis
    pattern-optional
    pattern-repeat
    
    ;; Guards and predicates
    pattern-guard*
    pattern-type-guard
    
    ;; Template generation
    template-substitute*
    template-compile
    
    ;; Pattern variables
    make-pattern-var
    pattern-var-name
    pattern-var-constraint)
  
  (import
    (rnrs)
    (std misc list)
    (std typed)
    (only (chezscheme) printf))

  ;; Enhanced pattern variable with constraints
  (defstruct pattern-var
    (name : symbol)
    (constraint : (or procedure #f)))

  ;; Pattern matching result
  (defstruct match-result
    (success : boolean)
    (bindings : list)
    (consumed : fixnum))

  ;; Core pattern matcher with support for complex patterns
  (define (pattern-match* pattern expr #:optional (env '()))
    "Advanced pattern matcher with environment support"
    (let ([result (match-pattern pattern expr env)])
      (if (match-result-success result)
        (match-result-bindings result)
        #f)))

  ;; Internal pattern matching engine
  (define (match-pattern pattern expr env)
    "Internal pattern matching with detailed results"
    (cond
      ;; Pattern variables
      [(pattern-var? pattern)
       (let ([constraint (pattern-var-constraint pattern)])
         (if (and constraint (not (constraint expr)))
           (make-match-result #f '() 0)
           (make-match-result #t 
             (list (cons (pattern-var-name pattern) expr)) 1)))]
      
      ;; Wildcard pattern
      [(eq? pattern '_)
       (make-match-result #t '() 1)]
      
      ;; Literal patterns
      [(or (number? pattern) (string? pattern) (boolean? pattern))
       (make-match-result (equal? pattern expr) '() 1)]
      
      ;; Symbol patterns
      [(symbol? pattern)
       (cond
         ;; Check for special pattern syntax
         [(pattern-variable-syntax? pattern)
          (match-pattern-variable pattern expr env)]
         ;; Regular symbol match
         [else (make-match-result (eq? pattern expr) '() 1)])]
      
      ;; List patterns
      [(pair? pattern)
       (match-list-pattern pattern expr env)]
      
      ;; Null pattern
      [(null? pattern)
       (make-match-result (null? expr) '() 0)]
      
      ;; Default
      [else (make-match-result (equal? pattern expr) '() 1)]))

  ;; List pattern matching with ellipsis support
  (define (match-list-pattern pattern expr env)
    "Match list patterns with ellipsis and repetition"
    (cond
      [(not (pair? expr))
       (make-match-result #f '() 0)]
      
      ;; Check for ellipsis patterns
      [(and (>= (length pattern) 2)
            (eq? (cadr pattern) '...))
       (match-ellipsis-pattern pattern expr env)]
      
      ;; Regular list matching
      [else
       (let loop ([pat-rest pattern] [exp-rest expr] [bindings '()] [consumed 0])
         (cond
           [(and (null? pat-rest) (null? exp-rest))
            (make-match-result #t bindings consumed)]
           [(or (null? pat-rest) (null? exp-rest))
            (make-match-result #f '() consumed)]
           [else
            (let ([head-result (match-pattern (car pat-rest) (car exp-rest) env)])
              (if (match-result-success head-result)
                (loop (cdr pat-rest) (cdr exp-rest)
                      (append bindings (match-result-bindings head-result))
                      (+ consumed (match-result-consumed head-result)))
                (make-match-result #f '() consumed)))]))]))

  ;; Ellipsis pattern matching
  (define (match-ellipsis-pattern pattern expr env)
    "Match patterns with ellipsis repetition"
    (let ([base-pattern (car pattern)]
          [rest-pattern (cddr pattern)])  ; skip the '...'
      (let loop ([exp-rest expr] [all-bindings '()] [matches 0])
        (let ([match-result (match-pattern base-pattern exp-rest env)])
          (cond
            ;; No more matches, try to match the rest
            [(not (match-result-success match-result))
             (let ([rest-result (match-list-pattern rest-pattern exp-rest env)])
               (if (match-result-success rest-result)
                 (make-match-result #t 
                   (merge-ellipsis-bindings all-bindings 
                     (match-result-bindings rest-result))
                   (+ matches (match-result-consumed rest-result)))
                 (make-match-result #f '() matches)))]
            
            ;; Match found, continue
            [else
             (loop (cdr exp-rest)
                   (merge-ellipsis-bindings all-bindings 
                     (match-result-bindings match-result))
                   (+ matches 1))])))))

  ;; Pattern variable syntax detection
  (define (pattern-variable-syntax? sym)
    "Check if symbol uses pattern variable syntax"
    (and (symbol? sym)
         (let ([str (symbol->string sym)])
           (and (> (string-length str) 1)
                (char=? (string-ref str 0) #\?)))))

  ;; Match pattern variable syntax
  (define (match-pattern-variable pattern expr env)
    "Match a pattern variable with optional constraints"
    (let* ([str (symbol->string pattern)]
           [var-name (string->symbol (substring str 1))]
           [constraint (lookup-constraint var-name env)])
      (if (and constraint (not (constraint expr)))
        (make-match-result #f '() 0)
        (make-match-result #t (list (cons var-name expr)) 1))))

  ;; Constraint lookup in environment
  (define (lookup-constraint name env)
    "Look up constraint for a pattern variable"
    (let ([entry (assq name env)])
      (if entry (cdr entry) #f)))

  ;; Merge bindings from ellipsis matching
  (define (merge-ellipsis-bindings bindings1 bindings2)
    "Merge bindings, handling ellipsis repetitions"
    (append bindings1 bindings2))  ; Simplified for now

  ;; Compiled pattern matcher
  (define (pattern-compile pattern #:optional (optimize? #t))
    "Compile pattern into optimized matcher function"
    (lambda (expr)
      (pattern-match* pattern expr)))

  ;; Pattern matching lambda
  (define-syntax pattern-match-lambda
    (syntax-rules ()
      [(_ ([pattern body] ...))
       (lambda (expr)
         (cond
           [(pattern-match* 'pattern expr) => (lambda (bindings) body)]
           ...
           [else #f]))]))

  ;; Pattern combinators
  
  (define (pattern-and . patterns)
    "Create a pattern that matches all sub-patterns"
    (lambda (expr)
      (let loop ([pats patterns] [all-bindings '()])
        (cond
          [(null? pats) all-bindings]
          [else
           (let ([result (pattern-match* (car pats) expr)])
             (if result
               (loop (cdr pats) (append all-bindings result))
               #f))]))))

  (define (pattern-or . patterns)
    "Create a pattern that matches any sub-pattern"
    (lambda (expr)
      (let loop ([pats patterns])
        (cond
          [(null? pats) #f]
          [else
           (let ([result (pattern-match* (car pats) expr)])
             (if result
               result
               (loop (cdr pats))))]))))

  (define (pattern-not pattern)
    "Create a pattern that matches when sub-pattern doesn't"
    (lambda (expr)
      (if (pattern-match* pattern expr) #f '())))

  (define (pattern-when pattern pred)
    "Create a conditional pattern"
    (lambda (expr)
      (let ([result (pattern-match* pattern expr)])
        (if (and result (pred expr))
          result
          #f))))

  (define (pattern-unless pattern pred)
    "Create a negative conditional pattern"
    (lambda (expr)
      (let ([result (pattern-match* pattern expr)])
        (if (and result (not (pred expr)))
          result
          #f))))

  ;; Advanced pattern types
  
  (define (pattern-ellipsis pattern)
    "Create an ellipsis pattern for repetition"
    (list pattern '...))

  (define (pattern-optional pattern)
    "Create an optional pattern"
    (lambda (expr)
      (let ([result (pattern-match* pattern expr)])
        (if result result '()))))

  (define (pattern-repeat pattern min max)
    "Create a repeat pattern with bounds"
    (lambda (expr)
      (if (and (pair? expr) (<= min (length expr) max))
        (let loop ([rest expr] [bindings '()] [count 0])
          (cond
            [(null? rest) 
             (if (>= count min) bindings #f)]
            [(let ([result (pattern-match* pattern (car rest))])
               (if result
                 (loop (cdr rest) (append bindings result) (+ count 1))
                 (if (>= count min) bindings #f)))])
        #f)))

  ;; Enhanced guards
  
  (define (pattern-guard* pred)
    "Create a pattern guard with better error reporting"
    (lambda (expr)
      (if (pred expr)
        '()  ; Empty bindings for guard-only patterns
        #f)))

  (define (pattern-type-guard type)
    "Create a type-checking guard"
    (case type
      [(number) (pattern-guard* number?)]
      [(string) (pattern-guard* string?)]
      [(symbol) (pattern-guard* symbol?)]
      [(list) (pattern-guard* list?)]
      [(pair) (pattern-guard* pair?)]
      [(null) (pattern-guard* null?)]
      [(boolean) (pattern-guard* boolean?)]
      [else (error 'pattern-type-guard "Unknown type" type)]))

  ;; Template substitution
  
  (define (template-substitute* template bindings)
    "Enhanced template substitution with error checking"
    (cond
      [(symbol? template)
       (let ([binding (assq template bindings)])
         (if binding
           (cdr binding)
           (if (pattern-variable-syntax? template)
             (error 'template-substitute* "Unbound pattern variable" template)
             template)))]
      [(pair? template)
       (cons (template-substitute* (car template) bindings)
             (template-substitute* (cdr template) bindings))]
      [else template]))

  (define (template-compile template)
    "Compile template into substitution function"
    (lambda (bindings)
      (template-substitute* template bindings))))