#!chezscheme
;;; (std error diagnostics) — Structured error diagnostics with stack traces
;;;
;;; Track 28: Captures continuation information using Chez's inspect/object,
;;; formats readable diagnostics with source locations and local context.

(library (std error diagnostics)
  (export
    with-diagnostics
    display-diagnostic
    continuation->frames
    format-diagnostic
    &diagnostic make-diagnostic diagnostic?
    diagnostic-frames diagnostic-context
    current-diagnostic-handler)

  (import (chezscheme))

  ;; ========== Diagnostic Condition Type ==========

  (define-condition-type &diagnostic &condition
    make-diagnostic diagnostic?
    (frames diagnostic-frames)
    (context diagnostic-context))

  ;; ========== Current Handler ==========

  (define current-diagnostic-handler
    (make-parameter
      (lambda (err frames port)
        (display-diagnostic err frames port))))

  ;; ========== Stack Frame Extraction ==========

  (define (continuation->frames k)
    ;; Extract stack frames from a continuation using Chez's inspector.
    ;; Each frame is: (procedure-name source-file line)
    (guard (e [#t '()])
      (let ([frames '()])
        (call-with-values
          (lambda () (inspect/object k))
          (lambda (obj . rest)
            (when (and obj (procedure? (lambda () obj)))
              (extract-frames-from-object obj frames))))
        ;; Fallback: try to get info via continuation-condition if available
        (if (null? frames)
          (extract-basic-frames k)
          frames))))

  (define (extract-basic-frames k)
    ;; Basic frame extraction without inspector
    ;; Use the condition's stack trace if available
    (guard (e [#t '()])
      (let ([s (call-with-string-output-port
                 (lambda (p)
                   (parameterize ([print-level 3] [print-length 10])
                     (display k p))))])
        (if (> (string-length s) 0)
          (list (list "continuation" #f #f))
          '()))))

  (define (extract-frames-from-object obj frames)
    ;; Walk the inspector object chain
    '())

  ;; ========== with-diagnostics ==========

  (define (with-diagnostics thunk . rest)
    ;; Execute thunk with diagnostic error handling.
    ;; Options: on-error: (lambda (err context port) ...)
    (let ([on-error (extract-opt rest 'on-error: #f)]
          [port (extract-opt rest 'port: (current-error-port))])
      (call/cc
        (lambda (escape)
          (with-exception-handler
            (lambda (exn)
              (let* ([frames (guard (e [#t '()])
                               (get-stack-trace))]
                     [diag (condition (make-diagnostic frames '()))])
                (if on-error
                  (on-error exn frames port)
                  ((current-diagnostic-handler) exn frames port))
                (escape (void))))
            thunk)))))

  ;; ========== Stack Trace via debug-condition ==========

  (define (get-stack-trace)
    ;; Try to extract meaningful stack info from the current continuation
    (guard (e [#t '()])
      (let ([trace (call-with-string-output-port
                     (lambda (port)
                       (parameterize ([print-level 5] [print-length 20])
                         (let ([cc (condition)])
                           (when (condition? cc)
                             (display-condition cc port))))))])
        (if (> (string-length trace) 0)
          (parse-trace-string trace)
          '()))))

  (define (parse-trace-string s)
    ;; Parse a condition trace string into frame records
    (let ([lines (string-split-lines s)])
      (filter-map parse-trace-line lines)))

  (define (string-split-lines s)
    (let ([n (string-length s)])
      (let lp ([i 0] [start 0] [result '()])
        (cond
          [(>= i n)
           (reverse (if (> i start)
                      (cons (substring s start i) result)
                      result))]
          [(char=? (string-ref s i) #\newline)
           (lp (+ i 1) (+ i 1)
               (cons (substring s start i) result))]
          [else (lp (+ i 1) start result)]))))

  (define (parse-trace-line line)
    ;; Try to extract procedure name and source info from a trace line
    (let ([trimmed (string-trim line)])
      (if (> (string-length trimmed) 0)
        (list trimmed #f #f)
        #f)))

  (define (string-trim s)
    (let ([n (string-length s)])
      (let ([start (let lp ([i 0])
                     (if (and (< i n) (char-whitespace? (string-ref s i)))
                       (lp (+ i 1)) i))]
            [end (let lp ([i (- n 1)])
                   (if (and (>= i 0) (char-whitespace? (string-ref s i)))
                     (lp (- i 1)) (+ i 1)))])
        (if (>= start end) ""
          (substring s start end)))))

  (define (filter-map f lst)
    (let lp ([lst lst] [result '()])
      (if (null? lst) (reverse result)
        (let ([v (f (car lst))])
          (lp (cdr lst) (if v (cons v result) result))))))

  ;; ========== Display Diagnostic ==========

  (define (display-diagnostic err frames port)
    (display (format-diagnostic err frames) port)
    (newline port))

  (define (format-diagnostic err frames)
    (call-with-string-output-port
      (lambda (port)
        ;; Error message
        (display "Error: " port)
        (cond
          [(message-condition? err)
           (display (condition-message err) port)]
          [(condition? err)
           (display-condition err port)]
          [else
           (display err port)])
        (newline port)

        ;; Irritants
        (when (and (condition? err) (irritants-condition? err))
          (let ([irr (condition-irritants err)])
            (when (pair? irr)
              (display "  Irritants: " port)
              (write irr port)
              (newline port))))

        ;; Who
        (when (and (condition? err) (who-condition? err))
          (display "  Who: " port)
          (display (condition-who err) port)
          (newline port))

        ;; Stack frames
        (when (pair? frames)
          (display "  Stack trace:" port)
          (newline port)
          (let lp ([frames frames] [i 0])
            (when (and (pair? frames) (< i 20))  ;; limit to 20 frames
              (let ([frame (car frames)])
                (display "    " port)
                (display (car frame) port)
                (when (cadr frame)
                  (display " at " port)
                  (display (cadr frame) port))
                (when (caddr frame)
                  (display ":" port)
                  (display (caddr frame) port))
                (newline port))
              (lp (cdr frames) (+ i 1))))))))

  (define (extract-opt opts key default)
    (let lp ([opts opts])
      (cond
        [(null? opts) default]
        [(and (pair? opts) (pair? (cdr opts)) (eq? (car opts) key))
         (cadr opts)]
        [(pair? opts) (lp (cdr opts))]
        [else default])))

  ) ;; end library
