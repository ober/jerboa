#!chezscheme
;;; :std/misc/process -- Process execution utilities

(library (std misc process)
  (export
    run-process
    run-process/batch)

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

  ) ;; end library
