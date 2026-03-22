#!chezscheme
;;; (std amb) — Nondeterministic computation with backtracking
;;;
;;; McCarthy's amb operator using call/cc and a failure continuation stack.
;;; Explores nondeterministic choices depth-first; backtracks on failure.
;;;
;;; API:
;;;   (amb x ...)              — choose one value; backtrack on failure
;;;   (amb-assert cond)        — fail if condition is #f
;;;   (amb-fail)               — trigger backtracking
;;;   (amb-find expr)          — find first solution or #f
;;;   (amb-collect expr)       — collect all solutions into a list

(library (std amb)
  (export amb amb-assert amb-fail amb-find amb-collect)

  (import (chezscheme))

  ;; The failure stack: a list of thunks, each of which resumes a
  ;; previously captured continuation to try the next alternative.
  (define *fail-stack* (make-parameter '()))

  ;; Trigger backtracking.  Pops the most recent alternative off the
  ;; failure stack and invokes it.  If the stack is empty, raises an
  ;; error (when used outside amb-find/amb-collect) or returns the
  ;; sentinel installed by those forms.
  (define (amb-fail)
    (let ([stk (*fail-stack*)])
      (if (null? stk)
          (error 'amb "no more alternatives")
          (let ([top (car stk)])
            (*fail-stack* (cdr stk))
            (top)))))

  ;; Assert a condition; backtrack if it is false.
  (define (amb-assert condition)
    (unless condition (amb-fail)))

  ;; (amb v1 v2 ... vn) — nondeterministically return one of the values.
  ;; With zero arguments, immediately fails (equivalent to amb-fail).
  ;; Implementation: capture the current continuation, push alternatives
  ;; onto the failure stack, and return the first choice.  When
  ;; backtracking reaches this point, the next alternative is tried.
  (define-syntax amb
    (syntax-rules ()
      [(_) (amb-fail)]
      [(_ x) x]
      [(_ x rest ...)
       (call/cc
         (lambda (k)
           ;; Save current failure stack so we can restore it when
           ;; trying alternatives at this choice point.
           (let ([saved (*fail-stack*)])
             ;; Push a thunk that will try the remaining alternatives.
             ;; When invoked, it restores the failure stack to what it
             ;; was *before* pushing, then sets up the remaining choices
             ;; by re-entering through the same continuation.
             (*fail-stack*
               (cons (lambda ()
                       (*fail-stack* saved)
                       (k (amb rest ...)))
                     saved))
             x)))]))

  ;; Find the first solution.  Returns #f if no solution exists.
  ;; Installs a bottom-of-stack handler that escapes with #f.
  (define-syntax amb-find
    (syntax-rules ()
      [(_ expr)
       (call/cc
         (lambda (exit)
           (parameterize ([*fail-stack*
                           (list (lambda () (exit #f)))])
             (let ([result expr])
               ;; Got a result — escape with it immediately so we
               ;; don't explore further.
               (exit result)))))]))

  ;; Collect all solutions into a list.
  ;; Installs a bottom-of-stack handler that escapes with the
  ;; accumulated results, and after each successful evaluation
  ;; forces backtracking to find more.
  (define-syntax amb-collect
    (syntax-rules ()
      [(_ expr)
       (let ([results '()])
         (call/cc
           (lambda (exit)
             (parameterize ([*fail-stack*
                             (list (lambda ()
                                     (exit (reverse results))))])
               (let ([v expr])
                 (set! results (cons v results))
                 ;; Force backtracking to find more solutions.
                 (amb-fail))))))]))

) ;; end library
