;;; jerboa-mode.el --- Jerboa Scheme mode -*- lexical-binding: t; -*-
;;
;; Author: Jerboa Contributors
;; Version: 1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: jerboa scheme lisp languages
;;
;; This file is not part of GNU Emacs.

;;; Commentary:
;;
;; Major mode for editing Jerboa Scheme code.  Jerboa is a Chez Scheme
;; dialect with Gerbil-inspired syntax extensions.
;;
;; Features:
;;  - Font-lock for all Jerboa forms, Chez Scheme, and reader syntax
;;  - Indentation rules for Jerboa-specific forms
;;  - Reader syntax highlighting: [...] lists, {...} dispatch, keywords:, #<<heredoc
;;  - Inferior scheme (REPL) integration via `scheme-send-region'
;;  - Imenu support for def, defstruct, defclass, defmethod, defrule, etc.
;;
;; Keybindings:
;;  C-c C-b  Build current project (make build)
;;  C-c C-e  Send definition to REPL
;;  C-c C-c  Send region to REPL
;;  C-x 9   Restart Scheme REPL

;;; Code:

(require 'scheme)
(require 'cmuscheme)

(defgroup jerboa-mode nil
  "Editing Jerboa Scheme code."
  :prefix "jerboa-"
  :group 'scheme)

(defcustom jerboa-program-name "scheme"
  "Command to run the Jerboa Scheme REPL."
  :type 'string
  :group 'jerboa-mode)

(defcustom jerboa-program-args '("--libdirs" "lib")
  "Arguments passed to the Jerboa Scheme REPL command."
  :type '(repeat string)
  :group 'jerboa-mode)

(defcustom jerboa-pretty-lambda t
  "If non-nil, display lambda as the Greek letter."
  :type 'boolean
  :group 'jerboa-mode)

;; ---------------------------------------------------------------------------
;; REPL integration
;; ---------------------------------------------------------------------------

(defun jerboa-send-string (string)
  "Send STRING to the inferior Scheme process."
  (let ((string (concat string "\n")))
    (comint-check-source string)
    (comint-send-string (scheme-proc) string)
    (message "Jerboa: sent %s ..."
             (substring string 0 (min 60 (or (string-match "\n" string)
                                             (length string)))))))

(defun jerboa-send-region (start end)
  "Send the region between START and END to the Jerboa REPL."
  (interactive "r")
  (jerboa-send-string (buffer-substring start end)))

(defun jerboa-restart-scheme ()
  "Kill and restart the inferior Scheme process."
  (interactive)
  (let ((process (ignore-errors (scheme-get-process))))
    (when process
      (ignore-errors
        (switch-to-buffer "*scheme*")
        (comint-clear-buffer))
      (ignore-errors (kill-process process))
      (sleep-for 1)))
  (switch-to-buffer "*scheme*")
  (run-scheme (mapconcat #'identity
                         (cons jerboa-program-name jerboa-program-args)
                         " "))
  (ignore-errors (comint-clear-buffer))
  (message "Jerboa REPL restarted"))

;; ---------------------------------------------------------------------------
;; Build integration
;; ---------------------------------------------------------------------------

(defun jerboa-find-project-root ()
  "Walk up from `default-directory' looking for a Makefile."
  (locate-dominating-file default-directory "Makefile"))

(defun jerboa-build ()
  "Run `make build' in the project root."
  (interactive)
  (let ((root (jerboa-find-project-root)))
    (if root
        (compile (concat "make -C " (shell-quote-argument root) " build"))
      (error "Cannot locate Makefile"))))

;; ---------------------------------------------------------------------------
;; Indentation
;; ---------------------------------------------------------------------------

