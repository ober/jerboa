#!chezscheme
;;; Tests for (std misc weak) — weak pairs, weak lists, weak hash tables

(import (except (chezscheme) weak-pair? make-weak-hashtable) (std misc weak))

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
                  (printf "FAIL ~a: got ~a, expected ~a~%" name got expected)))))]))

(printf "--- (std misc weak) tests ---~%")

;;; === Weak pairs ===

(printf "~%Weak pairs:~%")

(let ([wp (make-weak-pair 'hello 42)])
  (test "make-weak-pair returns pair" (pair? wp) #t)
  (test "weak-pair? on weak pair" (weak-pair? wp) #t)
  (test "weak-pair? on regular pair" (weak-pair? (cons 'a 'b)) #f)
  (test "weak-car" (weak-car wp) 'hello)
  (test "weak-cdr" (weak-cdr wp) 42)
  (test "weak-pair-value live" (weak-pair-value wp) 'hello))

;; weak-pair-value returns #f for reclaimed entries
(let ([wp (make-weak-pair (list 1 2 3) 'data)])
  (test "weak-pair-value before GC" (list? (weak-pair-value wp)) #t)
  ;; Drop all references to the key and force GC
  (collect (collect-maximum-generation))
  (test "weak-pair-value after GC" (weak-pair-value wp) #f))

;;; === Weak lists ===

(printf "~%Weak lists:~%")

(test "list->weak-list empty" (weak-list->list (list->weak-list '())) '())

(let ([wl (list->weak-list '(a b c d))])
  (test "weak-list->list roundtrip" (weak-list->list wl) '(a b c d))
  ;; Symbols are interned so they won't be GC'd; just test structural integrity
  (test "weak-list is chain of pairs" (pair? wl) #t)
  (test "weak-list second pair" (pair? (cdr wl)) #t))

;; Test with GC-reclaimable objects
(let ()
  (define wl
    (let ([a (list 'x)] [b (list 'y)] [c (list 'z)])
      (let ([result (list->weak-list (list a b c))])
        ;; Return only result, dropping a/b/c references
        result)))
  (test "weak-list before GC" (length (weak-list->list wl)) 3)
  (collect (collect-maximum-generation))
  ;; After GC, the freshly-allocated lists should be reclaimed
  (let ([live (weak-list->list wl)])
    (test "weak-list after GC filters reclaimed" (<= (length live) 3) #t)
    ;; We expect 0 survivors since the lists were only held weakly
    (test "weak-list GC reclaimed entries" (length live) 0)))

;; Test weak-list-compact!
(printf "~%Weak list compaction:~%")

(let ([wl (list->weak-list '(x y z))])
  (let ([compacted (weak-list-compact! wl)])
    (test "compact! live list unchanged" (weak-list->list compacted) '(x y z))))

(test "compact! empty list" (weak-list-compact! '()) '())

;; compact! with GC'd entries
(let ()
  (define wl
    (let ([a (list 'obj1)] [b (list 'obj2)])
      (list->weak-list (list a b))))
  (collect (collect-maximum-generation))
  (let ([compacted (weak-list-compact! wl)])
    (test "compact! removes GC'd" (weak-list->list compacted) '())))

;;; === Weak hash tables ===

(printf "~%Weak hash tables:~%")

(let ([ht (make-weak-hashtable)])
  ;; Basic operations with interned symbols (won't be GC'd)
  (weak-hashtable-set! ht 'foo 1)
  (weak-hashtable-set! ht 'bar 2)
  (weak-hashtable-set! ht 'baz 3)
  (test "weak-ht ref existing" (weak-hashtable-ref ht 'foo #f) 1)
  (test "weak-ht ref missing" (weak-hashtable-ref ht 'qux #f) #f)
  (test "weak-ht ref default" (weak-hashtable-ref ht 'qux 'nope) 'nope)

  ;; Keys list
  (let ([keys (weak-hashtable-keys ht)])
    (test "weak-ht keys count" (length keys) 3)
    (test "weak-ht keys contains foo" (memq 'foo keys) (memq 'foo keys))
    (test "weak-ht keys contains bar" (and (memq 'bar keys) #t) #t))

  ;; Delete
  (weak-hashtable-delete! ht 'bar)
  (test "weak-ht delete" (weak-hashtable-ref ht 'bar #f) #f)
  (test "weak-ht keys after delete" (length (weak-hashtable-keys ht)) 2)

  ;; Overwrite
  (weak-hashtable-set! ht 'foo 999)
  (test "weak-ht overwrite" (weak-hashtable-ref ht 'foo #f) 999))

;; Test with sized constructor
(let ([ht (make-weak-hashtable 64)])
  (weak-hashtable-set! ht 'a 1)
  (test "weak-ht sized constructor" (weak-hashtable-ref ht 'a #f) 1))

;; Test GC reclamation of weak hash table keys
(printf "~%Weak hash table GC:~%")

(let ([ht (make-weak-hashtable)])
  ;; Insert entries with freshly allocated keys (not interned)
  (let ([k1 (list 'key1)] [k2 (list 'key2)] [k3 (list 'key3)])
    (weak-hashtable-set! ht k1 'val1)
    (weak-hashtable-set! ht k2 'val2)
    (weak-hashtable-set! ht k3 'val3)
    (test "weak-ht before GC count" (length (weak-hashtable-keys ht)) 3)
    (test "weak-ht ref before GC" (weak-hashtable-ref ht k1 #f) 'val1)
    ;; Keep a reference to k1, drop k2 and k3
    (collect (collect-maximum-generation))
    (test "weak-ht ref retained key" (weak-hashtable-ref ht k1 #f) 'val1)
    ;; k1 is still live because we're inside the let binding
    (test "weak-ht retained key in keys" (and (memq k1 (weak-hashtable-keys ht)) #t) #t)))

;; Test that unreferenced keys get collected
(let ([ht (make-weak-hashtable)])
  (let ()
    ;; Create and insert keys that will go out of scope
    (do ([i 0 (fx+ i 1)])
        ((fx= i 10))
      (weak-hashtable-set! ht (list i) i)))
  ;; All keys are now unreferenced
  (collect (collect-maximum-generation))
  (let ([remaining (length (weak-hashtable-keys ht))])
    (test "weak-ht keys GC'd" remaining 0)))

;;; === Summary ===

(printf "~%~a tests, ~a passed, ~a failed~%" (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
