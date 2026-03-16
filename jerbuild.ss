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

(define (read-source-file path)
  ;; Read all top-level S-expressions from a .ss file.
  ;; Returns a list of forms.
  (call-with-input-file path
    (lambda (port)
      (let loop ([forms '()])
        (let ([form (read port)])
          (if (eof-object? form)
            (reverse forms)
            (loop (cons form forms))))))))

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

(define (translate-import spec)
  ;; Translate a single Gerbil import spec to R6RS.
  (cond
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
;;;; Chez exclusion triggers (conditional approach)
;;;; ============================================================

(define *exclusion-triggers*
  ;; Maps import library names to the Chez names they shadow.
  ;; Used to compute (except (chezscheme) ...) per-file.
  '(((jerboa core)    . (make-hash-table hash-table? iota 1+ 1-))
    ((jerboa runtime) . (make-hash-table hash-table? iota 1+ 1-))
    ((std sort)       . (sort sort!))
    ((std format)     . (printf fprintf))
    ((std misc ports) . (with-input-from-string with-output-to-string))
    ((std os path)    . (path-extension path-absolute?))))

(define (compute-exclusions translated-imports)
  ;; Union of all Chez names shadowed by the given imports.
  (let loop ([imports translated-imports] [excls '()])
    (if (null? imports)
      (delete-duplicates excls eq?)
      (let* ([lib-name (unwrap-import-lib (car imports))]
             [match (assoc lib-name *exclusion-triggers*)])
        (loop (cdr imports)
              (if match
                (append (cdr match) excls)
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
  ;; Inject (jerboa core) and (jerboa runtime) if not already present.
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

(define (generate-library library-name exports imports body-forms)
  ;; Produce the complete R6RS library S-expression.
  `(library ,library-name
     (export ,@exports)
     (import ,@imports)
     ,@body-forms))

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

             ;; Translate imports
             [translated-imports (map translate-import import-specs)]

             ;; Add auto-imports
             [with-autos (add-auto-imports translated-imports)]

             ;; Compute Chez exclusions based on what's imported
             [exclusions (compute-exclusions with-autos)]

             ;; Build final import list: (except (chezscheme) ...) first
             [final-imports
              (cons (if (null? exclusions)
                      '(chezscheme)
                      `(except (chezscheme) ,@exclusions))
                    with-autos)]

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