(defun jerboa--put-indent (syms val)
  "Set `scheme-indent-function' to VAL for each symbol in SYMS."
  (dolist (s syms) (put s 'scheme-indent-function val)))

(defun jerboa-init-indentation ()
  "Set up indentation for Jerboa forms."
  ;; 0-arg indent (body immediately)
  (jerboa--put-indent
   '(import export
     or and
     case-lambda
     call/cc call/values
     cond-expand
     for-each map foldl foldr
     unwind-protect
     begin-foreign)
   0)

  ;; 1-arg indent (1 special arg, then body)
  (jerboa--put-indent
   '(if when unless
     set!
     apply
     with-syntax
     let-values letrec-values
     module
     parameterize
     rec awhen aif
     alet alet*
     when-let if-let
     error
     catch guard
     match match*
     with with*
     let/cc let/esc
     lambda lambda%
     while until dotimes
     for for* for/collect
     for/or for/and
     with-resource
     try
     test-suite test-case
     using
     with-input-from-string with-output-to-string
     with-input-from-file with-output-to-file
     let-alist)
   1)

  ;; 2-arg indent
  (jerboa--put-indent
   '(syntax-case
     do-while
     for/fold)
   2)

  ;; defun-style indent
  (jerboa--put-indent
   '(def def* defvalues
     defsyntax defrule defrules
     defstruct defclass defrecord
     defgeneric defmethod
     define-enum
     extern)
   'defun))

;; ---------------------------------------------------------------------------
;; Font-lock: keyword lists
;; ---------------------------------------------------------------------------

(defconst jerboa-keywords
  '(;; core
    "import" "export" "module" "require" "provide"
    "if" "cond" "case" "when" "unless" "and" "or" "not"
    "begin" "begin0" "do"
    "set!" "apply" "eval" "values"
    ;; binding
    "let" "let*" "letrec" "letrec*"
    "let-values" "letrec-values"
    "let-syntax" "letrec-syntax"
    "parameterize"
    "rec" "fluid-let"
    ;; lambda
    "lambda" "case-lambda"
    ;; quoting
    "quote" "quasiquote" "unquote" "unquote-splicing"
    "syntax" "quasisyntax" "unsyntax" "unsyntax-splicing"
    ;; continuations
    "call/cc" "call/values" "call-with-current-continuation"
    "let/cc" "let/esc" "dynamic-wind"
    ;; control flow
    "for-each" "map" "foldl" "foldr"
    "andmap" "ormap" "filter-map"
    ;; error / exception
    "error" "raise" "guard"
    "with-exception-handler" "condition"
    ;; sugar
    "try" "catch" "finally"
    "unwind-protect" "with-resource"
    "while" "until" "dotimes"
    "assert!"
    ;; anaphoric
    "awhen" "aif" "when-let" "if-let"
    "alet" "alet*"
    ;; pattern matching
    "match" "match*" "where"
    ;; iterators
    "for" "for*" "for/collect" "for/fold"
    "for/or" "for/and"
    "in-list" "in-vector" "in-string" "in-range"
    "in-hash-keys" "in-hash-values" "in-hash-pairs"
    "in-naturals" "in-indexed"
    "in-port" "in-lines" "in-chars" "in-bytes" "in-producer"
    ;; threading
    "->" "->>" "as->" "some->" "cond->" "->?"
    ;; ergo typing
    ":" "using"
    ;; result type
    "ok" "err" "ok?" "err?"
    "unwrap" "unwrap-or"
    "map-ok" "map-err" "and-then"
    "try-result" "try-result*" "sequence-results"
    ;; testing
    "test-suite" "test-case"
    "check" "check-eq?" "check-equal?" "check-predicate" "check-exception"
    ;; misc
    "cut" "with" "with*"
    "cond-expand" "begin-foreign"
    "include"
    ;; Chez
    "syntax-case" "with-syntax"
    "record-type-descriptor" "foreign-procedure"
    "critical-section" "with-mutex" "make-mutex")
  "Jerboa and Chez Scheme keywords.")

(defconst jerboa-definition-keywords
  '("def" "def*" "defvalues"
    "defsyntax" "defrule" "defrules"
    "defstruct" "defclass" "defrecord"
    "defgeneric" "defmethod"
    "define-enum"
    "extern"
    "define" "define-syntax" "define-record-type")
  "Jerboa definition forms.")

(defconst jerboa-type-definition-keywords
  '("defstruct" "defclass" "defrecord" "define-enum")
  "Forms that define types.")

