#!chezscheme
;;; (std gambit-compat) — Gambit/Gerbil runtime compatibility for Chez Scheme
;;;
;;; One-stop import for porting Gerbil code to Jerboa. Re-exports everything
;;; from (jerboa core) and (std sugar), plus adds the remaining Gambit-isms
;;; that neither provides.
;;;
;;; Usage: (import (std gambit-compat))
;;;
;;; This module exists so that every jerboa-* port doesn't need to write
;;; its own (compat gambit) shim. The canonical set of Gambit compatibility
;;; functions lives here.

(library (std gambit-compat)
  (export
    ;; ---- Additional u8vector ops not in (jerboa core) ----
    u8vector? make-u8vector
    u8vector-append u8vector-copy u8vector-copy!
    open-input-u8vector open-output-u8vector get-output-u8vector
    write-subu8vector read-subu8vector

    ;; ---- Additional f64vector ops ----
    f64vector->list

    ;; ---- Void ----
    void?

    ;; ---- Box type ----
    ;; Chez 10 has box/box?/unbox/set-box! built-in, re-export
    box box? unbox set-box!

    ;; ---- Control flow ----
    let/cc
    with-exception-catcher*  ;; thunk-based alias (jerboa core has with-exception-catcher)
    with-unwind-protect

    ;; ---- Time ----
    current-second

    ;; ---- Date formatting ----
    date->string*

    ;; ---- Environment ----
    getenv*   ;; getenv with default arg (jerboa core's getenv already has this)
    setenv*   ;; alias for setenv
    get-environment-variables
    cpu-count

    ;; ---- Path/filesystem extras ----
    directory-files*  ;; Gambit settings-list style

    ;; ---- Arithmetic compat ----
    truncate-quotient truncate-remainder

    ;; ---- Hash constructor macro ----
    hash-constructor

    ;; ---- Global-mutation parameterize ----
    gerbil-parameterize

    ;; ---- Pretty print alias ----
    pp

    ;; ---- Re-exports from (jerboa core) ----
    ;; Definitions
    def def* defrule defrules
    defstruct defclass defmethod
    match
    try catch finally
    while until
    hash hash-eq hash-literal hash-eq-literal let-hash
    struct-out

    ;; I/O and filesystem
    read-line read-string getenv force-output
    read-u8 write-u8
    call-with-input-string call-with-output-string
    display-exception display-continuation-backtrace
    directory-files
    create-directory create-directory*

    ;; u8vector / bytes / string
    u8vector u8vector-ref u8vector-set! u8vector-length u8vector->list list->u8vector
    subu8vector string->bytes bytes->string object->string string-map
    string-split string-empty? string-subst

    ;; f64vector
    f64vector-ref f64vector-set! f64vector-length make-f64vector

    ;; Threading
    spawn spawn/name spawn/group
    make-thread thread-start! thread-join!
    thread-yield! thread-sleep! current-thread thread-name
    thread? thread-specific thread-specific-set!
    thread-interrupt! thread-terminate!
    make-mutex make-mutex-gambit mutex? mutex-name
    mutex-lock! mutex-unlock! mutex-specific mutex-specific-set!
    make-condition-variable condition-variable?
    condition-variable-signal! condition-variable-broadcast!
    condition-variable-specific condition-variable-specific-set!
    thread-send thread-receive thread-mailbox-next

    ;; Hash tables
    make-hash-table make-hash-table-eq
    hash-ref hash-get hash-put! hash-update! hash-remove!
    hash-key? hash->list hash->plist hash-for-each hash-map hash-fold
    hash-find hash-keys hash-values hash-copy hash-clear!
    hash-merge hash-merge! hash-length hash-table?
    list->hash-table plist->hash-table

    ;; Keywords
    keyword? keyword->string string->keyword make-keyword keyword-arg-ref

    ;; Errors
    error-message error-irritants error-trace

    ;; Path utilities
    path-expand path-normalize path-directory
    path-strip-directory path-extension path-strip-extension
    path-strip-trailing-directory-separator
    path-join path-absolute?

    ;; File info
    with-exception-catcher
    file-info file-info-type file-info-size file-info-mode
    file-info-last-modification-time file-info-last-access-time
    file-info-device file-info-inode file-info-owner file-info-group

    ;; Process
    open-process open-input-process process-status

    ;; Misc
    random-integer random-bytes copy-file setenv
    user-info user-info-home user-name
    filter-map displayln 1+ 1-
    any every iota last-pair
    arithmetic-shift
    time->seconds
    take drop delete last
    input-port-timeout-set! output-port-timeout-set!
    getpid

    ;; Method dispatch
    ~ bind-method! call-method
    *method-tables*
    register-struct-type! *struct-types*
    struct-predicate struct-field-ref struct-field-set!
    struct-type-info

    ;; ---- Re-exports from (std sugar) ----
    unwind-protect
    with-catch
    cut cute <> <...>
    chain chain-and with-id
    assert!
    with-lock
    awhen aif when-let if-let
    dotimes)

  (import (except (chezscheme)
            make-hash-table hash-table?
            iota 1+ 1-
            getenv
            path-extension path-absolute?
            thread? make-mutex mutex? mutex-name)
          (jerboa core)
          (std sugar))

  ;; ================================================================
  ;; Additional u8vector operations
  ;; ================================================================

  (define u8vector?       bytevector?)
  (define make-u8vector   make-bytevector)

  (define (u8vector-append . bvs)
    (let* ([total (apply + (map bytevector-length bvs))]
           [result (make-bytevector total)])
      (let loop ([bvs bvs] [pos 0])
        (if (null? bvs) result
          (let ([bv (car bvs)])
            (bytevector-copy! bv 0 result pos (bytevector-length bv))
            (loop (cdr bvs) (+ pos (bytevector-length bv))))))))

  (define u8vector-copy  bytevector-copy)
  (define u8vector-copy! bytevector-copy!)

  ;; ---- open-input-u8vector ----
  ;; Gambit: (open-input-u8vector (list init: bv char-encoding: 'UTF-8))
  (define (open-input-u8vector props)
    (let loop ([rest (if (list? props) props '())]
               [init #f] [encoding 'UTF-8])
      (cond
        [(null? rest)
         (let* ([bv (or init (make-bytevector 0))]
                [tc (make-transcoder
                      (case encoding
                        [(UTF-8 utf-8 utf8) (utf-8-codec)]
                        [(latin-1 ISO-8859-1 latin1) (latin-1-codec)]
                        [else (utf-8-codec)]))])
           (open-bytevector-input-port bv tc))]
        [(and (pair? (cdr rest)) (memq (car rest) '(init init:)))
         (loop (cddr rest) (cadr rest) encoding)]
        [(and (pair? (cdr rest)) (memq (car rest) '(char-encoding char-encoding:)))
         (loop (cddr rest) init (cadr rest))]
        [else (loop (cdr rest) init encoding)])))

  ;; ---- open-output-u8vector / get-output-u8vector ----
  (define *u8vec-extractors* (make-weak-eq-hashtable))

  (define (open-output-u8vector . _)
    (let ([chunks '()])
      (let* ([write-str!
               (lambda (str start count)
                 (let* ([sub (if (and (= start 0) (= count (string-length str)))
                               str (substring str start (+ start count)))]
                        [bv (string->utf8 sub)])
                   (set! chunks (cons bv chunks)))
                 count)]
             [port (make-custom-textual-output-port
                     "u8vector-output"
                     write-str!
                     #f #f #f)]
             [extract
               (lambda ()
                 (flush-output-port port)
                 (let* ([all (reverse chunks)]
                        [total (apply + (map bytevector-length all))]
                        [result (make-bytevector total)])
                   (let loop ([pos 0] [cs all])
                     (if (null? cs) result
                       (let ([bv (car cs)])
                         (bytevector-copy! bv 0 result pos (bytevector-length bv))
                         (loop (+ pos (bytevector-length bv)) (cdr cs)))))))])
        (hashtable-set! *u8vec-extractors* port extract)
        port)))

  (define (get-output-u8vector port)
    (let ([extract (hashtable-ref *u8vec-extractors* port #f)])
      (if extract (extract)
        (error 'get-output-u8vector "not a u8vector output port" port))))

  ;; ---- write-subu8vector / read-subu8vector ----
  (define (write-subu8vector bv start end . port-opt)
    (let ([port (if (pair? port-opt) (car port-opt) (current-output-port))])
      (if (binary-port? port)
        (put-bytevector port bv start (- end start))
        (display (utf8->string (subu8vector bv start end)) port))))

  (define (read-subu8vector bv start end . port-opt)
    (let ([port (if (pair? port-opt) (car port-opt) (current-input-port))])
      (if (binary-port? port)
        (let ([n (get-bytevector-n! port bv start (- end start))])
          (if (eof-object? n) 0 n))
        (let loop ([i start])
          (if (>= i end) (- i start)
            (let ([ch (get-char port)])
              (if (eof-object? ch) (- i start)
                (begin
                  (bytevector-u8-set! bv i (char->integer ch))
                  (loop (+ i 1))))))))))

  ;; ================================================================
  ;; Additional f64vector operations
  ;; ================================================================

  (define (f64vector->list fv)
    (let loop ([i 0] [acc '()])
      (if (= i (flvector-length fv))
        (reverse acc)
        (loop (+ i 1) (cons (flvector-ref fv i) acc)))))

  ;; ================================================================
  ;; Void
  ;; ================================================================

  (define (void? x) (eq? x (void)))

  ;; ================================================================
  ;; Control flow
  ;; ================================================================

  (define-syntax let/cc
    (syntax-rules ()
      [(_ k body ...)
       (call-with-current-continuation
         (lambda (k) body ...))]))

  ;; Thunk-based alias — same as with-exception-catcher from core
  (define (with-exception-catcher* handler thunk)
    (with-exception-catcher handler thunk))

  (define (with-unwind-protect body-thunk cleanup-thunk)
    (dynamic-wind
      (lambda () (void))
      body-thunk
      cleanup-thunk))

  ;; ================================================================
  ;; Time
  ;; ================================================================

  (define (current-second)
    (time->seconds (current-time 'time-utc)))

  ;; ================================================================
  ;; Date formatting (SRFI-19 subset)
  ;; ================================================================

  (define (date->string* date fmt)
    (let ([out (open-output-string)]
          [len (string-length fmt)])
      (let loop ([i 0])
        (when (< i len)
          (let ([c (string-ref fmt i)])
            (if (and (char=? c #\~) (< (+ i 1) len))
              (let ([d (string-ref fmt (+ i 1))])
                (case d
                  [(#\Y) (display (date-year date) out)]
                  [(#\m) (let ([m (date-month date)])
                           (when (< m 10) (display #\0 out))
                           (display m out))]
                  [(#\d) (let ([day (date-day date)])
                           (when (< day 10) (display #\0 out))
                           (display day out))]
                  [(#\H) (let ([h (date-hour date)])
                           (when (< h 10) (display #\0 out))
                           (display h out))]
                  [(#\M) (let ([min (date-minute date)])
                           (when (< min 10) (display #\0 out))
                           (display min out))]
                  [(#\S) (let ([s (date-second date)])
                           (when (< s 10) (display #\0 out))
                           (display s out))]
                  [(#\Z) (let* ([off (date-zone-offset date)]
                                [sign (if (< off 0) "-" "+")]
                                [abs-off (abs off)]
                                [hours (quotient abs-off 3600)]
                                [mins (quotient (remainder abs-off 3600) 60)])
                           (display sign out)
                           (when (< hours 10) (display #\0 out))
                           (display hours out)
                           (when (< mins 10) (display #\0 out))
                           (display mins out))]
                  [else (display c out)])
                (loop (+ i 2)))
              (begin (display c out) (loop (+ i 1)))))))
      (get-output-string out)))

  ;; ================================================================
  ;; Environment extras
  ;; ================================================================

  ;; getenv* with optional default (Gambit-style)
  ;; Note: (jerboa core)'s getenv already supports optional default,
  ;; but this provides a distinctly-named version for clarity.
  (define (getenv* name . default)
    (or (getenv name)
        (if (pair? default) (car default) #f)))

  (define setenv* setenv)

  (define (get-environment-variables)
    (guard (exn [#t '()])
      (let ([bv (call-with-port (open-file-input-port "/proc/self/environ")
                  (lambda (p) (get-bytevector-all p)))])
        (if (eof-object? bv) '()
          (let ([str (bytevector->string bv (make-transcoder (utf-8-codec)))])
            (let loop ([i 0] [start 0] [vars '()])
              (cond
                [(>= i (string-length str)) (reverse vars)]
                [(char=? (string-ref str i) #\nul)
                 (let* ([entry (substring str start i)]
                        [eq-pos (let find ([j 0])
                                  (if (>= j (string-length entry)) #f
                                    (if (char=? (string-ref entry j) #\=) j
                                      (find (+ j 1)))))])
                   (loop (+ i 1) (+ i 1)
                         (if eq-pos
                           (cons (cons (substring entry 0 eq-pos)
                                       (substring entry (+ eq-pos 1) (string-length entry)))
                                 vars)
                           vars)))]
                [else (loop (+ i 1) start vars)])))))))

  (define cpu-count
    (let ([cached
           (guard (exn [#t 1])
             (let ([c-sysconf (foreign-procedure "sysconf" (int) long)])
               (let ([result (c-sysconf 84)])
                 (if (> result 0) result 1))))])
      (lambda () cached)))

  ;; ================================================================
  ;; Path/filesystem extras
  ;; ================================================================

  ;; Gambit-style directory-files with settings list
  ;; Returns empty list on error (non-existent dir, permission denied)
  (define (directory-files* path-or-settings)
    (let ([path (if (pair? path-or-settings)
                  (let loop ([s path-or-settings])
                    (cond
                      [(null? s) "."]
                      [(and (pair? (cdr s)) (memq (car s) '(path path:))) (cadr s)]
                      [else (loop (cdr s))]))
                  path-or-settings)])
      (guard (exn [#t '()])
        (directory-files path))))

  ;; ================================================================
  ;; Arithmetic compat
  ;; ================================================================

  (define truncate-quotient  quotient)
  (define truncate-remainder remainder)

  ;; ================================================================
  ;; Hash constructor macro
  ;; ================================================================

  (define-syntax hash-constructor
    (syntax-rules ()
      [(_ (key val) ...)
       (let ([ht (make-hash-table)])
         (hash-put! ht key val) ...
         ht)]))

  ;; ================================================================
  ;; Gerbil-parameterize (global mutation, not thread-local)
  ;; ================================================================

  (define-syntax gerbil-parameterize
    (syntax-rules ()
      [(_ () body ...) (let () body ...)]
      [(_ ((p v) ...) body ...)
       (begin (p v) ... body ...)]))

  ;; ================================================================
  ;; Pretty print alias
  ;; ================================================================

  (define pp pretty-print)

) ;; end library
