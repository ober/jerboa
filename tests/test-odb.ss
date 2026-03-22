#!/usr/bin/env scheme-script
#!chezscheme
;;; Test suite for (std odb) — Persistent Object Database

(import (chezscheme)
        (std odb)
        (std clos))

(define test-count 0)
(define pass-count 0)

(define (test name thunk)
  (set! test-count (+ test-count 1))
  (guard (e [#t (display "FAIL: ") (display name) (newline)
              (display "  Error: ") (display (condition-message e)) (newline)
              (when (irritants-condition? e)
                (display "  Irritants: ") (display (condition-irritants e)) (newline))])
    (thunk)
    (set! pass-count (+ pass-count 1))
    (display "PASS: ") (display name) (newline)))

(define (assert-equal actual expected msg)
  (unless (equal? actual expected)
    (error 'assert-equal
           (string-append msg ": expected " (format "~s" expected)
                          " got " (format "~s" actual)))))

(define test-dir "/tmp/test-odb")

;; Clean up before test
(system (string-append "rm -rf " test-dir))

;; =========================================================================
;; Test 1: Open/close store
;; =========================================================================
(test "odb-open creates store"
  (lambda ()
    (let ([store (odb-open test-dir)])
      (assert-equal (odb? store) #t "should be odb")
      (odb-close))))

;; =========================================================================
;; Test 2: define-persistent-class and basic allocation
;; =========================================================================
(odb-open test-dir)

(define-persistent-class <point> ()
  ((x :type :s64 :initform 0)
   (y :type :s64 :initform 0)))

(test "define-persistent-class registers class"
  (lambda ()
    (assert-equal (not (not (odb-class-info '<point>))) #t
                  "class should be registered")))

(test "odb-make creates persistent object"
  (lambda ()
    (let ([p (odb-make <point> :x 42 :y 99)])
      (assert-equal (odb-proxy? p) #t "should be proxy"))))

;; =========================================================================
;; Test 3: Slot read/write
;; =========================================================================
(test "slot ref returns stored values"
  (lambda ()
    (let ([p (odb-make <point> :x 42 :y 99)])
      (assert-equal (odb-slot-ref p 'x) 42 "x should be 42")
      (assert-equal (odb-slot-ref p 'y) 99 "y should be 99"))))

(test "slot set! updates values"
  (lambda ()
    (let ([p (odb-make <point> :x 1 :y 2)])
      (odb-slot-set! p 'x 100)
      (odb-slot-set! p 'y 200)
      (assert-equal (odb-slot-ref p 'x) 100 "x should be 100")
      (assert-equal (odb-slot-ref p 'y) 200 "y should be 200"))))

;; =========================================================================
;; Test 4: Multiple objects
;; =========================================================================
(test "multiple objects have independent storage"
  (lambda ()
    (let ([p1 (odb-make <point> :x 10 :y 20)]
          [p2 (odb-make <point> :x 30 :y 40)])
      (assert-equal (odb-slot-ref p1 'x) 10 "p1.x")
      (assert-equal (odb-slot-ref p2 'x) 30 "p2.x")
      ;; Mutate p1, p2 unaffected
      (odb-slot-set! p1 'x 999)
      (assert-equal (odb-slot-ref p1 'x) 999 "p1.x after set")
      (assert-equal (odb-slot-ref p2 'x) 30 "p2.x unchanged"))))

;; =========================================================================
;; Test 5: Float slots
;; =========================================================================
(define-persistent-class <measurement> ()
  ((value :type :f64 :initform 0.0)
   (count :type :s64 :initform 0)))

(test "f64 slot stores and retrieves floats"
  (lambda ()
    (let ([m (odb-make <measurement> :value 3.14159 :count 1)])
      (let ([v (odb-slot-ref m 'value)])
        ;; Allow small floating point imprecision
        (assert-equal (< (abs (- v 3.14159)) 0.0001) #t
                      "value should be ~3.14159"))
      (assert-equal (odb-slot-ref m 'count) 1 "count should be 1"))))

;; =========================================================================
;; Test 6: doclass iteration
;; =========================================================================
(test "doclass iterates live objects"
  (lambda ()
    (let ([xs '()])
      (doclass (p <point>)
        (set! xs (cons (odb-slot-ref p 'x) xs)))
      ;; We've created several points above: 42, 1(->100), 10(->999), 30
      (assert-equal (> (length xs) 0) #t
                    "should find at least some points"))))

;; =========================================================================
;; Test 7: odb-count
;; =========================================================================
(test "odb-count reports object count"
  (lambda ()
    (let ([n (odb-count '<point>)])
      (assert-equal (> n 0) #t "should have some points"))))

;; =========================================================================
;; Test 8: odb-delete
;; =========================================================================
(test "odb-delete marks object as deleted"
  (lambda ()
    (let* ([before (odb-count '<point>)]
           [p (odb-make <point> :x 777 :y 888)])
      (odb-delete p)
      ;; Count should be same as before (one added, one deleted)
      (assert-equal (odb-count '<point>) before "count after delete"))))

;; =========================================================================
;; Test 9: odb-find
;; =========================================================================
(test "odb-find locates matching object"
  (lambda ()
    (let ([p (odb-make <point> :x 12345 :y 67890)])
      (let ([found (odb-find '<point> (lambda (obj)
                     (= (odb-slot-ref obj 'x) 12345)))])
        (assert-equal (odb-proxy? found) #t "should find object")
        (assert-equal (odb-slot-ref found 'y) 67890 "y should match")))))

;; =========================================================================
;; Test 10: odb-filter
;; =========================================================================
(test "odb-filter returns matching objects"
  (lambda ()
    (let ([results (odb-filter '<point> (lambda (obj)
                     (> (odb-slot-ref obj 'x) 100)))])
      (assert-equal (> (length results) 0) #t
                    "should find objects with x > 100"))))

;; =========================================================================
;; Test 11: odb-sync
;; =========================================================================
(test "odb-sync completes without error"
  (lambda ()
    (odb-sync)))

;; =========================================================================
;; Test 12: Close and reopen — persistence
;; =========================================================================
(odb-close)

(test "reopen preserves data"
  (lambda ()
    (odb-open test-dir)
    ;; Re-register classes (normally done by define-persistent-class at load time)
    (register-persistent-class! '<point>
      '((x :type :s64) (y :type :s64))
      <point>)
    (register-persistent-class! '<measurement>
      '((value :type :f64) (count :type :s64))
      <measurement>)
    ;; Find the object we stored with x=12345
    (let ([found (odb-find '<point> (lambda (obj)
                   (= (odb-slot-ref obj 'x) 12345)))])
      (assert-equal (odb-proxy? found) #t "should find persisted object")
      (assert-equal (odb-slot-ref found 'y) 67890 "y persists"))))

;; =========================================================================
;; Test 13: CLOS integration via slot-ref
;; =========================================================================
(test "CLOS slot-ref routes through mmap"
  (lambda ()
    (let ([p (odb-make <point> :x 555 :y 666)])
      ;; slot-ref via CLOS virtual allocation
      (assert-equal (slot-ref p 'x) 555 "CLOS slot-ref x")
      (assert-equal (slot-ref p 'y) 666 "CLOS slot-ref y"))))

;; =========================================================================
;; Test 14: odb-migrate
;; =========================================================================
(define-persistent-class <point3d> ()
  ((x :type :s64 :initform 0)
   (y :type :s64 :initform 0)
   (z :type :s64 :initform 0)))

(test "odb-migrate copies data with slot mapping"
  (lambda ()
    (let ([p2d (odb-make <point> :x 111 :y 222)])
      (odb-migrate p2d '<point3d>
        (lambda (slot-name old-proxy)
          (case slot-name
            [(x) (odb-slot-ref old-proxy 'x)]
            [(y) (odb-slot-ref old-proxy 'y)]
            [(z) 333])))
      ;; Verify migrated object exists
      (let ([found (odb-find '<point3d> (lambda (obj)
                     (= (odb-slot-ref obj 'z) 333)))])
        (assert-equal (odb-proxy? found) #t "should find migrated object")
        (assert-equal (odb-slot-ref found 'x) 111 "x migrated")
        (assert-equal (odb-slot-ref found 'y) 222 "y migrated")))))

;; =========================================================================
;; Test 15: Negative s64 values
;; =========================================================================
(test "negative s64 values stored correctly"
  (lambda ()
    (let ([p (odb-make <point3d> :x -42 :y -99999 :z 0)])
      (assert-equal (odb-slot-ref p 'x) -42 "negative x")
      (assert-equal (odb-slot-ref p 'y) -99999 "negative y")
      (assert-equal (odb-slot-ref p 'z) 0 "zero z"))))

;; =========================================================================
;; Test 16: CLOS slot-set! routes through mmap
;; =========================================================================
(test "CLOS slot-set! routes through mmap"
  (lambda ()
    (let ([p (odb-make <point> :x 1 :y 2)])
      (slot-set! p 'x 777)
      (slot-set! p 'y 888)
      (assert-equal (slot-ref p 'x) 777 "slot-set! x")
      (assert-equal (slot-ref p 'y) 888 "slot-set! y")
      ;; Also verify via odb-slot-ref (same underlying storage)
      (assert-equal (odb-slot-ref p 'x) 777 "odb-slot-ref x after CLOS set")
      (assert-equal (odb-slot-ref p 'y) 888 "odb-slot-ref y after CLOS set"))))

;; =========================================================================
;; Test 17: CLOS generic function dispatch on persistent class
;; =========================================================================
(define-generic describe-point)
(define-method (describe-point (p <point>))
  (format "point(~a, ~a)" (slot-ref p 'x) (slot-ref p 'y)))

(test "generic function dispatch on persistent objects"
  (lambda ()
    (let ([p (odb-make <point> :x 10 :y 20)])
      (assert-equal (describe-point p) "point(10, 20)"
                    "generic dispatch works"))))

;; =========================================================================
;; Test 18: Region growing (allocate many objects)
;; =========================================================================
(test "region grows to accommodate many objects"
  (lambda ()
    (let loop ([i 0])
      (when (< i 300)
        (odb-make <point> :x i :y (* i 2))
        (loop (+ i 1))))
    ;; Verify we can still find objects
    (let ([found (odb-find '<point> (lambda (obj)
                   (= (odb-slot-ref obj 'x) 299)))])
      (assert-equal (odb-proxy? found) #t "should find object 299")
      (assert-equal (odb-slot-ref found 'y) 598 "y = 299*2"))))

;; =========================================================================
;; Test 19: with-odb-transaction
;; =========================================================================
(test "with-odb-transaction commits on success"
  (lambda ()
    (with-odb-transaction
      (let ([p (odb-make <point> :x 11111 :y 22222)])
        (assert-equal (odb-slot-ref p 'x) 11111 "x inside txn")))))

;; =========================================================================
;; Test 20: Multiple persistent classes coexist
;; =========================================================================
(test "multiple classes have independent storage"
  (lambda ()
    (let ([p (odb-make <point> :x 50 :y 60)]
          [m (odb-make <measurement> :value 2.718 :count 7)])
      (assert-equal (odb-slot-ref p 'x) 50 "point x")
      (assert-equal (odb-slot-ref m 'count) 7 "measurement count")
      ;; Modifying one doesn't affect the other
      (odb-slot-set! p 'x 999)
      (assert-equal (odb-slot-ref m 'count) 7 "measurement unchanged"))))

(odb-close)

;; =========================================================================
;; Summary
;; =========================================================================
(newline)
(display "=========================================") (newline)
(display (format "Results: ~a/~a passed" pass-count test-count)) (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
