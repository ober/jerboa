#!chezscheme
;;; (std image) — Smalltalk-style world persistence
;;;
;;; Save and restore program state to/from files via FASL serialization.
;;; Limited version: saves registered global bindings, not continuations.
;;;
;;; API:
;;;   (register-world! name val)     — register a binding for world save
;;;   (save-world path)              — save all registered bindings to file
;;;   (load-world path)              — restore bindings from file
;;;   (world-bindings)               — list registered binding names
;;;   (world-snapshot)               — get current world as alist
;;;   (save-world-sexp path)         — save as S-expression (portable)
;;;   (load-world-sexp path)         — load from S-expression

(library (std image)
  (export register-world! save-world load-world
          world-bindings world-snapshot
          unregister-world! clear-world!
          save-world-sexp load-world-sexp)

  (import (chezscheme))

  ;; ========== World registry ==========
  ;; name -> (getter . setter) procedures

  (define *world* (make-eq-hashtable))

  (define (register-world! name getter setter)
    (hashtable-set! *world* name (cons getter setter)))

  (define (unregister-world! name)
    (hashtable-delete! *world* name))

  (define (clear-world!)
    (hashtable-clear! *world*))

  (define (world-bindings)
    (vector->list (hashtable-keys *world*)))

  (define (world-snapshot)
    (let-values ([(keys vals) (hashtable-entries *world*)])
      (let loop ([i 0] [acc '()])
        (if (= i (vector-length keys))
          acc
          (loop (+ i 1)
                (cons (cons (vector-ref keys i)
                            ((car (vector-ref vals i))))  ;; call getter
                      acc))))))

  ;; ========== Save/Load via FASL ==========

  (define (save-world path)
    (let ([snapshot (world-snapshot)])
      (let ([p (open-file-output-port path
                 (file-options no-fail)
                 (buffer-mode block)
                 #f)])
        (fasl-write snapshot p)
        (close-port p)
        (length snapshot))))

  (define (load-world path)
    (let ([p (open-file-input-port path
               (file-options)
               (buffer-mode block)
               #f)])
      (let ([snapshot (fasl-read p)])
        (close-port p)
        (for-each
          (lambda (binding)
            (let ([entry (hashtable-ref *world* (car binding) #f)])
              (when entry
                ((cdr entry) (cdr binding)))))  ;; call setter
          snapshot)
        (length snapshot))))

  ;; ========== Save/Load via S-expression (portable) ==========

  (define (save-world-sexp path)
    (let ([snapshot (world-snapshot)])
      (call-with-output-file path
        (lambda (p) (write snapshot p))
        'replace)
      (length snapshot)))

  (define (load-world-sexp path)
    (let ([snapshot (call-with-input-file path read)])
      (for-each
        (lambda (binding)
          (let ([entry (hashtable-ref *world* (car binding) #f)])
            (when entry
              ((cdr entry) (cdr binding)))))
        snapshot)
      (length snapshot)))

) ;; end library
