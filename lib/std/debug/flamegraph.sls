#!chezscheme
;;; (std debug flamegraph) — Flame Graph Profiler
;;;
;;; Manual instrumentation profiler (enter/exit) that builds call-stack
;;; sample data and can emit folded flame graph text for flamegraph.pl.

(library (std debug flamegraph)
  (export
    ;; Profiler control
    make-profiler
    profiler?
    profiler-start!
    profiler-stop!
    profiler-reset!
    profiler-running?
    ;; Data collection (manual instrumentation)
    profiler-enter!
    profiler-exit!
    profile-fn
    with-profile
    ;; Results
    profiler-samples
    profiler-flat-stats
    profiler-tree
    profiler-hotspots
    profiler-total-samples
    ;; Output
    profiler->flamegraph-text
    profiler->alist
    display-profile
    ;; Timing (wall-clock based)
    profiler-timing-enter!
    profiler-timing-exit!
    profile-fn/timed
    with-profile/timed
    profiler-timing-stats
    ;; Convenience
    profile-thunk
    top-k-hotspots)

  (import (chezscheme))

  ;; ========== Wall-clock time in milliseconds ==========

  (define (now-ms)
    (let ([t (current-time 'time-utc)])
      (+ (* (time-second t) 1000.0)
         (/ (time-nanosecond t) 1000000.0))))

  ;; ========== Profiler record ==========
  ;; - call-stack: mutable list (current head = top of stack)
  ;; - samples: hashtable from stack-key -> count
  ;; - timing-stack: list of (fn-name . enter-ms) pairs
  ;; - timing-data: hashtable fn-name -> (calls total-ms)
  ;; - running?: flag

  (define-record-type %profiler
    (fields
      (mutable call-stack)    ;; list of fn-name symbols/strings
      (mutable samples-ht)    ;; hashtable: stack-key -> count
      (mutable timing-stack)  ;; list of (fn-name . enter-ms)
      (mutable timing-ht)     ;; hashtable: fn-name -> (calls . total-ms)
      (mutable running?))
    (protocol
      (lambda (new)
        (lambda ()
          (new '()
               (make-hashtable equal-hash equal?)
               '()
               (make-hashtable equal-hash equal?)
               #f)))))


  ;; Per-profiler mutex table
  (define *profiler-mutex-table* (make-eq-hashtable))

  (define (profiler-mutex prof)
    (let ([m (hashtable-ref *profiler-mutex-table* prof #f)])
      (or m
          (let ([new-m (make-mutex)])
            (hashtable-set! *profiler-mutex-table* prof new-m)
            new-m))))

  (define (make-profiler)
    (let ([p (make-%profiler)])
      (profiler-mutex p)
      p))

  (define (profiler? x) (%profiler? x))
  (define (profiler-running? prof) (%profiler-running? prof))

  (define (profiler-start! prof . opts)
    ;; opts: #:interval-ms N (accepted but ignored — we use manual instrumentation)
    (with-mutex (profiler-mutex prof)
      (%profiler-running?-set! prof #t)))

  (define (profiler-stop! prof)
    (with-mutex (profiler-mutex prof)
      (%profiler-running?-set! prof #f)))

  (define (profiler-reset! prof)
    (with-mutex (profiler-mutex prof)
      (%profiler-call-stack-set! prof '())
      (%profiler-samples-ht-set! prof (make-hashtable equal-hash equal?))
      (%profiler-timing-stack-set! prof '())
      (%profiler-timing-ht-set! prof (make-hashtable equal-hash equal?))
      (%profiler-running?-set! prof #f)))

  ;; ========== Stack key ==========
  ;; A stack is represented as a list of fn-names (current call first).
  ;; The key for the hashtable is the list itself (equal? comparison).

  (define (record-stack-sample! prof stack)
    (when (%profiler-running? prof)
      (let* ([ht  (%profiler-samples-ht prof)]
             [cnt (hashtable-ref ht stack 0)])
        (hashtable-set! ht stack (+ cnt 1)))))

  ;; ========== Enter / Exit ==========

  (define (profiler-enter! prof fn-name)
    (with-mutex (profiler-mutex prof)
      (when (%profiler-running? prof)
        (let ([new-stack (cons fn-name (%profiler-call-stack prof))])
          (%profiler-call-stack-set! prof new-stack)
          (record-stack-sample! prof new-stack)))))

  (define (profiler-exit! prof fn-name)
    (with-mutex (profiler-mutex prof)
      (when (%profiler-running? prof)
        (let ([stack (%profiler-call-stack prof)])
          (unless (null? stack)
            (%profiler-call-stack-set! prof (cdr stack)))))))

  ;; ========== Wrappers ==========

  (define (profile-fn prof fn)
    (let ([name (or (procedure? fn) fn)])
      (lambda args
        (profiler-enter! prof fn)
        (let ([result (apply fn args)])
          (profiler-exit! prof fn)
          result))))

  (define-syntax with-profile
    (syntax-rules ()
      [(_ prof name body ...)
       (dynamic-wind
         (lambda () (profiler-enter! prof 'name))
         (lambda () body ...)
         (lambda () (profiler-exit! prof 'name)))]))

  ;; ========== Results ==========

  (define (profiler-samples prof)
    ;; Returns list of (stack . count) pairs
    (with-mutex (profiler-mutex prof)
      (let-values ([(keys vals) (hashtable-entries (%profiler-samples-ht prof))])
        (map cons (vector->list keys) (vector->list vals)))))

  (define (profiler-total-samples prof)
    (apply + (map cdr (profiler-samples prof))))

  (define (profiler-flat-stats prof)
    ;; alist of fn-name -> total-samples (counts all stacks fn appears in)
    (let ([samples (profiler-samples prof)]
          [ht (make-hashtable equal-hash equal?)])
      (for-each
        (lambda (pair)
          (let ([stack (car pair)]
                [count (cdr pair)])
            (for-each
              (lambda (fn)
                (hashtable-set! ht fn (+ (hashtable-ref ht fn 0) count)))
              stack)))
        samples)
      (let-values ([(keys vals) (hashtable-entries ht)])
        (map cons (vector->list keys) (vector->list vals)))))

  (define (profiler-hotspots prof)
    ;; All functions sorted by sample count descending
    (list-sort (lambda (a b) (> (cdr a) (cdr b)))
               (profiler-flat-stats prof)))

  (define (top-k-hotspots prof k)
    (let ([hs (profiler-hotspots prof)])
      (take-at-most hs k)))

  ;; take-at-most: return up to n elements from list
  (define (take-at-most lst n)
    (if (or (null? lst) (= n 0))
      '()
      (cons (car lst) (take-at-most (cdr lst) (- n 1)))))

  ;; ========== Tree ==========
  ;; Returns nested alist: (fn-name count . children-alist)
  ;; children-alist entries: same structure

  (define (profiler-tree prof)
    ;; Build tree from samples. Stack is stored newest-first (top of call stack first),
    ;; so reverse each stack to get root->leaf order.
    (let ([samples (profiler-samples prof)])
      (build-tree samples)))

  (define (build-tree samples)
    ;; Each sample's stack is (top ... bottom). Reverse to get call path root->leaf.
    ;; We build a trie of (fn . (count . children-map))
    (let ([root (list '*root* 0 '())])
      (for-each
        (lambda (pair)
          (let ([path  (reverse (car pair))]
                [count (cdr pair)])
            (insert-path! root path count)))
        samples)
      (cddr root))) ;; return children of root

  (define (insert-path! node path count)
    ;; node is (name total-count . children-list)
    ;; children-list is list of (name total-count . children-list)
    (unless (null? path)
      (let* ([fn (car path)]
             [rest (cdr path)]
             [children (%node-children node)]
             [child (assoc fn children)])
        (if child
          (begin
            (%node-add-count! child count)
            (insert-path! child rest count))
          (let ([new-child (list fn count '())])
            (%node-set-children! node (cons new-child children))
            (insert-path! new-child rest count))))))

  (define (%node-children n) (cddr n))
  (define (%node-add-count! n c) (set-car! (cdr n) (+ (cadr n) c)))
  (define (%node-set-children! n ch) (set-cdr! (cdr n) (list ch)))

  ;; ========== Output ==========

  (define (profiler->flamegraph-text prof . port-opt)
    ;; Folded format: "fn1;fn2;fn3 count" per line (root;...;leaf count)
    ;; Stack stored top-first, so reverse for root->leaf order.
    (let* ([out  (open-output-string)]
           [samples (profiler-samples prof)])
      (for-each
        (lambda (pair)
          (let ([stack (reverse (car pair))]
                [count (cdr pair)])
            (let loop ([s stack] [first? #t])
              (unless (null? s)
                (unless first? (display ";" out))
                (display (car s) out)
                (loop (cdr s) #f)))
            (fprintf out " ~a~%" count)))
        (list-sort (lambda (a b)
                     (string<? (stack->string (car a))
                                (stack->string (car b))))
                   samples))
      (let ([s (get-output-string out)])
        (when (pair? port-opt) (display s (car port-opt)))
        s)))

  (define (stack->string stack)
    (apply string-append
           (map (lambda (fn) (if (symbol? fn) (symbol->string fn) (format "~a" fn)))
                stack)))

  (define (profiler->alist prof)
    (profiler-samples prof))

  (define (display-profile prof . port-opt)
    (let* ([port (if (pair? port-opt) (car port-opt) (current-output-port))]
           [hotspots (profiler-hotspots prof)]
           [total (profiler-total-samples prof)])
      (fprintf port "~%Profile Results~%")
      (fprintf port "~a~%" (make-string 50 #\-))
      (fprintf port "~30a ~8a ~6a~%" "Function" "Samples" "%")
      (fprintf port "~a~%" (make-string 50 #\-))
      (for-each
        (lambda (pair)
          (let* ([fn  (car pair)]
                 [cnt (cdr pair)]
                 [pct (if (> total 0) (* 100.0 (/ cnt total)) 0.0)])
            (fprintf port "~30a ~8a ~5,1f%~%" fn cnt pct)))
        hotspots)
      (fprintf port "~a~%" (make-string 50 #\-))
      (fprintf port "Total samples: ~a~%~%" total)))

  ;; ========== Timing ==========

  (define (profiler-timing-enter! prof fn-name)
    (with-mutex (profiler-mutex prof)
      (%profiler-timing-stack-set! prof
        (cons (cons fn-name (now-ms))
              (%profiler-timing-stack prof)))))

  (define (profiler-timing-exit! prof fn-name)
    (with-mutex (profiler-mutex prof)
      (let ([tstack (%profiler-timing-stack prof)])
        (unless (null? tstack)
          (let* ([entry  (car tstack)]
                 [name   (car entry)]
                 [start  (cdr entry)]
                 [elapsed (- (now-ms) start)]
                 [ht     (%profiler-timing-ht prof)]
                 [old    (hashtable-ref ht name #f)])
            (%profiler-timing-stack-set! prof (cdr tstack))
            (if old
              (hashtable-set! ht name
                (cons (+ (car old) 1) (+ (cdr old) elapsed)))
              (hashtable-set! ht name (cons 1 elapsed))))))))

  (define (profile-fn/timed prof fn)
    (lambda args
      (profiler-timing-enter! prof fn)
      (let ([result (apply fn args)])
        (profiler-timing-exit! prof fn)
        result)))

  (define-syntax with-profile/timed
    (syntax-rules ()
      [(_ prof name body ...)
       (dynamic-wind
         (lambda () (profiler-timing-enter! prof 'name))
         (lambda () body ...)
         (lambda () (profiler-timing-exit! prof 'name)))]))

  (define (profiler-timing-stats prof)
    ;; Returns alist of fn-name -> (calls total-ms avg-ms)
    (with-mutex (profiler-mutex prof)
      (let-values ([(keys vals) (hashtable-entries (%profiler-timing-ht prof))])
        (map (lambda (fn entry)
               (let ([calls (car entry)]
                     [total (cdr entry)])
                 (list fn calls total
                       (if (> calls 0) (/ total calls) 0.0))))
             (vector->list keys)
             (vector->list vals)))))

  ;; ========== Convenience ==========

  (define (profile-thunk thunk)
    ;; Run thunk with a fresh profiler, return profiler stats
    (let ([prof (make-profiler)])
      (profiler-start! prof)
      (thunk)
      (profiler-stop! prof)
      (list
        'samples (profiler-samples prof)
        'flat-stats (profiler-flat-stats prof)
        'total (profiler-total-samples prof))))

) ;; end library
