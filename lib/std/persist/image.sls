;;; Image-Based Development — Phase 5b (Track 13.3)
;;;
;;; A simplified "image" system that serializes the key-value state of the
;;; current session to a file and can restore it later.  The image is stored
;;; as an in-memory equal?-hashtable; save-image/load-image persist it via
;;; Chez's fasl-write/fasl-read.
;;;
;;; API:
;;;   image-set!   key val → void   (register a value)
;;;   image-ref    key [default] → value  (look up a value)
;;;   image-keys   → list of all keys
;;;   image-clear! → void            (clear the image state)
;;;   save-image   path → void       (serialize to file)
;;;   load-image   path → void       (restore from file; merges into current)

(library (std persist image)
  (export
    save-image
    load-image
    image-set!
    image-ref
    image-keys
    image-clear!)

  (import (chezscheme))

  ;; -----------------------------------------------------------------------
  ;; Internal state — a single process-global hashtable
  ;; -----------------------------------------------------------------------

  (define *image* (make-hashtable equal-hash equal?))

  ;; -----------------------------------------------------------------------
  ;; image-set! key value → void
  ;; -----------------------------------------------------------------------

  (define (image-set! key val)
    (hashtable-set! *image* key val))

  ;; -----------------------------------------------------------------------
  ;; image-ref key [default] → value
  ;; -----------------------------------------------------------------------

  (define image-ref
    (case-lambda
      [(key)
       (if (hashtable-contains? *image* key)
           (hashtable-ref *image* key #f)
           (error 'image-ref "key not found in image" key))]
      [(key default)
       (hashtable-ref *image* key default)]))

  ;; -----------------------------------------------------------------------
  ;; image-keys → list
  ;; -----------------------------------------------------------------------

  (define (image-keys)
    (call-with-values
      (lambda () (hashtable-entries *image*))
      (lambda (keys _vals) (vector->list keys))))

  ;; -----------------------------------------------------------------------
  ;; image-clear! → void
  ;; -----------------------------------------------------------------------

  (define (image-clear!)
    (hashtable-clear! *image*))

  ;; -----------------------------------------------------------------------
  ;; Serialization helpers — convert hashtable ↔ alist for fasl portability
  ;; -----------------------------------------------------------------------

  (define (%image->alist ht)
    (call-with-values
      (lambda () (hashtable-entries ht))
      (lambda (keys vals)
        (let loop ([i 0] [acc '()])
          (if (= i (vector-length keys))
              acc
              (loop (+ i 1)
                    (cons (cons (vector-ref keys i) (vector-ref vals i))
                          acc)))))))

  (define (%alist->hashtable! ht alist)
    (for-each (lambda (pair)
                (hashtable-set! ht (car pair) (cdr pair)))
              alist))

  ;; -----------------------------------------------------------------------
  ;; save-image path → void
  ;;
  ;; Serializes the current image hashtable to PATH as a fasl alist.
  ;; -----------------------------------------------------------------------

  (define (save-image path)
    (let ([alist (%image->alist *image*)])
      (let ([p (open-file-output-port path (file-options no-fail))])
        (fasl-write alist p)
        (close-port p))))

  ;; -----------------------------------------------------------------------
  ;; load-image path → void
  ;;
  ;; Loads an image from PATH, merging its entries into the current image.
  ;; Existing keys are overwritten; keys not in the file are untouched.
  ;; -----------------------------------------------------------------------

  (define (load-image path)
    (let ([p (open-file-input-port path)])
      (let ([alist (fasl-read p)])
        (close-port p)
        (%alist->hashtable! *image* alist))))

)
