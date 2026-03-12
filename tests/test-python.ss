#!chezscheme
;;; test-python.ss -- Tests for (std python) -- Python interop via subprocess

(import (except (chezscheme) make-hash-table hash-table? iota 1+ 1-)
        (jerboa runtime)
        (std python)
        (std text json))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(define-syntax test-pred
  (syntax-rules ()
    [(_ name pred expr)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (pred got)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: predicate failed on ~s~%" name got)))))]))

(printf "--- (std python) tests ---~%~%")

;;;; ===== Data marshaling: scheme->python =====

(printf "~%-- Marshaling: scheme->python --~%")

(test "scheme->python true"
  (scheme->python #t)
  "true")

(test "scheme->python false"
  (scheme->python #f)
  "false")

(test "scheme->python integer"
  (scheme->python 42)
  "42")

(test "scheme->python negative"
  (scheme->python -7)
  "-7")

(test "scheme->python float"
  ;; JSON for 3.14 may vary, just check it's parseable
  (string? (scheme->python 3.14))
  #t)

(test "scheme->python string"
  (scheme->python "hello")
  "\"hello\"")

(test "scheme->python empty string"
  (scheme->python "")
  "\"\"")

(test "scheme->python string with quotes"
  (scheme->python "say \"hi\"")
  "\"say \\\"hi\\\"\"")

(test "scheme->python empty list -> []"
  (scheme->python '())
  "[]")

(test "scheme->python list of numbers"
  (scheme->python '(1 2 3))
  "[1,2,3]")

(test "scheme->python nested list"
  (scheme->python '(1 (2 3) 4))
  "[1,[2,3],4]")

(test "scheme->python symbol -> string"
  (scheme->python 'hello)
  "\"hello\"")

(test "scheme->python null"
  (scheme->python (void))
  "null")

;;;; ===== Data marshaling: python->scheme =====

(printf "~%-- Marshaling: python->scheme --~%")

(test "python->scheme true"
  (python->scheme #t)
  #t)

(test "python->scheme false"
  (python->scheme #f)
  #f)

(test "python->scheme integer"
  (python->scheme 99)
  99)

(test "python->scheme string"
  (python->scheme "hello")
  "hello")

(test "python->scheme null -> empty list"
  (python->scheme (void))
  '())

(test "python->scheme list"
  (python->scheme '(1 2 3))
  '(1 2 3))

(test "python->scheme nested list"
  (python->scheme '(1 (2 3)))
  '(1 (2 3)))

(test "python->scheme dict (hashtable) -> alist"
  (let* ([ht (make-hashtable equal-hash equal?)]
         [_ (hashtable-set! ht "x" 1)]
         [_ (hashtable-set! ht "y" 2)]
         [result (python->scheme ht)])
    (and (list? result)
         (pair? (assq 'x result))
         (pair? (assq 'y result))))
  #t)

(test "python->scheme dict values"
  (let* ([ht (make-hashtable equal-hash equal?)]
         [_ (hashtable-set! ht "name" "alice")]
         [result (python->scheme ht)])
    (cdr (assq 'name result)))
  "alice")

;;;; ===== python-list->scheme =====

(printf "~%-- python-list->scheme / python-dict->scheme --~%")

(test "python-list->scheme basic"
  (python-list->scheme '(1 2 3))
  '(1 2 3))

(test "python-list->scheme with nulls"
  (python-list->scheme (list 1 (void) 3))
  '(1 () 3))

(test "python-dict->scheme"
  (let* ([ht (make-hashtable equal-hash equal?)]
         [_ (hashtable-set! ht "a" 1)])
    (let ([result (python-dict->scheme ht)])
      (cdr (assq 'a result))))
  1)

(test "python-dict->scheme empty"
  (python-dict->scheme (make-hashtable equal-hash equal?))
  '())

;;;; ===== scheme-list->python =====

(test "scheme-list->python empty"
  (scheme-list->python '())
  "[]")

(test "scheme-list->python numbers"
  (scheme-list->python '(1 2 3))
  "[1, 2, 3]")

(test "scheme-list->python strings"
  (scheme-list->python '("a" "b"))
  "[\"a\", \"b\"]")

(test "scheme-list->python mixed"
  (let ([result (scheme-list->python '(1 "two" #t))])
    (string? result))
  #t)

;;;; ===== *default-python-cmd* parameter =====

(printf "~%-- Parameters --~%")

(test "default-python-cmd is python3"
  (*default-python-cmd*)
  "python3")

(test "default-python-cmd can be changed"
  (parameterize ([*default-python-cmd* "python"])
    (*default-python-cmd*))
  "python")

(test "default-python-cmd restored"
  (*default-python-cmd*)
  "python3")

;;;; ===== python-error? =====

(printf "~%-- Error handling --~%")

(test "python-error? on non-error is false"
  (python-error? "some string")
  #f)

(test "python-error? on non-condition is false"
  (python-error? 42)
  #f)

;;;; ===== Subprocess tests (skipped if python3 not available) =====

(printf "~%-- Subprocess tests --~%")

(define python-available?
  (guard (e [#t #f])
    (let-values ([(to from err pid)
                  (open-process-ports "python3 --version" 'block (native-transcoder))])
      (close-port to)
      (get-string-all from)
      (close-port from)
      (close-port err)
      #t)))

(if (not python-available?)
  (begin
    (printf "  (skipping subprocess tests: python3 not available)~%"))
  (begin
    (printf "  (python3 available, running subprocess tests)~%~%")

    (test "start-python returns proc"
      (let ([p (start-python)])
        (let ([result (python-proc? p)])
          (stop-python p)
          result))
      #t)

    (test "python-running? true after start"
      (let ([p (start-python)])
        (let ([r (python-running? p)])
          (stop-python p)
          r))
      #t)

    (test "python-running? false after stop"
      (let ([p (start-python)])
        (stop-python p)
        (python-running? p))
      #f)

    (test "python-version returns string"
      (let ([p (start-python)])
        (let ([v (python-version p)])
          (stop-python p)
          (string? v)))
      #t)

    (test "python-version contains 3"
      (let ([p (start-python)])
        (let ([v (python-version p)])
          (stop-python p)
          ;; Python 3.x.y
          (let ([n (string-length v)])
            (let loop ([i 0])
              (cond
                [(>= i n) #f]
                [(char=? #\3 (string-ref v i)) #t]
                [else (loop (+ i 1))])))))
      #t)

    (test "python-eval integer"
      (let ([p (start-python)])
        (let ([r (python-eval p "1 + 1")])
          (stop-python p)
          r))
      2)

    (test "python-eval string"
      (let ([p (start-python)])
        (let ([r (python-eval p "'hello'")])
          (stop-python p)
          r))
      "hello")

    (test "python-eval boolean true"
      (let ([p (start-python)])
        (let ([r (python-eval p "True")])
          (stop-python p)
          r))
      #t)

    (test "python-eval boolean false"
      (let ([p (start-python)])
        (let ([r (python-eval p "False")])
          (stop-python p)
          r))
      #f)

    (test "python-eval list"
      (let ([p (start-python)])
        (let ([r (python-eval p "[1,2,3]")])
          (stop-python p)
          r))
      '(1 2 3))

    (test "python-exec and python-eval share state"
      (let ([p (start-python)])
        (python-exec p "x = 42")
        (let ([r (python-eval p "x")])
          (stop-python p)
          r))
      42)

    (test "python-import and use"
      (let ([p (start-python)])
        (python-import p "math")
        (let ([r (python-eval p "math.floor(3.7)")])
          (stop-python p)
          r))
      3)

    (test "python-call with args"
      (let ([p (start-python)])
        (let ([r (python-call p "len" '(1 2 3))])
          (stop-python p)
          r))
      3)

    (test "python-call abs"
      (let ([p (start-python)])
        (let ([r (python-call p "abs" -5)])
          (stop-python p)
          r))
      5)

    (test "python-error? on bad eval"
      (let ([p (start-python)])
        (let ([result
               (guard (exn [#t (let ([r (python-error? exn)])
                                 (stop-python p)
                                 r)])
                 (python-eval p "undefined_var_xyz")
                 (stop-python p)
                 #f)])
          result))
      #t)

    (test "python-error-message is string"
      (let ([p (start-python)])
        (let ([result
               (guard (exn [#t (let ([r (string? (python-error-message exn))])
                                 (stop-python p)
                                 r)])
                 (python-eval p "1/0")
                 (stop-python p)
                 #f)])
          result))
      #t)

    ))

;;;; ===== Summary =====

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
