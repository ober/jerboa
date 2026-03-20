#!chezscheme
;;; Tests for batch 5: diff, ringbuf, printf, heap, lru-cache

(import (chezscheme)
        (std text diff)
        (std misc ringbuf)
        (std text printf)
        (std misc heap)
        (std misc lru-cache))

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

(printf "--- Testing batch 5 modules ---~n")

;; ========== (std text diff) ==========
(printf "  Diff...~n")

;; diff-lines: no changes
(check (diff-lines '("a" "b" "c") '("a" "b" "c"))
  => '((keep "a") (keep "b") (keep "c")))

;; diff-lines: additions
(let ([d (diff-lines '("a" "c") '("a" "b" "c"))])
  (check-true (member '(add "b") d)))

;; diff-lines: removals
(let ([d (diff-lines '("a" "b" "c") '("a" "c"))])
  (check-true (member '(remove "b") d)))

;; diff-lines: replacement
(let ([d (diff-lines '("a" "b" "c") '("a" "x" "c"))])
  (check-true (member '(remove "b") d))
  (check-true (member '(add "x") d)))

;; diff-lines: empty
(check (diff-lines '() '()) => '())
(let ([d (diff-lines '() '("a"))])
  (check-true (member '(add "a") d)))

;; diff-unified
(let ([u (diff-unified "old" "new" '("a" "b") '("a" "c"))])
  (check-true (string-contains* u "--- old"))
  (check-true (string-contains* u "+++ new"))
  (check-true (string-contains* u "-b"))
  (check-true (string-contains* u "+c")))

;; diff-strings
(let ([d (diff-strings "a\nb\nc" "a\nx\nc")])
  (check-true (member '(remove "b") d))
  (check-true (member '(add "x") d)))

;; edit-distance
(check (edit-distance "kitten" "sitting") => 3)
(check (edit-distance "" "") => 0)
(check (edit-distance "abc" "abc") => 0)
(check (edit-distance "abc" "") => 3)
(check (edit-distance "" "abc") => 3)

;; diff-summary
(let-values ([(adds dels keeps) (diff-summary '((keep "a") (remove "b") (add "x") (keep "c")))])
  (check adds => 1)
  (check dels => 1)
  (check keeps => 2))

;; diff-apply
(check (diff-apply '("a" "b" "c") '((keep "a") (remove "b") (add "x") (keep "c")))
  => '("a" "x" "c"))

;; ========== (std misc ringbuf) ==========
(printf "  Ring buffer...~n")

;; Basic
(let ([rb (make-ringbuf 5)])
  (check-true (ringbuf? rb))
  (check (ringbuf-capacity rb) => 5)
  (check-true (ringbuf-empty? rb))
  (check (ringbuf-size rb) => 0)

  (ringbuf-push! rb 1)
  (ringbuf-push! rb 2)
  (ringbuf-push! rb 3)
  (check (ringbuf-size rb) => 3)
  (check-false (ringbuf-full? rb))
  (check (ringbuf-peek rb) => 1)
  (check (ringbuf-peek-newest rb) => 3)

  (check (ringbuf-pop! rb) => 1)
  (check (ringbuf-pop! rb) => 2)
  (check (ringbuf-size rb) => 1))

;; ringbuf->list
(let ([rb (make-ringbuf 5)])
  (ringbuf-push! rb 'a)
  (ringbuf-push! rb 'b)
  (ringbuf-push! rb 'c)
  (check (ringbuf->list rb) => '(a b c)))

;; Overwrite when full
(let ([rb (make-ringbuf 3)])
  (ringbuf-push! rb 1)
  (ringbuf-push! rb 2)
  (ringbuf-push! rb 3)
  (check-true (ringbuf-full? rb))
  (ringbuf-push! rb 4)  ;; overwrites 1
  (check (ringbuf->list rb) => '(2 3 4))
  (ringbuf-push! rb 5)  ;; overwrites 2
  (check (ringbuf->list rb) => '(3 4 5)))

;; ringbuf-ref
(let ([rb (make-ringbuf 5)])
  (ringbuf-push! rb 10)
  (ringbuf-push! rb 20)
  (ringbuf-push! rb 30)
  (check (ringbuf-ref rb 0) => 10)
  (check (ringbuf-ref rb 1) => 20)
  (check (ringbuf-ref rb 2) => 30))

;; ringbuf-clear!
(let ([rb (make-ringbuf 5)])
  (ringbuf-push! rb 1)
  (ringbuf-push! rb 2)
  (ringbuf-clear! rb)
  (check-true (ringbuf-empty? rb))
  (check (ringbuf-size rb) => 0))

;; ringbuf-for-each
(let ([rb (make-ringbuf 5)]
      [sum 0])
  (ringbuf-push! rb 1)
  (ringbuf-push! rb 2)
  (ringbuf-push! rb 3)
  (ringbuf-for-each (lambda (x) (set! sum (+ sum x))) rb)
  (check sum => 6))

;; Error on empty
(check-true (guard (exn [#t #t])
              (ringbuf-pop! (make-ringbuf 3))
              #f))

;; ========== (std text printf) ==========
(printf "  Printf...~n")

;; Basic types
(check (sprintf "%d" 42) => "42")
(check (sprintf "%s" "hello") => "hello")
(check (sprintf "%x" 255) => "ff")
(check (sprintf "%X" 255) => "FF")
(check (sprintf "%o" 8) => "10")
(check (sprintf "%b" 10) => "1010")
(check (sprintf "%c" #\A) => "A")
(check (sprintf "%%" ) => "%")

;; Width and padding
(check (sprintf "%10d" 42) => "        42")
(check (sprintf "%-10d|" 42) => "42        |")
(check (sprintf "%010d" 42) => "0000000042")

;; Precision for floats
(check (sprintf "%.2f" 3.14159) => "3.14")
;; precision 0 still includes dot
(check-true (string-contains* (sprintf "%.0f" 3.7) "4"))

;; Multiple args
(check (sprintf "%d + %d = %d" 1 2 3) => "1 + 2 = 3")
(check (sprintf "Name: %s, Age: %d" "Alice" 30) => "Name: Alice, Age: 30")

;; Hex formatting
(check (sprintf "%08x" 255) => "000000ff")

;; Plus sign
(check (sprintf "%+d" 42) => "+42")

;; Scientific
(let ([s (sprintf "%.2e" 12345.0)])
  (check-true (string-contains* s "e+")))

;; format-one
(check (format-one "%d" 42) => "42")

;; cprintf (just check no error)
(let ([out (with-output-to-string (lambda () (cprintf "test %d" 99)))])
  (check out => "test 99"))

;; ========== Helpers ==========
(define (sorted? lst cmp)
  (or (null? lst) (null? (cdr lst))
      (and (not (cmp (cadr lst) (car lst)))  ;; a <= b when NOT b<a
           (sorted? (cdr lst) cmp))))

;; ========== (std misc heap) ==========
(printf "  Heap...~n")

;; Min-heap
(let ([h (make-heap <)])
  (check-true (heap? h))
  (check-true (heap-empty? h))

  (heap-insert! h 5)
  (heap-insert! h 2)
  (heap-insert! h 8)
  (heap-insert! h 1)
  (heap-insert! h 9)

  (check (heap-size h) => 5)
  (check (heap-peek h) => 1)
  (check (heap-extract! h) => 1)
  (check (heap-extract! h) => 2)
  (check (heap-extract! h) => 5)
  (check (heap-size h) => 2))

;; Max-heap
(let ([h (make-heap >)])
  (heap-insert! h 5)
  (heap-insert! h 2)
  (heap-insert! h 8)
  (check (heap-peek h) => 8)
  (check (heap-extract! h) => 8)
  (check (heap-extract! h) => 5))

;; list->heap and heap->sorted-list
(let ([h (list->heap < '(5 3 1 4 2))])
  (check (heap->sorted-list h) => '(1 2 3 4 5)))

;; Large heap
(let ([h (make-heap <)])
  (let loop ([i 100])
    (when (> i 0)
      (heap-insert! h (random 1000))
      (loop (- i 1))))
  (check (heap-size h) => 100)
  ;; Extract all should be sorted
  (let ([sorted (heap->sorted-list h)])
    (check (heap-size h) => 0)
    (check-true (sorted? sorted <))))

;; heap-clear!
(let ([h (list->heap < '(1 2 3))])
  (heap-clear! h)
  (check-true (heap-empty? h)))

;; Error on empty
(check-true (guard (exn [#t #t])
              (heap-peek (make-heap <))
              #f))

;; ========== (std misc lru-cache) ==========
(printf "  LRU cache...~n")

;; Basic
(let ([c (make-lru-cache 3)])
  (check-true (lru-cache? c))
  (check (lru-cache-size c) => 0)
  (check (lru-cache-capacity c) => 3)

  (lru-cache-put! c "a" 1)
  (lru-cache-put! c "b" 2)
  (lru-cache-put! c "c" 3)
  (check (lru-cache-size c) => 3)

  (check (lru-cache-get c "a") => 1)
  (check (lru-cache-get c "b") => 2)
  (check (lru-cache-get c "missing" #f) => #f)

  (check-true (lru-cache-contains? c "a"))
  (check-false (lru-cache-contains? c "missing")))

;; Eviction
(let ([c (make-lru-cache 3)])
  (lru-cache-put! c "a" 1)
  (lru-cache-put! c "b" 2)
  (lru-cache-put! c "c" 3)
  ;; Access "a" to make it recently used
  (lru-cache-get c "a")
  ;; Add "d" — should evict "b" (least recently used)
  (lru-cache-put! c "d" 4)
  (check (lru-cache-size c) => 3)
  (check-false (lru-cache-contains? c "b"))
  (check-true (lru-cache-contains? c "a"))
  (check-true (lru-cache-contains? c "d")))

;; Update existing
(let ([c (make-lru-cache 3)])
  (lru-cache-put! c "k" 1)
  (lru-cache-put! c "k" 2)
  (check (lru-cache-get c "k") => 2)
  (check (lru-cache-size c) => 1))

;; Delete
(let ([c (make-lru-cache 3)])
  (lru-cache-put! c "a" 1)
  (lru-cache-put! c "b" 2)
  (lru-cache-delete! c "a")
  (check (lru-cache-size c) => 1)
  (check-false (lru-cache-contains? c "a")))

;; Clear
(let ([c (make-lru-cache 3)])
  (lru-cache-put! c "a" 1)
  (lru-cache-put! c "b" 2)
  (lru-cache-clear! c)
  (check (lru-cache-size c) => 0))

;; Keys and values
(let ([c (make-lru-cache 5)])
  (lru-cache-put! c "a" 1)
  (lru-cache-put! c "b" 2)
  (lru-cache-put! c "c" 3)
  (check (length (lru-cache-keys c)) => 3)
  (check (length (lru-cache-values c)) => 3))

;; Stats
(let ([c (make-lru-cache 3)])
  (lru-cache-put! c "a" 1)
  (lru-cache-get c "a")    ;; hit
  (lru-cache-get c "b" #f) ;; miss
  (let ([stats (lru-cache-stats c)])
    (check (cdr (assq 'hits stats)) => 1)
    (check (cdr (assq 'misses stats)) => 1)
    (check (cdr (assq 'size stats)) => 1)))

;; For-each
(let ([c (make-lru-cache 5)]
      [collected '()])
  (lru-cache-put! c "x" 10)
  (lru-cache-put! c "y" 20)
  (lru-cache-for-each (lambda (k v) (set! collected (cons (cons k v) collected))) c)
  (check (length collected) => 2))

;; ========== Summary ==========
(printf "~n--- Results: ~a passed, ~a failed ---~n" pass-count fail-count)
(when (> fail-count 0) (exit 1))
