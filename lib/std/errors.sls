#!chezscheme
;;; (std errors) -- Enhanced error messages
;;;
;;; Wraps Chez Scheme's condition system with:
;;;   - Source-location-aware error formatting
;;;   - "Did you mean?" suggestions via Levenshtein distance
;;;   - Rich condition types (type-error, arity-error, unbound-error)
;;;   - Structured stack-trace display
;;;
;;; Usage:
;;;   (import (std errors))
;;;   (install-error-handler!)   ; enhance default error display
;;;   (type-error 'string-length "String" 42 "Fixnum")

(library (std errors)
  (export
    ;; Rich condition types
    type-error? type-error-who type-error-expected type-error-got type-error-got-type
    arity-error? arity-error-who arity-error-expected arity-error-got arity-error-definition
    unbound-error? unbound-error-name unbound-error-suggestions

    ;; Constructors with nice output
    type-error arity-error unbound-error

    ;; Did-you-mean suggestions
    levenshtein-distance find-suggestions

    ;; Error formatting
    format-error-message format-condition

    ;; REPL integration
    install-error-handler! with-enhanced-errors

    ;; Utilities
    make-source-location source-location? source-location-file
    source-location-line source-location-col)

  (import (chezscheme))

  ;;; ========== Source location ==========
  (define-record-type source-location
    (fields file line col))

  ;;; ========== Rich condition types ==========

  (define-condition-type &type-error &error
    make-type-error* type-error?
    (who      type-error-who)
    (expected type-error-expected)
    (got      type-error-got)
    (got-type type-error-got-type))

  (define-condition-type &arity-error &error
    make-arity-error* arity-error?
    (who        arity-error-who)
    (expected   arity-error-expected)  ; number or list of numbers
    (got        arity-error-got)
    (definition arity-error-definition)) ; source location or #f

  (define-condition-type &unbound-error &error
    make-unbound-error* unbound-error?
    (name        unbound-error-name)
    (suggestions unbound-error-suggestions)) ; list of similar names

  ;;; ========== Levenshtein distance ==========
  ;; Classic DP implementation. Used for "did you mean?" suggestions.
  (define (levenshtein-distance s1 s2)
    (let* ([n1   (string-length s1)]
           [n2   (string-length s2)]
           ;; dp: (n1+1) x (n2+1) matrix, stored as a vector
           [dp   (make-vector (* (+ n1 1) (+ n2 1)) 0)]
           [ref  (lambda (i j) (vector-ref  dp (+ (* i (+ n2 1)) j)))]
           [set! (lambda (i j v) (vector-set! dp (+ (* i (+ n2 1)) j) v))])
      ;; Base cases
      (do ([i 0 (+ i 1)]) ((> i n1)) (set! i 0 i))
      (do ([j 0 (+ j 1)]) ((> j n2)) (set! 0 j j))
      ;; Fill
      (do ([i 1 (+ i 1)]) ((> i n1))
        (do ([j 1 (+ j 1)]) ((> j n2))
          (let ([cost (if (char=? (string-ref s1 (- i 1))
                                  (string-ref s2 (- j 1)))
                        0 1)])
            (set! i j (min (+ (ref (- i 1) j) 1)
                           (+ (ref i (- j 1)) 1)
                           (+ (ref (- i 1) (- j 1)) cost))))))
      (ref n1 n2)))

  ;; Find candidates from a list that are "close" to the query
  (define (find-suggestions query candidates . max-dist-opt)
    (let ([max-dist (if (pair? max-dist-opt) (car max-dist-opt) 3)])
      (let ([scored
             (filter-map
               (lambda (c)
                 (let ([d (levenshtein-distance query (symbol->string c))])
                   (and (<= d max-dist) (cons d c))))
               candidates)])
        (map cdr (sort (lambda (a b) (< (car a) (car b))) scored)))))

  (define (filter-map proc lst)
    (let loop ([lst lst] [acc '()])
      (if (null? lst)
        (reverse acc)
        (let ([v (proc (car lst))])
          (loop (cdr lst) (if v (cons v acc) acc))))))

  ;;; ========== Error constructors ==========

  (define (type-error who expected got got-type)
    (raise
      (condition
        (make-type-error* who expected got got-type)
        (make-message-condition
          (format-type-error who expected got got-type))
        (make-irritants-condition (list got)))))

  (define (arity-error who expected got . def-opt)
    (let ([definition (if (pair? def-opt) (car def-opt) #f)])
      (raise
        (condition
          (make-arity-error* who expected got definition)
          (make-message-condition
            (format-arity-error who expected got definition))))))

  (define (unbound-error name . suggestions)
    (let ([suggs (if (pair? suggestions) (car suggestions) '())])
      (raise
        (condition
          (make-unbound-error* name suggs)
          (make-message-condition
            (format-unbound-error name suggs))))))

  ;;; ========== Formatting ==========

  (define (format-type-error who expected got got-type)
    (string-append
      "type mismatch"
      (if who (string-append " in " (symbol->string who)) "")
      "\n  expected: " (if (string? expected) expected (format "~a" expected))
      "\n  got:      " (format "~s" got)
      " (" (if (string? got-type) got-type (format "~a" got-type)) ")"))

  (define (format-arity-error who expected got definition)
    (string-append
      (if who (symbol->string who) "procedure")
      " called with "
      (number->string got)
      " argument" (if (= got 1) "" "s")
      ", but expects "
      (cond
        [(number? expected)
         (string-append (number->string expected)
                        (if (= expected 1) " argument" " arguments"))]
        [(list? expected)
         (string-append (string-join (map number->string expected) " or ")
                        " arguments")]
        [else (format "~a" expected)])
      (if definition
        (format "\n  defined at ~a:~a"
          (source-location-file definition)
          (source-location-line definition))
        "")))

  (define (format-unbound-error name suggestions)
    (string-append
      "unbound identifier '"
      (symbol->string name)
      "'"
      (if (null? suggestions)
        ""
        (string-append
          "\n  did you mean: "
          (string-join (map symbol->string suggestions) ", ")
          "?"))))

  (define (string-join strs sep)
    (if (null? strs)
      ""
      (let loop ([rest (cdr strs)] [acc (car strs)])
        (if (null? rest)
          acc
          (loop (cdr rest) (string-append acc sep (car rest)))))))

  ;;; ========== Enhanced condition display ==========

  (define (format-condition exn)
    (cond
      [(type-error? exn)
       (string-append "type error: "
         (format-type-error
           (type-error-who exn)
           (type-error-expected exn)
           (type-error-got exn)
           (type-error-got-type exn)))]
      [(arity-error? exn)
       (string-append "arity error: "
         (format-arity-error
           (arity-error-who exn)
           (arity-error-expected exn)
           (arity-error-got exn)
           (arity-error-definition exn)))]
      [(unbound-error? exn)
       (string-append "unbound: "
         (format-unbound-error
           (unbound-error-name exn)
           (unbound-error-suggestions exn)))]
      [(message-condition? exn)
       (condition-message exn)]
      [else
       (format "~a" exn)]))

  ;; Pretty-print an error to a port with context
  (define (format-error-message exn . port-opt)
    (let ([port (if (pair? port-opt) (car port-opt) (current-error-port))])
      (display "\nerror: " port)
      (display (format-condition exn) port)
      (newline port)
      ;; Show irritants if any
      (when (irritants-condition? exn)
        (let ([irritants (condition-irritants exn)])
          (unless (null? irritants)
            (display "  irritants: " port)
            (for-each (lambda (x) (display " " port) (write x port)) irritants)
            (newline port))))))

  ;;; ========== REPL integration ==========

  ;; Store original error handler
  (define original-error-handler #f)

  (define (install-error-handler!)
    ;; Replace Chez's default error display with our enhanced version
    (set! original-error-handler (current-exception-state))
    (current-exception-state
      (lambda (exn)
        (format-error-message exn (current-error-port)))))

  (define-syntax with-enhanced-errors
    (syntax-rules ()
      [(_ body ...)
       (call-with-current-continuation
         (lambda (k)
           (with-exception-handler
             (lambda (exn)
               (format-error-message exn (current-error-port))
               (k (void)))
             (lambda () body ...))))]))

) ;; end library
