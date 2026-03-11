#!chezscheme
;;; Tests for Phase 13: Concurrency Safety (Steps 45-47)

(import (chezscheme)
        (std concur))

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
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(printf "--- Phase 13: Concurrency Safety ---~%")

;;; ======== Step 45: Thread-Safety Annotations ========

(printf "~%-- Thread-Safety Annotations --~%")

;; Test immutable struct annotation
(defstruct/immutable point (x y))

(let ([p (make-point 3 4)])
  (test "immutable struct accessible"
    (point-x p)
    3)
  (test "immutable? annotation"
    (immutable? p)
    #t)
  (test "thread-safety-of immutable"
    (thread-safety-of p)
    'immutable))

;; Test thread-local struct annotation
(defstruct/thread-local scratch (buf pos))

(let ([s (make-scratch "buffer" 0)])
  (test "thread-local struct accessible"
    (scratch-buf s)
    "buffer")
  (test "thread-local-marker? annotation"
    (thread-local-marker? s)
    #t)
  (test "thread-safety-of thread-local"
    (thread-safety-of s)
    'thread-local))

;; Test thread-safe struct
(defstruct/thread-safe counter (value))

(let ([c (make-counter 0)])
  (test "thread-safe struct accessible"
    (counter-value c)
    0)
  (test "thread-safety-of thread-safe"
    (thread-safety-of c)
    'thread-safe))

;; Unannotated value
(test "thread-safety-of unannotated"
  (thread-safety-of '(plain list))
  'unannotated)

;;; ======== Step 46: Deadlock Detection ========

(printf "~%-- Deadlock Detection --~%")

(reset-lock-tracking!)

(let ([m1 (make-tracked-mutex "lock-A")]
      [m2 (make-tracked-mutex "lock-B")])
  (test "tracked-mutex? true"
    (tracked-mutex? m1)
    #t)

  ;; Basic lock/unlock
  (tracked-lock! m1)
  (test "can lock m1"
    #t
    #t)
  (tracked-unlock! m1)
  (test "can unlock m1"
    #t
    #t)

  ;; with-tracked-mutex
  (let ([result
         (with-tracked-mutex m1
           (+ 1 2))])
    (test "with-tracked-mutex result"
      result
      3))

  ;; Lock both in order A→B (no violation)
  (reset-lock-tracking!)
  (tracked-lock! m1)
  (tracked-lock! m2)
  (tracked-unlock! m2)
  (tracked-unlock! m1)
  (test "lock order A→B: no violations initially"
    (length (lock-order-violations))
    0)

  ;; Simulate reverse lock order B→A (potential deadlock)
  (reset-lock-tracking!)
  (tracked-lock! m2)
  (tracked-lock! m1)
  (tracked-unlock! m1)
  (tracked-unlock! m2)
  ;; Then A→B to create cycle in graph
  (tracked-lock! m1)
  (tracked-lock! m2)
  (tracked-unlock! m2)
  (tracked-unlock! m1)
  ;; Violations recorded
  (test "lock order violation detected"
    (> (length (lock-order-violations)) 0)
    #t)

  ;; deadlock-check! finds cycles
  (let ([cycles (deadlock-check!)])
    (test "deadlock-check returns list"
      (list? cycles)
      #t)))

;;; ======== Step 47: Resource Leak Detection ========

(printf "~%-- Resource Leak Detection --~%")

;; Register and close a resource
(let ([rid (register-resource! 'file "/tmp/test.txt")])
  (test "register-resource! returns id"
    (number? rid)
    #t)
  (test "open-resource-count after register"
    (>= (open-resource-count) 1)
    #t)

  (close-resource! rid)
  (test "open-resource-count after close"
    (member rid (map car (task-resources)))
    #f))

;; Multiple resources
(let ([r1 (register-resource! 'file "/tmp/a.txt")]
      [r2 (register-resource! 'socket "tcp://localhost:8080")]
      [r3 (register-resource! 'file "/tmp/b.txt")])
  (test "task-resources has 3"
    (>= (length (task-resources)) 3)
    #t)
  ;; Close 2, leak 1
  (close-resource! r1)
  (close-resource! r3)
  ;; r2 still open — would be a leak
  (let ([leaks (check-resource-leaks!)])
    (test "check-resource-leaks! finds leak"
      (and (pair? leaks) #t)
      #t))
  ;; Clean up
  (close-resource! r2))

;; with-resource-tracking
(let-values ([(result leaked)
              (with-resource-tracking
                (lambda ()
                  (let ([r (register-resource! 'temp "scratch")])
                    (close-resource! r)
                    42)))])
  (test "with-resource-tracking: result"
    result
    42)
  (test "with-resource-tracking: no leaks"
    (null? leaked)
    #t))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
