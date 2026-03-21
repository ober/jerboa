#!chezscheme
;;; (std misc with-destroy) — RAII-style resource management
;;;
;;; Ensure cleanup (destroy) runs on scope exit.
;;; Pattern: (with-destroy (obj (make-resource)) body ...)
;;; Calls (destroy obj) on scope exit (normal or exception).

(library (std misc with-destroy)
  (export with-destroy with-destroys)

  (import (chezscheme))

  ;; with-destroy: bind resource, run body, call destroy on exit
  ;; destroy-proc defaults to a generic 'destroy' method dispatch
  (define-syntax with-destroy
    (syntax-rules ()
      [(_ ((var init) destroy-proc) body body* ...)
       (let ([var init])
         (dynamic-wind
           void
           (lambda () body body* ...)
           (lambda () (destroy-proc var))))]
      [(_ (var init) body body* ...)
       ;; Default: call close-port if port, otherwise noop
       (let ([var init])
         (dynamic-wind
           void
           (lambda () body body* ...)
           (lambda ()
             (when (port? var) (close-port var)))))]))

  ;; with-destroys: multiple resources
  (define-syntax with-destroys
    (syntax-rules ()
      [(_ () body body* ...)
       (begin body body* ...)]
      [(_ ((binding ...) rest ...) body body* ...)
       (with-destroy (binding ...)
         (with-destroys (rest ...) body body* ...))]))

) ;; end library
