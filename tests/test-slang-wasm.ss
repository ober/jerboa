#!chezscheme
;;; test-slang-wasm.ss -- Tests for Slang-to-WASM compilation infrastructure
;;;
;;; Tests: tagged values, allocator, runtime primitives, lambda lifting,
;;; expression lowering, and end-to-end WASM compilation.

(import (except (chezscheme) compile-program)
        (jerboa wasm values)
        (jerboa wasm gc)
        (jerboa wasm scheme-runtime)
        (jerboa wasm closure)
        (jerboa wasm codegen))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ((result expr)
           (exp expected))
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (display "FAIL: ")
           (write 'expr)
           (display " => ")
           (write result)
           (display " expected ")
           (write exp)
           (newline))))]))

(define-syntax check-pred
  (syntax-rules ()
    [(_ pred expr)
     (let ((result expr))
       (if (pred result)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (display "FAIL: (")
           (display 'pred)
           (display " ")
           (write result)
           (display ")")
           (newline))))]))

(define (section title)
  (display "--- ")
  (display title)
  (display " ---")
  (newline))

;; ================================================================
;; Tagged Value Constants
;; ================================================================

(section "Tagged Value Constants")

;; Fixnum tagging
(check (tagged-fixnum 0) => 1)     ;; 0 tagged = (0 << 1) | 1 = 1
(check (tagged-fixnum 1) => 3)     ;; 1 tagged = (1 << 1) | 1 = 3
(check (tagged-fixnum -1) => -1)   ;; -1 tagged = (-1 << 1) | 1 = -1
(check (tagged-fixnum 42) => 85)   ;; 42 tagged = (42 << 1) | 1 = 85
(check (tagged-fixnum 100) => 201)

;; Immediate constants
(check IMM-FALSE => 0)
(check IMM-TRUE  => 2)
(check IMM-NIL   => 4)
(check IMM-VOID  => 6)
(check IMM-EOF   => 8)

