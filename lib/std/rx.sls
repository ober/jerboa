#!chezscheme
;;; (std rx) — Composable regex pattern macro
;;;
;;; Builds on (std regex) with a convenient macro syntax for defining
;;; named, composable regex patterns. Patterns defined with define-rx
;;; are re-objects that can be referenced by name inside other rx forms.
;;;
;;; How composition works:
;;;   define-rx compiles the SRE and registers the re-object in a global
;;;   registry (rx-registry). When a later rx or define-rx form is compiled,
;;;   any symbol in the SRE that names a registered re-object is replaced
;;;   with (embed "raw-pattern") — a special SRE form understood by srfi-115
;;;   that splices the pattern string directly (wrapped in a non-capturing group).
;;;
;;; Usage:
;;;   (import (std rx))
;;;
;;;   (re-match? (rx (+ digit)) "42")           ;; => #t
;;;   (re-match? (rx alpha (* alnum)) "hello1") ;; => #t
;;;
;;;   (define-rx octet  (** 1 3 digit))
;;;   (define-rx ip-addr (: octet "." octet "." octet "." octet))
;;;
;;;   (re-match? ip-addr "192.168.1.1")          ;; => #t
;;;   (re-find-all ip-addr "10.0.0.1 and 192.168.1.1")
;;;   ;; => ("10.0.0.1" "192.168.1.1")
;;;
;;;   ;; Named captures
;;;   (define-rx dated
;;;     (: (=> year (= 4 digit)) "-" (=> month (= 2 digit)) "-" (=> day (= 2 digit))))
;;;   (re-match-named (re-search dated "2026-04-09") 'year) ;; => "2026"

(library (std rx)
  (export rx define-rx)

  (import (chezscheme)
          (std regex)
          (std srfi srfi-115))

  ;; ========== Registry ==========
  ;; Maps symbol → re-object for named patterns defined with define-rx.
  ;; Used at runtime to splice patterns into larger SRE forms.

  (define rx-registry (make-eq-hashtable))

  ;; ========== SRE splicing ==========
  ;; Walk a quoted SRE datum; replace any symbol that names a registered
  ;; re-object with (embed "its-compiled-pattern-string").
  ;; (embed "str") is handled by srfi-115's sre->pregexp: it embeds the
  ;; string as a raw pregexp fragment inside (?:...).

  ;; SRE keywords that must never be replaced by registry entries.
  ;; These are operators or named character classes in the SRE language.
  (define sre-reserved-symbols
    '(: seq or * + ? = >= ** => submatch submatch-named
      not-submatch look-ahead neg-look-ahead look-behind neg-look-behind
      w/nocase / char-range ~ complement - difference & intersection embed
      ;; Named character classes
      any alpha alphabetic digit numeric num alnum alphanumeric
      space whitespace white upper upper-case lower lower-case
      word ascii hex-digit xdigit epsilon eof))

  (define (splice-re-refs sre)
    (cond
      ;; Symbol with a registered re-object → (embed raw-pattern)
      ;; But never replace SRE reserved keywords.
      [(and (symbol? sre)
            (not (memq sre sre-reserved-symbols))
            (hashtable-ref rx-registry sre #f))
       => (lambda (r)
            (list 'embed (re-object-pat-string r)))]
      ;; Pair: recurse into both sides
      [(pair? sre)
       (cons (splice-re-refs (car sre))
             (splice-re-refs (cdr sre)))]
      ;; Atom (string, char, number, boolean, other symbol) → unchanged
      [else sre]))

  ;; Compile a quoted SRE form to a re-object, splicing any registered patterns.
  (define (rx-compile quoted-sre)
    (re (splice-re-refs quoted-sre)))

  ;; ========== Macros ==========

  ;; rx: compile an SRE form (or sequence of forms) to a re-object.
  ;; Single form wraps directly; multiple forms are wrapped in (: ...).
  (define-syntax rx
    (syntax-rules ()
      [(_ form)
       (rx-compile 'form)]
      [(_ form ...)
       (rx-compile '(: form ...))]))

  ;; define-rx: define a named pattern.
  ;; The name is bound to a re-object AND registered in rx-registry so it
  ;; can be spliced into subsequent rx/define-rx forms by name.
  ;;
  ;; Registration is done INSIDE the define initializer (not as a separate
  ;; expression) to stay valid in R6RS library bodies where definitions cannot
  ;; follow expressions.
  (define-syntax define-rx
    (syntax-rules ()
      [(_ name form)
       (define name
         (let ([r (rx-compile 'form)])
           (hashtable-set! rx-registry 'name r)
           r))]
      [(_ name form ...)
       (define name
         (let ([r (rx-compile '(: form ...))])
           (hashtable-set! rx-registry 'name r)
           r))]))

) ;; end library