(defconst jerboa-builtin-functions
  '(;; hash tables
    "make-hash-table" "hash-table?"
    "hash-put!" "hash-ref" "hash-get" "hash-key?" "hash-remove!"
    "hash->list" "hash-keys" "hash-values" "hash-for-each"
    "list->hash-table"
    ;; strings
    "string-split" "string-join" "string-trim"
    "string-prefix?" "string-suffix?" "string-contains"
    "string-empty?" "str"
    "string-upcase" "string-downcase"
    "string->number" "number->string"
    "string->symbol" "symbol->string"
    "string-append" "substring" "string-length" "string-ref"
    "string->json-object" "json-object->string"
    ;; lists
    "cons" "car" "cdr" "list" "append" "reverse" "length"
    "null?" "pair?" "list?"
    "assoc" "assv" "assq"
    "member" "memv" "memq"
    "flatten" "unique" "distinct"
    "take" "drop" "take-last" "drop-last"
    "every" "any" "filter" "filter-map"
    "group-by" "zip" "frequencies"
    "partition" "interleave" "mapcat"
    "keep" "split-at" "append-map" "snoc"
    "sort" "sort!"
    ;; functional
    "compose" "comp" "partial" "complement" "negate"
    "identity" "constantly" "curry" "flip"
    "conjoin" "disjoin" "juxt"
    ;; predicates
    "list-of?" "maybe"
    "number?" "string?" "symbol?" "boolean?" "char?"
    "pair?" "vector?" "procedure?" "port?"
    "eq?" "eqv?" "equal?"
    "zero?" "positive?" "negative?" "even?" "odd?"
    ;; I/O
    "display" "displayln" "newline" "write" "print"
    "read" "get-line"
    "pp" "pp-to-string" "pprint"
    "format" "printf" "fprintf"
    "read-file-string" "read-file-lines" "write-file-string"
    "open-input-file" "open-output-file"
    "close-input-port" "close-output-port"
    "call-with-input-file" "call-with-output-file"
    "with-input-from-file" "with-output-to-file"
    "with-input-from-string" "with-output-to-string"
    ;; paths
    "path-join" "path-directory" "path-extension" "path-absolute?"
    "path-expand"
    ;; math
    "+" "-" "*" "/" "modulo" "remainder" "quotient"
    "abs" "max" "min" "gcd" "lcm"
    "floor" "ceiling" "truncate" "round"
    "expt" "sqrt" "log" "exp"
    "random"
    ;; datetime
    "datetime-now" "datetime-utc-now" "make-datetime"
    "parse-datetime" "datetime->iso8601" "datetime->epoch"
    "datetime-add" "datetime-diff"
    ;; vector
    "vector" "make-vector" "vector-ref" "vector-set!"
    "vector-length" "vector->list" "list->vector"
    ;; char
    "char->integer" "integer->char"
    "char-alphabetic?" "char-numeric?" "char-whitespace?"
    ;; misc
    "void" "gensym" "iota"
    "1+" "1-"
    ;; struct access dispatch
    "~")
  "Jerboa builtin functions and procedures.")

(defconst jerboa-constants
  '("#t" "#f" "#!void" "#!eof")
  "Jerboa constants.")

;; ---------------------------------------------------------------------------
;; Font-lock: rules
;; ---------------------------------------------------------------------------

