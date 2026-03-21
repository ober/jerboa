#!chezscheme
;;; (std test fuzz) -- Fuzzing harness library for Jerboa
;;;
;;; Provides random input generators, mutators, timeout detection via
;;; Chez Scheme's engine mechanism, memory tracking, and reporting.

(library (std test fuzz)
  (export
    ;; Configuration
    fuzz-iterations fuzz-max-size fuzz-fuel
    getenv-int
    ;; Generators
    random-bytevector random-ascii-string random-utf8-string
    random-choice random-element
    ;; Mutators
    mutate-bytevector mutate-string
    ;; Harness
    fuzz-run fuzz-one fuzz-with-timeout
    ;; Oracles
    fuzz-roundtrip-check
    ;; Reporting
    fuzz-report make-fuzz-stats
    fuzz-stats-iterations fuzz-stats-exceptions
    fuzz-stats-timeouts fuzz-stats-crashes
    fuzz-stats-name)

  (import (chezscheme))

  ;;; ========== Configuration ==========

  (define (getenv-int name default)
    (let ([v (getenv name)])
      (if v (or (string->number v) default) default)))

  (define fuzz-iterations (make-parameter (getenv-int "FUZZ_ITERATIONS" 10000)))
  (define fuzz-max-size   (make-parameter (getenv-int "FUZZ_MAX_SIZE" 4096)))
  (define fuzz-fuel       (make-parameter (getenv-int "FUZZ_FUEL" 500000)))

  ;;; ========== Random helpers ==========

  (define (random-bytevector n)
    (let ([bv (make-bytevector n)])
      (do ([i 0 (+ i 1)])
          ((= i n) bv)
        (bytevector-u8-set! bv i (random 256)))))

  (define (random-ascii-string max-len)
    (let* ([len (+ 1 (random (max 1 max-len)))]
           [chars (map (lambda (_) (integer->char (+ 32 (random 95))))
                       (make-list len))])
      (list->string chars)))

  (define (random-utf8-string max-len)
    ;; Generate a string with random printable chars + some edge cases
    (let* ([len (+ 1 (random (max 1 max-len)))]
           [chars (map (lambda (_)
                         (let ([r (random 100)])
                           (cond
                             [(< r 70) (integer->char (+ 32 (random 95)))]    ;; ASCII printable
                             [(< r 85) (integer->char (+ #x100 (random #x100)))] ;; Latin extended
                             [(< r 95) (integer->char (+ #x4E00 (random #x100)))] ;; CJK
                             [else (integer->char (random 128))])))            ;; ASCII full
                       (make-list len))])
      (list->string chars)))

  (define (random-choice . options)
    (list-ref options (random (length options))))

  (define (random-element lst)
    (list-ref lst (random (length lst))))

  ;;; ========== Mutators ==========

  (define (mutate-bytevector bv)
    (when (zero? (bytevector-length bv))
      (error 'mutate-bytevector "cannot mutate empty bytevector"))
    (let* ([copy (bytevector-copy bv)]
           [len  (bytevector-length copy)]
           [n-mutations (+ 1 (random (min 5 len)))])
      (do ([m 0 (+ m 1)])
          ((= m n-mutations) copy)
        (let ([pos (random len)])
          (case (random 5)
            [(0) ;; bit flip
             (bytevector-u8-set! copy pos
               (bitwise-xor (bytevector-u8-ref copy pos)
                            (bitwise-arithmetic-shift-left 1 (random 8))))]
            [(1) (bytevector-u8-set! copy pos 0)]        ;; null
            [(2) (bytevector-u8-set! copy pos #xFF)]      ;; max byte
            [(3) (bytevector-u8-set! copy pos (random 256))] ;; random
            [(4) ;; boundary value
             (bytevector-u8-set! copy pos
               (random-element '(0 1 #x7E #x7F #x80 #xFE #xFF)))])))))

  (define (mutate-string s)
    (if (string=? s "")
      (random-ascii-string 10)
      (let* ([bv (string->utf8 s)]
             [mutated (mutate-bytevector bv)])
        ;; Try to convert back; if invalid UTF-8, return original with char mutation
        (guard (e [#t
                   (let* ([chars (string->list s)]
                          [pos (random (length chars))]
                          [new-char (integer->char (+ 32 (random 95)))])
                     (let loop ([i 0] [rest chars] [acc '()])
                       (if (null? rest)
                         (list->string (reverse acc))
                         (loop (+ i 1) (cdr rest)
                               (cons (if (= i pos) new-char (car rest)) acc)))))])
          (utf8->string mutated)))))

  ;;; ========== Timeout via engine ==========

  (define (fuzz-with-timeout thunk fuel)
    ;; Returns: ('ok . result) | ('timeout . #f) | ('exception . condition)
    (guard (exn
             [#t (cons 'exception exn)])
      (let ([eng (make-engine thunk)])
        (eng fuel
          (lambda (remaining result)
            (cons 'ok result))
          (lambda (new-engine)
            (cons 'timeout #f))))))

  ;;; ========== Stats record ==========

  (define-record-type fuzz-stats
    (fields name
            (mutable iterations)
            (mutable exceptions)
            (mutable timeouts)
            (mutable crashes))
    (protocol
      (lambda (new)
        (lambda (name)
          (new name 0 0 0 0)))))

  ;;; ========== Core harness ==========

  (define (fuzz-one parse-fn input stats)
    (let ([result (fuzz-with-timeout
                    (lambda () (parse-fn input))
                    (fuzz-fuel))])
      (fuzz-stats-iterations-set! stats (+ 1 (fuzz-stats-iterations stats)))
      (case (car result)
        [(ok) 'ok]
        [(timeout)
         (fuzz-stats-timeouts-set! stats (+ 1 (fuzz-stats-timeouts stats)))
         'timeout]
        [(exception)
         (fuzz-stats-exceptions-set! stats (+ 1 (fuzz-stats-exceptions stats)))
         'exception])))

  (define (fuzz-run name parse-fn gen-fn . rest)
    (let* ([iterations (if (pair? rest) (car rest) (fuzz-iterations))]
           [stats (make-fuzz-stats name)]
           [progress-interval (max 1 (quotient iterations 10))])
      (fprintf (current-error-port) "[fuzz] ~a: ~a iterations~n" name iterations)
      (let loop ([i 0])
        (when (< i iterations)
          (when (and (> i 0) (zero? (modulo i progress-interval)))
            (fprintf (current-error-port) "[fuzz] ~a: ~a/~a (~a exceptions, ~a timeouts)~n"
                     name i iterations
                     (fuzz-stats-exceptions stats)
                     (fuzz-stats-timeouts stats)))
          (let ([input (gen-fn)])
            (fuzz-one parse-fn input stats))
          (loop (+ i 1))))
      (fuzz-report stats)
      stats))

  ;;; ========== Roundtrip oracle ==========

  (define (fuzz-roundtrip-check name encode decode gen-fn . rest)
    ;; Tests: decode(encode(x)) == x for random inputs
    (let* ([iterations (if (pair? rest) (car rest) (fuzz-iterations))]
           [stats (make-fuzz-stats (string-append name "-roundtrip"))]
           [mismatches 0])
      (fprintf (current-error-port) "[fuzz] ~a roundtrip: ~a iterations~n" name iterations)
      (let loop ([i 0])
        (when (< i iterations)
          (let ([input (gen-fn)])
            (guard (exn [#t
                         (fuzz-stats-exceptions-set! stats
                           (+ 1 (fuzz-stats-exceptions stats)))])
              (let* ([encoded (encode input)]
                     [decoded (decode encoded)])
                (unless (equal? input decoded)
                  (set! mismatches (+ mismatches 1))
                  (when (<= mismatches 5)
                    (fprintf (current-error-port)
                             "[fuzz] MISMATCH: input=~s encoded=~s decoded=~s~n"
                             input encoded decoded))))))
          (fuzz-stats-iterations-set! stats (+ 1 (fuzz-stats-iterations stats)))
          (loop (+ i 1))))
      (when (> mismatches 0)
        (fprintf (current-error-port) "[fuzz] ~a roundtrip: ~a MISMATCHES in ~a iterations~n"
                 name mismatches iterations))
      (fuzz-report stats)
      stats))

  ;;; ========== Reporting ==========

  (define (fuzz-report stats)
    (let ([name (fuzz-stats-name stats)]
          [iters (fuzz-stats-iterations stats)]
          [exc (fuzz-stats-exceptions stats)]
          [to (fuzz-stats-timeouts stats)]
          [crashes (fuzz-stats-crashes stats)])
      (fprintf (current-error-port)
               "[fuzz] ~a: DONE ~a iterations — ~a exceptions, ~a timeouts, ~a crashes~n"
               name iters exc to crashes)
      (when (> crashes 0)
        (fprintf (current-error-port) "[fuzz] ~a: *** ~a CRASHES DETECTED ***~n"
                 name crashes))))

  ) ;; end library
