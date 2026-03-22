#!chezscheme
;;; (std misc diff) — LCS-based diff algorithm
;;;
;;; (diff '(a b c) '(b c d))  =>  ((remove a) (same b) (same c) (add d))
;;; (edit-distance '(a b c) '(b c d))  =>  2
;;; (lcs '(a b c d) '(b d f))  =>  (b d)

(library (std misc diff)
  (export diff diff-strings edit-distance lcs diff->string diff-report)
  (import (chezscheme))

  ;; Compute the longest common subsequence of two lists.
  ;; Uses a DP table approach. Returns the LCS as a list.
  (define lcs
    (case-lambda
      [(xs ys) (lcs xs ys equal?)]
      [(xs ys =?)
       (let* ([xv (list->vector xs)]
              [yv (list->vector ys)]
              [m (vector-length xv)]
              [n (vector-length yv)]
              ;; dp is (m+1) x (n+1) table storing LCS lengths
              [dp (make-vector (* (+ m 1) (+ n 1)) 0)])
         (define (ref i j)
           (vector-ref dp (+ (* i (+ n 1)) j)))
         (define (set! i j v)
           (vector-set! dp (+ (* i (+ n 1)) j) v))
         ;; Fill the DP table bottom-up
         (let loop-i ([i (- m 1)])
           (when (>= i 0)
             (let loop-j ([j (- n 1)])
               (when (>= j 0)
                 (if (=? (vector-ref xv i) (vector-ref yv j))
                     (set! i j (+ 1 (ref (+ i 1) (+ j 1))))
                     (set! i j (max (ref (+ i 1) j) (ref i (+ j 1)))))
                 (loop-j (- j 1))))
             (loop-i (- i 1))))
         ;; Backtrack to recover the LCS
         (let backtrack ([i 0] [j 0] [acc '()])
           (cond
             [(or (= i m) (= j n))
              (reverse acc)]
             [(=? (vector-ref xv i) (vector-ref yv j))
              (backtrack (+ i 1) (+ j 1) (cons (vector-ref xv i) acc))]
             [(> (ref (+ i 1) j) (ref i (+ j 1)))
              (backtrack (+ i 1) j acc)]
             [else
              (backtrack i (+ j 1) acc)])))]))

  ;; Compute the diff between two lists, returning a list of edit operations:
  ;;   (same val) — element present in both
  ;;   (add val)  — element added (in ys but not xs)
  ;;   (remove val) — element removed (in xs but not ys)
  (define diff
    (case-lambda
      [(xs ys) (diff xs ys equal?)]
      [(xs ys =?)
       (let ([common (lcs xs ys =?)])
         ;; Walk xs, ys, and the LCS simultaneously to produce edit ops
         (let loop ([xs xs] [ys ys] [cs common] [acc '()])
           (cond
             ;; LCS exhausted — remaining xs are removals, remaining ys are additions
             [(null? cs)
              (let ([removes (map (lambda (x) (list 'remove x)) xs)]
                    [adds (map (lambda (y) (list 'add y)) ys)])
                (reverse (append (reverse adds) (reverse removes) acc)))]
             ;; Current x matches LCS head — but check if y also matches
             [(and (not (null? xs)) (=? (car xs) (car cs)))
              (if (and (not (null? ys)) (=? (car ys) (car cs)))
                  ;; Both match LCS — it's a 'same'
                  (loop (cdr xs) (cdr ys) (cdr cs)
                        (cons (list 'same (car cs)) acc))
                  ;; y doesn't match LCS — it's an addition, keep going
                  (if (null? ys)
                      (loop xs ys cs acc)
                      (loop xs (cdr ys) cs
                            (cons (list 'add (car ys)) acc))))]
             ;; Current x doesn't match LCS — it's a removal
             [(not (null? xs))
              (loop (cdr xs) ys cs
                    (cons (list 'remove (car xs)) acc))]
             ;; xs exhausted but ys remain — additions
             [(not (null? ys))
              (loop xs (cdr ys) cs
                    (cons (list 'add (car ys)) acc))]
             [else
              (reverse acc)])))]))

  ;; Compute the Levenshtein edit distance between two lists.
  (define edit-distance
    (case-lambda
      [(xs ys) (edit-distance xs ys equal?)]
      [(xs ys =?)
       (let* ([xv (list->vector xs)]
              [yv (list->vector ys)]
              [m (vector-length xv)]
              [n (vector-length yv)]
              [dp (make-vector (* (+ m 1) (+ n 1)) 0)])
         (define (ref i j)
           (vector-ref dp (+ (* i (+ n 1)) j)))
         (define (set! i j v)
           (vector-set! dp (+ (* i (+ n 1)) j) v))
         ;; Base cases
         (let init-i ([i 0])
           (when (<= i m)
             (set! i 0 i)
             (init-i (+ i 1))))
         (let init-j ([j 0])
           (when (<= j n)
             (set! 0 j j)
             (init-j (+ j 1))))
         ;; Fill DP table
         (let loop-i ([i 1])
           (when (<= i m)
             (let loop-j ([j 1])
               (when (<= j n)
                 (if (=? (vector-ref xv (- i 1)) (vector-ref yv (- j 1)))
                     (set! i j (ref (- i 1) (- j 1)))
                     (set! i j (+ 1 (min (ref (- i 1) j)
                                         (ref i (- j 1))
                                         (ref (- i 1) (- j 1))))))
                 (loop-j (+ j 1))))
             (loop-i (+ i 1))))
         (ref m n))]))

  ;; Format a diff as a unified-diff-style string with +/- prefixes.
  ;; Each edit op becomes a line: " val" for same, "+val" for add, "-val" for remove.
  (define (diff->string ops)
    (let ([port (open-output-string)])
      (for-each
        (lambda (op)
          (let ([tag (car op)]
                [val (cadr op)])
            (case tag
              [(same)   (display " " port) (display val port) (newline port)]
              [(add)    (display "+" port) (display val port) (newline port)]
              [(remove) (display "-" port) (display val port) (newline port)])))
        ops)
      (get-output-string port)))

  ;; Pretty-print a diff to current-output-port.
  (define (diff-report ops)
    (display (diff->string ops)))

  ;; Split a string into lines by newline character.
  (define (string-split-lines s)
    (let loop ([i 0] [start 0] [acc '()])
      (cond
        [(= i (string-length s))
         (reverse (cons (substring s start i) acc))]
        [(char=? (string-ref s i) #\newline)
         (loop (+ i 1) (+ i 1) (cons (substring s start i) acc))]
        [else
         (loop (+ i 1) start acc)])))

  ;; Diff two strings line-by-line. Returns a formatted diff string.
  (define (diff-strings s1 s2)
    (let* ([lines1 (string-split-lines s1)]
           [lines2 (string-split-lines s2)]
           [ops (diff lines1 lines2 string=?)])
      (diff->string ops)))

) ;; end library
