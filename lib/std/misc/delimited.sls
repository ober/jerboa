#!chezscheme
;;; (std misc delimited) — Delimited continuations with reset/shift
;;;
;;; Uses the Filinski encoding via call/cc and a mutable meta-continuation.
;;;
;;; (reset (+ 1 (shift k (k 10))))  => 11
;;; (reset (+ 1 (shift k 42)))      => 42  (k not called)
;;; (reset (+ 1 (shift k (+ (k 10) (k 20)))))  => 32

(library (std misc delimited)
  (export reset shift
          call-with-prompt abort-to-prompt
          make-prompt-tag)
  (import (except (chezscheme) reset))

  ;; =========================================================================
  ;; Prompt tags (for call-with-prompt API)
  ;; =========================================================================

  (define (make-prompt-tag . name)
    (list (if (pair? name) (car name) 'prompt)))

  (define *prompt-k* (make-parameter #f))
  (define *prompt-tag* (make-parameter #f))

  (define (call-with-prompt tag thunk handler)
    (call/cc
      (lambda (prompt-k)
        (parameterize ([*prompt-k* prompt-k]
                       [*prompt-tag* tag])
          (prompt-k (thunk))))))

  (define (abort-to-prompt tag . vals)
    (let ([k (*prompt-k*)]
          [current-tag (*prompt-tag*)])
      (unless (and k (eq? tag current-tag))
        (error 'abort-to-prompt "no matching prompt" tag))
      (k (apply values vals))))

  ;; =========================================================================
  ;; reset / shift — Filinski encoding with mutable cell
  ;; =========================================================================
  ;; Uses a plain box (not parameter) to avoid dynamic-wind interactions
  ;; with call/cc capturing/restoring parameter bindings.

  (define *meta-k* (box values))

  (define (reset-thunk thunk)
    (let ([saved-meta (unbox *meta-k*)])
      (call/cc
        (lambda (k)
          (set-box! *meta-k*
            (lambda (v)
              (set-box! *meta-k* saved-meta)
              (k v)))
          (let ([result (thunk)])
            ((unbox *meta-k*) result))))))

  (define (shift-thunk f)
    (call/cc
      (lambda (k)
        (let ([captured-k
               (lambda (v)
                 (reset-thunk (lambda () (k v))))])
          ((unbox *meta-k*) (f captured-k))))))

  (define-syntax reset
    (syntax-rules ()
      [(_ body ...)
       (reset-thunk (lambda () body ...))]))

  (define-syntax shift
    (syntax-rules ()
      [(_ k body ...)
       (shift-thunk (lambda (k) body ...))]))

) ;; end library
