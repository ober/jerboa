#!chezscheme
;;; (std resource) — RAII-style resource management
;;;
;;; Guarantees cleanup of resources even on exceptions.
;;; Auto-detects cleanup procedures for common resource types.
;;;
;;; Usage:
;;;   (with-resource ([db (sqlite-open "test.db")]
;;;                   [sock (tcp-connect "localhost" 8080)]
;;;                   [f (open-input-file "data.txt")])
;;;     (sqlite-exec db "SELECT 1")
;;;     (tcp-write-string sock "hello"))
;;;   ;; All three resources guaranteed closed here
;;;
;;;   ;; Explicit cleanup:
;;;   (with-resource ([buf (make-bytevector 4096) (lambda (b) (bytevector-fill! b 0))])
;;;     (use buf))
;;;
;;;   ;; Single resource shorthand:
;;;   (with-resource1 (db (sqlite-open "test.db"))
;;;     (sqlite-exec db "SELECT 1"))

(library (std resource)
  (export
    with-resource
    with-resource1
    register-resource-cleanup!
    call-with-resource)

  (import (chezscheme))

  ;; =========================================================================
  ;; Cleanup registry — maps type predicates to cleanup procedures
  ;; =========================================================================

  (define *cleanup-registry* '())
  (define *registry-mutex* (make-mutex))

  (define (register-resource-cleanup! pred cleanup)
    ;; Register a cleanup procedure for resources matching pred.
    ;; pred: (lambda (obj) boolean?)
    ;; cleanup: (lambda (obj) void)
    (with-mutex *registry-mutex*
      (set! *cleanup-registry*
        (cons (cons pred cleanup) *cleanup-registry*))))

  ;; Built-in cleanups for common types
  (define (auto-cleanup resource)
    ;; Returns a cleanup thunk for the resource, or a no-op if unknown.
    (cond
      ;; Ports (files, string ports, transcoded ports)
      [(port? resource)
       (lambda ()
         (when (not (port-closed? resource))
           (when (output-port? resource)
             (flush-output-port resource))
           (close-port resource)))]
      ;; Check registered cleanups
      [(find-registered-cleanup resource)
       => (lambda (cleanup)
            (lambda () (cleanup resource)))]
      ;; Unknown — no-op (user should provide explicit cleanup)
      [else (lambda () (void))]))

  (define (find-registered-cleanup resource)
    (let loop ([registry *cleanup-registry*])
      (cond
        [(null? registry) #f]
        [((caar registry) resource) (cdar registry)]
        [else (loop (cdr registry))])))

  ;; =========================================================================
  ;; Core: call-with-resource (procedural API)
  ;; =========================================================================

  (define (call-with-resource acquire cleanup body)
    ;; acquire: thunk that returns a resource
    ;; cleanup: (lambda (resource) ...) or #f for auto-detect
    ;; body: (lambda (resource) ...)
    (let ([resource (acquire)])
      (let ([do-cleanup
             (if cleanup
                 (lambda () (cleanup resource))
                 (auto-cleanup resource))])
        (dynamic-wind
          (lambda () (void))
          (lambda () (body resource))
          do-cleanup))))

  ;; =========================================================================
  ;; with-resource1 — single resource binding
  ;; =========================================================================

  (define-syntax with-resource1
    (syntax-rules ()
      ;; With explicit cleanup
      [(_ (var init cleanup) body ...)
       (let ([var init])
         (dynamic-wind
           (lambda () (void))
           (lambda () body ...)
           (lambda () (cleanup var))))]
      ;; Auto-detect cleanup
      [(_ (var init) body ...)
       (let ([resource init])
         (let ([do-cleanup (auto-cleanup resource)])
           (let ([var resource])
             (dynamic-wind
               (lambda () (void))
               (lambda () body ...)
               do-cleanup))))]))

  ;; =========================================================================
  ;; with-resource — multiple resource bindings (nested cleanup)
  ;; =========================================================================
  ;;
  ;; Each binding is (var init) or (var init cleanup-proc).
  ;; Resources are acquired left-to-right, cleaned up right-to-left.
  ;; If acquisition of resource N fails, resources 0..N-1 are still cleaned up.

  (define-syntax with-resource
    (syntax-rules ()
      ;; Base case: no more bindings
      [(_ () body ...)
       (begin body ...)]
      ;; Binding with explicit cleanup
      [(_ ((var init cleanup) rest ...) body ...)
       (with-resource1 (var init cleanup)
         (with-resource (rest ...) body ...))]
      ;; Binding with auto-detect cleanup
      [(_ ((var init) rest ...) body ...)
       (with-resource1 (var init)
         (with-resource (rest ...) body ...))]))

) ;; end library
