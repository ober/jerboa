#!chezscheme
;;; Tests for (std mmap-btree) — File-backed B+ tree

(import (chezscheme) (std mmap-btree))

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
    [(_ name expr pred)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (pred got)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: value ~s failed predicate~%" name got)))))]))

;; Helper: create a temp file path
(define (make-temp-path prefix)
  (string-append "/tmp/" prefix "-" (number->string (random 1000000)) ".btree"))

;; Helper: open, use, close and delete
(define-syntax with-temp-btree
  (syntax-rules ()
    [(_ var body ...)
     (let* ([path (make-temp-path "test")]
            [var  (open-btree path)])
       (let ([result (begin body ...)])
         (when (not (btree? var))
           (void)) ;; just a guard
         result))]))

(printf "--- (std mmap-btree) tests ---~%")

;; ========== Basic open/close ==========

(test "btree/open creates btree"
  (let* ([path (make-temp-path "basic")]
         [t    (open-btree path)])
    (btree? t))
  #t)

(test "btree/order default is 4"
  (let* ([path (make-temp-path "order")]
         [t    (open-btree path)])
    (btree-order t))
  4)

(test "btree/order custom"
  (let* ([path (make-temp-path "order2")]
         [t    (open-btree path 'order 8)])
    (btree-order t))
  8)

(test "btree/path stored"
  (let* ([path (make-temp-path "path")]
         [t    (open-btree path)])
    (string? (btree-path t)))
  #t)

(test "btree/size initially 0"
  (let* ([path (make-temp-path "size0")]
         [t    (open-btree path)])
    (btree-size t))
  0)

;; ========== btree-put! and btree-get ==========

(test "btree/put and get"
  (let* ([path (make-temp-path "put")]
         [t    (open-btree path)])
    (btree-put! t 'foo 42)
    (btree-get t 'foo))
  42)

(test "btree/get missing returns #f"
  (let* ([path (make-temp-path "miss")]
         [t    (open-btree path)])
    (btree-get t 'missing))
  #f)

(test "btree/size increases after put"
  (let* ([path (make-temp-path "size1")]
         [t    (open-btree path)])
    (btree-put! t 'a 1)
    (btree-put! t 'b 2)
    (btree-put! t 'c 3)
    (btree-size t))
  3)

(test "btree/update existing key"
  (let* ([path (make-temp-path "upd")]
         [t    (open-btree path)])
    (btree-put! t 'x 10)
    (btree-put! t 'x 20)
    (btree-get t 'x))
  20)

(test "btree/update does not change size"
  (let* ([path (make-temp-path "updsize")]
         [t    (open-btree path)])
    (btree-put! t 'x 10)
    (btree-put! t 'x 20)
    (btree-size t))
  1)

;; ========== btree-has? ==========

(test "btree/has existing key"
  (let* ([path (make-temp-path "has1")]
         [t    (open-btree path)])
    (btree-put! t 'k "v")
    (btree-has? t 'k))
  #t)

(test "btree/has missing key"
  (let* ([path (make-temp-path "has2")]
         [t    (open-btree path)])
    (btree-has? t 'missing))
  #f)

;; ========== btree-delete! ==========

(test "btree/delete removes key"
  (let* ([path (make-temp-path "del")]
         [t    (open-btree path)])
    (btree-put! t 'x 1)
    (btree-delete! t 'x)
    (btree-get t 'x))
  #f)

(test "btree/delete reduces size"
  (let* ([path (make-temp-path "delsize")]
         [t    (open-btree path)])
    (btree-put! t 'a 1)
    (btree-put! t 'b 2)
    (btree-delete! t 'a)
    (btree-size t))
  1)

(test "btree/delete non-existent is noop"
  (let* ([path (make-temp-path "delnoop")]
         [t    (open-btree path)])
    (btree-put! t 'a 1)
    (btree-delete! t 'z) ;; doesn't exist
    (btree-size t))
  1)

;; ========== btree-keys / btree-values ==========

(test "btree/keys sorted"
  (let* ([path (make-temp-path "keys")]
         [t    (open-btree path)])
    (btree-put! t "c" 3)
    (btree-put! t "a" 1)
    (btree-put! t "b" 2)
    (btree-keys t))
  '("a" "b" "c"))

(test "btree/values in key order"
  (let* ([path (make-temp-path "vals")]
         [t    (open-btree path)])
    (btree-put! t "c" 3)
    (btree-put! t "a" 1)
    (btree-put! t "b" 2)
    (btree-values t))
  '(1 2 3))

;; ========== btree->alist ==========

(test "btree->alist sorted"
  (let* ([path (make-temp-path "alist")]
         [t    (open-btree path)])
    (btree-put! t "z" 26)
    (btree-put! t "a" 1)
    (btree-put! t "m" 13)
    (btree->alist t))
  '(("a" . 1) ("m" . 13) ("z" . 26)))

;; ========== alist->btree ==========

(test "alist->btree/basic"
  (let* ([path (make-temp-path "fromalist")]
         [t    (alist->btree path '(("x" . 10) ("y" . 20) ("z" . 30)))])
    (btree-size t))
  3)

(test "alist->btree/values retrievable"
  (let* ([path (make-temp-path "fromalist2")]
         [t    (alist->btree path '(("hello" . 1) ("world" . 2)))])
    (btree-get t "hello"))
  1)

;; ========== btree-fold ==========

(test "btree-fold/sum values"
  (let* ([path (make-temp-path "fold")]
         [t    (open-btree path)])
    (btree-put! t "a" 10)
    (btree-put! t "b" 20)
    (btree-put! t "c" 30)
    (btree-fold t (lambda (k v acc) (+ acc v)) 0))
  60)

;; ========== btree-range ==========

(test "btree-range/subset"
  (let* ([path (make-temp-path "range")]
         [t    (open-btree path)])
    (btree-put! t "a" 1)
    (btree-put! t "b" 2)
    (btree-put! t "c" 3)
    (btree-put! t "d" 4)
    (btree-put! t "e" 5)
    (btree-range t "b" "d"))
  '(("b" . 2) ("c" . 3) ("d" . 4)))

;; ========== Persistence ==========

(test "btree/persists across close/open"
  (let* ([path (make-temp-path "persist")])
    ;; Write
    (let ([t1 (open-btree path)])
      (btree-put! t1 "key1" "value1")
      (btree-put! t1 "key2" "value2")
      (close-btree t1))
    ;; Read back
    (let ([t2 (open-btree path)])
      (let ([v1 (btree-get t2 "key1")]
            [v2 (btree-get t2 "key2")])
        (list v1 v2))))
  '("value1" "value2"))

;; ========== Transactions ==========

(test "btree/commit persists"
  (let* ([path (make-temp-path "txn")])
    (let ([t (open-btree path)])
      (with-btree-transaction t
        (btree-put! t "committed" 99))
      ;; After commit, value should be there
      (btree-get t "committed")))
  99)

(test "btree/rollback reverts"
  ;; Use with-btree-transaction to set up a snapshot, then rollback on error
  (let* ([path (make-temp-path "rollback")]
         [t    (open-btree path)])
    (btree-put! t "before" 1)
    ;; Wrap in transaction, but then error to trigger rollback
    (guard (exn [#t 'ok])
      (with-btree-transaction t
        (btree-put! t "during" 2)
        (error 'test "rollback!")))
    ;; "before" should be back, "during" should be gone
    (list (btree-has? t "before")
          (btree-has? t "during")))
  '(#t #f))

;; Simpler rollback test
(test "btree/rollback via with-btree-transaction on error"
  (let* ([path (make-temp-path "rollback2")]
         [t    (open-btree path)])
    (btree-put! t "stable" 1)
    (guard (exn [#t 'caught])
      (with-btree-transaction t
        (btree-put! t "unstable" 2)
        (error 'test "deliberate error")))
    ;; After rollback, unstable key should be gone
    (btree-has? t "unstable"))
  #f)

;; ========== Large tree (force splits) ==========

(test "btree/many inserts and lookups"
  (let* ([path (make-temp-path "large")]
         [t    (open-btree path)])
    ;; Insert 50 items
    (let loop ([i 0])
      (when (< i 50)
        (btree-put! t i (* i i))
        (loop (+ i 1))))
    ;; Check all values
    (let loop ([i 0] [ok #t])
      (if (= i 50)
        ok
        (loop (+ i 1)
              (and ok (= (btree-get t i) (* i i)))))))
  #t)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
