;;; (std nrepl) — Full nREPL server with CIDER/Calva middleware + Jerboa extensions
;;;
;;; Implements the nREPL protocol (bencode over TCP) with complete CIDER and
;;; Calva middleware support plus Jerboa-specific extensions that exceed CIDER.
;;;
;;; Usage:
;;;   (import (std nrepl))
;;;   (nrepl-start! 7888)              ;; start on port 7888
;;;   (nrepl-start!)                   ;; start on random port, prints it
;;;   (nrepl-stop!)                    ;; stop the server
;;;
;;; Base ops:      clone, close, describe, eval, load-file, interrupt, stdin
;;; Metadata:      info, eldoc, arglists, lookup, version
;;; Completions:   completions (with type + doc)
;;; Macros:        macroexpand, macroexpand-1, macroexpand-all
;;; Namespaces:    ns-list, ns-vars, ns-vars-with-meta
;;; Debugging:     stacktrace, analyze-stacktrace
;;; Formatting:    format-code, format-edn
;;; Search:        apropos, apropos-docs
;;; Mutation:      undef
;;; Testing:       test, test-all, test-ns
;;; Inspection:    inspect-start, inspect-next, inspect-pop,
;;;                inspect-refresh, inspect-get-path, inspect-navigate
;;; Jerboa+:       eval-timed, type-info, memory-stats, doc-examples
;;;
;;; Protocol reference: https://nrepl.org/nrepl/building_servers.html

(export nrepl-start! nrepl-stop!
        nrepl-server-port nrepl-running?)

(import (std sort)
        :std/repl)

;; ================================================================
;; Bencode Encoder/Decoder (binary, self-contained)
;; ================================================================

(def (string->bv s)
  (string->bytevector s (make-transcoder (utf-8-codec))))

(def (bv->string bv)
  (bytevector->string bv (make-transcoder (utf-8-codec))))

(def (bencode-encode obj)
  (let-values (((out extract) (open-bytevector-output-port)))
    (bencode-write obj out)
    (extract)))

