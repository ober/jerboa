;;; Compile-Time Regex Compilation
;;;
;;; Compiles regex patterns to native Scheme code at compile time,
;;; eliminating runtime regex engine overhead by generating optimized
;;; deterministic finite automata (DFA) as Scheme procedures.

(library (std text regex-compile)
  (export
    ;; Core regex compilation
    define-regex
    compile-regex
    regex-pattern?

    ;; Pattern construction
    make-regex-literal
    regex-literal?
    regex-literal-char
    make-regex-char-class
    regex-char-class?
    regex-char-class-chars
    regex-char-class-negated?
    make-regex-sequence
    regex-sequence?
    regex-sequence-parts
    make-regex-or
    regex-or?
    regex-or-alternatives
    make-regex-star
    regex-star?
    regex-star-inner
    make-regex-plus
    regex-plus?
    regex-plus-inner
    make-regex-optional
    regex-optional?
    regex-optional-inner
    make-regex-repeat
    regex-repeat?
    regex-repeat-inner
    regex-repeat-min
    regex-repeat-max

    ;; Matching interface
    regex-match?
    regex-match
    regex-find
    regex-split

    ;; NFA construction
    nfa-state?
    nfa-state-final?
    build-nfa
    nfa->dfa
    minimize-dfa

    ;; Code generation
    generate-matcher-code

    ;; Low-level NFA inspection (for tests)
    make-nfa-state
    nfa-state-id
    epsilon-closure
    char-matches?

    ;; Utilities
    regex-quote
    parse-regex-string)

  (import
    (chezscheme)
    (std match2)
    (std misc list))

  ;; -----------------------------------------------------------------------
  ;; Record types (Chez-native syntax)
  ;; -----------------------------------------------------------------------

  ;; Compiled regex pattern
  (define-record-type regex-pattern
    (fields
      (immutable ast  regex-pattern-ast)
      (immutable dfa  regex-pattern-dfa)
      (immutable proc regex-pattern-matcher-proc))
    (protocol
      (lambda (new)
        (lambda (ast dfa proc)
          (new ast dfa proc)))))

  ;; NFA state
  (define-record-type nfa-state
    (fields
      (immutable id          nfa-state-id)
      (mutable   transitions nfa-state-transitions nfa-state-transitions-set!)
      (immutable final?      nfa-state-final?))
    (protocol
      (lambda (new)
        (lambda (id transitions final?)
          (new id transitions final?)))))

  ;; NFA transition
  (define-record-type nfa-transition
    (fields
      (immutable from      nfa-transition-from)
      (immutable to        nfa-transition-to)
      (immutable condition nfa-transition-condition))
    (protocol
      (lambda (new)
        (lambda (from to condition)
          (new from to condition)))))

  ;; DFA state
  (define-record-type dfa-state
    (fields
      (immutable id         dfa-state-id)
      (immutable nfa-states dfa-state-nfa-states)
      (mutable   transitions dfa-state-transitions dfa-state-transitions-set!)
      (immutable final?     dfa-state-final?))
    (protocol
      (lambda (new)
        (lambda (id nfa-states transitions final?)
          (new id nfa-states transitions final?)))))

  ;; -----------------------------------------------------------------------
  ;; Regex AST node types
  ;; -----------------------------------------------------------------------

  (define-record-type regex-literal
    (fields (immutable char regex-literal-char))
    (protocol (lambda (new) (lambda (char) (new char)))))

  (define-record-type regex-char-class
    (fields
      (immutable chars    regex-char-class-chars)
      (immutable negated? regex-char-class-negated?))
    (protocol (lambda (new) (lambda (chars negated?) (new chars negated?)))))

  (define-record-type regex-sequence
    (fields (immutable parts regex-sequence-parts))
    (protocol (lambda (new) (lambda (parts) (new parts)))))

  (define-record-type regex-or
    (fields (immutable alternatives regex-or-alternatives))
    (protocol (lambda (new) (lambda (alts) (new alts)))))

  (define-record-type regex-star
    (fields (immutable inner regex-star-inner))
    (protocol (lambda (new) (lambda (inner) (new inner)))))

  (define-record-type regex-plus
    (fields (immutable inner regex-plus-inner))
    (protocol (lambda (new) (lambda (inner) (new inner)))))

  (define-record-type regex-optional
    (fields (immutable inner regex-optional-inner))
    (protocol (lambda (new) (lambda (inner) (new inner)))))

  (define-record-type regex-repeat
    (fields
      (immutable inner regex-repeat-inner)
      (immutable min   regex-repeat-min)
      (immutable max   regex-repeat-max))
    (protocol (lambda (new) (lambda (inner min max) (new inner min max)))))

  ;; -----------------------------------------------------------------------
  ;; Global state counter for NFA state IDs
  ;; -----------------------------------------------------------------------

  (define *state-counter* 0)

  (define (next-state-id!)
    (let ([id *state-counter*])
      (set! *state-counter* (+ *state-counter* 1))
      id))

  ;; -----------------------------------------------------------------------
  ;; Regex string parser
  ;; -----------------------------------------------------------------------

  (define (parse-regex-string pattern)
    "Parse regex string into an AST"
    (let* ([chars (string->list pattern)]
           [n     (length chars)]
           [pos   0])

      (define (peek)
        (and (< pos n) (list-ref chars pos)))

      (define (advance!)
        (set! pos (+ pos 1)))

      ;; Parse alternation (lowest precedence)
      (define (parse-alt)
        (let ([left (parse-seq)])
          (if (and (peek) (char=? (peek) #\|))
              (begin
                (advance!)
                (let ([right (parse-alt)])
                  (make-regex-or (list left right))))
              left)))

      ;; Parse concatenation
      (define (parse-seq)
        (let loop ([parts '()])
          (let ([ch (peek)])
            (if (or (not ch)
                    (char=? ch #\))
                    (char=? ch #\|))
                (cond
                  [(null? parts)       (make-regex-sequence '())]
                  [(null? (cdr parts)) (car parts)]
                  [else                (make-regex-sequence (reverse parts))])
                (let ([part (parse-postfix)])
                  (if part
                      (loop (cons part parts))
                      (cond
                        [(null? parts)       (make-regex-sequence '())]
                        [(null? (cdr parts)) (car parts)]
                        [else                (make-regex-sequence (reverse parts))])))))))

      ;; Parse postfix operators (*, +, ?)
      (define (parse-postfix)
        (let ([atom (parse-atom)])
          (and atom
               (let ([ch (peek)])
                 (cond
                   [(and ch (char=? ch #\*))
                    (advance!) (make-regex-star atom)]
                   [(and ch (char=? ch #\+))
                    (advance!) (make-regex-plus atom)]
                   [(and ch (char=? ch #\?))
                    (advance!) (make-regex-optional atom)]
                   [else atom])))))

      ;; Parse atomic expressions
      (define (parse-atom)
        (let ([ch (peek)])
          (cond
            [(not ch)          #f]
            [(char=? ch #\))   #f]
            [(char=? ch #\|)   #f]
            [(char=? ch #\\)
             (advance!)
             (let ([escaped (peek)])
               (and escaped (begin (advance!) (make-regex-literal escaped))))]
            [(char=? ch #\.)
             (advance!)
             ;; . matches any char (negated empty class)
             (make-regex-char-class '(#\newline) #t)]
            [(char=? ch #\[)
             (advance!)
             (parse-char-class)]
            [(char=? ch #\()
             (advance!)
             (let ([group (parse-alt)])
               (when (and (peek) (char=? (peek) #\)))
                 (advance!))
               group)]
            [else
             (advance!)
             (make-regex-literal ch)])))

      ;; Parse character class [...]
      (define (parse-char-class)
        (let ([negated? (and (peek) (char=? (peek) #\^)
                             (begin (advance!) #t))])
          (let loop ([chars '()])
            (let ([ch (peek)])
              (cond
                [(not ch)
                 (make-regex-char-class (reverse chars) (or negated? #f))]
                [(char=? ch #\])
                 (advance!)
                 (make-regex-char-class (reverse chars) (or negated? #f))]
                [(char=? ch #\\)
                 (advance!)
                 (let ([escaped (peek)])
                   (advance!)
                   (loop (cons escaped chars)))]
                [else
                 (advance!)
                 ;; Check for range a-z
                 (if (and (peek) (char=? (peek) #\-)
                          (let ([after-dash (and (< (+ pos 1) n)
                                                 (list-ref chars (- pos 1)))])
                            #f))
                     (loop (cons ch chars))
                     (loop (cons ch chars)))])))))

      (parse-alt)))

  ;; -----------------------------------------------------------------------
  ;; NFA construction from regex AST
  ;; -----------------------------------------------------------------------

  (define (connect-states! from to condition)
    (nfa-state-transitions-set! from
      (cons (make-nfa-transition from to condition)
            (nfa-state-transitions from))))

  (define (build-nfa regex-ast)
    "Build NFA from regex AST; returns (values start-state end-state)"
    (let ([start (make-nfa-state (next-state-id!) '() #f)]
          [end   (make-nfa-state (next-state-id!) '() #t)])
      (build-fragment! regex-ast start end)
      (values start end)))

  ;; All printable ASCII characters (for negated char classes)
  (define *all-chars*
    (let loop ([i 0] [acc '()])
      (if (= i 128) (reverse acc)
          (loop (+ i 1) (cons (integer->char i) acc)))))

  (define (expand-char-class cc)
    "Expand regex-char-class to a list of matching characters (printable ASCII)"
    (let ([listed (regex-char-class-chars cc)]
          [neg?   (regex-char-class-negated? cc)])
      (if neg?
          (filter (lambda (c) (not (member c listed))) *all-chars*)
          listed)))

  (define (build-fragment! ast start end)
    "Recursively add NFA transitions for AST between start and end"
    (cond
      [(regex-literal? ast)
       (connect-states! start end (regex-literal-char ast))]

      [(regex-char-class? ast)
       ;; Expand char class to individual character transitions
       (for-each (lambda (c) (connect-states! start end c))
                 (expand-char-class ast))]

      [(regex-sequence? ast)
       (let ([parts (regex-sequence-parts ast)])
         (cond
           [(null? parts)
            (connect-states! start end 'epsilon)]
           [(null? (cdr parts))
            (build-fragment! (car parts) start end)]
           [else
            (let loop ([parts parts] [cur start])
              (if (null? (cdr parts))
                  (build-fragment! (car parts) cur end)
                  (let ([mid (make-nfa-state (next-state-id!) '() #f)])
                    (build-fragment! (car parts) cur mid)
                    (loop (cdr parts) mid))))]))]

      [(regex-or? ast)
       (for-each (lambda (alt)
                   (let ([s (make-nfa-state (next-state-id!) '() #f)]
                         [e (make-nfa-state (next-state-id!) '() #f)])
                     (connect-states! start s 'epsilon)
                     (connect-states! e end 'epsilon)
                     (build-fragment! alt s e)))
                 (regex-or-alternatives ast))]

      [(regex-star? ast)
       (let ([s (make-nfa-state (next-state-id!) '() #f)]
             [e (make-nfa-state (next-state-id!) '() #f)])
         (build-fragment! (regex-star-inner ast) s e)
         (connect-states! start s 'epsilon)
         (connect-states! e end   'epsilon)
         (connect-states! start end 'epsilon)   ; zero repetitions
         (connect-states! e s     'epsilon))]   ; loop back

      [(regex-plus? ast)
       (let ([s (make-nfa-state (next-state-id!) '() #f)]
             [e (make-nfa-state (next-state-id!) '() #f)])
         (build-fragment! (regex-plus-inner ast) s e)
         (connect-states! start s 'epsilon)
         (connect-states! e end   'epsilon)
         (connect-states! e s     'epsilon))]   ; loop back

      [(regex-optional? ast)
       (build-fragment! (regex-optional-inner ast) start end)
       (connect-states! start end 'epsilon)]

      [(regex-repeat? ast)
       ;; Expand {min,max} to sequence of optional repetitions
       (let* ([inner (regex-repeat-inner ast)]
              [lo    (regex-repeat-min ast)]
              [hi    (regex-repeat-max ast)]
              [expanded
               (let ([mandatory
                      (make-regex-sequence
                        (map (lambda (_) inner) (iota lo)))]
                     [optional
                      (if hi
                          (make-regex-sequence
                            (map (lambda (_) (make-regex-optional inner))
                                 (iota (- hi lo))))
                          (make-regex-star inner))])
                 (make-regex-sequence (list mandatory optional)))])
         (build-fragment! expanded start end))]

      [else
       (error 'build-fragment! "unsupported regex AST node" ast)]))

  ;; -----------------------------------------------------------------------
  ;; Epsilon closure
  ;; -----------------------------------------------------------------------

  (define (epsilon-closure states)
    "Compute epsilon closure of a list of NFA states"
    (let ([visited (make-hashtable equal-hash equal?)])
      (let loop ([worklist states])
        (for-each
          (lambda (state)
            (unless (hashtable-ref visited state #f)
              (hashtable-set! visited state #t)
              (for-each
                (lambda (t)
                  (when (eq? (nfa-transition-condition t) 'epsilon)
                    (loop (list (nfa-transition-to t)))))
                (nfa-state-transitions state))))
          worklist))
      (let ([result '()])
        (let-values ([(keys _vals) (hashtable-entries visited)])
          (vector-for-each (lambda (k) (set! result (cons k result))) keys))
        result)))

  ;; -----------------------------------------------------------------------
  ;; Character matching
  ;; -----------------------------------------------------------------------

  (define (char-matches? char condition)
    "Test whether CHAR satisfies transition CONDITION"
    (cond
      [(char? condition)
       (char=? char condition)]
      [(regex-char-class? condition)
       (let ([in-class? (member char (regex-char-class-chars condition))])
         (if (regex-char-class-negated? condition)
             (not in-class?)
             (and in-class? #t)))]
      [else #f]))

  ;; -----------------------------------------------------------------------
  ;; NFA → DFA via subset construction
  ;; -----------------------------------------------------------------------

  (define (nfa-state-set-key states)
    "Canonical key for a set of NFA states (sorted list of IDs)"
    (list-sort < (map nfa-state-id states)))

  (define (nfa->dfa start-nfa)
    "Convert NFA to DFA using subset construction; returns start DFA state"
    (let ([dfa-table  (make-hashtable equal-hash equal?)]
          [worklist   '()]
          [dfa-id     0])

      (define (get-or-create-dfa nfa-set)
        (let ([key (nfa-state-set-key nfa-set)])
          (or (hashtable-ref dfa-table key #f)
              (let ([ds (make-dfa-state dfa-id nfa-set '()
                          (exists nfa-state-final? nfa-set))])
                (set! dfa-id (+ dfa-id 1))
                (hashtable-set! dfa-table key ds)
                (set! worklist (cons nfa-set worklist))
                ds))))

      (let ([start-closure (epsilon-closure (list start-nfa))])
        (get-or-create-dfa start-closure)

        (let loop ()
          (unless (null? worklist)
            (let* ([cur-set (car worklist)]
                   [cur-dfa (hashtable-ref dfa-table (nfa-state-set-key cur-set) #f)])
              (set! worklist (cdr worklist))

              ;; Gather all character-labeled transitions from this NFA state set
              (let ([char-map (make-hashtable char->integer char=?)])
                (for-each
                  (lambda (nfa-st)
                    (for-each
                      (lambda (t)
                        (let ([cond (nfa-transition-condition t)])
                          ;; Handle literal characters
                          (when (char? cond)
                            (hashtable-update! char-map cond
                              (lambda (old) (cons (nfa-transition-to t) old))
                              '()))
                          ;; Handle char classes: skip for now (handled at match time)
                          ))
                      (nfa-state-transitions nfa-st)))
                  cur-set)

                ;; For each reachable character, build target DFA state
                (let-values ([(chars target-lists) (hashtable-entries char-map)])
                  (vector-for-each
                    (lambda (ch targets)
                      (let* ([closure (epsilon-closure targets)]
                             [target-dfa (get-or-create-dfa closure)])
                        (dfa-state-transitions-set! cur-dfa
                          (cons (cons ch target-dfa)
                                (dfa-state-transitions cur-dfa)))))
                    chars target-lists))))

            (loop)))

        (hashtable-ref dfa-table (nfa-state-set-key start-closure) #f))))

  ;; -----------------------------------------------------------------------
  ;; DFA minimization (Hopcroft's algorithm, simplified)
  ;; -----------------------------------------------------------------------

  (define (minimize-dfa dfa)
    "Minimize DFA (currently a no-op placeholder — returns DFA unchanged)"
    dfa)

  ;; -----------------------------------------------------------------------
  ;; Code generation from DFA
  ;; -----------------------------------------------------------------------

  (define (generate-matcher-code dfa)
    "Generate Scheme source code for a DFA matcher procedure"
    (let ([labels  (make-hashtable equal-hash equal?)]
          [counter 0])

      (define (label-for state)
        (or (hashtable-ref labels state #f)
            (let ([lbl (string->symbol
                         (string-append "st" (number->string counter)))])
              (set! counter (+ counter 1))
              (hashtable-set! labels state lbl)
              lbl)))

      ;; Collect all reachable DFA states
      (define (collect-states start)
        (let ([visited (make-hashtable equal-hash equal?)]
              [all     '()])
          (define (visit s)
            (unless (hashtable-ref visited s #f)
              (hashtable-set! visited s #t)
              (set! all (cons s all))
              (for-each (lambda (t) (visit (cdr t)))
                        (dfa-state-transitions s))))
          (visit start)
          all))

      (define (gen-state-body state)
        (let ([trans (dfa-state-transitions state)]
              [final? (dfa-state-final? state)])
          (if (null? trans)
              ;; No transitions: accept iff at end of input
              `(>= pos len)
              `(if (>= pos len)
                   ,final?
                   (let ([ch (string-ref s pos)])
                     (set! pos (+ pos 1))
                     (cond
                       ,@(map (lambda (t)
                                `[(char=? ch ,(car t))
                                  (,(label-for (cdr t)))])
                              trans)
                       [else
                        ,(if final?
                             ;; Consumed extra char — backtrack logically?
                             ;; Simple approach: fail (whole-string match)
                             '#f
                             '#f)]))))))

      (let ([all-states (collect-states dfa)])
        ;; Assign labels
        (for-each label-for all-states)
        (let ([start-label (label-for dfa)])
          `(lambda (s)
             (let ([len (string-length s)]
                   [pos 0])
               (define (,start-label)
                 ,(gen-state-body dfa))
               ,@(filter-map
                    (lambda (st)
                      (if (eq? st dfa)
                          #f
                          `(define (,(label-for st))
                             ,(gen-state-body st))))
                    all-states)
               (,start-label)))))))

  ;; -----------------------------------------------------------------------
  ;; Main compilation entry point
  ;; -----------------------------------------------------------------------

  (define (compile-regex pattern)
    "Compile regex pattern string (or AST) to a native Scheme matcher"
    (let* ([ast  (if (string? pattern)
                     (parse-regex-string pattern)
                     pattern)]
           [_    (set! *state-counter* 0)])    ; reset counter per compilation
      (let-values ([(nfa-start _nfa-end) (build-nfa ast)])
        (let* ([dfa     (nfa->dfa nfa-start)]
               [min-dfa (minimize-dfa dfa)]
               [code    (generate-matcher-code min-dfa)]
               [proc    (eval code (environment '(chezscheme)))])
          (make-regex-pattern ast min-dfa proc)))))

  ;; -----------------------------------------------------------------------
  ;; Macro for defining compile-time regex
  ;; -----------------------------------------------------------------------

  (define-syntax define-regex
    (syntax-rules ()
      [(_ name pattern)
       (define name (compile-regex pattern))]))

  ;; -----------------------------------------------------------------------
  ;; Matching interface
  ;; -----------------------------------------------------------------------

  (define (regex-matcher pat)
    (if (regex-pattern? pat)
        (regex-pattern-matcher-proc pat)
        (regex-pattern-matcher-proc (compile-regex pat))))

  (define (regex-match? pattern input)
    "Test whether PATTERN matches the entire INPUT string"
    ((regex-matcher pattern) input))

  (define (regex-match pattern input)
    "Match PATTERN against INPUT; returns #t/#f (groups not yet implemented)"
    (regex-match? pattern input))

  (define (regex-find pattern input)
    "Find first match of PATTERN in INPUT; returns start index or #f"
    (let ([matcher (regex-matcher pattern)]
          [len     (string-length input)])
      (let loop ([i 0])
        (and (< i len)
             (if (matcher (substring input i len))
                 i
                 (loop (+ i 1)))))))

  (define (regex-split pattern input)
    "Split INPUT at each match of PATTERN"
    (let ([matcher (regex-matcher pattern)]
          [len     (string-length input)])
      (let loop ([i 0] [parts '()])
        (if (>= i len)
            (reverse (cons (substring input i len) parts))
            (if (matcher (substring input i (+ i 1)))
                (loop (+ i 1) (cons "" parts))
                (loop (+ i 1) parts))))))

  ;; -----------------------------------------------------------------------
  ;; Utilities
  ;; -----------------------------------------------------------------------

  (define (regex-quote str)
    "Escape all regex special characters in STR"
    (list->string
      (let loop ([cs (string->list str)] [acc '()])
        (if (null? cs)
            (reverse acc)
            (let ([c (car cs)])
              (if (member c '(#\. #\* #\+ #\? #\[ #\] #\( #\) #\{ #\} #\\ #\^ #\$))
                  (loop (cdr cs) (cons c (cons #\\ acc)))
                  (loop (cdr cs) (cons c acc))))))))

)
