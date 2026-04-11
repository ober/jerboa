#!chezscheme
;;; Tests for §4.10 record-as-map — Jerboa records participating in
;;; the (std clojure) polymorphic collection API.

(import (except (jerboa prelude) hash-map)
        (std clojure))

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

(printf "--- record-as-map (§4.10) ---~%~%")

;;; ---- Define test records ---------------------------------------

(defstruct point (x y z))
(defstruct user (name email age))

;;; ---- get on records --------------------------------------------

(define p (make-point 1 2 3))

(test "get by symbol"
  (get p 'x)
  1)

(test "get second field"
  (get p 'y)
  2)

(test "get third field"
  (get p 'z)
  3)

(test "get missing field returns #f by default"
  (get p 'w)
  #f)

(test "get missing field returns default"
  (get p 'w 'none)
  'none)

(test "get by string key (coerced to symbol)"
  (get p "x")
  1)

;;; ---- contains? -------------------------------------------------

(test "contains? true for known field"
  (contains? p 'x)
  #t)

(test "contains? false for unknown field"
  (contains? p 'w)
  #f)

(test "contains? true for string key of known field"
  (contains? p "y")
  #t)

;;; ---- count / empty? --------------------------------------------

(test "count returns number of fields"
  (count p)
  3)

(test "empty? false for record with fields"
  (empty? p)
  #f)

;;; ---- keys / vals -----------------------------------------------

(test "keys returns field name symbols"
  (keys p)
  '(x y z))

(test "vals returns field values in field order"
  (vals p)
  '(1 2 3))

(test "keys on user record"
  (keys (make-user "Alice" "a@x" 30))
  '(name email age))

(test "vals on user record"
  (vals (make-user "Alice" "a@x" 30))
  '("Alice" "a@x" 30))

;;; ---- assoc escapes to pmap -------------------------------------
;;;
;;; assoc on a record returns a persistent-map containing all the
;;; record's fields plus the new binding. This loses the record
;;; type but is uniform and doesn't require per-record reconstruction.

(test "assoc on record returns a persistent-map"
  (persistent-map? (assoc p 'new-key 99))
  #t)

(test "assoc preserves existing fields in the pmap"
  (let ([m (assoc p 'new-key 99)])
    (list (get m 'x) (get m 'y) (get m 'z) (get m 'new-key)))
  '(1 2 3 99))

(test "assoc of known field updates value in pmap escape"
  (let ([m (assoc p 'x 100)])
    (list (get m 'x) (get m 'y) (get m 'z)))
  '(100 2 3))

(test "original record unchanged after assoc"
  (let ([m (assoc p 'x 100)])
    (point-x p))
  1)

(test "assoc multiple bindings in one call"
  (let ([m (assoc p 'a 1 'b 2 'c 3)])
    (list (get m 'a) (get m 'b) (get m 'c) (get m 'x)))
  '(1 2 3 1))

;;; ---- dissoc escapes to pmap ------------------------------------

(test "dissoc returns a persistent-map"
  (persistent-map? (dissoc p 'x))
  #t)

(test "dissoc removes the named field from the pmap"
  (let ([m (dissoc p 'x)])
    (list (contains? m 'x) (contains? m 'y) (contains? m 'z)))
  '(#f #t #t))

(test "dissoc multiple fields"
  (let ([m (dissoc p 'x 'y)])
    (list (contains? m 'x) (contains? m 'y) (contains? m 'z)))
  '(#f #f #t))

(test "original record unchanged after dissoc"
  (let ([m (dissoc p 'x)])
    (point-x p))
  1)

;;; ---- Persistent types still work -------------------------------
;;;
;;; Make sure the record-as-map fallback didn't accidentally catch
;;; persistent-map, persistent-set, or other typed containers.

(define pm (hash-map "a" 1 "b" 2))
(define ps (hash-set 1 2 3))

(test "pmap get still works"
  (get pm "a")
  1)

(test "pmap contains? still works"
  (contains? pm "b")
  #t)

(test "pmap count still works"
  (count pm)
  2)

(test "pmap assoc still returns pmap"
  (let ([m2 (assoc pm "c" 3)])
    (list (persistent-map? m2) (get m2 "c")))
  '(#t 3))

(test "pset count still works"
  (count ps)
  3)

(test "pset contains still works"
  (contains? ps 2)
  #t)

;;; ---- get-in walks records --------------------------------------
;;;
;;; get-in should handle records-in-records, records-in-pmaps,
;;; pmaps-in-records, etc.

(defstruct address (city zip))

(define user-with-addr
  (make-user "Bob" "b@x" (make-address "NYC" "10001")))

(test "get-in walks into a record nested inside a record"
  (get-in user-with-addr '(age city))
  "NYC")

(test "get-in returns default on missing path"
  (get-in user-with-addr '(age zipcode) 'missing)
  'missing)

;;; ---- Summary ---------------------------------------------------
(printf "~%record-as-map: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
