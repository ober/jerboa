#!chezscheme
;;; (std parser deflexer) — Lexer definition macro
;;;
;;; Provides `deflexer` for defining lexers from ordered pattern/token-type
;;; clauses.  Patterns use a simple regex subset: literal chars, char classes
;;; [a-z], quantifiers *, +, ?, alternation |, and dot.
;;; Matching is first-match-wins over clauses.

(library (std parser deflexer)
  (export deflexer make-lexer lexer-next lex-string lex-port
          make-token token? token-type token-value token-line token-column)

  (import (chezscheme))

  ;; -----------------------------------------------------------------
  ;; Token record
  ;; -----------------------------------------------------------------

  (define-record-type token
    (fields (immutable type   token-type)
            (immutable value  token-value)
            (immutable line   token-line)
            (immutable column token-column))
    (protocol (lambda (new)
                (lambda (type value line column)
                  (new type value line column)))))

  ;; -----------------------------------------------------------------
  ;; Mini-regex compiler
  ;;
  ;; Compiles a regex string into a matcher procedure:
  ;;   (matcher str pos) -> end-pos or #f
  ;; where end-pos is one past the last matched character.
  ;; -----------------------------------------------------------------

  ;; Parse a regex string into an AST:
  ;;   (lit c)          — literal char
  ;;   (dot)            — any char
  ;;   (class pairs)    — char class, pairs = ((lo . hi) ...)
  ;;   (neg-class pairs)
  ;;   (seq a b ...)    — sequence
  ;;   (alt a b)        — alternation
  ;;   (star a)         — zero or more (greedy)
  ;;   (plus a)         — one or more
  ;;   (opt a)          — zero or one

  (define (parse-regex pat)
    (let ([len (string-length pat)])

      ;; Parse a char class body: [....], returns (pairs . end-idx)
      ;; idx points right after the opening [
      (define (parse-class idx negate?)
        (let loop ([i idx] [pairs '()])
          (when (>= i len)
            (error 'parse-regex "unterminated character class" pat))
          (let ([c (string-ref pat i)])
            (cond
              [(char=? c #\])
               (let ([cls (reverse pairs)])
                 (cons (if negate? `(neg-class ,cls) `(class ,cls))
                       (+ i 1)))]
              ;; range: a-z
              [(and (< (+ i 2) len)
                    (char=? (string-ref pat (+ i 1)) #\-)
                    (not (char=? (string-ref pat (+ i 2)) #\])))
               (loop (+ i 3)
                     (cons (cons c (string-ref pat (+ i 2))) pairs))]
              [else
               (loop (+ i 1)
                     (cons (cons c c) pairs))]))))

      ;; Parse atom: single element
      (define (parse-atom idx)
        (when (>= idx len)
          (error 'parse-regex "unexpected end of pattern" pat))
        (let ([c (string-ref pat idx)])
          (cond
            [(char=? c #\.)
             (cons '(dot) (+ idx 1))]
            [(char=? c #\\)
             (when (>= (+ idx 1) len)
               (error 'parse-regex "trailing backslash" pat))
             (let ([ec (string-ref pat (+ idx 1))])
               (cond
                 [(char=? ec #\d)
                  (cons '(class ((#\0 . #\9))) (+ idx 2))]
                 [(char=? ec #\w)
                  (cons '(class ((#\a . #\z) (#\A . #\Z) (#\0 . #\9) (#\_ . #\_)))
                        (+ idx 2))]
                 [(char=? ec #\s)
                  (cons '(class ((#\space . #\space) (#\tab . #\tab)
                                 (#\newline . #\newline) (#\return . #\return)))
                        (+ idx 2))]
                 [else
                  (cons `(lit ,ec) (+ idx 2))]))]
            [(char=? c #\[)
             (let* ([next (+ idx 1)]
                    [negate? (and (< next len)
                                 (char=? (string-ref pat next) #\^))]
                    [start (if negate? (+ next 1) next)])
               (parse-class start negate?))]
            [(char=? c #\()
             (let-values ([(ast end) (parse-alt (+ idx 1))])
               (when (or (>= end len)
                         (not (char=? (string-ref pat end) #\))))
                 (error 'parse-regex "unmatched paren" pat))
               (cons ast (+ end 1)))]
            [else
             (cons `(lit ,c) (+ idx 1))])))

      ;; Parse quantified: atom followed by optional *, +, ?
      (define (parse-quantified idx)
        (let* ([r (parse-atom idx)]
               [ast (car r)]
               [i (cdr r)])
          (if (< i len)
              (let ([c (string-ref pat i)])
                (cond
                  [(char=? c #\*) (cons `(star ,ast) (+ i 1))]
                  [(char=? c #\+) (cons `(plus ,ast) (+ i 1))]
                  [(char=? c #\?) (cons `(opt ,ast) (+ i 1))]
                  [else r]))
              r)))

      ;; Parse sequence: concatenation of quantified items
      (define (parse-seq idx)
        (let loop ([i idx] [items '()])
          (if (or (>= i len)
                  (char=? (string-ref pat i) #\|)
                  (char=? (string-ref pat i) #\)))
              (let ([seq (reverse items)])
                (values (if (= (length seq) 1) (car seq) `(seq ,@seq))
                        i))
              (let* ([r (parse-quantified i)]
                     [ast (car r)]
                     [ni (cdr r)])
                (loop ni (cons ast items))))))

      ;; Parse alternation: seq | seq | ...
      (define (parse-alt idx)
        (let-values ([(first fi) (parse-seq idx)])
          (if (and (< fi len) (char=? (string-ref pat fi) #\|))
              (let-values ([(rest ri) (parse-alt (+ fi 1))])
                (values `(alt ,first ,rest) ri))
              (values first fi))))

      (let-values ([(ast _) (parse-alt 0)])
        ast)))

  ;; Compile an AST into a matcher: (matcher str pos) -> end-pos or #f
  (define (compile-regex-ast ast)
    (case (car ast)
      [(lit)
       (let ([c (cadr ast)])
         (lambda (str pos)
           (and (< pos (string-length str))
                (char=? (string-ref str pos) c)
                (+ pos 1))))]
      [(dot)
       (lambda (str pos)
         (and (< pos (string-length str))
              (+ pos 1)))]
      [(class)
       (let ([pairs (cadr ast)])
         (lambda (str pos)
           (and (< pos (string-length str))
                (let ([c (string-ref str pos)])
                  (and (exists (lambda (p)
                                 (and (char>=? c (car p))
                                      (char<=? c (cdr p))))
                               pairs)
                       (+ pos 1))))))]
      [(neg-class)
       (let ([pairs (cadr ast)])
         (lambda (str pos)
           (and (< pos (string-length str))
                (let ([c (string-ref str pos)])
                  (and (not (exists (lambda (p)
                                      (and (char>=? c (car p))
                                           (char<=? c (cdr p))))
                                    pairs))
                       (+ pos 1))))))]
      [(seq)
       (let ([matchers (map compile-regex-ast (cdr ast))])
         (lambda (str pos)
           (let loop ([ms matchers] [p pos])
             (if (null? ms)
                 p
                 (let ([np ((car ms) str p)])
                   (and np (loop (cdr ms) np)))))))]
      [(alt)
       (let ([m1 (compile-regex-ast (cadr ast))]
             [m2 (compile-regex-ast (caddr ast))])
         (lambda (str pos)
           (or (m1 str pos)
               (m2 str pos))))]
      [(star)
       (let ([m (compile-regex-ast (cadr ast))])
         (lambda (str pos)
           ;; greedy: match as many as possible
           (let loop ([p pos])
             (let ([np (m str p)])
               (if np
                   (if (= np p) p  ;; zero-width match, stop
                       (loop np))
                   p)))))]  ;; zero matches is fine
      [(plus)
       (let ([m (compile-regex-ast (cadr ast))])
         (lambda (str pos)
           (let ([first (m str pos)])
             (and first
                  (let loop ([p first])
                    (let ([np (m str p)])
                      (if np
                          (if (= np p) p
                              (loop np))
                          p)))))))]
      [(opt)
       (let ([m (compile-regex-ast (cadr ast))])
         (lambda (str pos)
           (or (m str pos) pos)))]
      [else
       (error 'compile-regex-ast "unknown AST node" ast)]))

  ;; Compile a regex string to a matcher
  (define (compile-regex pat)
    (compile-regex-ast (parse-regex pat)))

  ;; -----------------------------------------------------------------
  ;; Lexer infrastructure
  ;; -----------------------------------------------------------------

  ;; A lexer is a vector: #(clauses)
  ;; where clauses is a list of (matcher token-type transform)
  ;; matcher: (str pos) -> end-pos or #f
  ;; transform: #f (use matched string) or (lambda (matched-str) -> value)

  (define (make-lexer clauses)
    ;; clauses: list of (regex-string token-type-symbol transform-or-#f)
    (let ([compiled
           (map (lambda (c)
                  (list (compile-regex (car c))
                        (cadr c)
                        (if (null? (cddr c)) #f (caddr c))))
                clauses)])
      (vector compiled)))

  ;; Try to match one token starting at pos in str.
  ;; Returns (token . new-pos) or #f if no clause matches.
  (define (try-match lexer str pos line col)
    (let ([clauses (vector-ref lexer 0)])
      (let loop ([cs clauses])
        (if (null? cs)
            #f
            (let* ([clause (car cs)]
                   [matcher (car clause)]
                   [ttype (cadr clause)]
                   [transform (caddr clause)]
                   [end (matcher str pos)])
              (if (and end (> end pos))  ;; must consume at least 1 char
                  (let* ([matched (substring str pos end)]
                         [val (if transform (transform matched) matched)]
                         [tok (make-token ttype val line col)])
                    (cons tok end))
                  (loop (cdr cs))))))))

  ;; Compute new line/col after consuming text from pos to end
  (define (advance-position str pos end line col)
    (let loop ([i pos] [l line] [c col])
      (if (>= i end)
          (values l c)
          (if (char=? (string-ref str i) #\newline)
              (loop (+ i 1) (+ l 1) 1)
              (loop (+ i 1) l (+ c 1))))))

  ;; Get the next token from a lexer state.
  ;; State is (str . pos . line . col).
  ;; Returns (values token new-state) or (values #f state) at end.
  (define (lexer-next lexer str pos line col)
    (if (>= pos (string-length str))
        (values #f pos line col)
        (let ([result (try-match lexer str pos line col)])
          (if result
              (let ([tok (car result)]
                    [end (cdr result)])
                (let-values ([(nl nc) (advance-position str pos end line col)])
                  (values tok end nl nc)))
              (error 'lexer-next
                     (format "unexpected character ~a at line ~a column ~a"
                             (string-ref str pos) line col)
                     str pos)))))

  ;; Lex an entire string, returning a list of tokens.
  (define (lex-string lexer str)
    (let loop ([pos 0] [line 1] [col 1] [tokens '()])
      (if (>= pos (string-length str))
          (reverse tokens)
          (let-values ([(tok npos nline ncol)
                        (lexer-next lexer str pos line col)])
            (if tok
                (loop npos nline ncol (cons tok tokens))
                (reverse tokens))))))

  ;; Lex from a port, returning a thunk (generator) that yields tokens.
  ;; Each call to the thunk returns the next token, or #f at EOF.
  (define (lex-port lexer port)
    (let ([content (get-string-all port)])
      (if (eof-object? content)
          (lambda () #f)
          (let ([pos 0] [line 1] [col 1]
                [str content])
            (lambda ()
              (if (>= pos (string-length str))
                  #f
                  (let-values ([(tok npos nline ncol)
                                (lexer-next lexer str pos line col)])
                    (set! pos npos)
                    (set! line nline)
                    (set! col ncol)
                    tok)))))))

  ;; -----------------------------------------------------------------
  ;; deflexer macro
  ;;
  ;; (deflexer name
  ;;   (regex-string token-type)
  ;;   (regex-string token-type transform-proc)
  ;;   ...)
  ;;
  ;; Defines `name` as a lexer.
  ;; -----------------------------------------------------------------

  (define-syntax deflexer
    (syntax-rules ()
      [(_ name clause ...)
       (define name
         (make-lexer (list (deflexer-clause clause) ...)))]))

  (define-syntax deflexer-clause
    (syntax-rules ()
      [(_ (regex-str ttype))
       (list regex-str 'ttype #f)]
      [(_ (regex-str ttype transform))
       (list regex-str 'ttype transform)]))

) ;; end library
