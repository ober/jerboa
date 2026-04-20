#!chezscheme
;;; :std/sugar -- Gerbil sugar forms

(library (std sugar)
  (export
    ;; Re-exported from (jerboa core):
    try catch finally
    unwind-protect
    chain chain-and with-id
    assert!
    with-lock
    with-catch
    cut cute <> <...>
    ;; Anaphoric macros
    awhen aif
    ;; Binding macros
    when-let if-let
    ;; Clojure-style threading
    -> ->> as-> some-> some->> cond-> cond->>
    ;; Result-aware threading
    ->? ->>?
    ;; Resource management
    with-resource
    ;; String builder
    str
    ;; Alist constructor
    alist
    ;; Guarded definitions
    defn
    ;; Record shorthand
    defrecord
    ;; Alist destructuring
    let-alist
    ;; Enum definitions
    define-enum
    ;; Output capture
    capture
    ;; Iteration
    dotimes
    ;; Multiple value binding (re-export from Chez)
    define-values)
  (import (except (chezscheme)
            make-hash-table hash-table? iota 1+ 1- getenv
            path-extension path-absolute?
            thread? make-mutex mutex? mutex-name)
          (jerboa core)
          (std result))

  ;; chain: thread a value through a series of expressions
  ;; (chain val (f _ arg) (g arg _)) → (g arg (f val arg))
  (define-syntax chain
    (lambda (stx)
      (syntax-case stx ()
        [(_ val) #'val]
        [(_ val (f args ...) rest ...)
         #'(chain (chain-apply f val args ...) rest ...)]
        [(_ val f rest ...)
         (identifier? #'f)
         #'(chain (f val) rest ...)])))

  (define-syntax chain-apply
    (lambda (stx)
      (syntax-case stx ()
        [(_ f val) #'(f val)]
        [(_ f val placeholder arg ...)
         (and (identifier? #'placeholder) (eq? (syntax->datum #'placeholder) '_))
         #'(f val arg ...)]
        [(_ f val arg1 rest ...)
         #'(chain-apply-tail f val (arg1) rest ...)])))

  (define-syntax chain-apply-tail
    (lambda (stx)
      (syntax-case stx ()
        [(_ f val (args ...) placeholder)
         (and (identifier? #'placeholder) (eq? (syntax->datum #'placeholder) '_))
         #'(f args ... val)]
        [(_ f val (args ...) placeholder rest ...)
         (and (identifier? #'placeholder) (eq? (syntax->datum #'placeholder) '_))
         #'(chain-apply-tail f val (args ... val) rest ...)]
        [(_ f val (args ...) arg rest ...)
         #'(chain-apply-tail f val (args ... arg) rest ...)]
        [(_ f val (args ...)) #'(f args ...)])))

  ;; chain-and: like chain but short-circuits on #f
  (define-syntax chain-and
    (syntax-rules ()
      [(_ val) val]
      [(_ val step rest ...)
       (let ([v val])
         (and v (chain-and (chain v step) rest ...)))]))

  ;; with-id: generate identifiers from a name
  (define-syntax with-id
    (lambda (stx)
      (syntax-case stx ()
        [(_ name ((var fmt) ...) body ...)
         (with-syntax ([(gen ...) (map (lambda (f)
                                         (datum->syntax #'name
                                           (string->symbol
                                             (format (syntax->datum f)
                                                     (syntax->datum #'name)))))
                                       (syntax->list #'(fmt ...)))])
           #'(let-syntax ([helper
                           (lambda (stx2)
                             (syntax-case stx2 ()
                               [(_)
                                (with-syntax ([var (datum->syntax #'name 'gen)] ...)
                                  #'(begin body ...))]))])
               (helper)))])))

  ;; assert!
  (define-syntax assert!
    (syntax-rules ()
      [(_ expr)
       (unless expr
         (error 'assert! "assertion failed" 'expr))]
      [(_ expr message)
       (unless expr
         (error 'assert! message 'expr))]))

  ;; unwind-protect — like Java's try/finally, guarantee cleanup runs
  (define-syntax unwind-protect
    (syntax-rules ()
      [(_ body cleanup ...)
       (dynamic-wind
         (lambda () (void))
         (lambda () body)
         (lambda () cleanup ...))]))

  ;; with-lock — acquire Chez mutex, run body, release even on exception
  (define-syntax with-lock
    (syntax-rules ()
      [(_ mutex-expr body body* ...)
       (let ([m mutex-expr])
         (dynamic-wind
           (lambda () (mutex-acquire m))
           (lambda () body body* ...)
           (lambda () (mutex-release m))))]))

  ;; with-catch — Gerbil's 2-arg exception handler shorthand
  ;; (with-catch handler thunk)
  ;; handler: (lambda (exn) fallback-value)
  ;; thunk:   (lambda () guarded-expression)
  ;; with-catch — Gerbil exception handler shorthand.
  ;; %apply1 indirection prevents Chez arity-check warnings on (handler e).
  (define (%apply1 f x) (apply f (list x)))
  (define (with-catch handler thunk)
    (call-with-current-continuation
      (lambda (k)
        (with-exception-handler
          (lambda (e) (k (%apply1 handler e)))
          thunk))))

  ;; Auxiliary syntax for cut/cute slot markers (must be exported for cross-module use)
  (define-syntax <> (lambda (x) (syntax-violation '<> "misuse of auxiliary syntax" x)))
  (define-syntax <...> (lambda (x) (syntax-violation '<...> "misuse of auxiliary syntax" x)))

  ;; cut / cute — SRFI-26 partial application
  ;; (cut f <> y) → (lambda (x) (f x y))
  ;; (cute f <> y) → (let ([t y]) (lambda (x) (f x t)))

  (define-syntax cut
    (syntax-rules ()
      [(_ . slots-or-exprs)
       (cut-aux () () . slots-or-exprs)]))

  (define-syntax cute
    (syntax-rules ()
      [(_ . slots-or-exprs)
       (cute-aux () () () . slots-or-exprs)]))

  (define-syntax cut-aux
    (syntax-rules (<> <...>)
      ;; No more args — build lambda
      [(_ (params ...) (args ...))
       (lambda (params ...) (args ...))]
      ;; Slot <> — add parameter
      [(_ (params ...) (args ...) <> . rest)
       (cut-aux (params ... x) (args ... x) . rest)]
      ;; Rest slot <...> — must be last
      [(_ (params ...) (args ...) <...>)
       (lambda (params ... . xs) (apply args ... xs))]
      ;; Normal expression — pass through
      [(_ (params ...) (args ...) expr . rest)
       (cut-aux (params ...) (args ... expr) . rest)]))

  (define-syntax cute-aux
    (syntax-rules (<> <...>)
      ;; No more args — build let + lambda
      [(_ (binds ...) (params ...) (args ...))
       (let (binds ...) (lambda (params ...) (args ...)))]
      ;; Slot <>
      [(_ (binds ...) (params ...) (args ...) <> . rest)
       (cute-aux (binds ...) (params ... x) (args ... x) . rest)]
      ;; Rest slot <...>
      [(_ (binds ...) (params ...) (args ...) <...>)
       (let (binds ...) (lambda (params ... . xs) (apply args ... xs)))]
      ;; Normal expression — evaluate once via let
      [(_ (binds ...) (params ...) (args ...) expr . rest)
       (cute-aux (binds ... (t expr)) (params ...) (args ... t) . rest)]))

  ;; awhen — anaphoric when: binds test result to `it`
  ;; (awhen (find-thing) (use it)) → (let ((it (find-thing))) (when it (use it)))
  (define-syntax awhen
    (lambda (stx)
      (syntax-case stx ()
        [(k test body body* ...)
         (with-syntax ([it (datum->syntax #'k 'it)])
           #'(let ([it test])
               (when it body body* ...)))])))

  ;; aif — anaphoric if: binds test result to `it`
  ;; (aif (lookup key) (use it) fallback)
  (define-syntax aif
    (lambda (stx)
      (syntax-case stx ()
        [(k test then else-expr)
         (with-syntax ([it (datum->syntax #'k 'it)])
           #'(let ([it test])
               (if it then else-expr)))]
        [(k test then)
         (with-syntax ([it (datum->syntax #'k 'it)])
           #'(let ([it test])
               (when it then)))])))

  ;; when-let — bind and test: execute body only if binding is truthy
  ;; (when-let (x (get-thing)) (use x))
  (define-syntax when-let
    (syntax-rules ()
      [(_ (var expr) body body* ...)
       (let ([var expr])
         (when var body body* ...))]))

  ;; if-let — bind and branch: execute then if binding is truthy, else otherwise
  ;; (if-let (x (get-thing)) (use x) fallback)
  (define-syntax if-let
    (syntax-rules ()
      [(_ (var expr) then else-expr)
       (let ([var expr])
         (if var then else-expr))]))

  ;; dotimes — iterate N times with counter variable
  ;; (dotimes (i 10) (display i))
  (define-syntax dotimes
    (syntax-rules ()
      [(_ (var count) body body* ...)
       (let ([n count])
         (let loop ([var 0])
           (when (< var n)
             body body* ...
             (loop (+ var 1)))))]))

  ;; define-values — re-exported from Chez (already built-in)
  ;; (define-values (a b c) (values 1 2 3))

  ;; --- Clojure-style threading macros ---

  ;; -> : thread as first argument
  ;; (-> x (f a b) (g c)) => (g (f x a b) c)
  (define-syntax ->
    (syntax-rules ()
      [(_ val) val]
      [(_ val (f args ...) rest ...)
       (-> (f val args ...) rest ...)]
      [(_ val f rest ...)
       (-> (f val) rest ...)]))

  ;; ->> : thread as last argument
  ;; (->> x (f a b) (g c)) => (g c (f a b x))
  (define-syntax ->>
    (syntax-rules ()
      [(_ val) val]
      [(_ val (f args ...) rest ...)
       (->> (f args ... val) rest ...)]
      [(_ val f rest ...)
       (->> (f val) rest ...)]))

  ;; as-> : thread with named binding (like chain but with explicit name)
  ;; (as-> 1 x (+ x 10) (* x 2)) => 22
  (define-syntax as->
    (syntax-rules ()
      [(_ val name) val]
      [(_ val name form rest ...)
       (as-> (let ([name val]) form) name rest ...)]))

  ;; some-> : thread as first arg, short-circuit on #f
  ;; (some-> x (f a) (g b)) => #f if x or (f x a) is #f
  (define-syntax some->
    (syntax-rules ()
      [(_ val) val]
      [(_ val form rest ...)
       (let ([v val])
         (if v (some-> (-> v form) rest ...) #f))]))

  ;; some->> : thread as last arg, short-circuit on #f
  (define-syntax some->>
    (syntax-rules ()
      [(_ val) val]
      [(_ val form rest ...)
       (let ([v val])
         (if v (some->> (->> v form) rest ...) #f))]))

  ;; cond-> : conditionally thread as first argument
  ;; (cond-> val test1 (f a) test2 (g b))
  ;; => threads through (f ... a) only if test1 is true, etc.
  (define-syntax cond->
    (syntax-rules ()
      [(_ val) val]
      [(_ val test form rest ...)
       (let ([v val])
         (cond-> (if test (-> v form) v) rest ...))]))

  ;; cond->> : conditionally thread as last argument
  (define-syntax cond->>
    (syntax-rules ()
      [(_ val) val]
      [(_ val test form rest ...)
       (let ([v val])
         (cond->> (if test (->> v form) v) rest ...))]))

  ;; --- Result-aware threading macros ---

  ;; ->? : thread through ok values as first arg, short-circuit on err
  ;; (->? (ok 5) (+ 1) (* 2)) => (ok 12)
  ;; (->? (err "bad") (+ 1)) => (err "bad")
  (define-syntax ->?
    (syntax-rules ()
      [(_ val) val]
      [(_ val (f args ...) rest ...)
       (let ([v val])
         (if (err? v)
           v
           (->? (ok (f (unwrap v) args ...)) rest ...)))]
      [(_ val f rest ...)
       (->? val (f) rest ...)]))

  ;; ->>? : thread through ok values as last arg, short-circuit on err
  (define-syntax ->>?
    (syntax-rules ()
      [(_ val) val]
      [(_ val (f args ...) rest ...)
       (let ([v val])
         (if (err? v)
           v
           (->>? (ok (f args ... (unwrap v))) rest ...)))]
      [(_ val f rest ...)
       (->>? val (f) rest ...)]))

  ;; --- Resource management ---

  ;; with-resource: automatic open/close lifecycle
  ;; (with-resource (p (open-input-file "foo.txt") close-input-port) (read p))
  (define-syntax with-resource
    (syntax-rules ()
      [(_ (var init cleanup) body body* ...)
       (let ([var init])
         (dynamic-wind
           (lambda () (void))
           (lambda () body body* ...)
           (lambda () (cleanup var))))]))

  ;; --- String builder ---

  ;; str: concatenate args, auto-coercing to strings.
  ;; (str "hello " 42 " world") => "hello 42 world"
  ;; (str) => ""
  ;;
  ;; For each argument the macro emits one of three forms:
  ;;   - string literal    → the literal itself (no call)
  ;;   - number/char/symbol/boolean literal
  ;;                       → the pre-converted string literal (expand-time
  ;;                         constant fold; no runtime allocation)
  ;;   - any other expression → (->string e) fallback
  ;; cp0 then folds the resulting string-append over adjacent literals.
  (define-syntax str
    (lambda (stx)
      (define (lit->string d)
        (cond
          [(string? d) d]
          [(number? d) (number->string d)]
          [(char? d)   (string d)]
          [(boolean? d) (if d "#t" "#f")]
          [(and (pair? d) (eq? (car d) 'quote) (symbol? (cadr d)))
           (symbol->string (cadr d))]
          [else #f]))
      (define (coerce-arg ctx arg-stx)
        (let ([lit (lit->string (syntax->datum arg-stx))])
          (if lit
            (datum->syntax ctx lit)
            #`(->string #,arg-stx))))
      (syntax-case stx ()
        [(_) #'""]
        [(k arg args ...)
         (with-syntax ([(e ...) (map (lambda (a) (coerce-arg #'k a))
                                     (syntax->list #'(arg args ...)))])
           #'(string-append e ...))])))

  (define (->string x)
    (cond
      [(string? x) x]
      [(fixnum? x) (number->string x)]
      [(number? x) (number->string x)]
      [(symbol? x) (symbol->string x)]
      [(char? x) (string x)]
      [(boolean? x) (if x "#t" "#f")]
      [else (format "~a" x)]))

  ;; --- Alist constructor ---

  ;; alist: shorthand for building association lists
  ;; (alist (name "Alice") (age 30)) => ((name . "Alice") (age . 30))
  (define-syntax alist
    (syntax-rules ()
      [(_ (key val) ...)
       (list (cons 'key val) ...)]))

  ;; --- Guarded definitions ---

  ;; defn: define with inline type guards
  ;; (defn (add [x number?] [y number?]) (+ x y))
  ;; Expands to: (define (add x y) (unless (number? x) (error ...)) (unless (number? y) (error ...)) (+ x y))
  (define-syntax defn
    (syntax-rules ()
      [(_ (name [var pred] ...) body body* ...)
       (define (name var ...)
         (unless (pred var)
           (error 'name (format "~a failed guard ~a, got ~s" 'var 'pred var))) ...
         body body* ...)]))

  ;; --- Record shorthand ---

  ;; defrecord: define a record type with auto-generated accessors and printer
  ;; (defrecord point (x y))
  ;; Generates:
  ;;   - make-point constructor
  ;;   - point? predicate
  ;;   - point-x, point-y accessors
  ;;   - (point->alist p) => ((x . val) (y . val))
  ;;   - record-writer for readable printing
  ;; defrecord delegates to defrecord-base (syntax-rules for clean record def)
  ;; then defrecord-extras (syntax-case for generated names)
  (define-syntax defrecord
    (syntax-rules ()
      [(_ name (field ...))
       (begin
         (define-record-type name
           (sealed #t)
           (fields field ...))
         (defrecord-extras name (field ...)))]))

  (define-syntax defrecord-extras
    (lambda (stx)
      (define (make-id ctx fmt . args)
        (datum->syntax ctx
          (string->symbol (apply format fmt args))))
      (syntax-case stx ()
        [(_ name (field ...))
         (let* ([name-str (symbol->string (syntax->datum #'name))]
                [fields (syntax->list #'(field ...))])
           (with-syntax
             ([alist-name (make-id #'name "~a->alist" name-str)]
              [(accessor ...)
               (map (lambda (f)
                      (make-id #'name "~a-~a" name-str
                               (symbol->string (syntax->datum f))))
                    fields)]
              [name-string (datum->syntax #'name name-str)])
             #'(begin
                 (define (alist-name r)
                   (list (cons 'field (accessor r)) ...))
                 (record-writer (record-type-descriptor name)
                   (lambda (r port writer)
                     (display "#<" port)
                     (display name-string port)
                     (begin
                       (display " " port)
                       (display 'field port)
                       (display "=" port)
                       (writer (accessor r) port)) ...
                     (display ">" port)))
                 )))])))  ;; close: begin, with-syntax, let*, branch, syntax-case, lambda, define-syntax

  ;; --- Alist destructuring ---

  ;; let-alist: destructure an alist into bindings
  ;; (let-alist expr ([name n] [age a]) body ...)
  ;;   binds n to (cdr (assq 'name expr)), a to (cdr (assq 'age expr))
  ;; (let-alist expr (name age) body ...)
  ;;   binds name and age directly from alist keys
  (define-syntax let-alist
    (syntax-rules ()
      ;; Named bindings: [key var]
      [(_ alist-expr ([key var] ...) body body* ...)
       (let ([al alist-expr])
         (let ([var (cdr (assq 'key al))] ...)
           body body* ...))]
      ;; Short form: use field names as variable names
      [(_ alist-expr (key ...) body body* ...)
       (let ([al alist-expr])
         (let ([key (cdr (assq 'key al))] ...)
           body body* ...))]))

  ;; --- Enum definitions ---

  ;; define-enum: define a set of named integer constants with lookups
  ;; (define-enum color (red green blue))
  ;; Generates:
  ;;   - color-red => 0, color-green => 1, color-blue => 2
  ;;   - color? predicate (checks if value is valid)
  ;;   - color->name: value => symbol
  ;;   - name->color: symbol => value
  (define-syntax define-enum
    (lambda (stx)
      (syntax-case stx ()
        [(_ name (val ...))
         (let* ([name-str (symbol->string (syntax->datum #'name))]
                [vals (map syntax->datum (syntax->list #'(val ...)))]
                [n (length vals)]
                [mk-id (lambda (fmt)
                          (datum->syntax #'name
                            (string->symbol (format fmt name-str))))]
                [const-ids (map (lambda (v)
                                  (datum->syntax #'name
                                    (string->symbol
                                      (format "~a-~a" name-str (symbol->string v)))))
                                vals)]
                [indices (let loop ([i 0] [acc '()])
                           (if (= i n) (reverse acc)
                             (loop (+ i 1) (cons i acc))))])
           (with-syntax ([pred (mk-id "~a?")]
                         [to-name (mk-id "~a->name")]
                         [from-name (mk-id "name->~a")]
                         [(const-id ...) const-ids]
                         [(idx ...) (map (lambda (i) (datum->syntax #'name i)) indices)]
                         [(val-sym ...) (map (lambda (v) (datum->syntax #'name `(quote ,v))) vals)]
                         [max-val (datum->syntax #'name (- n 1))])
             #'(begin
                 (define const-id idx) ...
                 (define (pred v) (and (integer? v) (>= v 0) (<= v max-val)))
                 (define to-name
                   (let ([names (vector val-sym ...)])
                     (lambda (v)
                       (if (pred v) (vector-ref names v)
                         (error 'to-name "invalid enum value" v)))))
                 (define from-name
                   (let ([pairs (list (cons val-sym idx) ...)])
                     (lambda (sym)
                       (cond
                         [(assq sym pairs) => cdr]
                         [else (error 'from-name "unknown enum name" sym)])))))))])))

  ;; --- Output capture ---

  ;; capture: capture stdout output as a string
  ;; (capture (display "hello") (display " world")) => "hello world"
  (define-syntax capture
    (syntax-rules ()
      [(_ body body* ...)
       (let ([p (open-output-string)])
         (parameterize ([current-output-port p])
           body body* ...)
         (get-output-string p))]))

  ) ;; end library
