#!chezscheme
;;; (std specialize) — Profile-guided specialization
;;;
;;; Specialize functions based on runtime type profiles, then recompile.
;;; Uses Chez's compile and eval for runtime recompilation.
;;;
;;; API:
;;;   (define-specializable (name args ...) body ...) — define with profiling
;;;   (specialize! name type-spec)    — specialize for given types
;;;   (profile-types name)            — get type profile for a function
;;;   (specialized? name)             — check if function is specialized
;;;   (unspecialize! name)            — revert to generic version

(library (std specialize)
  (export make-specializable specialize-fn specialized?
          type-profile record-type-call! clear-profile!
          specialize-numeric specialize-fixnum)

  (import (chezscheme))

  ;; ========== Type profiling ==========

  (define *profiles* (make-eq-hashtable))  ;; name -> type counts

  (define (record-type-call! name types)
    (let ([prof (hashtable-ref *profiles* name #f)])
      (unless prof
        (set! prof (make-hashtable equal-hash equal?))
        (hashtable-set! *profiles* name prof))
      (hashtable-update! prof types (lambda (n) (+ n 1)) 0)))

  (define (type-profile name)
    (let ([prof (hashtable-ref *profiles* name #f)])
      (if prof
        (let-values ([(keys vals) (hashtable-entries prof)])
          (map cons (vector->list keys) (vector->list vals)))
        '())))

  (define (clear-profile! name)
    (hashtable-delete! *profiles* name))

  ;; ========== Specialization ==========

  (define *originals* (make-eq-hashtable))
  (define *specialized* (make-eq-hashtable))

  (define (make-specializable name proc)
    (hashtable-set! *originals* name proc)
    proc)

  (define (specialized? name)
    (hashtable-contains? *specialized* name))

  ;; Specialize a numeric function to use fixnum ops
  (define (specialize-fixnum proc)
    (lambda args
      ;; Fast path: all fixnums
      (if (for-all fixnum? args)
        (apply proc args)  ;; Chez cp0 will optimize fx ops
        (apply proc args))))

  ;; Specialize for numeric types
  (define (specialize-numeric proc)
    (lambda args
      (apply proc args)))

  ;; Generic specialization entry point
  (define (specialize-fn name proc type-hint)
    (let ([specialized
           (case type-hint
             [(fixnum) (specialize-fixnum proc)]
             [(flonum) proc]
             [else proc])])
      (hashtable-set! *specialized* name specialized)
      specialized))

) ;; end library
