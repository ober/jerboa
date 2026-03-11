#!chezscheme
;;; (std regex-ct-impl) -- Regex Pipeline Implementation
;;;
;;; All phase-0 helper functions for the regex compile-time pipeline.
;;; Imported at phase 1 (via eval) by (std regex-ct)'s define-regex macro.

(library (std regex-ct-impl)
  (export
    ;; Parse state helpers
    make-parse-state
    ps-str
    ps-pos
    ps-set-pos!
    ps-end?
    ps-peek
    ps-next!
    ps-new-group!

    ;; Parser
    parse-regex
    parse-alternation
    parse-sequence
    parse-quantified
    parse-repetition
    parse-digits
    parse-atom
    parse-char-class
    parse-escape

    ;; NFA
    make-nfa-builder
    ast->nfa

    ;; DFA
    nfa->dfa
    epsilon-closure
    move
    nfa-alphabet

    ;; Code generation
    dfa->scheme
    label->pred-datum
    char-matches-class?

    ;; Utilities
    filter-map)

  (import (chezscheme))

  ;;; ========== Regex AST ==========
  ;; AST nodes:
  ;;   (lit ch)           — literal character
  ;;   (dot)              — any character except newline
  ;;   (class chars neg?) — character class [...]
  ;;   (seq a b)          — concatenation
  ;;   (alt a b)          — alternation |
  ;;   (star a)           — Kleene star *
  ;;   (plus a)           — one or more +
  ;;   (opt a)            — zero or one ?
  ;;   (rep a n m)        — {n,m} repetition (m=#f for {n,})
  ;;   (anchor-start)     — ^
  ;;   (anchor-end)       — $
  ;;   (group n a)        — capture group n
  ;;   (epsilon)          — empty string

  ;;; ========== Regex Parser ==========

  ;; Parse state: string + mutable position + group counter
  (define (make-parse-state str)
    (vector str 0 0))  ; [string, pos, group-count]
  (define (ps-str ps)   (vector-ref ps 0))
  (define (ps-pos ps)   (vector-ref ps 1))
  (define (ps-set-pos! ps i) (vector-set! ps 1 i))
  (define (ps-end? ps)  (= (ps-pos ps) (string-length (ps-str ps))))
  (define (ps-peek ps)  (string-ref (ps-str ps) (ps-pos ps)))
  (define (ps-next! ps) (let ([c (ps-peek ps)]) (ps-set-pos! ps (+ 1 (ps-pos ps))) c))
  (define (ps-new-group! ps)
    (let ([n (vector-ref ps 2)])
      (vector-set! ps 2 (+ 1 n))
      (+ 1 n)))

  ;; Parse a full regex string
  (define (parse-regex str)
    (let ([ps (make-parse-state str)])
      (let ([ast (parse-alternation ps)])
        (if (ps-end? ps)
          ast
          (error 'parse-regex "unexpected character" (ps-peek ps))))))

  ;; alternation: seq (| seq)*
  (define (parse-alternation ps)
    (let ([left (parse-sequence ps)])
      (if (and (not (ps-end? ps)) (char=? (ps-peek ps) #\|))
        (begin
          (ps-next! ps)  ; consume |
          (list 'alt left (parse-alternation ps)))
        left)))

  ;; sequence: atom*
  (define (parse-sequence ps)
    (let loop ([parts '()])
      (if (or (ps-end? ps)
              (char=? (ps-peek ps) #\|)
              (char=? (ps-peek ps) #\)))
        (if (null? parts)
          '(epsilon)
          (if (= 1 (length parts))
            (car parts)
            (fold-right (lambda (a b) (list 'seq a b))
                        (car (reverse parts))
                        (reverse (cdr (reverse parts))))))
        (let ([atom (parse-quantified ps)])
          (loop (append parts (list atom)))))))

  ;; quantified: atom [*+?{n,m}]
  (define (parse-quantified ps)
    (let ([atom (parse-atom ps)])
      (if (ps-end? ps)
        atom
        (case (ps-peek ps)
          [(#\*) (ps-next! ps) (list 'star atom)]
          [(#\+) (ps-next! ps) (list 'plus atom)]
          [(#\?) (ps-next! ps) (list 'opt atom)]
          [(#\{) (parse-repetition ps atom)]
          [else atom]))))

  ;; repetition: {n} or {n,} or {n,m}
  (define (parse-repetition ps atom)
    (ps-next! ps)  ; consume {
    (let ([n (parse-digits ps)])
      (cond
        [(and (not (ps-end? ps)) (char=? (ps-peek ps) #\}))
         (ps-next! ps)  ; consume }
         (list 'rep atom n n)]
        [(and (not (ps-end? ps)) (char=? (ps-peek ps) #\,))
         (ps-next! ps)  ; consume ,
         (if (and (not (ps-end? ps)) (char=? (ps-peek ps) #\}))
           (begin (ps-next! ps) (list 'rep atom n #f))
           (let ([m (parse-digits ps)])
             (when (not (ps-end? ps)) (ps-next! ps))  ; consume }
             (list 'rep atom n m)))]
        [else (error 'parse-repetition "bad repetition")])))

  (define (parse-digits ps)
    (let loop ([n 0] [found? #f])
      (if (and (not (ps-end? ps)) (char-numeric? (ps-peek ps)))
        (loop (+ (* n 10) (- (char->integer (ps-next! ps)) 48)) #t)
        (if found? n (error 'parse-digits "expected digits")))))

  ;; atom: literal, class, group, anchor, dot, escape
  (define (parse-atom ps)
    (if (ps-end? ps)
      '(epsilon)
      (case (ps-peek ps)
        [(#\()
         (ps-next! ps)  ; consume (
         (let* ([group-num (ps-new-group! ps)]
                [inner (parse-alternation ps)])
           (when (and (not (ps-end? ps)) (char=? (ps-peek ps) #\)))
             (ps-next! ps))  ; consume )
           (list 'group group-num inner))]
        [(#\[)
         (ps-next! ps)  ; consume [
         (parse-char-class ps)]
        [(#\.)
         (ps-next! ps)
         '(dot)]
        [(#\^)
         (ps-next! ps)
         '(anchor-start)]
        [(#\$)
         (ps-next! ps)
         '(anchor-end)]
        [(#\\)
         (ps-next! ps)  ; consume backslash
         (parse-escape ps)]
        [else
         (list 'lit (ps-next! ps))])))

  ;; Character class: [chars] or [^chars]
  (define (parse-char-class ps)
    (let ([negated? (and (not (ps-end? ps)) (char=? (ps-peek ps) #\^))])
      (when negated? (ps-next! ps))
      (let loop ([chars '()])
        (cond
          [(ps-end? ps) (list 'class chars negated?)]
          [(char=? (ps-peek ps) #\])
           (ps-next! ps)
           (list 'class (reverse chars) negated?)]
          [else
           (let ([c (ps-next! ps)])
             ;; Check for range a-z
             (if (and (not (ps-end? ps))
                      (char=? (ps-peek ps) #\-)
                      (> (- (string-length (ps-str ps)) (ps-pos ps)) 1)
                      (not (char=? (string-ref (ps-str ps) (+ 1 (ps-pos ps))) #\])))
               (begin
                 (ps-next! ps)  ; consume -
                 (let ([end (ps-next! ps)])
                   (loop (cons (cons 'range (cons c end)) chars))))
               (loop (cons c chars))))]))))

  ;; Escape sequences
  (define (parse-escape ps)
    (if (ps-end? ps)
      (error 'parse-escape "trailing backslash")
      (let ([c (ps-next! ps)])
        (case c
          [(#\d) '(class (range . (#\0 . #\9)) #f)]
          [(#\D) '(class ((range . (#\0 . #\9))) #t)]
          [(#\w) '(class ((range . (#\a . #\z)) (range . (#\A . #\Z)) (range . (#\0 . #\9)) #\_) #f)]
          [(#\W) '(class ((range . (#\a . #\z)) (range . (#\A . #\Z)) (range . (#\0 . #\9)) #\_) #t)]
          [(#\s) '(class (#\space #\tab #\newline #\return) #f)]
          [(#\S) '(class (#\space #\tab #\newline #\return) #t)]
          [(#\n) '(lit #\newline)]
          [(#\r) '(lit #\return)]
          [(#\t) '(lit #\tab)]
          [else  (list 'lit c)]))))

  ;;; ========== NFA Construction (Thompson's algorithm) ==========

  (define (make-nfa-builder)
    (let ([states (make-vector 256 #f)]
          [count  0])
      (define (new-state!)
        (when (>= count (vector-length states))
          (let ([new (make-vector (* 2 (vector-length states)) #f)])
            (do ([i 0 (+ i 1)]) ((= i count))
              (vector-set! new i (vector-ref states i)))
            (set! states new)))
        (vector-set! states count '())
        (let ([n count])
          (set! count (+ 1 n))
          n))
      (define (add-transition! from label to)
        (vector-set! states from
          (cons (list label to) (vector-ref states from))))
      (define (get-states)
        (let ([v (make-vector count)])
          (do ([i 0 (+ i 1)]) ((= i count) v)
            (vector-set! v i (vector-ref states i)))))
      (lambda (msg . args)
        (case msg
          [(new-state!)     (new-state!)]
          [(add-transition!) (apply add-transition! args)]
          [(get-states)     (get-states)]
          [(count)          count]))))

  ;; Build NFA from AST. Returns (start-state . accept-state).
  (define (ast->nfa ast nfa)
    (define (new!) (nfa 'new-state!))
    (define (link! from label to) (nfa 'add-transition! from label to))

    (let build ([node ast])
      (case (car node)
        [(epsilon)
         (let ([s (new!)] [e (new!)])
           (link! s 'epsilon e)
           (cons s e))]

        [(lit)
         (let ([s (new!)] [e (new!)])
           (link! s (cadr node) e)
           (cons s e))]

        [(dot)
         (let ([s (new!)] [e (new!)])
           (link! s 'dot e)
           (cons s e))]

        [(class)
         (let ([s (new!)] [e (new!)])
           (link! s (list 'class (cadr node) (caddr node)) e)
           (cons s e))]

        [(anchor-start)
         (let ([s (new!)] [e (new!)])
           (link! s 'anchor-start e)
           (cons s e))]

        [(anchor-end)
         (let ([s (new!)] [e (new!)])
           (link! s 'anchor-end e)
           (cons s e))]

        [(group)
         ;; Same as inner for DFA purposes
         (build (caddr node))]

        [(seq)
         (let ([left  (build (cadr node))]
               [right (build (caddr node))])
           (link! (cdr left) 'epsilon (car right))
           (cons (car left) (cdr right)))]

        [(alt)
         (let ([s    (new!)]
               [e    (new!)]
               [left  (build (cadr node))]
               [right (build (caddr node))])
           (link! s 'epsilon (car left))
           (link! s 'epsilon (car right))
           (link! (cdr left)  'epsilon e)
           (link! (cdr right) 'epsilon e)
           (cons s e))]

        [(star)
         (let ([s    (new!)]
               [e    (new!)]
               [inner (build (cadr node))])
           (link! s 'epsilon (car inner))
           (link! s 'epsilon e)
           (link! (cdr inner) 'epsilon (car inner))
           (link! (cdr inner) 'epsilon e)
           (cons s e))]

        [(plus)
         ;; a+ = a a*
         (let ([inner1 (build (cadr node))]
               [inner2 (build (list 'star (cadr node)))])
           (link! (cdr inner1) 'epsilon (car inner2))
           (cons (car inner1) (cdr inner2)))]

        [(opt)
         ;; a? = (a | epsilon)
         (build (list 'alt (cadr node) '(epsilon)))]

        [(rep)
         ;; {n,m}: expand manually
         (let* ([a    (cadr node)]
                [n    (caddr node)]
                [m    (cadddr node)]
                [base (let loop ([i 0] [acc '(epsilon)])
                        (if (= i n) acc
                            (loop (+ i 1) (list 'seq a acc))))]
                [tail (cond
                        [(not m) (list 'star a)]
                        [(= m n) '(epsilon)]
                        [else (let loop ([i n] [acc '(epsilon)])
                                (if (= i m) acc
                                    (loop (+ i 1) (list 'seq (list 'opt a) acc))))])])
           (build (list 'seq base tail)))]

        [else (error 'ast->nfa "unknown node" node)])))

  ;;; ========== NFA to DFA (Subset Construction) ==========

  ;; Compute epsilon-closure of a set of NFA states.
  (define (epsilon-closure states nfa-states)
    (let loop ([todo (list->vector states)] [head 0] [visited (make-eq-hashtable)])
      (if (= head (vector-length todo))
        (let-values ([(keys _) (hashtable-entries visited)])
          (sort < (vector->list keys)))
        (let ([s (vector-ref todo head)])
          (if (hashtable-ref visited s #f)
            (loop todo (+ head 1) visited)
            (begin
              (hashtable-set! visited s #t)
              (let* ([trans (vector-ref nfa-states s)]
                     [eps-targets (map cadr (filter (lambda (t) (eq? (car t) 'epsilon)) trans))])
                (loop (list->vector (append (vector->list todo) eps-targets))
                      (+ head 1) visited))))))))

  ;; Compute the set of NFA states reachable from `state-set` via `label`.
  (define (move state-set label nfa-states)
    (let ([result '()])
      (for-each
        (lambda (s)
          (for-each
            (lambda (trans)
              (when (equal? (car trans) label)
                (set! result (cons (cadr trans) result))))
            (vector-ref nfa-states s)))
        state-set)
      result))

  ;; Collect all unique labels (non-epsilon) from NFA.
  (define (nfa-alphabet nfa-states)
    (let ([labels (make-eq-hashtable)])
      (vector-for-each
        (lambda (trans-list)
          (for-each
            (lambda (t)
              (let ([lbl (car t)])
                (unless (eq? lbl 'epsilon)
                  (hashtable-set! labels lbl #t))))
            trans-list))
        nfa-states)
      (let-values ([(keys _) (hashtable-entries labels)])
        (vector->list keys))))

  ;; Convert NFA to DFA using subset construction.
  ;; Returns: (values dfa-states transitions accept-states state-map)
  (define (nfa->dfa nfa-states nfa-start nfa-accept)
    (let* ([start-closure (epsilon-closure (list nfa-start) nfa-states)]
           [alphabet (nfa-alphabet nfa-states)]
           [dfa-states (list start-closure)]
           [dfa-state-map (make-hashtable equal-hash equal?)]
           [transitions '()]
           [work-list (list start-closure)]
           [state-idx 0])

      (hashtable-set! dfa-state-map start-closure 0)

      (let loop ([work work-list])
        (unless (null? work)
          (let* ([current-set (car work)]
                 [current-idx (hashtable-ref dfa-state-map current-set #f)])
            (for-each
              (lambda (label)
                (let* ([moved   (move current-set label nfa-states)]
                       [closure (epsilon-closure moved nfa-states)])
                  (unless (null? closure)
                    (let ([target-idx
                           (or (hashtable-ref dfa-state-map closure #f)
                               (let ([new-idx (+ 1 (hashtable-size dfa-state-map))])
                                 (hashtable-set! dfa-state-map closure new-idx)
                                 (set! dfa-states (append dfa-states (list closure)))
                                 (set! work (append work (list closure)))
                                 new-idx))])
                      (set! transitions
                        (cons (list current-idx label target-idx) transitions))))))
              alphabet)
            (loop (cdr work)))))

      (let ([accept-states
             (filter-map
               (lambda (state-set)
                 (and (member nfa-accept state-set)
                      (hashtable-ref dfa-state-map state-set #f)))
               dfa-states)])
        (values dfa-states transitions accept-states dfa-state-map))))

  ;;; ========== DFA to Scheme code ==========

  ;; Character class matcher
  (define (char-matches-class? c class-spec negated?)
    (let ([match?
           (let loop ([specs class-spec])
             (if (null? specs) #f
                 (let ([s (car specs)])
                   (or (and (char? s) (char=? c s))
                       (and (pair? s) (eq? (car s) 'range)
                            (char<=? (cadr s) c) (char<=? c (cddr s)))
                       (loop (cdr specs))))))])
      (if negated? (not match?) match?)))

  ;; Generate a predicate datum for a DFA transition label.
  (define (label->pred-datum label c-sym)
    (cond
      [(char? label)        `(char=? ,c-sym ,label)]
      [(eq? label 'dot)     `(not (char=? ,c-sym #\newline))]
      [(pair? label)
       (case (car label)
         [(class)
          (let ([specs (cadr label)]
               [neg?  (caddr label)])
            (let ([match-expr
                   (if (null? specs) #f
                       (let ([parts (map (lambda (s)
                                          (cond
                                            [(char? s) `(char=? ,c-sym ,s)]
                                            [(pair? s) `(and (char<=? ,(cadr s) ,c-sym)
                                                             (char<=? ,c-sym ,(cddr s)))]
                                            [else #f]))
                                        specs)])
                         (let ([valid (filter (lambda (x) x) parts)])
                           (if (null? valid) #f
                               (if (= 1 (length valid)) (car valid)
                                   `(or ,@valid))))))])
              (if neg?
                (if match-expr `(not ,match-expr) #t)
                (if match-expr match-expr #f))))]
         [else #f])]
      [else #f]))

  ;; Generate Scheme code for the DFA.
  ;; Returns a datum (lambda (str) ...) implementing the state machine.
  (define (dfa->scheme transitions accept-states num-states anchor-start? anchor-end?)
    (let* ([state-transitions
            (let ([by-state (make-eq-hashtable)])
              (for-each
                (lambda (t)
                  (let ([from  (car t)]
                        [label (cadr t)]
                        [to    (caddr t)])
                    (hashtable-set! by-state from
                      (cons (list label to)
                            (or (hashtable-ref by-state from #f) '())))))
                transitions)
              by-state)])

      (let ([state-fns
             (map (lambda (state-idx)
                    (let* ([trans-list (or (hashtable-ref state-transitions state-idx #f) '())]
                           [is-accept? (member state-idx accept-states)]
                           [c-sym 'c]
                           [i-sym 'i]
                           [n-sym 'n]
                           [trans-conds
                            (filter-map
                              (lambda (t)
                                (let* ([label (car t)]
                                       [to    (cadr t)]
                                       [pred  (label->pred-datum label c-sym)])
                                  (and pred
                                       `[,pred (,(string->symbol (string-append "state-" (number->string to))) (+ ,i-sym 1))])))
                              trans-list)]
                           [body
                            (if (null? trans-list)
                              (if is-accept?
                                `(if (= ,i-sym ,n-sym) #t #f)
                                `#f)
                              `(if (= ,i-sym ,n-sym)
                                 ,(if is-accept? #t #f)
                                 (let ([,c-sym (string-ref str ,i-sym)])
                                   (cond ,@trans-conds [else #f]))))])
                      `(define (,(string->symbol (string-append "state-" (number->string state-idx))) ,i-sym)
                         ,body)))
                  (iota num-states))])

        `(lambda (str)
           (let ([n (string-length str)])
             ,@state-fns
             (state-0 0))))))

  ;;; ========== Utilities ==========

  ;; filter-map helper
  (define (filter-map f lst)
    (let loop ([l lst] [acc '()])
      (if (null? l) (reverse acc)
          (let ([v (f (car l))])
            (loop (cdr l) (if v (cons v acc) acc))))))

) ;; end library
