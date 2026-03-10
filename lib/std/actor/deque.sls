#!chezscheme
;;; (std actor deque) — Work-stealing double-ended queue
;;;
;;; Owner pushes/pops from the bottom (LIFO).
;;; Thieves steal from the top (FIFO).
;;; Mutex-based (simpler than lock-free Chase-Lev; fast when uncontended).

(library (std actor deque)
  (export
    make-work-deque
    work-deque?
    deque-push-bottom!    ;; owner pushes a task
    deque-pop-bottom!     ;; owner pops (LIFO — locality of reference)
    deque-steal-top!      ;; thief steals (FIFO — oldest tasks first)
    deque-empty?
    deque-size)
  (import (chezscheme))

  ;; Circular buffer that grows as needed
  (define-record-type work-deque
    (fields
      (mutable buf)      ;; vector of tasks
      (mutable bottom)   ;; owner's end (push/pop here)
      (mutable top)      ;; thief's end (steal from here)
      (immutable mutex))
    (protocol
      (lambda (new)
        (lambda ()
          (new (make-vector 64 #f) 0 0 (make-mutex)))))
    (sealed #t))

  (define (deque-capacity d) (vector-length (work-deque-buf d)))

  (define (deque-size d)
    (with-mutex (work-deque-mutex d)
      (let ([b (work-deque-bottom d)]
            [t (work-deque-top d)])
        (if (fx>= b t) (fx- b t) 0))))

  (define (deque-empty? d)
    (with-mutex (work-deque-mutex d)
      (fx<= (work-deque-bottom d) (work-deque-top d))))

  ;; Grow buffer when full (called under lock)
  (define (deque-grow! d)
    (let* ([old     (work-deque-buf d)]
           [old-cap (vector-length old)]
           [new-cap (fx* old-cap 2)]
           [new-buf (make-vector new-cap #f)]
           [top     (work-deque-top d)]
           [bottom  (work-deque-bottom d)])
      (do ([i top (fx+ i 1)])
          ((fx= i bottom))
        (vector-set! new-buf (fxmod i new-cap)
                     (vector-ref old (fxmod i old-cap))))
      (work-deque-buf-set! d new-buf)))

  ;; Owner pushes a task to the bottom
  (define (deque-push-bottom! d task)
    (with-mutex (work-deque-mutex d)
      (let ([b (work-deque-bottom d)])
        (when (fx>= (fx- b (work-deque-top d)) (fx- (deque-capacity d) 1))
          (deque-grow! d))
        (vector-set! (work-deque-buf d) (fxmod b (deque-capacity d)) task)
        (work-deque-bottom-set! d (fx+ b 1)))))

  ;; Owner pops from the bottom (LIFO — most recently pushed task first)
  ;; Returns the task or #f if empty
  (define (deque-pop-bottom! d)
    (with-mutex (work-deque-mutex d)
      (let ([b (work-deque-bottom d)]
            [t (work-deque-top d)])
        (if (fx> b t)
          (let ([new-b (fx- b 1)])
            (work-deque-bottom-set! d new-b)
            (let ([task (vector-ref (work-deque-buf d)
                                    (fxmod new-b (deque-capacity d)))])
              (vector-set! (work-deque-buf d) (fxmod new-b (deque-capacity d)) #f)
              task))
          #f))))

  ;; Thief steals from the top (FIFO — oldest tasks first)
  ;; Returns (values task #t) or (values #f #f) if empty
  (define (deque-steal-top! d)
    (with-mutex (work-deque-mutex d)
      (let ([t (work-deque-top d)]
            [b (work-deque-bottom d)])
        (cond
          [(fx>= t b)
           (values #f #f)]
          [else
           (let ([task (vector-ref (work-deque-buf d)
                                   (fxmod t (deque-capacity d)))])
             (vector-set! (work-deque-buf d) (fxmod t (deque-capacity d)) #f)
             (work-deque-top-set! d (fx+ t 1))
             (values task #t))]))))

  ) ;; end library
