#!chezscheme
(import (chezscheme) (std net zero-copy))

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

(printf "--- Phase 2d: Zero-Copy Networking ---~%~%")

;; Test 1: make-buffer-pool
(let ([pool (make-buffer-pool 1024 4)])
  (test "pool-created" (buffer-pool? pool) #t)
  (let ([stats (buffer-pool-stats pool)])
    (test "pool-total" (cdr (assq 'total stats)) 4)
    (test "pool-available" (cdr (assq 'available stats)) 4)
    (test "pool-buf-size" (cdr (assq 'buf-size stats)) 1024)))

;; Test 2: pool-acquire! returns buffer
(let ([pool (make-buffer-pool 512 2)])
  (let-values ([(id bv) (pool-acquire! pool)])
    (test "acquire-returns-id" (integer? id) #t)
    (test "acquire-returns-bytevector"
      (bytevector? bv)
      #t)
    (test "buffer-has-right-size"
      (bytevector-length bv)
      512)
    (pool-release! pool id)))

;; Test 3: acquire and release, stats update
(let ([pool (make-buffer-pool 64 3)])
  (let-values ([(id bv) (pool-acquire! pool)])
    (let ([stats-during (buffer-pool-stats pool)])
      (test "available-decreases-on-acquire"
        (cdr (assq 'available stats-during))
        2)
      (pool-release! pool id)
      (let ([stats-after (buffer-pool-stats pool)])
        (test "available-restores-on-release"
          (cdr (assq 'available stats-after))
          3)))))

;; Test 4: make-buffer-slice
(let ([pool (make-buffer-pool 256 2)])
  (let-values ([(id bv) (pool-acquire! pool)])
    ;; Write some data into the buffer
    (bytevector-u8-set! bv 10 #xAB)
    (bytevector-u8-set! bv 11 #xCD)
    (bytevector-u8-set! bv 12 #xEF)
    ;; Create a slice starting at offset 10, length 3
    (let ([slice (make-buffer-slice id 10 3 pool)])
      (test "slice-offset" (slice-offset slice) 10)
      (test "slice-length" (slice-length slice) 3)
      (test "slice-data-ref-first"
        (bytevector-u8-ref (slice-data slice) 10)
        #xAB))
    (pool-release! pool id)))

;; Test 5: slice->bytevector copies data
(let ([pool (make-buffer-pool 256 2)])
  (let-values ([(id bv) (pool-acquire! pool)])
    (bytevector-u8-set! bv 0 1)
    (bytevector-u8-set! bv 1 2)
    (bytevector-u8-set! bv 2 3)
    (let ([slice (make-buffer-slice id 0 3 pool)])
      (let ([copy (slice->bytevector slice)])
        (test "copy-length" (bytevector-length copy) 3)
        (test "copy-content"
          (list (bytevector-u8-ref copy 0)
                (bytevector-u8-ref copy 1)
                (bytevector-u8-ref copy 2))
          '(1 2 3))))
    (pool-release! pool id)))

;; Test 6: slice-copy! into destination
(let ([pool (make-buffer-pool 64 2)])
  (let-values ([(id bv) (pool-acquire! pool)])
    (bytevector-u8-set! bv 5 10)
    (bytevector-u8-set! bv 6 20)
    (let ([slice (make-buffer-slice id 5 2 pool)]
          [dst (make-bytevector 10 0)])
      (slice-copy! dst 3 slice)
      (test "slice-copy-at-offset"
        (list (bytevector-u8-ref dst 3)
              (bytevector-u8-ref dst 4))
        '(10 20)))
    (pool-release! pool id)))

;; Test 7: with-buffer acquires and releases
(let ([pool (make-buffer-pool 128 2)])
  (let ([result #f])
    (with-buffer pool
      (lambda (buf-id bv)
        (set! result (bytevector-length bv))
        (let ([stats-in (buffer-pool-stats pool)])
          (test "available-in-with-buffer"
            (cdr (assq 'available stats-in))
            1))))
    (test "with-buffer-returns-correct-size" result 128)
    (let ([stats-after (buffer-pool-stats pool)])
      (test "available-restored-after-with-buffer"
        (cdr (assq 'available stats-after))
        2))))

;; Test 8: pool-stats acquired/released counters
(let ([pool (make-buffer-pool 64 4)])
  (let-values ([(id1 _bv1) (pool-acquire! pool)]
               [(id2 _bv2) (pool-acquire! pool)])
    (pool-release! pool id1)
    (let ([stats (buffer-pool-stats pool)])
      (test "stats-acquired-count"
        (cdr (assq 'acquired stats))
        2)
      (test "stats-released-count"
        (cdr (assq 'released stats))
        1))
    (pool-release! pool id2)))

;; Test 9: with-buffer via dynamic-wind releases on exception
(let ([pool (make-buffer-pool 64 1)])
  (guard (exn [#t (void)])
    (with-buffer pool
      (lambda (buf-id bv)
        (error 'test "deliberate error"))))
  (test "buffer-released-after-exception"
    (cdr (assq 'available (buffer-pool-stats pool)))
    1))

;; Test 10: multiple sequential acquires of same buffer (after release)
(let ([pool (make-buffer-pool 64 1)])
  (let-values ([(id1 _bv1) (pool-acquire! pool)])
    (pool-release! pool id1))
  (let-values ([(id2 bv2) (pool-acquire! pool)])
    (test "reuse-same-buffer" (integer? id2) #t)
    (pool-release! pool id2)))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
