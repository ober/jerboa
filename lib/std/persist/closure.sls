;;; Persistent Closures / Data Serialization — Phase 5b (Track 13.1)
;;;
;;; Uses Chez Scheme's fasl-write/fasl-read for binary serialization of
;;; Scheme values.  Note that *live closures* (procedures) cannot be
;;; serialized by fasl; only pure data (lists, vectors, strings, numbers,
;;; symbols, bytevectors, booleans, chars, …) round-trips correctly.
;;;
;;; API:
;;;   fasl-serialize    value → bytevector
;;;   fasl-deserialize  bytevector → value
;;;   closure-save      value path → void   (writes to file)
;;;   closure-load      path → value        (reads from file)
;;;   checkpoint-computation  state-alist path → void
;;;   resume-computation      path → state-alist

(library (std persist closure)
  (export
    closure-save
    closure-load
    checkpoint-computation
    resume-computation
    fasl-serialize
    fasl-deserialize)

  (import (chezscheme))

  ;; -----------------------------------------------------------------------
  ;; fasl-serialize : value → bytevector
  ;; -----------------------------------------------------------------------

  (define (fasl-serialize val)
    (call-with-values
      (lambda () (open-bytevector-output-port))
      (lambda (out get)
        (fasl-write val out)
        (get))))

  ;; -----------------------------------------------------------------------
  ;; fasl-deserialize : bytevector → value
  ;; -----------------------------------------------------------------------

  (define (fasl-deserialize bv)
    (fasl-read (open-bytevector-input-port bv)))

  ;; -----------------------------------------------------------------------
  ;; closure-save : value path → void
  ;;
  ;; Serializes VALUE to the file at PATH using fasl-write.
  ;; Works for pure data values; raises an error for live closures.
  ;; -----------------------------------------------------------------------

  (define (closure-save val path)
    ;; fasl-write requires a binary output port
    (let ([p (open-file-output-port path (file-options no-fail))])
      (fasl-write val p)
      (close-port p)))

  ;; -----------------------------------------------------------------------
  ;; closure-load : path → value
  ;; -----------------------------------------------------------------------

  (define (closure-load path)
    (let ([p (open-file-input-port path)])
      (let ([val (fasl-read p)])
        (close-port p)
        val)))

  ;; -----------------------------------------------------------------------
  ;; checkpoint-computation : alist path → void
  ;;
  ;; Saves a state alist (association list of key→value pairs) to PATH.
  ;; Values must be fasl-serializable (pure data).
  ;; -----------------------------------------------------------------------

  (define (checkpoint-computation state-alist path)
    (closure-save state-alist path))

  ;; -----------------------------------------------------------------------
  ;; resume-computation : path → alist
  ;;
  ;; Restores a state alist previously saved by checkpoint-computation.
  ;; Returns '() if the file does not exist.
  ;; -----------------------------------------------------------------------

  (define (resume-computation path)
    (if (file-exists? path)
        (closure-load path)
        '()))

)
