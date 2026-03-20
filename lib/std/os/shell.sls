#!chezscheme
;;; (std os shell) -- Shell Command Execution
;;;
;;; High-level shell command utilities for scripting:
;;;   - shell: run command, return stdout string
;;;   - shell!: run command, check exit status, raise on failure
;;;   - shell/lines: run command, return list of lines
;;;   - shell/status: run command, return (values stdout stderr exit-code)
;;;   - shell-pipe: pipe multiple commands together
;;;   - shell-env: run with custom environment variables
;;;   - shell-capture: capture both stdout and stderr
;;;
;;; Usage:
;;;   (import (std os shell))
;;;   (shell "ls -la")          ; => "total 4\n..."
;;;   (shell! "make build")     ; raises on non-zero exit
;;;   (shell/lines "ls")        ; => ("file1" "file2" ...)
;;;   (shell-pipe "ls" "grep .ss" "wc -l")  ; => "5\n"

(library (std os shell)
  (export
    shell
    shell!
    shell/lines
    shell/status
    shell-pipe
    shell-env
    shell-capture
    shell-async
    shell-async-wait
    shell-async?
    shell-async-pid
    shell-async-stdout
    shell-async-stderr
    shell-quote)

  (import (chezscheme))

  ;; ========== Core: shell ==========
  (define shell
    (case-lambda
      [(cmd) (shell cmd #f)]
      [(cmd dir)
       (let ([full (if dir (string-append "cd " (sq dir) " && " cmd) cmd)])
         (let-values ([(to-stdin from-stdout from-stderr pid)
                       (open-process-ports full 'line (native-transcoder))])
           (close-port to-stdin)
           (let ([out (read-all from-stdout)])
             (close-port from-stdout)
             (close-port from-stderr)
             out)))]))

  ;; ========== shell! — raises on failure ==========
  (define shell!
    (case-lambda
      [(cmd) (shell! cmd #f)]
      [(cmd dir)
       (let-values ([(stdout stderr code) (shell/status cmd dir)])
         (unless (= code 0)
           (error 'shell! (string-append "command failed (exit " (number->string code) "): " cmd
                                         (if (string=? stderr "") "" (string-append "\n" stderr)))))
         stdout)]))

  ;; ========== shell/lines — return list of lines ==========
  (define shell/lines
    (case-lambda
      [(cmd) (shell/lines cmd #f)]
      [(cmd dir)
       (let ([out (shell cmd dir)])
         (if (string=? out "")
           '()
           (split-lines (strip-trailing-newline out))))]))

  ;; ========== shell/status — return stdout, stderr, exit code ==========
  (define shell/status
    (case-lambda
      [(cmd) (shell/status cmd #f)]
      [(cmd dir)
       (let* ([full (if dir (string-append "cd " (sq dir) " && " cmd) cmd)]
              ;; Redirect to temp files and capture exit code
              [stdout-file (format "/tmp/jerboa-sh-out-~a" (random 999999999))]
              [stderr-file (format "/tmp/jerboa-sh-err-~a" (random 999999999))]
              [wrapper (format "(~a) >~a 2>~a; echo $?" full (sq stdout-file) (sq stderr-file))]
              )
         (let-values ([(to-stdin from-stdout from-stderr pid)
                       (open-process-ports wrapper 'line (native-transcoder))])
           (close-port to-stdin)
           (let* ([exit-str (string-trim (read-all from-stdout))]
                  [exit-code (or (string->number exit-str) 1)])
             (close-port from-stdout)
             (close-port from-stderr)
             (let ([stdout (read-file-safe stdout-file)]
                   [stderr (read-file-safe stderr-file)])
               (delete-file-safe stdout-file)
               (delete-file-safe stderr-file)
               (values stdout stderr exit-code)))))]))

  ;; ========== shell-pipe — pipe multiple commands ==========
  (define (shell-pipe . cmds)
    (if (null? cmds)
      ""
      (shell (string-join-with cmds " | "))))

  ;; ========== shell-env — run with environment variables ==========
  (define (shell-env cmd env-alist)
    ;; env-alist: ((name . value) ...)
    ;; Uses export to make vars available to subprocesses
    (let ([exports (apply string-append
                    (map (lambda (pair)
                           (string-append "export " (car pair) "=" (sq (cdr pair)) "; "))
                         env-alist))])
      (shell (string-append exports cmd))))

  ;; ========== shell-capture — return (values stdout stderr) ==========
  (define shell-capture
    (case-lambda
      [(cmd) (shell-capture cmd #f)]
      [(cmd dir)
       (let-values ([(stdout stderr code) (shell/status cmd dir)])
         (values stdout stderr))]))

  ;; ========== shell-async — run in background ==========
  (define-record-type shell-async-rec
    (fields (immutable pid)
            (immutable stdin-port)
            (immutable stdout-port)
            (immutable stderr-port)
            (mutable exit-code))
    (sealed #t))

  (define (shell-async? x) (shell-async-rec? x))
  (define (shell-async-pid x) (shell-async-rec-pid x))

  (define (shell-async-stdout proc)
    (read-all (shell-async-rec-stdout-port proc)))

  (define (shell-async-stderr proc)
    (read-all (shell-async-rec-stderr-port proc)))

  (define (shell-async cmd)
    (let-values ([(to-stdin from-stdout from-stderr pid)
                  (open-process-ports cmd 'line (native-transcoder))])
      (close-port to-stdin)
      (make-shell-async-rec pid #f from-stdout from-stderr #f)))

  (define (shell-async-wait proc)
    ;; Read all output and return (values stdout stderr)
    (let ([out (read-all (shell-async-rec-stdout-port proc))]
          [err (read-all (shell-async-rec-stderr-port proc))])
      (close-port (shell-async-rec-stdout-port proc))
      (close-port (shell-async-rec-stderr-port proc))
      (values out err)))

  ;; ========== shell-quote ==========
  (define (shell-quote str)
    (sq str))

  ;; ========== Helpers ==========
  (define (sq s)
    ;; Single-quote shell escaping
    (if (and (> (string-length s) 0)
             (not (string-contains-char? s #\'))
             (not (string-contains-char? s #\space))
             (not (string-contains-char? s #\$))
             (not (string-contains-char? s #\`))
             (not (string-contains-char? s #\\))
             (not (string-contains-char? s #\")))
      s
      (string-append "'" (string-replace-all* s "'" "'\"'\"'") "'")))

  (define (string-contains-char? s c)
    (let ([n (string-length s)])
      (let loop ([i 0])
        (cond
          [(= i n) #f]
          [(char=? (string-ref s i) c) #t]
          [else (loop (+ i 1))]))))

  (define (string-replace-all* s old new)
    (let ([olen (string-length old)]
          [slen (string-length s)])
      (let loop ([i 0] [parts '()])
        (cond
          [(> (+ i olen) slen)
           (apply string-append (reverse (cons (substring s i slen) parts)))]
          [(string=? (substring s i (+ i olen)) old)
           (loop (+ i olen) (cons new parts))]
          [else (loop (+ i 1) (cons (string (string-ref s i)) parts))]))))

  (define (string-join-with lst sep)
    (cond
      [(null? lst) ""]
      [(null? (cdr lst)) (car lst)]
      [else (let loop ([rest (cdr lst)] [acc (car lst)])
              (if (null? rest) acc
                (loop (cdr rest) (string-append acc sep (car rest)))))]))

  (define (read-all port)
    (let loop ([chunks '()])
      (let ([buf (get-string-n port 4096)])
        (if (eof-object? buf)
          (if (null? chunks) ""
            (apply string-append (reverse chunks)))
          (loop (cons buf chunks))))))

  (define (string-trim s)
    (let* ([n (string-length s)]
           [start (let loop ([i 0])
                    (if (or (= i n) (not (char-whitespace? (string-ref s i)))) i
                      (loop (+ i 1))))]
           [end (let loop ([i (- n 1)])
                  (if (or (< i 0) (not (char-whitespace? (string-ref s i)))) (+ i 1)
                    (loop (- i 1))))])
      (if (>= start end) "" (substring s start end))))

  (define (split-lines s)
    (let ([n (string-length s)])
      (let loop ([i 0] [start 0] [acc '()])
        (cond
          [(= i n) (reverse (cons (substring s start n) acc))]
          [(char=? (string-ref s i) #\newline)
           (loop (+ i 1) (+ i 1) (cons (substring s start i) acc))]
          [else (loop (+ i 1) start acc)]))))

  (define (strip-trailing-newline s)
    (let ([n (string-length s)])
      (if (and (> n 0) (char=? (string-ref s (- n 1)) #\newline))
        (substring s 0 (- n 1))
        s)))

  (define (read-file-safe path)
    (guard (exn [#t ""])
      (call-with-input-file path
        (lambda (p) (read-all p)))))

  (define (delete-file-safe path)
    (guard (exn [#t (void)])
      (delete-file path)))

) ;; end library
