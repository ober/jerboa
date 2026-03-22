#!chezscheme
;;; multicall.sls -- Subcommand dispatch framework
;;; Extends (std cli getopt) with multi-command CLI apps (like git, cargo).

(library (std cli multicall)
  (export define-cli run-cli add-command! cli-name cli-version cli-commands
          cli-cmd-name cli-cmd-description)
  (import (except (chezscheme) filter find))

  (define-record-type cli-app
    (fields name version description (mutable commands)))

  (define (cli-name app) (cli-app-name app))
  (define (cli-version app) (cli-app-version app))
  (define (cli-commands app) (cli-app-commands app))

  (define-record-type cli-cmd
    (fields name description handler))

  (define-syntax define-cli
    (syntax-rules ()
      ((_ var name version description)
       (define var (make-cli-app name version description '())))))

  (define (add-command! app name description handler)
    (cli-app-commands-set! app
      (append (cli-app-commands app)
              (list (make-cli-cmd name description handler)))))

  (define (run-cli app argv)
    (let ((args (if (null? argv) '() (cdr argv))))
      (cond
        ((or (null? args) (string=? (car args) "--help"))
         (display-help app))
        ((string=? (car args) "--version")
         (display-version app))
        (else
         (let ((cmd-name (car args)) (rest (cdr args)))
           (cond
             ((string=? cmd-name "help")
              (if (null? rest) (display-help app)
                  (display-command-help app (car rest))))
             ((string=? cmd-name "version") (display-version app))
             ((find-command app cmd-name)
              => (lambda (cmd) ((cli-cmd-handler cmd) rest)))
             (else (display-unknown app cmd-name))))))))

  (define (display-help app)
    (let ((p (current-output-port)))
      (fprintf p "~a ~a~n" (cli-app-name app) (cli-app-version app))
      (when (cli-app-description app)
        (fprintf p "~a~n" (cli-app-description app)))
      (fprintf p "~nUsage: ~a <command> [args...]~n~nCommands:~n" (cli-app-name app))
      (fprintf p "  ~a~25t~a~n" "help" "Show this help message")
      (fprintf p "  ~a~25t~a~n" "version" "Show version")
      (for-each
        (lambda (cmd)
          (fprintf p "  ~a~25t~a~n" (cli-cmd-name cmd) (cli-cmd-description cmd)))
        (cli-app-commands app))))

  (define (display-command-help app name)
    (cond
      ((find-command app name)
       => (lambda (cmd)
            (fprintf (current-output-port) "~a: ~a~n"
                     (cli-cmd-name cmd) (cli-cmd-description cmd))))
      (else (fprintf (current-error-port) "Unknown command: ~a~n" name))))

  (define (display-version app)
    (fprintf (current-output-port) "~a ~a~n" (cli-app-name app) (cli-app-version app)))

  (define (display-unknown app cmd-name)
    (fprintf (current-error-port) "Unknown command: ~a~n" cmd-name)
    (let ((suggestion (find-closest app cmd-name)))
      (when suggestion
        (fprintf (current-error-port) "Did you mean: ~a?~n" suggestion)))
    (fprintf (current-error-port) "Run '~a help' for usage.~n" (cli-app-name app))
    (exit 1))

  (define (find-closest app name)
    (let ((all-names (append '("help" "version")
                             (map cli-cmd-name (cli-app-commands app)))))
      (let lp ((names all-names) (best #f) (best-dist +inf.0))
        (if (null? names) best
            (let ((d (edit-distance name (car names))))
              (if (and (< d best-dist) (<= d 3))
                (lp (cdr names) (car names) d)
                (lp (cdr names) best best-dist)))))))

  (define (edit-distance s1 s2)
    (let* ((len1 (string-length s1)) (len2 (string-length s2))
           (w (+ len2 1))
           (matrix (make-vector (* (+ len1 1) w) 0)))
      (define (ref i j) (vector-ref matrix (+ (* i w) j)))
      (define (set! i j v) (vector-set! matrix (+ (* i w) j) v))
      (do ((i 0 (+ i 1))) ((> i len1)) (set! i 0 i))
      (do ((j 0 (+ j 1))) ((> j len2)) (set! 0 j j))
      (do ((i 1 (+ i 1))) ((> i len1))
        (do ((j 1 (+ j 1))) ((> j len2))
          (let ((cost (if (char=? (string-ref s1 (- i 1))
                                  (string-ref s2 (- j 1))) 0 1)))
            (set! i j (min (+ (ref (- i 1) j) 1)
                           (+ (ref i (- j 1)) 1)
                           (+ (ref (- i 1) (- j 1)) cost))))))
      (ref len1 len2)))

  (define (find-command app name)
    (find (lambda (cmd) (string=? (cli-cmd-name cmd) name))
          (cli-app-commands app)))

  (define (find pred lst)
    (cond ((null? lst) #f)
          ((pred (car lst)) (car lst))
          (else (find pred (cdr lst)))))

) ;; end library
