;;; Continuation Marks — Phase 5b (Track 12.3)
;;;
;;; Wraps Chez Scheme's built-in continuation marks system to provide
;;; a clean, key-oriented API:
;;;
;;;   (with-continuation-mark key val expr ...)
;;;     — Chez special form; attaches key→val to current continuation frame
;;;   (current-continuation-marks key)
;;;     — returns the most-recent value for key, or #f
;;;   (continuation-marks->list key)
;;;     — returns all values for key in the current continuation, outermost first
;;;   (call-with-current-continuation-marks proc)
;;;     — calls proc with a snapshot of all marks (raw Chez object)
;;;
;;; Chez Scheme note:
;;;   - `with-continuation-mark` is a built-in special form (not a procedure)
;;;   - `current-continuation-marks` (0-arg) returns a #<continuation-marks> object
;;;   - `continuation-marks->list` (marks key) / `continuation-marks-first` query it
;;;
;;; Implementation note on stacking:  Chez's `with-continuation-mark` is
;;; "tail-mark-collapsing": consecutive marks with the *same* key in tail
;;; position replace rather than stack.  We expose this honestly.

(library (std control marks)
  (export
    with-continuation-mark
    current-continuation-marks
    continuation-marks->list
    call-with-current-continuation-marks)

  ;; Rename the built-in multi-arg versions to private aliases, then
  ;; shadow them with our key-oriented single-arg wrappers.
  (import
    (rename (chezscheme)
            (current-continuation-marks  %chez-current-continuation-marks)
            (continuation-marks->list    %chez-continuation-marks->list)))

  ;; -----------------------------------------------------------------------
  ;; current-continuation-marks key  →  value | #f
  ;; Returns the most recent value for KEY in the current continuation.
  ;; -----------------------------------------------------------------------

  (define (current-continuation-marks key)
    (continuation-marks-first
      (%chez-current-continuation-marks)
      key
      #f))

  ;; -----------------------------------------------------------------------
  ;; continuation-marks->list key  →  list of values, outermost first
  ;; -----------------------------------------------------------------------

  (define (continuation-marks->list key)
    (%chez-continuation-marks->list
      (%chez-current-continuation-marks)
      key))

  ;; -----------------------------------------------------------------------
  ;; call-with-current-continuation-marks proc
  ;; Calls proc with the raw Chez continuation-marks snapshot.
  ;; -----------------------------------------------------------------------

  (define (call-with-current-continuation-marks proc)
    (proc (%chez-current-continuation-marks)))

)
