#!chezscheme
;;; (std repl) -- Enhanced Interactive REPL
;;;
;;; Provides a rich interactive REPL with:
;;;   ,type expr      -- show type of expression result
;;;   ,time expr      -- measure evaluation time
;;;   ,doc sym        -- show documentation
;;;   ,apropos str    -- search for symbols matching string
;;;   ,trace (f args) -- trace a function call
;;;   ,expand expr    -- show macro expansion
;;;   ,profile expr   -- profile expression
;;;   ,pp expr        -- pretty-print
;;;   ,load path      -- load a file
;;;   ,env            -- list current bindings
;;;
;;; Usage:
;;;   (import (std repl))
;;;   (jerboa-repl)   ; start the enhanced REPL

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
    value->type-string describe-value)

  (import (except (chezscheme) cpu-time)
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
  (define (color-code n)
    (string-append "\x1b;[" (number->string n) "m"))

  (define reset-color   "\x1b;[0m")
  (define bold          "\x1b;[1m")
  (define red           "\x1b;[31m")
  (define green         "\x1b;[32m")
  (define yellow        "\x1b;[33m")
  (define blue          "\x1b;[34m")
  (define magenta       "\x1b;[35m")
  (define cyan          "\x1b;[36m")
  (define white         "\x1b;[37m")

  (define (colored cfg color str)
    (if (repl-config-color? cfg)
      (string-append color str reset-color)
      str))

  ;;; ========== Type inference ==========
  ;; Returns a human-readable type string for a value.
  (define (value->type-string v)
    (cond
      [(boolean? v)    "Boolean"]
      [(fixnum? v)     "Fixnum"]
      [(flonum? v)     "Flonum"]
      [(bignum? v)     "Bignum"]
      [(rational? v)   "Rational"]
      [(complex? v)    "Complex"]
      [(char? v)       "Char"]
      [(string? v)     (string-append "String[" (number->string (string-length v)) "]")]
      [(symbol? v)     "Symbol"]
      [(keyword? v)    "Keyword"]
      [(null? v)       "Null"]
      [(pair? v)
       (if (list? v)
         (string-append "List[" (number->string (length v)) "]")
         "Pair")]
      [(vector? v)     (string-append "Vector[" (number->string (vector-length v)) "]")]
      [(bytevector? v) (string-append "Bytevector[" (number->string (bytevector-length v)) "]")]
      [(port? v)       (if (input-port? v) "InputPort" "OutputPort")]
      [(procedure? v)  "Procedure"]
      [(hash-table? v) (string-append "HashTable[" (number->string (hashtable-size v)) "]")]
      [(void-object? v) "Void"]
      [else
       ;; Try to get record type name
       (guard (exn [#t "Unknown"])
         (let ([rtd (record-rtd v)])
           (symbol->string (record-type-name rtd))))]))

  (define (keyword? v)
    ;; Keywords are symbols starting with ':'  -- simplified check
    (and (symbol? v)
         (let ([s (symbol->string v)])
           (and (> (string-length s) 0)
                (char=? (string-ref s 0) #\:)))))

  (define (void-object? v)
    (eq? v (void)))

  ;;; ========== describe-value ==========
  (define (describe-value v . port-opt)
    (let ([port (if (pair? port-opt) (car port-opt) (current-output-port))])
      (display (value->type-string v) port)
      (display ": " port)
      (write v port)
      (newline port)))

  ;;; ========== Timing ==========
  (define (time-thunk thunk)
    (let* ([gc-before (statistics)]
           [t-before  (cpu-time)]
           [result    (thunk)]
           [t-after   (cpu-time)]
           [gc-after  (statistics)])
      (values result
              (- t-after t-before)  ; CPU time in milliseconds
              )))

  (define (cpu-time)
    ;; Returns CPU time in milliseconds
    (let ([t (current-time 'time-process)])
      (+ (* (time-second t) 1000)
         (quotient (time-nanosecond t) 1000000))))

  ;;; ========== Documentation lookup ==========
  ;; Simple documentation registry
  (define *doc-registry* (make-hash-table))

  (define (register-doc! sym doc-string)
    (hashtable-set! *doc-registry* sym doc-string))

  (define (repl-doc sym)
    (or (hashtable-ref *doc-registry* sym #f)
        (format "No documentation found for '~a'" sym)))

  ;;; ========== Apropos search ==========
  (define (repl-apropos query . env-opt)
    ;; Search for identifiers containing query as a substring
    (let* ([env  (if (pair? env-opt) (car env-opt) (interaction-environment))]
           [syms (environment-symbols env)]
           [q    (string-downcase query)])
      (filter
        (lambda (sym)
          (let ([s (string-downcase (symbol->string sym))])
            (string-contains s q)))
        (if (list? syms) syms '()))))

  (define (string-contains haystack needle)
    (let ([hn (string-length haystack)]
          [nn (string-length needle)])
      (let loop ([i 0])
        (cond
          [(> (+ i nn) hn) #f]
          [(string=? (substring haystack i (+ i nn)) needle) #t]
          [else (loop (+ i 1))]))))

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

  ;;; ========== REPL command type annotation ==========
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

  ;;; ========== Helpers (defined early for forward-reference safety) ==========
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

  ;;; ========== Command dispatch ==========
  (define (dispatch-command line env cfg)
    ;; Parses REPL commands starting with ","
    (let ([parts (string-split-first-word (string-trim line))])
      (let ([cmd  (car parts)]
            [rest (cdr parts)])
        (cond
          [(string=? cmd ",type")
           (guard (exn [#t (display (format "Error: ~a~n" exn))])
             (let* ([expr   (with-input-from-string rest read)]
                    [val    (eval expr env)]
                    [type-s (value->type-string val)])
               (display (colored cfg cyan type-s))
               (newline)))]

          [(string=? cmd ",time")
           (guard (exn [#t (display (format "Error: ~a~n" exn))])
             (let ([expr (with-input-from-string rest read)])
               (let* ([t0     (cpu-time)]
                      [result (eval expr env)]
                      [t1     (cpu-time)])
                 (repl-print result env cfg)
                 (display (colored cfg yellow
                   (format ";; ~a ms~n" (- t1 t0)))))))]

          [(string=? cmd ",doc")
           (let ([sym-str (string-trim rest)])
             (display (repl-doc (string->symbol sym-str)))
             (newline))]

          [(string=? cmd ",apropos")
           (let* ([q     (string-trim rest)]
                  [syms  (repl-apropos q env)])
             (if (null? syms)
               (display ";; no matches\n")
               (begin
                 (for-each (lambda (s)
                             (display (colored cfg green (symbol->string s)))
                             (display " "))
                           (take syms 20))
                 (newline))))]

          [(string=? cmd ",expand")
           (guard (exn [#t (display (format "Error: ~a~n" exn))])
             (let* ([expr (with-input-from-string rest read)]
                    [expanded (expand expr env)])
               (pretty-print expanded)))]

          [(string=? cmd ",pp")
           (guard (exn [#t (display (format "Error: ~a~n" exn))])
             (let* ([expr (with-input-from-string rest read)]
                    [val  (eval expr env)])
               (pretty-print val)))]

          [(string=? cmd ",load")
           (let ([path (string-trim rest)])
             (repl-load path env)
             (display (colored cfg green (format ";; loaded ~a~n" path))))]

          [(string=? cmd ",env")
           (for-each (lambda (s) (display s) (display " "))
                     (take (environment-symbols env) 50))
           (newline)]

          [(string=? cmd ",help")
           (display
             (string-append
               bold "Jerboa REPL Commands:\n" reset-color
               "  ,type expr     — show type of expression result\n"
               "  ,time expr     — measure evaluation time\n"
               "  ,doc sym       — show documentation\n"
               "  ,apropos str   — search for symbols\n"
               "  ,expand expr   — show macro expansion\n"
               "  ,pp expr       — pretty-print value\n"
               "  ,load path     — load a file\n"
               "  ,env           — list environment symbols\n"
               "  ,help          — show this help\n"
               "  ,quit          — exit REPL\n"))]

          [else
           (display (format ";; unknown command: ~a (try ,help)~n" cmd))]))))

  ;;; ========== REPL print ==========
  (define (repl-print val env cfg)
    (cond
      [(eq? val (void))
       (void)]  ; don't print void
      [else
       (display (colored cfg green ";; => "))
       (write val)
       (newline)]))

  (define (balanced? str)
    ;; Check if parentheses/brackets/braces are balanced
    (let loop ([chars (string->list str)] [depth 0])
      (cond
        [(< depth 0) #f]
        [(null? chars) (= depth 0)]
        [else
         (let ([c (car chars)])
           (cond
             [(or (char=? c #\() (char=? c #\[) (char=? c #\{))
              (loop (cdr chars) (+ depth 1))]
             [(or (char=? c #\)) (char=? c #\]) (char=? c #\}))
              (loop (cdr chars) (- depth 1))]
             [else
              (loop (cdr chars) depth)]))])))

  ;;; ========== REPL read ==========
  (define (repl-read-expr prompt-str port)
    ;; Read a complete s-expression, handling multi-line
    (display prompt-str)
    (flush-output-port (current-output-port))
    (let ([line (get-line port)])
      (if (eof-object? line)
        line
        (let ([trimmed (string-trim line)])
          (if (string=? trimmed "")
            trimmed
            ;; Check if balanced
            (let complete ([acc trimmed])
              (if (balanced? acc)
                acc
                (begin
                  ;; More input needed
                  (display "  ... ")
                  (flush-output-port (current-output-port))
                  (let ([next (get-line port)])
                    (if (eof-object? next)
                      acc
                      (complete (string-append acc "\n" next))))))))))))

  ;;; ========== Main REPL loop ==========
  (define (jerboa-repl . args)
    (let* ([cfg  (if (and (pair? args) (repl-config? (car args)))
                   (car args)
                   *default-config*)]
           [env  (interaction-environment)]
           [port (current-input-port)])
      ;; Welcome banner
      (display bold)
      (display "Jerboa REPL")
      (display reset-color)
      (display "  (type ,help for commands, ,quit to exit)\n")

      (let loop ()
        (let ([input (repl-read-expr (repl-config-prompt cfg) port)])
          (cond
            [(eof-object? input)
             (newline)
             (display "Goodbye.\n")]
            [(string=? (string-trim input) "")
             (loop)]
            [(string=? (string-trim input) ",quit")
             (display "Goodbye.\n")]
            [(and (> (string-length (string-trim input)) 0)
                  (char=? #\, (string-ref (string-trim input) 0)))
             ;; REPL command
             (dispatch-command (string-trim input) env cfg)
             (loop)]
            [else
             ;; Normal expression
             (guard (exn [#t
                          (display (colored cfg red "error: "))
                          (if (message-condition? exn)
                            (display (condition-message exn))
                            (write exn))
                          (newline)])
               (let* ([expr (with-input-from-string input read)]
                      [t0   (cpu-time)]
                      [val  (eval expr env)]
                      [t1   (cpu-time)])
                 (repl-print val env cfg)
                 (when (repl-config-show-time? cfg)
                   (display (colored cfg yellow
                     (format ";; ~a ms~n" (- t1 t0)))))))
             (loop)])))))

  ;; Pre-populate doc registry with common procedures
  (for-each
    (lambda (entry)
      (register-doc! (car entry) (cadr entry)))
    '((car     "(car pair) -> any\n  Return the first element of pair.")
      (cdr     "(cdr pair) -> any\n  Return the rest of pair.")
      (cons    "(cons a b) -> pair\n  Construct a pair.")
      (list    "(list x ...) -> list\n  Create a list.")
      (map     "(map proc list ...) -> list\n  Apply proc to each element.")
      (filter  "(filter pred list) -> list\n  Keep elements satisfying pred.")
      (fold-left  "(fold-left proc init list) -> any\n  Left fold.")
      (fold-right "(fold-right proc init list) -> any\n  Right fold.")
      (for-each "(for-each proc list ...) -> void\n  Apply proc for side effects.")
      (apply   "(apply proc arg ... list) -> any\n  Apply proc to argument list.")
      (values  "(values x ...) -> values\n  Return multiple values.")
      (call-with-values "(call-with-values producer consumer)\n  Multiple-value protocol.")
      (hash-ref  "(hash-ref ht key [default]) -> any\n  Look up key in hash table.")
      (hash-put! "(hash-put! ht key val) -> void\n  Set key in hash table.")
      (hash-get  "(hash-get ht key [default]) -> any\n  Get key, #f if missing.")
      (string-append "(string-append str ...) -> string\n  Concatenate strings.")
      (number->string "(number->string n [radix]) -> string")
      (string->number "(string->number str [radix]) -> number or #f")))

) ;; end library
