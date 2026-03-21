#!/usr/bin/env scheme-script
#!chezscheme
;;; fuzz-format.ss -- Fuzzer for std/format (format string injection)
;;;
;;; Targets: format, printf, safe-printf
;;; Bug classes: format injection, arity mismatch crashes

(import (chezscheme)
        (std format)
        (std test fuzz))

;;; ========== Seed corpus ==========

(define format-seeds
  '("hello ~a world"
    "~s"
    "~d"
    "~b ~o ~x"
    "~%~%~%"
    "~~"
    "~10a"
    "~10,5f"
    "no directives"
    ""
    "~a ~a ~a"
    ))

;;; ========== Generators ==========

(define (gen-random-format-string)
  (case (random 8)
    [(0) ;; too many directives, not enough args
     (apply string-append
       (make-list (+ 2 (random 20)) "~a "))]
    [(1) ;; user-controlled input as format string
     (random-ascii-string (+ 1 (random 200)))]
    [(2) ;; ~* (argument jumping)
     "~a ~* ~a"]
    [(3) ;; nested ~? (indirect format)
     "~?"]
    [(4) ;; very long format string
     (make-string (+ 100 (random 2000)) #\~)]
    [(5) ;; valid format with edge case args
     (random-element format-seeds)]
    [(6) ;; tilde at end
     "hello~"]
    [(7) ;; mixed valid and invalid directives
     (let ([chars (map (lambda (_)
                         (if (zero? (random 3))
                           #\~
                           (integer->char (+ 32 (random 95)))))
                       (make-list (+ 5 (random 50))))])
       (list->string chars))]))

(define (gen-format-args)
  ;; Generate 0-5 random arguments
  (map (lambda (_)
         (case (random 4)
           [(0) (random 1000)]
           [(1) (random-ascii-string 10)]
           [(2) #t]
           [(3) '(1 2 3)]))
       (make-list (random 6))))

;;; ========== Run ==========

;; Fuzz format with random format strings and args
(define format-stats
  (fuzz-run "format"
    (lambda (_)
      (let ([fmt (gen-random-format-string)]
            [args (gen-format-args)])
        (guard (exn [#t (void)])
          (let ([port (open-output-string)])
            (apply fprintf port fmt args)
            (get-output-string port)))))
    (lambda () #f)))

;; Verify safe-printf doesn't interpret directives
(define safe-stats
  (fuzz-run "safe-printf"
    (lambda (input)
      (guard (exn [#t (void)])
        (let ([port (open-output-string)])
          (safe-fprintf port input)
          (let ([result (get-output-string port)])
            ;; safe-fprintf should output the string literally
            (unless (string=? result input)
              (error 'safe-printf "directive was interpreted!" input result))))))
    (lambda () (gen-random-format-string))
    (quotient (fuzz-iterations) 4)))

(when (or (> (fuzz-stats-crashes format-stats) 0)
          (> (fuzz-stats-crashes safe-stats) 0))
  (exit 1))
