#!chezscheme
;;; Tests for (std misc cont-marks) — Continuation marks

(import (chezscheme) (std misc cont-marks))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn
              [#t (set! fail (+ fail 1))
                  (printf "FAIL ~a: exception ~a~%" name
                    (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1))
                  (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(printf "--- (std misc cont-marks) tests ---~%")

;; Test 1: Basic mark and retrieve
(let ([marks (with-continuation-mark 'key1 'val1
               (current-continuation-marks))])
  (test "basic mark retrieve"
    (continuation-mark-set->list marks 'key1)
    '(val1))
  (test "basic mark first"
    (continuation-mark-set-first marks 'key1)
    'val1))

;; Test 2: Empty marks
(let ([marks (current-continuation-marks)])
  (test "empty marks list"
    (continuation-mark-set->list marks 'anything)
    '())
  (test "empty marks first"
    (continuation-mark-set-first marks 'anything)
    #f)
  (test "empty marks first with default"
    (continuation-mark-set-first marks 'anything 'default)
    'default))

;; Test 3: Nested marks with same key — most recent wins for first,
;; all returned for list
(let ([marks (with-continuation-mark 'key 'outer
               (let ([m (with-continuation-mark 'key 'inner
                          (current-continuation-marks))])
                 m))])
  (test "nested same key - list returns both"
    (continuation-mark-set->list marks 'key)
    '(inner outer))
  (test "nested same key - first returns most recent"
    (continuation-mark-set-first marks 'key)
    'inner))

;; Test 4: Multiple keys in same frame
(let ([marks (with-continuation-mark 'k1 'v1
               (with-continuation-mark 'k2 'v2
                 (current-continuation-marks)))])
  (test "multiple keys - k1"
    (continuation-mark-set->list marks 'k1)
    '(v1))
  (test "multiple keys - k2"
    (continuation-mark-set->list marks 'k2)
    '(v2)))

;; Test 5: Same key in same frame — value replaced (tail-call behavior)
(let ([marks (with-continuation-mark 'key 'first
               (with-continuation-mark 'key 'replaced
                 (current-continuation-marks)))])
  (test "same frame replace - list"
    (continuation-mark-set->list marks 'key)
    '(replaced))
  (test "same frame replace - first"
    (continuation-mark-set-first marks 'key)
    'replaced))

;; Test 6: Marks across function calls
(define (inner-fn)
  (with-continuation-mark 'depth 'inner
    (current-continuation-marks)))

(define (outer-fn)
  (with-continuation-mark 'depth 'outer
    (let ([m (inner-fn)])
      m)))

(let ([marks (outer-fn)])
  (test "across calls - list"
    (continuation-mark-set->list marks 'depth)
    '(inner outer))
  (test "across calls - first"
    (continuation-mark-set-first marks 'depth)
    'inner))

;; Test 7: call-with-immediate-continuation-mark
(test "immediate mark present"
  (with-continuation-mark 'imm 42
    (call-with-immediate-continuation-mark 'imm values))
  42)

(test "immediate mark absent"
  (call-with-immediate-continuation-mark 'imm values)
  #f)

(test "immediate mark absent with default"
  (call-with-immediate-continuation-mark 'imm 'none values)
  'none)

;; call-with-immediate-continuation-mark only looks at the innermost frame,
;; so a key set in an outer frame is not visible in an inner frame.
(test "immediate mark - only sees innermost frame"
  (with-continuation-mark 'imm 'outer
    (let ([result (with-continuation-mark 'other 'x
                    (call-with-immediate-continuation-mark 'imm 'missing values))])
      result))
  'missing)

;; But if the key is in the same frame, it is visible.
(test "immediate mark - key in same frame"
  (with-continuation-mark 'imm 'here
    (call-with-immediate-continuation-mark 'imm 'default values))
  'here)

;; Test 8: Non-symbol keys
;; Note: Chez uses eq? for key comparison, so keys must be the same object.
;; Symbols and fixnums are eq?-comparable; strings require using the same binding.
(let ([k "string-key"])
  (let ([marks (with-continuation-mark k 100
                 (current-continuation-marks))])
    (test "string key (same object)"
      (continuation-mark-set-first marks k)
      100)))

(let ([marks (with-continuation-mark 42 'num-key-val
               (current-continuation-marks))])
  (test "number key"
    (continuation-mark-set-first marks 42)
    'num-key-val))

;; Test 9: Marks don't leak outside their scope
(let ([before (current-continuation-marks)])
  (with-continuation-mark 'scoped 'yes
    (void))
  (let ([after (current-continuation-marks)])
    (test "marks don't leak - before"
      (continuation-mark-set->list before 'scoped)
      '())
    (test "marks don't leak - after"
      (continuation-mark-set->list after 'scoped)
      '())))

;; Test 10: Multiple different keys across nested frames
(let ([marks (with-continuation-mark 'a 1
               (let ([m (with-continuation-mark 'b 2
                          (let ([m2 (with-continuation-mark 'c 3
                                      (current-continuation-marks))])
                            m2))])
                 m))])
  (test "three nested keys - a"
    (continuation-mark-set->list marks 'a)
    '(1))
  (test "three nested keys - b"
    (continuation-mark-set->list marks 'b)
    '(2))
  (test "three nested keys - c"
    (continuation-mark-set->list marks 'c)
    '(3))
  (test "three nested keys - missing"
    (continuation-mark-set->list marks 'z)
    '()))

;; Summary
(printf "~%--- Results: ~a passed, ~a failed ---~%" pass fail)
(when (> fail 0) (exit 1))
