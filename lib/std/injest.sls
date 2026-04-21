#!chezscheme
;;; (std injest) — Clojure-style injest smart threading macros.
;;;
;;; Inspired by matthewdowney/injest for Clojure. Provides two macros:
;;;
;;;   (=>  coll step ...)  — smart thread-last (like ->>) with automatic
;;;                          transducer fusion when two or more adjacent
;;;                          steps are recognised sequence operations.
;;;
;;;   (x>> coll step ...)  — explicit transducer pipeline. Every step
;;;                          must be a recognised transducer-convertible
;;;                          form; expansion produces a single fused
;;;                          (sequence (compose-transducers ...) coll)
;;;                          call. Use when you want to guarantee fusion
;;;                          and get a compile-time error otherwise.
;;;
;;; Recognised heads (each maps to an (std transducer) constructor):
;;;
;;;   (map f)          -> (mapping f)
;;;   (filter p)       -> (filtering p)
;;;   (remove p)       -> (filtering (lambda (x) (not (p x))))
;;;   (take n)         -> (taking n)
;;;   (drop n)         -> (dropping n)
;;;   (mapcat f)       -> (flat-mapping f)
;;;   (append-map f)   -> (flat-mapping f)
;;;   (take-while p)   -> (taking-while p)
;;;   (drop-while p)   -> (dropping-while p)
;;;   (filter-map f)   -> (mapping f) + (filtering identity)
;;;   (dedupe)         -> (deduplicate)  ; consecutive-only
;;;   (deduplicate)    -> (deduplicate)
;;;   (indexing)       -> (indexing)
;;;   (enumerate)      -> (indexing)
;;;   (indexed)        -> (indexing)
;;;
;;; Head matching is by symbol name (not free-identifier=?), so the
;;; macros recognise these operations regardless of which import they
;;; came from. Steps not matching a recognised head fall through to
;;; plain thread-last semantics in =>, and are a syntax error in x>>.
;;;
;;; A single recognised step in => is emitted as the native call
;;; (e.g. (map f v)) rather than through the transducer machinery, to
;;; avoid the allocation overhead of a one-stage pipeline. Fusion only
;;; kicks in when a run has two or more recognised steps.

(library (std injest)
  (export => x>>)
  (import (except (chezscheme) =>)
          (std transducer))

  ;; ---------------------------------------------------------------
  ;; Head recognition (compile-time helpers).
  ;; ---------------------------------------------------------------
  ;; Return a syntax object for the transducer constructor expression,
  ;; or #f if step is not a recognised transducer-convertible form.

  (meta define (recognize-step step)
    (syntax-case step ()
      [(head arg ...)
       (identifier? #'head)
       (case (syntax->datum #'head)
         [(map)          #'(mapping arg ...)]
         [(filter)       #'(filtering arg ...)]
         [(remove)
          (syntax-case #'(arg ...) ()
            [(p) #'(filtering (lambda (%x) (not (p %x))))]
            [_ #f])]
         [(take)         #'(taking arg ...)]
         [(drop)         #'(dropping arg ...)]
         [(mapcat append-map) #'(flat-mapping arg ...)]
         [(take-while)   #'(taking-while arg ...)]
         [(drop-while)   #'(dropping-while arg ...)]
         [(filter-map)
          (syntax-case #'(arg ...) ()
            [(f) #'(compose-transducers
                     (mapping f)
                     (filtering (lambda (%x) %x)))]
            [_ #f])]
         [(dedupe deduplicate) #'(deduplicate)]
         [(indexing enumerate indexed) #'(indexing)]
         [else #f])]
      [head
       (identifier? #'head)
       (case (syntax->datum #'head)
         [(dedupe deduplicate) #'(deduplicate)]
         [(indexing enumerate indexed) #'(indexing)]
         [else #f])]
      [_ #f]))

  ;; Build the syntax for a plain thread-last application of step to v.
  ;;   (f a b) , v  =>  (f a b v)
  ;;   f       , v  =>  (f v)
  (meta define (thread-last-apply step v)
    (syntax-case step ()
      [(f arg ...) (with-syntax ([v v]) #'(f arg ... v))]
      [f           (with-syntax ([v v]) #'(f v))]))

  ;; Given a non-empty list of ORIGINAL step syntaxes that were all
  ;; recognised, and the input value syntax v, return the expression
  ;; syntax for running them. A singleton run is emitted as the native
  ;; call (no transducer overhead); a longer run is fused.
  (meta define (emit-run v run)
    (cond
      [(null? (cdr run))
       ;; Single recognised step — emit as native thread-last call.
       (thread-last-apply (car run) v)]
      [else
       (let ([xfs (map recognize-step run)])
         (with-syntax ([(xf ...) xfs]
                       [v v])
           #'(sequence (compose-transducers xf ...) v)))]))

  ;; Main walk: fold a list of steps into a nested expression over v.
  (meta define (walk v steps)
    (cond
      [(null? steps) v]
      [(recognize-step (car steps))
       ;; Start a run; greedily extend while next steps are recognised.
       (let loop ([run (list (car steps))]
                  [rest (cdr steps)])
         (cond
           [(null? rest)
            (emit-run v (reverse run))]
           [(recognize-step (car rest))
            (loop (cons (car rest) run) (cdr rest))]
           [else
            (walk (emit-run v (reverse run)) rest)]))]
      [else
       (walk (thread-last-apply (car steps) v) (cdr steps))]))

  ;; ---------------------------------------------------------------
  ;; => : smart thread-last
  ;; ---------------------------------------------------------------
  (define-syntax =>
    (lambda (stx)
      (syntax-case stx ()
        [(_ v) #'v]
        [(_ v step ...)
         (walk #'v (syntax->list #'(step ...)))])))

  ;; ---------------------------------------------------------------
  ;; x>> : strict transducer pipeline
  ;; ---------------------------------------------------------------
  (define-syntax x>>
    (lambda (stx)
      (syntax-case stx ()
        [(_ v) #'v]
        [(_ v step ...)
         (let* ([steps  (syntax->list #'(step ...))]
                [xfs    (map recognize-step steps)]
                [bad    (let loop ([ss steps] [rs xfs])
                          (cond
                            [(null? ss) #f]
                            [(not (car rs)) (car ss)]
                            [else (loop (cdr ss) (cdr rs))]))])
           (cond
             [bad
              (syntax-violation 'x>>
                "step is not a recognised transducer-convertible form"
                stx bad)]
             [(null? (cdr xfs))
              (with-syntax ([xf (car xfs)])
                #'(sequence xf v))]
             [else
              (with-syntax ([(xf ...) xfs])
                #'(sequence (compose-transducers xf ...) v))]))])))

  ) ;; end library
