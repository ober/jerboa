#!chezscheme
;;; :std/string -- Unified string utilities
;;;
;;; Convenience module that re-exports (std srfi srfi-13) plus the unique
;;; additions from (std misc string): string-split and string-empty?.
;;;
;;; This avoids R6RS import conflicts when you need both modules.
;;; For the full (std misc string) API or full (std srfi srfi-13) API,
;;; import them individually with (only ...) to resolve overlaps.

(library (std string)
  (export
    ;; From (std srfi srfi-13)
    string-index string-index-right
    string-contains
    string-prefix? string-suffix?
    string-trim string-trim-right string-trim-both
    string-pad string-pad-right
    string-join string-concatenate
    string-take string-take-right
    string-drop string-drop-right
    string-count
    string-filter string-delete
    string-reverse
    string-null?
    string-every string-any
    string-fold string-fold-right
    string-for-each-index
    string-map!
    string-tokenize
    string-replace
    ;; From (std misc string) — unique additions
    string-split
    string-empty?)
  (import (std srfi srfi-13)
          (only (std misc string) string-split string-empty?))

  ) ;; end library
