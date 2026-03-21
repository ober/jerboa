#!chezscheme
;;; (std build sbom) — Software Bill of Materials Generation
;;;
;;; Generate SBOM in a structured S-expression format for auditing.
;;; Tracks Scheme dependencies, C library dependencies, and build metadata.

(library (std build sbom)
  (export
    ;; SBOM generation
    make-sbom
    sbom?
    sbom-project
    sbom-version
    sbom-timestamp
    sbom-components
    sbom-build-info

    ;; Component tracking
    make-component
    component?
    component-name
    component-version
    component-type
    component-hash
    component-license

    ;; SBOM operations
    sbom-add-component!
    sbom-add-build-info!
    sbom-find-component

    ;; Serialization
    sbom->sexp
    sexp->sbom
    sbom-write
    sbom-read

    ;; Auto-detection
    detect-scheme-deps
    detect-c-deps
    detect-rust-deps
    detect-all-deps)

  (import (chezscheme))

  ;; ========== Component Record ==========

  (define-record-type (component %make-component component?)
    (sealed #t)
    (fields
      (immutable name component-name)         ;; string
      (immutable version component-version)   ;; string or #f
      (immutable type component-type)         ;; 'library | 'framework | 'application | 'c-library
      (immutable hash component-hash)         ;; string SHA-256 hex or #f
      (immutable license component-license))) ;; string or #f

  (define (make-component name version type . opts)
    (let loop ([o opts] [hash #f] [license #f])
      (if (or (null? o) (null? (cdr o)))
        (%make-component name version type hash license)
        (let ([k (car o)] [v (cadr o)])
          (loop (cddr o)
                (if (eq? k 'hash:) v hash)
                (if (eq? k 'license:) v license))))))

  ;; ========== SBOM Record ==========

  (define-record-type (sbom %make-sbom sbom?)
    (sealed #t)
    (fields
      (immutable project sbom-project)           ;; string
      (immutable version sbom-version)           ;; string
      (immutable timestamp sbom-timestamp)       ;; integer (epoch seconds)
      (mutable components %sbom-components %sbom-set-components!)  ;; list of component
      (mutable build-info %sbom-build-info %sbom-set-build-info!))) ;; alist

  (define (make-sbom project version)
    (%make-sbom project version
                (time-second (current-time 'time-utc))
                '() '()))

  (define (sbom-components s) (%sbom-components s))
  (define (sbom-build-info s) (%sbom-build-info s))

  ;; ========== Operations ==========

  (define (sbom-add-component! s comp)
    (%sbom-set-components! s (cons comp (%sbom-components s))))

  (define (sbom-add-build-info! s key value)
    (%sbom-set-build-info! s (cons (cons key value) (%sbom-build-info s))))

  (define (sbom-find-component s name)
    (let loop ([cs (%sbom-components s)])
      (cond
        [(null? cs) #f]
        [(equal? (component-name (car cs)) name) (car cs)]
        [else (loop (cdr cs))])))

  ;; ========== Serialization ==========

  (define (sbom->sexp s)
    `(sbom
       (project ,(sbom-project s))
       (version ,(sbom-version s))
       (timestamp ,(sbom-timestamp s))
       (build-info ,@(%sbom-build-info s))
       (components
         ,@(map (lambda (c)
                  `(component
                     (name ,(component-name c))
                     (version ,(component-version c))
                     (type ,(component-type c))
                     ,@(if (component-hash c) `((hash ,(component-hash c))) '())
                     ,@(if (component-license c) `((license ,(component-license c))) '())))
                (%sbom-components s)))))

  (define (sexp->sbom sexp)
    (unless (and (pair? sexp) (eq? (car sexp) 'sbom))
      (error 'sexp->sbom "invalid SBOM" sexp))
    (let ([s (make-sbom
               (sexp-field sexp 'project "unknown")
               (sexp-field sexp 'version "0.0.0"))])
      ;; Parse components
      (let ([comps-form (assq 'components (cdr sexp))])
        (when comps-form
          (for-each (lambda (cf)
                      (when (and (pair? cf) (eq? (car cf) 'component))
                        (sbom-add-component! s
                          (%make-component
                            (sexp-field cf 'name "")
                            (sexp-field cf 'version #f)
                            (sexp-field cf 'type 'library)
                            (sexp-field cf 'hash #f)
                            (sexp-field cf 'license #f)))))
                    (cdr comps-form))))
      ;; Parse build-info
      (let ([bi-form (assq 'build-info (cdr sexp))])
        (when bi-form
          (for-each (lambda (kv)
                      (when (pair? kv)
                        (sbom-add-build-info! s (car kv) (cdr kv))))
                    (cdr bi-form))))
      s))

  (define (sexp-field sexp key default)
    (let ([entry (assq key (cdr sexp))])
      (if (and entry (pair? (cdr entry)))
        (cadr entry)
        default)))

  (define (sbom-write s port)
    (pretty-print (sbom->sexp s) port))

  (define (sbom-read port)
    (let ([sexp (read port)])
      (if (eof-object? sexp)
        (error 'sbom-read "empty SBOM file")
        (sexp->sbom sexp))))

  ;; ========== Auto-Detection ==========

  (define (detect-scheme-deps libdirs)
    ;; Scan library directories for .sls files.
    ;; Returns list of (name . path) pairs.
    (let ([results '()])
      (for-each
        (lambda (dir)
          (guard (exn [#t #f])
            (when (file-directory? dir)
              (let-values ([(to-stdin from-stdout from-stderr pid)
                            (open-process-ports
                              (string-append "find " dir " -name '*.sls' -type f 2>/dev/null")
                              (buffer-mode block)
                              (make-transcoder (utf-8-codec)))])
                (close-port to-stdin)
                (let loop ()
                  (let ([line (get-line from-stdout)])
                    (unless (eof-object? line)
                      (set! results (cons (cons (path->lib-name line) line) results))
                      (loop))))
                (close-port from-stdout)
                (close-port from-stderr)))))
        libdirs)
      results))

  (define (path->lib-name path)
    ;; Convert path like "/lib/std/crypto/random.sls" to "std/crypto/random"
    (let* ([base (if (string-suffix? ".sls" path)
                   (substring path 0 (- (string-length path) 4))
                   path)]
           ;; Find last /lib/ segment
           [lib-idx (string-find-last base "/lib/")])
      (if lib-idx
        (substring base (+ lib-idx 5) (string-length base))
        base)))

  (define (detect-c-deps build-file)
    ;; Parse a build.ss or Makefile for -l flags.
    ;; Returns list of C library names.
    (guard (exn [#t '()])
      (if (file-exists? build-file)
        (let ([content (call-with-input-file build-file get-string-all)])
          (extract-l-flags content))
        '())))

  (define (extract-l-flags content)
    ;; Extract -lXXX flags from content.
    (let ([n (string-length content)])
      (let loop ([i 0] [results '()])
        (cond
          [(>= (+ i 2) n) (reverse results)]
          [(and (char=? (string-ref content i) #\-)
                (char=? (string-ref content (+ i 1)) #\l)
                (or (= i 0)
                    (char-whitespace? (string-ref content (- i 1)))
                    (char=? (string-ref content (- i 1)) #\")))
           (let ([end (let find-end ([j (+ i 2)])
                        (if (or (>= j n) (char-whitespace? (string-ref content j))
                                (char=? (string-ref content j) #\"))
                          j
                          (find-end (+ j 1))))])
             (loop end (cons (substring content (+ i 2) end) results)))]
          [else (loop (+ i 1) results)]))))

  ;; ========== Rust/Cargo Dependency Detection ==========

  (define (detect-rust-deps project-dir)
    ;; Parse Cargo.lock for crate dependencies.
    ;; Falls back to Cargo.toml if no lock file.
    ;; Returns list of (name version) pairs.
    (let ([lock-file (string-append project-dir "/Cargo.lock")]
          [toml-file (string-append project-dir "/Cargo.toml")])
      (cond
        [(file-exists? lock-file)
         (parse-cargo-lock lock-file)]
        [(file-exists? toml-file)
         (parse-cargo-toml-deps toml-file)]
        [else '()])))

  (define (parse-cargo-lock path)
    ;; Parse Cargo.lock [[package]] entries.
    ;; Format:
    ;;   [[package]]
    ;;   name = "crate-name"
    ;;   version = "1.2.3"
    (guard (exn [#t '()])
      (let ([content (call-with-input-file path get-string-all)])
        (let loop ([lines (string-split-lines* content)]
                   [current-name #f]
                   [current-version #f]
                   [results '()])
          (if (null? lines)
            (let ([final (if (and current-name current-version)
                           (cons (list current-name current-version) results)
                           results)])
              (reverse final))
            (let ([line (string-trim-whitespace (car lines))])
              (cond
                ;; New package section
                [(string=? line "[[package]]")
                 (let ([updated (if (and current-name current-version)
                                  (cons (list current-name current-version) results)
                                  results)])
                   (loop (cdr lines) #f #f updated))]
                ;; name = "..."
                [(string-prefix-ci? "name = " line)
                 (loop (cdr lines)
                       (extract-quoted-value line)
                       current-version results)]
                ;; version = "..."
                [(string-prefix-ci? "version = " line)
                 (loop (cdr lines)
                       current-name
                       (extract-quoted-value line)
                       results)]
                [else (loop (cdr lines) current-name current-version results)])))))))

  (define (parse-cargo-toml-deps path)
    ;; Parse [dependencies] section from Cargo.toml.
    ;; Simplified parser: extracts crate-name = "version" pairs.
    (guard (exn [#t '()])
      (let ([content (call-with-input-file path get-string-all)])
        (let loop ([lines (string-split-lines* content)]
                   [in-deps #f]
                   [results '()])
          (if (null? lines)
            (reverse results)
            (let ([line (string-trim-whitespace (car lines))])
              (cond
                ;; Section headers
                [(and (> (string-length line) 0)
                      (char=? (string-ref line 0) #\[))
                 (loop (cdr lines)
                       (or (string=? line "[dependencies]")
                           (string-prefix-ci? "[dependencies." line))
                       results)]
                ;; In dependencies section: name = "version"
                [(and in-deps (> (string-length line) 0)
                      (not (char=? (string-ref line 0) #\#)))
                 (let ([eq-pos (string-index* line #\=)])
                   (if eq-pos
                     (let ([name (string-trim-whitespace
                                   (substring line 0 eq-pos))]
                           [val  (string-trim-whitespace
                                   (substring line (+ eq-pos 1) (string-length line)))])
                       (loop (cdr lines) in-deps
                             (cons (list name (strip-quotes val)) results)))
                     (loop (cdr lines) in-deps results)))]
                [else (loop (cdr lines) in-deps results)])))))))

  (define (detect-all-deps project-dir libdirs)
    ;; Detect all dependency types and return an SBOM.
    ;; project-dir: root of the project
    ;; libdirs: list of Scheme library directories
    (let ([sbom (make-sbom (path-basename project-dir) "0.0.0")])
      ;; Scheme dependencies
      (for-each
        (lambda (dep)
          (sbom-add-component! sbom
            (make-component (car dep) #f 'library)))
        (detect-scheme-deps libdirs))
      ;; C dependencies
      (let ([build-file (string-append project-dir "/build.ss")])
        (for-each
          (lambda (lib)
            (sbom-add-component! sbom
              (make-component lib #f 'c-library)))
          (detect-c-deps build-file)))
      ;; Rust dependencies
      (for-each
        (lambda (dep)
          (sbom-add-component! sbom
            (make-component (car dep) (cadr dep) 'library
                            'license: "unknown")))
        (detect-rust-deps project-dir))
      ;; Build info
      (sbom-add-build-info! sbom 'scheme-implementation
                            (format "~a" (scheme-version)))
      (sbom-add-build-info! sbom 'machine-type
                            (format "~a" (machine-type)))
      sbom))

  ;; ========== Helpers ==========

  (define (string-suffix? suffix str)
    (let ([slen (string-length suffix)]
          [len (string-length str)])
      (and (>= len slen)
           (string=? (substring str (- len slen) len) suffix))))

  (define (string-find-last str needle)
    (let ([slen (string-length str)]
          [nlen (string-length needle)])
      (let loop ([i (- slen nlen)])
        (cond
          [(< i 0) #f]
          [(string=? (substring str i (+ i nlen)) needle) i]
          [else (loop (- i 1))]))))

  (define (string-split-lines* s)
    ;; Split string by newlines, return list of strings.
    (let loop ([i 0] [start 0] [lines '()])
      (cond
        [(= i (string-length s))
         (reverse (if (> i start)
                    (cons (substring s start i) lines)
                    lines))]
        [(char=? (string-ref s i) #\newline)
         (loop (+ i 1) (+ i 1) (cons (substring s start i) lines))]
        [else (loop (+ i 1) start lines)])))

  (define (string-trim-whitespace s)
    (let* ([n (string-length s)]
           [start (let loop ([i 0])
                    (if (or (= i n) (not (char-whitespace? (string-ref s i))))
                      i (loop (+ i 1))))]
           [end (let loop ([i (- n 1)])
                  (if (or (< i start) (not (char-whitespace? (string-ref s i))))
                    (+ i 1) (loop (- i 1))))])
      (substring s start end)))

  (define (string-prefix-ci? prefix str)
    (let ([plen (string-length prefix)]
          [slen (string-length str)])
      (and (>= slen plen)
           (string-ci=? (substring str 0 plen) prefix))))

  (define (string-index* str ch)
    (let loop ([i 0])
      (cond
        [(= i (string-length str)) #f]
        [(char=? (string-ref str i) ch) i]
        [else (loop (+ i 1))])))

  (define (extract-quoted-value line)
    ;; Extract value from: key = "value"
    (let ([eq-pos (string-index* line #\=)])
      (if eq-pos
        (strip-quotes (string-trim-whitespace
                        (substring line (+ eq-pos 1) (string-length line))))
        "")))

  (define (strip-quotes s)
    (let ([n (string-length s)])
      (if (and (>= n 2)
               (char=? (string-ref s 0) #\")
               (char=? (string-ref s (- n 1)) #\"))
        (substring s 1 (- n 1))
        s)))

  (define (path-basename path)
    (let loop ([i (- (string-length path) 1)])
      (cond
        [(< i 0) path]
        [(char=? (string-ref path i) #\/)
         (substring path (+ i 1) (string-length path))]
        [else (loop (- i 1))])))

) ;; end library
