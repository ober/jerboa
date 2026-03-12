;;; Stack Frame Inspector — Phase 5c (Track 14.1)
;;;
;;; Provides a simplified stack inspection API.  Chez Scheme's native
;;; inspector is interactive; we build a lightweight call-tracking layer
;;; that maintains a pseudo-stack and exposes it through a clean API.

(library (std debug inspector)
  (export
    ;; Frame records
    make-frame
    frame?
    frame-name
    frame-locals

    ;; Stack capture
    current-stack-frames
    stack-trace

    ;; Instrumented call tracking
    with-tracked-call
    call-with-inspector

    ;; Exception helpers
    with-stack-inspector)
  (import (chezscheme))

  ;; -----------------------------------------------------------------------
  ;; Frame record
  ;; -----------------------------------------------------------------------

  (define-record-type frame
    (fields (immutable name   frame-name)
            (immutable locals frame-locals))
    (protocol (lambda (new) (lambda (name locals) (new name locals)))))

  ;; -----------------------------------------------------------------------
  ;; Thread-local pseudo call stack
  ;; -----------------------------------------------------------------------

  (define *call-stack* (make-thread-parameter '()))

  ;; -----------------------------------------------------------------------
  ;; with-tracked-call — push a frame during evaluation
  ;; -----------------------------------------------------------------------

  (define-syntax with-tracked-call
    (syntax-rules ()
      [(_ name locals body ...)
       (let ([frm (make-frame name locals)])
         (parameterize ([*call-stack* (cons frm (*call-stack*))])
           body ...))]))

  ;; -----------------------------------------------------------------------
  ;; current-stack-frames — return current pseudo-stack
  ;; -----------------------------------------------------------------------

  (define (current-stack-frames)
    (*call-stack*))

  ;; -----------------------------------------------------------------------
  ;; stack-trace — format stack as string
  ;; -----------------------------------------------------------------------

  (define (stack-trace)
    (let ([frames (current-stack-frames)])
      (with-output-to-string
        (lambda ()
          (for-each
            (lambda (f i)
              (printf "  #~a  ~a" i (frame-name f))
              (unless (null? (frame-locals f))
                (printf " locals: ~s" (frame-locals f)))
              (printf "~n"))
            frames
            (let loop ([i 0] [n (length frames)] [acc '()])
              (if (= i n) (reverse acc) (loop (+ i 1) n (cons i acc)))))))))

  ;; -----------------------------------------------------------------------
  ;; call-with-inspector — run a thunk with stack inspection on exception
  ;; -----------------------------------------------------------------------

  (define (call-with-inspector thunk handler)
    "Run THUNK; if an exception is raised, call HANDLER with (exn frames)"
    (call-with-current-continuation
      (lambda (k)
        (with-exception-handler
          (lambda (exn)
            (handler exn (current-stack-frames))
            (k (void)))
          thunk))))

  ;; -----------------------------------------------------------------------
  ;; with-stack-inspector macro
  ;; -----------------------------------------------------------------------

  (define-syntax with-stack-inspector
    (syntax-rules ()
      [(_ ((exn-var frames-var) handler ...) body ...)
       (call-with-inspector
         (lambda () body ...)
         (lambda (exn-var frames-var) handler ...))]))

)
