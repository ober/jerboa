#!chezscheme
;;; :std/misc/repr -- Object representation printing

(library (std misc repr)
  (export
    repr
    prn
    pr
    print-representation
    display-separated
    default-representation-options
    current-representation-options)

  (import (chezscheme))

  (define default-representation-options '())
  (define current-representation-options
    (make-parameter default-representation-options))

  (define (repr obj)
    ;; Return a string representation of obj
    (let ((port (open-output-string)))
      (print-representation obj port)
      (get-output-string port)))

  (define (pr obj . rest)
    ;; Print representation to port (default current-output-port)
    (let ((port (if (pair? rest) (car rest) (current-output-port))))
      (print-representation obj port)))

  (define (prn obj . rest)
    ;; Print representation + newline
    (let ((port (if (pair? rest) (car rest) (current-output-port))))
      (print-representation obj port)
      (newline port)))

  (define (print-representation obj port)
    (write obj port))

  (define (display-separated lst . rest)
    ;; Display items from lst separated by separator
    (let ((sep (if (pair? rest) (car rest) " "))
          (port (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) (current-output-port))))
      (unless (null? lst)
        (display (car lst) port)
        (for-each (lambda (x) (display sep port) (display x port)) (cdr lst)))))

  ) ;; end library
