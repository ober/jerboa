#!chezscheme
;;; (std misc chaperone) — Impersonators/chaperones (contract proxies)
;;;
;;; Transparent proxies that intercept operations on values.
;;; Chaperones enforce contracts via interceptors; impersonators can freely transform.
;;;
;;; (chaperone-procedure proc args-interceptor result-interceptor)
;;; (impersonate-procedure proc args-interceptor result-interceptor)
;;; (chaperone-vector vec ref-interceptor set-interceptor)
;;; (chaperone-hashtable ht ref-interceptor set-interceptor delete-interceptor)
;;; (chaperone? v) — is v a chaperone/impersonator?
;;; (chaperone-of? v1 v2) — is v1 a chaperone wrapping v2 (directly or transitively)?

(library (std misc chaperone)
  (export chaperone-procedure
          impersonate-procedure
          chaperone-vector
          chaperone-hashtable
          chaperone?
          chaperone-of?
          chaperone-vector-ref
          chaperone-vector-set!
          chaperone-hashtable-ref
          chaperone-hashtable-set!
          chaperone-hashtable-delete!
          chaperone-unwrap)
  (import (chezscheme))

  ;; ---------------------------------------------------------------
  ;; Core record types
  ;; ---------------------------------------------------------------

  ;; Base record type for all chaperones/impersonators
  (define-record-type chaperone-base
    (fields
      (immutable inner)         ; the wrapped value (or another chaperone)
      (immutable kind)))        ; symbol: procedure, vector, hashtable

  ;; Procedure chaperone/impersonator
  (define-record-type procedure-chaperone
    (parent chaperone-base)
    (fields
      (immutable args-interceptor)    ; #f or (lambda args -> args-list)
      (immutable result-interceptor)  ; #f or (lambda results -> results-list)
      (immutable impersonator?)       ; #t if impersonator
      (mutable wrapper)))             ; the lambda returned to the user

  ;; Vector chaperone
  (define-record-type vector-chaperone
    (parent chaperone-base)
    (fields
      (immutable ref-interceptor)   ; #f or (lambda (vec idx val) -> val)
      (immutable set-interceptor))) ; #f or (lambda (vec idx val) -> val)

  ;; Hashtable chaperone
  (define-record-type hashtable-chaperone
    (parent chaperone-base)
    (fields
      (immutable ref-interceptor)     ; #f or (lambda (ht key val) -> val)
      (immutable set-interceptor)     ; #f or (lambda (ht key val) -> val)
      (immutable delete-interceptor))) ; #f or (lambda (ht key) -> key)

  ;; ---------------------------------------------------------------
  ;; Mapping from wrapper procedures back to their chaperone records
  ;; ---------------------------------------------------------------

  ;; We use an eq-hashtable with weak keys so that GC can collect
  ;; wrapper procedures that are no longer referenced.
  (define *proc-chaperone-table*
    (make-weak-eq-hashtable))

  (define (register-proc-chaperone! wrapper chap)
    (hashtable-set! *proc-chaperone-table* wrapper chap))

  (define (lookup-proc-chaperone wrapper)
    (hashtable-ref *proc-chaperone-table* wrapper #f))

  ;; ---------------------------------------------------------------
  ;; Unwrap — get the innermost (non-chaperone) value
  ;; ---------------------------------------------------------------

  (define (chaperone-unwrap v)
    (cond
      [(chaperone-base? v)
       (chaperone-unwrap (chaperone-base-inner v))]
      [(and (procedure? v) (lookup-proc-chaperone v))
       => (lambda (chap) (chaperone-unwrap (chaperone-base-inner chap)))]
      [else v]))

  ;; ---------------------------------------------------------------
  ;; Resolve — get the chaperone record for any chaperoned value
  ;; ---------------------------------------------------------------

  (define (resolve-chaperone v)
    (cond
      [(chaperone-base? v) v]
      [(and (procedure? v) (lookup-proc-chaperone v))
       => (lambda (chap) chap)]
      [else #f]))

  ;; ---------------------------------------------------------------
  ;; Predicates
  ;; ---------------------------------------------------------------

  (define (chaperone? v)
    (or (chaperone-base? v)
        (and (procedure? v) (lookup-proc-chaperone v) #t)))

  ;; Is v1 a chaperone of v2? (directly or transitively)
  (define (chaperone-of? v1 v2)
    (let ([c1 (resolve-chaperone v1)])
      (and c1
           (let ([inner (chaperone-base-inner c1)])
             (or (eq? inner v2)
                 ;; For procedure chaperones, the inner might be a wrapper proc
                 (and (procedure-chaperone? c1)
                      (procedure-chaperone-wrapper c1)
                      ;; inner is the original proc or another wrapper
                      #f)
                 ;; Check if both unwrap to the same base value
                 (let ([c2 (resolve-chaperone v2)])
                   (and c2
                        (eq? (chaperone-unwrap v1) (chaperone-unwrap v2))))
                 ;; Check transitively
                 (chaperone-of? inner v2))))))

  ;; ---------------------------------------------------------------
  ;; Procedure chaperones/impersonators
  ;; ---------------------------------------------------------------

  (define (call-through-chain chap args)
    ;; Walk the chain: intercept args at each layer, call base proc, intercept results
    ;; We collect interceptors in outside-in order, then apply them.
    (let loop ([c chap] [current-args args] [result-interceptors '()])
      (let ([intercepted-args
             (if (procedure-chaperone-args-interceptor c)
                 (apply (procedure-chaperone-args-interceptor c) current-args)
                 current-args)]
            [ri (if (procedure-chaperone-result-interceptor c)
                    (cons (procedure-chaperone-result-interceptor c) result-interceptors)
                    result-interceptors)])
        (let ([inner (chaperone-base-inner c)])
          (let ([inner-chap (resolve-chaperone inner)])
            (if (and inner-chap (procedure-chaperone? inner-chap))
                ;; Inner is also a procedure chaperone, continue chain
                (loop inner-chap intercepted-args ri)
                ;; Inner is the base procedure
                (let ([results (call-with-values
                                 (lambda () (apply inner intercepted-args))
                                 list)])
                  ;; Apply result interceptors innermost-first (reverse of collection order)
                  (let apply-results ([rs ri] [vals results])
                    (if (null? rs)
                        (apply values vals)
                        (apply-results
                          (cdr rs)
                          (apply (car rs) vals)))))))))))

  (define chaperone-procedure
    (case-lambda
      [(proc args-interceptor result-interceptor)
       (unless (procedure? (chaperone-unwrap proc))
         (error 'chaperone-procedure "expected a procedure" proc))
       (let* ([chap (make-procedure-chaperone
                      proc 'procedure
                      args-interceptor result-interceptor #f #f)]
              [wrapper (lambda args
                         (call-through-chain chap args))])
         (procedure-chaperone-wrapper-set! chap wrapper)
         (register-proc-chaperone! wrapper chap)
         wrapper)]
      [(proc args-interceptor)
       (chaperone-procedure proc args-interceptor #f)]))

  (define impersonate-procedure
    (case-lambda
      [(proc args-interceptor result-interceptor)
       (unless (procedure? (chaperone-unwrap proc))
         (error 'impersonate-procedure "expected a procedure" proc))
       (let* ([chap (make-procedure-chaperone
                      proc 'procedure
                      args-interceptor result-interceptor #t #f)]
              [wrapper (lambda args
                         (call-through-chain chap args))])
         (procedure-chaperone-wrapper-set! chap wrapper)
         (register-proc-chaperone! wrapper chap)
         wrapper)]
      [(proc args-interceptor)
       (impersonate-procedure proc args-interceptor #f)]))

  ;; ---------------------------------------------------------------
  ;; Vector chaperones
  ;; ---------------------------------------------------------------

  (define chaperone-vector
    (case-lambda
      [(vec ref-interceptor set-interceptor)
       (unless (vector? (chaperone-unwrap vec))
         (error 'chaperone-vector "expected a vector" vec))
       (make-vector-chaperone vec 'vector ref-interceptor set-interceptor)]
      [(vec ref-interceptor)
       (chaperone-vector vec ref-interceptor #f)]))

  (define (chaperone-vector-ref cv idx)
    (if (vector-chaperone? cv)
        (let* ([inner (chaperone-base-inner cv)]
               [raw-val (if (vector-chaperone? inner)
                            (chaperone-vector-ref inner idx)
                            (vector-ref inner idx))])
          (if (vector-chaperone-ref-interceptor cv)
              ((vector-chaperone-ref-interceptor cv) cv idx raw-val)
              raw-val))
        (vector-ref cv idx)))

  (define (chaperone-vector-set! cv idx val)
    (if (vector-chaperone? cv)
        (let* ([intercepted-val
                (if (vector-chaperone-set-interceptor cv)
                    ((vector-chaperone-set-interceptor cv) cv idx val)
                    val)]
               [inner (chaperone-base-inner cv)])
          (if (vector-chaperone? inner)
              (chaperone-vector-set! inner idx intercepted-val)
              (vector-set! inner idx intercepted-val)))
        (vector-set! cv idx val)))

  ;; ---------------------------------------------------------------
  ;; Hashtable chaperones
  ;; ---------------------------------------------------------------

  (define chaperone-hashtable
    (case-lambda
      [(ht ref-interceptor set-interceptor delete-interceptor)
       (unless (hashtable? (chaperone-unwrap ht))
         (error 'chaperone-hashtable "expected a hashtable" ht))
       (make-hashtable-chaperone
         ht 'hashtable ref-interceptor set-interceptor delete-interceptor)]
      [(ht ref-interceptor set-interceptor)
       (chaperone-hashtable ht ref-interceptor set-interceptor #f)]
      [(ht ref-interceptor)
       (chaperone-hashtable ht ref-interceptor #f #f)]))

  (define (chaperone-hashtable-ref ch key default)
    (if (hashtable-chaperone? ch)
        (let* ([inner (chaperone-base-inner ch)]
               [raw-val (if (hashtable-chaperone? inner)
                            (chaperone-hashtable-ref inner key default)
                            (hashtable-ref inner key default))])
          (if (hashtable-chaperone-ref-interceptor ch)
              ((hashtable-chaperone-ref-interceptor ch) ch key raw-val)
              raw-val))
        (hashtable-ref ch key default)))

  (define (chaperone-hashtable-set! ch key val)
    (if (hashtable-chaperone? ch)
        (let* ([intercepted-val
                (if (hashtable-chaperone-set-interceptor ch)
                    ((hashtable-chaperone-set-interceptor ch) ch key val)
                    val)]
               [inner (chaperone-base-inner ch)])
          (if (hashtable-chaperone? inner)
              (chaperone-hashtable-set! inner key intercepted-val)
              (hashtable-set! inner key intercepted-val)))
        (hashtable-set! ch key val)))

  (define (chaperone-hashtable-delete! ch key)
    (if (hashtable-chaperone? ch)
        (let* ([intercepted-key
                (if (hashtable-chaperone-delete-interceptor ch)
                    ((hashtable-chaperone-delete-interceptor ch) ch key)
                    key)]
               [inner (chaperone-base-inner ch)])
          (if (hashtable-chaperone? inner)
              (chaperone-hashtable-delete! inner intercepted-key)
              (hashtable-delete! inner intercepted-key)))
        (hashtable-delete! ch key)))

) ;; end library
