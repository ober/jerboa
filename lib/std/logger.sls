#!chezscheme
;;; :std/logger -- Simple logging to stderr with level filtering

(library (std logger)
  (export
    start-logger!
    current-logger
    current-logger-options
    current-log-directory
    make-logger-options
    logger-options?
    deflogger
    errorf
    warnf
    infof
    debugf
    verbosef)

  (import (except (chezscheme) errorf))

  ;; Log levels: 0=error, 1=warn, 2=info, 3=debug, 4=verbose
  (define-record-type logger-options
    (fields level output))

  (define current-logger-options
    (make-parameter (make-logger-options 2 (current-error-port))))

  (define current-logger
    (make-parameter #f))

  (define current-log-directory
    (make-parameter #f))

  (define (start-logger! . args)
    ;; (start-logger! level: 'info output: port)
    (let lp ((args args) (level 2) (output (current-error-port)))
      (cond
        ((null? args)
         (current-logger-options (make-logger-options level output))
         (current-logger #t))
        ((and (symbol? (car args)) (string=? "level:" (symbol->string (car args))))
         (lp (cddr args) (level->int (cadr args)) output))
        ((and (symbol? (car args)) (string=? "output:" (symbol->string (car args))))
         (lp (cddr args) level (cadr args)))
        (else (lp (cdr args) level output)))))

  (define (level->int sym)
    (case sym
      ((error) 0)
      ((warn warning) 1)
      ((info) 2)
      ((debug) 3)
      ((verbose) 4)
      (else 2)))

  (define (log-at level prefix fmt . args)
    (let ((opts (current-logger-options)))
      (when (<= level (logger-options-level opts))
        (let ((port (logger-options-output opts))
              (msg (apply format fmt args)))
          (fprintf port "[~a] ~a~n" prefix msg)
          (flush-output-port port)))))

  (define (errorf fmt . args) (apply log-at 0 "ERROR" fmt args))
  (define (warnf fmt . args) (apply log-at 1 "WARN" fmt args))
  (define (infof fmt . args) (apply log-at 2 "INFO" fmt args))
  (define (debugf fmt . args) (apply log-at 3 "DEBUG" fmt args))
  (define (verbosef fmt . args) (apply log-at 4 "VERBOSE" fmt args))

  ;; deflogger is a macro in Gerbil; here we just provide it as a no-op
  ;; that defines the logging functions in the current module.
  ;; Since we use globals, this is just a pass-through.
  (define-syntax deflogger
    (syntax-rules ()
      ((_ name)
       (begin))
      ((_ name args ...)
       (begin))))

  ) ;; end library
