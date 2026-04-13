#!/usr/bin/env scheme-script
#!chezscheme
;;; jerbuild.ss — Gerbil-style .ss → R6RS .sls compiler
;;;
;;; Transforms Gerbil-style source modules into R6RS library files for
;;; Chez Scheme. Enables writing idiomatic Gerbil source while running
;;; on stock Chez Scheme.
;;;
;;; Usage:
;;;   scheme --libdirs lib --script jerbuild.ss <src-dir> <lib-dir> [--force] [--verbose]

(import (chezscheme)
        (jerboa build))  ;; compute-file-hash, module-changed?

;;;; ============================================================
;;;; CLI
;;;; ============================================================

(define *verbose* #f)
(define *force* #f)

(define (parse-args args)
  (let loop ([args args] [positional '()])
    (cond
      [(null? args)
       (unless (= (length positional) 2)
         (error 'jerbuild "Usage: jerbuild <src-dir> <lib-dir> [--force] [--verbose]"))
       (let ([pos (reverse positional)])
         (values (car pos) (cadr pos)))]
      [(string=? (car args) "--force")
       (set! *force* #t)
       (loop (cdr args) positional)]
      [(string=? (car args) "--verbose")
       (set! *verbose* #t)
       (loop (cdr args) positional)]
      [else
       (loop (cdr args) (cons (car args) positional))])))

(define (log-verbose fmt . args)
  (when *verbose*
    (apply printf fmt args)
    (newline)))

;;;; ============================================================
;;;; String helpers
;;;; ============================================================

(define (string-split-char str ch)
  ;; Split str by character ch, returning list of substrings.
  ;; "std/sugar" #\/ → ("std" "sugar")
  (let ([len (string-length str)])
    (let loop ([i 0] [start 0] [acc '()])
      (cond
        [(>= i len)
         (reverse (cons (substring str start len) acc))]
        [(char=? (string-ref str i) ch)
         (loop (+ i 1) (+ i 1) (cons (substring str start i) acc))]
        [else (loop (+ i 1) start acc)]))))

(define (string-ends-with? str suffix)
  (let ([slen (string-length str)]
        [plen (string-length suffix)])
    (and (>= slen plen)
         (string=? (substring str (- slen plen) slen) suffix))))

(define (string-starts-with? str prefix)
  (let ([slen (string-length str)]
        [plen (string-length prefix)])
    (and (>= slen plen)
         (string=? (substring str 0 plen) prefix))))

;;;; ============================================================
;;;; Path computation
;;;; ============================================================

(define (normalize-dir dir)
  ;; Ensure dir ends with /
  (if (string-ends-with? dir "/")
    dir
    (string-append dir "/")))

(define (path->library-name src-dir file-path)
  ;; src-dir  = "src/"
  ;; file-path = "src/jerboa-emacs/helm.ss"
  ;; Result:   (jerboa-emacs helm)
  (let* ([src-dir (normalize-dir src-dir)]
         [relative (if (string-starts-with? file-path src-dir)
                     (substring file-path (string-length src-dir) (string-length file-path))
                     file-path)]
         ;; strip .ss
         [no-ext (if (string-ends-with? relative ".ss")
                   (substring relative 0 (- (string-length relative) 3))
                   relative)]
         [parts (string-split-char no-ext #\/)])
    (map string->symbol parts)))

(define (compute-output-path lib-dir library-name)
  ;; library-name = (jerboa-emacs helm)
  ;; lib-dir = "lib/"
  ;; Result: "lib/jerboa-emacs/helm.sls"
  (let ([lib-dir (normalize-dir lib-dir)])
    (string-append lib-dir
                   (apply string-append
                     (map (lambda (sym)
                            (string-append (symbol->string sym) "/"))
                          (drop-last library-name)))
                   (symbol->string (last library-name))
                   ".sls")))

(define (last lst)
  (if (null? (cdr lst))
    (car lst)
    (last (cdr lst))))

(define (drop-last lst)
  (if (null? (cdr lst))
    '()
    (cons (car lst) (drop-last (cdr lst)))))

(define (ensure-directory-exists dir)
  ;; Create dir and all parents if they don't exist.
  ;; Pure Scheme implementation to avoid shell injection.
  (let* ([absolute? (and (> (string-length dir) 0)
                         (char=? (string-ref dir 0) #\/))]
         [parts (filter (lambda (p) (not (string=? p "")))
                        (string-split-char dir #\/))])
    (let loop ([parts parts] [path (if absolute? "/" "")])
      (unless (null? parts)
        (let* ([part (car parts)]
               [new-path (cond
                           [(string=? path "") part]
                           [(string=? path "/") (string-append "/" part)]
                           [else (string-append path "/" part)])])
          (when (and (not (string=? new-path ""))
                     (not (file-exists? new-path)))
            (guard (exn [#t #f])
              (mkdir new-path)))
          (loop (cdr parts) new-path))))))

;;;; ============================================================
;;;; File discovery
;;;; ============================================================

(define (discover-ss-files dir)
  ;; Recursively find all .ss files under dir.
  ;; Returns list of absolute file paths.
  ;; Skips hidden directories (starting with ".").
  (let ([dir (let ([d (normalize-dir dir)])
               ;; strip trailing slash for directory-list
               (substring d 0 (- (string-length d) 1)))])
    (let loop ([dirs (list dir)] [result '()])
      (if (null? dirs)
        (reverse result)
        (let ([current (car dirs)]
              [rest (cdr dirs)])
          (let ([entries (guard (exn [#t '()])
                           (directory-list current))])
            (let inner ([entries entries] [subdirs rest] [files result])
              (if (null? entries)
                (loop subdirs files)
                (let* ([entry (car entries)]
                       [full (string-append current "/" entry)])
                  (cond
                    ;; skip hidden
                    [(char=? (string-ref entry 0) #\.)
                     (inner (cdr entries) subdirs files)]
                    [(file-directory? full)
                     (inner (cdr entries) (cons full subdirs) files)]
                    [(and (file-regular? full)
                          (string-ends-with? entry ".ss"))
                     (inner (cdr entries) subdirs (cons full files))]
                    [else
                     (inner (cdr entries) subdirs files)]))))))))))

;;;; ============================================================
;;;; Reading and classifying source forms
;;;; ============================================================

(define (preprocess-brackets str)
  ;; Convert Jerboa/Chez bracket syntax [x y z] → (x y z)
  ;; in source text, while correctly skipping strings, comments,
  ;; and character literals (#\[).
  ;; In Chez Scheme (and Gerbil), [...] is syntactically identical to (...).
  ;; This matches the reader semantics: [let ([x 1]) x] ≡ (let ((x 1)) x).
  (let* ([len (string-length str)]
         [out (open-output-string)])
    (let loop ([i 0]
               [in-string #f]
               [in-line-comment #f])
      (if (>= i len)
        (get-output-string out)
        (let ([ch (string-ref str i)])
          (cond
            ;; Inside a line comment — copy until newline
            [in-line-comment
             (write-char ch out)
             (loop (+ i 1) in-string (not (char=? ch #\newline)))]
            ;; Inside a string — copy, handle escapes
            [in-string
             (write-char ch out)
             (cond
               ;; Escaped character inside string — copy next char verbatim
               [(char=? ch #\\)
                (when (< (+ i 1) len)
                  (write-char (string-ref str (+ i 1)) out))
                (loop (+ i 2) in-string #f)]
               ;; End of string
               [(char=? ch #\")
                (loop (+ i 1) #f #f)]
               [else
                (loop (+ i 1) in-string #f)])]
            ;; Character literal: #\x — copy # \ and the character name verbatim
            ;; Must not convert #\[ or #\] — those are char literals, not list brackets
            [(and (char=? ch #\#)
                  (< (+ i 1) len)
                  (char=? (string-ref str (+ i 1)) #\\))
             (write-char ch out)
             (write-char (string-ref str (+ i 1)) out)
             (if (>= (+ i 2) len)
               (loop (+ i 2) #f #f)
               (let ([nc (string-ref str (+ i 2))])
                 ;; If single non-alphabetic char (like #\[ #\] #\( #\space etc.):
                 ;; write it verbatim and continue WITHOUT going through the bracket handler
                 (if (not (char-alphabetic? nc))
                   (begin
                     (write-char nc out)
                     (loop (+ i 3) #f #f))
                   ;; Alphabetic: read the whole name (e.g. newline, space, nul)
                   (let char-loop ([j (+ i 2)])
                     (if (>= j len)
                       (loop j #f #f)
                       (let ([ac (string-ref str j)])
                         (if (or (char-whitespace? ac)
                                 (memv ac '(#\( #\) #\[ #\] #\; #\")))
                           (loop j #f #f)
                           (begin
                             (write-char ac out)
                             (char-loop (+ j 1))))))))))]
            ;; Block comment #| ... |#
            [(and (char=? ch #\#)
                  (< (+ i 1) len)
                  (char=? (string-ref str (+ i 1)) #\|))
             (write-char ch out)
             (write-char (string-ref str (+ i 1)) out)
             (let block-loop ([j (+ i 2)] [depth 1])
               (if (or (>= j len) (= depth 0))
                 (loop j #f #f)
                 (let ([bc (string-ref str j)])
                   (cond
                     [(and (char=? bc #\|)
                           (< (+ j 1) len)
                           (char=? (string-ref str (+ j 1)) #\#))
                      (write-char bc out)
                      (write-char (string-ref str (+ j 1)) out)
                      (block-loop (+ j 2) (- depth 1))]
                     [(and (char=? bc #\#)
                           (< (+ j 1) len)
                           (char=? (string-ref str (+ j 1)) #\|))
                      (write-char bc out)
                      (write-char (string-ref str (+ j 1)) out)
                      (block-loop (+ j 2) (+ depth 1))]
                     [else
                      (write-char bc out)
                      (block-loop (+ j 1) depth)]))))]
            ;; Start of line comment
            [(char=? ch #\;)
             (write-char ch out)
             (loop (+ i 1) #f #t)]
            ;; Start of string
            [(char=? ch #\")
             (write-char ch out)
             (loop (+ i 1) #t #f)]
            ;; Empty bracket pair [] → '() (Gerbil empty list literal)
            [(and (char=? ch #\[)
                  (< (+ i 1) len)
                  (char=? (string-ref str (+ i 1)) #\]))
             (display "'()" out)
             (loop (+ i 2) #f #f)]
            ;; Bracket open → (
            [(char=? ch #\[)
             (write-char #\( out)
             (loop (+ i 1) #f #f)]
            ;; Bracket close → )
            [(char=? ch #\])
             (write-char #\) out)
             (loop (+ i 1) #f #f)]
            ;; Everything else — copy verbatim
            [else
             (write-char ch out)
             (loop (+ i 1) #f #f)]))))))

(define (read-source-file path)
  ;; Read all top-level S-expressions from a .ss file.
  ;; Preprocesses Jerboa/Chez bracket syntax [x y z] → (x y z).
  ;; Returns a list of forms.
  (let* ([raw (call-with-input-file path
                (lambda (port)
                  (let ([p (open-output-string)])
                    (let loop ()
                      (let ([ch (read-char port)])
                        (unless (eof-object? ch)
                          (write-char ch p)
                          (loop))))
                    (get-output-string p))))]
         [processed (preprocess-brackets raw)]
         [port (open-input-string processed)])
    (let loop ([forms '()])
      (let ([form (read port)])
        (if (eof-object? form)
          (reverse forms)
          (loop (cons form forms)))))))

(define (classify-forms forms)
  ;; Separate forms into export-specs, import-specs, body-forms.
  ;; Multiple (export ...) and (import ...) forms are merged.
  ;; (declare ...) forms are silently dropped.
  ;; Returns: (values export-specs import-specs body-forms)
  (let loop ([forms forms]
             [exports '()]
             [imports '()]
             [body '()])
    (cond
      [(null? forms)
       ;; exports and imports use append (in-order), body uses cons (reversed)
       (values exports imports (reverse body))]
      [(and (pair? (car forms)) (eq? (caar forms) 'export))
       (loop (cdr forms) (append exports (cdar forms)) imports body)]
      [(and (pair? (car forms)) (eq? (caar forms) 'import))
       (loop (cdr forms) exports (append imports (cdar forms)) body)]
      [(and (pair? (car forms)) (eq? (caar forms) 'declare))
       (loop (cdr forms) exports imports body)]
      [else
       (loop (cdr forms) exports imports (cons (car forms) body))])))

;;;; ============================================================
;;;; Import path translation
;;;; ============================================================

(define (colon-symbol? x)
  (and (symbol? x)
       (let ([s (symbol->string x)])
         (and (> (string-length s) 1)
              (char=? (string-ref s 0) #\:)))))

;; Set before translating each file's imports to resolve ./module relative paths.
(define *current-library-prefix* '())

(define (translate-colon-path sym)
  ;; :std/sugar        → (std sugar)
  ;; :std/srfi/13      → (std srfi srfi-13)
  ;; :jerboa-emacs/core → (jerboa-emacs core)
  (let* ([s (symbol->string sym)]
         [without-colon (substring s 1 (string-length s))]
         [parts (string-split-char without-colon #\/)]
         [symbols (map string->symbol parts)])
    ;; SRFI special case: (std srfi N) → (std srfi srfi-N)
    (if (and (>= (length symbols) 3)
             (eq? (car symbols) 'std)
             (eq? (cadr symbols) 'srfi))
      (let* ([last-sym (list-ref symbols (- (length symbols) 1))]
             [last-str (symbol->string last-sym)]
             [srfi-name (if (string-starts-with? last-str "srfi-")
                          last-str
                          (string-append "srfi-" last-str))])
        (append (list 'std 'srfi) (list (string->symbol srfi-name))))
      symbols)))

(define (translate-relative-import sym)
  ;; ./module → (current-prefix module)
  ;; The current library prefix is set from the file being compiled.
  (let* ([s (symbol->string sym)]
         [module-name (substring s 2 (string-length s))]  ; strip "./"
         [module-sym (string->symbol module-name)])
    ;; Append module name to all but the last element of current prefix
    ;; e.g., prefix=(jerboa-emacs editor), ./pregexp-compat → (jerboa-emacs pregexp-compat)
    (let ([prefix-parts (if (null? *current-library-prefix*)
                          '()
                          (reverse (cdr (reverse *current-library-prefix*))))])
      (append prefix-parts (list module-sym)))))

(define (relative-import-symbol? spec)
  ;; Returns #t if spec is a symbol starting with "./"
  (and (symbol? spec)
       (let ([s (symbol->string spec)])
         (and (>= (string-length s) 2)
              (char=? (string-ref s 0) #\.)
              (char=? (string-ref s 1) #\/)))))

(define (translate-import spec)
  ;; Translate a single Gerbil import spec to R6RS.
  (cond
    ;; ./module — relative import (same package)
    [(relative-import-symbol? spec)
     (translate-relative-import spec)]

    ;; :pkg/module symbol
    [(colon-symbol? spec)
     (translate-colon-path spec)]

    ;; (only-in :pkg/module sym ...)
    [(and (pair? spec) (eq? (car spec) 'only-in))
     (let ([lib (translate-import (cadr spec))]
           [syms (cddr spec)])
       (cons 'only (cons lib syms)))]

    ;; (except-in :pkg/module sym ...)
    [(and (pair? spec) (eq? (car spec) 'except-in))
     (let ([lib (translate-import (cadr spec))]
           [syms (cddr spec)])
       (cons 'except (cons lib syms)))]

    ;; (rename-in :pkg/module (old new) ...)
    [(and (pair? spec) (eq? (car spec) 'rename-in))
     (let ([lib (translate-import (cadr spec))]
           [renames (cddr spec)])
       (cons 'rename (cons lib renames)))]

    ;; Already R6RS list form — pass through
    [(pair? spec) spec]

    ;; Bare symbol (not colon-prefixed) — wrap in list
    [(symbol? spec) (list spec)]

    [else (error 'translate-import "Unknown import spec" spec)]))

(define (unwrap-import-lib spec)
  ;; Extract base library name from import spec, stripping wrappers.
  ;; (only (std sugar) try) → (std sugar)
  ;; (std sugar)            → (std sugar)
  (if (and (pair? spec) (memq (car spec) '(only except rename for)))
    (cadr spec)
    spec))

;;;; ============================================================
;;;; Inter-library conflict resolution
;;;; ============================================================

;; When library A and library B are both imported, the symbols listed
;; should be excluded from library A to avoid "multiple definitions" errors.
;; Format: (lib-A lib-B . (symbol ...))
(define *inter-library-conflicts*
  '(;; std/misc/string re-exports several SRFI-13 identifiers; when both are
    ;; imported, exclude the overlapping ones from SRFI-13.
    ;; SRFI-13 and std/misc/string overlap on these identifiers.
    ;; (string-split and string-empty? are only in misc/string, not SRFI-13)
    ((std srfi srfi-13) (std misc string)
     string-join string-trim
     string-prefix? string-suffix?
     string-contains string-index)
    ;; (std misc process) provides open-process, open-input-process.
    ;; (jerboa core) has compat wrappers for files that don't import misc/process.
    ;; When both are present, exclude the compat from (jerboa core).
    ;; Note: process-status is NOT in (std misc process), so don't exclude it.
    ((jerboa core) (std misc process)
     open-process open-input-process)
    ;; (std srfi srfi-19) provides time->seconds.
    ;; (jerboa core) has a compat wrapper. Prefer srfi-19 when both present.
    ((jerboa core) (std srfi srfi-19)
     time->seconds)
    ;; (std srfi srfi-1) provides iota, any, every, filter-map, take, drop, delete,
    ;; append-map, fold, fold-right, last, delete-duplicates, count, etc.
    ;; (jerboa core) has compat versions. Prefer srfi-1 when both present.
    ((jerboa core) (std srfi srfi-1)
     iota any every filter-map take drop delete
     append-map fold fold-right last delete-duplicates count
     take-while drop-while concatenate list-index)
    ;; (jerboa runtime) provides iota. Prefer srfi-1 when both imported.
    ((jerboa runtime) (std srfi srfi-1)
     iota)
    ;; jerboa-emacs/persist defines fill-column as a getter function.
    ;; jerboa-emacs/editor-text also defines fill-column as a local constant.
    ;; When both are imported, prefer persist's version (exclude from editor-text).
    ((jerboa-emacs editor-text) (jerboa-emacs persist)
     fill-column)))

(define (import-actual-symbols imp)
  ;; Return the symbols actually imported by an import spec, or #f if "all".
  ;; (only lib sym ...) → (sym ...)
  ;; anything else → #f  (meaning: all exports of the library)
  (and (pair? imp) (eq? (car imp) 'only)
       (cddr imp)))

(define (resolve-inter-library-conflicts imports)
  ;; For each entry in *inter-library-conflicts*, if both lib-A and lib-B
  ;; are in imports, wrap lib-A with (except lib-A symbol ...) to drop duplicates.
  ;; When lib-B is imported via (only ...), only the actually imported symbols are
  ;; considered as potential conflicts.
  (let ([base-libs (map unwrap-import-lib imports)])
    (let loop ([rules *inter-library-conflicts*] [result imports])
      (if (null? rules)
        result
        (let* ([rule   (car rules)]
               [lib-a  (car rule)]
               [lib-b  (cadr rule)]
               [syms   (cddr rule)])
          (if (and (member lib-a base-libs)
                   (member lib-b base-libs))
            ;; Find what lib-a and lib-b actually import
            (let* ([lib-a-import (find (lambda (imp)
                                         (equal? (unwrap-import-lib imp) lib-a))
                                       result)]
                   [lib-b-import (find (lambda (imp)
                                         (equal? (unwrap-import-lib imp) lib-b))
                                       result)]
                   [a-syms (import-actual-symbols lib-a-import)]
                   [b-syms (import-actual-symbols lib-b-import)]
                   ;; Effective conflicts: symbols in both lib-a (if only) and lib-b (if only)
                   [effective-syms
                    (filter (lambda (s)
                              (and (or (not a-syms) (memq s a-syms))
                                   (or (not b-syms) (memq s b-syms))))
                            syms)])
              (if (null? effective-syms)
                (loop (cdr rules) result)
                (loop (cdr rules)
                      (map (lambda (imp)
                             (if (equal? (unwrap-import-lib imp) lib-a)
                               ;; Already wrapped? Add more exclusions.
                               (if (and (pair? imp) (eq? (car imp) 'except))
                                 (append imp effective-syms)
                                 `(except ,imp ,@effective-syms))
                               imp))
                           result))))
            (loop (cdr rules) result)))))))

(define *library-known-exports*
  ;; Known exports per library that commonly conflict with local body definitions.
  ;; When the body locally defines a symbol AND imports a library that exports
  ;; that same symbol, we exclude the symbol from the library import.
  ;; (Local definition takes priority — matches Gerbil semantics.)
  '(((std srfi srfi-1) .
     (iota any every filter-map take drop delete
      append-map fold fold-right last delete-duplicates count
      take-while drop-while concatenate list-index
      zip reduce reduce-right not-pair? null-list?
      first second third fourth fifth sixth seventh eighth ninth tenth))
    ((std srfi srfi-13) .
     (string-join string-trim string-trim-right
      string-prefix? string-prefix-ci? string-suffix? string-suffix-ci?
      string-contains string-contains-ci
      string-index string-index-right string-count))
    ((jerboa core) .
     (iota any every filter-map take drop delete
      append-map open-process open-input-process time->seconds))
    ((jerboa runtime) .
     (iota))))

(define (resolve-local-vs-import-conflicts imports body-forms)
  ;; When the body locally defines a symbol that a library imports also exports,
  ;; the local definition wins (Gerbil semantics). Exclude those symbols from
  ;; the offending imports to avoid R6RS "multiple definitions" errors.
  (let ([local-defs (collect-all-local-definitions body-forms)])
    (map (lambda (imp)
           (let* ([lib (unwrap-import-lib imp)]
                  [entry (assoc lib *library-known-exports*)]
                  [conflicts (and entry
                                  (filter (lambda (sym) (memq sym local-defs))
                                          (cdr entry)))])
             (if (and conflicts (not (null? conflicts)))
               (if (and (pair? imp) (eq? (car imp) 'except))
                 ;; Already an except form — add new conflicts, deduplicating
                 (let ([new (filter (lambda (s) (not (memq s (cddr imp)))) conflicts)])
                   (if (null? new) imp (append imp new)))
                 `(except ,imp ,@conflicts))
               imp)))
         imports)))

(define (collect-all-local-definitions body-forms)
  ;; Collect all top-level symbol names defined in body-forms.
  ;; Used for local-vs-import conflict resolution.
  (let loop ([forms body-forms] [names '()])
    (if (null? forms)
      names
      (let ([form (car forms)])
        (loop (cdr forms)
              (if (and (pair? form) (pair? (cdr form)))
                (let ([head (car form)]
                      [second (cadr form)])
                  (cond
                    [(and (memq head '(def define)) (symbol? second))
                     (cons second names)]
                    [(and (memq head '(def define)) (pair? second) (symbol? (car second)))
                     (cons (car second) names)]
                    [else names]))
                names))))))

;;;; ============================================================
;;;; Chez exclusion triggers (conditional approach)
;;;; ============================================================

(define *exclusion-triggers*
  ;; Maps import library names to the Chez names they shadow.
  ;; Used to compute (except (chezscheme) ...) per-file.
  '(((jerboa core)    . (make-hash-table hash-table? iota 1+ 1- getenv
                         path-extension path-absolute?
                         thread? make-mutex mutex? mutex-name))
    ((jerboa runtime) . (make-hash-table hash-table? iota 1+ 1-))
    ((std sort)       . (sort sort!))
    ((std format)     . (printf fprintf))
    ((std os path)    . (path-extension path-absolute?))
    ((std misc atom)  . (atom?))
    ;; srfi-1 redefines iota with SRFI-1 semantics (count [start [step]])
    ((std srfi srfi-1) . (iota))
    ;; std/misc/ports redefines with-input-from-string and with-output-to-string
    ((std misc ports) . (with-input-from-string with-output-to-string))
    ;; jsh/util re-exports and overrides several chezscheme identifiers
    ((jsh util) . (string-downcase string-upcase file-directory? file-regular?))))

;; Chez Scheme built-in names that may be redefined in user code.
;; Only these will be auto-excluded when a local definition shadows them.
;; Covers the most commonly redefined standard names.
(define *chez-shadowing-candidates*
  '(list-head list-tail error void warning format
    sort sort! find filter map for-each
    assoc assq assv member memq memv
    read write display newline
    open-input-file open-output-file close-port
    with-exception-handler raise
    error? condition? condition-message
    string-copy string-append substring
    string-trim string-trim-right
    string-upcase string-downcase string-titlecase
    number->string string->number
    symbol->string string->symbol
    char->integer integer->char
    make-vector vector-ref vector-set! vector-length
    make-string string-ref string-set! string-length
    make-bytevector bytevector-u8-ref bytevector-u8-set!
    call-with-current-continuation call/cc
    values call-with-values
    dynamic-wind
    gensym))

(define (chez-export? sym)
  (memq sym *chez-shadowing-candidates*))

(define (collect-local-defs body-forms)
  ;; Collect top-level symbol names defined in body-forms that shadow chezscheme.
  ;; Only returns symbols actually exported by chezscheme (to avoid invalid except clauses).
  ;; Handles: (def name ...), (def (name ...) ...), (define name ...),
  ;;          (define (name ...) ...), (defstruct name ...)
  (let loop ([forms body-forms] [names '()])
    (if (null? forms)
      names
      (let ([form (car forms)])
        (loop (cdr forms)
              (if (and (pair? form) (pair? (cdr form)))
                (let ([head (car form)]
                      [second (cadr form)])
                  (let ([sym
                         (cond
                           ;; (def name ...) or (define name ...)
                           [(and (memq head '(def define)) (symbol? second))
                            second]
                           ;; (def (name args...) ...) or (define (name args...) ...)
                           [(and (memq head '(def define)) (pair? second) (symbol? (car second)))
                            (car second)]
                           ;; (defstruct name ...) or (defstruct (name parent) ...)
                           [(eq? head 'defstruct)
                            (if (pair? second) (car second) second)]
                           [else #f])])
                    (if (and sym (chez-export? sym))
                      (cons sym names)
                      names)))
                names))))))

(define (compute-exclusions translated-imports)
  ;; Union of all Chez names shadowed by the given imports.
  ;; When an import is (only lib sym ...), only add exclusions for the
  ;; symbols actually imported (not all trigger symbols for that library).
  (let loop ([imports translated-imports] [excls '()])
    (if (null? imports)
      (delete-duplicates excls eq?)
      (let* ([imp     (car imports)]
             [lib-name (unwrap-import-lib imp)]
             [match   (assoc lib-name *exclusion-triggers*)])
        (loop (cdr imports)
              (if match
                ;; If it's an (only lib ...) form, filter to only the imported syms.
                (let ([only-syms (import-actual-symbols imp)]
                      [trigger-syms (cdr match)])
                  (append (if only-syms
                            (filter (lambda (s) (memq s only-syms)) trigger-syms)
                            trigger-syms)
                          excls))
                excls))))))

(define (delete-duplicates lst pred)
  (let loop ([lst lst] [seen '()])
    (cond
      [(null? lst) (reverse seen)]
      [(let check ([s seen])
         (and (pair? s) (or (pred (car lst) (car s)) (check (cdr s)))))
       (loop (cdr lst) seen)]
      [else (loop (cdr lst) (cons (car lst) seen))])))

;;;; ============================================================
;;;; Auto-imports
;;;; ============================================================

(define *auto-imports*
  '((jerboa core)
    (jerboa runtime)))

(define (add-auto-imports translated-imports)
  ;; Always inject (jerboa core) and (jerboa runtime) if not already present.
  ;; Gherkin-generated .sls files confirm these coexist with (std ...) in Docker.
  ;; Identifier conflicts with chezscheme are handled by *exclusion-triggers*.
  (let ([existing-libs (map unwrap-import-lib translated-imports)])
    (let loop ([autos *auto-imports*] [result translated-imports])
      (if (null? autos)
        result
        (if (member (car autos) existing-libs)
          (loop (cdr autos) result)
          (loop (cdr autos) (append result (list (car autos)))))))))

;;;; ============================================================
;;;; Defstruct parsing (for struct-out expansion)
;;;; ============================================================

(define (collect-defstructs body-forms)
  ;; Scan body for (defstruct name (fields ...)) and (defclass ...) forms.
  ;; Returns alist: ((name . (field1 field2 ...)) ...)
  (let loop ([forms body-forms] [structs '()])
    (cond
      [(null? forms) (reverse structs)]
      [(and (pair? (car forms))
            (>= (length (car forms)) 3)
            (memq (caar forms) '(defstruct defclass)))
       (let* ([form (car forms)]
              [name-part (cadr form)]
              [name (if (pair? name-part) (car name-part) name-part)]
              [fields (caddr form)])
         (if (and (symbol? name) (list? fields))
           (loop (cdr forms) (cons (cons name fields) structs))
           (loop (cdr forms) structs)))]
      [else (loop (cdr forms) structs)])))

;;;; ============================================================
;;;; Export expansion
;;;; ============================================================

(define (expand-struct-out name fields)
  ;; Produce all exported symbols for a defstruct:
  ;;   name::t, make-name, name?, name-field, name-field-set! ...
  (let ([ns (symbol->string name)])
    (append
      (list
        (string->symbol (string-append ns "::t"))
        (string->symbol (string-append "make-" ns))
        (string->symbol (string-append ns "?")))
      (map (lambda (f)
             (string->symbol (string-append ns "-" (symbol->string f))))
           fields)
      (map (lambda (f)
             (string->symbol (string-append ns "-" (symbol->string f) "-set!")))
           fields))))

(define (collect-all-definitions body-forms struct-table)
  ;; Collect all top-level definition names from body forms.
  ;; Used for (export #t). Skips private names starting with %.
  (let loop ([forms body-forms] [names '()])
    (cond
      [(null? forms) (reverse names)]

      ;; def / define
      [(and (pair? (car forms))
            (memq (caar forms) '(def define)))
       (let ([second (cadar forms)])
         (cond
           [(pair? second)   (loop (cdr forms) (cons (car second) names))]
           [(symbol? second) (loop (cdr forms) (cons second names))]
           [else             (loop (cdr forms) names)]))]

      ;; def*
      [(and (pair? (car forms)) (eq? (caar forms) 'def*))
       (loop (cdr forms) (cons (cadar forms) names))]

      ;; define-syntax
      [(and (pair? (car forms)) (eq? (caar forms) 'define-syntax))
       (loop (cdr forms) (cons (cadar forms) names))]

      ;; defrule: (defrule (name . pattern) template)
      [(and (pair? (car forms)) (eq? (caar forms) 'defrule))
       (let ([pat (cadar forms)])
         (if (pair? pat)
           (loop (cdr forms) (cons (car pat) names))
           (loop (cdr forms) names)))]

      ;; defrules: (defrules name ...)
      [(and (pair? (car forms)) (eq? (caar forms) 'defrules))
       (loop (cdr forms) (cons (cadar forms) names))]

      ;; defstruct / defclass — expand to all generated names
      [(and (pair? (car forms))
            (memq (caar forms) '(defstruct defclass)))
       (let* ([name-part (cadar forms)]
              [name (if (pair? name-part) (car name-part) name-part)]
              [entry (assq name struct-table)])
         (if entry
           (let ([expanded (expand-struct-out name (cdr entry))])
             (loop (cdr forms) (append (reverse expanded) names)))
           (loop (cdr forms) names)))]

      ;; begin — descend into body
      [(and (pair? (car forms)) (eq? (caar forms) 'begin))
       (let ([inner (collect-all-definitions (cdar (car forms)) struct-table)])
         (loop (cdr forms) (append (reverse inner) names)))]

      ;; defmethod — skip (dispatched via bind-method!, not a top-level binding)
      [(and (pair? (car forms)) (eq? (caar forms) 'defmethod))
       (loop (cdr forms) names)]

      [else (loop (cdr forms) names)])))

(define (private-name? sym)
  ;; Skip names starting with % (Gerbil private convention)
  (let ([s (symbol->string sym)])
    (and (> (string-length s) 0)
         (char=? (string-ref s 0) #\%))))

(define (expand-exports export-specs struct-table body-forms)
  ;; Process export spec list → flat list of symbols.
  ;; Handles: plain symbols, (struct-out name), (rename (old new)), #t.
  (let loop ([specs export-specs] [result '()])
    (cond
      [(null? specs) (reverse result)]

      ;; (struct-out name)
      [(and (pair? (car specs))
            (eq? (caar specs) 'struct-out)
            (= (length (car specs)) 2))
       (let* ([struct-name (cadar specs)]
              [entry (assq struct-name struct-table)])
         (if entry
           (let ([expanded (expand-struct-out struct-name (cdr entry))])
             (loop (cdr specs) (append (reverse expanded) result)))
           (error 'jerbuild
                  (format "struct-out: no defstruct found for ~a in this file" struct-name))))]

      ;; #t — export all top-level definitions, skipping private names
      [(eq? (car specs) #t)
       (let ([all-names (filter (lambda (n) (not (private-name? n)))
                                (collect-all-definitions body-forms struct-table))])
         (loop (cdr specs) (append (reverse all-names) result)))]

      ;; Plain symbol
      [(symbol? (car specs))
       (loop (cdr specs) (cons (car specs) result))]

      ;; (rename (old new)) — keep as-is
      [(and (pair? (car specs)) (eq? (caar specs) 'rename))
       (loop (cdr specs) (cons (car specs) result))]

      [else
       (error 'jerbuild (format "Unknown export spec: ~s" (car specs)))])))

;;;; ============================================================
;;;; Output generation
;;;; ============================================================

(define (definition-form? form)
  ;; Returns #t if this form is a definition (vs expression).
  ;; In R6RS library bodies, all definitions must precede expressions.
  (and (pair? form)
       (memq (car form) '(define define-syntax define-values define-record-type
                          def def* defrule defrules
                          defstruct defclass defmethod))))

(define (reorder-body-forms forms)
  ;; Partition into definitions and expressions, emitting defs first.
  ;; This ensures R6RS library body compliance.
  (let loop ([forms forms] [defs '()] [exprs '()])
    (if (null? forms)
      (append (reverse defs) (reverse exprs))
      (if (definition-form? (car forms))
        (loop (cdr forms) (cons (car forms) defs) exprs)
        (loop (cdr forms) defs (cons (car forms) exprs))))))

(define (transform-set!-fields form)
  ;; Recursively transform (set! (f obj) val) → (f-set! obj val)
  ;; This handles Gerbil's struct field mutation idiom.
  (cond
    [(not (pair? form)) form]
    [(and (eq? (car form) 'set!)
          (pair? (cdr form))
          (pair? (cadr form))
          (symbol? (caadr form)))
     ;; (set! (f arg ...) val) → (f-set! arg ... val)
     ;; Special case: car/cdr use Chez's set-car!/set-cdr! names.
     (let* ([accessor (caadr form)]
            [args     (cdadr form)]
            [val      (caddr form)]
            [setter   (case accessor
                        [(car)  'set-car!]
                        [(cdr)  'set-cdr!]
                        [else   (string->symbol (string-append (symbol->string accessor) "-set!"))])])
       `(,setter ,@(map transform-set!-fields args)
                 ,(transform-set!-fields val)))]
    [else
     ;; Recursively walk the list, preserving improper list tails (dotted pairs)
     (let loop ([lst form])
       (cond
         [(null? lst) '()]
         [(pair? lst) (cons (transform-set!-fields (car lst)) (loop (cdr lst)))]
         [else lst]))]))

(define (transform-set!-fields-in-body forms)
  (map transform-set!-fields forms))

(define (quote-bare-vectors form)
  ;; In Gerbil, #(a b c) is a self-evaluating vector literal.
  ;; In Chez R6RS, vectors must be quoted: '#(a b c).
  ;; This transform wraps any bare vector values in (quote ...).
  (cond
    [(vector? form) `(quote ,form)]
    [(not (pair? form)) form]
    ;; Don't recurse into (quote ...) — already quoted
    [(eq? (car form) 'quote) form]
    [else
     ;; Recurse, preserving improper list tails
     (let loop ([lst form])
       (cond
         [(null? lst) '()]
         [(pair? lst) (cons (quote-bare-vectors (car lst)) (loop (cdr lst)))]
         [else lst]))]))

(define (quote-bare-vectors-in-body forms)
  (map quote-bare-vectors forms))

;; Keyword symbols (symbols ending in ':') in Gerbil call sites are passed as
;; literal keyword markers. In Chez R6RS they must be quoted.
(define (keyword-sym? sym)
  (and (symbol? sym)
       (let ([s (symbol->string sym)])
         (and (> (string-length s) 0)
              (char=? (string-ref s (- (string-length s) 1)) #\:)))))

;; Special forms where keyword-like symbols appear as syntax (not call-site args)
(define *non-call-heads*
  '(quote quasiquote unquote unquote-splicing
    let let* letrec letrec* let-values let*-values
    lambda case-lambda define define-syntax define-values define-record-type
    begin cond case and or when unless do
    if set! syntax-rules syntax-case with-syntax
    def def* defrule defrules defstruct defclass defmethod
    defmacro match try catch finally while until
    let-hash hash hash-eq import export library meta))

(define (quote-keyword-args form)
  ;; In a call (f a1 a2 kw: v ...), quote any kw: symbols in argument positions.
  ;; Does not quote keyword-like symbols in car position (function name).
  ;; Does not recurse into quote forms.
  ;; Special handling for def/lambda: the parameter list is NOT a call.
  (cond
    [(not (pair? form)) form]
    [(eq? (car form) 'quote) form]
    ;; (def (name params...) body...) — skip the parameter list (cadr), recurse into body
    [(and (memq (car form) '(def def*))
          (pair? (cdr form))
          (pair? (cadr form)))
     (cons (car form)
           (cons (cadr form)  ; parameter list — don't quote keywords here
                 (map quote-keyword-args (cddr form))))]
    ;; (lambda (params...) body...) — skip parameter list
    [(and (memq (car form) '(lambda case-lambda))
          (pair? (cdr form)))
     (cons (car form)
           (cons (cadr form)
                 (map quote-keyword-args (cddr form))))]
    [(and (symbol? (car form))
          (memq (car form) *non-call-heads*))
     ;; Other special form — recurse into subforms but don't quote keyword args directly
     (let loop ([lst form])
       (cond
         [(null? lst) '()]
         [(pair? lst) (cons (quote-keyword-args (car lst)) (loop (cdr lst)))]
         [else lst]))]
    [(and (pair? form) (keyword-sym? (car form)))
     ;; Gerbil keyword plist used as data: (path: "git" arguments: ...) →
     ;; (list 'path: "git" 'arguments: ...) so it evaluates to a proper alist.
     (cons 'list
           (let loop ([kv form])
             (cond
               [(null? kv) '()]
               [(keyword-sym? (car kv))
                (cons `(quote ,(car kv))
                      (if (pair? (cdr kv))
                        (cons (quote-keyword-args (cadr kv))
                              (loop (cddr kv)))
                        '()))]
               [else (cons (quote-keyword-args (car kv)) (loop (cdr kv)))])))]
    [else
     ;; Regular call or list traversal: quote keyword symbols in all positions.
     ;; If the head is itself a pair (e.g. a binding in a let* binding list),
     ;; recurse into it too so keywords inside bindings are also quoted.
     (cons (if (pair? (car form))
             (quote-keyword-args (car form))
             (car form))
           (let loop ([args (cdr form)])
             (cond
               [(null? args) '()]
               [(pair? args)
                (let ([arg (car args)])
                  (cons (if (keyword-sym? arg)
                          `(quote ,arg)
                          (quote-keyword-args arg))
                        (loop (cdr args))))]
               [else args])))]))

(define (quote-keyword-args-in-body forms)
  (map quote-keyword-args forms))

(define (find-set!-vars forms)
  ;; Collect all variable names that appear as (set! var ...) anywhere in forms.
  (let loop ([forms forms] [acc '()])
    (cond
      [(null? forms) acc]
      [(not (pair? forms)) acc]
      [(pair? (car forms))
       (let ([form (car forms)])
         (let ([inner
                (cond
                  ;; (set! var expr)
                  [(and (eq? (car form) 'set!)
                        (pair? (cdr form))
                        (symbol? (cadr form)))
                   (cons (cadr form) (find-set!-vars (cddr form)))]
                  ;; Recurse into any nested pair
                  [else (find-set!-vars form)])])
           (loop (cdr forms) (append inner acc))))]
      [else (loop (cdr forms) acc)])))

(define (make-mutable-cell-name var)
  (string->symbol (string-append (symbol->string var) "--cell")))

(define (earmuff-variable? sym)
  ;; Gerbil convention: *name* signals a mutable global variable
  (let ([s (symbol->string sym)])
    (and (> (string-length s) 2)
         (char=? (string-ref s 0) #\*)
         (char=? (string-ref s (- (string-length s) 1)) #\*))))

(define (locally-defined-vars body-forms)
  ;; Collect all variable names that are locally defined (via def/define)
  ;; in the body, regardless of whether they shadow chezscheme exports.
  (let loop ([forms body-forms] [names '()])
    (if (null? forms)
      names
      (let ([form (car forms)])
        (loop (cdr forms)
              (if (and (pair? form) (pair? (cdr form)))
                (let ([head (car form)]
                      [second (cadr form)])
                  (let ([sym
                         (cond
                           [(and (memq head '(def define)) (symbol? second)) second]
                           [(and (memq head '(def define)) (pair? second) (symbol? (car second)))
                            (car second)]
                           [else #f])])
                    (if sym (cons sym names) names)))
                names))))))

(define (wrap-mutable-exports exports body-forms)
  ;; For exported variables that are set! in the body OR follow the earmuff
  ;; naming convention (*name*) AND are locally defined in the body, replace
  ;; the plain define with a vector cell + identifier-syntax wrapper.
  ;; The identifier-syntax form allows cross-library set! to work (Chez
  ;; identifier-syntax captures the cell in the defining library's scope).
  ;; Returns (values new-exports new-body-forms).
  (let* ([assigned    (find-set!-vars body-forms)]
         [local-defs  (locally-defined-vars body-forms)]
         [var-exports (filter symbol? exports)]
         [mutable    (filter (lambda (v)
                               (or (memq v assigned)
                                   (and (earmuff-variable? v)
                                        (memq v local-defs))))
                             var-exports)])
    (if (null? mutable)
      (values exports body-forms)
      (let* ([new-body
              (let loop ([forms body-forms] [acc '()])
                (if (null? forms)
                  (let* ([cell-defs
                          (map (lambda (v)
                                 (let ([cell (make-mutable-cell-name v)])
                                   `(define-syntax ,v
                                      (identifier-syntax
                                        [id (vector-ref ,cell 0)]
                                        [(set! id val) (vector-set! ,cell 0 val)]))))
                               mutable)])
                    (append (reverse acc) cell-defs))
                  (let ([form (car forms)])
                    ;; Replace (define var init) or (def var init) for mutable vars
                    (let ([new-form
                           (if (and (pair? form)
                                    (memq (car form) '(define def))
                                    (pair? (cdr form))
                                    (symbol? (cadr form))
                                    (memq (cadr form) mutable))
                             ;; Convert: (define *x* init) → (define *x*--cell (vector init))
                             (let* ([var (cadr form)]
                                    [cell (make-mutable-cell-name var)]
                                    [init (if (pair? (cddr form)) (caddr form) '(void))])
                               `(define ,cell (vector ,init)))
                             form)])
                      (loop (cdr forms) (cons new-form acc))))))])
        (values exports new-body)))))

(define (generate-library library-name exports imports body-forms)
  ;; Produce the complete R6RS library S-expression.
  ;; 1. Transform (set! (f obj) val) → (f-set! obj val)
  ;; 2. Wrap exported+assigned variables in identifier-syntax cells.
  ;; 3. Reorder body so all definitions precede expressions (R6RS requirement).
  ;; 4. Resolve local-def vs import conflicts (local definition wins).
  (let* ([transformed-body (quote-bare-vectors-in-body
                              (quote-keyword-args-in-body
                                (transform-set!-fields-in-body body-forms)))]
         ;; Resolve: locally-defined symbols exclude from their source libraries
         [resolved-imports (resolve-local-vs-import-conflicts imports body-forms)])
    (let-values ([(new-exports new-body) (wrap-mutable-exports exports transformed-body)])
      (let ([ordered (reorder-body-forms new-body)])
        `(library ,library-name
           (export ,@new-exports)
           (import ,@resolved-imports)
           ,@ordered)))))

(define (write-library-file output-path library-form src-path)
  (ensure-directory-exists
    (let ([parts (string-split-char output-path #\/)])
      (apply string-append
        (map (lambda (p) (string-append p "/"))
             (drop-last parts)))))
  (call-with-output-file output-path
    (lambda (port)
      (display "#!chezscheme\n" port)
      (display ";;; Generated by jerbuild — DO NOT EDIT\n" port)
      (display (format ";;; Source: ~a\n\n" src-path) port)
      (pretty-print library-form port))
    'replace))

;;;; ============================================================
;;;; Hash cache for incremental builds
;;;; ============================================================

(define *hash-cache-file* ".jerbuild-hashes")

(define (hash-cache-path src-dir)
  (string-append (normalize-dir src-dir) *hash-cache-file*))

(define (load-hash-cache src-dir)
  (let ([cache (make-hashtable string-hash string=?)]
        [path (hash-cache-path src-dir)])
    (when (file-exists? path)
      (guard (exn [#t #f])
        (let ([data (call-with-input-file path read)])
          (when (list? data)
            (for-each
              (lambda (entry)
                (when (and (pair? entry)
                           (string? (car entry))
                           (string? (cdr entry)))
                  (hashtable-set! cache (car entry) (cdr entry))))
              data)))))
    cache))

(define (save-hash-cache src-dir cache)
  (let ([path (hash-cache-path src-dir)])
    (guard (exn [#t #f])
      (call-with-output-file path
        (lambda (port)
          (let-values ([(keys vals) (hashtable-entries cache)])
            (let ([entries (map cons (vector->list keys) (vector->list vals))])
              (pretty-print entries port))))
        'replace))))

(define (file-changed? file-path hash-cache)
  (or *force*
      (let ([current (compute-file-hash file-path)]
            [stored (hashtable-ref hash-cache file-path #f)])
        (not (equal? current stored)))))

;;;; ============================================================
;;;; Transform a single file
;;;; ============================================================

(define (transform-file ss-path src-dir lib-dir hash-cache)
  ;; Returns #t on success, raises on error.
  (let* ([library-name (path->library-name src-dir ss-path)]
         [output-path (compute-output-path lib-dir library-name)]
         [forms (read-source-file ss-path)])
    (let-values ([(export-specs import-specs body-forms)
                  (classify-forms forms)])

      ;; Require explicit exports
      (when (null? export-specs)
        (error 'jerbuild
               (format "~a: no (export ...) form found" ss-path)))

      ;; Parse defstructs for struct-out expansion
      (let* ([struct-table (collect-defstructs body-forms)]

             ;; Expand exports
             [expanded-exports (expand-exports export-specs struct-table body-forms)]

             ;; Set current library prefix for relative import resolution
             [_ (set! *current-library-prefix* library-name)]

             ;; Translate imports
             [translated-imports (map translate-import import-specs)]

             ;; Add auto-imports
             [with-autos (add-auto-imports translated-imports)]

             ;; Compute Chez exclusions based on what's imported
             [import-exclusions (compute-exclusions with-autos)]

             ;; Also exclude locally-defined names that shadow chezscheme
             [local-defs (collect-local-defs body-forms)]
             [exclusions (delete-duplicates
                           (append import-exclusions local-defs)
                           eq?)]

             ;; Build final import list: (except (chezscheme) ...) first
             [pre-final
              (cons (if (null? exclusions)
                      '(chezscheme)
                      `(except (chezscheme) ,@exclusions))
                    with-autos)]

             ;; Resolve inter-library conflicts (e.g. srfi-13 vs misc/string)
             [final-imports (resolve-inter-library-conflicts pre-final)]

             ;; Assemble library form
             [library-form (generate-library library-name
                                             expanded-exports
                                             final-imports
                                             body-forms)])

        ;; Write output
        (write-library-file output-path library-form ss-path)
        (printf "  ~a → ~a\n" ss-path output-path)

        ;; Update hash
        (let ([h (compute-file-hash ss-path)])
          (when h (hashtable-set! hash-cache ss-path h)))

        #t))))

;;;; ============================================================
;;;; Main build loop
;;;; ============================================================

(define (jerbuild src-dir lib-dir)
  (let ([ss-files (discover-ss-files src-dir)]
        [hash-cache (load-hash-cache src-dir)]
        [processed 0]
        [skipped 0]
        [errors 0])

    (for-each
      (lambda (ss-path)
        (if (file-changed? ss-path hash-cache)
          (guard (exn [#t
                       (set! errors (+ errors 1))
                       (printf "ERROR: ~a:\n" ss-path)
                       (display-condition exn (current-output-port))
                       (newline)])
            (log-verbose "Processing: ~a" ss-path)
            (transform-file ss-path src-dir lib-dir hash-cache)
            (set! processed (+ processed 1)))
          (begin
            (log-verbose "Skipped (unchanged): ~a" ss-path)
            (set! skipped (+ skipped 1)))))
      ss-files)

    (save-hash-cache src-dir hash-cache)

    (printf "\njerbuild: ~a processed, ~a skipped, ~a errors (of ~a total)\n"
            processed skipped errors (length ss-files))

    (when (> errors 0)
      (exit 1))))

;;;; ============================================================
;;;; Entry point
;;;; ============================================================

(let-values ([(src-dir lib-dir) (parse-args (command-line-arguments))])
  (jerbuild src-dir lib-dir))
