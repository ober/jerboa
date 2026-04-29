#!chezscheme
;;; binary-entry.ss — Default entry point compiled into `make binary` output.
;;;
;;; With no args: starts the Jerboa REPL.
;;; With one arg ending in .ss: loads that script.
;;; --version / -v: prints version.

(import (except (chezscheme) make-hash-table hash-table? sort sort! printf fprintf
                 path-extension path-absolute? with-input-from-string
                 with-output-to-string iota 1+ 1- partition make-date make-time
                 meta atom?)
        (jerboa prelude))

(let ([args (cdr (command-line))])
  (cond
    [(null? args)
     (displayln "Jerboa Scheme — type (exit) to quit")
     (let loop ()
       (display "jerboa> ")
       (flush-output-port (current-output-port))
       (let ([form (read)])
         (cond
           [(eof-object? form) (newline)]
           [else
            (guard (exn [#t (display "Error: ")
                            (display-condition exn)
                            (newline)])
              (let ([result (eval form (interaction-environment))])
                (unless (eq? result (void))
                  (write result) (newline))))
            (loop)])))]
    [(or (string=? (car args) "--version")
         (string=? (car args) "-v"))
     (displayln "jerboa-bin 0.1.0")]
    [(or (string=? (car args) "--help")
         (string=? (car args) "-h"))
     (displayln "Usage: jerboa-bin [<script.ss> | --version | --help]")
     (displayln "  no args         start REPL")
     (displayln "  <script.ss>     load and run a Scheme script")
     (displayln "  --version, -v   print version")
     (displayln "  --help, -h      print this help")]
    [else
     (load (car args))]))
