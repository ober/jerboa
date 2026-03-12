#!chezscheme
;;; Tests for (std wasm wasi) — WASI host implementation

(import (chezscheme) (std wasm wasi))

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

(define-syntax test-true
  (syntax-rules ()
    [(_ name expr)
     (test name (if expr #t #f) #t)]))

(define-syntax test-not
  (syntax-rules ()
    [(_ name expr)
     (test name (if expr #f #t) #t)]))

(printf "--- (std wasm wasi) tests ---~%~%")

;;; ======== errno constants ========

(test "errno/success is 0"   wasi-errno/success   0)
(test "errno/badf is 8"      wasi-errno/badf       8)
(test "errno/noent is 44"    wasi-errno/noent     44)
(test "errno/inval is 28"    wasi-errno/inval     28)
(test "errno/nosys is 52"    wasi-errno/nosys     52)
(test "errno/io is 29"       wasi-errno/io        29)

;;; ======== clock IDs ========

(test "clock/realtime is 0"        wasi-clock/realtime        0)
(test "clock/monotonic is 1"       wasi-clock/monotonic       1)
(test "clock/process-cputime is 2" wasi-clock/process-cputime 2)

;;; ======== make-wasi-env ========

(define *env*
  (make-wasi-env
    '("prog" "--flag" "arg1")     ;; args
    '(("HOME" . "/home/user")     ;; env
      ("PATH" . "/usr/bin"))
    #f #f #f                      ;; use default stdin/stdout/stderr
    '(("/sandbox" . "/tmp"))))    ;; preopens

(test-true "wasi-env? predicate" (wasi-env? *env*))
(test-not  "non-env is not wasi-env" (wasi-env? 42))

(test "wasi-env-args"
  (wasi-env-args *env*)
  '("prog" "--flag" "arg1"))

(test "wasi-env-env"
  (wasi-env-env *env*)
  '(("HOME" . "/home/user") ("PATH" . "/usr/bin")))

(test "wasi-env-preopens"
  (wasi-env-preopens *env*)
  '(("/sandbox" . "/tmp")))

;;; ======== wasi-args-get ========

(test "wasi-args-get returns arg list"
  (wasi-args-get *env*)
  '("prog" "--flag" "arg1"))

;;; ======== wasi-args-sizes-get ========

(test "wasi-args-sizes-get count"
  (let-values ([(count size) (wasi-args-sizes-get *env*)])
    count)
  3)

(test "wasi-args-sizes-get size positive"
  (let-values ([(count size) (wasi-args-sizes-get *env*)])
    (> size 0))
  #t)

(test "wasi-args-sizes-get total size"
  ;; "prog"(4+1) + "--flag"(6+1) + "arg1"(4+1) = 17
  (let-values ([(count size) (wasi-args-sizes-get *env*)])
    size)
  17)

;;; ======== wasi-environ-get ========

(test "wasi-environ-get returns alist"
  (wasi-environ-get *env*)
  '(("HOME" . "/home/user") ("PATH" . "/usr/bin")))

;;; ======== wasi-clock-time-get ========

(test-true "wasi-clock-time-get realtime is positive"
  (> (wasi-clock-time-get wasi-clock/realtime) 0))

(test-true "wasi-clock-time-get monotonic is positive"
  (> (wasi-clock-time-get wasi-clock/monotonic) 0))

(test-true "wasi-clock-time-get process-cputime is non-negative"
  (>= (wasi-clock-time-get wasi-clock/process-cputime) 0))

(test-true "clock-time-get unknown clock-id returns a number"
  (number? (wasi-clock-time-get 99)))

;;; ======== wasi-fd-write ========

(test "wasi-fd-write to stdout (bytevector)"
  (let-values ([(port get-bytes) (open-bytevector-output-port)])
    (let ([e (make-wasi-env '() '() #f port #f '())])
      (wasi-fd-write e 1 (string->utf8 "hello"))))
  5)

(test "wasi-fd-write returns byte count"
  (let-values ([(port get-bytes) (open-bytevector-output-port)])
    (let ([e (make-wasi-env '() '() #f port #f '())])
      (wasi-fd-write e 1 (string->utf8 "world"))))
  5)

(test "wasi-fd-write bad fd returns errno/badf"
  (wasi-fd-write *env* 99 (string->utf8 "x"))
  wasi-errno/badf)

(test "wasi-fd-write empty bytevector"
  (let-values ([(port get-bytes) (open-bytevector-output-port)])
    (let ([e (make-wasi-env '() '() #f port #f '())])
      (wasi-fd-write e 1 (make-bytevector 0))))
  0)

;;; ======== wasi-fd-close ========

(test "wasi-fd-close fd > 2 returns success"
  ;; fd 3 is not in the fd-table, but close should return success
  (let ([e (make-wasi-env '() '() #f #f #f '())])
    (wasi-fd-close e 99))
  wasi-errno/success)

(test "wasi-fd-close stdin (fd 0) returns inval"
  (wasi-fd-close *env* 0)
  wasi-errno/inval)

(test "wasi-fd-close stdout (fd 1) returns inval"
  (wasi-fd-close *env* 1)
  wasi-errno/inval)

(test "wasi-fd-close stderr (fd 2) returns inval"
  (wasi-fd-close *env* 2)
  wasi-errno/inval)

;;; ======== wasi-random-get ========

(test "wasi-random-get returns bytevector"
  (bytevector? (wasi-random-get 16))
  #t)

(test "wasi-random-get correct size"
  (bytevector-length (wasi-random-get 32))
  32)

(test "wasi-random-get size 0"
  (bytevector-length (wasi-random-get 0))
  0)

(test "wasi-random-get bytes in range 0-255"
  (let ([bv (wasi-random-get 100)])
    (let loop ([i 0])
      (if (= i 100)
        #t
        (if (and (>= (bytevector-u8-ref bv i) 0)
                 (<= (bytevector-u8-ref bv i) 255))
          (loop (+ i 1))
          #f))))
  #t)

;;; ======== wasi-proc-exit ========

(test "wasi-proc-exit raises wasi-exit-condition"
  (guard (exn [(wasi-exit-condition? exn)
               (wasi-exit-code exn)])
    (wasi-proc-exit 0)
    'not-raised)
  0)

(test "wasi-proc-exit exit code 1"
  (guard (exn [(wasi-exit-condition? exn)
               (wasi-exit-code exn)])
    (wasi-proc-exit 1)
    'not-raised)
  1)

(test "wasi-proc-exit exit code 42"
  (guard (exn [(wasi-exit-condition? exn)
               (wasi-exit-code exn)])
    (wasi-proc-exit 42)
    'not-raised)
  42)

;;; ======== wasi-exit-condition? ========

(test "wasi-exit-condition? on non-condition is false"
  (wasi-exit-condition? 42)
  #f)

(test "wasi-exit-condition? on condition"
  (guard (exn [#t (wasi-exit-condition? exn)])
    (wasi-proc-exit 7)
    #f)
  #t)

;;; ======== make-wasi-imports ========

(test "make-wasi-imports returns hashtable"
  (hashtable? (make-wasi-imports *env*))
  #t)

(test "make-wasi-imports has args_get key"
  (not (eq? #f (hashtable-ref (make-wasi-imports *env*)
                 "wasi_snapshot_preview1/args_get"
                 #f)))
  #t)

;; More robust presence check
(test "make-wasi-imports args_get is a procedure"
  (procedure?
    (hashtable-ref (make-wasi-imports *env*)
      "wasi_snapshot_preview1/args_get"
      #f))
  #t)

(test "make-wasi-imports fd_write is a procedure"
  (procedure?
    (hashtable-ref (make-wasi-imports *env*)
      "wasi_snapshot_preview1/fd_write"
      #f))
  #t)

(test "make-wasi-imports proc_exit is a procedure"
  (procedure?
    (hashtable-ref (make-wasi-imports *env*)
      "wasi_snapshot_preview1/proc_exit"
      #f))
  #t)

(test "make-wasi-imports random_get is a procedure"
  (procedure?
    (hashtable-ref (make-wasi-imports *env*)
      "wasi_snapshot_preview1/random_get"
      #f))
  #t)

(test "make-wasi-imports clock_time_get is a procedure"
  (procedure?
    (hashtable-ref (make-wasi-imports *env*)
      "wasi_snapshot_preview1/clock_time_get"
      #f))
  #t)

(test "make-wasi-imports args_get call returns count"
  (let* ([ht (make-wasi-imports *env*)]
         [f (hashtable-ref ht "wasi_snapshot_preview1/args_get" #f)])
    (f))
  3)

(test "make-wasi-imports environ_get call returns alist"
  (let* ([ht (make-wasi-imports *env*)]
         [f (hashtable-ref ht "wasi_snapshot_preview1/environ_get" #f)])
    (f))
  '(("HOME" . "/home/user") ("PATH" . "/usr/bin")))

;;; ======== with-wasi-env ========

(test "with-wasi-env runs body"
  (with-wasi-env *env*
    42)
  42)

(test "with-wasi-env returns body result"
  (with-wasi-env *env*
    (+ 1 2 3))
  6)

;;; ======== wasi-run ========

(test "wasi-run thunk returning normally exits 0"
  (wasi-run (lambda () 'ok) *env*)
  0)

(test "wasi-run thunk calling proc-exit returns exit code"
  (wasi-run
    (lambda () (wasi-proc-exit 7))
    *env*)
  7)

(test "wasi-run thunk calling proc-exit 0 returns 0"
  (wasi-run
    (lambda () (wasi-proc-exit 0))
    *env*)
  0)

(test "wasi-run thunk calling proc-exit 42 returns 42"
  (wasi-run
    (lambda () (wasi-proc-exit 42))
    *env*)
  42)

;;; Summary

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
