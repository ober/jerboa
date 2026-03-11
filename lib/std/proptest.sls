#!chezscheme
;;; (std proptest) — Property-Based Testing with Shrinking
;;;
;;; QuickCheck-style property testing for Chez Scheme.
;;; Generators produce random values; on failure, shrinking finds minimal counterexamples.

(library (std proptest)
  (export
    ;; Generators
    gen-integer
    gen-nat
    gen-boolean
    gen-char
    gen-string
    gen-list
    gen-vector
    gen-symbol
    gen-real
    gen-one-of
    gen-frequency
    gen-map
    gen-bind
    gen-such-that
    gen-tuple
    gen-sample
    generator?
    ;; RNG
    make-rng
    rng?
    rng-next!
    rng-next-float!
    ;; Properties
    defproperty
    check-property
    property-result?
    property-passed?
    property-failed?
    property-counterexample
    property-num-trials
    ;; Shrinking
    shrink-integer
    shrink-list
    shrink-string
    shrink-boolean
    shrink-value
    ;; Stateful model testing
    define-model-test
    run-model-test
    ;; Integration with (std test)
    check-property/test
    ;; Reporting
    property-report
    *default-trials*
    *default-seed*)

  (import (chezscheme))

  ;; ========== Parameters ==========

  (define *default-trials* (make-parameter 100))
  (define *default-seed*   (make-parameter 42))

  ;; ========== RNG: Linear Congruential Generator ==========
  ;;
  ;; State is a box holding the current seed value.
  ;; Parameters: a=1664525, c=1013904223, m=2^32 (classic Numerical Recipes LCG)

  (define-record-type rng-rec
    (fields (mutable state))
    (nongenerative rng-rec-uid))

  (define (make-rng seed)
    (make-rng-rec (modulo seed (expt 2 32))))

  (define (rng? x)
    (rng-rec? x))

  (define (rng-next! rng)
    (let* ([s (rng-rec-state rng)]
           [s2 (modulo (+ (* 1664525 s) 1013904223) (expt 2 32))])
      (rng-rec-state-set! rng s2)
      s2))

  (define (rng-next-float! rng)
    (/ (rng-next! rng) (expt 2 32)))

  ;; ========== Generator Protocol ==========
  ;;
  ;; A generator is a procedure: (gen rng size) -> value
  ;; size is a non-negative integer that grows with trial number (0..max-size).

  (define-record-type generator-rec
    (fields proc)
    (nongenerative generator-rec-uid))

  (define (make-generator proc)
    (make-generator-rec proc))

  (define (generator? x)
    (generator-rec? x))

  (define (gen-run gen rng size)
    ((generator-rec-proc gen) rng size))

  ;; (gen-sample gen rng) -> one value at size=10
  (define (gen-sample gen rng)
    (gen-run gen rng 10))

  ;; ========== Basic Generators ==========

  ;; (gen-integer lo hi) -> integer in [lo, hi]
  (define (gen-integer lo hi)
    (make-generator
      (lambda (rng size)
        (let ([range (- hi lo -1)])
          (+ lo (modulo (rng-next! rng) range))))))

  ;; (gen-nat n) -> integer in [0, n] (n grows with size)
  (define (gen-nat . args)
    (let ([max-n (if (null? args) #f (car args))])
      (make-generator
        (lambda (rng size)
          (let ([bound (if max-n max-n (+ 1 size))])
            (modulo (rng-next! rng) (+ 1 bound)))))))

  (define (gen-boolean)
    (make-generator
      (lambda (rng size)
        (= 0 (modulo (rng-next! rng) 2)))))

  (define (gen-char)
    (make-generator
      (lambda (rng size)
        (integer->char (+ 32 (modulo (rng-next! rng) 95))))))

  ;; (gen-string max-len char-gen)
  (define (gen-string max-len char-gen)
    (make-generator
      (lambda (rng size)
        (let* ([bound (min max-len (+ 1 size))]
               [len   (modulo (rng-next! rng) (+ 1 bound))]
               [chars (let loop ([i 0] [acc '()])
                        (if (= i len)
                          (reverse acc)
                          (loop (+ i 1)
                                (cons (gen-run char-gen rng size) acc))))])
          (list->string chars)))))

  ;; (gen-list max-len element-gen)
  (define (gen-list max-len element-gen)
    (make-generator
      (lambda (rng size)
        (let* ([bound (min max-len (+ 1 size))]
               [len   (modulo (rng-next! rng) (+ 1 bound))])
          (let loop ([i 0] [acc '()])
            (if (= i len)
              (reverse acc)
              (loop (+ i 1)
                    (cons (gen-run element-gen rng size) acc))))))))

  ;; (gen-vector max-len element-gen)
  (define (gen-vector max-len element-gen)
    (gen-map list->vector (gen-list max-len element-gen)))

  ;; (gen-symbol) -> random symbol (lowercase letters)
  (define (gen-symbol)
    (gen-map string->symbol
             (gen-string 8 (gen-map integer->char (gen-integer 97 122)))))

  ;; (gen-real) -> float in [-size, size]
  (define (gen-real)
    (make-generator
      (lambda (rng size)
        (let* ([f (rng-next-float! rng)]
               [range (* 2.0 (+ 1.0 (exact->inexact size)))])
          (- (* f range) (/ range 2.0))))))

  ;; (gen-one-of val ...) -> picks one of the given values
  (define (gen-one-of . vals)
    (make-generator
      (lambda (rng size)
        (let ([idx (modulo (rng-next! rng) (length vals))])
          (list-ref vals idx)))))

  ;; (gen-frequency (weight gen) ...) -> weighted choice
  (define (gen-frequency . weighted-gens)
    ;; weighted-gens is a list of (weight gen) pairs
    (make-generator
      (lambda (rng size)
        (let* ([total (fold-left (lambda (acc wg) (+ acc (car wg))) 0 weighted-gens)]
               [r     (* (rng-next-float! rng) total)])
          (let loop ([wgs weighted-gens] [cumulative 0.0])
            (if (null? (cdr wgs))
              (gen-run (cadar wgs) rng size)
              (let ([new-cum (+ cumulative (caar wgs))])
                (if (< r new-cum)
                  (gen-run (cadar wgs) rng size)
                  (loop (cdr wgs) new-cum)))))))))

  ;; (gen-map f gen) -> transforms output of gen through f
  (define (gen-map f gen)
    (make-generator
      (lambda (rng size)
        (f (gen-run gen rng size)))))

  ;; (gen-bind gen f) -> monadic bind: run gen, pass result to f to get next gen
  (define (gen-bind gen f)
    (make-generator
      (lambda (rng size)
        (let ([val (gen-run gen rng size)])
          (gen-run (f val) rng size)))))

  ;; (gen-such-that gen pred [max-tries]) -> filtered generator
  (define (gen-such-that gen pred . args)
    (let ([max-tries (if (null? args) 100 (car args))])
      (make-generator
        (lambda (rng size)
          (let loop ([tries 0])
            (if (>= tries max-tries)
              (error 'gen-such-that "could not satisfy predicate after max tries" max-tries)
              (let ([val (gen-run gen rng size)])
                (if (pred val)
                  val
                  (loop (+ tries 1))))))))))

  ;; (gen-tuple gen1 gen2 ...) -> list of values, one per generator
  (define (gen-tuple . gens)
    (make-generator
      (lambda (rng size)
        (map (lambda (g) (gen-run g rng size)) gens))))

  ;; ========== Shrinking ==========
  ;;
  ;; Each shrinker returns a list of candidate smaller values.

  ;; shrink-integer: produce smaller candidates
  (define (shrink-integer n)
    (cond
      [(= n 0) '()]
      [(> n 0)
       (filter (lambda (x) (and (integer? x) (not (= x n))))
               (list 0 (quotient n 2) (- n 1)))]
      [else ;; n < 0
       (filter (lambda (x) (and (integer? x) (not (= x n))))
               (list 0 (quotient n 2) (+ n 1) (- n)))]))

  ;; shrink-boolean: #t shrinks to #f
  (define (shrink-boolean b)
    (if b '(#f) '()))

  ;; shrink-list: try removing elements
  (define (shrink-list lst shrinker)
    (if (null? lst)
      '()
      (let* ([len (length lst)]
             ;; Drop first element
             [drop-first (cdr lst)]
             ;; Drop last element
             [drop-last (reverse (cdr (reverse lst)))]
             ;; Take first half
             [half-len (quotient len 2)]
             [first-half (list-head lst half-len)])
        ;; Also try shrinking each element
        (let ([element-shrunk
               (let loop ([i 0] [result '()])
                 (if (= i len)
                   result
                   (let* ([elem (list-ref lst i)]
                          [shrunk-elems (shrinker elem)])
                     (let inner ([se shrunk-elems] [acc result])
                       (if (null? se)
                         (loop (+ i 1) acc)
                         (let* ([new-lst (append (list-head lst i)
                                                 (list (car se))
                                                 (list-tail lst (+ i 1)))])
                           (inner (cdr se) (cons new-lst acc))))))))])
          ;; Deduplicate and filter out original
          (let ([candidates
                 (append
                   (if (equal? drop-first lst) '() (list drop-first))
                   (if (or (equal? drop-last lst) (equal? drop-last drop-first)) '() (list drop-last))
                   (if (or (equal? first-half lst) (null? first-half)) '() (list first-half))
                   element-shrunk)])
            (filter (lambda (c) (not (equal? c lst))) candidates))))))

  ;; shrink-string: shrink by reducing length
  (define (shrink-string s)
    (let ([len (string-length s)])
      (if (= len 0)
        '()
        (list
          (substring s 0 (quotient len 2))
          (substring s 1 len)
          (substring s 0 (- len 1))))))

  ;; shrink-value: generic dispatcher based on type
  (define (shrink-value v)
    (cond
      [(integer? v)  (shrink-integer v)]
      [(boolean? v)  (shrink-boolean v)]
      [(string? v)   (shrink-string v)]
      [(list? v)     (shrink-list v shrink-value)]
      [else          '()]))

  ;; ========== Properties ==========

  (define-record-type property-rec
    (fields name gens body)
    (nongenerative property-rec-uid))

  ;; (defproperty name (gen ...) body-expr)
  ;; body-expr evaluates to a procedure accepting as many args as there are generators.
  ;; Called with generated values; should return truthy to pass (or raise on failure).
  (define-syntax defproperty
    (lambda (stx)
      (syntax-case stx ()
        [(_ prop-name (g ...) body-expr)
         #'(define prop-name
             (make-property-rec
               'prop-name
               (list g ...)
               body-expr))])))

  ;; Result record
  (define-record-type property-result-rec
    (fields passed? counterexample num-trials failure-msg)
    (nongenerative property-result-rec-uid))

  (define (property-result? x)   (property-result-rec? x))
  (define (property-passed? r)   (property-result-rec-passed? r))
  (define (property-failed? r)   (not (property-result-rec-passed? r)))
  (define (property-counterexample r) (property-result-rec-counterexample r))
  (define (property-num-trials r) (property-result-rec-num-trials r))

  ;; Try to find a smaller failing example via shrinking
  (define (shrink-inputs inputs body)
    (let loop ([current inputs] [steps 0])
      (if (> steps 1000)
        current
        ;; Try shrinking each input position
        (let find-smaller ([i 0] [found #f])
          (if (= i (length current))
            (if found
              (loop found (+ steps 1))
              current)
            ;; Shrink the i-th element
            (let* ([elem (list-ref current i)]
                   [candidates (shrink-value elem)])
              (let try-candidates ([cs candidates] [best found])
                (if (null? cs)
                  (find-smaller (+ i 1) best)
                  (let* ([new-inputs (append (list-head current i)
                                             (list (car cs))
                                             (list-tail current (+ i 1)))]
                         [still-fails?
                          (guard (exn [#t #t])
                            (not (apply body new-inputs)))])
                    (if still-fails?
                      (try-candidates (cdr cs) new-inputs)
                      (try-candidates (cdr cs) best)))))))))))

  ;; (check-property prop [#:trials N] [#:seed S]) -> property-result
  (define (check-property prop . kwargs)
    (let* ([trials (let loop ([kw kwargs] [v (*default-trials*)])
                     (cond [(null? kw) v]
                           [(eq? (car kw) '|#:trials|) (cadr kw)]
                           [else (loop (cddr kw) v)]))]
           [seed   (let loop ([kw kwargs] [v (*default-seed*)])
                     (cond [(null? kw) v]
                           [(eq? (car kw) '|#:seed|) (cadr kw)]
                           [else (loop (cddr kw) v)]))]
           [rng    (make-rng seed)]
           [gens   (property-rec-gens prop)]
           [body   (property-rec-body prop)])
      ;; Run trials
      (let loop ([trial 0])
        (if (= trial trials)
          ;; All passed
          (make-property-result-rec #t #f trial #f)
          ;; Generate inputs for this trial
          (let* ([size    (min trial 100)]
                 [inputs  (map (lambda (g) (gen-run g rng size)) gens)]
                 [failed? (guard (exn [#t #t])
                            ;; Consider #f return as failure
                            (not (apply body inputs)))])
            (if failed?
              ;; Shrink and report
              (let ([shrunk (shrink-inputs inputs body)])
                (make-property-result-rec #f shrunk (+ trial 1) #f))
              (loop (+ trial 1))))))))

  ;; Human-readable report
  (define (property-report result)
    (if (property-passed? result)
      (format "OK: ~a trials passed." (property-num-trials result))
      (format "FAILED after ~a trial(s). Counterexample: ~s"
              (property-num-trials result)
              (property-counterexample result))))

  ;; ========== Integration with (std test) ==========
  ;; check-property/test: signal failure through assertion-style mechanism
  ;; (Works standalone; does not require importing (std test) at library phase)

  (define (check-property/test prop . kwargs)
    (let ([result (apply check-property prop kwargs)])
      (unless (property-passed? result)
        (error 'check-property/test
               (property-report result)
               (property-counterexample result)))))

  ;; ========== Stateful Model Testing ==========
  ;;
  ;; A model test checks that a "real" system matches an "ideal" model
  ;; when a sequence of random commands is applied.

  (define-record-type model-test-rec
    (fields name make-model make-real commands invariant)
    (nongenerative model-test-rec-uid))

  ;; (define-model-test name model commands ...)
  ;; model is (make-model make-real (command-name gen (model-var real-var) body ...) ...)
  ;; Each command clause creates a handler (lambda (model-var real-var) body ...).
  (define-syntax define-model-test
    (lambda (stx)
      (syntax-case stx ()
        [(_ mt-name (make-model-expr make-real-expr) cmd-clause ...)
         ;; cmd-clause: (cmd-name cmd-gen (param1 param2) body ...)
         (let* ([clauses  (syntax->list #'(cmd-clause ...))]
                [cmd-list
                 (map (lambda (clause)
                        (syntax-case clause ()
                          [(cname cgen (p1 p2) cbody ...)
                           #'(list 'cname cgen
                                   (lambda (p1 p2)
                                     cbody ...))]))
                      clauses)])
           (with-syntax ([(cmd-entry ...) cmd-list])
             #'(define mt-name
                 (make-model-test-rec
                   'mt-name
                   (lambda () make-model-expr)
                   (lambda () make-real-expr)
                   (list cmd-entry ...)
                   (lambda (mv rv) #t)))))])))

  ;; (run-model-test test [#:steps 100] [#:trials 10])
  (define (run-model-test mt . kwargs)
    (let* ([steps  (let loop ([kw kwargs] [v 100])
                     (cond [(null? kw) v]
                           [(eq? (car kw) '|#:steps|) (cadr kw)]
                           [else (loop (cddr kw) v)]))]
           [trials (let loop ([kw kwargs] [v 10])
                     (cond [(null? kw) v]
                           [(eq? (car kw) '|#:trials|) (cadr kw)]
                           [else (loop (cddr kw) v)]))]
           [seed   (let loop ([kw kwargs] [v (*default-seed*)])
                     (cond [(null? kw) v]
                           [(eq? (car kw) '|#:seed|) (cadr kw)]
                           [else (loop (cddr kw) v)]))]
           [cmds   (model-test-rec-commands mt)]
           [cmd-gen (gen-one-of . (map (lambda (c) (list-ref c 2)) cmds))])
      (let trial-loop ([t 0] [rng (make-rng seed)])
        (if (= t trials)
          'passed
          (let ([model ((model-test-rec-make-model mt))]
                [real  ((model-test-rec-make-real mt))])
            (let step-loop ([s 0])
              (if (= s steps)
                (trial-loop (+ t 1) rng)
                (let* ([cmd-idx (modulo (rng-next! rng) (length cmds))]
                       [cmd     (list-ref cmds cmd-idx)]
                       [cmd-fn  (list-ref cmd 2)])
                  (guard (exn [#t (list 'failed-at t s
                                       (list-ref cmd 0)
                                       (if (message-condition? exn)
                                         (condition-message exn)
                                         (format "~a" exn)))])
                    (cmd-fn model real)
                    (step-loop (+ s 1)))))))))))

  ) ;; end library
