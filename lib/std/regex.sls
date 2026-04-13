#!chezscheme
;;; (std regex) — Unified regex facade
;;;
;;; One import, one set of names. Automatically selects the best available
;;; backend: Rust regex (linear-time, ReDoS-safe) when libjerboa_native.so
;;; is present, otherwise pregexp (full-featured backtracking).
;;;
;;; Accepts: string patterns, SRE s-expressions, raw strings (#r"..."),
;;;          or existing re objects (idempotent).
;;;
;;; Usage:
;;;   (import (std regex))
;;;
;;;   (re-match? #r"\d+" "123")           ;; => #t
;;;   (re-match? "\\d+" "123")            ;; => #t
;;;   (re-match? '(+ digit) "123")        ;; => #t
;;;
;;;   (re-find-all #r"\d+" "a1b22c333")   ;; => ("1" "22" "333")
;;;
;;;   (let ([m (re-search '(: (=> user word) "@" (=> host word)) "u@h")])
;;;     (list (re-match-named m 'user) (re-match-named m 'host)))
;;;   ;; => ("u" "h")
;;;
;;;   ;; Compiled re objects are reusable and auto-cleaned up
;;;   (define email-re (re '(: (+ (or alnum ".")) "@" (+ (or alnum ".")) "." (** 2 6 alpha))))
;;;   (re-find-all email-re "send to foo@bar.com and baz@qux.io")

(library (std regex)
  (export
    ;; Compilation
    re re?
    ;; Match test (2 args) and match-object predicate (1 arg)
    re-match?
    ;; Search
    re-search
    ;; Extraction
    re-find-all re-groups
    ;; Replacement
    re-replace re-replace-all
    ;; Splitting and folding
    re-split re-fold
    ;; Match object accessors
    re-match-full re-match-group re-match-groups
    re-match-start re-match-end re-match-named
    ;; Internal accessor used by (std rx) for pattern splicing
    re-object-pat-string)

  (import (chezscheme)
          (std pregexp)
          (std srfi srfi-115))

  ;; ========== Optional native backend ==========
  ;; Try to load the Rust regex crate shim for linear-time matching.
  ;; Falls back silently to pregexp if the library is absent.
  ;;
  ;; Search order:
  ;;   1. libjerboa_native.so / .dylib  (LD_LIBRARY_PATH / DYLD_LIBRARY_PATH)
  ;;   2. lib/libjerboa_native.so / .dylib  (relative to CWD)
  ;;   3. $JERBOA_HOME/lib/libjerboa_native.so / .dylib  (absolute, set by Makefile)

  (define native-available?
    (let ([try (lambda (path)
                 (guard (exn [#t #f])
                   (load-shared-object path) #t))]
          [home (or (getenv "JERBOA_HOME") "")])
      (or (try "libjerboa_native.so")
          (try "libjerboa_native.dylib")
          (try "lib/libjerboa_native.so")
          (try "lib/libjerboa_native.dylib")
          (and (not (string=? home ""))
               (or (try (string-append home "/lib/libjerboa_native.so"))
                   (try (string-append home "/lib/libjerboa_native.dylib"))))
          #f)))

  ;; Foreign procedures — defined conditionally.
  ;; (foreign-procedure ...) is evaluated eagerly in compiled/WPO code on both
  ;; Linux and macOS; if the native library is absent the form throws "no entry
  ;; for".  Guard by checking native-available? first.  The fallback lambdas are
  ;; never called because every call site checks native-available? first.
  (define c-native-compile
    (if native-available?
      (foreign-procedure "jerboa_regex_compile" (u8* size_t u8*) int)
      (lambda args (error 'c-native-compile "native backend not available"))))
  (define c-native-find
    (if native-available?
      (foreign-procedure "jerboa_regex_find" (unsigned-64 u8* size_t u8* u8*) int)
      (lambda args (error 'c-native-find "native backend not available"))))
  (define c-native-free
    (if native-available?
      (foreign-procedure "jerboa_regex_free" (unsigned-64) int)
      (lambda args (error 'c-native-free "native backend not available"))))

  ;; ========== Records ==========

  (define-record-type re-object
    (fields
      (immutable pattern)       ;; original: string or SRE datum
      (immutable pat-string)    ;; normalized pregexp-compatible string
      (immutable named-groups)  ;; alist: (symbol . 1-based-group-index)
      (immutable native-handle)) ;; u64 integer handle, or #f
    (sealed #t))

  (define-record-type re-match-object
    (fields
      (immutable full)          ;; string: full matched text
      (immutable groups)        ;; vector: index 0=full, 1..N=capture groups (string or #f)
      (immutable named-groups)  ;; alist: (symbol . group-index), copied from re
      (immutable start)         ;; integer: start char-index in subject string
      (immutable end))          ;; integer: end char-index in subject string
    (sealed #t))

  ;; ========== Guardian for native handles ==========
  ;; When a re-object is GC'd, its native handle is freed.

  (define re-guardian (make-guardian))

  (define (drain-re-guardian!)
    (let loop ([obj (re-guardian)])
      (when obj
        (when (re-object? obj)
          (let ([h (re-object-native-handle obj)])
            (when h
              (guard (exn [#t #f]) (c-native-free h)))))
        (loop (re-guardian)))))

  ;; ========== Internal helpers ==========

  ;; Scan a pregexp pattern string for (?P<name>...) named groups.
  ;; Returns alist of (symbol . 1-based-index) in left-to-right order.
  (define (pattern->named-groups pat)
    (let ([len (string-length pat)])
      (let loop ([i 0] [gidx 1] [acc '()])
        (if (>= i len)
          (reverse acc)
          (let ([c (string-ref pat i)])
            (cond
              ;; Skip escaped char (backslash + next char)
              [(char=? c #\\)
               (loop (+ i 2) gidx acc)]
              ;; Any (?...) group — check if named
              [(and (char=? c #\()
                    (< (+ i 1) len)
                    (char=? (string-ref pat (+ i 1)) #\?))
               (if (and (< (+ i 3) len)
                        (char=? (string-ref pat (+ i 2)) #\P)
                        (char=? (string-ref pat (+ i 3)) #\<))
                 ;; Named group (?P<name> — extract the name
                 (let name-loop ([j (+ i 4)] [chars '()])
                   (if (or (>= j len) (char=? (string-ref pat j) #\>))
                     (let ([sym (string->symbol (list->string (reverse chars)))])
                       (loop (+ j 1) (+ gidx 1) (cons (cons sym gidx) acc)))
                     (name-loop (+ j 1) (cons (string-ref pat j) chars))))
                 ;; Other (?...) — non-capturing, don't bump group index
                 (loop (+ i 2) gidx acc))]
              ;; Regular capturing group
              [(char=? c #\()
               (loop (+ i 1) (+ gidx 1) acc)]
              [else
               (loop (+ i 1) gidx acc)]))))))

  ;; Normalize pattern input to a pregexp-compatible string.
  (define (normalize-pattern pat)
    (cond
      [(string? pat) pat]
      [(or (list? pat) (symbol? pat)) (sre->pattern-string pat)]
      [else (error 're "expected string, SRE list/symbol, or re object" pat)]))

  ;; Try to compile a native handle. Returns handle (u64) or #f on failure.
  (define (try-native-compile! pat-str)
    (and native-available?
         (drain-re-guardian!)
         (guard (exn [#t #f])
           (let* ([bv  (string->utf8 pat-str)]
                  [hbuf (make-bytevector 8)]
                  [rc  (c-native-compile bv (bytevector-length bv) hbuf)])
             (and (>= rc 0)
                  (bytevector-u64-native-ref hbuf 0))))))

  ;; Construct a re-object, registering with guardian if native handle present.
  ;; named-override: optional alist (symbol . group-index) from SRE compilation;
  ;;   when omitted, falls back to scanning the pattern string for (?P<name>...).
  (define (make-re original pat-str . named-override)
    (let* ([named  (if (null? named-override)
                       (pattern->named-groups pat-str)
                       (car named-override))]
           [handle (try-native-compile! pat-str)]
           [obj    (make-re-object original pat-str named handle)])
      (when handle (re-guardian obj))  ;; guard the object, not just the handle
      obj))

  ;; Build a re-match-object from position info.
  ;; raw-positions: list of (start . end) pairs OR #f for optional groups,
  ;;   all relative to the original subject string (already offset-adjusted).
  ;; named: alist from the parent re-object.
  (define (build-match-object subject raw-positions named)
    (let* ([full-pos  (car raw-positions)]
           [full-start (car full-pos)]
           [full-end   (cdr full-pos)]
           [groups    (list->vector
                        (map (lambda (p)
                               (and p (substring subject (car p) (cdr p))))
                             raw-positions))])
      (make-re-match-object
        (substring subject full-start full-end)
        groups
        named
        full-start
        full-end)))

  ;; Internal search with explicit offset.
  ;; Returns re-match-object or #f.
  (define (search-from r str start)
    (let* ([pat-str (re-object-pat-string r)]
           [named   (re-object-named-groups r)]
           [subject (if (= start 0) str (substring str start (string-length str)))]
           [raw-pos (pregexp-match-positions pat-str subject)])
      (and raw-pos
           ;; Adjust positions from substring-relative to str-relative
           (let ([adj-pos (map (lambda (p)
                                 (and p (cons (+ start (car p))
                                              (+ start (cdr p)))))
                               raw-pos)])
             (build-match-object str adj-pos named)))))

  ;; ========== Public API ==========

  ;; re: compile a pattern to a re object. Idempotent on re-objects.
  (define (re pat)
    (cond
      [(re-object? pat) pat]
      [(string? pat) (make-re pat pat)]
      [(or (list? pat) (symbol? pat))
       ;; For SRE forms, extract named-groups directly from the SRE tree
       ;; so that (=> name ...) captures can be looked up by name.
       (let ([pat-str (sre->pattern-string pat)]
             [named   (sre->named-groups pat)])
         (make-re pat pat-str named))]
      [else (error 're "expected string, SRE, or re object" pat)]))

  ;; re?: true only for compiled re objects (not match objects).
  (define (re? x) (re-object? x))

  ;; re-match?: overloaded by arity.
  ;;   (re-match? obj)       — #t if obj is a re-match-object
  ;;   (re-match? pat str)   — #t if str is a full match for pat
  (define re-match?
    (case-lambda
      [(obj)
       (re-match-object? obj)]
      [(pat str)
       (let* ([r       (re pat)]
              [pat-str (re-object-pat-string r)])
         ;; Use native if available: find match and verify it spans entire string
         (cond
           [(and native-available? (re-object-native-handle r))
            (guard (exn [#t ; fall through to pregexp
                         (let ([full (string-append "^(?:" pat-str ")$")])
                           (and (pregexp-match full str) #t))])
              (let* ([h    (re-object-native-handle r)]
                     [bv   (string->utf8 str)]
                     [blen (bytevector-length bv)]
                     [sbuf (make-bytevector 8)]
                     [ebuf (make-bytevector 8)]
                     [rc   (c-native-find h bv blen sbuf ebuf)])
                (and (= rc 1)
                     (= (bytevector-u64-native-ref sbuf 0) 0)
                     (= (bytevector-u64-native-ref ebuf 0) blen))))]
           [else
            (let ([full (string-append "^(?:" pat-str ")$")])
              (and (pregexp-match full str) #t))]))]))

  ;; re-search: find first match anywhere in str, from optional start offset.
  ;; Returns re-match-object or #f.
  (define re-search
    (case-lambda
      [(pat str) (search-from (re pat) str 0)]
      [(pat str start) (search-from (re pat) str start)]))

  ;; re-find-all: list of all non-overlapping matched strings.
  (define (re-find-all pat str)
    (let* ([r       (re pat)]
           [pat-str (re-object-pat-string r)]
           [len     (string-length str)])
      (let loop ([pos 0] [acc '()])
        (if (> pos len)
          (reverse acc)
          (let ([positions (pregexp-match-positions pat-str
                             (if (= pos 0) str (substring str pos len)))])
            (if (not positions)
              (reverse acc)
              (let* ([mstart (+ pos (caar positions))]
                     [mend   (+ pos (cdar positions))]
                     [matched (substring str mstart mend)]
                     [next    (max (+ mstart 1) mend)])
                (loop next (cons matched acc)))))))))

  ;; re-groups: capture groups of first match as list, or #f if no match.
  ;; Does not include the full match (index 0); only capture groups 1..N.
  (define (re-groups pat str)
    (let ([m (re-search pat str)])
      (and m
           (let* ([v   (re-match-object-groups m)]
                  [len (vector-length v)])
             (let loop ([i 1] [acc '()])
               (if (>= i len)
                 (reverse acc)
                 (loop (+ i 1) (cons (vector-ref v i) acc))))))))

  ;; re-replace: replace first match with replacement string.
  (define (re-replace pat str replacement)
    (pregexp-replace (re-object-pat-string (re pat)) str replacement))

  ;; re-replace-all: replace all non-overlapping matches.
  (define (re-replace-all pat str replacement)
    (pregexp-replace* (re-object-pat-string (re pat)) str replacement))

  ;; re-split: split str on each match; returns list of strings.
  (define (re-split pat str)
    (pregexp-split (re-object-pat-string (re pat)) str))

  ;; re-fold: fold kons over all matches left-to-right.
  ;; kons receives (match-index re-match-object subject accumulator).
  (define (re-fold pat kons knil str)
    (let* ([r       (re pat)]
           [pat-str (re-object-pat-string r)]
           [named   (re-object-named-groups r)]
           [len     (string-length str)])
      (let loop ([pos 0] [i 0] [acc knil])
        (if (> pos len)
          acc
          (let* ([subject  (if (= pos 0) str (substring str pos len))]
                 [raw-pos  (pregexp-match-positions pat-str subject)])
            (if (not raw-pos)
              acc
              (let* ([adj-pos  (map (lambda (p)
                                      (and p (cons (+ pos (car p))
                                                   (+ pos (cdr p)))))
                                    raw-pos)]
                     [m        (build-match-object str adj-pos named)]
                     [mstart   (re-match-object-start m)]
                     [mend     (re-match-object-end m)]
                     [next     (max (+ mstart 1) mend)])
                (loop next (+ i 1) (kons i m str acc)))))))))

  ;; ========== Match object accessors ==========

  ;; re-match-full: the complete matched string.
  (define (re-match-full m) (re-match-object-full m))

  ;; re-match-group: nth group string (0 = full match, 1..N = captures).
  (define (re-match-group m n)
    (let ([v (re-match-object-groups m)])
      (if (< n (vector-length v))
        (vector-ref v n)
        (error 're-match-group "group index out of range" n))))

  ;; re-match-groups: all capture groups as list (excludes full match at 0).
  (define (re-match-groups m)
    (let* ([v   (re-match-object-groups m)]
           [len (vector-length v)])
      (let loop ([i 1] [acc '()])
        (if (>= i len)
          (reverse acc)
          (loop (+ i 1) (cons (vector-ref v i) acc))))))

  ;; re-match-start: start character index of full match in subject.
  (define (re-match-start m) (re-match-object-start m))

  ;; re-match-end: end character index (exclusive) of full match in subject.
  (define (re-match-end m) (re-match-object-end m))

  ;; re-match-named: value of a named capture group by symbol.
  ;; Named groups are created with (=> name ...) in SRE or (?P<name>...) in strings.
  (define (re-match-named m name)
    (let ([entry (assq name (re-match-object-named-groups m))])
      (and entry (re-match-group m (cdr entry)))))

) ;; end library
