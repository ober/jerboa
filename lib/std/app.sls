#!chezscheme
;;; (std app) — Safe program loading without threading hacks
;;;
;;; Track 23: Separates boot-time initialization from runtime startup,
;;; enabling thread creation in the main phase. Provides clean argument
;;; passing that avoids Chez's -c flag conflict.

(library (std app)
  (export
    define-application
    app-arguments
    current-app-name
    app-run!
    make-app
    app?
    app-name       ;; record accessor: (app-name app-record) -> string
    app-init-proc
    app-main-proc)

  (import (chezscheme))

  ;; ========== Application Record ==========

  (define-record-type app
    (fields
      (immutable name)
      (immutable init-proc)    ;; (lambda () ...) — runs during boot, no threads
      (immutable main-proc))   ;; (lambda (args) ...) — runs after boot, threads OK
    (protocol
      (lambda (new)
        (lambda (name init main)
          (new name init main)))))

  ;; Global registry for the current application
  (define *current-app* #f)
  (define *app-arguments* '())
  (define *current-app-name* "")

  (define (app-arguments) *app-arguments*)
  (define (current-app-name) *current-app-name*)

  ;; ========== define-application ==========
  (define-syntax define-application
    (lambda (stx)
      (syntax-case stx ()
        [(_ name-expr clauses ...)
         (let ([init-expr #'(lambda () (void))]
               [main-expr #'(lambda (args) (void))])
           (let lp ([clauses (syntax->list #'(clauses ...))])
             (cond
               [(null? clauses) (void)]
               [(and (>= (length clauses) 2)
                     (identifier? (car clauses))
                     (free-identifier=? (car clauses) #'init:))
                (set! init-expr (cadr clauses))
                (lp (cddr clauses))]
               [(and (>= (length clauses) 2)
                     (identifier? (car clauses))
                     (free-identifier=? (car clauses) #'main:))
                (set! main-expr (cadr clauses))
                (lp (cddr clauses))]
               [else (lp (cdr clauses))]))
           (with-syntax ([init init-expr]
                         [main main-expr])
             #'(begin
                 (set! *current-app*
                   (make-app name-expr init main))
                 (set! *current-app-name* name-expr)
                 ;; Run init immediately (during library load / boot)
                 ((app-init-proc *current-app*)))))])))

  ;; ========== Application Runner ==========

  (define (app-run! . args)
    (unless *current-app*
      (error 'app-run! "no application registered"))
    (let ([argv (if (pair? args)
                  (car args)
                  (command-line))])
      (set! *app-arguments* argv)
      ((app-main-proc *current-app*) argv)))

  ) ;; end library
