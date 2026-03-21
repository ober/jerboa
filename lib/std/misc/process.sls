#!chezscheme
;;; :std/misc/process -- Process execution utilities

(library (std misc process)
  (export
    run-process
    run-process/batch
    run-process/exec
    filter-with-process

    ;; Process ports (Gambit-compatible subprocess I/O)
    open-input-process
    open-output-process
    open-process
    process-port-pid
    process-port?
    process-port-status
    process-port-rec-stdin-port
    process-port-rec-stdout-port
    process-port-rec-stderr-port

    ;; Process control
    process-kill
    tty?)

  (import (chezscheme))

  (define (run-process args . rest)
    ;; Run a process and return its stdout as a string.
    ;; args: list of strings (command and arguments)
    ;; Keywords: stdin-redirection: #f, stdout-redirection: #t, stderr-redirection: #f,
    ;;           coprocess: #f, environment: #f, directory: #f
    ;; For Chez, we use process and open-process-ports
    (let* ((cmd (build-command-string args))
           (show-console (extract-keyword rest 'show-console: #f))
           (dir (extract-keyword rest 'directory: #f))
           (full-cmd (if dir
                       (string-append "cd " (shell-quote dir) " && " cmd)
                       cmd)))
      (let-values (((to-stdin from-stdout from-stderr pid)
                    (open-process-ports full-cmd 'line (native-transcoder))))
        (close-port to-stdin)
        (let ((output (read-all from-stdout)))
          (close-port from-stdout)
          (close-port from-stderr)
          output))))

  (define (run-process/batch args . rest)
    ;; Run a process and return exit status (0 = success)
    (let* ((cmd (build-command-string args))
           (dir (extract-keyword rest 'directory: #f))
           (full-cmd (if dir
                       (string-append "cd " (shell-quote dir) " && " cmd)
                       cmd)))
      (system full-cmd)))

  (define (run-process/exec args . rest)
    ;; Run a process WITHOUT shell interpolation.
    ;; args: list of strings (command and arguments)
    ;; Each argument is individually shell-quoted to prevent injection.
    ;; No shell metacharacters are interpreted.
    ;; Keywords: directory: path, stdin-data: string
    (unless (and (list? args) (pair? args) (for-all string? args))
      (error 'run-process/exec "args must be a non-empty list of strings" args))
    (let* ([dir (extract-keyword rest 'directory: #f)]
           [stdin-data (extract-keyword rest 'stdin-data: #f)]
           ;; Each argument is individually quoted — no shell expansion
           [cmd (string-join (map strict-shell-quote args) " ")]
           [full-cmd (if dir
                       (string-append "cd " (strict-shell-quote dir) " && " cmd)
                       cmd)])
      (let-values ([(to-stdin from-stdout from-stderr pid)
                    (open-process-ports full-cmd 'line (native-transcoder))])
        (when stdin-data
          (display stdin-data to-stdin)
          (flush-output-port to-stdin))
        (close-port to-stdin)
        (let ([output (read-all from-stdout)])
          (close-port from-stdout)
          (close-port from-stderr)
          output))))

  (define (strict-shell-quote s)
    ;; Strictly quote a string for shell: wrap in single quotes,
    ;; escape embedded single quotes. This prevents ALL shell
    ;; metacharacter interpretation.
    (string-append "'" (string-replace-all s "'" "'\"'\"'") "'"))

  (define (build-command-string args)
    (if (string? args)
      args
      (string-join (map shell-quote args) " ")))

  (define (shell-quote s)
    ;; Simple shell quoting
    (if (and (not (string-contains? s "'"))
             (not (string-contains? s " "))
             (not (string-contains? s "\""))
             (not (string-contains? s "$"))
             (not (string-contains? s "`"))
             (not (string-contains? s "\\"))
             (> (string-length s) 0))
      s
      (string-append "'" (string-replace-all s "'" "'\"'\"'") "'")))

  (define (string-contains? s sub)
    (let ((slen (string-length s))
          (sublen (string-length sub)))
      (let lp ((i 0))
        (cond
          ((> (+ i sublen) slen) #f)
          ((string=? (substring s i (+ i sublen)) sub) #t)
          (else (lp (+ i 1)))))))

  (define (string-replace-all s old new)
    (let ((olen (string-length old))
          (slen (string-length s)))
      (let lp ((i 0) (parts '()))
        (cond
          ((> (+ i olen) slen)
           (apply string-append (reverse (cons (substring s i slen) parts))))
          ((string=? (substring s i (+ i olen)) old)
           (lp (+ i olen) (cons new parts)))
          (else
           (let lp2 ((j (+ i 1)))
             (cond
               ((> (+ j olen) slen)
                (apply string-append (reverse (cons (substring s i slen) parts))))
               ((string=? (substring s j (+ j olen)) old)
                (lp j (cons (substring s i j) parts)))
               (else (lp2 (+ j 1))))))))))

  (define (string-join lst sep)
    (cond
      ((null? lst) "")
      ((null? (cdr lst)) (car lst))
      (else
       (let lp ((rest (cdr lst)) (acc (car lst)))
         (if (null? rest) acc
           (lp (cdr rest) (string-append acc sep (car rest))))))))

  (define (extract-keyword args key default)
    (let lp ((args args))
      (cond
        ((null? args) default)
        ((and (symbol? (car args))
              (string=? (symbol->string (car args))
                        (symbol->string key)))
         (if (pair? (cdr args)) (cadr args) default))
        (else (lp (cdr args))))))

  (define (read-all port)
    (let lp ((chunks '()))
      (let ((buf (get-string-n port 4096)))
        (if (eof-object? buf)
          (if (null? chunks)
            ""
            (apply string-append (reverse chunks)))
          (lp (cons buf chunks))))))

  ;; ========== Process Ports (Gambit-compatible) ==========
  ;; These wrap Chez's open-process-ports to provide the simpler
  ;; Gambit API used by Gerbil applications.

  (define-record-type process-port-rec
    (fields
      (immutable stdin-port)    ;; port to write to process stdin (or #f)
      (immutable stdout-port)   ;; port to read process stdout (or #f)
      (immutable stderr-port)   ;; port to read process stderr (or #f)
      (immutable pid)           ;; process id
      (mutable status))         ;; exit status (set when reaped)
    (sealed #t))

  (define (process-port? x) (process-port-rec? x))
  (define (process-port-pid pp) (process-port-rec-pid pp))
  (define (process-port-status pp) (process-port-rec-status pp))

  (define (keyword-sym? x)
    (and (symbol? x)
         (let ([s (symbol->string x)])
           (and (> (string-length s) 0)
                (char=? (string-ref s (- (string-length s) 1)) #\:)))))

  (define (parse-process-settings args)
    ;; Parse Gambit-style open-process settings.
    ;; args can be:
    ;;   - a string: the shell command
    ;;   - a list of strings: command + arguments
    ;;   - a keyword plist: (path: "prog" arguments: '(...) directory: d ...)
    ;; Returns (values cmd-string dir)
    (cond
      ((string? args) (values args #f))
      ((and (pair? args) (keyword-sym? (car args)))
       ;; Keyword plist: extract path, arguments, directory
       (let* ((path (extract-keyword args 'path: #f))
              (arguments (extract-keyword args 'arguments: '()))
              (directory (extract-keyword args 'directory: #f))
              (all-args (if path (cons path arguments) arguments))
              (cmd (build-command-string all-args)))
         (values cmd directory)))
      (else
       ;; List of strings
       (values (build-command-string args) #f))))

  (define (open-input-process args)
    ;; Run a command, return a textual input port connected to its stdout.
    (let-values ([(cmd dir) (parse-process-settings args)])
      (let* ([full-cmd (if dir (string-append "cd " (shell-quote dir) " && " cmd) cmd)])
        (let-values ([(to-stdin from-stdout from-stderr pid)
                      (open-process-ports full-cmd 'line (native-transcoder))])
          (close-port to-stdin)
          (close-port from-stderr)
          from-stdout))))

  (define (open-output-process args)
    ;; Run a command, return a textual output port connected to its stdin.
    (let-values ([(cmd dir) (parse-process-settings args)])
      (let* ([full-cmd (if dir (string-append "cd " (shell-quote dir) " && " cmd) cmd)])
        (let-values ([(to-stdin from-stdout from-stderr pid)
                      (open-process-ports full-cmd 'line (native-transcoder))])
          (close-port from-stdout)
          (close-port from-stderr)
          to-stdin))))

  (define (open-process args)
    ;; Run a command, return a process-port record with stdin/stdout/stderr.
    ;; Accepts string, list-of-strings, or Gambit keyword plist.
    (let-values ([(cmd dir) (parse-process-settings args)])
      (let* ([full-cmd (if dir (string-append "cd " (shell-quote dir) " && " cmd) cmd)])
        (let-values ([(to-stdin from-stdout from-stderr pid)
                      (open-process-ports full-cmd 'line (native-transcoder))])
          (make-process-port-rec to-stdin from-stdout from-stderr pid #f)))))

  (define (filter-with-process command writer reader . rest)
    ;; Run COMMAND (list of strings or string), pipe input via WRITER,
    ;; and return the result of calling READER on the process stdout.
    ;; Keyword: directory: dir
    (let* ((dir (extract-keyword rest 'directory: #f))
           (cmd (build-command-string command))
           (full-cmd (if dir
                       (string-append "cd " (shell-quote dir) " && " cmd)
                       cmd)))
      (let-values (((to-stdin from-stdout from-stderr pid)
                    (open-process-ports full-cmd 'block (native-transcoder))))
        (writer to-stdin)
        (flush-output-port to-stdin)
        (close-port to-stdin)
        (let ((result (reader from-stdout)))
          (close-port from-stdout)
          (close-port from-stderr)
          result))))

  ;; ========== Process Control ==========

  (define _libc-loaded
    (let ((v (getenv "JEMACS_STATIC")))
      (if (and v (not (string=? v "")) (not (string=? v "0")))
          #f
          (load-shared-object "libc.so.6"))))

  (define c-kill (foreign-procedure "kill" (int int) int))
  (define c-isatty (foreign-procedure "isatty" (int) int))

  ;; Send a signal to a process. Default signal is SIGTERM (15).
  (define process-kill
    (case-lambda
      [(pid) (process-kill pid 15)]
      [(pid sig) (c-kill pid sig)]))

  ;; Check if a port (or fd number) is connected to a terminal
  (define (tty? x)
    (cond
      [(fixnum? x) (= (c-isatty x) 1)]
      [(eq? x (current-input-port)) (= (c-isatty 0) 1)]
      [(eq? x (current-output-port)) (= (c-isatty 1) 1)]
      [(eq? x (current-error-port)) (= (c-isatty 2) 1)]
      [else #f]))

  ) ;; end library
