#!chezscheme
;;; (std log) -- Structured logging with sinks
;;;
;;; Provides log levels, structured fields, and pluggable sinks
;;; (console, file, JSON).  The current logger is a thread-local
;;; parameter so dynamic scoping works naturally with `with-logger`.

(library (std log)
  (export
    ;; Logger construction / inspection
    make-logger logger? logger-level logger-fields
    ;; Logging procedures
    log-debug log-info log-warn log-error log-fatal
    ;; Dynamic binding
    with-logger current-logger
    ;; Sink management
    add-sink! make-console-sink make-file-sink make-json-sink
    ;; Level predicate
    log-level?)

  (import (chezscheme))

  ;;; ========== Level ordering ==========
  ;; debug=0 info=1 warn=2 error=3 fatal=4
  (define (level->int lvl)
    (case lvl
      ((debug)  0)
      ((info)   1)
      ((warn)   2)
      ((error)  3)
      ((fatal)  4)
      (else (error 'log "unknown level" lvl))))

  (define (level->string lvl)
    (case lvl
      ((debug) "DEBUG")
      ((info)  "INFO")
      ((warn)  "WARN")
      ((error) "ERROR")
      ((fatal) "FATAL")
      (else    "?")))

  (define (log-level? x)
    (and (memq x '(debug info warn error fatal)) #t))

  ;;; ========== Logger record ==========
  ;; level   — minimum level to emit (symbol)
  ;; sinks   — mutable list of sink procedures
  ;; fields  — alist of global structured fields
  (define-record-type %logger
    (fields level (mutable sinks) fields)
    (protocol
      (lambda (new)
        (lambda (level fields)
          (new level '() fields)))))

  (define (logger? x) (%logger? x))
  (define (logger-level lg) (%logger-level lg))
  (define (logger-fields lg) (%logger-fields lg))

  ;;; ========== Current logger parameter ==========
  (define current-logger
    (make-parameter #f))

  (define-syntax with-logger
    (syntax-rules ()
      [(_ lg body ...)
       (parameterize ([current-logger lg])
         body ...)]))

  ;;; ========== make-logger ==========
  ;; (make-logger level)         — no extra fields
  ;; (make-logger level k1 v1 …) — extra fields baked in
  (define (make-logger level . kv)
    (unless (log-level? level)
      (error 'make-logger "invalid log level" level))
    (let loop ([lst kv] [fields '()])
      (if (null? lst)
        (make-%logger level (reverse fields))
        (if (null? (cdr lst))
          (error 'make-logger "odd number of key/value arguments")
          (loop (cddr lst)
                (cons (cons (car lst) (cadr lst)) fields))))))

  ;;; ========== add-sink! ==========
  (define (add-sink! lg sink)
    (%logger-sinks-set! lg (append (%logger-sinks lg) (list sink))))

  ;;; ========== Internal: emit a log record ==========
  ;; A record is an alist:
  ;;   (timestamp . <time>) (level . <symbol>) (message . <string>)
  ;;   followed by any extra fields.
  (define (emit! lg level message extra-fields)
    (when (>= (level->int level) (level->int (%logger-level lg)))
      (let* ([ts  (current-time)]
             [rec (append
                    (list (cons 'timestamp ts)
                          (cons 'level     level)
                          (cons 'message   message))
                    (%logger-fields lg)
                    extra-fields)])
        (for-each (lambda (sink) (sink rec)) (%logger-sinks lg)))))

  ;;; ========== Logging macros / procedures ==========
  ;; (log-info logger "msg" 'key val …)
  (define (parse-kv who lst)
    (let loop ([lst lst] [acc '()])
      (if (null? lst)
        (reverse acc)
        (if (null? (cdr lst))
          (error who "odd number of key/value field arguments")
          (loop (cddr lst)
                (cons (cons (car lst) (cadr lst)) acc))))))

  (define (log-at level lg msg . kv)
    (let ([logger (or lg (current-logger))])
      (unless logger
        (error 'log "no current logger — pass a logger or use with-logger"))
      (emit! logger level msg (parse-kv 'log-at kv))))

  (define (log-debug lg msg . kv) (apply log-at 'debug lg msg kv))
  (define (log-info  lg msg . kv) (apply log-at 'info  lg msg kv))
  (define (log-warn  lg msg . kv) (apply log-at 'warn  lg msg kv))
  (define (log-error lg msg . kv) (apply log-at 'error lg msg kv))
  (define (log-fatal lg msg . kv) (apply log-at 'fatal lg msg kv))

  ;;; ========== Sinks ==========

  ;; Timestamp → "HH:MM:SS" approximation using seconds
  (define (time->string ts)
    (let* ([secs (time-second ts)]
           [h    (mod (div secs 3600) 24)]
           [m    (mod (div secs 60) 60)]
           [s    (mod secs 60)])
      (format "~2,'0d:~2,'0d:~2,'0d" h m s)))

  ;; Console sink: "[LEVEL] HH:MM:SS  message  key=val …"
  (define (make-console-sink . port-opt)
    (let ([port (if (pair? port-opt) (car port-opt) (current-output-port))])
      (lambda (rec)
        (let ([level   (cdr (assq 'level   rec))]
              [ts      (cdr (assq 'timestamp rec))]
              [msg     (cdr (assq 'message rec))])
          (let ([fields (filter (lambda (p)
                                  (not (memq (car p) '(timestamp level message))))
                                rec)])
            (fprintf port "[~a] ~a  ~a"
              (level->string level)
              (time->string ts)
              msg)
            (for-each (lambda (p)
                        (fprintf port "  ~a=~s" (car p) (cdr p)))
                      fields)
            (newline port)
            (flush-output-port port))))))

  ;; File sink: same format as console but to a file path
  (define (make-file-sink path)
    (let ([port (open-file-output-port
                  path
                  (file-options append)
                  (buffer-mode line)
                  (make-transcoder (utf-8-codec)))])
      (make-console-sink port)))

  ;; JSON sink: one JSON object per line
  (define (make-json-sink . port-opt)
    (let ([port (if (pair? port-opt) (car port-opt) (current-output-port))])
      (lambda (rec)
        (display "{" port)
        (let loop ([pairs rec] [first? #t])
          (unless (null? pairs)
            (unless first? (display "," port))
            (let ([k (car (car pairs))]
                  [v (cdr (car pairs))])
              (fprintf port "\"~a\":~a" k (json-encode v port)))
            (loop (cdr pairs) #f)))
        (display "}" port)
        (newline port)
        (flush-output-port port))))

  (define (json-encode v port)
    (cond
      [(string? v)  (format "\"~a\"" (json-escape v))]
      [(symbol? v)  (format "\"~a\"" (symbol->string v))]
      [(number? v)  (number->string v)]
      [(boolean? v) (if v "true" "false")]
      [(time? v)    (format "~s" (time-second v))]
      [else         (format "\"~a\"" v)]))

  (define (json-escape s)
    ;; Escape double-quotes and backslashes
    (let loop ([i 0] [acc '()])
      (if (= i (string-length s))
        (list->string (reverse acc))
        (let ([c (string-ref s i)])
          (loop (+ i 1)
                (case c
                  ((#\") (cons #\" (cons #\\ acc)))
                  ((#\\) (cons #\\ (cons #\\ acc)))
                  (else  (cons c acc))))))))

) ;; end library