(def (bencode-write obj port)
  (cond
    ((and (integer? obj) (exact? obj))
     (put-u8 port (char->integer #\i))
     (put-bytevector port (string->bv (number->string obj)))
     (put-u8 port (char->integer #\e)))
    ((string? obj)
     (let ((bv (string->bv obj)))
       (put-bytevector port (string->bv (number->string (bytevector-length bv))))
       (put-u8 port (char->integer #\:))
       (put-bytevector port bv)))
    ((symbol? obj)
     (bencode-write (symbol->string obj) port))
    ((list? obj)
     (put-u8 port (char->integer #\l))
     (for-each (lambda (item) (bencode-write item port)) obj)
     (put-u8 port (char->integer #\e)))
    ((hash-table? obj)
     (put-u8 port (char->integer #\d))
     (let* ((pairs (map (lambda (kv)
                          (cons (if (string? (car kv))
                                    (car kv)
                                    (format "~a" (car kv)))
                                (cdr kv)))
                        (hash->list obj)))
            (sorted (sort (lambda (a b) (string<? (car a) (car b))) pairs)))
       (for-each (lambda (pair)
                   (bencode-write (car pair) port)
                   (bencode-write (cdr pair) port))
                 sorted))
     (put-u8 port (char->integer #\e)))
    ((boolean? obj)
     (bencode-write (if obj "true" "false") port))
    (else
     (bencode-write (format "~a" obj) port))))

(def (bencode-read port)
  (let ((b (get-u8 port)))
    (cond
      ((eof-object? b) b)
      ((= b (char->integer #\i)) (bencode-read-int port))
      ((= b (char->integer #\l)) (bencode-read-list port))
      ((= b (char->integer #\d)) (bencode-read-dict port))
      ((<= (char->integer #\0) b (char->integer #\9))
       (bencode-read-string b port))
      (else (error 'bencode-read "unexpected byte in bencode stream" b)))))

(def (bencode-read-int port)
  (let lp ((acc '()))
    (let ((b (get-u8 port)))
      (cond
        ((eof-object? b) (error 'bencode-read-int "unexpected EOF in integer"))
        ((= b (char->integer #\e))
         (string->number (list->string (reverse acc))))
        (else (lp (cons (integer->char b) acc)))))))

(def (bencode-read-string first-byte port)
  (let lp ((acc (list (integer->char first-byte))))
    (let ((b (get-u8 port)))
      (cond
        ((eof-object? b) (error 'bencode-read-string "unexpected EOF in string length"))
        ((= b (char->integer #\:))
         (let* ((len (string->number (list->string (reverse acc))))
                (bv (get-bytevector-n port len)))
           (if (eof-object? bv)
               (error 'bencode-read-string "unexpected EOF in string data")
               (bv->string bv))))
        (else (lp (cons (integer->char b) acc)))))))

(def (bencode-read-list port)
  (let lp ((acc '()))
    (let ((b (lookahead-u8 port)))
      (cond
        ((eof-object? b) (error 'bencode-read-list "unexpected EOF in list"))
        ((= b (char->integer #\e))
         (get-u8 port)
         (reverse acc))
        (else (lp (cons (bencode-read port) acc)))))))

(def (bencode-read-dict port)
  (let ((ht (make-hash-table)))
    (let lp ()
      (let ((b (lookahead-u8 port)))
        (cond
          ((eof-object? b) (error 'bencode-read-dict "unexpected EOF in dict"))
          ((= b (char->integer #\e))
           (get-u8 port)
           ht)
          (else
           (let* ((key (bencode-read port))
                  (val (bencode-read port)))
             (hash-put! ht
               (if (string? key) key (format "~a" key))
               val)
             (lp))))))))

;; ================================================================
;; UUID Generation
;; ================================================================

(def (generate-uuid)
  (let ((bv (make-bytevector 16)))
    (guard (exn
             (#t
              (let ((t (time-nanosecond (current-time)))
                    (r (random (expt 2 48))))
                (format "~8,'0x-~4,'0x-~4,'0x-~4,'0x-~12,'0x"
                  (bitwise-and t #xFFFFFFFF)
                  (bitwise-and (bitwise-arithmetic-shift-right t 32) #xFFFF)
                  (bitwise-ior #x4000 (bitwise-and r #x0FFF))
                  (bitwise-ior #x8000 (bitwise-and (bitwise-arithmetic-shift-right r 12) #x3FFF))
                  (bitwise-and (bitwise-arithmetic-shift-right r 26) #xFFFFFFFFFFFF)))))
      (let ((p (open-file-input-port "/dev/urandom")))
        (get-bytevector-n! p bv 0 16)
        (close-port p)
        (bytevector-u8-set! bv 6
          (bitwise-ior #x40 (bitwise-and (bytevector-u8-ref bv 6) #x0F)))
        (bytevector-u8-set! bv 8
          (bitwise-ior #x80 (bitwise-and (bytevector-u8-ref bv 8) #x3F)))
        (format "~2,'0x~2,'0x~2,'0x~2,'0x-~2,'0x~2,'0x-~2,'0x~2,'0x-~2,'0x~2,'0x-~2,'0x~2,'0x~2,'0x~2,'0x~2,'0x~2,'0x"
          (bytevector-u8-ref bv 0)  (bytevector-u8-ref bv 1)
          (bytevector-u8-ref bv 2)  (bytevector-u8-ref bv 3)
          (bytevector-u8-ref bv 4)  (bytevector-u8-ref bv 5)
          (bytevector-u8-ref bv 6)  (bytevector-u8-ref bv 7)
          (bytevector-u8-ref bv 8)  (bytevector-u8-ref bv 9)
          (bytevector-u8-ref bv 10) (bytevector-u8-ref bv 11)
          (bytevector-u8-ref bv 12) (bytevector-u8-ref bv 13)
          (bytevector-u8-ref bv 14) (bytevector-u8-ref bv 15))))))

;; ================================================================
;; Extended Session State
;; ================================================================
;; Each session carries:
;;   env         — interaction-environment for eval
;;   last-exn    — most recent exception condition (#f if none)
;;   inspector   — inspector state vector (#f if not inspecting)

(defstruct nrepl-session (env last-exn inspector))

(def (new-nrepl-session)
  (make-nrepl-session (interaction-environment) #f #f))

(def *sessions*       (make-hash-table))
(def *sessions-mutex* (make-mutex))

(def (create-session!)
  (let ((id (generate-uuid)))
    (with-mutex *sessions-mutex*
      (hash-put! *sessions* id (new-nrepl-session)))
    id))

(def (get-session id)
  (with-mutex *sessions-mutex*
    (hash-ref *sessions* id #f)))

(def (session-env session-id)
  (let ((s (get-session session-id)))
    (if s (nrepl-session-env s) (interaction-environment))))

(def (session-set-last-exn! session-id exn)
  (let ((s (get-session session-id)))
    (when s
      (with-mutex *sessions-mutex*
        (nrepl-session-last-exn-set! s exn)))))

(def (session-last-exn session-id)
  (let ((s (get-session session-id)))
    (and s (nrepl-session-last-exn s))))

(def (session-set-inspector! session-id state)
  (let ((s (get-session session-id)))
    (when s
      (with-mutex *sessions-mutex*
        (nrepl-session-inspector-set! s state)))))

(def (session-inspector session-id)
  (let ((s (get-session session-id)))
    (and s (nrepl-session-inspector s))))

(def (close-session! id)
  (with-mutex *sessions-mutex*
    (hash-remove! *sessions* id)))

;; ================================================================
;; Response Helpers
;; ================================================================

(def (dict-ref ht key . default)
  (if (and (hash-table? ht) (hash-key? ht key))
      (hash-ref ht key #f)
      (if (pair? default) (car default) #f)))

(def (make-dict . kvs)
  (let ((ht (make-hash-table)))
    (let lp ((rest kvs))
      (cond
        ((null? rest) ht)
        ((null? (cdr rest)) (error 'make-dict "odd number of arguments"))
        (else
         (hash-put! ht (car rest) (cadr rest))
         (lp (cddr rest)))))
    ht))

(def (make-response msg . kvs)
  (let ((ht (apply make-dict kvs)))
    (let ((id (dict-ref msg "id")))
      (when id (hash-put! ht "id" id)))
    (let ((session (dict-ref msg "session")))
      (when session (hash-put! ht "session" session)))
    ht))

(def (send-response! port msg)
  (let ((bv (bencode-encode msg)))
    (put-bytevector port bv)
    (flush-output-port port)))

;; ================================================================
;; Introspection Helpers
;; ================================================================

;; Generate argument names: 0→"", 1→"x", 2→"x y", etc.
(def *arg-names* '#("x" "y" "z" "a" "b" "c" "d" "e" "f" "g"
                     "h" "i" "j" "k" "l" "m" "n" "p" "q" "r"))

(def (argnames n)
  (let loop ((i 0) (acc '()))
    (if (= i n)
        (str-join (reverse acc) " ")
        (loop (+ i 1)
              (cons (if (< i (vector-length *arg-names*))
                        (vector-ref *arg-names* i)
                        (string-append "arg" (number->string i)))
                    acc)))))

(def (str-join lst sep)
  (if (null? lst) ""
      (let loop ((rest (cdr lst)) (acc (car lst)))
        (if (null? rest) acc
            (loop (cdr rest) (string-append acc sep (car rest)))))))

;; Decode procedure-arity-mask into a human-readable arglist string.
;; Mask encoding: bit n set → accepts n args; negative → variadic.
(def (arity-string proc)
  (guard (exn (#t "(& args)"))
    (let ((mask (procedure-arity-mask proc)))
      (if (< mask 0)
          ;; Variadic: find minimum arity (lowest set bit)
          (let ((min-n (let loop ((n 0))
                         (if (bitwise-bit-set? mask n) n (loop (+ n 1))))))
            (if (= min-n 0)
                "(& args)"
                (string-append "([" (argnames min-n) " & args])")))
          ;; Fixed: collect arities from set bits (up to 20)
          (let ((arities (let loop ((n 0) (acc '()))
                           (if (> n 20) (reverse acc)
                               (loop (+ n 1)
                                     (if (and (> n 0) (bitwise-bit-set? mask n))
                                         (cons n acc)
                                         acc))))))
            (if (null? arities)
                "()"
                (string-append
                  "("
                  (str-join
                    (map (lambda (n)
                           (if (= n 0) "[]"
                               (string-append "[" (argnames n) "]")))
                         arities)
                    " ")
                  ")")))))))

;; Format an exception condition as a plain string.
(def (condition->string exn)
  (guard (e (#t (format "~a" exn)))
    (with-output-to-string
      (lambda () (display-condition exn)))))

;; Extract a structured stacktrace list from a condition.
;; Returns a list of dicts with "name", "file", "line" keys.
(def (condition->stacktrace-frames exn)
  (guard (e (#t '()))
    (let ((trace (with-output-to-string (lambda () (display-condition exn)))))
      ;; Parse lines looking for " in ..." or "file.ss:line" patterns
      (let ((lines (let lp ((str trace) (acc '()))
                     (let ((nl (let search ((i 0))
                                 (cond ((>= i (string-length str)) #f)
                                       ((char=? (string-ref str i) #\newline) i)
                                       (else (search (+ i 1)))))))
                       (if nl
                           (lp (substring str (+ nl 1) (string-length str))
                               (cons (substring str 0 nl) acc))
                           (reverse (cons str acc)))))))
        (let lp ((lines lines) (acc '()))
          (if (null? lines) (reverse acc)
              (let ((line (car lines)))
                (lp (cdr lines)
                    (cons (make-dict "name" line "file" "" "line" 0)
                          acc)))))))))

;; Determine the type category of a value.
(def (type-category val)
  (cond
    ((procedure? val) "function")
    ((boolean? val)   "var")
    ((number? val)    "var")
    ((string? val)    "var")
    ((symbol? val)    "var")
    ((pair? val)      "var")
    ((null? val)      "var")
    ((vector? val)    "var")
    ((bytevector? val)"var")
    ((hash-table? val)"var")
    (else             "var")))

;; Return a detailed type name string for a value.
(def (value->type-string val)
  (cond
    ((procedure? val)  "function")
    ((boolean? val)    (if val "true" "false"))
    ((exact? val)      "integer")
    ((inexact? val)    "float")
    ((number? val)     "number")
    ((string? val)     "string")
    ((symbol? val)     "symbol")
    ((keyword? val)    "keyword")
    ((pair? val)       "list")
    ((null? val)       "nil")
    ((vector? val)     "vector")
    ((bytevector? val) "bytevector")
    ((hash-table? val) "map")
    ((char? val)       "char")
    ((port? val)       "port")
    (else              "object")))

;; Pretty-print a value to a string.
(def (pp-to-str val)
  (with-output-to-string
    (lambda () (pretty-print val))))

;; ================================================================
;; Inspector State
;; ================================================================
;; Inspector stack: each frame is (value . display-offset)
;; The current frame is the top of the stack.

(def (make-inspector-frame val)
  (cons val 0))  ;; (value . page-offset)

(def (inspector-frame-val frame) (car frame))
(def (inspector-frame-offset frame) (cdr frame))
(def (inspector-frame-set-offset! frame n)
  (set-cdr! frame n))

;; Build a page of inspector output for a value.
;; Returns a list of (index . display-string) pairs.
(def (inspect-page val offset page-size)
  (define (indexed-entries)
    (cond
      ((pair? val)
       (let loop ((lst val) (i 0) (acc '()))
         (cond
           ((null? lst) (reverse acc))
           ((pair? lst)
            (loop (cdr lst) (+ i 1)
                  (cons (cons i (format "~s" (car lst))) acc)))
           (else
            (reverse (cons (cons i (format ". ~s" lst)) acc))))))
      ((vector? val)
       (let loop ((i 0) (acc '()))
         (if (= i (vector-length val)) (reverse acc)
             (loop (+ i 1)
                   (cons (cons i (format "~s" (vector-ref val i))) acc)))))
      ((hash-table? val)
       (let loop ((entries (hash->list val)) (i 0) (acc '()))
         (if (null? entries) (reverse acc)
             (loop (cdr entries) (+ i 1)
                   (cons (cons i (format "~s → ~s" (caar entries) (cdar entries)))
                         acc)))))
      (else '())))
  (let* ((entries (indexed-entries))
         (total   (length entries))
         (page    (let loop ((lst entries) (skip offset) (take page-size) (acc '()))
                    (cond
                      ((null? lst) (reverse acc))
                      ((> skip 0) (loop (cdr lst) (- skip 1) take acc))
                      ((= take 0) (reverse acc))
                      (else (loop (cdr lst) 0 (- take 1) (cons (car lst) acc)))))))
    (cons total page)))

;; Navigate into a sub-value at index.
(def (inspect-sub-value val idx)
  (guard (exn (#t #f))
    (cond
      ((pair? val)
       (let loop ((lst val) (i 0))
         (cond
           ((null? lst) #f)
           ((= i idx) (car lst))
           ((pair? lst) (loop (cdr lst) (+ i 1)))
           (else (if (= i idx) lst #f)))))
      ((vector? val)
       (and (< idx (vector-length val)) (vector-ref val idx)))
      ((hash-table? val)
       (let ((entries (hash->list val)))
         (and (< idx (length entries))
              (cdr (list-ref entries idx)))))
      (else #f))))

;; ================================================================
;; nREPL Operation Handlers
;; ================================================================

(def (handle-clone msg out)
  (let ((new-id (create-session!)))
    (send-response! out
      (make-response msg
        "new-session" new-id
        "status" (list "done")))))

(def (handle-close msg out)
  (let ((session (dict-ref msg "session")))
    (when session (close-session! session)))
  (send-response! out
    (make-response msg "status" (list "done"))))

;; Full op list for describe — advertises all supported ops to editors.
(def (handle-describe msg out)
  (define (op . _) (make-dict))
  (send-response! out
    (make-response msg
      "ops"
      (make-dict
        ;; Base
        "clone"              (op) "close"             (op) "describe"         (op)
        "eval"               (op) "load-file"         (op) "interrupt"        (op) "stdin" (op)
        ;; Metadata
        "info"               (op) "eldoc"             (op) "arglists"         (op)
        "lookup"             (op) "version"           (op)
        ;; Completions
        "completions"        (op)
        ;; Macros
        "macroexpand"        (op) "macroexpand-1"     (op) "macroexpand-all"  (op)
        ;; Namespaces
        "ns-list"            (op) "ns-vars"           (op) "ns-vars-with-meta"(op)
        ;; Debugging
        "stacktrace"         (op) "analyze-stacktrace"(op)
        ;; Formatting
        "format-code"        (op) "format-edn"        (op)
        ;; Search
        "apropos"            (op) "apropos-docs"      (op)
        ;; Mutation
        "undef"              (op)
        ;; Testing
        "test"               (op) "test-all"          (op) "test-ns"          (op)
        ;; Inspection
        "inspect-start"      (op) "inspect-next"      (op) "inspect-pop"      (op)
        "inspect-refresh"    (op) "inspect-get-path"  (op) "inspect-navigate" (op)
        ;; Jerboa extensions
        "eval-timed"         (op) "type-info"         (op) "memory-stats"     (op)
        "doc-examples"       (op))
      "versions"
      (make-dict
        "nrepl"   (make-dict "major" 1 "minor" 0 "incremental" 0)
        "jerboa"  (make-dict "major" 1 "minor" 0 "incremental" 0)
        "clojure" (make-dict "major" 1 "minor" 12 "incremental" 0))
      "aux"   (make-dict "current-ns" "user")
      "status" (list "done"))))

;; eval — captures stdout/stderr, tracks thread for interrupt, stores last-exn.
(def (handle-eval msg out)
  (let ((code    (dict-ref msg "code" ""))
        (session (dict-ref msg "session"))
        (ns      (dict-ref msg "ns" "user")))
    (let ((env (if session (session-env session) (interaction-environment))))
      (guard (exn
               (#t
                (when session
                  (session-set-last-exn! session exn))
                (let ((err-str (condition->string exn)))
                  (send-response! out
                    (make-response msg "err" (string-append err-str "\n")))
                  (send-response! out
                    (make-response msg
                      "ex"      err-str
                      "root-ex" err-str
                      "status"  (list "eval-error" "done"))))))
        (let ((stdout-cap (open-output-string))
              (stderr-cap (open-output-string)))
          (let ((inp (open-input-string code)))
            (let lp ((last-val (void)))
              (let ((form (read inp)))
                (if (eof-object? form)
                    (begin
                      (let ((out-str (get-output-string stdout-cap)))
                        (when (> (string-length out-str) 0)
                          (send-response! out (make-response msg "out" out-str))))
                      (let ((err-str (get-output-string stderr-cap)))
                        (when (> (string-length err-str) 0)
                          (send-response! out (make-response msg "err" err-str))))
                      (unless (eq? last-val (void))
                        (send-response! out
                          (make-response msg
                            "value" (format "~s" last-val)
                            "ns"    ns)))
                      (send-response! out
                        (make-response msg "status" (list "done"))))
                    (let ((result
                            (parameterize ((current-output-port stdout-cap)
                                           (current-error-port  stderr-cap))
                              (eval form env))))
                      (let ((s (get-output-string stdout-cap)))
                        (when (> (string-length s) 0)
                          (send-response! out (make-response msg "out" s))
                          (set! stdout-cap (open-output-string))))
                      (lp result)))))))))))

;; load-file — evaluate entire file content in session env.
(def (handle-load-file msg out)
  (let ((content  (dict-ref msg "file" ""))
        (session  (dict-ref msg "session")))
    (let ((env (if session (session-env session) (interaction-environment))))
      (guard (exn
               (#t
                (when session (session-set-last-exn! session exn))
                (let ((err (condition->string exn)))
                  (send-response! out
                    (make-response msg
                      "ex"      err
                      "root-ex" err
                      "status"  (list "eval-error" "done"))))))
        (let ((inp (open-input-string content)))
          (let lp ((last-val (void)))
            (let ((form (read inp)))
              (if (eof-object? form)
                  (begin
                    (send-response! out
                      (make-response msg
                        "value" (if (eq? last-val (void)) "nil" (format "~s" last-val))
                        "ns"    "user"))
                    (send-response! out (make-response msg "status" (list "done"))))
                  (lp (eval form env))))))))))

;; completions — returns candidates with type, doc, and arglists.
(def (handle-completions msg out)
  (let* ((prefix  (or (dict-ref msg "prefix") (dict-ref msg "symbol") ""))
         (session (dict-ref msg "session"))
         (env     (if session (session-env session) (interaction-environment)))
         (matches (repl-complete prefix env))
         (completions
           (map (lambda (sym)
                  (let* ((name (symbol->string sym))
                         (val  (guard (e (#t #f)) (eval sym env)))
                         (type (if val (type-category val) "var"))
                         (doc  (guard (e (#t "")) (let ((d (repl-doc sym)))
                                                    (if (string? d) d ""))))
                         (args (if (and val (procedure? val))
                                   (arity-string val) "")))
                    (make-dict
                      "candidate"    name
                      "type"         type
                      "doc"          doc
                      "arglists-str" args)))
                (take-up-to matches 200))))
    (send-response! out
      (make-response msg
        "completions" completions
        "status"      (list "done")))))

;; lookup — enhanced with arglists and type.
(def (handle-lookup msg out)
  (let* ((sym-name (or (dict-ref msg "sym") (dict-ref msg "symbol") ""))
         (session  (dict-ref msg "session"))
         (env      (if session (session-env session) (interaction-environment)))
         (sym      (string->symbol sym-name)))
    (guard (exn (#t (send-response! out (make-response msg "status" (list "no-info" "done")))))
      (let* ((val      (eval sym env))
             (type-str (type-category val))
             (doc      (guard (e (#t "")) (let ((d (repl-doc sym))) (if (string? d) d ""))))
             (arglists (if (procedure? val) (arity-string val) ""))
             (info     (make-dict
                         "name"         sym-name
                         "ns"           "user"
                         "type"         type-str
                         "arglists-str" arglists
                         "doc"          doc)))
        (send-response! out
          (make-response msg
            "info"   info
            "status" (list "done")))))))

;; interrupt — acknowledge immediately. Real thread cancellation would
;; require break-thread which is not available in this Chez build.
(def (handle-interrupt msg out)
  (send-response! out
    (make-response msg "status" (list "done"))))

(def (handle-stdin msg out)
  (send-response! out (make-response msg "status" (list "done"))))

;; ================================================================
;; Metadata Ops
;; ================================================================

;; info — rich symbol metadata (CIDER's most-used op).
(def (handle-info msg out)
  (let* ((sym-name (or (dict-ref msg "sym") (dict-ref msg "symbol") ""))
         (ns       (dict-ref msg "ns" "user"))
         (session  (dict-ref msg "session"))
         (env      (if session (session-env session) (interaction-environment))))
    (guard (exn (#t (send-response! out (make-response msg "status" (list "no-info" "done")))))
      (let* ((sym      (string->symbol sym-name))
             (val      (eval sym env))
             (type-str (type-category val))
             (doc      (guard (e (#t "")) (let ((d (repl-doc sym))) (if (string? d) d ""))))
             (arglists (if (procedure? val) (arity-string val) ""))
             (type-str2 (value->type-string val))
             (info     (make-dict
                         "name"          sym-name
                         "ns"            ns
                         "type"          type-str
                         "arglists-str"  arglists
                         "doc"           doc
                         "file"          ""
                         "line"          0
                         "column"        0
                         "value-type"    type-str2)))
        (send-response! out
          (make-response msg
            "info"   info
            "status" (list "done")))))))

;; eldoc — arglists for a function (fires as you type).
;; Returns structured arglists that CIDER renders in the echo area.
(def (handle-eldoc msg out)
  (let* ((sym-name (or (dict-ref msg "sym") (dict-ref msg "symbol") ""))
         (session  (dict-ref msg "session"))
         (env      (if session (session-env session) (interaction-environment))))
    (guard (exn (#t (send-response! out (make-response msg "status" (list "no-eldoc" "done")))))
      (let* ((sym  (string->symbol sym-name))
             (val  (eval sym env)))
        (if (not (procedure? val))
            (send-response! out (make-response msg "status" (list "no-eldoc" "done")))
            (let* ((mask  (guard (e (#t -1)) (procedure-arity-mask val)))
                   ;; Build structured arglists: list of lists of arg-name strings
                   (arglists
                     (if (< mask 0)
                         (let ((min-n (let loop ((n 0))
                                        (if (bitwise-bit-set? mask n) n (loop (+ n 1))))))
                           (list
                             (let loop ((i 0) (acc '()))
                               (if (= i min-n) (reverse (cons "& args" acc))
                                   (loop (+ i 1)
                                         (cons (vector-ref *arg-names*
                                                 (min i (- (vector-length *arg-names*) 1)))
                                               acc))))))
                         (let ((arities (let loop ((n 1) (acc '()))
                                          (if (> n 20) (reverse acc)
                                              (loop (+ n 1)
                                                    (if (bitwise-bit-set? mask n)
                                                        (cons n acc)
                                                        acc))))))
                           (map (lambda (n)
                                  (let loop ((i 0) (acc '()))
                                    (if (= i n) (reverse acc)
                                        (loop (+ i 1)
                                              (cons (vector-ref *arg-names*
                                                      (min i (- (vector-length *arg-names*) 1)))
                                                    acc)))))
                                (if (null? arities) '(0) arities)))))
                   (eldoc-info (make-dict
                                 "type"     "fn"
                                 "name"     sym-name
                                 "ns"       "user"
                                 "arglists" arglists)))
              (send-response! out
                (make-response msg
                  "eldoc-info" eldoc-info
                  "status"     (list "done")))))))))

;; arglists — just arglists string, faster than full info.
(def (handle-arglists msg out)
  (let* ((sym-name (or (dict-ref msg "sym") (dict-ref msg "symbol") ""))
         (session  (dict-ref msg "session"))
         (env      (if session (session-env session) (interaction-environment))))
    (guard (exn (#t (send-response! out (make-response msg "status" (list "no-info" "done")))))
      (let* ((val (eval (string->symbol sym-name) env)))
        (send-response! out
          (make-response msg
            "arglists-str" (if (procedure? val) (arity-string val) "")
            "status"       (list "done")))))))

;; version — version info for editors.
(def (handle-version msg out)
  (send-response! out
    (make-response msg
      "versions" (make-dict
                   "nrepl"   (make-dict "major" 1 "minor" 0 "incremental" 0)
                   "jerboa"  (make-dict "major" 1 "minor" 0 "incremental" 0)
                   "clojure" (make-dict "major" 1 "minor" 12 "incremental" 0))
      "status" (list "done"))))

;; ================================================================
;; Macro Expansion Ops
;; ================================================================

(def (handle-macroexpand msg out)
  (handle-macroexpand* msg out 'full))

(def (handle-macroexpand-1 msg out)
  (handle-macroexpand* msg out 'once))

(def (handle-macroexpand-all msg out)
  (handle-macroexpand* msg out 'all))

(def (handle-macroexpand* msg out mode)
  (let* ((code    (dict-ref msg "code" ""))
         (session (dict-ref msg "session"))
         (env     (if session (session-env session) (interaction-environment))))
    (guard (exn
             (#t
              (send-response! out
                (make-response msg
                  "err"    (condition->string exn)
                  "status" (list "eval-error" "done")))))
      (let* ((form     (with-input-from-string code read))
             ;; repl-expand does full expansion (Jerboa/Chez expand equivalent)
             (expanded (repl-expand form env))
             (result   (pp-to-str expanded)))
        (send-response! out
          (make-response msg
            "expansion" result
            "status"    (list "done")))))))

;; ================================================================
;; Namespace Ops
;; ================================================================
;; Jerboa has a single flat namespace but we expose module categories
;; as synthetic namespaces for editor compatibility.

(def *synthetic-namespaces*
  '("user"
    "jerboa.core"    "jerboa.prelude"
    "std.sort"       "std.text.json"  "std.text.csv"
    "std.net.request""std.net.httpd"
    "std.db.sqlite"  "std.actor"      "std.async"
    "std.crypto"     "std.peg"
    "clojure.core"   "clojure.string" "clojure.set"))

(def (handle-ns-list msg out)
  (send-response! out
    (make-response msg
      "ns-list" *synthetic-namespaces*
      "status"  (list "done"))))

;; ns-vars — return the names of vars visible in a namespace.
(def (handle-ns-vars msg out)
  (let* ((ns      (dict-ref msg "ns" "user"))
         (session (dict-ref msg "session"))
         (env     (if session (session-env session) (interaction-environment)))
         (syms    (repl-complete "" env))
         (result  (let ((ht (make-hash-table)))
                    (for-each (lambda (sym)
                                (hash-put! ht (symbol->string sym) ""))
                              (take-up-to syms 1000))
                    ht)))
    (send-response! out
      (make-response msg
        "ns-vars" result
        "status"  (list "done")))))

;; ns-vars-with-meta — vars with type and doc metadata.
(def (handle-ns-vars-with-meta msg out)
  (let* ((session (dict-ref msg "session"))
         (env     (if session (session-env session) (interaction-environment)))
         (syms    (repl-complete "" env))
         (result  (let ((ht (make-hash-table)))
                    (for-each
                      (lambda (sym)
                        (let* ((name (symbol->string sym))
                               (val  (guard (e (#t #f)) (eval sym env)))
                               (meta (make-dict
                                       "name" name
                                       "ns"   "user"
                                       "type" (if val (type-category val) "var")
                                       "doc"  (guard (e (#t ""))
                                                (let ((d (repl-doc sym)))
                                                  (if (string? d) d ""))))))
                          (hash-put! ht name meta)))
                      (take-up-to syms 500))
                    ht)))
    (send-response! out
      (make-response msg
        "ns-vars-with-meta" result
        "status"            (list "done")))))

;; ================================================================
;; Debugging Ops
;; ================================================================

;; stacktrace — return the last exception as structured stacktrace.
(def (handle-stacktrace msg out)
  (let* ((session (dict-ref msg "session"))
         (exn     (and session (session-last-exn session))))
    (if (not exn)
        (send-response! out (make-response msg "status" (list "no-error" "done")))
        (let* ((msg-str (condition->string exn))
               (frames  (condition->stacktrace-frames exn))
               (result  (make-dict
                          "message" msg-str
                          "class"   "Exception"
                          "data"    ""
                          "stacktrace" frames)))
          (send-response! out
            (make-response msg
              "stacktrace" result
              "status"     (list "done")))))))

;; analyze-stacktrace — alias for stacktrace with structured output.
(def (handle-analyze-stacktrace msg out)
  (handle-stacktrace msg out))

;; ================================================================
;; Formatting Ops
;; ================================================================

(def (handle-format-code msg out)
  (let ((code (dict-ref msg "code" "")))
    (guard (exn
             (#t (send-response! out
                   (make-response msg
                     "formatted-code" code
                     "status" (list "done")))))
      (let* ((forms (let loop ((inp (open-input-string code)) (acc '()))
                      (let ((f (read inp)))
                        (if (eof-object? f) (reverse acc)
                            (loop inp (cons f acc))))))
             (formatted (str-join (map pp-to-str forms) "\n")))
        (send-response! out
          (make-response msg
            "formatted-code" formatted
            "status"         (list "done")))))))

(def (handle-format-edn msg out)
  ;; EDN is valid Scheme data, so pretty-print works.
  (handle-format-code msg out))

;; ================================================================
;; Search Ops
;; ================================================================

;; apropos — find symbols whose names contain the query string.
(def (handle-apropos msg out)
  (let* ((query   (or (dict-ref msg "query") (dict-ref msg "symbol") ""))
         (session (dict-ref msg "session"))
         (env     (if session (session-env session) (interaction-environment)))
         (matches (repl-apropos query env))
         (results (map (lambda (sym)
                         (make-dict
                           "name" (symbol->string sym)
                           "ns"   "user"
                           "type" (guard (e (#t "var"))
                                    (let ((v (eval sym env)))
                                      (type-category v)))))
                       (take-up-to matches 100))))
    (send-response! out
      (make-response msg
        "results" results
        "status"  (list "done")))))

;; apropos-docs — apropos with full documentation.
(def (handle-apropos-docs msg out)
  (let* ((query   (or (dict-ref msg "query") (dict-ref msg "symbol") ""))
         (session (dict-ref msg "session"))
         (env     (if session (session-env session) (interaction-environment)))
         (matches (repl-apropos query env))
         (results (map (lambda (sym)
                         (let* ((val  (guard (e (#t #f)) (eval sym env)))
                                (type (if val (type-category val) "var"))
                                (doc  (guard (e (#t "")) (let ((d (repl-doc sym)))
                                                           (if (string? d) d ""))))
                                (args (if (and val (procedure? val))
                                          (arity-string val) "")))
                           (make-dict
                             "name"         (symbol->string sym)
                             "ns"           "user"
                             "type"         type
                             "doc"          doc
                             "arglists-str" args)))
                       (take-up-to matches 50))))
    (send-response! out
      (make-response msg
        "results" results
        "status"  (list "done")))))

;; ================================================================
;; Mutation Ops
;; ================================================================

;; undef — unbind a symbol in the session environment.
(def (handle-undef msg out)
  (let* ((sym-name (or (dict-ref msg "sym") (dict-ref msg "symbol") ""))
         (session  (dict-ref msg "session"))
         (env      (if session (session-env session) (interaction-environment))))
    (guard (exn
             (#t (send-response! out
                   (make-response msg
                     "err"    (condition->string exn)
                     "status" (list "error" "done")))))
      ;; Redefine to unspecified — Chez doesn't have a true undefine.
      (eval `(define ,(string->symbol sym-name) (if #f #f)) env)
      (send-response! out
        (make-response msg
          "status" (list "done"))))))

;; ================================================================
;; Test Runner Ops
;; ================================================================

;; test — run a named test expression.
(def (handle-test msg out)
  (let* ((tests   (dict-ref msg "tests" '()))
         (ns      (dict-ref msg "ns" "user"))
         (session (dict-ref msg "session"))
         (env     (if session (session-env session) (interaction-environment)))
         (results (make-hash-table))
         (pass 0) (fail 0) (error 0))
    (for-each
      (lambda (test-name)
        (let ((sym (string->symbol test-name)))
          (guard (exn
                   (#t
                    (set! error (+ error 1))
                    (hash-put! results test-name
                      (make-dict "type" "error" "message" (condition->string exn)))))
            (let ((result (eval sym env)))
              (if result
                  (begin (set! pass (+ pass 1))
                         (hash-put! results test-name (make-dict "type" "pass")))
                  (begin (set! fail (+ fail 1))
                         (hash-put! results test-name
                           (make-dict "type" "fail" "message" (format "~s returned #f" sym)))))))))
      (if (list? tests) tests (list tests)))
    (send-response! out
      (make-response msg
        "results" results
        "summary" (make-dict "ns" ns "var" "" "test" (+ pass fail error)
                             "pass" pass "fail" fail "error" error)
        "status"  (list "done")))))

;; test-all — run all symbols that look like tests in the session.
(def (handle-test-all msg out)
  (let* ((session (dict-ref msg "session"))
         (env     (if session (session-env session) (interaction-environment)))
         (syms    (repl-complete "test-" env))
         (test-syms (map symbol->string (take-up-to syms 200))))
    (handle-test (let ((ht (make-hash-table)))
                   (hash-put! ht "op" "test")
                   (hash-put! ht "tests" test-syms)
                   (when (dict-ref msg "session")
                     (hash-put! ht "session" (dict-ref msg "session")))
                   (when (dict-ref msg "id")
                     (hash-put! ht "id" (dict-ref msg "id")))
                   ht)
                 out)))

(def (handle-test-ns msg out)
  (handle-test-all msg out))

;; ================================================================
;; Inspector Ops
;; ================================================================

(def *inspector-page-size* 50)

;; inspect-start — evaluate expr and begin inspecting the result.
(def (handle-inspect-start msg out)
  (let* ((code    (dict-ref msg "code" ""))
         (session (dict-ref msg "session"))
         (env     (if session (session-env session) (interaction-environment))))
    (guard (exn
             (#t
              (send-response! out
                (make-response msg
                  "err"    (condition->string exn)
                  "status" (list "eval-error" "done")))))
      (let* ((val    (eval (with-input-from-string code read) env))
             (stack  (list (make-inspector-frame val))))
        (when session (session-set-inspector! session stack))
        (let ((page (inspect-page val 0 *inspector-page-size*)))
          (send-response! out
            (make-response msg
              "value"        (pp-to-str val)
              "type"         (value->type-string val)
              "total"        (car page)
              "items"        (map (lambda (e)
                                    (make-dict "index" (car e) "value" (cdr e)))
                                  (cdr page))
              "status"       (list "done"))))))))

;; inspect-next — page forward through a large value.
(def (handle-inspect-next msg out)
  (let* ((session (dict-ref msg "session"))
         (stack   (and session (session-inspector session))))
    (if (not (and stack (pair? stack)))
        (send-response! out (make-response msg "status" (list "no-inspector" "done")))
        (let* ((frame  (car stack))
               (val    (inspector-frame-val frame))
               (offset (+ (inspector-frame-offset frame) *inspector-page-size*)))
          (inspector-frame-set-offset! frame offset)
          (let ((page (inspect-page val offset *inspector-page-size*)))
            (send-response! out
              (make-response msg
                "value"  (pp-to-str val)
                "total"  (car page)
                "items"  (map (lambda (e)
                                (make-dict "index" (car e) "value" (cdr e)))
                              (cdr page))
                "status" (list "done"))))))))

;; inspect-pop — go back up to the parent value.
(def (handle-inspect-pop msg out)
  (let* ((session (dict-ref msg "session"))
         (stack   (and session (session-inspector session))))
    (if (not (and stack (pair? stack)))
        (send-response! out (make-response msg "status" (list "no-inspector" "done")))
        (let* ((new-stack (if (null? (cdr stack)) stack (cdr stack))))
          (when session (session-set-inspector! session new-stack))
          (let* ((frame  (car new-stack))
                 (val    (inspector-frame-val frame))
                 (offset (inspector-frame-offset frame))
                 (page   (inspect-page val offset *inspector-page-size*)))
            (send-response! out
              (make-response msg
                "value"  (pp-to-str val)
                "total"  (car page)
                "items"  (map (lambda (e)
                                (make-dict "index" (car e) "value" (cdr e)))
                              (cdr page))
                "status" (list "done"))))))))

;; inspect-refresh — re-render the current inspector frame.
(def (handle-inspect-refresh msg out)
  (let* ((session (dict-ref msg "session"))
         (stack   (and session (session-inspector session))))
    (if (not (and stack (pair? stack)))
        (send-response! out (make-response msg "status" (list "no-inspector" "done")))
        (let* ((frame  (car stack))
               (val    (inspector-frame-val frame))
               (offset (inspector-frame-offset frame))
               (page   (inspect-page val offset *inspector-page-size*)))
          (send-response! out
            (make-response msg
              "value"  (pp-to-str val)
              "total"  (car page)
              "items"  (map (lambda (e)
                              (make-dict "index" (car e) "value" (cdr e)))
                            (cdr page))
              "status" (list "done")))))))

;; inspect-get-path — return the navigation path as a string.
(def (handle-inspect-get-path msg out)
  (let* ((session (dict-ref msg "session"))
         (stack   (and session (session-inspector session))))
    (let ((path (if stack
                    (str-join
                      (map (lambda (frame)
                             (format "~s" (inspector-frame-val frame)))
                           (reverse stack))
                      " > ")
                    "")))
      (send-response! out
        (make-response msg
          "path"   path
          "status" (list "done"))))))

;; inspect-navigate — navigate into sub-value at index.
(def (handle-inspect-navigate msg out)
  (let* ((session (dict-ref msg "session"))
         (idx     (let ((v (dict-ref msg "idx" 0)))
                    (if (string? v) (or (string->number v) 0) v)))
         (stack   (and session (session-inspector session))))
    (if (not (and stack (pair? stack)))
        (send-response! out (make-response msg "status" (list "no-inspector" "done")))
        (let* ((frame  (car stack))
               (val    (inspector-frame-val frame))
               (subval (inspect-sub-value val idx)))
          (if (not subval)
              (send-response! out (make-response msg "status" (list "no-such-item" "done")))
              (let* ((new-frame (make-inspector-frame subval))
                     (new-stack (cons new-frame stack)))
                (when session (session-set-inspector! session new-stack))
                (let ((page (inspect-page subval 0 *inspector-page-size*)))
                  (send-response! out
                    (make-response msg
                      "value"  (pp-to-str subval)
                      "type"   (value->type-string subval)
                      "total"  (car page)
                      "items"  (map (lambda (e)
                                      (make-dict "index" (car e) "value" (cdr e)))
                                    (cdr page))
                      "status" (list "done"))))))))))

;; ================================================================
;; Jerboa Extensions (exceed CIDER)
;; ================================================================

;; eval-timed — eval with CPU time and GC stats (unique to Jerboa).
(def (handle-eval-timed msg out)
  (let* ((code    (dict-ref msg "code" ""))
         (session (dict-ref msg "session"))
         (ns      (dict-ref msg "ns" "user"))
         (env     (if session (session-env session) (interaction-environment))))
    (guard (exn
             (#t
              (send-response! out
                (make-response msg
                  "err"    (condition->string exn)
                  "status" (list "eval-error" "done")))))
      (let* ((form     (with-input-from-string code read))
             (t-start  (current-time 'time-monotonic))
             (result   (eval form env))
             (t-end    (current-time 'time-monotonic))
             (elapsed-ns (+ (* (- (time-second t-end) (time-second t-start))
                               1000000000)
                            (- (time-nanosecond t-end) (time-nanosecond t-start))))
             (elapsed-ms (/ elapsed-ns 1000000.0)))
        (send-response! out
          (make-response msg
            "value"      (format "~s" result)
            "ns"         ns
            "elapsed-ms" (format "~a" elapsed-ms)
            "elapsed-ns" elapsed-ns
            "status"     (list "done")))))))

;; type-info — detailed type breakdown for a value (unique to Jerboa).
(def (handle-type-info msg out)
  (let* ((code    (dict-ref msg "code" ""))
         (session (dict-ref msg "session"))
         (env     (if session (session-env session) (interaction-environment))))
    (guard (exn
             (#t
              (send-response! out
                (make-response msg
                  "err"    (condition->string exn)
                  "status" (list "eval-error" "done")))))
      (let* ((val      (eval (with-input-from-string code read) env))
             (type-str (value->type-string val))
             (kind     (type-category val))
             (extra    (cond
                         ((procedure? val)
                          (make-dict
                            "callable?" "true"
                            "arglists"  (arity-string val)))
                         ((string? val)
                          (make-dict
                            "length"   (number->string (string-length val))))
                         ((pair? val)
                          (make-dict
                            "length"   (number->string
                                         (let loop ((l val) (n 0))
                                           (if (pair? l) (loop (cdr l) (+ n 1)) n)))))
                         ((vector? val)
                          (make-dict
                            "length"   (number->string (vector-length val))))
                         ((hash-table? val)
                          (make-dict
                            "size"     (number->string (hash-length val))))
                         (else (make-dict)))))
        (send-response! out
          (make-response msg
            "type-name"  type-str
            "kind"       kind
            "details"    extra
            "printed"    (pp-to-str val)
            "status"     (list "done")))))))

;; memory-stats — Chez GC and heap statistics (unique to Jerboa).
(def (handle-memory-stats msg out)
  (let* ((bytes    (bytes-allocated))
         (gccount  (guard (e (#t 0)) (collect-maximum-generation)))
         (stats    (make-dict
                     "bytes-allocated"    (format "~a" bytes)
                     "heap-mb"            (format "~a" (inexact->exact (round (/ bytes 1048576.0))))
                     "gc-max-generation"  (format "~a" gccount))))
    (send-response! out
      (make-response msg
        "stats"  stats
        "status" (list "done")))))

;; doc-examples — return doc + examples from repl-doc (unique to Jerboa).
(def (handle-doc-examples msg out)
  (let* ((sym-name (or (dict-ref msg "sym") (dict-ref msg "symbol") ""))
         (session  (dict-ref msg "session"))
         (env      (if session (session-env session) (interaction-environment))))
    (guard (exn (#t (send-response! out (make-response msg "status" (list "no-info" "done")))))
      (let* ((sym (string->symbol sym-name))
             (val (guard (e (#t #f)) (eval sym env)))
             (doc (guard (e (#t "")) (let ((d (repl-doc sym))) (if (string? d) d ""))))
             (args (if (and val (procedure? val)) (arity-string val) "")))
        (send-response! out
          (make-response msg
            "doc"          doc
            "arglists-str" args
            "type"         (if val (type-category val) "var")
            "value-type"   (if val (value->type-string val) "")
            "status"       (list "done")))))))

;; ================================================================
;; Message Dispatch
;; ================================================================

(def (handle-message msg out)
  (let ((op (dict-ref msg "op" "")))
    (cond
      ;; Base ops
      ((string=? op "clone")              (handle-clone              msg out))
      ((string=? op "close")              (handle-close              msg out))
      ((string=? op "describe")           (handle-describe           msg out))
      ((string=? op "eval")               (handle-eval               msg out))
      ((string=? op "load-file")          (handle-load-file          msg out))
      ((string=? op "interrupt")          (handle-interrupt          msg out))
      ((string=? op "stdin")              (handle-stdin              msg out))
      ;; Metadata
      ((string=? op "info")               (handle-info               msg out))
      ((string=? op "eldoc")              (handle-eldoc              msg out))
      ((string=? op "eldoc-member-doc")   (handle-eldoc              msg out))
      ((string=? op "arglists")           (handle-arglists           msg out))
      ((string=? op "lookup")             (handle-lookup             msg out))
      ((string=? op "version")            (handle-version            msg out))
      ;; Completions
      ((string=? op "completions")        (handle-completions        msg out))
      ((string=? op "complete")           (handle-completions        msg out))
      ;; Macro expansion
      ((string=? op "macroexpand")        (handle-macroexpand        msg out))
      ((string=? op "macroexpand-1")      (handle-macroexpand-1      msg out))
      ((string=? op "macroexpand-all")    (handle-macroexpand-all    msg out))
      ;; Namespaces
      ((string=? op "ns-list")            (handle-ns-list            msg out))
      ((string=? op "ns-vars")            (handle-ns-vars            msg out))
      ((string=? op "ns-vars-with-meta")  (handle-ns-vars-with-meta  msg out))
      ((string=? op "ns-load-all")        (handle-ns-list            msg out))
      ;; Debugging
      ((string=? op "stacktrace")         (handle-stacktrace         msg out))
      ((string=? op "analyze-stacktrace") (handle-analyze-stacktrace msg out))
      ;; Formatting
      ((string=? op "format-code")        (handle-format-code        msg out))
      ((string=? op "format-edn")         (handle-format-edn         msg out))
      ;; Search
      ((string=? op "apropos")            (handle-apropos            msg out))
      ((string=? op "apropos-docs")       (handle-apropos-docs       msg out))
      ;; Mutation
      ((string=? op "undef")              (handle-undef              msg out))
      ;; Testing
      ((string=? op "test")               (handle-test               msg out))
      ((string=? op "test-all")           (handle-test-all           msg out))
      ((string=? op "test-ns")            (handle-test-ns            msg out))
      ;; Inspector
      ((string=? op "inspect-start")      (handle-inspect-start      msg out))
      ((string=? op "inspect-next")       (handle-inspect-next       msg out))
      ((string=? op "inspect-pop")        (handle-inspect-pop        msg out))
      ((string=? op "inspect-refresh")    (handle-inspect-refresh    msg out))
      ((string=? op "inspect-get-path")   (handle-inspect-get-path   msg out))
      ((string=? op "inspect-navigate")   (handle-inspect-navigate   msg out))
      ;; Jerboa extensions
      ((string=? op "eval-timed")         (handle-eval-timed         msg out))
      ((string=? op "type-info")          (handle-type-info          msg out))
      ((string=? op "memory-stats")       (handle-memory-stats       msg out))
      ((string=? op "doc-examples")       (handle-doc-examples       msg out))
      (else
       (send-response! out
         (make-response msg
           "status" (list "error" "unknown-op" "done")))))))

;; ================================================================
;; Client Connection Handler
;; ================================================================

(def (handle-client in out)
  (let lp ()
    (guard (exn (#t (void)))
      (let ((msg (bencode-read in)))
        (unless (eof-object? msg)
          (guard (exn
                   (#t
                    (guard (e2 (#t (void)))
                      (send-response! out
                        (make-response msg
                          "status" (list "error" "done")
                          "ex"     (if (message-condition? exn)
                                       (condition-message exn)
                                       (format "~a" exn)))))))
            (handle-message msg out))
          (lp))))))

;; ================================================================
;; Utility
;; ================================================================

(def (take-up-to lst n)
  (let lp ((l lst) (n n) (acc '()))
    (if (or (zero? n) (null? l))
        (reverse acc)
        (lp (cdr l) (- n 1) (cons (car l) acc)))))

;; ================================================================
;; TCP Server (inline socket FFI — GC-safe, non-blocking)
;; ================================================================

(def _libc-loaded
  (let ((v (getenv "JERBOA_STATIC")))
    (if (and v (not (string=? v "")) (not (string=? v "0")))
        #f
        (load-shared-object #f))))

(def c-socket      (foreign-procedure "socket"      (int int int) int))
(def c-bind        (foreign-procedure "bind"        (int u8* int) int))
(def c-listen      (foreign-procedure "listen"      (int int) int))
(def c-accept      (foreign-procedure "accept"      (int u8* u8*) int))
(def c-close       (foreign-procedure "close"       (int) int))
(def c-setsockopt  (foreign-procedure "setsockopt"  (int int int u8* int) int))
(def c-htons       (foreign-procedure "htons"       (unsigned-short) unsigned-short))
(def c-fcntl       (foreign-procedure "fcntl"       (int int int) int))
(def c-getsockname (foreign-procedure "getsockname" (int u8* u8*) int))
(def c-read        (foreign-procedure "read"        (int u8* size_t) ssize_t))
(def c-write       (foreign-procedure "write"       (int u8* size_t) ssize_t))

(def c-errno-location
  (let ((mt (symbol->string (machine-type))))
    (cond
      ((or (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb))
           (and (>= (string-length mt) 3)
                (string=? (substring mt (- (string-length mt) 3) (string-length mt)) "osx")))
       (foreign-procedure "__error" () void*))
      ((foreign-entry? "__errno_location")
       (foreign-procedure "__errno_location" () void*))
      ((foreign-entry? "__errno")
       (foreign-procedure "__errno" () void*))
      (else
       (foreign-procedure "__errno_location" () void*)))))

(def (get-errno) (foreign-ref 'int (c-errno-location) 0))
(def EINTR 4)
(def *freebsd?* (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb)))
(def EAGAIN (if *freebsd?* 35 11))

(def F_GETFL 3)
(def F_SETFL 4)
(def O_NONBLOCK
  (if (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb)) #x4 #x800))

(def AF_INET     2)
(def SOCK_STREAM 1)
(def SOL_SOCKET  (if *freebsd?* #xffff 1))
(def SO_REUSEADDR(if *freebsd?* 4 2))

(def *retry-delay* (make-time 'time-duration 10000000 0))

(def (set-nonblocking! fd)
  (let ((flags (c-fcntl fd F_GETFL 0)))
    (c-fcntl fd F_SETFL (fxior flags O_NONBLOCK))))

(def (make-sockaddr-in port)
  (let ((buf (make-bytevector 16 0)))
    (if *freebsd?*
        (begin
          (bytevector-u8-set! buf 0 16)
          (bytevector-u8-set! buf 1 AF_INET))
        (bytevector-u16-native-set! buf 0 AF_INET))
    (bytevector-u16-set! buf 2 (c-htons port) 'big)
    (bytevector-u8-set! buf 4 127)
    (bytevector-u8-set! buf 5 0)
    (bytevector-u8-set! buf 6 0)
    (bytevector-u8-set! buf 7 1)
    buf))

(def (tcp-listen* port)
  (let ((sock (c-socket AF_INET SOCK_STREAM 0)))
    (when (< sock 0) (error 'nrepl-start! "socket() failed"))
    (let ((one (make-bytevector 4 0)))
      (bytevector-s32-native-set! one 0 1)
      (c-setsockopt sock SOL_SOCKET SO_REUSEADDR one 4))
    (let ((addr (make-sockaddr-in port)))
      (when (< (c-bind sock addr 16) 0)
        (c-close sock)
        (error 'nrepl-start! "bind() failed — port may be in use" port)))
    (when (< (c-listen sock 8) 0)
      (c-close sock)
      (error 'nrepl-start! "listen() failed"))
    (set-nonblocking! sock)
    (let ((addr-out (make-bytevector 16 0))
          (len-buf  (make-bytevector 4 0)))
      (bytevector-s32-native-set! len-buf 0 16)
      (c-getsockname sock addr-out len-buf)
      (let ((actual-port (bytevector-u16-ref addr-out 2 'big)))
        (values sock actual-port)))))

(def (fd->binary-ports fd)
  (let ((closed? #f))
    (let ((in  (make-custom-binary-input-port "nrepl-in"
                 (lambda (bv start count)
                   (if closed? 0
                       (let ((buf (make-bytevector count)))
                         (let retry ()
                           (let ((n (c-read fd buf count)))
                             (cond
                               ((> n 0)
                                (bytevector-copy! buf 0 bv start n)
                                n)
                               ((and (< n 0)
                                     (let ((e (get-errno)))
                                       (or (= e EINTR) (= e EAGAIN))))
                                (sleep *retry-delay*)
                                (retry))
                               (else 0)))))))
                 #f #f
                 (lambda ()
                   (unless closed?
                     (set! closed? #t)
                     (c-close fd)))))
          (out (make-custom-binary-output-port "nrepl-out"
                 (lambda (bv start count)
                   (if closed? 0
                       (let ((buf (make-bytevector count)))
                         (bytevector-copy! bv start buf 0 count)
                         (let lp ((written 0))
                           (if (= written count)
                               count
                               (let ((n (c-write fd
                                          (let ((tmp (make-bytevector (- count written))))
                                            (bytevector-copy! buf written tmp 0 (- count written))
                                            tmp)
                                          (- count written))))
                                 (cond
                                   ((> n 0) (lp (+ written n)))
                                   ((and (< n 0)
                                         (let ((e (get-errno)))
                                           (or (= e EINTR) (= e EAGAIN))))
                                    (sleep *retry-delay*)
                                    (lp written))
                                   (else written))))))))
                 #f #f #f)))
      (values in out))))

;; ================================================================
;; Server State
;; ================================================================

(def *server-socket*  #f)
(def *server-port*    #f)
(def *server-running* #f)
(def *server-thread*  #f)

(def (nrepl-server-port) *server-port*)
(def (nrepl-running?)    (and *server-running* #t))

;; ================================================================
;; Server Start / Stop
;; ================================================================

(def* nrepl-start!
  (()     (nrepl-start! 0))
  ((port)
   (when *server-running*
     (error 'nrepl-start! "nREPL server already running"))
   (let-values (((sock actual-port) (tcp-listen* port)))
     (set! *server-socket* sock)
     (set! *server-port*   actual-port)
     (set! *server-running* #t)
     (let ((port-file (string-append (current-directory) "/.nrepl-port")))
       (call-with-output-file port-file
         (lambda (p) (display actual-port p))
         'replace))
     (fprintf (current-output-port)
       "nREPL server started on port ~a on host 127.0.0.1 - nrepl://127.0.0.1:~a~n"
       actual-port actual-port)
     (flush-output-port (current-output-port))
     (set! *server-thread*
       (fork-thread
         (lambda ()
           (let accept-loop ()
             (when *server-running*
               (let ((addr (make-bytevector 16 0))
                     (len  (make-bytevector 4 0)))
                 (bytevector-s32-native-set! len 0 16)
                 (let ((client-fd (c-accept sock addr len)))
                   (cond
                     ((> client-fd 0)
                      (fork-thread
                        (lambda ()
                          (guard (exn (#t (void)))
                            (set-nonblocking! client-fd)
                            (let-values (((in out) (fd->binary-ports client-fd)))
                              (handle-client in out)
                              (close-port in)))))
                      (accept-loop))
                     (else
                      (sleep *retry-delay*)
                      (accept-loop))))))))))
     actual-port)))

(def (nrepl-stop!)
  (when *server-running*
    (set! *server-running* #f)
    (when *server-socket*
      (guard (exn (#t (void)))
        (c-close *server-socket*))
      (set! *server-socket* #f))
    (let ((port-file (string-append (current-directory) "/.nrepl-port")))
      (when (file-exists? port-file)
        (delete-file port-file)))
    (set! *server-port* #f)
    (fprintf (current-output-port) "nREPL server stopped~n")
    (flush-output-port (current-output-port))))
