#!chezscheme
;;; Tests for (std gambit-compat) — Gambit/Gerbil runtime compatibility

(import (except (chezscheme)
          make-hash-table hash-table? iota 1+ 1- getenv
          path-extension path-absolute?
          thread? make-mutex mutex? mutex-name
          box box? unbox set-box!)
        (std gambit-compat))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr]
           [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (printf "FAIL: ~s => ~s (expected ~s)~n" 'expr result exp))))]))

(define-syntax check-true
  (syntax-rules ()
    [(_ expr)
     (let ([result expr])
       (if result
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (printf "FAIL: ~s => ~s (expected truthy)~n" 'expr result))))]))

(define-syntax check-false
  (syntax-rules ()
    [(_ expr)
     (let ([result expr])
       (if (not result)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (printf "FAIL: ~s => ~s (expected falsy)~n" 'expr result))))]))

(define (string-contains* haystack needle)
  (let ([hn (string-length haystack)]
        [nn (string-length needle)])
    (let loop ([i 0])
      (cond
        [(> (+ i nn) hn) #f]
        [(string=? (substring haystack i (+ i nn)) needle) #t]
        [else (loop (+ i 1))]))))

(printf "--- Testing (std gambit-compat) ---~n")

;; ========== u8vector ==========
(printf "  u8vector aliases...~n")
(let ([bv (make-u8vector 4 0)])
  (check (u8vector? bv) => #t)
  (check (u8vector-length bv) => 4)
  (u8vector-set! bv 0 65)
  (u8vector-set! bv 1 66)
  (check (u8vector-ref bv 0) => 65)
  (check (u8vector-ref bv 1) => 66))

(let ([bv (u8vector 1 2 3 4 5)])
  (check (u8vector-length bv) => 5)
  (check (u8vector-ref bv 0) => 1)
  (check (u8vector-ref bv 4) => 5)
  (check (u8vector->list bv) => '(1 2 3 4 5)))

(check (u8vector->list (list->u8vector '(10 20 30))) => '(10 20 30))

;; subu8vector
(let ([bv (u8vector 10 20 30 40 50)])
  (check (u8vector->list (subu8vector bv 1 4)) => '(20 30 40)))

;; u8vector-append
(let ([a (u8vector 1 2)] [b (u8vector 3 4 5)])
  (check (u8vector->list (u8vector-append a b)) => '(1 2 3 4 5)))
(check (u8vector->list (u8vector-append)) => '())

;; ========== f64vector ==========
(printf "  f64vector aliases...~n")
(let ([fv (make-f64vector 3 1.5)])
  (check (f64vector-ref fv 0) => 1.5)
  (check (f64vector-length fv) => 3)
  (f64vector-set! fv 1 2.5)
  (check (f64vector-ref fv 1) => 2.5)
  (check (f64vector->list fv) => '(1.5 2.5 1.5)))

;; ========== string/bytes ==========
(printf "  string/bytes conversion...~n")
(let ([bv (string->bytes "hello")])
  (check (bytevector? bv) => #t)
  (check (bytes->string bv) => "hello"))

(check (object->string 42) => "42")
(check (object->string '(a b)) => "(a b)")

;; ========== void? ==========
(printf "  void?...~n")
(check-true (void? (void)))
(check-false (void? 42))
(check-false (void? #f))

;; ========== box ==========
(printf "  box type...~n")
(let ([b (box 42)])
  (check-true (box? b))
  (check (unbox b) => 42)
  (set-box! b 99)
  (check (unbox b) => 99))
(check-false (box? 42))

;; ========== random-integer ==========
(printf "  random-integer...~n")
(let ([r (random-integer 100)])
  (check-true (and (>= r 0) (< r 100))))

;; ========== let/cc ==========
(printf "  let/cc...~n")
(check (let/cc k (k 42) 99) => 42)
(check (let/cc k (+ 1 2)) => 3)

;; ========== with-exception-catcher ==========
(printf "  with-exception-catcher...~n")
(check (with-exception-catcher
         (lambda (e) 'caught)
         (lambda () (error 'test "boom")))
       => 'caught)
(check (with-exception-catcher
         (lambda (e) 'caught)
         (lambda () 42))
       => 42)

;; Also test with-exception-catcher* (alias)
(check (with-exception-catcher*
         (lambda (e) 'got-it)
         (lambda () (/ 1 0)))
       => 'got-it)

;; ========== with-unwind-protect ==========
(printf "  with-unwind-protect...~n")
(let ([cleaned #f])
  (with-unwind-protect
    (lambda () 42)
    (lambda () (set! cleaned #t)))
  (check-true cleaned))

;; ========== call-with-input/output-string ==========
(printf "  call-with-input/output-string...~n")
(check (call-with-input-string "(+ 1 2)"
         (lambda (p) (read p)))
       => '(+ 1 2))

(check (call-with-output-string
         (lambda (p) (display "hello" p) (display " world" p)))
       => "hello world")

;; ========== read-line ==========
(printf "  read-line...~n")
(let ([p (open-input-string "line1\nline2\nline3")])
  (check (read-line p) => "line1")
  (check (read-line p) => "line2")
  (check (read-line p) => "line3"))

;; ========== force-output ==========
(printf "  force-output...~n")
;; Just verify it doesn't error
(force-output)
(set! pass-count (+ pass-count 1))

;; ========== write-u8 ==========
(printf "  write-u8...~n")
;; Test on a binary port
(let-values ([(port getter) (open-bytevector-output-port)])
  (write-u8 65 port)
  (write-u8 66 port)
  (let ([bv (getter)])
    (check (bytevector-u8-ref bv 0) => 65)
    (check (bytevector-u8-ref bv 1) => 66)))

;; ========== display-exception ==========
(printf "  display-exception...~n")
(let ([out (with-output-to-string
             (lambda ()
               (display-exception "test error" (current-output-port))))])
  (check-true (> (string-length out) 0)))

;; ========== time->seconds / current-second ==========
(printf "  time->seconds / current-second...~n")
(let ([t (current-time 'time-utc)])
  (let ([s (time->seconds t)])
    (check-true (and (number? s) (> s 0)))))
(let ([s (current-second)])
  (check-true (and (number? s) (> s 1000000000))))
;; Non-time passthrough
(check (time->seconds 42) => 42)

;; ========== date->string* ==========
(printf "  date->string*...~n")
(let ([d (current-date)])
  (let ([s (date->string* d "~Y-~m-~d ~H:~M:~S")])
    (check-true (> (string-length s) 10))
    ;; Should contain the year
    (check-true (string-contains* s (number->string (date-year d))))))

;; ========== getenv* / setenv* ==========
(printf "  getenv* / setenv*...~n")
(check-true (string? (getenv* "HOME")))
(check (getenv* "NONEXISTENT_VAR_XYZ_12345") => #f)
(check (getenv* "NONEXISTENT_VAR_XYZ_12345" "default") => "default")

(setenv* "JERBOA_TEST_VAR" "hello")
(check (getenv* "JERBOA_TEST_VAR") => "hello")

;; ========== user-name ==========
(printf "  user-name...~n")
(check-true (string? (user-name)))

;; ========== get-environment-variables ==========
(printf "  get-environment-variables...~n")
(let ([vars (get-environment-variables)])
  (check-true (list? vars))
  ;; Should have at least some env vars
  (check-true (> (length vars) 0))
  ;; Each entry should be a pair
  (check-true (pair? (car vars)))
  ;; HOME should be in there
  (check-true (assoc "HOME" vars)))

;; ========== cpu-count ==========
(printf "  cpu-count...~n")
(check-true (and (integer? (cpu-count)) (> (cpu-count) 0)))

;; ========== directory-files ==========
(printf "  directory-files...~n")
(let ([files (directory-files ".")])
  (check-true (list? files))
  (check-true (> (length files) 0)))

;; Gambit-style settings list
(let ([files (directory-files* (list 'path: "."))])
  (check-true (list? files))
  (check-true (> (length files) 0)))

;; Non-existent directory → empty list
(check (directory-files* "/nonexistent_xyz_12345") => '())

;; ========== truncate-quotient / truncate-remainder / arithmetic-shift ==========
(printf "  arithmetic compat...~n")
(check (truncate-quotient 7 2) => 3)
(check (truncate-remainder 7 2) => 1)
(check (arithmetic-shift 1 4) => 16)
(check (arithmetic-shift 16 -2) => 4)

;; ========== hash-constructor ==========
(printf "  hash-constructor...~n")
(let ([ht (hash-constructor ("name" "Alice") ("age" 30))])
  (check (hash-ref ht "name") => "Alice")
  (check (hash-ref ht "age") => 30))

;; ========== gerbil-parameterize ==========
(printf "  gerbil-parameterize...~n")
(define test-param (make-parameter 0))
(gerbil-parameterize ((test-param 42))
  (check (test-param) => 42))
;; Value persists after gerbil-parameterize exits (global mutation)
(check (test-param) => 42)

;; ========== spawn / thread basics ==========
(printf "  spawn / threading...~n")
(let ([result-box (box #f)])
  (let ([t (spawn (lambda () (set-box! result-box 'done)))])
    (thread-join! t)
    (check (unbox result-box) => 'done)))

(let ([result-box (box #f)])
  (let ([t (spawn/name "test-thread"
             (lambda () (set-box! result-box (thread-name (current-thread)))))])
    (thread-join! t)
    (check (unbox result-box) => "test-thread")))

;; thread-sleep!
(let ([start (current-second)])
  (thread-sleep! 0.05)
  (let ([elapsed (- (current-second) start)])
    (check-true (>= elapsed 0.04))))

;; ========== with-catch (re-exported from sugar) ==========
(printf "  with-catch...~n")
(check (with-catch
         (lambda (e) 'caught)
         (lambda () (error 'test "oops")))
       => 'caught)

;; ========== cut / cute (re-exported from sugar) ==========
(printf "  cut/cute...~n")
(check ((cut + <> 10) 5) => 15)
(check ((cut * <> <>) 3 4) => 12)
(check ((cute + <> 10) 5) => 15)

;; ========== open-input/output-u8vector ==========
(printf "  u8vector ports...~n")
(let ([bv (u8vector 104 101 108 108 111)]) ;; "hello" in ASCII
  (let ([p (open-input-u8vector (list 'init: bv))])
    (check (read-line p) => "hello")))

(let ([p (open-output-u8vector)])
  (display "hi" p)
  (let ([bv (get-output-u8vector p)])
    (check (bytes->string bv) => "hi")))

;; ========== write-subu8vector / read-subu8vector ==========
(printf "  write-subu8vector / read-subu8vector...~n")
(let-values ([(out getter) (open-bytevector-output-port)])
  (let ([bv (u8vector 65 66 67 68 69)])  ;; ABCDE
    (write-subu8vector bv 1 4 out)
    (let ([result (getter)])
      (check (bytevector-length result) => 3)
      (check (bytevector-u8-ref result 0) => 66)  ;; B
      (check (bytevector-u8-ref result 2) => 68)))) ;; D

;; ========== pp ==========
(printf "  pp...~n")
(let ([out (with-output-to-string (lambda () (pp '(a b c))))])
  (check-true (> (string-length out) 0)))

;; ========== Summary ==========
(printf "~n--- Results: ~a passed, ~a failed ---~n" pass-count fail-count)
(when (> fail-count 0) (exit 1))
