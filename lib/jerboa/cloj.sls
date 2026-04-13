#!chezscheme
;;; jerboa/cloj.sls — Clojure reader mode support
;;;
;;; Provides:
;;;   reader-cloj-mode — parameter: activates Clojure syntax in the Jerboa reader
;;;   fn-literal       — macro: expands  #(...)  anonymous function reader literals
;;;
;;; The Jerboa reader expands  #(+ % 1)  to  (fn-literal + % 1)  when cloj mode
;;; is active.  fn-literal walks the body, detects % / %1 / %2 / %& references,
;;; and emits the appropriate (lambda ...) form.
;;;
;;; Activation: add  #!cloj  at the top of any Jerboa source file, or call
;;;   (reader-cloj-mode #t)  programmatically.

(library (jerboa cloj)
  (export reader-cloj-mode fn-literal activate-cloj-reader!)

  (import (chezscheme)
          (only (jerboa reader) reader-cloj-mode))

  ;;; activate-cloj-reader! — call from library bodies to enable cloj mode
  ;; Wraps (reader-cloj-mode #t) so that libraries with restricted import
  ;; environments can activate cloj mode with a single function call.
  (define (activate-cloj-reader!) (reader-cloj-mode #t))

  ;;; fn-literal — expands #(...) anonymous function literals
  ;;
  ;; #(+ % 1)         → (lambda (%1) (+ %1 1))
  ;; #(str %1 " " %2) → (lambda (%1 %2) (str %1 " " %2))
  ;; #(apply + %&)    → (lambda %& (apply + %&))
  ;; #(begin (f %) %) → (lambda (%1) (begin (f %1) %1))
  ;;
  ;; % is an alias for %1. %2, %3, etc. for more positional args.
  ;; %& collects all extra args as a rest list.

  (define-syntax fn-literal
    (lambda (stx)

      ;; Replace bare % with %1 throughout a datum tree
      (define (normalize d)
        (cond
          ((eq? d '%) '%1)
          ((pair? d) (cons (normalize (car d)) (normalize (cdr d))))
          (else d)))

      ;; Walk datum, return (max-positional-n . has-rest?)
      ;; Recognises: %1 %2 %3 ... (and %) %&
      (define (find-info d)
        (let loop ((d d) (n 0) (r? #f))
          (cond
            ((null? d)    (cons n r?))
            ((eq? d '%&)  (cons n #t))
            ((symbol? d)
             (let* ((s   (symbol->string d))
                    (len (string-length s)))
               (if (and (> len 1) (char=? (string-ref s 0) #\%))
                   (let ((num (string->number (substring s 1 len))))
                     (if num (cons (max n num) r?) (cons n r?)))
                   (cons n r?))))
            ((pair? d)
             (let ((r1 (loop (car d) n r?)))
               (loop (cdr d) (car r1) (cdr r1))))
            (else (cons n r?)))))

      ;; Build list (1 2 ... n)
      (define (range-1-to n)
        (let lp ((i n) (acc '()))
          (if (= i 0) acc (lp (- i 1) (cons i acc)))))

      (syntax-case stx ()
        ((kw body-form ...)
         (let* ((raw   (syntax->datum #'(body-form ...)))
                (nb    (normalize raw))
                ;; If there's exactly one form, use it directly; else wrap in begin
                (body  (if (and (pair? nb) (null? (cdr nb)))
                           (car nb)
                           (cons 'begin nb)))
                (info  (find-info body))
                (max-n (car info))
                (rest? (cdr info))
                (positional (map (lambda (i)
                                   (string->symbol
                                     (string-append "%" (number->string i))))
                                 (range-1-to max-n)))
                ;; arg-list:
                ;;   no args + rest   → %&          (variadic bare symbol)
                ;;   no args, no rest → ()           (nullary)
                ;;   args + rest      → (%1 %2 . %&) (dotted list via append)
                ;;   args, no rest    → (%1 %2 ...)
                (arg-list (cond
                            ((and (null? positional) rest?) '%&)
                            ((null? positional)             '())
                            (rest?  (append positional '%&)) ;; (append list sym) = dotted
                            (else   positional))))
           (datum->syntax #'kw `(lambda ,arg-list ,body)))))))

  ) ;; end library
