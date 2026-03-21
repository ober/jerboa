#!chezscheme
;;; (std effect resource) — Effect-based resource management
;;;
;;; Resources acquired dynamically with guaranteed cleanup in reverse order.
;;; Like bracket/RAII but via effect handlers — N resources, any exceptions.
;;;
;;; API:
;;;   (with-resources thunk)         — run thunk, cleanup all acquired resources
;;;   (acquire ctor dtor)            — acquire a resource (constructor, destructor)
;;;   (acquire-port open-thunk)      — shorthand for port resources

(library (std effect resource)
  (export with-resources acquire acquire-port)

  (import (chezscheme))

  ;; Resource stack: thread-local list of (resource . destructor) pairs
  (define *resource-stack* (make-thread-parameter '()))

  (define (acquire ctor dtor)
    (let ([r (ctor)])
      (*resource-stack* (cons (cons r dtor) (*resource-stack*)))
      r))

  (define (acquire-port open-thunk)
    (acquire open-thunk close-port))

  (define (cleanup-resources! resources)
    ;; Cleanup in reverse order (LIFO)
    (for-each
      (lambda (pair)
        (guard (exn [#t (void)])  ;; don't let cleanup errors propagate
          ((cdr pair) (car pair))))
      resources))

  (define (with-resources thunk)
    (let ([saved (*resource-stack*)])
      (parameterize ([*resource-stack* '()])
        (let ([result
               (guard (exn
                       [#t (cleanup-resources! (*resource-stack*))
                           (*resource-stack* saved)
                           (raise exn)])
                 (thunk))])
          (cleanup-resources! (*resource-stack*))
          (*resource-stack* saved)
          result))))

) ;; end library
