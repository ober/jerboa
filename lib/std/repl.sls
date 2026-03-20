#!chezscheme
;;; (std repl) -- World-class Interactive REPL
;;;
;;; Inspired by SLIME/SWANK for Common Lisp, this REPL provides:
;;;
;;; Value History:
;;;   *  ** ***          -- last 3 results (CL-style)
;;;   $1 $2 $3 ...      -- numbered result history
;;;
;;; Inspection & Exploration:
;;;   ,type expr         -- show type of expression result
;;;   ,describe expr     -- deep inspection of value (records, lists, hashes)
;;;   ,inspect expr      -- interactive inspector for complex values
;;;   ,apropos str       -- search for symbols matching string
;;;   ,doc sym           -- show documentation
;;;   ,complete prefix   -- show completions for a symbol prefix
;;;   ,who sym           -- find all bindings referencing a symbol
;;;
;;; Evaluation & Debugging:
;;;   ,expand expr       -- show macro expansion
;;;   ,expand1 expr      -- show one-step macro expansion
;;;   ,trace fn          -- enable tracing for a function
;;;   ,untrace fn        -- disable tracing
;;;   ,trace-all         -- show all traced functions
;;;   ,step expr         -- step through evaluation (display bindings)
;;;
;;; Performance:
;;;   ,time expr         -- measure evaluation time (CPU + real + GC)
;;;   ,bench expr [n]    -- benchmark with N iterations (default 100)
;;;   ,profile expr      -- profile with Chez's built-in profiler
;;;   ,alloc expr        -- show memory allocation for expression
;;;
;;; Module System:
;;;   ,import (mod ...)  -- import a module into the REPL environment
;;;   ,reload path       -- reload a file (clearing old bindings)
;;;   ,cd [path]         -- change/show current directory
;;;   ,pwd               -- show current directory
;;;   ,ls [path]         -- list directory contents
;;;   ,shell cmd         -- run a shell command
;;;
;;; Data Inspection:
;;;   ,pp expr           -- pretty-print value
;;;   ,table expr        -- display as aligned table (lists of alists/lists)
;;;   ,json expr         -- display value as JSON
;;;   ,csv expr          -- display value as CSV
;;;   ,head expr [n]     -- show first N items (default 10)
;;;   ,tail expr [n]     -- show last N items (default 10)
;;;   ,count expr        -- count items in collection
;;;   ,stats expr        -- column statistics for numeric lists
;;;   ,freq expr         -- frequency table for a list
;;;
;;; Session:
;;;   ,history [n]       -- show last N history entries
;;;   ,save path         -- save session history to file
;;;   ,load path         -- load and evaluate a file
;;;   ,clear             -- clear value history
;;;   ,reset             -- reset environment
;;;   ,set key val       -- set REPL option (prompt, color, time)
;;;   ,env [pattern]     -- list environment symbols, optionally filtered
;;;   ,help [cmd]        -- show help (detailed help for a command)
;;;   ,quit              -- exit REPL
;;;
;;; Usage:
;;;   (import (std repl))
;;;   (jerboa-repl)          ; start the enhanced REPL
;;;   (jerboa-repl config)   ; start with custom config

