#!chezscheme
;;; Tests for (std persist closure) — Persistent Closures / Data Serialization

(import (chezscheme) (std persist closure))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn)
                           (condition-message exn)
                           exn))])
       (let ([got expr])
         (if (equal? got expected)
             (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
             (begin (set! fail (+ fail 1))
                    (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(define-syntax test-true
  (syntax-rules ()
    [(_ name expr)
     (test name (if expr #t #f) #t)]))

(printf "--- (std persist closure) tests ---~%~%")

;;; Use a temp directory for file-based tests
(define *tmp-dir*
  (let ([d (string-append "/tmp/jerboa-closure-test-"
                          (number->string (random 1000000)))])
    (system (string-append "mkdir -p " d))
    d))

(define (tmp-path name)
  (string-append *tmp-dir* "/" name))

;;; ======== fasl-serialize / fasl-deserialize ========

(test-true "fasl-serialize returns bytevector"
  (bytevector? (fasl-serialize 42)))

(test-true "fasl-serialize non-empty"
  (> (bytevector-length (fasl-serialize 99)) 0))

(test "roundtrip: integer"
  (fasl-deserialize (fasl-serialize 12345))
  12345)

(test "roundtrip: negative integer"
  (fasl-deserialize (fasl-serialize -99))
  -99)

(test "roundtrip: flonum"
  (fasl-deserialize (fasl-serialize 3.14))
  3.14)

(test "roundtrip: string"
  (fasl-deserialize (fasl-serialize "hello world"))
  "hello world")

(test "roundtrip: empty string"
  (fasl-deserialize (fasl-serialize ""))
  "")

(test "roundtrip: symbol"
  (fasl-deserialize (fasl-serialize 'my-symbol))
  'my-symbol)

(test "roundtrip: boolean #t"
  (fasl-deserialize (fasl-serialize #t))
  #t)

(test "roundtrip: boolean #f"
  (fasl-deserialize (fasl-serialize #f))
  #f)

(test "roundtrip: empty list"
  (fasl-deserialize (fasl-serialize '()))
  '())

(test "roundtrip: list"
  (fasl-deserialize (fasl-serialize '(1 2 3)))
  '(1 2 3))

(test "roundtrip: nested list"
  (fasl-deserialize (fasl-serialize '(1 (2 3) (4 (5)))))
  '(1 (2 3) (4 (5))))

(test "roundtrip: alist"
  (fasl-deserialize (fasl-serialize '((a . 1) (b . 2))))
  '((a . 1) (b . 2)))

(test "roundtrip: vector"
  (fasl-deserialize (fasl-serialize (vector 1 "two" 'three)))
  (vector 1 "two" 'three))

(test "roundtrip: bytevector"
  (fasl-deserialize (fasl-serialize #vu8(10 20 30)))
  #vu8(10 20 30))

(test "roundtrip: char"
  (fasl-deserialize (fasl-serialize #\A))
  #\A)

(test "roundtrip: complex nested"
  (fasl-deserialize
    (fasl-serialize '((step . 3) (data . (1 2 3)) (flag . #t) (name . "test"))))
  '((step . 3) (data . (1 2 3)) (flag . #t) (name . "test")))

;;; ======== closure-save / closure-load ========

(let ([path (tmp-path "integer.fasl")])
  (closure-save 42 path)
  (test "closure-save/load: integer"
    (closure-load path)
    42))

(let ([path (tmp-path "string.fasl")])
  (closure-save "hello persistence" path)
  (test "closure-save/load: string"
    (closure-load path)
    "hello persistence"))

(let ([path (tmp-path "list.fasl")])
  (closure-save '(a b c 1 2 3) path)
  (test "closure-save/load: list"
    (closure-load path)
    '(a b c 1 2 3)))

(let ([path (tmp-path "nested.fasl")])
  (closure-save '((x . 10) (y . (1 2 3)) (z . "data")) path)
  (test "closure-save/load: alist with strings"
    (closure-load path)
    '((x . 10) (y . (1 2 3)) (z . "data"))))

(test-true "closure-save creates file"
  (let ([path (tmp-path "exists-test.fasl")])
    (closure-save 'test-val path)
    (file-exists? path)))

(let ([path (tmp-path "overwrite.fasl")])
  (closure-save 'first path)
  (closure-save 'second path)
  (test "closure-save overwrites existing"
    (closure-load path)
    'second))

;;; ======== checkpoint-computation / resume-computation ========

(let ([path (tmp-path "checkpoint1.fasl")])
  (checkpoint-computation '((step . 1) (result . 0)) path)
  (test "checkpoint/resume: initial state"
    (resume-computation path)
    '((step . 1) (result . 0))))

(let ([path (tmp-path "checkpoint2.fasl")])
  (checkpoint-computation '((step . 5) (acc . (1 2 3 4 5)) (done . #f)) path)
  (test "checkpoint/resume: complex state"
    (resume-computation path)
    '((step . 5) (acc . (1 2 3 4 5)) (done . #f))))

(let ([path (tmp-path "nonexistent-resume.fasl")])
  (test "resume-computation returns empty list for missing file"
    (resume-computation path)
    '()))

(let ([path (tmp-path "update-ckpt.fasl")])
  (checkpoint-computation '((v . 1)) path)
  (checkpoint-computation '((v . 99)) path)
  (test "checkpoint-computation overwrites previous checkpoint"
    (resume-computation path)
    '((v . 99))))

;;; ======== simulated incremental computation ========

(let* ([path (tmp-path "sim-compute.fasl")]
       [state '((counter . 0) (sum . 0))]
       [_ (checkpoint-computation state path)]
       ;; Simulate resuming and updating
       [restored (resume-computation path)]
       [counter (cdr (assq 'counter restored))]
       [sum (cdr (assq 'sum restored))]
       [new-state (list (cons 'counter (+ counter 5))
                        (cons 'sum (+ sum 15)))]
       [_ (checkpoint-computation new-state path)]
       [final (resume-computation path)])
  (test "simulated computation: counter updated"
    (cdr (assq 'counter final))
    5)
  (test "simulated computation: sum updated"
    (cdr (assq 'sum final))
    15))

;;; Summary

(printf "~%~a tests: ~a passed, ~a failed~%" (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