(defun jerboa--font-lock-keywords ()
  "Compute font-lock keywords for `jerboa-mode'."
  (list
   ;; ------- definition forms with name capture -------

   ;; (def (name args...) body) and (def name value)
   `(,(concat "(\\(def\\)\\s-+(?\\(\\(?:\\sw\\|\\s_\\)+\\)")
     (1 font-lock-keyword-face)
     (2 font-lock-function-name-face))

   ;; (def* name clauses...)
   `(,(concat "(\\(def[*]\\)\\s-+\\(\\(?:\\sw\\|\\s_\\)+\\)")
     (1 font-lock-keyword-face)
     (2 font-lock-function-name-face))

   ;; (defmethod (name (self type)) body)
   `(,(concat "(\\(defmethod\\)\\s-+(\\(\\(?:\\sw\\|\\s_\\)+\\)")
     (1 font-lock-keyword-face)
     (2 font-lock-function-name-face))

   ;; (defgeneric name)
   `(,(concat "(\\(defgeneric\\)\\s-+\\(\\(?:\\sw\\|\\s_\\)+\\)")
     (1 font-lock-keyword-face)
     (2 font-lock-function-name-face))

   ;; (defstruct name ...) / (defclass name ...) / (defrecord name ...)
   ;; Also handles inheritance: (defstruct (child parent) ...)
   `(,(concat "(\\(defstruct\\|defclass\\|defrecord\\)\\s-+(?\\(\\(?:\\sw\\|\\s_\\)+\\)")
     (1 font-lock-keyword-face)
     (2 font-lock-type-face))

   ;; (define-enum name ...)
   `(,(concat "(\\(define-enum\\)\\s-+\\(\\(?:\\sw\\|\\s_\\)+\\)")
     (1 font-lock-keyword-face)
     (2 font-lock-type-face))

   ;; (defrule (name pattern) template)
   `(,(concat "(\\(defrule\\)\\s-+(\\(\\(?:\\sw\\|\\s_\\)+\\)")
     (1 font-lock-keyword-face)
     (2 font-lock-variable-name-face))

   ;; (defrules name ...)  (defsyntax name ...)
   `(,(concat "(\\(defrules\\|defsyntax\\)\\s-+\\(\\(?:\\sw\\|\\s_\\)+\\)")
     (1 font-lock-keyword-face)
     (2 font-lock-variable-name-face))

   ;; (define (name ...) body) — standard Scheme
   `(,(concat "(\\(define\\)\\s-+(?\\(\\(?:\\sw\\|\\s_\\)+\\)")
     (1 font-lock-keyword-face)
     (2 font-lock-function-name-face))

   ;; (define-syntax name ...)
   `(,(concat "(\\(define-syntax\\)\\s-+\\(\\(?:\\sw\\|\\s_\\)+\\)")
     (1 font-lock-keyword-face)
     (2 font-lock-variable-name-face))

   ;; (module name ...)
   `(,(concat "(\\(module\\)\\s-+\\(\\(?:\\sw\\|\\s_\\)+\\)")
     (1 font-lock-keyword-face)
     (2 font-lock-variable-name-face))

   ;; ------- using with ergo typing -------
   ;; (using (var expr : type?) ...)
   `(,(concat "(\\(using\\)\\s-+((?\\(\\(?:\\sw\\|\\s_\\)+\\)"
              "\\s-+[^:]*\\(:\\)\\s-+\\(\\(?:\\sw\\|\\s_\\)+\\)")
     (1 font-lock-keyword-face)
     (2 font-lock-variable-name-face)
     (3 font-lock-keyword-face)
     (4 font-lock-type-face))

   ;; ------- all other keywords -------
   `(,(concat
      "("
      (regexp-opt jerboa-keywords t)
      "\\_>")
     (1 font-lock-keyword-face))

   ;; ------- builtin functions -------
   `(,(concat
      "("
      (regexp-opt jerboa-builtin-functions t)
      "\\_>")
     (1 font-lock-builtin-face))

   ;; ------- dot-access: obj.field -------
   '("\\_<\\(\\(?:\\sw\\|\\s_\\)+\\)\\.\\(\\(?:\\sw\\|\\s_\\)+\\)\\_>"
     (1 font-lock-variable-name-face)
     (2 font-lock-constant-face))

   ;; ------- Jerboa keywords: name: (identifier ending in colon) -------
   '("\\_<\\(\\(?:\\sw\\|\\s_\\)+:\\)\\_>"
     (1 font-lock-builtin-face))

   ;; ------- #:keyword -------
   '("\\(#:\\(?:\\sw\\|\\s_\\)+\\)"
     (1 font-lock-builtin-face))

   ;; ------- constants: #t #f #!void #!eof -------
   '("\\<\\(#[tf]\\|#!\\w+\\)"
     (1 font-lock-constant-face))

   ;; ------- characters: #\a #\space #\newline -------
   '("\\(#\\\\\\(?:\\sw+\\|.\\)\\)"
     (1 font-lock-string-face))

   ;; ------- reader syntax brackets: [...] {...} -------
   '("\\([][{}]\\)"
     (1 font-lock-bracket-face nil t))

   ;; ------- quasiquote / unquote markers -------
   '("\\(#?[`',]\\)"
     (1 font-lock-keyword-face))
   '("\\(#?,@\\)"
     (1 font-lock-keyword-face))

   ;; ------- ellipsis -------
   '("\\_<\\(\\.\\.\\.\\)\\_>"
     (1 font-lock-builtin-face))

   ;; ------- cut placeholders: <> <...> -------
   '("\\(<>\\|<\\.\\.\\.>\\)"
     (1 font-lock-builtin-face))

   ;; ------- => in match/cond -------
   '("\\_<\\(=>\\)\\_>"
     (1 font-lock-builtin-face))

   ;; ------- wildcard _ -------
   '("\\_<\\(_\\)\\_>"
     (1 font-lock-builtin-face))

   ;; ------- predicates: name? -------
   '("\\_<\\(\\(?:\\sw\\|\\s_\\)+\\?\\)\\_>"
     (1 font-lock-type-face nil t))

   ;; ------- mutators: name! -------
   '("\\_<\\(\\(?:\\sw\\|\\s_\\)+!\\)\\_>"
     (1 font-lock-warning-face nil t))

   ;; ------- TODO/FIXME/XXX/HACK -------
   '("\\<\\(TODO\\|FIXME\\|XXX\\|HACK\\|NOTE\\)\\>"
     (1 font-lock-warning-face t))))