(library (std repl)
  (export
    ;; Main entry point
    jerboa-repl

    ;; Individual REPL commands (usable from code)
    repl-type repl-time repl-doc repl-apropos repl-expand
    repl-pp repl-load

    ;; REPL configuration
    make-repl-config repl-config?
    repl-config-prompt repl-config-history-size
    repl-config-show-time? repl-config-color?

    ;; Utilities
    value->type-string describe-value

    ;; Documentation registry
    register-doc!

    ;; Completion
    repl-complete

    ;; Value history access
    repl-history-ref)

  (import (except (chezscheme) cpu-time box?)
          (std misc list))

  ;;; ========== REPL Configuration ==========
  (define-record-type repl-config
    (fields (mutable prompt)        ; string: e.g. "jerboa> "
            (mutable history-size)  ; fixnum: max history entries
            (mutable show-time?)    ; boolean: auto-show timing
            (mutable color?))       ; boolean: ANSI colors
    (protocol (lambda (new)
      (lambda ()
        (new "jerboa> " 1000 #f #t)))))

  (define *default-config* (make-repl-config))

  ;;; ========== ANSI color codes ==========
  (define reset-color   "\x1b;[0m")
  (define bold          "\x1b;[1m")
  (define dim           "\x1b;[2m")
  (define italic        "\x1b;[3m")
  (define underline     "\x1b;[4m")
  (define red           "\x1b;[31m")
  (define green         "\x1b;[32m")
  (define yellow        "\x1b;[33m")
  (define blue          "\x1b;[34m")
  (define magenta       "\x1b;[35m")
  (define cyan          "\x1b;[36m")
  (define white         "\x1b;[37m")
  (define bright-black  "\x1b;[90m")

  (define (colored cfg color str)
    (if (repl-config-color? cfg)
      (string-append color str reset-color)
      str))

  (define (c-bold cfg str)
    (if (repl-config-color? cfg)
      (string-append bold str reset-color)
      str))

  (define (c-dim cfg str)
    (if (repl-config-color? cfg)
      (string-append bright-black str reset-color)
      str))

  ;;; ========== Value History ==========
  ;; CL-style: *, **, *** for last 3 results
  ;; Numbered: $1, $2, ... for all results

  (define *value-history* '())   ;; list of (index . value) newest first
  (define *history-counter* 0)
  (define *last-1* (void))  ;; *
  (define *last-2* (void))  ;; **
  (define *last-3* (void))  ;; ***

  (define (history-push! val)
    (set! *history-counter* (+ *history-counter* 1))
    (set! *value-history*
      (cons (cons *history-counter* val)
            (if (> (length *value-history*) 999)
              (take *value-history* 999)
              *value-history*)))
    ;; Shift CL-style history
    (set! *last-3* *last-2*)
    (set! *last-2* *last-1*)
    (set! *last-1* val)
    *history-counter*)

  (define (repl-history-ref n)
    (let ([entry (assv n *value-history*)])
      (if entry (cdr entry)
        (error 'repl-history-ref "no history entry" n))))

  (define (history-clear!)
    (set! *value-history* '())
    (set! *history-counter* 0)
    (set! *last-1* (void))
    (set! *last-2* (void))
    (set! *last-3* (void)))

  ;; Install history variables into environment
  (define (install-history-bindings! env)
    (eval '(define * (void)) env)
    (eval '(define ** (void)) env)
    (eval '(define *** (void)) env))

  (define (update-history-bindings! env)
    (eval `(set! * ',*last-1*) env)
    (eval `(set! ** ',*last-2*) env)
    (eval `(set! *** ',*last-3*) env))

  ;;; ========== Input History ==========
  (define *input-history* '())  ;; list of strings, newest first

  (define (input-history-push! str)
    (when (and (> (string-length str) 0)
               (or (null? *input-history*)
                   (not (string=? str (car *input-history*)))))
      (set! *input-history* (cons str *input-history*))
      (when (> (length *input-history*) 1000)
        (set! *input-history* (take *input-history* 1000)))))

  ;;; ========== Persistent History ==========
  (define (history-file-path)
    (let ([home (or (getenv "HOME") ".")])
      (string-append home "/.jerboa_history")))

  (define (save-history!)
    (guard (exn [#t (void)])  ;; silently fail
      (let ([path (history-file-path)])
        (call-with-output-file path
          (lambda (p)
            (for-each (lambda (line) (display line p) (newline p))
                      (reverse (take *input-history*
                                     (min 500 (length *input-history*))))))
          'replace))))

  (define (load-history!)
    (guard (exn [#t (void)])
      (let ([path (history-file-path)])
        (when (file-exists? path)
          (call-with-input-file path
            (lambda (p)
              (let loop ([lines '()])
                (let ([line (get-line p)])
                  (if (eof-object? line)
                    (set! *input-history* (reverse lines))
                    (loop (cons line lines)))))))))))

  ;;; ========== Traced Functions ==========
  (define *traced-fns* '())  ;; list of symbols

  ;;; ========== Type inference ==========
  (define (value->type-string v)
    (cond
      [(boolean? v)    "Boolean"]
      [(fixnum? v)     "Fixnum"]
      [(flonum? v)     "Flonum"]
      [(bignum? v)     "Bignum"]
      [(rational? v)   "Rational"]
      [(complex? v)    "Complex"]
      [(char? v)       "Char"]
      [(string? v)     (format "String[~a]" (string-length v))]
      [(symbol? v)     (if (keyword? v) "Keyword" "Symbol")]
      [(null? v)       "Null"]
      [(pair? v)
       (cond
         [(not (list? v)) "Pair"]
         [(and (> (length v) 0) (pair? (car v))
               (every pair? v))
          (format "AList[~a]" (length v))]
         [else (format "List[~a]" (length v))])]
      [(vector? v)     (format "Vector[~a]" (vector-length v))]
      [(bytevector? v) (format "Bytevector[~a]" (bytevector-length v))]
      [(port? v)
       (cond
         [(and (input-port? v) (output-port? v)) "InputOutputPort"]
         [(input-port? v) "InputPort"]
         [else "OutputPort"])]
      [(procedure? v)  "Procedure"]
      [(hashtable? v) (format "HashTable[~a]" (hashtable-size v))]
      [(void-object? v) "Void"]
      [(condition? v)
       (if (message-condition? v)
         (format "Condition(~a)" (condition-message v))
         "Condition")]
      [(eq? v #!eof)   "EOF"]
      [(box? v)        "Box"]
      [(fxvector? v)   (format "FxVector[~a]" (fxvector-length v))]
      [else
       (guard (exn [#t "Unknown"])
         (let ([rtd (record-rtd v)])
           (symbol->string (record-type-name rtd))))]))

  (define (keyword? v)
    (and (symbol? v)
         (let ([s (symbol->string v)])
           (and (> (string-length s) 0)
                (char=? (string-ref s 0) #\:)))))

  (define (void-object? v) (eq? v (void)))
  (define (box? v)
    (guard (exn [#t #f])
      (and (record? v) (eq? (record-type-name (record-rtd v)) 'box))))

  ;;; ========== Rich describe-value ==========
  (define (describe-value v . port-opt)
    (let ([port (if (pair? port-opt) (car port-opt) (current-output-port))])
      (display (value->type-string v) port)
      (display ": " port)
      (write v port)
      (newline port)))

  (define (deep-describe cfg v port)
    ;; Rich multi-line description of a value
    (display (colored cfg cyan (value->type-string v)) port)
    (newline port)
    (cond
      [(hashtable? v)
       (fprintf port "  size: ~a~n" (hashtable-size v))
       (let-values ([(keys vals) (hashtable-entries v)])
         (let ([n (vector-length keys)])
           (do ([i 0 (+ i 1)])
               ((or (= i n) (= i 20)))
             (fprintf port "  ~a: " (vector-ref keys i))
             (write (vector-ref vals i) port)
             (newline port))
           (when (> n 20)
             (fprintf port "  ... and ~a more entries~n" (- n 20)))))]
      [(and (list? v) (> (length v) 0))
       (fprintf port "  length: ~a~n" (length v))
       (let ([n (min 10 (length v))])
         (do ([i 0 (+ i 1)] [l v (cdr l)])
             ((= i n))
           (fprintf port "  [~a] " i)
           (let ([item (car l)])
             (if (> (string-length (format "~s" item)) 72)
               (begin (display (value->type-string item) port)
                      (display " ..." port))
               (write item port)))
           (newline port))
         (when (> (length v) 10)
           (fprintf port "  ... and ~a more items~n" (- (length v) 10))))]
      [(vector? v)
       (fprintf port "  length: ~a~n" (vector-length v))
       (let ([n (min 10 (vector-length v))])
         (do ([i 0 (+ i 1)])
             ((= i n))
           (fprintf port "  [~a] " i)
           (write (vector-ref v i) port)
           (newline port))
         (when (> (vector-length v) 10)
           (fprintf port "  ... and ~a more elements~n" (- (vector-length v) 10))))]
      [(string? v)
       (fprintf port "  length: ~a~n" (string-length v))
       (when (> (string-length v) 80)
         (fprintf port "  preview: ~a...~n" (substring v 0 77)))]
      [(bytevector? v)
       (fprintf port "  length: ~a bytes~n" (bytevector-length v))
       (let ([n (min 32 (bytevector-length v))])
         (display "  hex: " port)
         (do ([i 0 (+ i 1)])
             ((= i n))
           (let* ([b (bytevector-u8-ref v i)]
                  [s (number->string b 16)])
             (when (< b 16) (display "0" port))
             (display s port)
             (display " " port)))
         (when (> (bytevector-length v) 32)
           (display "..." port))
         (newline port))]
      [(procedure? v)
       (let ([info (guard (e [#t #f]) (#%$code-name (#%$closure-code v)))])
         (when info
           (fprintf port "  name: ~a~n" info)))]
      [(and (record? v) (not (condition? v)))
       (guard (exn [#t (void)])
         (let* ([rtd (record-rtd v)]
                [names (record-type-field-names rtd)]
                [n (vector-length names)])
           (fprintf port "  fields:~n")
           (do ([i 0 (+ i 1)])
               ((= i n))
             (fprintf port "    ~a: " (vector-ref names i))
             (write ((record-accessor rtd i) v) port)
             (newline port))
           (let ([parent (record-type-parent rtd)])
             (when parent
               (fprintf port "  parent: ~a~n" (record-type-name parent))))))]
      [(condition? v)
       (when (message-condition? v)
         (fprintf port "  message: ~a~n" (condition-message v)))
       (when (irritants-condition? v)
         (fprintf port "  irritants: ~s~n" (condition-irritants v)))]
      [(pair? v)
       (fprintf port "  car: ~s~n" (car v))
       (fprintf port "  cdr: ~s~n" (cdr v))]
      [else
       (display "  value: " port)
       (write v port)
       (newline port)]))

  ;;; ========== Table Display ==========
  (define (display-table cfg data port)
    ;; Display a list of lists as an aligned table
    ;; data: list of rows (each row is a list of values)
    (when (and (pair? data) (pair? (car data)))
      (let* ([rows (map (lambda (row)
                          (map (lambda (v) (format "~a" v)) row))
                        data)]
             [ncols (apply max (map length rows))]
             ;; Pad short rows
             [rows (map (lambda (row)
                          (let ([n (length row)])
                            (if (< n ncols)
                              (append row (make-list (- ncols n) ""))
                              row)))
                        rows)]
             ;; Compute column widths
             [widths (let loop ([col 0] [acc '()])
                       (if (= col ncols)
                         (reverse acc)
                         (loop (+ col 1)
                               (cons (apply max 1
                                       (map (lambda (row)
                                              (string-length (list-ref row col)))
                                            rows))
                                     acc))))])
        ;; Print header separator
        (let ([header (car rows)]
              [body (cdr rows)])
          ;; Print header
          (let loop ([h header] [w widths])
            (when (pair? h)
              (display (colored cfg bold (car h)) port)
              (display (make-string (max 0 (- (car w) (string-length (car h)))) #\space) port)
              (when (pair? (cdr h)) (display "  " port))
              (loop (cdr h) (cdr w))))
          (newline port)
          ;; Separator line
          (let loop ([w widths])
            (when (pair? w)
              (display (make-string (car w) #\-) port)
              (when (pair? (cdr w)) (display "  " port))
              (loop (cdr w))))
          (newline port)
          ;; Print body rows
          (for-each
            (lambda (row)
              (let loop ([r row] [w widths])
                (when (pair? r)
                  (display (car r) port)
                  (display (make-string (max 0 (- (car w) (string-length (car r)))) #\space) port)
                  (when (pair? (cdr r)) (display "  " port))
                  (loop (cdr r) (cdr w))))
              (newline port))
            body)))))

  ;; Convert various data shapes to table rows
  (define (value->table-rows v)
    (cond
      ;; List of alists: [{(name . "a") (age . 1)} ...]
      [(and (list? v) (pair? v) (pair? (car v))
            (every (lambda (x) (and (pair? x) (every pair? x))) v))
       (let* ([all-keys (unique (apply append (map (lambda (row) (map car row)) v)))]
              [header (map symbol->string all-keys)])
         (cons header
               (map (lambda (row)
                      (map (lambda (key)
                             (let ([pair (assq key row)])
                               (if pair (format "~a" (cdr pair)) "")))
                           all-keys))
                    v)))]
      ;; List of lists
      [(and (list? v) (pair? v) (every list? v))
       v]
      ;; Hash table
      [(hashtable? v)
       (let-values ([(keys vals) (hashtable-entries v)])
         (cons (list "key" "value")
               (let loop ([i 0] [acc '()])
                 (if (= i (vector-length keys))
                   (reverse acc)
                   (loop (+ i 1)
                         (cons (list (format "~a" (vector-ref keys i))
                                     (format "~a" (vector-ref vals i)))
                               acc))))))]
      [else #f]))

  ;;; ========== Frequency Table ==========
  (define (frequency-table lst)
    (let ([ht (make-hashtable equal-hash equal?)])
      (for-each (lambda (v)
                  (hashtable-update! ht v (lambda (c) (+ c 1)) 0))
                lst)
      (let-values ([(keys vals) (hashtable-entries ht)])
        (let ([pairs (let loop ([i 0] [acc '()])
                       (if (= i (vector-length keys))
                         acc
                         (loop (+ i 1)
                               (cons (cons (vector-ref keys i) (vector-ref vals i))
                                     acc))))])
          ;; Sort by count descending
          (sort (lambda (a b) (> (cdr a) (cdr b))) pairs)))))

  ;;; ========== Numeric Statistics ==========
  (define (list-stats lst)
    ;; Returns alist of statistics for a numeric list
    (if (or (null? lst) (not (every number? lst)))
      '()
      (let* ([sorted (sort < lst)]
             [n (length sorted)]
             [total (apply + sorted)]
             [mean (/ total n)]
             [lo (car sorted)]
             [hi (car (reverse sorted))]
             [median (if (odd? n)
                       (list-ref sorted (quotient n 2))
                       (/ (+ (list-ref sorted (- (quotient n 2) 1))
                             (list-ref sorted (quotient n 2)))
                          2))]
             [variance (/ (apply + (map (lambda (x) (expt (- x mean) 2)) sorted)) n)]
             [stddev (sqrt (inexact variance))])
        `((count . ,n)
          (mean  . ,(inexact mean))
          (std   . ,stddev)
          (min   . ,lo)
          (25%   . ,(list-ref sorted (quotient n 4)))
          (50%   . ,median)
          (75%   . ,(list-ref sorted (quotient (* 3 n) 4)))
          (max   . ,hi)
          (sum   . ,total)))))

  ;;; ========== Timing ==========
  (define (cpu-time)
    (let ([t (current-time 'time-process)])
      (+ (* (time-second t) 1000)
         (quotient (time-nanosecond t) 1000000))))

  (define (real-time-ms)
    (let ([t (current-time 'time-monotonic)])
      (+ (* (time-second t) 1000)
         (quotient (time-nanosecond t) 1000000))))

  (define (time-thunk thunk)
    (let* ([gc-before (statistics)]
           [t-before  (cpu-time)]
           [r-before  (real-time-ms)]
           [result    (thunk)]
           [t-after   (cpu-time)]
           [r-after   (real-time-ms)]
           [gc-after  (statistics)])
      (values result
              (- t-after t-before)    ; CPU ms
              (- r-after r-before)))) ; Real ms

  (define (time-thunk/detailed thunk)
    ;; Returns (values result cpu-ms real-ms gc-count bytes-allocated)
    (collect (collect-maximum-generation))
    (let* ([stats0 (statistics)]
           [t0     (cpu-time)]
           [r0     (real-time-ms)]
           [result (thunk)]
           [t1     (cpu-time)]
           [r1     (real-time-ms)]
           [stats1 (statistics)])
      ;; statistics returns an alist with gc-count, cpu-time, bytes-allocated, etc.
      (values result
              (- t1 t0)
              (- r1 r0)
              stats0
              stats1)))

  ;;; ========== Benchmarking ==========
  (define (benchmark-thunk thunk iterations)
    (collect (collect-maximum-generation))
    (let ([t0 (real-time-ms)])
      (do ([i 0 (+ i 1)])
          ((= i iterations))
        (thunk))
      (let* ([t1 (real-time-ms)]
             [total (- t1 t0)]
             [per-iter (if (> iterations 0) (/ (inexact total) iterations) 0.0)])
        (values total per-iter iterations))))

  ;;; ========== Documentation lookup ==========
  (define *doc-registry* (make-hash-table))

  (define (register-doc! sym doc-string)
    (hashtable-set! *doc-registry* sym doc-string))

  (define (repl-doc sym)
    (or (hashtable-ref *doc-registry* sym #f)
        (format "No documentation found for '~a'" sym)))

  ;;; ========== Apropos search ==========
  (define (repl-apropos query . env-opt)
    (let* ([env  (if (pair? env-opt) (car env-opt) (interaction-environment))]
           [syms (environment-symbols env)]
           [q    (string-downcase query)])
      (filter
        (lambda (sym)
          (let ([s (string-downcase (symbol->string sym))])
            (string-contains s q)))
        (if (list? syms) syms '()))))

  ;;; ========== Completion ==========
  (define (repl-complete prefix . env-opt)
    (let* ([env  (if (pair? env-opt) (car env-opt) (interaction-environment))]
           [syms (environment-symbols env)]
           [pfx  (string-downcase prefix)])
      (sort (lambda (a b) (string<? (symbol->string a) (symbol->string b)))
        (filter
          (lambda (sym)
            (let ([s (string-downcase (symbol->string sym))])
              (and (>= (string-length s) (string-length pfx))
                   (string=? (substring s 0 (string-length pfx)) pfx))))
          (if (list? syms) syms '())))))

  ;;; ========== String Helpers ==========
  (define (string-contains haystack needle)
    (let ([hn (string-length haystack)]
          [nn (string-length needle)])
      (let loop ([i 0])
        (cond
          [(> (+ i nn) hn) #f]
          [(string=? (substring haystack i (+ i nn)) needle) #t]
          [else (loop (+ i 1))]))))

  (define (string-trim str)
    (let* ([n   (string-length str)]
           [s   (let loop ([i 0])
                  (if (or (= i n) (not (char-whitespace? (string-ref str i))))
                    i
                    (loop (+ i 1))))]
           [e   (let loop ([i (- n 1)])
                  (if (or (< i 0) (not (char-whitespace? (string-ref str i))))
                    (+ i 1)
                    (loop (- i 1))))])
      (if (>= s e) "" (substring str s e))))

  (define (string-split-first-word str)
    (let* ([n   (string-length str)]
           [sp  (let loop ([i 0])
                  (if (or (= i n) (char-whitespace? (string-ref str i)))
                    i
                    (loop (+ i 1))))])
      (cons (substring str 0 sp)
            (if (= sp n)
              ""
              (string-trim (substring str sp n))))))

  (define (string-starts-with? str prefix)
    (and (>= (string-length str) (string-length prefix))
         (string=? (substring str 0 (string-length prefix)) prefix)))

  (define (string-join-with strs sep)
    (if (null? strs) ""
      (let loop ([rest (cdr strs)] [acc (car strs)])
        (if (null? rest) acc
          (loop (cdr rest) (string-append acc sep (car rest)))))))

  ;;; ========== Expand macro ==========
  (define (repl-expand expr env)
    (guard (exn [#t (format "Expansion error: ~a" exn)])
      (expand expr env)))

  ;;; ========== Pretty print ==========
  (define (repl-pp val . port-opt)
    (let ([port (if (pair? port-opt) (car port-opt) (current-output-port))])
      (pretty-print val port)))

  ;;; ========== Load file ==========
  (define (repl-load path env)
    (guard (exn [#t (format "Load error: ~a" exn)])
      (load path (lambda (x) (eval x env)))))

  ;;; ========== Type annotation ==========
  (define (repl-type val . port-opt)
    (let ([port (if (pair? port-opt) (car port-opt) (current-output-port))])
      (display (value->type-string val) port)
      (newline port)))

  ;;; ========== Time command ==========
  (define (repl-time thunk . port-opt)
    (let ([port (if (pair? port-opt) (car port-opt) (current-output-port))])
      (let* ([t0  (cpu-time)]
             [result (thunk)]
             [t1  (cpu-time)]
             [ms  (- t1 t0)])
        (fprintf port ";; ~a ms elapsed~n" ms)
        result)))

  ;;; ========== Balanced parens check ==========
  (define (balanced? str)
    (let loop ([chars (string->list str)] [depth 0] [in-string #f] [escape #f])
      (cond
        [(< depth 0) #f]
        [(null? chars) (and (= depth 0) (not in-string))]
        [else
         (let ([c (car chars)])
           (cond
             [escape
              (loop (cdr chars) depth in-string #f)]
             [(char=? c #\\)
              (loop (cdr chars) depth in-string #t)]
             [in-string
              (if (char=? c #\")
                (loop (cdr chars) depth #f #f)
                (loop (cdr chars) depth #t #f))]
             [(char=? c #\")
              (loop (cdr chars) depth #t #f)]
             [(char=? c #\;)
              ;; Skip to end of line
              (let skip ([rest (cdr chars)])
                (cond
                  [(null? rest) (= depth 0)]
                  [(char=? (car rest) #\newline)
                   (loop (cdr rest) depth #f #f)]
                  [else (skip (cdr rest))]))]
             [(or (char=? c #\() (char=? c #\[) (char=? c #\{))
              (loop (cdr chars) (+ depth 1) #f #f)]
             [(or (char=? c #\)) (char=? c #\]) (char=? c #\}))
              (loop (cdr chars) (- depth 1) #f #f)]
             [else
              (loop (cdr chars) depth #f #f)]))])))

  ;;; ========== REPL read ==========
  (define (repl-read-expr prompt-str port)
    (display prompt-str)
    (flush-output-port (current-output-port))
    (let ([line (get-line port)])
      (if (eof-object? line)
        line
        (let ([trimmed (string-trim line)])
          (if (string=? trimmed "")
            trimmed
            (let complete ([acc trimmed])
              (if (balanced? acc)
                acc
                (begin
                  (display "  ... ")
                  (flush-output-port (current-output-port))
                  (let ([next (get-line port)])
                    (if (eof-object? next)
                      acc
                      (complete (string-append acc "\n" next))))))))))))

  ;;; ========== REPL print ==========
  (define (repl-print val env cfg)
    (cond
      [(eq? val (void)) (void)]
      [else
       (let ([idx (history-push! val)])
         (update-history-bindings! env)
         ;; Show $N tag
         (display (colored cfg bright-black (format "$~a " idx)))
         (display (colored cfg cyan (format "[~a] " (value->type-string val))))
         ;; Smart printing: use pp for complex, write for simple
         (if (or (and (list? val) (> (length val) 3))
                 (and (vector? val) (> (vector-length val) 3))
                 (hashtable? val)
                 (and (record? val) (not (condition? val))))
           (begin (newline) (pretty-print val))
           (begin (write val) (newline))))]))

  ;;; ========== Multi-value printing ==========
  (define (repl-eval-and-print expr env cfg)
    ;; Evaluates expr, handles multiple values, stores in history
    (call-with-values
      (lambda () (eval expr env))
      (lambda results
        (cond
          [(null? results)
           (void)]
          [(= (length results) 1)
           (repl-print (car results) env cfg)]
          [else
           ;; Multiple values
           (display (colored cfg magenta ";; multiple values:\n"))
           (let loop ([vals results] [i 0])
             (when (pair? vals)
               (let ([idx (history-push! (car vals))])
                 (update-history-bindings! env)
                 (display (colored cfg bright-black (format "  $~a " idx)))
                 (display (colored cfg cyan
                   (format "[~a] " (value->type-string (car vals)))))
                 (write (car vals))
                 (newline))
               (loop (cdr vals) (+ i 1))))]))))

  ;;; ========== Command dispatch ==========
  (define (dispatch-command line env cfg)
    (let ([parts (string-split-first-word (string-trim line))])
      (let ([cmd  (car parts)]
            [rest (cdr parts)])
        (cond
          ;; ---- Inspection ----
          [(string=? cmd ",type")
           (guard (exn [#t (display-error cfg exn)])
             (let* ([expr   (with-input-from-string rest read)]
                    [val    (eval expr env)])
               (display (colored cfg cyan (value->type-string val)))
               (newline)))]

          [(string=? cmd ",describe")
           (guard (exn [#t (display-error cfg exn)])
             (let* ([expr (with-input-from-string rest read)]
                    [val  (eval expr env)])
               (deep-describe cfg val (current-output-port))))]

          [(string=? cmd ",inspect")
           (guard (exn [#t (display-error cfg exn)])
             (let* ([expr (with-input-from-string rest read)]
                    [val  (eval expr env)])
               (interactive-inspect cfg val env)))]

          [(string=? cmd ",apropos")
           (let* ([q    (string-trim rest)]
                  [syms (repl-apropos q env)]
                  [sorted (sort (lambda (a b)
                                  (string<? (symbol->string a) (symbol->string b)))
                                syms)])
             (if (null? sorted)
               (display ";; no matches\n")
               (begin
                 (fprintf (current-output-port) ";; ~a matches:~n" (length sorted))
                 (for-each (lambda (s)
                             (display "  ")
                             (display (colored cfg green (symbol->string s)))
                             ;; Show type of binding
                             (guard (exn [#t (void)])
                               (let ([v (eval s env)])
                                 (display (c-dim cfg
                                   (format " (~a)" (value->type-string v))))))
                             (newline))
                           (take sorted (min 30 (length sorted))))
                 (when (> (length sorted) 30)
                   (fprintf (current-output-port)
                     "  ... and ~a more~n" (- (length sorted) 30))))))]

          [(string=? cmd ",doc")
           (let ([sym-str (string-trim rest)])
             (display (colored cfg yellow (repl-doc (string->symbol sym-str))))
             (newline))]

          [(string=? cmd ",complete")
           (let* ([pfx   (string-trim rest)]
                  [comps (repl-complete pfx env)])
             (if (null? comps)
               (display ";; no completions\n")
               (begin
                 (for-each (lambda (s)
                             (display "  ")
                             (display (colored cfg green (symbol->string s)))
                             (newline))
                           (take comps (min 40 (length comps))))
                 (when (> (length comps) 40)
                   (fprintf (current-output-port) "  ... ~a more~n"
                     (- (length comps) 40))))))]

          [(string=? cmd ",who")
           (let* ([q   (string-trim rest)]
                  [sym (string->symbol q)]
                  [syms (environment-symbols env)])
             (display (format ";; '~a' is " q))
             (guard (exn [#t (display "not bound\n")])
               (let ([v (eval sym env)])
                 (display (colored cfg cyan (value->type-string v)))
                 (newline)
                 (when (procedure? v)
                   (let ([name (guard (e [#t #f]) (#%$code-name (#%$closure-code v)))])
                     (when name
                       (fprintf (current-output-port) "  procedure-name: ~a~n" name)))))))]

          ;; ---- Evaluation & Debugging ----
          [(string=? cmd ",expand")
           (guard (exn [#t (display-error cfg exn)])
             (let* ([expr (with-input-from-string rest read)]
                    [expanded (expand expr env)])
               (pretty-print expanded)))]

          [(string=? cmd ",expand1")
           (guard (exn [#t (display-error cfg exn)])
             (let* ([expr (with-input-from-string rest read)]
                    [expanded (sc-expand expr)])
               (pretty-print expanded)))]

          [(string=? cmd ",trace")
           (guard (exn [#t (display-error cfg exn)])
             (let ([sym (string->symbol (string-trim rest))])
               (eval `(trace ,sym) env)
               (set! *traced-fns* (cons sym *traced-fns*))
               (display (colored cfg green (format ";; tracing ~a~n" sym)))))]

          [(string=? cmd ",untrace")
           (guard (exn [#t (display-error cfg exn)])
             (let ([sym (string->symbol (string-trim rest))])
               (eval `(untrace ,sym) env)
               (set! *traced-fns* (filter (lambda (s) (not (eq? s sym))) *traced-fns*))
               (display (colored cfg green (format ";; untraced ~a~n" sym)))))]

          [(string=? cmd ",trace-all")
           (if (null? *traced-fns*)
             (display ";; no traced functions\n")
             (begin
               (display ";; traced functions:\n")
               (for-each (lambda (s)
                           (fprintf (current-output-port) "  ~a~n" s))
                         *traced-fns*)))]

          ;; ---- Performance ----
          [(string=? cmd ",time")
           (guard (exn [#t (display-error cfg exn)])
             (let ([expr (with-input-from-string rest read)])
               (let-values ([(result cpu-ms real-ms _s0 _s1)
                             (time-thunk/detailed (lambda () (eval expr env)))])
                 (repl-print result env cfg)
                 (display (colored cfg yellow
                   (format ";; cpu: ~ams  real: ~ams~n" cpu-ms real-ms))))))]

          [(string=? cmd ",bench")
           (guard (exn [#t (display-error cfg exn)])
             (let* ([p    (open-input-string rest)]
                    [expr (read p)]
                    [n    (let ([v (read p)]) (if (eof-object? v) 100 v))])
               (display (colored cfg yellow (format ";; benchmarking ~a iterations...~n" n)))
               (flush-output-port (current-output-port))
               (let-values ([(total per-iter iters)
                             (benchmark-thunk (lambda () (eval expr env)) n)])
                 (display (colored cfg yellow
                   (format ";; total: ~ams  per-iteration: ~,3fms  (~a iter/s)~n"
                     total per-iter
                     (if (> per-iter 0)
                       (inexact (round (/ 1000.0 per-iter)))
                       "+inf")))))))]

          [(string=? cmd ",profile")
           (guard (exn [#t (display-error cfg exn)])
             (let ([expr (with-input-from-string rest read)])
               (profile-clear)
               (let ([result (eval expr env)])
                 (repl-print result env cfg)
                 (display (colored cfg yellow ";; profile dump:\n"))
                 (profile-dump))))]

          [(string=? cmd ",alloc")
           (guard (exn [#t (display-error cfg exn)])
             (let ([expr (with-input-from-string rest read)])
               (collect (collect-maximum-generation))
               (let* ([before (bytes-allocated)]
                      [result (eval expr env)]
                      [after  (bytes-allocated)]
                      [delta  (- after before)])
                 (repl-print result env cfg)
                 (display (colored cfg yellow
                   (format ";; allocated: ~a bytes~n" delta))))))]

          ;; ---- Module System ----
          [(string=? cmd ",import")
           (guard (exn [#t (display-error cfg exn)])
             (let ([mod-expr (with-input-from-string rest read)])
               (eval `(import ,mod-expr) env)
               (display (colored cfg green (format ";; imported ~s~n" mod-expr)))))]

          [(string=? cmd ",reload")
           (let ([path (string-trim rest)])
             (guard (exn [#t (display-error cfg exn)])
               (load path (lambda (x) (eval x env)))
               (display (colored cfg green (format ";; reloaded ~a~n" path)))))]

          [(string=? cmd ",cd")
           (let ([path (string-trim rest)])
             (if (string=? path "")
               (begin
                 (current-directory (or (getenv "HOME") "/"))
                 (display (colored cfg green (format ";; ~a~n" (current-directory)))))
               (begin
                 (current-directory path)
                 (display (colored cfg green (format ";; ~a~n" (current-directory)))))))]

          [(string=? cmd ",pwd")
           (display (current-directory))
           (newline)]

          [(string=? cmd ",ls")
           (let ([path (if (string=? (string-trim rest) "")
                         (current-directory)
                         (string-trim rest))])
             (guard (exn [#t (display-error cfg exn)])
               (let ([entries (sort string<? (directory-list path))])
                 (for-each (lambda (e)
                             (let ([full (string-append path "/" e)])
                               (if (file-directory? full)
                                 (display (colored cfg blue (string-append e "/")))
                                 (display e)))
                             (display "  "))
                           entries)
                 (newline))))]

          [(string=? cmd ",shell")
           (guard (exn [#t (display-error cfg exn)])
             (let ([cmd-str (string-trim rest)])
               (system cmd-str)))]

          ;; ---- Data Inspection ----
          [(string=? cmd ",pp")
           (guard (exn [#t (display-error cfg exn)])
             (let* ([expr (with-input-from-string rest read)]
                    [val  (eval expr env)])
               (pretty-print val)))]

          [(string=? cmd ",table")
           (guard (exn [#t (display-error cfg exn)])
             (let* ([expr (with-input-from-string rest read)]
                    [val  (eval expr env)]
                    [rows (value->table-rows val)])
               (if rows
                 (display-table cfg rows (current-output-port))
                 (display ";; value cannot be displayed as a table\n"))))]

          [(string=? cmd ",json")
           (guard (exn [#t (display-error cfg exn)])
             (let* ([expr (with-input-from-string rest read)]
                    [val  (eval expr env)])
               (display (value->json-string val))
               (newline)))]

          [(string=? cmd ",head")
           (guard (exn [#t (display-error cfg exn)])
             (let* ([p    (open-input-string rest)]
                    [expr (read p)]
                    [n    (let ([v (read p)]) (if (eof-object? v) 10 v))]
                    [val  (eval expr env)])
               (cond
                 [(list? val)
                  (for-each (lambda (v i)
                              (display (c-dim cfg (format "[~a] " i)))
                              (write v) (newline))
                            (take val (min n (length val)))
                            (iota* (min n (length val))))]
                 [(vector? val)
                  (do ([i 0 (+ i 1)])
                      ((or (= i n) (= i (vector-length val))))
                    (display (c-dim cfg (format "[~a] " i)))
                    (write (vector-ref val i))
                    (newline))]
                 [else (write val) (newline)])))]

          [(string=? cmd ",tail")
           (guard (exn [#t (display-error cfg exn)])
             (let* ([p    (open-input-string rest)]
                    [expr (read p)]
                    [n    (let ([v (read p)]) (if (eof-object? v) 10 v))]
                    [val  (eval expr env)])
               (cond
                 [(list? val)
                  (let* ([len (length val)]
                         [start (max 0 (- len n))])
                    (for-each (lambda (v i)
                                (display (c-dim cfg (format "[~a] " (+ start i))))
                                (write v) (newline))
                              (drop val start)
                              (iota* (min n len))))]
                 [(vector? val)
                  (let* ([len (vector-length val)]
                         [start (max 0 (- len n))])
                    (do ([i start (+ i 1)])
                        ((= i len))
                      (display (c-dim cfg (format "[~a] " i)))
                      (write (vector-ref val i))
                      (newline)))]
                 [else (write val) (newline)])))]

          [(string=? cmd ",count")
           (guard (exn [#t (display-error cfg exn)])
             (let* ([expr (with-input-from-string rest read)]
                    [val  (eval expr env)])
               (cond
                 [(list? val) (fprintf (current-output-port) "~a items~n" (length val))]
                 [(vector? val) (fprintf (current-output-port) "~a elements~n" (vector-length val))]
                 [(string? val) (fprintf (current-output-port) "~a characters~n" (string-length val))]
                 [(bytevector? val) (fprintf (current-output-port) "~a bytes~n" (bytevector-length val))]
                 [(hashtable? val) (fprintf (current-output-port) "~a entries~n" (hashtable-size val))]
                 [else (display ";; not a collection\n")])))]

          [(string=? cmd ",stats")
           (guard (exn [#t (display-error cfg exn)])
             (let* ([expr (with-input-from-string rest read)]
                    [val  (eval expr env)]
                    [lst  (cond
                            [(list? val) val]
                            [(vector? val) (vector->list val)]
                            [else '()])]
                    [stats (list-stats lst)])
               (if (null? stats)
                 (display ";; not a numeric collection\n")
                 (for-each (lambda (p)
                             (fprintf (current-output-port) "  ~6a ~a~n"
                               (car p) (cdr p)))
                           stats))))]

          [(string=? cmd ",freq")
           (guard (exn [#t (display-error cfg exn)])
             (let* ([expr (with-input-from-string rest read)]
                    [val  (eval expr env)]
                    [lst  (cond [(list? val) val]
                                [(vector? val) (vector->list val)]
                                [else '()])]
                    [freq (frequency-table lst)]
                    [total (length lst)])
               (display-table cfg
                 (cons (list "value" "count" "%")
                       (map (lambda (p)
                              (list (format "~a" (car p))
                                    (format "~a" (cdr p))
                                    (format "~,1f" (* 100.0 (/ (cdr p) total)))))
                            (take freq (min 30 (length freq)))))
                 (current-output-port))
               (when (> (length freq) 30)
                 (fprintf (current-output-port) ";; ... ~a more distinct values~n"
                   (- (length freq) 30)))))]

          ;; ---- Session ----
          [(string=? cmd ",history")
           (let* ([n (if (string=? (string-trim rest) "")
                       20
                       (string->number (string-trim rest)))]
                  [entries (take *value-history* (min n (length *value-history*)))])
             (for-each (lambda (entry)
                         (display (colored cfg bright-black (format "$~a " (car entry))))
                         (display (c-dim cfg (format "[~a] " (value->type-string (cdr entry)))))
                         (let ([s (format "~s" (cdr entry))])
                           (if (> (string-length s) 72)
                             (display (string-append (substring s 0 69) "..."))
                             (display s)))
                         (newline))
                       (reverse entries)))]

          [(string=? cmd ",save")
           (let ([path (string-trim rest)])
             (if (string=? path "")
               (begin (save-history!)
                      (display (colored cfg green
                        (format ";; saved history to ~a~n" (history-file-path)))))
               (guard (exn [#t (display-error cfg exn)])
                 (call-with-output-file path
                   (lambda (p)
                     (for-each (lambda (line) (display line p) (newline p))
                               (reverse *input-history*)))
                   'replace)
                 (display (colored cfg green (format ";; saved ~a entries to ~a~n"
                   (length *input-history*) path))))))]

          [(string=? cmd ",load")
           (let ([path (string-trim rest)])
             (guard (exn [#t (display-error cfg exn)])
               (repl-load path env)
               (display (colored cfg green (format ";; loaded ~a~n" path)))))]

          [(string=? cmd ",clear")
           (history-clear!)
           (install-history-bindings! env)
           (display ";; history cleared\n")]

          [(string=? cmd ",reset")
           (history-clear!)
           (set! *input-history* '())
           (set! *traced-fns* '())
           (display ";; environment and history reset\n")]

          [(string=? cmd ",set")
           (let ([parts2 (string-split-first-word rest)])
             (let ([key (string-trim (car parts2))]
                   [val-str (string-trim (cdr parts2))])
               (cond
                 [(string=? key "prompt")
                  (repl-config-prompt-set! cfg val-str)
                  (display (format ";; prompt set to ~s~n" val-str))]
                 [(string=? key "color")
                  (repl-config-color?-set! cfg (string=? val-str "on"))
                  (display (format ";; color ~a~n" (if (repl-config-color? cfg) "on" "off")))]
                 [(string=? key "time")
                  (repl-config-show-time?-set! cfg (string=? val-str "on"))
                  (display (format ";; auto-time ~a~n" (if (repl-config-show-time? cfg) "on" "off")))]
                 [else
                  (display (format ";; unknown setting: ~a (try: prompt, color, time)~n" key))])))]

          [(string=? cmd ",env")
           (let* ([pattern (string-trim rest)]
                  [syms (sort (lambda (a b)
                                (string<? (symbol->string a) (symbol->string b)))
                              (if (string=? pattern "")
                                (environment-symbols env)
                                (filter (lambda (s)
                                          (string-contains (string-downcase (symbol->string s))
                                                          (string-downcase pattern)))
                                        (environment-symbols env))))])
             (let ([shown (take syms (min 60 (length syms)))])
               (for-each (lambda (s)
                           (display "  ")
                           (display (colored cfg green (symbol->string s)))
                           (guard (exn [#t (void)])
                             (let ([v (eval s env)])
                               (display (c-dim cfg
                                 (format " : ~a" (value->type-string v))))))
                           (newline))
                         shown)
               (when (> (length syms) 60)
                 (fprintf (current-output-port) ";; ... ~a more~n" (- (length syms) 60)))))]

          [(string=? cmd ",help")
           (let ([topic (string-trim rest)])
             (if (string=? topic "")
               (display-help cfg)
               (display-help-topic cfg topic)))]

          [else
           (display (colored cfg red (format ";; unknown command: ~a (try ,help)~n" cmd)))]))))

  ;;; ========== Interactive Inspector ==========
  (define (interactive-inspect cfg val env)
    (let inspect-loop ([v val] [path '("root")] [stack '()])
      (display (colored cfg bold "\n--- Inspector ---\n"))
      (display (c-dim cfg (format "  path: ~a\n" (string-join-with (reverse path) " > "))))
      (deep-describe cfg v (current-output-port))
      (newline)
      (display (c-dim cfg "  [number] dive into element  [u]p  [q]uit  [p]rint  [e]val expr\n"))
      (display (colored cfg magenta "inspect> "))
      (flush-output-port (current-output-port))
      (let ([input (get-line (current-input-port))])
        (cond
          [(or (eof-object? input) (string=? (string-trim input) "q"))
           (void)]
          [(string=? (string-trim input) "u")
           (if (null? stack)
             (void)  ;; at top level, quit
             (inspect-loop (car stack) (cdr path) (cdr stack)))]
          [(string=? (string-trim input) "p")
           (pretty-print v)
           (inspect-loop v path stack)]
          [(string-starts-with? (string-trim input) "e ")
           (guard (exn [#t (display-error cfg exn)])
             (let* ([expr (with-input-from-string
                            (substring (string-trim input) 2
                                       (string-length (string-trim input)))
                            read)]
                    [result (eval expr env)])
               (write result) (newline)))
           (inspect-loop v path stack)]
          [else
           ;; Try as index
           (let ([n (string->number (string-trim input))])
             (if n
               (guard (exn [#t
                            (display (colored cfg red ";; invalid index\n"))
                            (inspect-loop v path stack)])
                 (let ([child (cond
                                [(list? v) (list-ref v n)]
                                [(vector? v) (vector-ref v n)]
                                [(hashtable? v)
                                 (let-values ([(keys vals) (hashtable-entries v)])
                                   (vector-ref vals n))]
                                [(and (record? v) (not (condition? v)))
                                 (let ([rtd (record-rtd v)])
                                   ((record-accessor rtd n) v))]
                                [else (error 'inspect "cannot index" v)])])
                   (inspect-loop child
                                (cons (format "~a" n) path)
                                (cons v stack))))
               (begin
                 (display ";; enter a number, 'u', 'q', 'p', or 'e expr'\n")
                 (inspect-loop v path stack))))]))))

  ;;; ========== JSON output ==========
  (define (value->json-string v)
    (cond
      [(eq? v #t) "true"]
      [(eq? v #f) "false"]
      [(null? v) "[]"]
      [(void-object? v) "null"]
      [(number? v) (number->string (inexact v))]
      [(string? v)
       (string-append "\"" (json-escape-string v) "\"")]
      [(symbol? v)
       (string-append "\"" (json-escape-string (symbol->string v)) "\"")]
      [(and (list? v) (every pair? v) (not (every list? v)))
       ;; Alist -> object
       (string-append "{"
         (string-join-with
           (map (lambda (p)
                  (string-append
                    "\"" (json-escape-string (format "~a" (car p))) "\": "
                    (value->json-string (cdr p))))
                v)
           ", ")
         "}")]
      [(list? v)
       (string-append "["
         (string-join-with (map value->json-string v) ", ")
         "]")]
      [(vector? v)
       (value->json-string (vector->list v))]
      [(hashtable? v)
       (let-values ([(keys vals) (hashtable-entries v)])
         (string-append "{"
           (string-join-with
             (let loop ([i 0] [acc '()])
               (if (= i (vector-length keys))
                 (reverse acc)
                 (loop (+ i 1)
                       (cons (string-append
                               "\"" (json-escape-string (format "~a" (vector-ref keys i)))
                               "\": " (value->json-string (vector-ref vals i)))
                             acc))))
             ", ")
           "}"))]
      [else (format "~s" v)]))

  (define (json-escape-string s)
    (let ([out (open-output-string)])
      (string-for-each
        (lambda (c)
          (cond
            [(char=? c #\") (display "\\\"" out)]
            [(char=? c #\\) (display "\\\\" out)]
            [(char=? c #\newline) (display "\\n" out)]
            [(char=? c #\tab) (display "\\t" out)]
            [(char=? c #\return) (display "\\r" out)]
            [else (display c out)]))
        s)
      (get-output-string out)))

  ;;; ========== Error display ==========
  (define (display-error cfg exn)
    (display (colored cfg red "error: "))
    (cond
      [(message-condition? exn)
       (display (colored cfg red (condition-message exn)))
       (when (irritants-condition? exn)
         (display " ")
         (write (condition-irritants exn)))]
      [else (write exn)])
    (newline))

  ;;; ========== Help System ==========
  (define *help-topics*
    '(("type"     "Show the type of an expression result"
       ",type expr\n  Evaluates expr and displays its type.\n  Example: ,type (list 1 2 3)  =>  List[3]")
      ("describe" "Deep inspection of a value"
       ",describe expr\n  Shows detailed structure: fields, entries, elements.\n  Works with records, hash tables, lists, vectors, bytevectors.")
      ("inspect"  "Interactive value inspector"
       ",inspect expr\n  Opens an interactive inspector. Navigate with numbers to dive\n  into sub-values, 'u' to go up, 'q' to quit, 'e expr' to eval.")
      ("apropos"  "Search for symbols"
       ",apropos str\n  Case-insensitive substring search across all bound symbols.\n  Shows type annotations for each match.")
      ("doc"      "Show documentation for a symbol"
       ",doc sym\n  Looks up sym in the documentation registry.")
      ("complete" "Symbol completion"
       ",complete prefix\n  Shows all symbols starting with the given prefix.")
      ("who"      "Show binding info for a symbol"
       ",who sym\n  Shows what a symbol is bound to and its type.")
      ("expand"   "Full macro expansion"
       ",expand expr\n  Shows the fully expanded form of a macro expression.")
      ("expand1"  "One-step macro expansion"
       ",expand1 expr\n  Shows one level of macro expansion.")
      ("trace"    "Enable function tracing"
       ",trace fn\n  Enables Chez Scheme's built-in tracing for fn.\n  Each call and return is printed.")
      ("untrace"  "Disable function tracing"
       ",untrace fn\n  Disables tracing for fn.")
      ("trace-all" "List traced functions"
       ",trace-all\n  Shows all currently traced functions.")
      ("time"     "Time an expression"
       ",time expr\n  Measures CPU and real time for evaluation.")
      ("bench"    "Benchmark an expression"
       ",bench expr [n]\n  Runs expr N times (default 100) and reports timing.\n  Example: ,bench (sort < (iota 1000)) 1000")
      ("profile"  "Profile with Chez profiler"
       ",profile expr\n  Uses Chez's built-in profiler to analyze expr.")
      ("alloc"    "Show memory allocation"
       ",alloc expr\n  Reports bytes allocated during evaluation.")
      ("import"   "Import a module"
       ",import (module-name)\n  Imports a library into the REPL environment.\n  Example: ,import (std text json)")
      ("reload"   "Reload a file"
       ",reload path\n  Re-loads and evaluates a file.")
      ("cd"       "Change directory"
       ",cd [path]\n  Changes current directory. No arg = home.")
      ("pwd"      "Print working directory"
       ",pwd\n  Shows the current directory.")
      ("ls"       "List directory"
       ",ls [path]\n  Lists directory contents. Directories shown in blue.")
      ("shell"    "Run shell command"
       ",shell cmd\n  Executes a shell command.")
      ("pp"       "Pretty-print"
       ",pp expr\n  Pretty-prints the value of expr.")
      ("table"    "Display as table"
       ",table expr\n  Displays lists-of-alists or lists-of-lists as aligned columns.\n  Also works with hash tables.")
      ("json"     "Display as JSON"
       ",json expr\n  Converts value to JSON and displays it.")
      ("head"     "Show first N items"
       ",head expr [n]\n  Shows first N items of a list/vector (default 10).")
      ("tail"     "Show last N items"
       ",tail expr [n]\n  Shows last N items of a list/vector (default 10).")
      ("count"    "Count collection items"
       ",count expr\n  Shows the size of a list, vector, string, bytevector, or hash.")
      ("stats"    "Numeric statistics"
       ",stats expr\n  Shows count, mean, std, min, max, quartiles for numeric data.")
      ("freq"     "Frequency table"
       ",freq expr\n  Shows value frequencies sorted by count descending.")
      ("history"  "Show value history"
       ",history [n]\n  Shows last N result history entries (default 20).\n  Use $N to reference history values.")
      ("save"     "Save history"
       ",save [path]\n  Saves input history. No arg = ~/.jerboa_history")
      ("load"     "Load a file"
       ",load path\n  Loads and evaluates a Scheme file.")
      ("clear"    "Clear history"
       ",clear\n  Clears the value history ($N references).")
      ("reset"    "Reset environment"
       ",reset\n  Resets the REPL environment and history.")
      ("set"      "Set REPL option"
       ",set key val\n  Options: prompt <str>, color on|off, time on|off")
      ("env"      "List environment bindings"
       ",env [pattern]\n  Lists bound symbols, optionally filtered by pattern.\n  Shows type annotations.")
      ("help"     "Show help"
       ",help [cmd]\n  Shows general help or detailed help for a command.")
      ("quit"     "Exit REPL"
       ",quit\n  Exits the REPL.")))

  (define (display-help cfg)
    (display (c-bold cfg "Jerboa REPL — World-class Interactive Environment\n\n"))
    (display (c-bold cfg "  Value History:\n"))
    (display "    *  ** ***           last 3 results (Common Lisp-style)\n")
    (display "    $1 $2 $3 ...       numbered result references\n\n")
    (display (c-bold cfg "  Inspection & Exploration:\n"))
    (for-each (lambda (t)
                (when (member (car t) '("type" "describe" "inspect" "apropos" "doc" "complete" "who"))
                  (fprintf (current-output-port) "    ,~a~a— ~a~n"
                    (car t)
                    (make-string (max 1 (- 14 (string-length (car t)))) #\space)
                    (cadr t))))
              *help-topics*)
    (display (c-bold cfg "\n  Evaluation & Debugging:\n"))
    (for-each (lambda (t)
                (when (member (car t) '("expand" "expand1" "trace" "untrace" "trace-all"))
                  (fprintf (current-output-port) "    ,~a~a— ~a~n"
                    (car t)
                    (make-string (max 1 (- 14 (string-length (car t)))) #\space)
                    (cadr t))))
              *help-topics*)
    (display (c-bold cfg "\n  Performance:\n"))
    (for-each (lambda (t)
                (when (member (car t) '("time" "bench" "profile" "alloc"))
                  (fprintf (current-output-port) "    ,~a~a— ~a~n"
                    (car t)
                    (make-string (max 1 (- 14 (string-length (car t)))) #\space)
                    (cadr t))))
              *help-topics*)
    (display (c-bold cfg "\n  Module System:\n"))
    (for-each (lambda (t)
                (when (member (car t) '("import" "reload" "cd" "pwd" "ls" "shell"))
                  (fprintf (current-output-port) "    ,~a~a— ~a~n"
                    (car t)
                    (make-string (max 1 (- 14 (string-length (car t)))) #\space)
                    (cadr t))))
              *help-topics*)
    (display (c-bold cfg "\n  Data Inspection:\n"))
    (for-each (lambda (t)
                (when (member (car t) '("pp" "table" "json" "head" "tail" "count" "stats" "freq"))
                  (fprintf (current-output-port) "    ,~a~a— ~a~n"
                    (car t)
                    (make-string (max 1 (- 14 (string-length (car t)))) #\space)
                    (cadr t))))
              *help-topics*)
    (display (c-bold cfg "\n  Session:\n"))
    (for-each (lambda (t)
                (when (member (car t) '("history" "save" "load" "clear" "reset" "set" "env" "help" "quit"))
                  (fprintf (current-output-port) "    ,~a~a— ~a~n"
                    (car t)
                    (make-string (max 1 (- 14 (string-length (car t)))) #\space)
                    (cadr t))))
              *help-topics*)
    (newline))

  (define (display-help-topic cfg topic)
    (let ([entry (find (lambda (t) (string=? (car t) topic)) *help-topics*)])
      (if entry
        (begin
          (display (c-bold cfg (format "  ,~a — ~a\n\n" (car entry) (cadr entry))))
          (display (caddr entry))
          (newline))
        (display (format ";; no help for '~a' — try ,help~n" topic)))))

  ;;; ========== History variable expansion ==========
  ;; Rewrite $N references to (repl-history-ref N) before eval
  (define (expand-history-refs expr-str)
    ;; Replace $N with history lookups in the expression string
    (let ([len (string-length expr-str)])
      (let loop ([i 0] [acc '()])
        (cond
          [(>= i len)
           (list->string (reverse acc))]
          [(and (char=? (string-ref expr-str i) #\$)
                (< (+ i 1) len)
                (char-numeric? (string-ref expr-str (+ i 1))))
           ;; Found $N — collect digits
           (let digit-loop ([j (+ i 1)] [digits '()])
             (if (and (< j len) (char-numeric? (string-ref expr-str j)))
               (digit-loop (+ j 1) (cons (string-ref expr-str j) digits))
               (let ([num-str (list->string (reverse digits))])
                 (let ([replacement (string->list
                                     (string-append "(repl-history-ref "
                                                    num-str ")"))])
                   (loop j (append (reverse replacement) acc))))))]
          [else
           (loop (+ i 1) (cons (string-ref expr-str i) acc))]))))

  ;;; ========== iota helper ==========
  (define (iota* n)
    (let loop ([i 0] [acc '()])
      (if (= i n) (reverse acc) (loop (+ i 1) (cons i acc)))))

  ;;; ========== Main REPL loop ==========
  (define (jerboa-repl . args)
    (let* ([cfg  (if (and (pair? args) (repl-config? (car args)))
                   (car args)
                   *default-config*)]
           [env  (interaction-environment)]
           [port (current-input-port)])

      ;; Load persistent history
      (load-history!)

      ;; Install history bindings
      (install-history-bindings! env)

      ;; Make repl-history-ref available in env
      (eval '(define repl-history-ref #f) env)
      (eval `(set! repl-history-ref ,repl-history-ref) env)

      ;; Welcome banner
      (display (c-bold cfg "Jerboa REPL"))
      (display (c-dim cfg (format " v1.0 [Chez Scheme ~a]" (scheme-version))))
      (newline)
      (display (c-dim cfg "  Type ,help for commands, ,quit to exit\n"))
      (display (c-dim cfg "  Results stored as $1, $2, ... and *, **, ***\n"))
      (newline)

      (let loop ()
        (let ([input (repl-read-expr (colored cfg green (repl-config-prompt cfg)) port)])
          (cond
            [(eof-object? input)
             (newline)
             (save-history!)
             (display "Goodbye.\n")]
            [(string=? (string-trim input) "")
             (loop)]
            [(string=? (string-trim input) ",quit")
             (save-history!)
             (display "Goodbye.\n")]
            [(and (> (string-length (string-trim input)) 0)
                  (char=? #\, (string-ref (string-trim input) 0)))
             ;; REPL command
             (input-history-push! (string-trim input))
             (dispatch-command (string-trim input) env cfg)
             (loop)]
            [else
             ;; Normal expression — expand $N history refs
             (let ([expanded-input (expand-history-refs input)])
               (input-history-push! (string-trim input))
               (guard (exn [#t (display-error cfg exn)])
                 (let ([expr (with-input-from-string expanded-input read)])
                   (let ([t0 (cpu-time)])
                     (repl-eval-and-print expr env cfg)
                     (when (repl-config-show-time? cfg)
                       (let ([t1 (cpu-time)])
                         (display (colored cfg yellow
                           (format ";; ~a ms~n" (- t1 t0))))))))))
             (loop)])))))

  ;; Pre-populate doc registry with common procedures
  (for-each
    (lambda (entry)
      (register-doc! (car entry) (cadr entry)))
    '((car        "(car pair) -> any\n  Return the first element of pair.")
      (cdr        "(cdr pair) -> any\n  Return the rest of pair.")
      (cons       "(cons a b) -> pair\n  Construct a pair.")
      (list       "(list x ...) -> list\n  Create a list from arguments.")
      (map        "(map proc list ...) -> list\n  Apply proc to each element, collecting results.")
      (filter     "(filter pred list) -> list\n  Keep elements satisfying pred.")
      (fold-left  "(fold-left proc init list) -> any\n  Left fold over a list.")
      (fold-right "(fold-right proc init list) -> any\n  Right fold over a list.")
      (for-each   "(for-each proc list ...) -> void\n  Apply proc for side effects.")
      (apply      "(apply proc arg ... list) -> any\n  Apply proc to argument list.")
      (values     "(values x ...) -> values\n  Return multiple values.")
      (call-with-values "(call-with-values producer consumer)\n  Multiple-value protocol.")
      (hash-ref   "(hash-ref ht key [default]) -> any\n  Look up key in hash table.")
      (hash-put!  "(hash-put! ht key val) -> void\n  Set key in hash table.")
      (hash-get   "(hash-get ht key [default]) -> any\n  Get key, #f if missing.")
      (string-append "(string-append str ...) -> string\n  Concatenate strings.")
      (number->string "(number->string n [radix]) -> string\n  Convert number to string.")
      (string->number "(string->number str [radix]) -> number or #f\n  Parse a number from string.")
      (sort       "(sort pred list) -> list\n  Sort a list using predicate.")
      (vector     "(vector x ...) -> vector\n  Create a vector from arguments.")
      (make-hash-table "(make-hash-table) -> hash-table\n  Create an empty hash table (equal? keys).")
      (eval       "(eval expr [env]) -> any\n  Evaluate an expression.")
      (load       "(load path) -> void\n  Load and evaluate a file.")
      (import     "(import (lib ...)) -> void\n  Import a library.")
      (define     "(define name expr) or (define (name args) body)\n  Define a binding.")
      (lambda     "(lambda (args) body ...) -> procedure\n  Create a procedure.")
      (let        "(let ((var expr) ...) body) -> any\n  Local bindings.")
      (if         "(if test then else) -> any\n  Conditional expression.")
      (cond       "(cond (test expr) ... (else expr)) -> any\n  Multi-way conditional.")
      (match      "(match expr (pattern body) ...) -> any\n  Pattern matching.")
      (guard      "(guard (var (test expr) ...) body) -> any\n  Exception handling.")
      (format     "(format fmt arg ...) -> string\n  Formatted string output (~a display, ~s write, ~n newline).")
      (pretty-print "(pretty-print obj [port]) -> void\n  Pretty-print with indentation.")
      (with-input-from-string "(with-input-from-string str thunk) -> any\n  Read from a string.")
      (with-output-to-string "(with-output-to-string thunk) -> string\n  Capture output as string.")
      (current-directory "(current-directory [path]) -> string\n  Get or set the current directory.")
      (file-exists? "(file-exists? path) -> boolean\n  Test if file exists.")
      (open-input-file "(open-input-file path) -> port\n  Open a file for reading.")
      (open-output-file "(open-output-file path) -> port\n  Open a file for writing.")))

) ;; end library
