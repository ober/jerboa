;;; Closure Inspection — Phase 5c (Track 14.2)

(library (std debug closure-inspect)
  (export
    make-tracked-closure
    tracked-closure?
    closure-free-variables
    closure-set-free-variable!
    closure-with
    closure-arity
    closure-min-arity
    closure-max-arity)
  (import (chezscheme))

  ;; We store a mutable env-box (a list cell) + the underlying proc.
  ;; The "record" has a mutable env-box field.

  (define-record-type tc-type
    (fields (mutable env-box tc-env-box set-tc-env-box!)
            (immutable proc tc-proc))
    (protocol (lambda (new) (lambda (env proc) (new (list env) proc)))))

  (define (make-tracked-closure env-alist proc)
    (unless (procedure? proc) (error 'make-tracked-closure "not a procedure" proc))
    (make-tc-type env-alist proc))

  (define (tracked-closure? x) (tc-type? x))

  (define (closure-free-variables tc)
    (cond [(tc-type? tc) (car (tc-env-box tc))]
          [(procedure? tc) '()]
          [else (error 'closure-free-variables "not a closure" tc)]))

  (define (closure-set-free-variable! tc name val)
    (unless (tc-type? tc) (error 'closure-set-free-variable! "not a tracked closure" tc))
    (let* ([env  (car (tc-env-box tc))]
           [pair (assq name env)])
      (if pair
          (set-cdr! pair val)
          (set-tc-env-box! tc (list (cons (cons name val) env))))))

  (define (closure-with tc new-env)
    (unless (tc-type? tc) (error 'closure-with "not a tracked closure" tc))
    (make-tc-type new-env (tc-proc tc)))

  (define (get-proc x)
    (cond [(tc-type? x) (tc-proc x)]
          [(procedure? x) x]
          [else (error 'get-proc "not a procedure" x)]))

  (define (closure-arity x) (procedure-arity-mask (get-proc x)))

  (define (closure-min-arity x)
    (let ([mask (procedure-arity-mask (get-proc x))])
      (let loop ([i 0])
        (if (bitwise-bit-set? mask i) i (loop (+ i 1))))))

  (define (closure-max-arity x)
    (let* ([p    (get-proc x)]
           [mask (procedure-arity-mask p)])
      ;; variadic if highest bit is the sign bit (negative mask possible)
      ;; In Chez, arity-mask=-1 means any number of args
      (if (< mask 0) #f (- (integer-length mask) 1))))

)
