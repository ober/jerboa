#!chezscheme
;;; (std errdefer) — Error-path cleanup (Zig-inspired)
;;;
;;; Provides `errdefer` — a form that registers cleanup code to run
;;; ONLY when the dynamic extent exits via an exception.
;;;
;;; Unlike `unwind-protect` which always runs cleanup:
;;;   (unwind-protect body cleanup)  ; cleanup runs on success OR error
;;;
;;; `errdefer` cancels cleanup on normal exit:
;;;   (errdefer cleanup body ...)    ; cleanup only runs on error
;;;
;;; Multiple errdefers stack in LIFO order (like Zig).

(library (std errdefer)
  (export
    errdefer
    errdefer*
    with-errdefer)

  (import (chezscheme))

  ;; errdefer: single cleanup expression, single body expression
  ;; (errdefer cleanup body) — cleanup runs only if body raises an exception
  ;;
  ;; Implementation: Use a success flag that gets set after body completes.
  ;; The dynamic-wind after thunk checks the flag and only runs cleanup if false.
  (define-syntax errdefer
    (syntax-rules ()
      [(_ cleanup body)
       (let ([ok? #f])
         (dynamic-wind
           (lambda () (void))
           (lambda ()
             (let ([result body])
               (set! ok? #t)
               result))
           (lambda ()
             (unless ok? cleanup))))]
      [(_ cleanup body body* ...)
       (errdefer cleanup (begin body body* ...))]))

  ;; errdefer*: multiple body forms with begin
  ;; (errdefer* cleanup body1 body2 ...) — same as errdefer but cleaner for multi-form bodies
  (define-syntax errdefer*
    (syntax-rules ()
      [(_ cleanup body ...)
       (errdefer cleanup (begin body ...))]))

  ;; with-errdefer: Zig-style stacking of multiple errdefers
  ;; (with-errdefer ([cleanup1] [cleanup2] ...) body ...)
  ;;
  ;; Cleanups are registered in order but fire in LIFO order on error.
  ;; This matches Zig's errdefer semantics where:
  ;;   errdefer a();
  ;;   errdefer b();
  ;;   // on error: b() then a()
  (define-syntax with-errdefer
    (syntax-rules ()
      ;; Base case: no cleanups left, just run body
      [(_ () body ...)
       (begin body ...)]
      ;; Recursive case: wrap body in errdefer for this cleanup
      [(_ ([cleanup] rest ...) body ...)
       (errdefer cleanup
         (with-errdefer (rest ...) body ...))]))

  ) ;; end library
