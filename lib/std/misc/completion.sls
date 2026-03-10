#!chezscheme
;;; :std/misc/completion -- Asynchronous completion tokens

(library (std misc completion)
  (export
    make-completion completion?
    completion-ready?
    completion-post! completion-error! completion-wait!)

  (import (chezscheme))

  (define-record-type completion
    (fields (mutable ready?)
            (mutable val)
            (mutable exn)
            (immutable mx)
            (immutable cv))
    (protocol
      (lambda (new)
        (lambda args
          (new #f #f #f (make-mutex) (make-condition))))))

  (define (completion-post! c val)
    (with-mutex (completion-mx c)
      (when (completion-ready? c)
        (error 'completion-post! "completion already posted"))
      (completion-ready?-set! c #t)
      (completion-val-set! c val)
      (condition-broadcast (completion-cv c))))

  (define (completion-error! c exn)
    (with-mutex (completion-mx c)
      (when (completion-ready? c)
        (error 'completion-error! "completion already posted"))
      (completion-ready?-set! c #t)
      (completion-exn-set! c exn)
      (condition-broadcast (completion-cv c))))

  (define (completion-wait! c)
    (mutex-acquire (completion-mx c))
    (let lp ()
      (cond
        ((completion-ready? c)
         (let ((exn (completion-exn c))
               (val (completion-val c)))
           (mutex-release (completion-mx c))
           (if exn (raise exn) val)))
        (else
         (condition-wait (completion-cv c) (completion-mx c))
         (lp)))))

  ) ;; end library
