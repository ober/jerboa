#!chezscheme
;;; :std/srfi/159 -- Combinator Formatting (SRFI-159)
;;; Composable formatting system where formatters are procedures
;;; that take a mutable output state and produce output.

(library (std srfi srfi-159)
  (export
    show displayed written written-shared
    numeric numeric/comma numeric/si
    nl fl space-to tab-to nothing
    each each-in-list
    joined joined/prefix joined/suffix joined/last joined/dot joined/range
    padded padded/right padded/both
    trimmed trimmed/right trimmed/both trimmed/lazy
    fitted fitted/right fitted/both
    with forked call-with-output)

  (import (chezscheme))

  ;; ---- Formatting state record ----
  ;; Mutable record tracking output port, position, and formatting parameters.

  (define-record-type fmt-state
    (fields
      (mutable port)
      (mutable col)
      (mutable row)
      (mutable width)
      (mutable pad-char)
      (mutable radix)
      (mutable precision)
      (mutable comma-sep)
      (mutable comma-width)
      (mutable decimal-sep))
    (protocol
      (lambda (new)
        (lambda (port)
          (new port 0 0 78 #\space 10 #f #\, 3 #\.)))))

  ;; ---- State helpers ----

  (define (fmt-output st str)
    ;; Write a string to the state's port and update column/row tracking.
    (let ([p (fmt-state-port st)])
      (let loop ([i 0] [len (string-length str)])
        (when (< i len)
          (let ([c (string-ref str i)])
            (cond
              [(char=? c #\newline)
               (put-char p c)
               (fmt-state-col-set! st 0)
               (fmt-state-row-set! st (+ 1 (fmt-state-row st)))]
              [else
               (put-char p c)
               (fmt-state-col-set! st (+ 1 (fmt-state-col st)))]))
          (loop (+ i 1) len)))))

  ;; ---- Core: show ----

  (define (run-formatter st fmt)
    (cond
      [(procedure? fmt) (fmt st)]
      [(string? fmt) (fmt-output st fmt)]
      [(char? fmt) (fmt-output st (string fmt))]
      [else (fmt-output st (format "~a" fmt))]))

  (define show
    (case-lambda
      [(port-or-bool . formatters)
       (cond
         [(eq? port-or-bool #f)
          ;; Return output as string
          (let-values ([(sp get) (open-string-output-port)])
            (let ([st (make-fmt-state sp)])
              (for-each (lambda (f) (run-formatter st f)) formatters)
              (get)))]
         [(eq? port-or-bool #t)
          ;; Write to current-output-port
          (let ([st (make-fmt-state (current-output-port))])
            (for-each (lambda (f) (run-formatter st f)) formatters)
            (void))]
         [(output-port? port-or-bool)
          (let ([st (make-fmt-state port-or-bool)])
            (for-each (lambda (f) (run-formatter st f)) formatters)
            (void))]
         [else
          (error 'show "expected port, #t, or #f" port-or-bool)])]))

  ;; ---- Basic formatters ----

  (define (displayed obj)
    ;; Format obj using display semantics.
    (lambda (st)
      (fmt-output st (format "~a" obj))))

  (define (written obj)
    ;; Format obj using write semantics.
    (lambda (st)
      (fmt-output st (format "~s" obj))))

  (define (written-shared obj)
    ;; Format obj using write with shared structure notation.
    (lambda (st)
      (fmt-output st (let-values ([(sp get) (open-string-output-port)])
                       (parameterize ([print-graph #t])
                         (write obj sp))
                       (get)))))

  ;; ---- Newline, flush, nothing ----

  (define (nl st)
    (fmt-output st (string #\newline)))

  (define (fl st)
    (flush-output-port (fmt-state-port st)))

  (define (nothing st)
    (void))

  ;; ---- Column/tab ----

  (define (space-to col-target)
    ;; Pad with spaces until reaching column col-target.
    (lambda (st)
      (let ([cur (fmt-state-col st)]
            [pc (fmt-state-pad-char st)])
        (when (< cur col-target)
          (fmt-output st (make-string (- col-target cur) pc))))))

  (define (tab-to col-target)
    ;; Tab to column position (modular).
    (lambda (st)
      (let* ([cur (fmt-state-col st)]
             [target (if (<= col-target cur)
                         ;; next tab stop
                         (+ cur (- col-target (mod cur col-target)))
                         col-target)])
        (when (> target cur)
          (fmt-output st (make-string (- target cur) #\space))))))

  ;; ---- Sequencing ----

  (define (each . formatters)
    ;; Run formatters in sequence.
    (lambda (st)
      (for-each (lambda (f) (run-formatter st f)) formatters)))

  (define (each-in-list lst)
    ;; Format each element of lst using displayed.
    (lambda (st)
      (for-each (lambda (x) (run-formatter st (displayed x))) lst)))

  ;; ---- Joining ----

  (define joined
    (case-lambda
      [(formatter lst)
       (joined formatter lst "")]
      [(formatter lst sep)
       (lambda (st)
         (let loop ([xs lst] [first? #t])
           (unless (null? xs)
             (unless first?
               (run-formatter st sep))
             (run-formatter st (formatter (car xs)))
             (loop (cdr xs) #f))))]))

  (define joined/prefix
    (case-lambda
      [(formatter lst)
       (joined/prefix formatter lst "")]
      [(formatter lst sep)
       (lambda (st)
         (for-each
           (lambda (x)
             (run-formatter st sep)
             (run-formatter st (formatter x)))
           lst))]))

  (define joined/suffix
    (case-lambda
      [(formatter lst)
       (joined/suffix formatter lst "")]
      [(formatter lst sep)
       (lambda (st)
         (for-each
           (lambda (x)
             (run-formatter st (formatter x))
             (run-formatter st sep))
           lst))]))

  (define joined/last
    (case-lambda
      [(formatter last-formatter lst)
       (joined/last formatter last-formatter lst "")]
      [(formatter last-formatter lst sep)
       (lambda (st)
         (let loop ([xs lst] [first? #t])
           (unless (null? xs)
             (unless first?
               (run-formatter st sep))
             (if (null? (cdr xs))
                 (run-formatter st (last-formatter (car xs)))
                 (run-formatter st (formatter (car xs))))
             (loop (cdr xs) #f))))]))

  (define joined/dot
    (case-lambda
      [(formatter lst)
       (joined/dot formatter lst "")]
      [(formatter lst sep)
       (lambda (st)
         (let loop ([xs lst] [first? #t])
           (cond
             [(null? xs) (void)]
             [(pair? xs)
              (unless first?
                (run-formatter st sep))
              (run-formatter st (formatter (car xs)))
              (loop (cdr xs) #f)]
             [else
              ;; Dotted tail
              (run-formatter st " . ")
              (run-formatter st (formatter xs))])))]))

  (define (joined/range formatter start end . maybe-sep)
    (let ([sep (if (null? maybe-sep) "" (car maybe-sep))])
      (lambda (st)
        (let loop ([i start] [first? #t])
          (when (< i end)
            (unless first?
              (run-formatter st sep))
            (run-formatter st (formatter i))
            (loop (+ i 1) #f))))))

  ;; ---- Numeric formatting ----

  (define (integer->string/radix n radix)
    ;; Convert integer to string in given radix.
    (if (zero? n)
        "0"
        (let* ([neg? (negative? n)]
               [n (abs n)])
          (let loop ([n n] [acc '()])
            (if (zero? n)
                (let ([s (list->string acc)])
                  (if neg? (string-append "-" s) s))
                (let* ([d (mod n radix)]
                       [c (if (< d 10)
                              (integer->char (+ d (char->integer #\0)))
                              (integer->char (+ (- d 10) (char->integer #\a))))])
                  (loop (div n radix) (cons c acc))))))))

  (define (format-float x prec decimal-sep)
    ;; Format a flonum with given precision.
    (let* ([prec (or prec 6)]
           [neg? (negative? x)]
           [x (abs (inexact x))]
           [factor (expt 10 prec)]
           [rounded (inexact->exact (round (* x factor)))]
           [int-part (div rounded factor)]
           [frac-part (mod rounded factor)]
           [int-str (number->string int-part)]
           [frac-str (let ([s (number->string frac-part)])
                       (if (< (string-length s) prec)
                           (string-append (make-string (- prec (string-length s)) #\0) s)
                           s))])
      (string-append
        (if neg? "-" "")
        int-str
        (string decimal-sep)
        frac-str)))

  (define numeric
    (case-lambda
      [(n)
       (numeric n #f)]
      [(n radix-arg)
       (numeric n radix-arg #f)]
      [(n radix-arg prec)
       (lambda (st)
         (let ([r (or radix-arg (fmt-state-radix st))]
               [p (or prec (fmt-state-precision st))]
               [dsep (fmt-state-decimal-sep st)])
           (cond
             [(and (or (flonum? n) (and p (not (zero? p)))) (= r 10))
              (fmt-output st (format-float (if (flonum? n) n (inexact n)) p dsep))]
             [(exact? n)
              (fmt-output st (integer->string/radix
                               (if (integer? n) n (inexact->exact (round n)))
                               r))]
             [else
              (fmt-output st (format-float n p dsep))])))]))

  (define (insert-commas str comma-char width)
    ;; Insert comma separators into an integer string.
    (let* ([neg? (and (> (string-length str) 0)
                      (char=? (string-ref str 0) #\-))]
           [digits (if neg? (substring str 1 (string-length str)) str)]
           [len (string-length digits)])
      (if (<= len width)
          str
          (let loop ([i (- len 1)] [count 0] [acc '()])
            (if (< i 0)
                (let ([result (list->string acc)])
                  (if neg? (string-append "-" result) result))
                (begin
                  (if (and (> count 0) (zero? (mod count width)))
                      (loop (- i 1) (+ count 1) (cons (string-ref digits i) (cons comma-char acc)))
                      (loop (- i 1) (+ count 1) (cons (string-ref digits i) acc)))))))))

  (define numeric/comma
    (case-lambda
      [(n)
       (numeric/comma n #f)]
      [(n radix-arg)
       (numeric/comma n radix-arg #f)]
      [(n radix-arg prec)
       (lambda (st)
         (let ([r (or radix-arg (fmt-state-radix st))]
               [cs (fmt-state-comma-sep st)]
               [cw (fmt-state-comma-width st)]
               [dsep (fmt-state-decimal-sep st)]
               [p (or prec (fmt-state-precision st))])
           (cond
             [(and (integer? n) (exact? n))
              (fmt-output st (insert-commas (integer->string/radix n r) cs cw))]
             [else
              ;; Float: format, then comma the integer part
              (let* ([s (format-float n p dsep)]
                     [dot-pos (let loop ([i 0])
                                (cond
                                  [(>= i (string-length s)) #f]
                                  [(char=? (string-ref s i) dsep) i]
                                  [else (loop (+ i 1))]))]
                     [int-part (if dot-pos (substring s 0 dot-pos) s)]
                     [frac-part (if dot-pos (substring s dot-pos (string-length s)) "")])
                (fmt-output st (string-append (insert-commas int-part cs cw) frac-part)))])))]))

  (define si-prefixes
    ;; (exponent . prefix-char) for SI
    '((24 . "Y") (21 . "Z") (18 . "E") (15 . "P") (12 . "T")
      (9 . "G") (6 . "M") (3 . "k") (0 . "") (-3 . "m") (-6 . "u")
      (-9 . "n") (-12 . "p") (-15 . "f") (-18 . "a") (-21 . "z") (-24 . "y")))

  (define numeric/si
    (case-lambda
      [(n)
       (numeric/si n 1)]
      [(n base)
       (lambda (st)
         (if (zero? n)
             (fmt-output st "0")
             (let* ([x (inexact (abs n))]
                    [neg? (negative? n)]
                    [exp3 (* 3 (exact (floor (/ (log x) (log 1000)))))]
                    [entry (assv exp3 si-prefixes)]
                    [exp3 (if entry exp3 0)]
                    [prefix (if entry (cdr entry) "")]
                    [scaled (/ (inexact (abs n)) (expt 10.0 exp3))]
                    [p (fmt-state-precision st)]
                    [s (format-float scaled (or p 1) (fmt-state-decimal-sep st))])
               ;; Trim trailing zeros after decimal
               (let* ([trimmed (let loop ([i (- (string-length s) 1)])
                                 (cond
                                   [(< i 0) "0"]
                                   [(char=? (string-ref s i) #\0) (loop (- i 1))]
                                   [(char=? (string-ref s i) (fmt-state-decimal-sep st))
                                    (substring s 0 i)]
                                   [else (substring s 0 (+ i 1))]))])
                 (fmt-output st (string-append (if neg? "-" "") trimmed prefix))))))]))

  ;; ---- Padding ----

  (define (capture-output st formatter)
    ;; Run formatter capturing output as string; returns the string.
    (let-values ([(sp get) (open-string-output-port)])
      (let ([saved-port (fmt-state-port st)]
            [saved-col (fmt-state-col st)])
        (fmt-state-port-set! st sp)
        (fmt-state-col-set! st saved-col)
        (run-formatter st formatter)
        (let ([result (get)]
              [new-col (fmt-state-col st)])
          (fmt-state-port-set! st saved-port)
          (fmt-state-col-set! st saved-col)
          (values result new-col)))))

  (define padded
    (case-lambda
      [(width formatter)
       (padded width #f formatter)]
      [(width pad-ch formatter)
       ;; Pad on the right (left-align) to width.
       (lambda (st)
         (let ([pc (or pad-ch (fmt-state-pad-char st))])
           (let-values ([(s new-col) (capture-output st formatter)])
             (let ([slen (string-length s)])
               (fmt-output st s)
               (when (< slen width)
                 (fmt-output st (make-string (- width slen) pc)))))))]))

  (define padded/right
    (case-lambda
      [(width formatter)
       (padded/right width #f formatter)]
      [(width pad-ch formatter)
       ;; Pad on the left (right-align) to width.
       (lambda (st)
         (let ([pc (or pad-ch (fmt-state-pad-char st))])
           (let-values ([(s new-col) (capture-output st formatter)])
             (let ([slen (string-length s)])
               (when (< slen width)
                 (fmt-output st (make-string (- width slen) pc)))
               (fmt-output st s)))))]))

  (define padded/both
    (case-lambda
      [(width formatter)
       (padded/both width #f formatter)]
      [(width pad-ch formatter)
       ;; Center within width.
       (lambda (st)
         (let ([pc (or pad-ch (fmt-state-pad-char st))])
           (let-values ([(s new-col) (capture-output st formatter)])
             (let* ([slen (string-length s)]
                    [total-pad (max 0 (- width slen))]
                    [left-pad (div total-pad 2)]
                    [right-pad (- total-pad left-pad)])
               (when (> left-pad 0)
                 (fmt-output st (make-string left-pad pc)))
               (fmt-output st s)
               (when (> right-pad 0)
                 (fmt-output st (make-string right-pad pc)))))))]))

  ;; ---- Trimming ----

  (define trimmed
    (case-lambda
      [(width formatter)
       ;; Trim from the left (keep rightmost width chars).
       (lambda (st)
         (let-values ([(s _) (capture-output st formatter)])
           (let ([slen (string-length s)])
             (if (<= slen width)
                 (fmt-output st s)
                 (fmt-output st (substring s (- slen width) slen))))))]
      [(width pad-ch formatter)
       ;; pad-ch ignored for trimming, kept for API symmetry
       (trimmed width formatter)]))

  (define trimmed/right
    (case-lambda
      [(width formatter)
       ;; Trim from the right (keep leftmost width chars).
       (lambda (st)
         (let-values ([(s _) (capture-output st formatter)])
           (let ([slen (string-length s)])
             (if (<= slen width)
                 (fmt-output st s)
                 (fmt-output st (substring s 0 width))))))]
      [(width pad-ch formatter)
       (trimmed/right width formatter)]))

  (define trimmed/both
    (case-lambda
      [(width formatter)
       ;; Trim from both sides (keep center).
       (lambda (st)
         (let-values ([(s _) (capture-output st formatter)])
           (let ([slen (string-length s)])
             (if (<= slen width)
                 (fmt-output st s)
                 (let* ([excess (- slen width)]
                        [left (div excess 2)])
                   (fmt-output st (substring s left (+ left width))))))))]
      [(width pad-ch formatter)
       (trimmed/both width formatter)]))

  (define trimmed/lazy
    (case-lambda
      [(width formatter)
       ;; Lazy trim: same as trimmed/right for captured output.
       (trimmed/right width formatter)]
      [(width pad-ch formatter)
       (trimmed/right width formatter)]))

  ;; ---- Fitted (pad or trim to exact width) ----

  (define fitted
    (case-lambda
      [(width formatter)
       ;; Left-aligned, exact width.
       (lambda (st)
         (let-values ([(s _) (capture-output st formatter)])
           (let* ([slen (string-length s)]
                  [pc (fmt-state-pad-char st)])
             (cond
               [(= slen width) (fmt-output st s)]
               [(< slen width)
                (fmt-output st s)
                (fmt-output st (make-string (- width slen) pc))]
               [else
                (fmt-output st (substring s 0 width))]))))]
      [(width pad-ch formatter)
       (lambda (st)
         (let-values ([(s _) (capture-output st formatter)])
           (let* ([slen (string-length s)]
                  [pc (or pad-ch (fmt-state-pad-char st))])
             (cond
               [(= slen width) (fmt-output st s)]
               [(< slen width)
                (fmt-output st s)
                (fmt-output st (make-string (- width slen) pc))]
               [else
                (fmt-output st (substring s 0 width))]))))]))

  (define fitted/right
    (case-lambda
      [(width formatter)
       ;; Right-aligned, exact width.
       (lambda (st)
         (let-values ([(s _) (capture-output st formatter)])
           (let* ([slen (string-length s)]
                  [pc (fmt-state-pad-char st)])
             (cond
               [(= slen width) (fmt-output st s)]
               [(< slen width)
                (fmt-output st (make-string (- width slen) pc))
                (fmt-output st s)]
               [else
                (fmt-output st (substring s (- slen width) slen))]))))]
      [(width pad-ch formatter)
       (lambda (st)
         (let-values ([(s _) (capture-output st formatter)])
           (let* ([slen (string-length s)]
                  [pc (or pad-ch (fmt-state-pad-char st))])
             (cond
               [(= slen width) (fmt-output st s)]
               [(< slen width)
                (fmt-output st (make-string (- width slen) pc))
                (fmt-output st s)]
               [else
                (fmt-output st (substring s (- slen width) slen))]))))]))

  (define fitted/both
    (case-lambda
      [(width formatter)
       ;; Center, exact width.
       (lambda (st)
         (let-values ([(s _) (capture-output st formatter)])
           (let* ([slen (string-length s)]
                  [pc (fmt-state-pad-char st)])
             (cond
               [(= slen width) (fmt-output st s)]
               [(< slen width)
                (let* ([total-pad (- width slen)]
                       [left-pad (div total-pad 2)]
                       [right-pad (- total-pad left-pad)])
                  (fmt-output st (make-string left-pad pc))
                  (fmt-output st s)
                  (fmt-output st (make-string right-pad pc)))]
               [else
                (let* ([excess (- slen width)]
                       [left (div excess 2)])
                  (fmt-output st (substring s left (+ left width))))]))))]
      [(width pad-ch formatter)
       (lambda (st)
         (let-values ([(s _) (capture-output st formatter)])
           (let* ([slen (string-length s)]
                  [pc (or pad-ch (fmt-state-pad-char st))])
             (cond
               [(= slen width) (fmt-output st s)]
               [(< slen width)
                (let* ([total-pad (- width slen)]
                       [left-pad (div total-pad 2)]
                       [right-pad (- total-pad left-pad)])
                  (fmt-output st (make-string left-pad pc))
                  (fmt-output st s)
                  (fmt-output st (make-string right-pad pc)))]
               [else
                (let* ([excess (- slen width)]
                       [left (div excess 2)])
                  (fmt-output st (substring s left (+ left width))))]))))]))

  ;; ---- with (parameterize formatting state) ----
  ;; Uses syntax-case with symbol-name matching to avoid needing auxiliary
  ;; keywords that would conflict with local variable names like 'width'.

  (define (fmt-with-one st key val thunk)
    ;; Set state parameter by symbol key, run thunk, restore.
    (case key
      [(pad-char)
       (let ([saved (fmt-state-pad-char st)])
         (fmt-state-pad-char-set! st val)
         (thunk)
         (fmt-state-pad-char-set! st saved))]
      [(radix)
       (let ([saved (fmt-state-radix st)])
         (fmt-state-radix-set! st val)
         (thunk)
         (fmt-state-radix-set! st saved))]
      [(precision)
       (let ([saved (fmt-state-precision st)])
         (fmt-state-precision-set! st val)
         (thunk)
         (fmt-state-precision-set! st saved))]
      [(width)
       (let ([saved (fmt-state-width st)])
         (fmt-state-width-set! st val)
         (thunk)
         (fmt-state-width-set! st saved))]
      [(comma-sep)
       (let ([saved (fmt-state-comma-sep st)])
         (fmt-state-comma-sep-set! st val)
         (thunk)
         (fmt-state-comma-sep-set! st saved))]
      [(comma-width)
       (let ([saved (fmt-state-comma-width st)])
         (fmt-state-comma-width-set! st val)
         (thunk)
         (fmt-state-comma-width-set! st saved))]
      [(decimal-sep)
       (let ([saved (fmt-state-decimal-sep st)])
         (fmt-state-decimal-sep-set! st val)
         (thunk)
         (fmt-state-decimal-sep-set! st saved))]
      [else (error 'with "unknown formatting parameter" key)]))

  (define-syntax with
    (lambda (x)
      (syntax-case x ()
        [(_ () body)
         #'body]
        [(_ ((key val) rest ...) body)
         #'(lambda (st)
             (fmt-with-one st 'key val
               (lambda ()
                 (run-formatter st (with (rest ...) body)))))])))

  ;; ---- forked ----

  (define (forked formatter1 formatter2)
    ;; Run formatter1 normally, then run formatter2 on the same state.
    (lambda (st)
      (run-formatter st formatter1)
      (run-formatter st formatter2)))

  ;; ---- call-with-output ----

  (define (call-with-output formatter proc)
    ;; Capture formatter output as string, pass to proc which returns a formatter.
    (lambda (st)
      (let-values ([(s _) (capture-output st formatter)])
        (run-formatter st (proc s)))))

) ;; end library
