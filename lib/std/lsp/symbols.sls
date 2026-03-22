#!chezscheme
;;; :std/lsp/symbols -- Symbol database for LSP completion and hover
;;;
;;; Provides a hashtable of known Jerboa/std exports for use by the
;;; LSP server's completion and hover handlers.

(library (std lsp symbols)
  (export symbol-db-init! symbol-db-lookup symbol-db-complete
          symbol-db-add-module!)
  (import (chezscheme))

  ;; symbol-name-string -> (module-name . description)
  (define *symbol-db* (make-hashtable string-hash string=?))

  (define (symbol-db-add! name module desc)
    (hashtable-set! *symbol-db* name (cons module desc)))

  (define (symbol-db-add-module! module-name entries)
    ;; entries: list of (name . description)
    (for-each
     (lambda (e)
       (symbol-db-add! (car e) module-name (cdr e)))
     entries))

  (define (symbol-db-lookup name)
    (let ([v (hashtable-ref *symbol-db* name #f)])
      v))

  (define (symbol-db-complete prefix)
    (let ([len (string-length prefix)]
          [result '()])
      (let-values ([(keys vals) (hashtable-entries *symbol-db*)])
        (vector-for-each
         (lambda (k v)
           (when (and (>= (string-length k) len)
                      (string=? prefix (substring k 0 len)))
             (set! result (cons (list k (car v) (cdr v)) result))))
         keys vals))
      result))

  (define (symbol-db-init!)
    (symbol-db-add-module! "(jerboa prelude)"
      '(("def"            . "Define a binding (Gerbil-style)")
        ("def*"           . "Define with multiple clauses")
        ("defrule"        . "Define a syntax rule")
        ("defstruct"      . "Define a struct type with fields")
        ("defclass"       . "Define a class type")
        ("defmethod"      . "Define a method implementation")
        ("match"          . "Pattern matching expression")
        ("try"            . "Try/catch exception handling")
        ("catch"          . "Catch clause for try")
        ("finally"        . "Finally clause for try")
        ("while"          . "While loop")
        ("until"          . "Until loop (inverse while)")
        ("hash-ref"       . "Get value from hash table (error if missing)")
        ("hash-get"       . "Get value from hash table (returns #f if missing)")
        ("hash-put!"      . "Set value in hash table")
        ("hash-update!"   . "Update hash table value with procedure")
        ("hash-remove!"   . "Remove key from hash table")
        ("hash-key?"      . "Check if key exists in hash table")
        ("hash->list"     . "Convert hash table to alist")
        ("hash-keys"      . "List of hash table keys")
        ("hash-values"    . "List of hash table values")
        ("hash-for-each"  . "Iterate over hash table entries")
        ("hash-map"       . "Map over hash table entries")
        ("hash-fold"      . "Fold over hash table entries")
        ("make-hash-table"    . "Create a new hash table (equal-based)")
        ("make-hash-table-eq" . "Create a new hash table (eq-based)")
        ("hash-merge"     . "Merge two hash tables (functional)")
        ("hash-merge!"    . "Merge two hash tables (mutating)")
        ("displayln"      . "Display value followed by newline")
        ("iota"           . "Generate list of integers [0, n)")
        ("format"         . "Format string (like Common Lisp format)")
        ("printf"         . "Formatted print to stdout")
        ("let-hash"       . "Bind hash table values to variables")
        ("~"              . "Method call syntax: (~ method obj args ...)")))

    (symbol-db-add-module! "(std text json)"
      '(("read-json"            . "Read JSON from port or stdin")
        ("write-json"           . "Write Scheme value as JSON to port")
        ("string->json-object"  . "Parse JSON string to Scheme value")
        ("json-object->string"  . "Convert Scheme value to JSON string")))

    (symbol-db-add-module! "(std sort)"
      '(("sort"         . "Sort a list with comparator (non-destructive)")
        ("sort!"        . "Sort a list with comparator")
        ("stable-sort"  . "Stable sort (preserves equal-element order)")
        ("stable-sort!" . "Stable sort (in-place)")))

    (symbol-db-add-module! "(std iter)"
      '(("for"          . "Iterate: (for ((x (in-list xs))) body ...)")
        ("for/collect"  . "Iterate and collect results into a list")
        ("for/fold"     . "Iterate with accumulator")
        ("for/or"       . "Iterate, return first truthy result")
        ("for/and"      . "Iterate, return #f if any body is #f")
        ("in-list"      . "Iterator over list elements")
        ("in-vector"    . "Iterator over vector elements")
        ("in-range"     . "Iterator over integer range")
        ("in-string"    . "Iterator over string characters")
        ("in-hash-keys"   . "Iterator over hash table keys")
        ("in-hash-values" . "Iterator over hash table values")
        ("in-hash-pairs"  . "Iterator over hash table (key . value) pairs")
        ("in-naturals"    . "Infinite iterator 0, 1, 2, ...")
        ("in-indexed"     . "Iterator with index: (i . element)")))

    (symbol-db-add-module! "(std misc thread)"
      '(("spawn"        . "Spawn a new thread running thunk")
        ("spawn/name"   . "Spawn a named thread")
        ("thread-sleep!" . "Sleep current thread for N seconds")
        ("thread-yield!" . "Yield current thread")
        ("current-thread" . "Return current thread object")
        ("thread-join!"   . "Wait for thread to complete, return result")
        ("make-mutex"     . "Create a new mutex")
        ("with-lock"      . "Execute body while holding mutex")))

    (symbol-db-add-module! "(std test)"
      '(("check"           . "Assert: (check expr => expected)")
        ("check-exn"       . "Assert expression raises exception")
        ("test-suite"      . "Define a named test suite")
        ("run-test-suite!"  . "Run a test suite")))

    (symbol-db-add-module! "(std sugar)"
      '(("with-catch"    . "Catch exceptions: (with-catch handler thunk)")
        ("with-destroy"  . "Execute body, call destroy on exit")
        ("defsyntax"     . "Define a syntax transformer")
        ("chain"         . "Thread value through functions"))))

  ) ;; end library
