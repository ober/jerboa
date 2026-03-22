#!chezscheme
;;; (std test quickcheck) -- QuickCheck-style property-based testing
;;;
;;; A generator is a procedure that takes a `size` parameter (non-negative
;;; integer) and returns a random value.  Larger sizes hint the generator to
;;; produce larger / more complex values.
;;;
;;; `check-property` runs a property over many random inputs with increasing
;;; sizes, and on failure attempts to shrink the counterexample.

(library (std test quickcheck)
  (export
    ;; Core
    check-property for-all quickcheck make-gen

    ;; Generators
    gen-int gen-nat gen-bool gen-char gen-string
    gen-list gen-vector gen-one-of gen-pair gen-choose

    ;; Combinators
    gen-map gen-bind gen-filter gen-sized

    ;; Shrinking
    shrink-int shrink-list shrink-string)

  (import (except (chezscheme) for-all))

  ;; ================================================================
  ;; make-gen -- wrap a (lambda (size) ...) into a generator
  ;; ================================================================

  ;; Generators are plain procedures.  make-gen is just the identity
  ;; wrapper kept for API clarity.
  (define (make-gen proc)
    proc)

  ;; ================================================================
  ;; Primitive generators
  ;; ================================================================

  ;; Random integer in [-size, size].
  (define (gen-int size)
    (if (zero? size)
        0
        (- (random (+ 1 (* 2 size))) size)))

  ;; Random non-negative integer in [0, size].
  (define (gen-nat size)
    (if (zero? size)
        0
        (random (+ size 1))))

  ;; Random boolean.
  (define (gen-bool size)
    (= (random 2) 0))

  ;; Random character (printable ASCII 32-126).
  (define (gen-char size)
    (integer->char (+ 32 (random 95))))

  ;; Random string of length up to size.
  (define (gen-string size)
    (let* ([len (random (+ size 1))]
           [chars (let loop ([n len] [acc '()])
                    (if (zero? n)
                        acc
                        (loop (- n 1)
                              (cons (gen-char size) acc))))])
      (list->string chars)))

  ;; Random list whose elements come from `elem-gen`, length up to size.
  (define (gen-list elem-gen)
    (lambda (size)
      (let ([len (random (+ size 1))])
        (let loop ([n len] [acc '()])
          (if (zero? n)
              acc
              (loop (- n 1) (cons (elem-gen size) acc)))))))

  ;; Random vector whose elements come from `elem-gen`.
  (define (gen-vector elem-gen)
    (lambda (size)
      (let ([lst ((gen-list elem-gen) size)])
        (list->vector lst))))

  ;; Choose uniformly from a non-empty list of values.
  (define (gen-one-of choices)
    (lambda (size)
      (list-ref choices (random (length choices)))))

  ;; Random pair from two generators.
  (define (gen-pair gen-a gen-b)
    (lambda (size)
      (cons (gen-a size) (gen-b size))))

  ;; Random integer in [lo, hi] (inclusive).
  (define (gen-choose lo hi)
    (lambda (size)
      (+ lo (random (+ 1 (- hi lo))))))

  ;; ================================================================
  ;; Generator combinators
  ;; ================================================================

  ;; Transform a generator's output.
  (define (gen-map f gen)
    (lambda (size)
      (f (gen size))))

  ;; Monadic bind: `f` receives the value and returns a new generator.
  (define (gen-bind gen f)
    (lambda (size)
      (let ([v (gen size)])
        ((f v) size))))

  ;; Keep trying until the predicate holds (with retry limit).
  (define (gen-filter pred gen)
    (lambda (size)
      (let loop ([tries 100])
        (if (zero? tries)
            (error 'gen-filter "could not satisfy predicate after 100 tries")
            (let ([v (gen size)])
              (if (pred v)
                  v
                  (loop (- tries 1))))))))

  ;; Size-dependent generator: `f` receives the size and returns a generator.
  (define (gen-sized f)
    (lambda (size)
      ((f size) size)))

  ;; ================================================================
  ;; Shrinking
  ;; ================================================================

  ;; Shrink an integer toward 0 -- returns a list of candidates.
  (define (shrink-int n)
    (cond
      [(= n 0) '()]
      [(> n 0)
       ;; 0, halved, and predecessor
       (let ([candidates (list 0 (quotient n 2) (- n 1))])
         ;; remove duplicates and n itself, keep only < n
         (filter (lambda (c) (and (>= c 0) (< c n))) candidates))]
      [else
       ;; Negative: try 0, negate, halved toward 0, and successor
       (let ([candidates (list 0 (- n) (- (quotient (- n) 2)) (+ n 1))])
         (filter (lambda (c) (< (abs c) (abs n))) candidates))]))

  ;; Shrink a list by removing elements one at a time, plus try empty.
  (define (shrink-list lst)
    (if (null? lst)
        '()
        (cons '()
              (let loop ([i 0] [acc '()])
                (if (>= i (length lst))
                    (reverse acc)
                    (loop (+ i 1)
                          (cons (append (list-head lst i)
                                        (list-tail lst (+ i 1)))
                                acc)))))))

  ;; Shrink a string by converting to list, shrinking that, then back.
  (define (shrink-string s)
    (map list->string (shrink-list (string->list s))))

  ;; ================================================================
  ;; Property running
  ;; ================================================================

  ;; Try to shrink the failing inputs.  `inputs` is a list of generated
  ;; values, `shrinkers` is a parallel list of (value -> list-of-candidates)
  ;; procedures, and `prop` is a procedure taking the input list and
  ;; returning truthy on success.
  (define (shrink-inputs inputs shrinkers prop)
    ;; Simple greedy shrink: iterate over each position, try candidates.
    (let loop ([current inputs] [fuel 100])
      (if (zero? fuel)
          current
          (let pos-loop ([pos 0] [improved? #f] [cur current])
            (if (>= pos (length cur))
                (if improved?
                    (loop cur (- fuel 1))
                    cur)
                (let ([shrink-fn (if (< pos (length shrinkers))
                                     (list-ref shrinkers pos)
                                     (lambda (x) '()))])
                  (let cand-loop ([cands (shrink-fn (list-ref cur pos))])
                    (if (null? cands)
                        (pos-loop (+ pos 1) improved? cur)
                        (let ([new-inputs
                               (let build ([i 0] [xs cur])
                                 (cond
                                   [(null? xs) '()]
                                   [(= i pos) (cons (car cands) (cdr xs))]
                                   [else (cons (car xs) (build (+ i 1) (cdr xs)))]))])
                          (if (guard (exn [#t #t])  ;; exception counts as failure
                                (not (apply prop new-inputs)))
                              ;; Shrunk successfully
                              (pos-loop (+ pos 1) #t new-inputs)
                              ;; Candidate didn't fail, try next
                              (cand-loop (cdr cands))))))))))))

  ;; Infer a default shrinker from the type of a value.
  (define (default-shrinker v)
    (cond
      [(integer? v) shrink-int]
      [(string? v) shrink-string]
      [(list? v) shrink-list]
      [else (lambda (x) '())]))

  ;; ---- check-property ----
  ;; Run a property `n-trials` times with increasing sizes.
  ;; `gen-list-arg` is a list of generators.
  ;; `prop` is a procedure that takes as many arguments as generators
  ;; and returns truthy on success.
  ;; Returns a result alist: ((status . pass/fail) ...)
  (define (check-property n-trials generators prop)
    (let loop ([trial 0])
      (if (>= trial n-trials)
          `((status . pass) (trials . ,n-trials))
          (let* ([size (min trial 100)]
                 [inputs (map (lambda (g) (g size)) generators)])
            (let ([ok? (guard (exn [#t #f])
                         (apply prop inputs))])
              (if ok?
                  (loop (+ trial 1))
                  ;; Failure -- attempt shrinking
                  (let* ([shrinkers (map default-shrinker inputs)]
                         [shrunk (shrink-inputs inputs shrinkers prop)])
                    `((status . fail)
                      (trial . ,trial)
                      (original . ,inputs)
                      (shrunk . ,shrunk)))))))))

  ;; ---- for-all macro ----
  ;; (for-all ([x gen-int] [y gen-string]) body ...)
  ;; Expands into a (check-property ...) call.
  ;; Each binding's generator is used directly, and body is wrapped
  ;; in a lambda.  Returns the check-property result alist.
  (define-syntax for-all
    (syntax-rules ()
      [(_ ([var gen] ...) body ...)
       (check-property 100
                       (list gen ...)
                       (lambda (var ...) body ...))]))

  ;; ---- quickcheck ----
  ;; Main entry point:
  ;;   (quickcheck n-trials property)
  ;; where property is (lambda (gen-fn) ...) and gen-fn takes a generator
  ;; and returns a random value at the current trial's size.
  ;;
  ;; Returns result alist.
  (define (quickcheck n-trials property)
    (let loop ([trial 0])
      (if (>= trial n-trials)
          `((status . pass) (trials . ,n-trials))
          (let* ([size (min trial 100)]
                 [gen-fn (lambda (gen) (gen size))]
                 [ok? (guard (exn [#t #f])
                        (property gen-fn))])
            (if ok?
                (loop (+ trial 1))
                `((status . fail) (trial . ,trial)))))))

  ) ;; end library
