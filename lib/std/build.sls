#!chezscheme
;;; (std build) — Incremental parallel build system
;;;
;;; Track 22: Automatic dependency discovery, parallel compilation
;;; via native threads, and incremental rebuilds using content hashing.

(library (std build)
  (export
    build-project
    discover-modules
    module-dependencies
    build-dag
    topological-sort
    content-hash
    build-cache-load
    build-cache-save
    module-changed?)

  (import (chezscheme))

  ;; ========== Content Hashing (FNV-1a) ==========

  (define FNV-OFFSET 14695981039346656037)
  (define FNV-PRIME  1099511628211)
  (define FNV-MASK   (- (expt 2 64) 1))

  (define (content-hash str)
    (let ([n (string-length str)])
      (let lp ([i 0] [h FNV-OFFSET])
        (if (>= i n) h
          (lp (+ i 1)
              (bitwise-and
                FNV-MASK
                (* (bitwise-xor h (char->integer (string-ref str i)))
                   FNV-PRIME)))))))

  ;; ========== Module Discovery ==========

  (define (discover-modules src-dir)
    ;; Find all .sls files under src-dir
    (let ([result '()])
      (let scan ([dir src-dir])
        (when (file-directory? dir)
          (for-each
            (lambda (entry)
              (let ([path (string-append dir "/" entry)])
                (cond
                  [(file-directory? path)
                   (unless (member entry '("." ".."))
                     (scan path))]
                  [(string-suffix? ".sls" entry)
                   (set! result (cons path result))]
                  [(string-suffix? ".ss" entry)
                   (set! result (cons path result))])))
            (directory-list dir))))
      (reverse result)))

  (define (string-suffix? suffix str)
    (let ([slen (string-length str)]
          [suflen (string-length suffix)])
      (and (>= slen suflen)
           (string=? (substring str (- slen suflen) slen) suffix))))

  ;; ========== Dependency Extraction ==========

  (define (module-dependencies file-path)
    ;; Parse a library file and extract import module names
    (guard (e [#t '()])
      (let ([forms (call-with-input-file file-path
                     (lambda (port)
                       (let lp ([forms '()])
                         (let ([form (read port)])
                           (if (eof-object? form)
                             (reverse forms)
                             (lp (cons form forms)))))))])
        (let lp ([forms forms])
          (cond
            [(null? forms) '()]
            [(and (pair? (car forms))
                  (eq? (caar forms) 'library))
             (extract-imports (car forms))]
            [else (lp (cdr forms))])))))

  (define (extract-imports lib-form)
    ;; From (library name (export ...) (import spec ...) ...)
    ;; extract the module names from import specs
    (let lp ([rest (cdr lib-form)] [imports '()])
      (cond
        [(null? rest) imports]
        [(and (pair? (car rest)) (eq? (caar rest) 'import))
         (append imports (extract-import-names (cdar rest)))]
        [else (lp (cdr rest) imports)])))

  (define (extract-import-names specs)
    (let lp ([specs specs] [result '()])
      (if (null? specs) result
        (let ([spec (car specs)])
          (lp (cdr specs)
              (cons (import-spec->name spec) result))))))

  (define (import-spec->name spec)
    ;; Handle (except (mod ...) ...), (only (mod ...) ...), (rename (mod ...) ...)
    ;; or plain (mod sub ...)
    (cond
      [(and (pair? spec) (memq (car spec) '(except only rename prefix)))
       (import-spec->name (cadr spec))]
      [(pair? spec) spec]
      [else (list spec)]))

  ;; ========== DAG Construction ==========

  (define (build-dag module-files)
    ;; Returns an association list: ((file . (dep-files ...)) ...)
    ;; Maps file paths to their dependency file paths (that are in module-files)
    (let ([name->file (make-hashtable equal-hash equal?)])
      ;; Build module-name -> file-path mapping
      (for-each
        (lambda (file)
          (let ([name (file->module-name file)])
            (when name
              (hashtable-set! name->file name file))))
        module-files)
      ;; Build dependency edges
      (map
        (lambda (file)
          (let ([deps (module-dependencies file)])
            (cons file
                  (filter-map
                    (lambda (dep-name)
                      (hashtable-ref name->file dep-name #f))
                    deps))))
        module-files)))

  (define (filter-map f lst)
    (let lp ([lst lst] [result '()])
      (if (null? lst) (reverse result)
        (let ([v (f (car lst))])
          (lp (cdr lst) (if v (cons v result) result))))))

  (define (file->module-name file)
    ;; Extract library name from file
    (guard (e [#t #f])
      (call-with-input-file file
        (lambda (port)
          (let ([form (read port)])
            (and (pair? form)
                 (eq? (car form) 'library)
                 (cadr form)))))))

  ;; ========== Topological Sort ==========

  (define (topological-sort dag)
    ;; Kahn's algorithm for topological sort
    ;; Returns files in compilation order
    (let ([in-degree (make-hashtable string-hash string=?)]
          [adj (make-hashtable string-hash string=?)]
          [all-nodes '()])
      ;; Initialize
      (for-each
        (lambda (entry)
          (let ([node (car entry)]
                [deps (cdr entry)])
            (set! all-nodes (cons node all-nodes))
            (unless (hashtable-ref in-degree node #f)
              (hashtable-set! in-degree node 0))
            (for-each
              (lambda (dep)
                (unless (hashtable-ref in-degree dep #f)
                  (hashtable-set! in-degree dep 0))
                (hashtable-set! in-degree node
                  (+ 1 (hashtable-ref in-degree node 0)))
                (hashtable-set! adj dep
                  (cons node (hashtable-ref adj dep '()))))
              deps)))
        dag)
      ;; Find nodes with in-degree 0
      (let ([queue '()]
            [result '()])
        (for-each
          (lambda (node)
            (when (= (hashtable-ref in-degree node 0) 0)
              (set! queue (cons node queue))))
          all-nodes)
        ;; Process
        (let lp ()
          (if (null? queue) (reverse result)
            (let ([node (car queue)])
              (set! queue (cdr queue))
              (set! result (cons node result))
              (for-each
                (lambda (neighbor)
                  (let ([new-deg (- (hashtable-ref in-degree neighbor 0) 1)])
                    (hashtable-set! in-degree neighbor new-deg)
                    (when (= new-deg 0)
                      (set! queue (cons neighbor queue)))))
                (hashtable-ref adj node '()))
              (lp)))))))

  ;; ========== Build Cache ==========

  (define (build-cache-load cache-file)
    ;; Load hash cache from file.
    ;; Serialized as an alist because fasl cannot round-trip hashtables
    ;; with custom hash/equal functions.
    ;; Returns hashtable: file-path -> content-hash
    (guard (e [#t (make-hashtable string-hash string=?)])
      (if (file-exists? cache-file)
        (let ([alist (call-with-port (open-file-input-port cache-file)
                       (lambda (port)
                         (fasl-read port)))])
          (if (list? alist)
            (let ([ht (make-hashtable string-hash string=?)])
              (for-each
                (lambda (pair)
                  (when (and (pair? pair) (string? (car pair)))
                    (hashtable-set! ht (car pair) (cdr pair))))
                alist)
              ht)
            ;; Fallback for old format
            (make-hashtable string-hash string=?)))
        (make-hashtable string-hash string=?))))

  (define (build-cache-save cache-file cache)
    ;; Save as alist for reliable fasl round-trip.
    (guard (e [#t (void)])
      (let ([alist (let-values ([(keys vals) (hashtable-entries cache)])
                     (let lp ([i 0] [acc '()])
                       (if (= i (vector-length keys)) acc
                         (lp (+ i 1)
                             (cons (cons (vector-ref keys i)
                                         (vector-ref vals i))
                                   acc)))))])
        (call-with-port (open-file-output-port cache-file
                          (file-options no-fail))
          (lambda (port)
            (fasl-write alist port))))))

  (define (module-changed? file cache)
    (guard (e [#t #t])
      (let* ([content (call-with-input-file file
                        (lambda (p)
                          (let lp ([chunks '()])
                            (let ([buf (get-string-n p 8192)])
                              (if (eof-object? buf)
                                (apply string-append (reverse chunks))
                                (lp (cons buf chunks)))))))]
             [hash (content-hash content)]
             [old-hash (hashtable-ref cache file #f)])
        (not (eqv? hash old-hash)))))

  ;; ========== Parallel Build ==========

  (define (build-project src-dir . options)
    ;; Main entry point: discover, sort, compile
    (let ([parallel? (extract-opt options 'parallel #t)]
          [incremental? (extract-opt options 'incremental #t)]
          [output (extract-opt options 'output #f)]
          [cache-file (string-append src-dir "/.build-cache.fasl")]
          [verbose? (extract-opt options 'verbose #f)])

      (let* ([files (discover-modules src-dir)]
             [dag (build-dag files)]
             [ordered (topological-sort dag)]
             [cache (if incremental?
                      (build-cache-load cache-file)
                      (make-hashtable string-hash string=?))]
             [to-compile (if incremental?
                           (compute-rebuild-set ordered dag cache)
                           ordered)])

        (when verbose?
          (printf "Found ~a modules, ~a need recompilation~n"
                  (length ordered) (length to-compile)))

        (if (and parallel? (> (length to-compile) 1))
          (compile-parallel to-compile dag cache verbose?)
          (compile-sequential to-compile cache verbose?))

        ;; Save cache
        (when incremental?
          (for-each
            (lambda (file)
              (guard (e [#t (void)])
                (let* ([content (call-with-input-file file get-string-all)]
                       [hash (content-hash content)])
                  (hashtable-set! cache file hash))))
            to-compile)
          (build-cache-save cache-file cache))

        (length to-compile))))

  (define (compute-rebuild-set ordered dag cache)
    ;; Determine which files need recompilation
    ;; A file needs recompilation if it changed or any dependency changed
    (let ([needs-rebuild (make-hashtable string-hash string=?)])
      (for-each
        (lambda (file)
          (let ([deps (cdr (or (assoc file dag) (cons file '())))])
            (when (or (module-changed? file cache)
                      (exists (lambda (dep)
                                (hashtable-ref needs-rebuild dep #f))
                              deps))
              (hashtable-set! needs-rebuild file #t))))
        ordered)
      (filter (lambda (f) (hashtable-ref needs-rebuild f #f)) ordered)))



  (define (compile-sequential files cache verbose?)
    (for-each
      (lambda (file)
        (when verbose?
          (printf "  Compiling ~a~n" file))
        (guard (e [#t
                   (printf "  ERROR compiling ~a: ~a~n" file
                           (if (message-condition? e)
                             (condition-message e)
                             e))])
          (compile-library file)))
      files))

  (define (compile-parallel files dag cache verbose?)
    ;; Group files into levels (all files in a level can compile in parallel)
    (let ([levels (group-by-level files dag)])
      (for-each
        (lambda (level)
          (if (= (length level) 1)
            ;; Single file, compile directly
            (compile-sequential level cache verbose?)
            ;; Multiple files, use threads
            (let ([mutex (make-mutex)]
                  [done (make-condition)]
                  [remaining (length level)]
                  [errors '()])
              (for-each
                (lambda (file)
                  (fork-thread
                    (lambda ()
                      (guard (e [#t
                                 (with-mutex mutex
                                   (set! errors (cons (cons file e) errors)))])
                        (when verbose?
                          (with-mutex mutex
                            (printf "  Compiling ~a (parallel)~n" file)))
                        (compile-library file))
                      (with-mutex mutex
                        (set! remaining (- remaining 1))
                        (when (= remaining 0)
                          (condition-signal done))))))
                level)
              ;; Wait for all threads in this level
              (mutex-acquire mutex)
              (let lp ()
                (unless (= remaining 0)
                  (condition-wait done mutex)
                  (lp)))
              (mutex-release mutex)
              ;; Report errors
              (for-each
                (lambda (err)
                  (printf "  ERROR compiling ~a: ~a~n" (car err)
                          (if (message-condition? (cdr err))
                            (condition-message (cdr err))
                            (cdr err))))
                errors))))
        levels)))

  (define (group-by-level files dag)
    ;; Group files into compilation levels using topological ordering
    ;; Files with no uncompiled dependencies go in the first level, etc.
    (let ([compiled (make-hashtable string-hash string=?)]
          [levels '()])
      (let lp ([remaining files])
        (if (null? remaining)
          (reverse levels)
          (let ([ready (filter
                         (lambda (f)
                           (let ([deps (cdr (or (assoc f dag) (cons f '())))])
                             (for-all (lambda (d)
                                        (or (hashtable-ref compiled d #f)
                                            (not (member d remaining))))
                                      deps)))
                         remaining)])
            (if (null? ready)
              ;; Break cycle by taking first file
              (begin
                (hashtable-set! compiled (car remaining) #t)
                (set! levels (cons (list (car remaining)) levels))
                (lp (cdr remaining)))
              (begin
                (for-each (lambda (f) (hashtable-set! compiled f #t)) ready)
                (set! levels (cons ready levels))
                (lp (filter (lambda (f) (not (member f ready))) remaining)))))))))

  (define (extract-opt opts key default)
    (let lp ([opts opts])
      (cond
        [(null? opts) default]
        [(and (pair? opts) (pair? (cdr opts))
              (eq? (car opts) key))
         (cadr opts)]
        [(pair? opts) (lp (cdr opts))]
        [else default])))

  ) ;; end library
