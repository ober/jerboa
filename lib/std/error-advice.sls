#!chezscheme
;;; (std error-advice) — Error messages with actionable fix suggestions
;;;
;;; Catches common Chez Scheme errors and augments them with plain-English
;;; fix suggestions.  Built on top of Chez's condition system.
;;;
;;; API:
;;;   (error-with-advice msg irritant ...)    — like error but advice-checked
;;;   (advise-error condition)                — return fix string or #f
;;;   (define-error-advice pattern fix-tmpl)  — register advice rule
;;;   (*error-advice-enabled* #t/#f)          — parameter (default #t)
;;;   (with-error-advice body ...)            — install advisor for body
;;;   (install-error-advisor!)                — install globally
;;;   common-error-fixes                      — built-in alist of (pattern . fix)
;;;   (format-error-with-fix condition)       — format condition + fix suggestion

(library (std error-advice)
  (export
    error-with-advice
    advise-error
    define-error-advice
    *error-advice-enabled*
    with-error-advice
    install-error-advisor!
    common-error-fixes
    format-error-with-fix)

  (import (chezscheme) (std pregexp))

  ;; ========== Configuration ==========

  (define *error-advice-enabled*
    (make-parameter #t
      (lambda (v)
        (unless (boolean? v)
          (error '*error-advice-enabled* "must be boolean" v))
        v)))

  ;; ========== Advice rule storage ==========
  ;;
  ;; Each rule is a pair (compiled-regexp . fix-template-string).
  ;; Rules are tried in order; first match wins.

  (define *advice-rules* '())

  ;; Register a new rule.  pattern is a pregexp string; fix-template is a
  ;; plain string (may include ~a / ~s placeholders in future).
  (define (register-advice! pattern fix-template)
    (let ([rx (pregexp pattern)])
      (set! *advice-rules*
        (append *advice-rules* (list (cons rx fix-template))))))

  ;; ========== common-error-fixes ==========
  ;;
  ;; Built-in advice for the most common Chez Scheme runtime errors.
  ;; Exported as a plain alist for user inspection.

  (define common-error-fixes
    '(;; Arity errors
      ("wrong number of arguments" .
       "Check the function's signature. Use (procedure-arity f) to inspect expected argument counts. Ensure you are not passing too few or too many arguments.")

      ;; Unbound variable
      ("(?i:unbound variable|variable .* is not bound|undefined)" .
       "The variable is not in scope. Check that it is imported, defined before use, and spelled correctly. Common typos: forgot to (import ...) or misspelled the library name.")

      ;; car/cdr on non-pair
      ("(?i:car.*not a pair|\\(\\) is not a pair|cdr.*not a pair)" .
       "You are calling car or cdr on an empty list or a non-pair value. Check for null? first, or verify the list is non-empty before destructuring.")

      ;; Arithmetic type error
      ("(?i:not a (real )?number|\\+ .* not a number|\\* .* not a number|\\- .* not a number)" .
       "A non-numeric value was passed to an arithmetic operation. Did you use string-append instead of + for strings? Or mix up a string/symbol with a number?")

      ;; string-ref out of range
      ("(?i:string-ref.*out of range|index .* out of range.*string)" .
       "The string index is out of bounds. Check (string-length s) before calling (string-ref s i). Remember indices are 0-based and the valid range is 0 .. (string-length s)-1.")

      ;; vector-ref out of range
      ("(?i:vector-ref.*out of range|index .* out of range.*vector)" .
       "The vector index is out of bounds. Check (vector-length v) before indexing. Valid indices are 0 .. (vector-length v)-1.")

      ;; Applying non-procedure
      ("(?i:attempt to apply.*non-procedure|call of non-procedure|not a procedure)" .
       "The value you are calling is not a procedure. Double-check that the name is bound to a function, not a variable or syntax form. If using higher-order functions, ensure the callback is actually a procedure.")

      ;; Assertion violation
      ("(?i:assertion violation)" .
       "A precondition was violated. Read the error message for which invariant failed, then check the inputs to the function. This often means a value is outside the expected range or has the wrong type.")

      ;; Division by zero
      ("(?i:division by zero|divide.*by zero|zero divisor)" .
       "Guard numeric division with (if (zero? denominator) fallback (/ numerator denominator)), or use (and (not (zero? x)) (/ ... x)).")

      ;; Contract violation
      ("(?i:contract.*violation|violated contract)" .
       "A contract or guard condition failed. Check the function's expected argument types and any precondition guards.")

      ;; I/O errors
      ("(?i:no such file|file not found|cannot open)" .
       "The file does not exist or is not accessible. Check the path, ensure the working directory is correct, and verify file permissions.")

      ;; Stack overflow / max recursion
      ("(?i:stack overflow|maximum recursion|too many nested calls)" .
       "Infinite or very deep recursion detected. Ensure the recursive call has a correct base case. Consider converting to a tail-recursive or iterative form.")

      ;; Type errors (various)
      ("(?i:expected.*but got|type mismatch|wrong type)" .
       "A value of the wrong type was passed. Check the expected type in the function's documentation or source, and add explicit type conversion if needed.")

      ;; Port errors
      ("(?i:port is closed|port.*not open|closed port)" .
       "The port has been closed before reading/writing was complete. Use call-with-port or ensure the port is open for the entire duration it is needed.")

      ;; Continuation/control errors
      ("(?i:continuation.*cannot be used|escape.*procedure)" .
       "A one-shot continuation or escape continuation was invoked outside its dynamic extent. Use call/cc carefully and avoid storing continuations beyond their scope.")

      ;; Hashtable errors
      ("(?i:hashtable.*not a hashtable|hash.*not found)" .
       "The value is not a hashtable, or you are using the wrong lookup procedure. Use (hashtable-ref ht key default) and ensure ht is created with make-equal-hashtable or similar.")))

  ;; ========== Installation of built-in rules ==========

  (define (install-builtin-rules!)
    (for-each
      (lambda (pair)
        (register-advice! (car pair) (cdr pair)))
      common-error-fixes))

  ;; ========== define-error-advice macro ==========

  (define-syntax define-error-advice
    (syntax-rules ()
      [(_ pattern fix-template)
       (register-advice! pattern fix-template)]))

  ;; ========== Extract error message string from condition ==========

  (define (condition->message-string exn)
    (cond
      [(message-condition? exn) (condition-message exn)]
      [(condition? exn)
       ;; Try to get a report string from Chez's condition reporter
       (guard (inner [#t ""])
         (let-values ([(port get) (open-string-output-port)])
           (display-condition exn port)
           (get)))]
      [(string? exn) exn]
      [else
       (guard (inner [#t ""])
         (format "~a" exn))]))

  ;; ========== advise-error ==========
  ;;
  ;; Given a Chez condition object, returns the first matching fix string or #f.

  (define (advise-error exn)
    (and (*error-advice-enabled*)
         (let ([msg (condition->message-string exn)])
           (let loop ([rules *advice-rules*])
             (if (null? rules)
               #f
               (let ([rx  (caar rules)]
                     [fix (cdar rules)])
                 (if (pregexp-match rx msg)
                   fix
                   (loop (cdr rules)))))))))

  ;; ========== format-error-with-fix ==========

  (define (format-error-with-fix exn)
    (let ([base-msg (condition->message-string exn)]
          [fix      (advise-error exn)])
      (if fix
        (string-append base-msg "\n\n  Suggestion: " fix)
        base-msg)))

  ;; ========== error-with-advice ==========
  ;;
  ;; Like (error who msg irritant ...) but first checks for advice and
  ;; prepends the suggestion to the message if one is found.

  (define (error-with-advice msg . irritants)
    ;; Build a temporary condition to check if we have advice for this message
    (let* ([test-condition
            (condition
              (make-message-condition msg)
              (make-irritants-condition irritants))]
           [fix (advise-error test-condition)]
           [full-msg (if fix
                       (string-append msg "\n\n  Suggestion: " fix)
                       msg)])
      (apply error full-msg irritants)))

  ;; ========== with-error-advice ==========
  ;;
  ;; Installs an exception handler for the dynamic extent of body that
  ;; augments error displays with fix suggestions.  Errors are re-raised
  ;; after the suggestion is printed; non-continuable errors propagate.

  (define-syntax with-error-advice
    (syntax-rules ()
      [(_ body ...)
       (with-exception-handler
         (lambda (exn)
           (when (*error-advice-enabled*)
             (let ([fix (advise-error exn)])
               (when fix
                 (display "\n  Suggestion: " (current-error-port))
                 (display fix (current-error-port))
                 (newline (current-error-port)))))
           ;; Re-raise so normal error handling still applies
           (raise-continuable exn))
         (lambda () body ...))]))

  ;; ========== install-error-advisor! ==========
  ;;
  ;; Installs advice display as a persistent side-channel alongside Chez's
  ;; normal condition handler.  Uses `with-exception-handler` at the REPL
  ;; interaction level.  This is advisory only — normal Chez error handling
  ;; continues unaffected.

  (define *advisor-installed* #f)

  (define (install-error-advisor!)
    (unless *advisor-installed*
      (set! *advisor-installed* #t)
      ;; Wrap the current exception handler
      (let ([prev (current-exception-state)])
        (current-exception-state
          (lambda (exn)
            ;; Show suggestion first (if any), then delegate to Chez handler
            (when (*error-advice-enabled*)
              (let ([fix (advise-error exn)])
                (when fix
                  (display "\n  Suggestion: " (current-error-port))
                  (display fix (current-error-port))
                  (newline (current-error-port)))))
            (prev exn))))))

  ;; Install built-in rules on library load (must be after all definitions)
  (install-builtin-rules!)

) ;; end library
