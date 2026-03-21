#!chezscheme
;;; (std cafe) — REPL customization
;;;
;;; Re-exports Chez's cafe (REPL) customization parameters.

(library (std cafe)
  (export waiter-prompt-string waiter-prompt-and-read
          new-cafe cafe-eval reset-handler)

  (import (chezscheme))

  ;; cafe-eval: evaluate an expression in the interaction environment
  (define (cafe-eval expr)
    (eval expr (interaction-environment)))

  ;; All other exports are Chez built-ins:
  ;;   waiter-prompt-string: parameter for prompt text
  ;;   waiter-prompt-and-read: parameter for custom read proc
  ;;   new-cafe: launch nested REPL
  ;;   reset-handler: parameter for reset behavior

) ;; end library