;; make-imm-const
(check (make-imm-const 'false) => 0)
(check (make-imm-const '#f)    => 0)
(check (make-imm-const 'true)  => 2)
(check (make-imm-const '#t)    => 2)
(check (make-imm-const 'nil)   => 4)
(check (make-imm-const 'void)  => 6)
(check (make-imm-const 'eof)   => 8)

;; make-fixnum-const
(check (make-fixnum-const 0)  => 1)
(check (make-fixnum-const 5)  => 11)
(check (make-fixnum-const -3) => -5)

;; Fixnum range
(check FIXNUM-MIN => -1073741824)
(check FIXNUM-MAX => 1073741823)

;; Tagging preserves value within range
(check (bitwise-arithmetic-shift-right (tagged-fixnum 0) 1)    => 0)
(check (bitwise-arithmetic-shift-right (tagged-fixnum 42) 1)   => 42)
(check (bitwise-arithmetic-shift-right (tagged-fixnum -100) 1) => -100)

;; Tag bit is always 1 for fixnums
(check (bitwise-and (tagged-fixnum 0) 1)   => 1)
(check (bitwise-and (tagged-fixnum 999) 1) => 1)
(check (bitwise-and (tagged-fixnum -1) 1)  => 1)

;; Immediates have bit 0 = 0
(check (bitwise-and IMM-FALSE 1) => 0)
(check (bitwise-and IMM-TRUE 1)  => 0)
(check (bitwise-and IMM-NIL 1)   => 0)

;; Immediates are below HEAP-BASE
(check (< IMM-FALSE HEAP-BASE) => #t)
(check (< IMM-TRUE HEAP-BASE)  => #t)
(check (< IMM-NIL HEAP-BASE)   => #t)
(check (< IMM-VOID HEAP-BASE)  => #t)
(check (< IMM-EOF HEAP-BASE)   => #t)

;; ================================================================
;; Type Tags
;; ================================================================

(section "Type Tags")

(check TYPE-PAIR       => 0)
(check TYPE-STRING     => 1)
(check TYPE-BYTEVECTOR => 2)
(check TYPE-VECTOR     => 3)
(check TYPE-SYMBOL     => 4)
(check TYPE-CLOSURE    => 5)
(check TYPE-RECORD     => 6)
(check TYPE-FLONUM     => 7)
(check TYPE-HASHTABLE  => 8)

;; Header encoding: type in bits 31:24, size in bits 22:0
;; (type << 24) | size
(let ([pair-header (bitwise-ior (bitwise-arithmetic-shift-left TYPE-PAIR HEADER-TYPE-SHIFT)
                                PAIR-PAYLOAD-SIZE)])
  (check (bitwise-arithmetic-shift-right pair-header HEADER-TYPE-SHIFT) => TYPE-PAIR)
  (check (bitwise-and pair-header HEADER-SIZE-MASK) => PAIR-PAYLOAD-SIZE))

(let ([string-header (bitwise-ior (bitwise-arithmetic-shift-left TYPE-STRING HEADER-TYPE-SHIFT)
                                  100)])
  (check (bitwise-arithmetic-shift-right string-header HEADER-TYPE-SHIFT) => TYPE-STRING)
  (check (bitwise-and string-header HEADER-SIZE-MASK) => 100))

;; ================================================================
;; Memory Layout Constants
;; ================================================================

(section "Memory Layout")

;; Regions don't overlap
(check (< MEM-ROOT-STACK-BASE MEM-STATIC-BASE) => #t)
(check (<= (+ MEM-ROOT-STACK-BASE MEM-ROOT-STACK-SIZE) MEM-STATIC-BASE) => #t)
(check (< MEM-STATIC-BASE MEM-IO-BASE) => #t)
(check (<= (+ MEM-STATIC-BASE MEM-STATIC-SIZE) MEM-IO-BASE) => #t)
(check (< MEM-IO-BASE MEM-HEAP-START) => #t)
(check (<= (+ MEM-IO-BASE MEM-IO-SIZE) MEM-HEAP-START) => #t)

;; Heap starts at a sane offset
(check (>= MEM-HEAP-START HEAP-BASE) => #t)

;; Global indices are distinct
(check (not (= GLOBAL-HEAP-PTR GLOBAL-HEAP-END)) => #t)
(check (not (= GLOBAL-HEAP-PTR GLOBAL-ROOT-SP)) => #t)
(check (not (= GLOBAL-HEAP-PTR GLOBAL-ARENA-BASE)) => #t)

;; ================================================================
;; WASM Source Forms Structure
;; ================================================================

(section "WASM Source Forms")

;; value-tag-forms should be a non-empty list of define forms
(check-pred pair? value-tag-forms)
(check-pred pair? value-predicate-forms)
(check-pred pair? value-accessor-forms)
(check-pred pair? value-constructor-forms)
(check-pred pair? value-global-forms)
(check-pred pair? value-memory-forms)

;; Each tag form should be a define
(for-each
  (lambda (form)
    (check (car form) => 'define))
  value-tag-forms)

;; GC forms
(check-pred pair? gc-all-forms)
(check-pred pair? gc-allocator-forms)
(check-pred pair? gc-memory-grow-forms)
(check-pred pair? gc-root-stack-forms)

;; All gc forms should be defines
(for-each
  (lambda (form)
    (check (car form) => 'define))
  gc-all-forms)

;; Runtime forms
(check-pred pair? runtime-list-forms)
(check-pred pair? runtime-bytevector-forms)
(check-pred pair? runtime-string-forms)
(check-pred pair? runtime-vector-forms)
(check-pred pair? runtime-arithmetic-forms)
(check-pred pair? runtime-comparison-forms)
(check-pred pair? runtime-equality-forms)
(check-pred pair? runtime-conversion-forms)
(check-pred pair? runtime-io-forms)
(check-pred pair? runtime-all-forms)

;; ================================================================
;; Free Variable Analysis
;; ================================================================

(section "Free Variable Analysis")

;; No free variables in a constant
(check (free-variables '42 '()) => '())
(check (free-variables '#t '()) => '())

;; Symbol is free if not bound
(check (free-variables 'x '()) => '(x))
(check (free-variables 'x '(x)) => '())
(check (free-variables 'x '(y)) => '(x))

;; Lambda binds its parameters
(check (free-variables '(lambda (x) x) '()) => '())
(check (free-variables '(lambda (x) y) '()) => '(y))
(check (free-variables '(lambda (x) (+ x y)) '()) => '(+ y))
(check (free-variables '(lambda (x) (+ x y)) '(+)) => '(y))

;; Let binds its variables for the body
(check (free-variables '(let ([x 1]) x) '()) => '())
(check (free-variables '(let ([x 1]) y) '()) => '(y))
(check (free-variables '(let ([x y]) x) '()) => '(y))

;; Nested lambdas
(check (free-variables '(lambda (x) (lambda (y) (+ x y z))) '(+))
  => '(z))

;; If expression
(check (free-variables '(if a b c) '()) => '(a b c))
(check (free-variables '(if a b c) '(a)) => '(b c))

;; Begin
(check (free-variables '(begin a b c) '()) => '(a b c))

;; Set!
(check (free-variables '(set! x 42) '()) => '(x))
(check (free-variables '(set! x 42) '(x)) => '())

;; While
(check (free-variables '(while (< i n) (set! i (+ i 1))) '(< + i))
  => '(n))

;; ================================================================
;; Lambda Lifting
;; ================================================================

(section "Lambda Lifting")

;; Simple function with no closures passes through
(let ([result (lambda-lift '((define (f x) (+ x 1))))])
  (check (length result) => 1)
  (check (caar result) => 'define)
  (check (caadar result) => 'f))

;; Two independent functions pass through
(let ([result (lambda-lift '((define (f x) (+ x 1))
                              (define (g y) (* y 2))))])
  (check (length result) => 2))

;; Lambda in let gets lifted
(let ([result (lambda-lift
                '((define (f x)
                    (let ([g (lambda (y) (+ x y))])
                      (g 10)))))])
  ;; Should have more than 1 form (lifted + original)
  (check (> (length result) 1) => #t)
  ;; First form(s) should be the lifted lambda
  (let ([lifted-defs (filter (lambda (f)
                                (and (pair? f)
                                     (eq? (car f) 'define)
                                     (pair? (cadr f))
                                     (let ([name (symbol->string (caadr f))])
                                       (and (>= (string-length name) 8)
                                            (string=? (substring name 0 8) "__lifted")))))
                              result)])
    (check (>= (length lifted-defs) 1) => #t)))

;; ================================================================
;; WASM Compilation (compile-program)
;; ================================================================

(section "WASM Compilation")

;; Minimal program: single function
(let ([wasm (compile-program
              '((define-memory 1)
                (define (add a b) (+ a b))))])
  (check-pred bytevector? wasm)
  ;; WASM magic number: \0asm
  (check (bytevector-u8-ref wasm 0) => 0)
  (check (bytevector-u8-ref wasm 1) => #x61)  ;; 'a'
  (check (bytevector-u8-ref wasm 2) => #x73)  ;; 's'
  (check (bytevector-u8-ref wasm 3) => #x6D)  ;; 'm'
  ;; Version 1
  (check (bytevector-u8-ref wasm 4) => 1))

;; Program with globals and memory
(let ([wasm (compile-program
              '((define-memory 2 16)
                (define-global hp i32 #t 8192)
                (define (get-hp) (global.get 0))
                (define (set-hp val) -> void
                  (global.set 0 val))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 20) => #t))

;; Program with tagged value operations
(let ([wasm (compile-program
              (append
                '((define-memory 2 16))
                value-global-forms
                value-tag-forms
                '((define (test-tag n)
                    (untag-fixnum (tag-fixnum n))))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 40) => #t))

;; Runtime + allocator compiles
(let ([wasm (compile-program
              (append
                value-memory-forms
                value-global-forms
                value-tag-forms
                value-predicate-forms
                value-accessor-forms
                gc-all-forms
                value-constructor-forms
                '((define (test-cons)
                    (cons-val (tag-fixnum 1) (tag-fixnum 2))))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 100) => #t))

;; Full runtime compiles (runtime-all-forms)
(let ([wasm (compile-program
              (append
                value-memory-forms
                value-global-forms
                value-tag-forms
                value-predicate-forms
                value-accessor-forms
                gc-all-forms
                value-constructor-forms
                runtime-all-forms
                '((define (test-list)
                    (let ([lst (scheme-cons (tag-fixnum 1)
                                (scheme-cons (tag-fixnum 2)
                                  (scheme-cons (tag-fixnum 3) 4)))])
                      (scheme-length lst))))))])
  (check-pred bytevector? wasm)
  ;; Should be a reasonable size for a full runtime
  (check (> (bytevector-length wasm) 500) => #t))

;; Program with memory operations (DNS-style)
(let ([wasm (compile-program
              (append
                value-memory-forms
                value-global-forms
                value-tag-forms
                gc-all-forms
                runtime-io-forms
                '((define (read-dns-id buf-offset)
                    (io-read-u16be buf-offset))
                  (define (write-dns-id buf-offset val)
                    (io-write-u16be buf-offset val)))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 50) => #t))

;; ================================================================
;; Compile-program with imports
;; ================================================================

(section "WASM with Imports")

(let ([wasm (compile-program
              '((define-memory 2)
                (define-import "host" log_msg (i32 i32) (i32))
                (define (greet)
                  (log_msg 0 5))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 20) => #t))

;; ================================================================
;; UTF-8 String Length
;; ================================================================

(section "UTF-8 String Length")

;; runtime-string-forms should contain scheme-string-length
(check-pred pair? runtime-string-forms)

;; Verify the scheme-string-length function uses codepoint counting
;; (not byte counting) by checking it references bitwise-and
(let ([src (with-output-to-string (lambda () (write runtime-string-forms)))])
  (check-pred string? src)
  ;; Should contain bitwise-and (UTF-8 continuation byte check)
  (check (string? (let loop ([i 0])
                    (cond
                      [(> i (- (string-length src) 11)) #f]
                      [(string=? (substring src i (+ i 11)) "bitwise-and") src]
                      [else (loop (+ i 1))])))
         => #t))

;; Verify scheme-string-byte-length is also defined (as a runtime form)
(let ([names (map (lambda (f)
                    (and (pair? f) (eq? (car f) 'define) (pair? (cadr f))
                         (caadr f)))
                  runtime-string-forms)])
  (check-pred pair? (memq 'scheme-string-byte-length names)))

;; ================================================================
;; Higher-Order Function Patterns (map, filter, fold-left, etc.)
;; ================================================================

(section "Higher-Order Function Patterns")

;; Test that the patterns produced by map/filter/fold lowering
;; compile to valid WASM.  We construct the lowered forms directly
;; since wasm-target.sls requires the Jerboa reader.

;; map pattern: while + cons + reverse
(let ([wasm (compile-program
              (append
                value-memory-forms
                value-global-forms
                value-tag-forms
                value-predicate-forms
                value-accessor-forms
                gc-all-forms
                value-constructor-forms
                runtime-all-forms
                '((define (double n) (fx+ n n))
                  (define (double-all lst)
                    (let ([__map_iter lst]
                          [__map_result 4])  ;; 4 = IMM-NIL
                      (while (is-pair __map_iter)
                        (let ([__map_item (scheme-car __map_iter)])
                          (set! __map_result
                            (scheme-cons (double __map_item) __map_result))
                          (set! __map_iter (scheme-cdr __map_iter))))
                      (scheme-reverse __map_result))))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 100) => #t))

;; filter pattern: while + conditional cons + reverse
(let ([wasm (compile-program
              (append
                value-memory-forms
                value-global-forms
                value-tag-forms
                value-predicate-forms
                value-accessor-forms
                gc-all-forms
                value-constructor-forms
                runtime-all-forms
                '((define (is-pos n) (fx> n 1))  ;; tagged 0 = fixnum 0
                  (define (keep-positive lst)
                    (let ([__filt_iter lst]
                          [__filt_result 4])
                      (while (is-pair __filt_iter)
                        (let ([__filt_item (scheme-car __filt_iter)])
                          (when (is-pos __filt_item)
                            (set! __filt_result
                              (scheme-cons __filt_item __filt_result)))
                          (set! __filt_iter (scheme-cdr __filt_iter))))
                      (scheme-reverse __filt_result))))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 100) => #t))

;; fold-left pattern: while + accumulator
(let ([wasm (compile-program
              (append
                value-memory-forms
                value-global-forms
                value-tag-forms
                value-predicate-forms
                value-accessor-forms
                gc-all-forms
                value-constructor-forms
                runtime-all-forms
                '((define (sum lst)
                    (let ([__fl_acc 1]      ;; tagged fixnum 0
                          [__fl_iter lst])
                      (while (is-pair __fl_iter)
                        (set! __fl_acc
                          (fx+ __fl_acc (scheme-car __fl_iter)))
                        (set! __fl_iter (scheme-cdr __fl_iter)))
                      __fl_acc)))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 100) => #t))

;; for-each pattern: while + call, return void
(let ([wasm (compile-program
              (append
                value-memory-forms
                value-global-forms
                value-tag-forms
                value-predicate-forms
                value-accessor-forms
                gc-all-forms
                value-constructor-forms
                runtime-all-forms
                '((define (noop x) x)
                  (define (do-each lst)
                    (let ([__fe_iter lst])
                      (while (is-pair __fe_iter)
                        (noop (scheme-car __fe_iter))
                        (set! __fe_iter (scheme-cdr __fe_iter)))
                      6)))))])   ;; 6 = IMM-VOID
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 100) => #t))

;; fold-right pattern: reverse then fold-left
(let ([wasm (compile-program
              (append
                value-memory-forms
                value-global-forms
                value-tag-forms
                value-predicate-forms
                value-accessor-forms
                gc-all-forms
                value-constructor-forms
                runtime-all-forms
                '((define (my-reverse lst)
                    (let ([__fr_acc 4]
                          [__fr_iter (scheme-reverse lst)])
                      (while (is-pair __fr_iter)
                        (set! __fr_acc
                          (scheme-cons (scheme-car __fr_iter) __fr_acc))
                        (set! __fr_iter (scheme-cdr __fr_iter)))
                      __fr_acc)))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 100) => #t))

;; ================================================================
;; Quasiquote / N-ary Append Patterns
;; ================================================================

(section "Quasiquote Patterns")

;; Quasiquote expansion produces list+cons+append patterns.
;; Test that n-ary append (the pattern for ,@splicing) compiles correctly.

;; Two-arg append compiles
(let ([wasm (compile-program
              (append
                value-memory-forms
                value-global-forms
                value-tag-forms
                value-predicate-forms
                value-accessor-forms
                gc-all-forms
                value-constructor-forms
                runtime-all-forms
                '((define (test-append a b)
                    (scheme-append a b)))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 50) => #t))

;; Nested append (pattern for 3-arg append from quasiquote) compiles
(let ([wasm (compile-program
              (append
                value-memory-forms
                value-global-forms
                value-tag-forms
                value-predicate-forms
                value-accessor-forms
                gc-all-forms
                value-constructor-forms
                runtime-all-forms
                '((define (test-append3 a b c)
                    (scheme-append a (scheme-append b c))))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 50) => #t))

;; Pattern for `(1 ,b) → (cons 1 (cons b nil)) → cons chain
(let ([wasm (compile-program
              (append
                value-memory-forms
                value-global-forms
                value-tag-forms
                value-predicate-forms
                value-accessor-forms
                gc-all-forms
                value-constructor-forms
                runtime-all-forms
                '((define (test-qq b)
                    (scheme-cons (tag-fixnum 1)
                      (scheme-cons b 4))))))])  ;; 4 = NIL
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 50) => #t))

;; ================================================================
;; Result Type Operations
;; ================================================================

(section "Result Type Operations")

;; runtime-result-forms should be a non-empty list of define forms
(check-pred pair? runtime-result-forms)
(for-each
  (lambda (form)
    (check (car form) => 'define))
  runtime-result-forms)

;; Result runtime contains ok, err, ok?, err?, unwrap, unwrap-or
(let ([names (map (lambda (f)
                    (and (pair? f) (eq? (car f) 'define) (pair? (cadr f))
                         (caadr f)))
                  runtime-result-forms)])
  (check-pred pair? (memq 'scheme-ok names))
  (check-pred pair? (memq 'scheme-err names))
  (check-pred pair? (memq 'scheme-ok? names))
  (check-pred pair? (memq 'scheme-err? names))
  (check-pred pair? (memq 'scheme-unwrap names))
  (check-pred pair? (memq 'scheme-unwrap-or names))
  (check-pred pair? (memq 'scheme-result-value names)))

;; Result operations compile to valid WASM
(let ([wasm (compile-program
              (append
                value-memory-forms
                value-global-forms
                value-tag-forms
                value-predicate-forms
                value-accessor-forms
                gc-all-forms
                value-constructor-forms
                runtime-all-forms
                '((define (test-ok x)
                    (scheme-ok (tag-fixnum x)))
                  (define (test-err x)
                    (scheme-err (tag-fixnum x)))
                  (define (test-check r)
                    (if (scheme-ok? r)
                      (scheme-unwrap r)
                      (scheme-unwrap-or r (tag-fixnum 0)))))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 100) => #t))

;; ================================================================
;; Variadic Lambda Parameters
;; ================================================================

(section "Variadic Lambda Parameters")

;; Lambda-params already handles rest args
(check (lambda-params '(x y)) => '(x y))
(check (lambda-params '(x . rest)) => '(x rest))
(check (lambda-params 'args) => '(args))
(check (lambda-params '((x i32) . rest)) => '(x rest))

;; Free variable analysis handles rest args in lambda
(let ([fvs (free-variables '(lambda (x . rest) (+ x y rest)) '())])
  ;; x and rest are bound, y and + are free
  (check-pred pair? (memq 'y fvs))
  (check (memq 'x fvs) => #f)
  (check (memq 'rest fvs) => #f))

;; Lambda lifting of varargs lambda
(let ([result (lambda-lift
                '((define (f x)
                    (let ([g (lambda (y . rest) (+ x y))])
                      (g 1 2 3)))))])
  (check-pred pair? result)
  ;; Should have lifted definitions
  (check (> (length result) 1) => #t))

;; ================================================================
;; Exception Handling Patterns
;; ================================================================

(section "Exception Handling Patterns")

;; throw with tag compiles to valid WASM
(let ([wasm (compile-program
              (append
                value-memory-forms
                value-global-forms
                value-tag-forms
                '((define-tag 0)
                  (define (check-positive n)
                    (when (not n)
                      (throw 0 0))
                    n))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 30) => #t))

;; assert! pattern: throw on falsy condition
(let ([wasm (compile-program
              (append
                value-memory-forms
                value-global-forms
                value-tag-forms
                '((define-tag 0)
                  (define (assert-test n)
                    (when (= n 0)
                      (throw 0 0))
                    n))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 30) => #t))

;; ================================================================
;; Tail Call Patterns
;; ================================================================

(section "Tail Call Patterns")

;; return-call compiles to valid WASM (tail call instruction)
(let ([wasm (compile-program
              (append
                value-memory-forms
                value-global-forms
                '((define (factorial n acc)
                    (if (= n 0)
                      acc
                      (return-call factorial (- n 1) (* acc n)))))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 30) => #t))

;; Recursive tail call with branching
(let ([wasm (compile-program
              (append
                value-memory-forms
                value-global-forms
                '((define (count-down n)
                    (if (= n 0)
                      0
                      (return-call count-down (- n 1)))))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 30) => #t))

;; Full runtime with UTF-8 string-length compiles to valid WASM
(let ([wasm (compile-program
              (append
                value-memory-forms
                value-global-forms
                value-tag-forms
                value-predicate-forms
                value-accessor-forms
                gc-all-forms
                value-constructor-forms
                runtime-all-forms
                '((define (test-strlen)
                    (scheme-string-length (tag-fixnum 0))))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 100) => #t))

;; ================================================================
;; Closure Infrastructure (Phase 1A/1B/1C)
;; ================================================================

(section "Closure Infrastructure")

;; runtime-closure-forms contains call-closure-N and closure-func-idx
(check-pred pair? runtime-closure-forms)
(let ([names (map (lambda (f)
                    (and (pair? f) (eq? (car f) 'define) (pair? (cadr f))
                         (caadr f)))
                  runtime-closure-forms)])
  (check-pred pair? (memq 'closure-func-idx names))
  (check-pred pair? (memq 'closure-env-count names))
  (check-pred pair? (memq 'call-closure-1 names))
  (check-pred pair? (memq 'call-closure-2 names))
  (check-pred pair? (memq 'call-closure-3 names)))

;; runtime-closure-type-forms contains exactly 3 define-type forms
(check (length runtime-closure-type-forms) => 3)
(for-each
  (lambda (form)
    (check (car form) => 'define-type))
  runtime-closure-type-forms)

;; define-type is accepted by compile-program without error
(let ([wasm (compile-program
              (append
                value-memory-forms
                value-global-forms
                '((define-type (i32 i32) (i32))
                  (define-type (i32 i32 i32) (i32)))
                value-tag-forms
                value-predicate-forms
                value-accessor-forms
                value-constructor-forms
                gc-all-forms
                runtime-all-forms
                '((define (test-fn x) x))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 50) => #t))

;; lambda-lift now uses symbolic lifted name in alloc-closure (not 0)
(let* ([forms '((define (make-adder x)
                  (lambda (y) (+ x y))))]
       [lifted (lambda-lift forms)])
  ;; Find alloc-closure forms in the lifted output
  (define (find-alloc-closure forms)
    (let loop ([fs forms] [found '()])
      (if (null? fs) found
        (let ([f (car fs)])
          (loop (cdr fs)
            (if (and (pair? f) (eq? (car f) 'alloc-closure))
              (cons f found)
              (append found (find-alloc-closure
                              (if (pair? f) f '())))))))))
  (define (collect-alloc-closures expr)
    (cond
      [(not (pair? expr)) '()]
      [(eq? (car expr) 'alloc-closure) (list expr)]
      [else (apply append (map collect-alloc-closures expr))]))
  (let ([allocs (apply append (map collect-alloc-closures lifted))])
    ;; There should be at least one alloc-closure
    (check-pred pair? allocs)
    ;; The func-idx field (cadr) should be a symbol (lifted name), not 0
    (for-each
      (lambda (ac)
        (check-pred symbol? (cadr ac)))
      allocs)))

;; assign-closure-indices replaces symbolic func-idx with integer
;; (test via compile-program: a closure-using program compiles cleanly)
(let ([wasm (compile-program
              (append
                ;; closure type pre-registration first
                runtime-closure-type-forms
                value-memory-forms
                value-global-forms
                value-tag-forms
                value-predicate-forms
                value-accessor-forms
                value-constructor-forms
                gc-all-forms
                runtime-all-forms
                ;; A pre-lifted closure: func-idx 0 (first table slot)
                '((define-table 64 256)
                  (define (__lifted_test env y)
                    (+ (closure-env-ref env 0) y))
                  (define (make-adder x)
                    (let ([c (alloc-closure 0 1)])
                      (closure-env-set! c 0 x)
                      c))
                  (define-element 0 (__lifted_test)))))])
  (check-pred bytevector? wasm)
  (check (> (bytevector-length wasm) 100) => #t))

;; ================================================================
;; Summary
;; ================================================================

(newline)
(display "=========================")
(newline)
(display "Results: ")
(display pass-count)
(display " passed, ")
(display fail-count)
(display " failed")
(newline)
(display "=========================")
(newline)

(when (> fail-count 0)
  (exit 1))
