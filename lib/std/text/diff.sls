#!chezscheme
;;; (std text diff) -- Text Diffing Utilities
;;;
;;; Line-by-line diff with unified diff output format.
;;;
;;; Usage:
;;;   (import (std text diff))
;;;   (diff-lines '("a" "b" "c") '("a" "x" "c"))
;;;   ; => ((keep "a") (remove "b") (add "x") (keep "c"))
;;;
;;;   (diff-unified "file1" "file2"
;;;     '("a" "b" "c") '("a" "x" "c"))
;;;   ; => unified diff string
;;;
;;;   (edit-distance "kitten" "sitting")  ; => 3

(library (std text diff)
  (export
    diff-lines
    diff-unified
    diff-strings
    edit-distance
    diff-summary
    diff-apply)

  (import (chezscheme))

  ;; ========== LCS-based Line Diff ==========
  ;; Uses Hunt-McIlroy / simple O(nm) DP for correctness

  (define (diff-lines old new)
    ;; Returns list of (keep str) | (remove str) | (add str)
    (let* ([old-v (list->vector old)]
           [new-v (list->vector new)]
           [m (vector-length old-v)]
           [n (vector-length new-v)]
           ;; DP table for LCS length
           [dp (make-vector (* (+ m 1) (+ n 1)) 0)])

      ;; Fill DP table
      (let loop-i ([i 1])
        (when (<= i m)
          (let loop-j ([j 1])
            (when (<= j n)
              (if (string=? (vector-ref old-v (- i 1))
                            (vector-ref new-v (- j 1)))
                (dp-set! dp m n i j (+ 1 (dp-ref dp m n (- i 1) (- j 1))))
                (dp-set! dp m n i j (max (dp-ref dp m n (- i 1) j)
                                         (dp-ref dp m n i (- j 1)))))
              (loop-j (+ j 1))))
          (loop-i (+ i 1))))

      ;; Backtrace
      (let backtrace ([i m] [j n] [result '()])
        (cond
          [(and (= i 0) (= j 0)) result]
          [(and (> i 0) (> j 0)
                (string=? (vector-ref old-v (- i 1))
                          (vector-ref new-v (- j 1))))
           (backtrace (- i 1) (- j 1)
                      (cons (list 'keep (vector-ref old-v (- i 1))) result))]
          [(and (> j 0)
                (or (= i 0)
                    (> (dp-ref dp m n i (- j 1))
                       (dp-ref dp m n (- i 1) j))))
           (backtrace i (- j 1)
                      (cons (list 'add (vector-ref new-v (- j 1))) result))]
          [else
           (backtrace (- i 1) j
                      (cons (list 'remove (vector-ref old-v (- i 1))) result))]))))

  (define (dp-ref dp m n i j)
    (vector-ref dp (+ (* i (+ n 1)) j)))

  (define (dp-set! dp m n i j val)
    (vector-set! dp (+ (* i (+ n 1)) j) val))

  ;; ========== Unified Diff ==========
  (define (diff-unified name1 name2 old new)
    ;; Generate unified diff format string
    (let ([hunks (diff-lines old new)]
          [out (open-output-string)])
      (fprintf out "--- ~a~n" name1)
      (fprintf out "+++ ~a~n" name2)

      ;; Group into context hunks
      (let ([old-line 1] [new-line 1])
        (for-each
          (lambda (entry)
            (case (car entry)
              [(keep)
               (fprintf out " ~a~n" (cadr entry))
               (set! old-line (+ old-line 1))
               (set! new-line (+ new-line 1))]
              [(remove)
               (fprintf out "-~a~n" (cadr entry))
               (set! old-line (+ old-line 1))]
              [(add)
               (fprintf out "+~a~n" (cadr entry))
               (set! new-line (+ new-line 1))]))
          hunks))
      (get-output-string out)))

  ;; ========== String Diff ==========
  (define (diff-strings old-str new-str)
    ;; Diff two strings line by line
    (diff-lines (string-split-lines old-str)
                (string-split-lines new-str)))

  ;; ========== Edit Distance (Levenshtein) ==========
  (define (edit-distance s1 s2)
    (let* ([m (string-length s1)]
           [n (string-length s2)]
           [dp (make-vector (* (+ m 1) (+ n 1)) 0)])
      ;; Initialize
      (let loop ([i 0])
        (when (<= i m) (dp-set! dp m n i 0 i) (loop (+ i 1))))
      (let loop ([j 0])
        (when (<= j n) (dp-set! dp m n 0 j j) (loop (+ j 1))))
      ;; Fill
      (let loop-i ([i 1])
        (when (<= i m)
          (let loop-j ([j 1])
            (when (<= j n)
              (let ([cost (if (char=? (string-ref s1 (- i 1))
                                      (string-ref s2 (- j 1))) 0 1)])
                (dp-set! dp m n i j
                  (min (+ (dp-ref dp m n (- i 1) j) 1)      ;; delete
                       (+ (dp-ref dp m n i (- j 1)) 1)      ;; insert
                       (+ (dp-ref dp m n (- i 1) (- j 1)) cost)))) ;; replace
              (loop-j (+ j 1))))
          (loop-i (+ i 1))))
      (dp-ref dp m n m n)))

  ;; ========== Summary ==========
  (define (diff-summary hunks)
    ;; Returns (values additions deletions unchanged)
    (let loop ([h hunks] [adds 0] [dels 0] [keeps 0])
      (if (null? h)
        (values adds dels keeps)
        (case (caar h)
          [(add)    (loop (cdr h) (+ adds 1) dels keeps)]
          [(remove) (loop (cdr h) adds (+ dels 1) keeps)]
          [(keep)   (loop (cdr h) adds dels (+ keeps 1))]))))

  ;; ========== Apply ==========
  (define (diff-apply old hunks)
    ;; Apply diff hunks to produce new text
    (let loop ([h hunks] [result '()])
      (if (null? h)
        (reverse result)
        (case (caar h)
          [(keep)   (loop (cdr h) (cons (cadar h) result))]
          [(add)    (loop (cdr h) (cons (cadar h) result))]
          [(remove) (loop (cdr h) result)]))))

  ;; ========== Helpers ==========
  (define (string-split-lines str)
    (let ([n (string-length str)])
      (if (= n 0) '()
        (let loop ([i 0] [start 0] [acc '()])
          (cond
            [(= i n) (reverse (cons (substring str start n) acc))]
            [(char=? (string-ref str i) #\newline)
             (loop (+ i 1) (+ i 1) (cons (substring str start i) acc))]
            [else (loop (+ i 1) start acc)])))))

) ;; end library
