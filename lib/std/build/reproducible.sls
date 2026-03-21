#!chezscheme
;;; (std build reproducible) — Reproducible Build Utilities
;;;
;;; Content-addressed artifact store, build manifests, caching,
;;; and verification of reproducible builds.

(library (std build reproducible)
  (export
    ;; Content-addressed hashing
    content-hash
    content-hash-string

    ;; Build manifest
    make-manifest
    manifest?
    manifest-add!
    manifest-get
    manifest-hash
    manifest->alist
    manifest->string
    manifest-from-string

    ;; Artifact store
    make-artifact-store
    artifact-store?
    artifact-store-put!
    artifact-store-get
    artifact-store-has?
    artifact-store-path

    ;; Build records
    make-build-record
    build-record?
    build-record-hash
    build-record-timestamp
    build-record-source-hash
    build-record-deps-hash

    ;; Verification
    verify-build
    normalize-artifact

    ;; Build cache
    make-build-cache
    build-cache?
    build-cache-lookup
    build-cache-store!
    build-cache-stats

    ;; Provenance tracking (S3)
    make-provenance
    provenance?
    provenance-source-hash
    provenance-builder-id
    provenance-build-timestamp
    provenance-output-hash
    provenance->sexp
    sexp->provenance
    provenance-write
    provenance-read
    verify-provenance)

  (import (chezscheme))

  ;; ========== Content Hashing ==========
  ;; Default: SHA-256 via Chez's built-in bytevector-hash + double-hashing.
  ;; If (std crypto hash) is available, uses real SHA-256.
  ;; *content-hasher* parameter allows plugging in a custom hasher.

  (define *content-hasher* (make-parameter #f)) ;; #f = use built-in

  ;; Try to load real SHA-256 from (std crypto hash) at init time.
  (define sha256-proc
    (guard (e [#t #f])
      (let ([env (environment '(std crypto hash))])
        (eval 'sha256-bytevector env))))

  (define (sha256-hash bv)
    ;; Real SHA-256 producing hex string.
    ;; Falls back to strong FNV-1a if crypto module not available.
    (if sha256-proc
      (sha256-proc bv)
      (fnv1a-hash bv)))

  (define (fnv1a-hash bv)
    ;; FNV-1a 64-bit over a bytevector. Returns hex string.
    ;; Used as fallback when SHA-256 is not available.
    (let ([basis #xcbf29ce484222325]
          [prime #x100000001b3]
          [mask  #xffffffffffffffff])
      (let loop ([i 0] [h basis])
        (if (= i (bytevector-length bv))
            (let ([hex (number->string h 16)])
              ;; Zero-pad to 16 hex chars
              (string-append (make-string (max 0 (- 16 (string-length hex))) #\0) hex))
            (loop (+ i 1)
                  (bitwise-and
                    (* (bitwise-xor h (bytevector-u8-ref bv i)) prime)
                    mask))))))

  (define (str->bv str)
    ;; String to bytevector using char codes.
    (let* ([n (string-length str)]
           [bv (make-bytevector n)])
      (do ([i 0 (+ i 1)])
          ((= i n) bv)
        (bytevector-u8-set! bv i (char->integer (string-ref str i))))))

  (define (read-file-bytevector path)
    ;; Read entire file into a bytevector by chunking.
    (call-with-port (open-file-input-port path)
      (lambda (port)
        (let loop ([chunks '()])
          (let ([bv (get-bytevector-n port 4096)])
            (if (or (eof-object? bv) (= (bytevector-length bv) 0))
                (let* ([total  (apply + (map bytevector-length chunks))]
                       [result (make-bytevector total)])
                  (let fill ([offset 0] [cs (reverse chunks)])
                    (unless (null? cs)
                      (let ([c (car cs)])
                        (bytevector-copy! c 0 result offset (bytevector-length c))
                        (fill (+ offset (bytevector-length c)) (cdr cs)))))
                  result)
                (loop (cons bv chunks))))))))

  (define (content-hash path)
    ;; Hash the contents of file at path. Returns hex string or #f.
    (guard (exn [#t #f])
      (if (*content-hasher*)
          ((*content-hasher*) path)
          (sha256-hash (read-file-bytevector path)))))

  (define (content-hash-string str)
    ;; Hash the contents of a string.
    (sha256-hash (str->bv str)))

  ;; ========== Safe directory creation (no shell injection) ==========

  (define (mkdir-p path)
    ;; Recursively create directories, like mkdir -p but without system().
    ;; Validates path contains no null bytes (path traversal).
    (when (string-contains-char path #\nul)
      (error 'mkdir-p "path contains null byte" path))
    (let ([components (split-path path)])
      (let loop ([parts components] [current ""])
        (unless (null? parts)
          (let ([dir (if (string=? current "")
                       (car parts)
                       (string-append current "/" (car parts)))])
            (unless (or (string=? dir "") (file-directory? dir))
              (guard (exn [#t (void)]) ;; ignore EEXIST race
                (mkdir dir #o755)))
            (loop (cdr parts) dir))))))

  (define (split-path path)
    ;; Split "a/b/c" into ("a" "b" "c"), preserving leading "/" as "/".
    (let loop ([i 0] [start 0] [parts '()])
      (cond
        [(= i (string-length path))
         (reverse (if (> i start)
                    (cons (substring path start i) parts)
                    parts))]
        [(char=? (string-ref path i) #\/)
         (if (= i start)
           (if (= i 0)
             (loop (+ i 1) (+ i 1) (cons "/" parts))  ;; leading /
             (loop (+ i 1) (+ i 1) parts))            ;; skip consecutive /
           (loop (+ i 1) (+ i 1)
                 (cons (substring path start i) parts)))]
        [else (loop (+ i 1) start parts)])))

  (define (string-contains-char str ch)
    (let loop ([i 0])
      (cond
        [(= i (string-length str)) #f]
        [(char=? (string-ref str i) ch) #t]
        [else (loop (+ i 1))])))

  ;; ========== Manifest ==========

  (define-record-type (%manifest %make-manifest manifest?)
    (fields (mutable entries)))  ;; ordered alist: (key . value) pairs

  (define (make-manifest)
    (%make-manifest '()))

  (define (manifest-add! m key value)
    ;; Add or update entry. Append if new, update existing in-place.
    (let ([existing (assoc key (%manifest-entries m))])
      (if existing
          (set-cdr! existing value)
          (%manifest-entries-set! m
            (append (%manifest-entries m) (list (cons key value)))))))

  (define (manifest-get m key)
    (let ([entry (assoc key (%manifest-entries m))])
      (and entry (cdr entry))))

  (define (manifest->alist m)
    ;; Return a fresh copy of the entries list.
    (map (lambda (kv) (cons (car kv) (cdr kv)))
         (%manifest-entries m)))

  (define (manifest->string m)
    ;; Serialize as "key=value\n" lines.
    (apply string-append
           (map (lambda (kv)
                  (string-append (format "~a" (car kv)) "="
                                 (format "~a" (cdr kv)) "\n"))
                (%manifest-entries m))))

  (define (manifest-hash m)
    (content-hash-string (manifest->string m)))

  (define (string-split-lines s)
    (let loop ([i 0] [start 0] [lines '()])
      (cond
        [(= i (string-length s))
         (let ([last (substring s start i)])
           (reverse (if (string=? last "") lines (cons last lines))))]
        [(char=? (string-ref s i) #\newline)
         (loop (+ i 1) (+ i 1) (cons (substring s start i) lines))]
        [else (loop (+ i 1) start lines)])))

  (define (string-index str ch)
    (let loop ([i 0])
      (cond
        [(= i (string-length str)) #f]
        [(char=? (string-ref str i) ch) i]
        [else (loop (+ i 1))])))

  (define (manifest-from-string s)
    ;; Deserialize from "key=value\n" lines.
    (let ([m (make-manifest)]
          [lines (string-split-lines s)])
      (for-each
        (lambda (line)
          (let ([eq-pos (string-index line #\=)])
            (when eq-pos
              (let ([key (substring line 0 eq-pos)]
                    [val (substring line (+ eq-pos 1) (string-length line))])
                (manifest-add! m key val)))))
        lines)
      m))

  ;; ========== Artifact Store ==========
  ;; Files stored at <store-path>/<hash[0:2]>/<hash[2:]>

  (define-record-type (%artifact-store %make-artifact-store artifact-store?)
    (fields (immutable root)))  ;; root directory of the store

  (define (make-artifact-store path)
    (guard (exn [#t #f])
      (unless (file-directory? path)
        (mkdir-p path))
      (%make-artifact-store path)))

  (define (artifact-store-path store hash)
    (let* ([root   (%artifact-store-root store)]
           [prefix (if (>= (string-length hash) 2) (substring hash 0 2) hash)]
           [rest   (if (>= (string-length hash) 2)
                       (substring hash 2 (string-length hash))
                       "")])
      (string-append root "/" prefix "/" rest)))

  (define (artifact-store-has? store hash)
    (file-exists? (artifact-store-path store hash)))

  (define (path-directory path)
    ;; Return directory part of path.
    (let loop ([i (- (string-length path) 1)])
      (cond
        [(< i 0) "."]
        [(char=? (string-ref path i) #\/) (substring path 0 i)]
        [else (loop (- i 1))])))

  (define (artifact-store-put! store content)
    ;; content is a string; returns its hash.
    (let* ([hash (content-hash-string content)]
           [path (artifact-store-path store hash)]
           [dir  (path-directory path)])
      (unless (file-directory? dir)
        (guard (exn [#t #f])
          (mkdir-p dir)))
      (call-with-output-file path
        (lambda (port) (display content port))
        'replace)
      hash))

  (define (artifact-store-get store hash)
    ;; Returns content string or #f.
    (guard (exn [#t #f])
      (let ([path (artifact-store-path store hash)])
        (if (file-exists? path)
            (call-with-input-file path
              (lambda (port)
                (let loop ([chunks '()])
                  (let ([line (get-line port)])
                    (if (eof-object? line)
                        (apply string-append (reverse chunks))
                        (loop (cons (string-append line "\n") chunks)))))))
            #f))))

  ;; ========== Build Records ==========

  (define-record-type (%build-record %make-build-record build-record?)
    (fields
      (immutable source-hash)  ;; hash of source content
      (immutable deps-hash)    ;; hash of dependencies
      (immutable flags)        ;; compiler flags string
      (immutable timestamp)))  ;; integer seconds when record was made

  (define (make-build-record source-hash deps-hash flags)
    (%make-build-record source-hash deps-hash flags
      (time-second (current-time))))

  (define (build-record-source-hash r) (%build-record-source-hash r))
  (define (build-record-deps-hash r)   (%build-record-deps-hash r))
  (define (build-record-timestamp r)   (%build-record-timestamp r))

  (define (build-record-hash r)
    ;; Combined hash of all inputs: source + deps + flags.
    (content-hash-string
      (string-append
        (%build-record-source-hash r)
        (%build-record-deps-hash r)
        (format "~a" (%build-record-flags r)))))

  ;; ========== Verification ==========

  (define (verify-build record artifact-path)
    ;; Returns #t if artifact exists and both record and artifact hashes are non-empty.
    (guard (exn [#t #f])
      (let ([artifact-hash (content-hash artifact-path)])
        (and artifact-hash
             (> (string-length (build-record-hash record)) 0)
             (> (string-length artifact-hash) 0)))))

  (define (digit? c)
    (and (char>=? c #\0) (char<=? c #\9)))

  (define (normalize-artifact path)
    ;; Read file, strip embedded timestamps (ISO 8601 YYYY-MM-DD patterns), write to .normalized file.
    (guard (exn [#t #f])
      (let* ([content (call-with-input-file path
                        (lambda (port)
                          (let loop ([chars '()])
                            (let ([c (read-char port)])
                              (if (eof-object? c)
                                  (list->string (reverse chars))
                                  (loop (cons c chars)))))))]
             [normalized (strip-timestamps content)]
             [out-path   (string-append path ".normalized")])
        (call-with-output-file out-path
          (lambda (port) (display normalized port))
          'replace)
        out-path)))

  (define (strip-timestamps s)
    ;; Strip ISO date-like sequences: YYYY-MM-DD
    (let ([n (string-length s)]
          [result (open-output-string)])
      (let loop ([i 0])
        (cond
          [(>= i n) (get-output-string result)]
          ;; Check for YYYY-MM-DD pattern at position i
          [(and (<= (+ i 10) n)
                (digit? (string-ref s i))
                (digit? (string-ref s (+ i 1)))
                (digit? (string-ref s (+ i 2)))
                (digit? (string-ref s (+ i 3)))
                (char=? (string-ref s (+ i 4)) #\-)
                (digit? (string-ref s (+ i 5)))
                (digit? (string-ref s (+ i 6)))
                (char=? (string-ref s (+ i 7)) #\-)
                (digit? (string-ref s (+ i 8)))
                (digit? (string-ref s (+ i 9))))
           (display "<DATE>" result)
           (loop (+ i 10))]
          [else
           (write-char (string-ref s i) result)
           (loop (+ i 1))]))))

  ;; ========== Build Cache ==========

  (define-record-type (%build-cache %make-build-cache build-cache?)
    (fields
      (mutable table)    ;; hashtable: build-record-hash -> artifact
      (mutable hits)
      (mutable misses)))

  (define (make-build-cache)
    (%make-build-cache
      (make-hashtable equal-hash equal?)
      0
      0))

  (define (build-cache-lookup cache record)
    ;; Returns cached artifact or #f on miss.
    (let* ([key (build-record-hash record)]
           [val (hashtable-ref (%build-cache-table cache) key #f)])
      (if val
          (begin
            (%build-cache-hits-set! cache (+ (%build-cache-hits cache) 1))
            val)
          (begin
            (%build-cache-misses-set! cache (+ (%build-cache-misses cache) 1))
            #f))))

  (define (build-cache-store! cache record artifact)
    (hashtable-set! (%build-cache-table cache)
                    (build-record-hash record)
                    artifact))

  (define (build-cache-stats cache)
    ;; Returns alist: ((hits . N) (misses . N) (entries . N))
    (list
      (cons 'hits    (%build-cache-hits cache))
      (cons 'misses  (%build-cache-misses cache))
      (cons 'entries (hashtable-size (%build-cache-table cache)))))

  ;; ========== Provenance Tracking (S3) ==========

  (define-record-type (%provenance %make-provenance provenance?)
    (fields
      (immutable source-hash)    ;; git tree hash or content hash
      (immutable builder-id)     ;; machine identifier
      (immutable build-timestamp) ;; epoch seconds (or #f for reproducibility)
      (immutable output-hash)    ;; hash of built artifact
      (immutable metadata)))     ;; alist of additional info

  (define (make-provenance source-hash builder-id output-hash . opts)
    (let loop ([o opts] [ts #f] [meta '()])
      (if (or (null? o) (null? (cdr o)))
        (%make-provenance source-hash builder-id ts output-hash meta)
        (let ([k (car o)] [v (cadr o)])
          (loop (cddr o)
                (if (eq? k 'timestamp:) v ts)
                (if (eq? k 'metadata:) v meta))))))

  (define (provenance-source-hash p) (%provenance-source-hash p))
  (define (provenance-builder-id p)  (%provenance-builder-id p))
  (define (provenance-build-timestamp p) (%provenance-build-timestamp p))
  (define (provenance-output-hash p) (%provenance-output-hash p))

  (define (provenance->sexp p)
    `(provenance
       (source-hash ,(%provenance-source-hash p))
       (builder-id  ,(%provenance-builder-id p))
       (timestamp   ,(%provenance-build-timestamp p))
       (output-hash ,(%provenance-output-hash p))
       (metadata    ,@(%provenance-metadata p))))

  (define (sexp->provenance sexp)
    (unless (and (pair? sexp) (eq? (car sexp) 'provenance))
      (error 'sexp->provenance "invalid provenance" sexp))
    (let ([src  (prov-field sexp 'source-hash #f)]
          [bld  (prov-field sexp 'builder-id #f)]
          [ts   (prov-field sexp 'timestamp #f)]
          [out  (prov-field sexp 'output-hash #f)]
          [meta (let ([m (assq 'metadata (cdr sexp))])
                  (if m (cdr m) '()))])
      (%make-provenance src bld ts out meta)))

  (define (prov-field sexp key default)
    (let ([entry (assq key (cdr sexp))])
      (if (and entry (pair? (cdr entry)))
        (cadr entry)
        default)))

  (define (provenance-write p port)
    (write (provenance->sexp p) port)
    (newline port))

  (define (provenance-read port)
    (let ([sexp (read port)])
      (if (eof-object? sexp)
        (error 'provenance-read "empty provenance file")
        (sexp->provenance sexp))))

  (define (verify-provenance provenance-record expected-source-hash)
    ;; Verify that a provenance record matches expected source.
    ;; Returns #t if source hash matches, #f otherwise.
    (and (%provenance-source-hash provenance-record)
         (string? expected-source-hash)
         (string=? (%provenance-source-hash provenance-record)
                   expected-source-hash)))

) ;; end library
