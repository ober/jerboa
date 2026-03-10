#!chezscheme
;;; getopt.sls -- Compat shim for Gerbil's :std/cli/getopt
;;; Command-line argument parsing with options, flags, arguments, and commands.

(library (std cli getopt)
  (export
    getopt
    getopt?
    getopt-object?
    getopt-error?
    getopt-parse
    getopt-display-help
    getopt-display-help-topic
    option
    flag
    command
    argument
    optional-argument
    rest-arguments
    call-with-getopt)

  (import (except (chezscheme) filter find make-hash-table hash-table? iota 1+ 1-)
          (only (jerboa runtime) make-hash-table hash-put!))

  ;; --- Option/Flag/Argument/Command records ---

  (define-record-type opt
    (fields name short long help default (mutable value) kind))
  ;; kind: 'option, 'flag, 'argument, 'optional-argument, 'rest-arguments

  (define-record-type cmd
    (fields name help options handler))

  (define-record-type getopt-obj
    (fields program options commands))

  (define-record-type getopt-err
    (fields message context))

  (define (getopt? x) (getopt-obj? x))
  (define (getopt-object? x) (getopt-obj? x))
  (define (getopt-error? x) (getopt-err? x))

  ;; --- Constructor helpers ---

  (define (option name . args)
    ;; (option "name" "-s" "--long" help: "..." default: val)
    (let ((parsed (parse-opt-args args)))
      (make-opt name (car parsed) (cadr parsed) (caddr parsed) (cadddr parsed) #f 'option)))

  (define (flag name . args)
    (let ((parsed (parse-opt-args args)))
      (make-opt name (car parsed) (cadr parsed) (caddr parsed) (or (cadddr parsed) #f) #f 'flag)))

  (define (argument name . args)
    (let ((parsed (parse-opt-args args)))
      (make-opt name #f #f (or (caddr parsed) "") (cadddr parsed) #f 'argument)))

  (define (optional-argument name . args)
    (let ((parsed (parse-opt-args args)))
      (make-opt name #f #f (or (caddr parsed) "") (cadddr parsed) #f 'optional-argument)))

  (define (rest-arguments name . args)
    (let ((parsed (parse-opt-args args)))
      (make-opt name #f #f (or (caddr parsed) "") (or (cadddr parsed) '()) #f 'rest-arguments)))

  (define (command name . args)
    ;; (command name help: "..." opts... handler)
    ;; Last arg is a lambda handler, preceding args are opts
    (let lp ((args args) (help #f) (opts '()))
      (cond
        ((null? args)
         (make-cmd name (or help "") (reverse opts) #f))
        ((and (symbol? (car args)) (string=? "help:" (symbol->string (car args))))
         (lp (cddr args) (cadr args) opts))
        ((procedure? (car args))
         (make-cmd name (or help "") (reverse opts) (car args)))
        ((opt? (car args))
         (lp (cdr args) help (cons (car args) opts)))
        (else
         (lp (cdr args) help opts)))))

  ;; Parse option constructor arguments: short long help: default:
  (define (parse-opt-args args)
    (let lp ((args args) (short #f) (long #f) (help #f) (default #f))
      (cond
        ((null? args)
         (list short long help default))
        ((and (string? (car args)) (> (string-length (car args)) 0)
              (char=? (string-ref (car args) 0) #\-))
         (if (and (> (string-length (car args)) 1)
                  (char=? (string-ref (car args) 1) #\-))
           (lp (cdr args) short (car args) help default)
           (lp (cdr args) (car args) long help default)))
        ((and (pair? args) (symbol? (car args))
              (string=? "help:" (symbol->string (car args))))
         (lp (cddr args) short long (cadr args) default))
        ((and (pair? args) (symbol? (car args))
              (string=? "default:" (symbol->string (car args))))
         (lp (cddr args) short long help (cadr args)))
        (else
         (lp (cdr args) short long help default)))))

  ;; --- getopt ---
  (define (getopt . specs)
    ;; specs is a mix of option/flag/argument/command objects
    (let lp ((specs specs) (program #f) (opts '()) (cmds '()))
      (cond
        ((null? specs)
         (make-getopt-obj program (reverse opts) (reverse cmds)))
        ((and (symbol? (car specs))
              (string=? "program:" (symbol->string (car specs))))
         (lp (cddr specs) (cadr specs) opts cmds))
        ((opt? (car specs))
         (lp (cdr specs) program (cons (car specs) opts) cmds))
        ((cmd? (car specs))
         (lp (cdr specs) program opts (cons (car specs) cmds)))
        (else
         (lp (cdr specs) program opts cmds)))))

  ;; --- getopt-parse ---
  (define (getopt-parse gopt args)
    ;; Returns: (values options rest-args) or raises getopt-err
    ;; options is an alist of (name . value) pairs
    (let ((opts (if (getopt-obj? gopt) (getopt-obj-options gopt) '()))
          (cmds (if (getopt-obj? gopt) (getopt-obj-commands gopt) '())))
      (parse-args opts cmds args)))

  (define (parse-args opts cmds args)
    (let lp ((args args) (result '()) (positionals '()) (pos-idx 0))
      (let ((pos-opts (filter (lambda (o) (memq (opt-kind o) '(argument optional-argument rest-arguments))) opts)))
        (cond
          ((null? args)
           ;; Fill in defaults for unset options
           (let ((result (fold-left
                           (lambda (acc o)
                             (if (assoc (opt-name o) acc)
                               acc
                               (cons (cons (opt-name o) (opt-default o)) acc)))
                           result
                           opts)))
             (values result '())))
          ;; -- flag or option
          ((and (string? (car args))
                (> (string-length (car args)) 1)
                (char=? (string-ref (car args) 0) #\-))
           (let ((arg (car args)))
             (cond
               ;; -- means end of options
               ((string=? arg "--")
                (let ((result (fold-left
                                (lambda (acc o)
                                  (if (assoc (opt-name o) acc)
                                    acc
                                    (cons (cons (opt-name o) (opt-default o)) acc)))
                                result
                                opts)))
                  (values result (cdr args))))
               ;; Find matching option/flag
               ((find-opt opts arg)
                => (lambda (o)
                     (case (opt-kind o)
                       ((flag)
                        (lp (cdr args) (cons (cons (opt-name o) #t) result) positionals pos-idx))
                       ((option)
                        (if (null? (cdr args))
                          (error 'getopt-parse (string-append "missing value for " arg))
                          (lp (cddr args)
                              (cons (cons (opt-name o) (cadr args)) result)
                              positionals pos-idx))))))
               (else
                (error 'getopt-parse (string-append "unknown option: " arg))))))
          ;; Check for command
          ((and (null? result) (pair? cmds)
                (find-cmd cmds (car args)))
           => (lambda (c)
                (let-values (((cmd-opts rest) (parse-args (cmd-options c) '() (cdr args))))
                  (values (cons (cons "command" (cmd-name c)) cmd-opts) rest))))
          ;; Positional argument
          (else
           (if (< pos-idx (length pos-opts))
             (let ((po (list-ref pos-opts pos-idx)))
               (case (opt-kind po)
                 ((rest-arguments)
                  (lp '() (cons (cons (opt-name po) args) result) positionals pos-idx))
                 (else
                  (lp (cdr args) (cons (cons (opt-name po) (car args)) result)
                      positionals (+ pos-idx 1)))))
             (lp (cdr args) result (cons (car args) positionals) pos-idx)))))))

  (define (find-opt opts arg)
    (find (lambda (o)
            (or (and (opt-short o) (string=? arg (opt-short o)))
                (and (opt-long o) (string=? arg (opt-long o)))))
          opts))

  (define (find-cmd cmds name)
    (let ((name-str (if (symbol? name) (symbol->string name) name)))
      (find (lambda (c)
              (let ((cn (cmd-name c)))
                (string=? name-str (if (symbol? cn) (symbol->string cn) cn))))
            cmds)))

  ;; --- getopt-display-help ---
  (define (getopt-display-help gopt . rest)
    (let ((port (if (pair? rest) (car rest) (current-output-port))))
      (when (getopt-obj-program gopt)
        (fprintf port "Usage: ~a [options]~n" (getopt-obj-program gopt)))
      (let ((opts (getopt-obj-options gopt))
            (cmds (getopt-obj-commands gopt)))
        (unless (null? opts)
          (fprintf port "~nOptions:~n")
          (for-each
            (lambda (o)
              (let ((short (or (opt-short o) ""))
                    (long (or (opt-long o) ""))
                    (help (or (opt-help o) "")))
                (cond
                  ((memq (opt-kind o) '(argument optional-argument rest-arguments))
                   (fprintf port "  ~a~30t~a~n" (opt-name o) help))
                  (else
                   (fprintf port "  ~a ~a~30t~a~n" short long help)))))
            opts))
        (unless (null? cmds)
          (fprintf port "~nCommands:~n")
          (for-each
            (lambda (c)
              (fprintf port "  ~a~30t~a~n" (cmd-name c) (cmd-help c)))
            cmds)))))

  (define (getopt-display-help-topic gopt topic . rest)
    (let ((port (if (pair? rest) (car rest) (current-output-port))))
      (let ((c (find-cmd (getopt-obj-commands gopt) topic)))
        (if c
          (begin
            (fprintf port "~a: ~a~n" (cmd-name c) (cmd-help c))
            (unless (null? (cmd-options c))
              (fprintf port "~nOptions:~n")
              (for-each
                (lambda (o)
                  (fprintf port "  ~a ~a~30t~a~n"
                    (or (opt-short o) "") (or (opt-long o) "") (or (opt-help o) "")))
                (cmd-options c))))
          (fprintf port "Unknown topic: ~a~n" topic)))))

  ;; --- call-with-getopt ---
  (define (call-with-getopt proc args . specs)
    ;; Gerbil convention: (proc cmd opt-hash)
    ;; cmd = command name symbol, opt-hash = hash table of options
    (let ((gopt (apply getopt specs)))
      (guard (exn (#t (fprintf (current-error-port) "Error: ~a~n" exn)
                      (getopt-display-help gopt (current-error-port))
                      (exit 1)))
        (let-values (((opts rest) (getopt-parse gopt args)))
          (let ((cmd-pair (assoc "command" opts))
                (ht (make-hash-table)))
            (for-each (lambda (pair)
                        (unless (string=? "command" (let ((k (car pair)))
                                                      (if (symbol? k) (symbol->string k) k)))
                          (hash-put! ht (car pair) (cdr pair))))
                      opts)
            (if cmd-pair
              (proc (cdr cmd-pair) ht)
              (proc #f ht)))))))

  ;; Helpers
  (define (find pred lst)
    (cond
      ((null? lst) #f)
      ((pred (car lst)) (car lst))
      (else (find pred (cdr lst)))))

  (define (filter pred lst)
    (cond
      ((null? lst) '())
      ((pred (car lst)) (cons (car lst) (filter pred (cdr lst))))
      (else (filter pred (cdr lst)))))

  ) ;; end library
