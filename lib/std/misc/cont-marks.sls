#!chezscheme
;;; (std misc cont-marks) — Continuation marks (SRFI 157-style API)
;;;
;;; Provides SRFI 157-compatible names on top of Chez Scheme's native
;;; continuation mark support (with-continuation-mark, current-continuation-marks,
;;; call-with-immediate-continuation-mark).
;;;
;;; Chez uses the names continuation-marks->list and continuation-marks-first;
;;; this library re-exports them as continuation-mark-set->list and
;;; continuation-mark-set-first for SRFI 157 / Racket compatibility.
;;;
;;; Note: Chez uses eq? for key comparison. Use symbols or fixnums as keys.
;;; String/pair keys work only if the same object is used for set and lookup.
;;;
;;; Note: call-with-immediate-continuation-mark takes (key default proc),
;;; not (key proc default) as in some Racket documentation.
;;;
;;; (with-continuation-mark 'key 'val
;;;   (continuation-mark-set->list (current-continuation-marks) 'key))
;;; => (val)

(library (std misc cont-marks)
  (export with-continuation-mark
          current-continuation-marks
          continuation-mark-set->list
          continuation-mark-set-first
          continuation-marks?
          call-with-immediate-continuation-mark)
  (import (chezscheme))

  ;; SRFI 157-style aliases for Chez Scheme's native functions.
  ;; Chez names: continuation-marks->list, continuation-marks-first
  ;; SRFI 157 names: continuation-mark-set->list, continuation-mark-set-first

  (define continuation-mark-set->list continuation-marks->list)

  (define continuation-mark-set-first continuation-marks-first)

  ;; with-continuation-mark, current-continuation-marks,
  ;; call-with-immediate-continuation-mark, and continuation-marks?
  ;; are re-exported directly from (chezscheme).

) ;; end library
