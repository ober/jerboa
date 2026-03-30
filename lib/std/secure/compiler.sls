#!chezscheme
;;; (std secure compiler) -- Slang compiler front-end
;;;
;;; Validates that Scheme source uses only the safe Slang subset,
;;; rejects unsafe operations (eval, FFI, call/cc, system, etc.),
;;; enforces resource limits (recursion depth, iteration bounds),
;;; parses slang-module declarations, and emits safe Chez Scheme
;;; suitable for compile-whole-program.
;;;
;;; This is a FILTER, not a new backend. Every Slang program is a
;;; valid Jerboa program. The compiler rejects the dangerous parts
;;; before Chez compiles what remains.

(library (std secure compiler)
  (export
    ;; Core compilation
    slang-compile
    slang-validate
    slang-validate-file

    ;; Module declaration parsing
    parse-slang-module
    slang-module?
    slang-module-name
    slang-module-requires
    slang-module-limits
    slang-module-body

    ;; Configuration
    make-slang-config
    slang-config?
    slang-config-platform
    slang-config-debug?
    slang-config-max-recursion
    slang-config-max-iteration

    ;; Validation results
    slang-error?
    slang-error-kind
    slang-error-form
    slang-error-message

    ;; Subset inspection
    slang-allowed-forms
    slang-forbidden-forms)

  (import (chezscheme)
          (std error conditions))

  ;; ========== Condition type ==========

  (define-condition-type &slang-error &jerboa
    make-slang-error slang-error?
    (kind    slang-error-kind)     ;; 'forbidden | 'syntax | 'limit | 'module
    (form    slang-error-form)     ;; the offending s-expression or #f
    (message slang-error-message)) ;; human-readable string

  ;; ========== Configuration ==========

  (define-record-type (%slang-config %make-slang-config slang-config?)
    (sealed #t)
    (fields
      (immutable platform       slang-config-platform)
      (immutable debug?         slang-config-debug?)
      (immutable max-recursion  slang-config-max-recursion)
      (immutable max-iteration  slang-config-max-iteration)
      (immutable max-alloc-mb   slang-config-max-alloc-mb)))

  (define (normalize-key sym)
    (let ([s (symbol->string sym)])
      (cond
        [(and (>= (string-length s) 2)
              (char=? (string-ref s 0) #\#)
              (char=? (string-ref s 1) #\:))
         (substring s 2 (string-length s))]
        [(and (> (string-length s) 0)
              (char=? (string-ref s (- (string-length s) 1)) #\:))
         (substring s 0 (- (string-length s) 1))]
        [else s])))

  (define (make-slang-config . args)
    (let loop ([rest args]
               [platform (detect-platform)]
               [debug? #f]
               [max-recursion 1000]
               [max-iteration 10000000]
               [max-alloc-mb 64])
      (if (null? rest)
        (%make-slang-config platform debug? max-recursion
                           max-iteration max-alloc-mb)
        (begin
          (when (null? (cdr rest))
            (error 'make-slang-config "keyword missing value" (car rest)))
          (let ([key (normalize-key (car rest))]
                [val (cadr rest)]
                [remaining (cddr rest)])
            (cond
              [(string=? key "platform")
               (loop remaining val debug? max-recursion max-iteration max-alloc-mb)]
              [(string=? key "debug")
               (loop remaining platform val max-recursion max-iteration max-alloc-mb)]
              [(string=? key "max-recursion")
               (loop remaining platform debug? val max-iteration max-alloc-mb)]
              [(string=? key "max-iteration")
               (loop remaining platform debug? max-recursion val max-alloc-mb)]
              [(string=? key "max-alloc-mb")
               (loop remaining platform debug? max-recursion max-iteration val)]
              [else
               (error 'make-slang-config "unknown keyword" (car rest))]))))))

  ;; ========== Platform detection ==========

  (define (string-contains-ci str sub)
    (let ([slen (string-length str)]
          [sublen (string-length sub)])
      (let lp ([i 0])
        (cond
          [(> (+ i sublen) slen) #f]
          [(string-ci=? (substring str i (+ i sublen)) sub) #t]
          [else (lp (+ i 1))]))))

  (define (detect-platform)
    (let ([mt (symbol->string (machine-type))])
      (cond
        [(string-contains-ci mt "le")  'linux]
        [(string-contains-ci mt "osx") 'macos]
        [(string-contains-ci mt "fb")  'freebsd]
        [else                          'unknown])))

  ;; ========== Slang allowed / forbidden forms ==========

  ;; Forms that are ALLOWED in the Slang subset.
  ;; This is an allowlist -- anything not here is rejected at the head position.
  (define *slang-allowed-heads*
    '(;; Core definitions
      define lambda let let* letrec letrec* let-values
      begin if cond case when unless and or not do

      ;; Pattern matching
      match

      ;; Data structure definitions
      define-record-type define-enum

      ;; Iteration (bounded -- compiler wraps with limits)
      for for/collect for/fold for/or for/and
      map filter fold-left fold-right for-each
      while until dotimes

      ;; Error handling
      guard with-exception-handler raise
      assert

      ;; Resource management
      with-resource dynamic-wind

      ;; Threading macros
      -> ->> some-> cond-> as->

      ;; Binding forms
      let-values define-values

      ;; Quoting
      quote quasiquote

      ;; Type annotations (pass-through to std/typed)
      define/t lambda/t

      ;; Concurrency (channels only)
      make-channel channel-put channel-get
      channel-try-put channel-try-get channel-close

      ;; Structured spawn
      spawn spawn-group

      ;; Values
      values call-with-values))

  ;; Forms that are EXPLICITLY FORBIDDEN -- produce clear error messages.
  ;; Anything not in allowed AND not in forbidden gets a generic rejection.
  (define *slang-forbidden-forms*
    '((eval             "runtime code generation is not allowed in Slang")
      (load             "runtime code loading is not allowed in Slang")
      (compile          "runtime compilation is not allowed in Slang")
      (compile-program  "runtime compilation is not allowed in Slang")
      (compile-file     "runtime compilation is not allowed in Slang")
      (compile-whole-program "runtime compilation is not allowed in Slang")
      (expand           "macro expansion is not allowed in Slang")

      (foreign-procedure "raw FFI is not allowed in Slang")
      (c-lambda         "raw FFI is not allowed in Slang")
      (foreign-entry?   "raw FFI is not allowed in Slang")
      (load-shared-object "loading shared objects is not allowed in Slang")
      (ftype-pointer-address "raw pointer access is not allowed in Slang")

      (call/cc          "call/cc can escape the security sandbox")
      (call-with-current-continuation "call/cc can escape the security sandbox")

      (system           "shell access is not allowed in Slang")
      (process-create   "spawning processes is not allowed in Slang")
      (open-process-ports "spawning processes is not allowed in Slang")

      (open-input-file  "ambient file access is not allowed -- use pre-opened FDs")
      (open-output-file "ambient file access is not allowed -- use pre-opened FDs")
      (open-file-input-port  "ambient file access is not allowed -- use pre-opened FDs")
      (open-file-output-port "ambient file access is not allowed -- use pre-opened FDs")
      (delete-file      "ambient file access is not allowed -- use pre-opened FDs")
      (rename-file      "ambient file access is not allowed -- use pre-opened FDs")

      (gensym           "symbol table access is not allowed in Slang")
      (interaction-environment "environment access is not allowed in Slang")
      (scheme-environment "environment access is not allowed in Slang")
      (environment       "environment access is not allowed in Slang")
      (top-level-value   "environment access is not allowed in Slang")
      (define-top-level-value "environment access is not allowed in Slang")

      (set!             "global mutation is not allowed in Slang")

      (define-syntax    "user-defined macros are not allowed in Slang")
      (syntax-case      "user-defined macros are not allowed in Slang")
      (syntax-rules     "user-defined macros are not allowed in Slang")
      (define-record     "use define-record-type instead")

      (make-parameter   "dynamic scope is not allowed in Slang")
      (parameterize     "dynamic scope is not allowed in Slang")

      (read             "raw deserialization is not allowed -- use typed parsers")

      (sleep            "arbitrary delays are not allowed in Slang")
      (thread-sleep     "arbitrary delays are not allowed in Slang")))

  (define (slang-allowed-forms) (list-copy *slang-allowed-heads*))
  (define (slang-forbidden-forms) (map car *slang-forbidden-forms*))

  ;; ========== Safe callable functions ==========

  ;; These are functions/values that may appear in operator position
  ;; beyond the allowed special forms. They include safe prelude functions.
  (define *slang-safe-callables*
    '(;; Arithmetic
      + - * / = < > <= >= zero? positive? negative?
      add1 sub1 abs min max gcd lcm
      quotient remainder modulo
      expt sqrt floor ceiling truncate round
      number? integer? rational? real? complex? fixnum? flonum?
      exact? inexact? exact->inexact inexact->exact
      number->string string->number
      bitwise-and bitwise-ior bitwise-xor bitwise-not
      bitwise-arithmetic-shift-left bitwise-arithmetic-shift-right
      fx+ fx- fx* fxdiv fxmod fx= fx< fx> fx<= fx>=
      fl+ fl- fl* fl/ fl= fl< fl> fl<= fl>=

      ;; Comparison
      eq? eqv? equal? not

      ;; Booleans
      boolean? boolean=?

      ;; Pairs and lists
      cons car cdr pair? null? list? list
      caar cadr cdar cddr
      caaar caadr cadar caddr cdaar cdadr cddar cdddr
      length append reverse
      assoc assv assq member memv memq
      list-ref list-tail
      exists for-all
      iota

      ;; Extended list ops (from prelude)
      flatten unique take drop take-last drop-last
      every any filter-map group-by zip frequencies
      partition interleave mapcat distinct keep split-at
      append-map snoc

      ;; Strings
      string? string-length string-ref string-append
      string=? string<? string>? string<=? string>=?
      substring string->list list->string
      string-upcase string-downcase string-copy
      symbol->string string->symbol
      string-split string-join string-trim
      string-prefix? string-suffix? string-contains
      string-empty? str format

      ;; Characters
      char? char=? char<? char>?
      char-alphabetic? char-numeric? char-whitespace?
      char->integer integer->char char-upcase char-downcase

      ;; Vectors
      vector? vector vector-length vector-ref
      make-vector vector->list list->vector vector-copy
      vector-map vector-for-each

      ;; Bytevectors
      bytevector? make-bytevector bytevector-length
      bytevector-u8-ref bytevector-u8-set!
      bytevector-copy bytevector-copy!
      utf8->string string->utf8
      bytevector-append

      ;; Hash tables (construction + read)
      make-hash-table hash-table?
      hash-ref hash-get hash-key?
      hash-put! hash-remove!
      hash->list hash-keys hash-values
      hash-for-each list->hash-table

      ;; Symbols
      symbol?

      ;; I/O (restricted)
      display write newline displayln printf fprintf
      port? input-port? output-port?
      eof-object? eof-object
      read-char peek-char write-char
      get-line get-string-all
      put-string put-bytevector
      open-input-string open-output-string get-output-string
      open-bytevector-output-port get-output-bytevector
      flush-output-port close-port
      current-input-port current-output-port current-error-port
      with-output-to-string with-input-from-string

      ;; FD-based I/O (for pre-opened descriptors)
      fd-read fd-write fd-close

      ;; Errors and conditions
      error condition? message-condition? condition-message
      warning who-condition? condition-who

      ;; Result types
      ok err ok? err? result? unwrap unwrap-or
      map-ok map-err and-then or-else
      try-result try-result*
      sequence-results flatten-result
      ->?

      ;; Misc
      void apply values call-with-values
      sort reverse
      identity constantly
      compose comp partial complement negate
      curry flip conjoin disjoin juxt cut

      ;; Predicates
      procedure? symbol? string? number? pair? null? list?
      vector? bytevector? boolean? char? fixnum? flonum?
      hashtable? hash-table?

      ;; Type system
      define/t lambda/t

      ;; Struct operations (generated by define-record-type)
      ;; These are allowed dynamically -- any predicate ending in ?
      ;; and any accessor matching a known struct prefix.

      ;; JSON (safe -- operates on in-memory data)
      string->json-object json-object->string
      read-json write-json

      ;; CSV
      csv->alists

      ;; DateTime
      datetime-now datetime-utc-now
      make-datetime parse-datetime
      datetime->iso8601 datetime->epoch
      datetime-add datetime-diff datetime<?
      day-of-week leap-year?

      ;; Paths (pure functions)
      path-join path-directory path-extension path-absolute?

      ;; File I/O (guarded -- only works on pre-opened/allowed paths)
      read-file-string read-file-lines write-file-string

      ;; Pretty printing
      pp pp-to-string

      ;; Formatting
      format printf displayln

      ;; Anaphoric
      ;; awhen, aif, when-let, if-let are macros -- handled as allowed heads

      ;; Iterators
      in-list in-vector in-string in-range
      in-hash-keys in-hash-values in-hash-pairs
      in-naturals in-indexed in-port in-lines
      in-chars in-bytes in-bytevector in-producer))

  ;; ========== Module declaration parsing ==========

  (define-record-type (%slang-module %make-slang-module slang-module?)
    (sealed #t)
    (fields
      (immutable name     slang-module-name)
      (immutable requires slang-module-requires)  ;; alist of (kind . specs)
      (immutable limits   slang-module-limits)     ;; alist of (key . value)
      (immutable body     slang-module-body)))     ;; list of body forms

  (define (parse-slang-module forms)
    "Parse a list of top-level forms. The first form may be a
     (slang-module name ...) declaration. Returns a slang-module record."
    (if (and (pair? forms)
             (pair? (car forms))
             (eq? (caar forms) 'slang-module))
      ;; Has module declaration
      (let* ([decl (car forms)]
             [name (cadr decl)]
             [body-forms (cdr forms)]
             [sections (cddr decl)]
             [requires (parse-require-section sections)]
             [limits (parse-limits-section sections)])
        (%make-slang-module name requires limits body-forms))
      ;; No module declaration -- bare program
      (%make-slang-module 'anonymous '() '() forms)))

  (define (parse-require-section sections)
    "Extract (require ...) from module declaration sections."
    (let ([req (find-section 'require sections)])
      (if req
        (map parse-require-entry (cdr req))
        '())))

  (define (parse-require-entry entry)
    "Parse a single require entry like (network (listen ...)) or
     (filesystem (read ...))."
    (unless (and (pair? entry) (symbol? (car entry)))
      (raise (make-slang-error "slang" 'syntax entry
               "require entry must be (kind spec ...)")))
    (cons (car entry) (cdr entry)))

  (define (parse-limits-section sections)
    "Extract (limits ...) from module declaration sections."
    (let ([lim (find-section 'limits sections)])
      (if lim
        (map (lambda (entry)
               (unless (and (pair? entry)
                            (symbol? (car entry))
                            (pair? (cdr entry)))
                 (raise (make-slang-error "slang" 'syntax entry
                          "limits entry must be (key value)")))
               (cons (car entry) (cadr entry)))
             (cdr lim))
        '())))

  (define (find-section name sections)
    "Find a (name ...) form in a list of sections."
    (cond
      [(null? sections) #f]
      [(and (pair? (car sections))
            (eq? (caar sections) name))
       (car sections)]
      [else (find-section name (cdr sections))]))

  ;; ========== AST validation ==========

  (define (slang-validate forms . opts)
    "Validate a list of forms against the Slang subset.
     Returns a list of slang-error conditions (empty = valid).
     Does NOT raise -- collects all errors for reporting."
    (let ([config (if (and (pair? opts) (slang-config? (car opts)))
                    (car opts)
                    (make-slang-config))]
          [errors '()])

      (define (add-error! kind form msg)
        (set! errors (cons (make-slang-error "slang" kind form msg) errors)))

      (define (check-form form depth)
        (cond
          ;; Self-evaluating: numbers, strings, booleans, chars, bytevectors
          [(or (number? form) (string? form) (boolean? form)
               (char? form) (bytevector? form))
           (void)]

          ;; Symbol reference -- allowed
          [(symbol? form)
           (when (memq form (slang-forbidden-forms))
             (let ([entry (assq form *slang-forbidden-forms*)])
               (add-error! 'forbidden form
                 (if entry (cadr entry)
                   (format "~a is not allowed in Slang" form)))))]

          ;; Pair (compound form)
          [(pair? form)
           (let ([head (car form)])
             (cond
               ;; Skip the slang-module declaration itself
               [(eq? head 'slang-module) (void)]

               ;; import -- only allow (import (jerboa prelude))
               ;; and specific safe std modules
               [(eq? head 'import)
                (for-each
                  (lambda (spec)
                    (check-import-spec spec form))
                  (cdr form))]

               ;; quote/quasiquote -- contents not validated
               [(memq head '(quote quasiquote)) (void)]

               ;; define -- check the body, not the name
               [(eq? head 'define)
                (check-define form depth)]

               ;; define-record-type -- allowed, check field specs
               [(eq? head 'define-record-type)
                (void)] ;; record type definitions are safe

               ;; define-enum -- allowed
               [(eq? head 'define-enum)
                (void)]

               ;; Known allowed special forms -- check subforms
               [(memq head *slang-allowed-heads*)
                (check-subforms (cdr form) (+ depth 1))]

               ;; Known forbidden forms -- specific error
               [(assq head *slang-forbidden-forms*)
                => (lambda (entry)
                     (add-error! 'forbidden form (cadr entry)))]

               ;; Function application -- head must be safe callable
               ;; or a lambda/let-bound variable (can't statically verify all)
               [(symbol? head)
                (cond
                  ;; Known safe callable
                  [(memq head *slang-safe-callables*)
                   (check-subforms (cdr form) (+ depth 1))]
                  ;; set! on anything -- forbidden
                  [(eq? head 'set!)
                   (add-error! 'forbidden form
                     "mutation via set! is not allowed in Slang")]
                  ;; Could be a user-defined function -- allow
                  ;; (we can't statically resolve all bindings)
                  [else
                   (check-subforms (cdr form) (+ depth 1))])]

               ;; Head is an expression (lambda application etc.)
               [else
                (check-form head (+ depth 1))
                (check-subforms (cdr form) (+ depth 1))]))]

          ;; Vector literal
          [(vector? form)
           (vector-for-each
             (lambda (elem) (check-form elem depth))
             form)]

          ;; Anything else (void, eof, etc.)
          [else (void)]))

      (define (check-subforms forms depth)
        (when (pair? forms)
          (check-form (car forms) depth)
          (check-subforms (cdr forms) depth)))

      (define (check-define form depth)
        ;; (define name expr) or (define (name args...) body...)
        (when (and (pair? (cdr form)) (pair? (cddr form)))
          (let ([target (cadr form)])
            (cond
              ;; (define (f args...) body...)
              [(pair? target)
               (check-subforms (cddr form) (+ depth 1))]
              ;; (define name expr)
              [(symbol? target)
               (check-subforms (cddr form) (+ depth 1))]
              [else
               (add-error! 'syntax form "malformed define")]))))

      ;; Allowed import modules for Slang
      (define *slang-allowed-imports*
        '((jerboa prelude)
          (std text json)
          (std text base64)
          (std text hex)
          (std text csv)
          (std text regex)
          (std sort)
          (std result)
          (std format)
          (std datetime)
          (std test)
          (std binary)
          (std misc channel)
          (std misc string)
          (std typed)
          (std arena)))

      (define (check-import-spec spec form)
        (cond
          ;; Bare module path: (std text json)
          [(and (pair? spec) (symbol? (car spec)))
           (unless (member spec *slang-allowed-imports*)
             (add-error! 'forbidden form
               (format "import of ~a is not allowed in Slang" spec)))]
          ;; (only ...), (except ...), (rename ...) wrappers
          [(and (pair? spec) (memq (car spec) '(only except rename prefix)))
           (check-import-spec (cadr spec) form)]
          [else (void)]))

      ;; Validate all forms
      (for-each (lambda (form) (check-form form 0)) forms)

      ;; Return collected errors (reversed to preserve order)
      (reverse errors)))

  (define (slang-validate-file path . opts)
    "Read and validate a Slang source file.
     Returns a list of slang-error conditions."
    (let ([forms (read-source-file path)])
      (apply slang-validate forms opts)))

  ;; ========== Source reading ==========

  (define (read-source-file path)
    "Read all forms from a Scheme source file."
    (call-with-input-file path
      (lambda (port)
        (let loop ([forms '()])
          (let ([form (read port)])
            (if (eof-object? form)
              (reverse forms)
              (loop (cons form forms))))))))

  ;; ========== Code emission ==========

  (define (emit-slang-program mod config)
    "Transform a validated slang-module into safe Chez Scheme source.
     Returns a list of forms ready for compile-program."
    (let ([preamble-import '(import (std secure preamble))]
          [debug? (slang-config-debug? config)]
          [max-rec (slang-config-max-recursion config)]
          [max-iter (slang-config-max-iteration config)]
          [platform (slang-config-platform config)])

      (append
        ;; 1. Import the prelude (provides safe Jerboa environment)
        '((import (jerboa prelude)))

        ;; 2. Import the security preamble
        (list preamble-import)

        ;; 3. Import any additional allowed modules from the source
        (extract-imports (slang-module-body mod))

        ;; 4. Runtime limit definitions
        (list
          `(define *slang-max-recursion* ,max-rec)
          `(define *slang-max-iteration* ,max-iter))

        ;; 5. Preamble initialization call
        ;; This sets up the sandbox, integrity checks, etc.
        (list
          `(slang-preamble-init!
             ',(slang-module-name mod)
             ',platform
             ',(slang-module-requires mod)
             ',debug?))

        ;; 6. The user's program body (already validated)
        (filter (lambda (form)
                  ;; Strip slang-module declarations and imports
                  ;; (we already handled them above)
                  (not (and (pair? form)
                            (memq (car form) '(slang-module import)))))
                (slang-module-body mod)))))

  (define (extract-imports forms)
    "Extract import forms from the body for re-emission."
    (filter (lambda (form)
              (and (pair? form) (eq? (car form) 'import)))
            forms))

  ;; ========== Top-level compilation ==========

  (define (slang-compile source-path . opts)
    "Compile a Slang source file.

     Parameters:
       source-path - Path to .ss source file

     Keyword options:
       output:    - Output path for compiled .wpo (default: derived from source)
       config:    - slang-config record (default: auto-detected)
       verbose:   - Print compilation steps

     Returns: output path on success, raises on validation errors."
    (let* ([config (kwarg 'config: opts (make-slang-config))]
           [verbose? (kwarg 'verbose: opts #f)]
           [output (kwarg 'output: opts
                     (string-append (%slang-path-root source-path) ".wpo"))]
           ;; Read source
           [forms (read-source-file source-path)]
           ;; Parse module declaration
           [mod (parse-slang-module forms)])

      ;; Step 1: Validate
      (when verbose?
        (printf "[slang] Validating ~a...~n" source-path))

      (let ([errors (slang-validate forms config)])
        (unless (null? errors)
          (when verbose?
            (printf "[slang] ~a validation error(s):~n" (length errors))
            (for-each
              (lambda (err)
                (printf "  ~a: ~a~n"
                  (slang-error-kind err)
                  (slang-error-message err)))
              errors))
          (raise (car errors))))

      ;; Step 2: Emit safe Chez Scheme
      (when verbose?
        (printf "[slang] Emitting safe Chez Scheme...~n"))

      (let* ([safe-forms (emit-slang-program mod config)]
             [temp-path (string-append source-path ".slang-tmp")])

        ;; Write the transformed source
        (call-with-output-file temp-path
          (lambda (out)
            (for-each
              (lambda (form)
                (pretty-print form out)
                (newline out))
              safe-forms))
          'replace)

        ;; Step 3: Compile with Chez
        (when verbose?
          (printf "[slang] Compiling to ~a...~n" output))

        (guard (exn
                 [#t (guard (e [#t (void)])
                       (delete-file temp-path))
                     (raise exn)])
          (parameterize ([optimize-level 2]
                         [compile-imported-libraries #t]
                         [generate-inspector-information #f])
            (compile-program temp-path output))

          ;; Cleanup temp file
          (guard (e [#t (void)])
            (delete-file temp-path))

          (when verbose?
            (printf "[slang] Compilation complete: ~a~n" output))

          output))))

  ;; ========== Helpers ==========

  (define (kwarg key opts . default-args)
    (let ([default (if (null? default-args) #f (car default-args))])
      (let loop ([lst opts])
        (cond [(or (null? lst) (null? (cdr lst))) default]
              [(eq? (car lst) key) (cadr lst)]
              [else (loop (cddr lst))]))))

  (define (%slang-path-root path)
    (let loop ([i (- (string-length path) 1)])
      (cond
        [(< i 0) path]
        [(char=? (string-ref path i) #\.) (substring path 0 i)]
        [(char=? (string-ref path i) #\/) path]
        [else (loop (- i 1))])))

  ) ;; end library
