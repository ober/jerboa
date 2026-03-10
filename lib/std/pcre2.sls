#!chezscheme
;;; :std/pcre2 -- PCRE2 regular expressions (wraps chez-pcre2)
;;; Requires: pcre2_shim.so (libpcre2-8)

(library (std pcre2)
  (export
    ;; Compilation
    pcre2-compile pcre2-regex pcre2-release!
    pcre-regex? pcre-match?
    ;; Matching
    pcre2-match pcre2-search pcre2-matches?
    ;; Match access
    pcre-match-group pcre-match-named
    pcre-match-positions pcre-match->list pcre-match->alist
    ;; Substitution
    pcre2-replace pcre2-replace-all
    ;; Iteration
    pcre2-find-all pcre2-extract pcre2-fold
    pcre2-split pcre2-partition
    ;; Utilities
    pcre2-quote
    ;; Pregexp compatibility
    pcre2-pregexp-match pcre2-pregexp-match-positions
    pcre2-pregexp-replace pcre2-pregexp-replace*
    pcre2-pregexp-quote
    ;; Constants
    PCRE2_CASELESS PCRE2_MULTILINE PCRE2_DOTALL
    PCRE2_EXTENDED PCRE2_UTF PCRE2_UCP
    PCRE2_ANCHORED PCRE2_UNGREEDY PCRE2_LITERAL)

  (import (chez-pcre2 pcre2))

  ) ;; end library