;; ---------------------------------------------------------------------------
;; Heredoc support (#<<DELIM ... DELIM)
;; ---------------------------------------------------------------------------

(defconst jerboa-heredoc-start-rx
  "#<<\\([A-Za-z_][A-Za-z0-9_]*\\)"
  "Regexp matching the start of a Jerboa heredoc.")

(defun jerboa-syntax-propertize (start end)
  "Apply syntax properties for heredoc strings between START and END."
  (goto-char start)
  (jerboa-syntax-propertize-heredoc end))

(defun jerboa-syntax-propertize-heredoc (end)
  "Find and propertize heredoc strings up to END."
  (while (re-search-forward jerboa-heredoc-start-rx end t)
    (let ((delim (match-string 1))
          (beg (match-beginning 0)))
      (put-text-property beg (1+ beg)
                         'syntax-table (string-to-syntax "|"))
      (when (re-search-forward (concat "^" (regexp-quote delim) "$") end t)
        (put-text-property (1- (match-end 0)) (match-end 0)
                           'syntax-table (string-to-syntax "|"))))))

;; ---------------------------------------------------------------------------
;; Imenu
;; ---------------------------------------------------------------------------

(defvar jerboa-imenu-generic-expression
  `(("Functions"
     ,(concat "^\\s-*(\\(def\\*?\\)\\s-+(?\\(\\(?:\\sw\\|\\s_\\)+\\)") 2)
    ("Methods"
     ,(concat "^\\s-*(defmethod\\s-+(\\(\\(?:\\sw\\|\\s_\\)+\\)") 1)
    ("Types"
     ,(concat "^\\s-*(\\(?:defstruct\\|defclass\\|defrecord\\|define-enum\\)"
              "\\s-+(?\\(\\(?:\\sw\\|\\s_\\)+\\)") 1)
    ("Macros"
     ,(concat "^\\s-*(\\(?:defrule\\|defsyntax\\|defrules\\)"
              "\\s-+(?\\(\\(?:\\sw\\|\\s_\\)+\\)") 1))
  "Imenu patterns for `jerboa-mode'.")

;; ---------------------------------------------------------------------------
;; Pretty lambda
;; ---------------------------------------------------------------------------

(defun jerboa-pretty-lambda ()
  "Display `lambda' as the Greek letter."
  (font-lock-add-keywords
   nil
   `(("\\<\\(lambda\\)\\>"
      (0 (progn
           (compose-region (match-beginning 1) (match-end 1)
                           ?\u03BB)
           nil))))
   t))

;; ---------------------------------------------------------------------------
;; Keymap
;; ---------------------------------------------------------------------------

(defvar jerboa-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map scheme-mode-map)
    (define-key map (kbd "C-c C-b") #'jerboa-build)
    (define-key map (kbd "C-c C-e") #'scheme-send-definition)
    (define-key map (kbd "C-c C-c") #'jerboa-send-region)
    (define-key map (kbd "C-x 9")   #'jerboa-restart-scheme)
    map)
  "Keymap for `jerboa-mode'.")

;; ---------------------------------------------------------------------------
;; Mode definition
;; ---------------------------------------------------------------------------

;;;###autoload
(define-derived-mode jerboa-mode scheme-mode "Jerboa"
  "Major mode for editing Jerboa Scheme code.

Jerboa is a Chez Scheme dialect with Gerbil-inspired extensions.
This mode extends `scheme-mode' with Jerboa-aware font-lock,
indentation, heredoc syntax, and REPL integration.

\\{jerboa-mode-map}"
  (setq-local scheme-program-name
              (mapconcat #'identity
                         (cons jerboa-program-name jerboa-program-args)
                         " "))
  (setq-local comment-start ";;")
  (setq-local comment-end "")

  ;; Font-lock
  (setq-local font-lock-defaults
              `((,(jerboa--font-lock-keywords))
                nil nil
                ;; Scheme-compatible syntax alist
                ((?- . "w") (?+ . "w") (?/ . "w") (?* . "w")
                 (?< . "w") (?> . "w") (?= . "w") (?! . "w")
                 (?? . "w") (?~ . "w") (?& . "w") (?^ . "w")
                 (?@ . "w"))
                beginning-of-defun))
  (font-lock-ensure)

  ;; Heredoc syntax support
  (setq-local syntax-propertize-function #'jerboa-syntax-propertize)

  ;; Indentation
  (jerboa-init-indentation)

  ;; Imenu
  (setq-local imenu-generic-expression jerboa-imenu-generic-expression)

  ;; Pretty lambda
  (when (and jerboa-pretty-lambda window-system)
    (jerboa-pretty-lambda)))

;; ---------------------------------------------------------------------------
;; Auto-mode
;; ---------------------------------------------------------------------------

;;;###autoload
(progn
  (add-to-list 'auto-mode-alist '("\\.ss\\'" . jerboa-mode))
  (add-to-list 'auto-mode-alist '("\\.sls\\'" . jerboa-mode))
  (modify-coding-system-alist 'file "\\.ss\\'" 'utf-8)
  (modify-coding-system-alist 'file "\\.sls\\'" 'utf-8))

(provide 'jerboa-mode)

;;; jerboa-mode.el ends here
