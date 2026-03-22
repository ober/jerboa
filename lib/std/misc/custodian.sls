#!chezscheme
;;; (std misc custodian) --- Hierarchical custodians for resource management
;;;
;;; Custodians are hierarchical resource groups that can be shut down atomically.
;;; Every managed resource (ports, custom handles) belongs to a custodian.
;;; Shutting down a parent recursively shuts down all children and their resources.
;;;
;;; Usage:
;;;   (with-custodian
;;;     (let ([p (custodian-open-input-file "data.txt")])
;;;       (read p)))
;;;   ;; port is automatically closed when with-custodian exits

(library (std misc custodian)
  (export make-custodian
          current-custodian
          custodian?
          custodian-shutdown-all
          custodian-managed-list
          custodian-register!
          custodian-open-input-file
          custodian-open-output-file
          with-custodian)
  (import (chezscheme))

  ;; A custodian holds:
  ;;   parent   - parent custodian or #f for root
  ;;   children - list of child custodians
  ;;   resources - list of (resource . shutdown-proc) pairs
  ;;   alive?   - #t until shutdown
  (define-record-type cust
    (fields
      (immutable parent)
      (mutable children)
      (mutable resources)
      (mutable alive?))
    (protocol
      (lambda (new)
        (lambda (parent)
          (new parent '() '() #t)))))

  (define (custodian? x)
    (cust? x))

  ;; Root custodian has no parent
  (define root-custodian (make-cust #f))

  ;; Parameter for the current custodian
  (define current-custodian (make-parameter root-custodian))

  ;; Create a new custodian. If parent is not given, uses current-custodian.
  (define make-custodian
    (case-lambda
      [()
       (make-custodian (current-custodian))]
      [(parent)
       (unless (cust? parent)
         (error 'make-custodian "expected a custodian" parent))
       (unless (cust-alive? parent)
         (error 'make-custodian "parent custodian is shut down" parent))
       (let ([c (make-cust parent)])
         (cust-children-set! parent
           (cons c (cust-children parent)))
         c)]))

  ;; Register a resource with a custodian.
  ;; shutdown-proc is a thunk called to release the resource.
  ;; Returns the resource for convenience.
  (define custodian-register!
    (case-lambda
      [(resource shutdown-proc)
       (custodian-register! (current-custodian) resource shutdown-proc)]
      [(custodian resource shutdown-proc)
       (unless (cust? custodian)
         (error 'custodian-register! "expected a custodian" custodian))
       (unless (cust-alive? custodian)
         (error 'custodian-register! "custodian is shut down" custodian))
       (unless (procedure? shutdown-proc)
         (error 'custodian-register! "expected a procedure for shutdown" shutdown-proc))
       (cust-resources-set! custodian
         (cons (cons resource shutdown-proc) (cust-resources custodian)))
       resource]))

  ;; Shut down a custodian: close all resources, recursively shut down children,
  ;; and remove self from parent's child list.
  (define (custodian-shutdown-all c)
    (unless (cust? c)
      (error 'custodian-shutdown-all "expected a custodian" c))
    (when (cust-alive? c)
      ;; First, recursively shut down children (copy the list since shutdown mutates it)
      (for-each custodian-shutdown-all (list-copy (cust-children c)))
      ;; Then close all resources, catching errors so one bad resource
      ;; doesn't prevent others from being cleaned up
      (for-each
        (lambda (pair)
          (guard (e [#t (void)])  ;; swallow errors during shutdown
            ((cdr pair))))
        (cust-resources c))
      ;; Mark as dead and clear
      (cust-alive?-set! c #f)
      (cust-resources-set! c '())
      (cust-children-set! c '())
      ;; Remove self from parent's children list
      (let ([parent (cust-parent c)])
        (when parent
          (cust-children-set! parent
            (remq c (cust-children parent)))))))

  ;; List managed resources (not shutdown procs) for a custodian
  (define (custodian-managed-list c)
    (unless (cust? c)
      (error 'custodian-managed-list "expected a custodian" c))
    (append
      (map car (cust-resources c))
      (list-copy (cust-children c))))

  ;; Open an input file port registered with the current custodian
  (define custodian-open-input-file
    (case-lambda
      [(path)
       (custodian-open-input-file path (current-custodian))]
      [(path custodian)
       (let ([p (open-input-file path)])
         (custodian-register! custodian p (lambda () (close-input-port p)))
         p)]))

  ;; Open an output file port registered with the current custodian
  (define custodian-open-output-file
    (case-lambda
      [(path)
       (custodian-open-output-file path (current-custodian))]
      [(path custodian)
       (let ([p (open-output-file path)])
         (custodian-register! custodian p (lambda () (close-output-port p)))
         p)]))

  ;; Run body under a fresh custodian; shut it down when body exits
  ;; (whether normally, by exception, or by continuation escape).
  (define-syntax with-custodian
    (syntax-rules ()
      [(_ body ...)
       (let ([c (make-custodian)])
         (dynamic-wind
           (lambda () (void))
           (lambda ()
             (parameterize ([current-custodian c])
               body ...))
           (lambda ()
             (custodian-shutdown-all c))))]))

) ;; end library
