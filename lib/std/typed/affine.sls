#!chezscheme
;;; (std typed affine) — Affine types: use-at-most-once
;;;
;;; Unlike linear types (exactly once), affine types allow dropping
;;; but not duplicating. Guardians clean up dropped values.
;;;
;;; API:
;;;   (make-affine val)              — wrap value as affine
;;;   (make-affine/cleanup val proc) — wrap with custom cleanup
;;;   (affine? v)                    — test for affine value
;;;   (affine-use v proc)            — consume v, call (proc payload)
;;;   (affine-peek v)                — read without consuming
;;;   (affine-consumed? v)           — check if already consumed
;;;   (with-affine ((name expr) ...) body ...) — bind affine values

(library (std typed affine)
  (export make-affine make-affine/cleanup
          affine? affine-use affine-peek affine-consumed?
          with-affine affine-drop!)

  (import (chezscheme))

  ;; Guardian for cleanup of dropped affine values
  (define affine-guardian (make-guardian))

  ;; Run pending cleanups
  (define (process-affine-guardian!)
    (let loop ()
      (let ([entry (affine-guardian)])
        (when entry
          (let ([cleanup (vector-ref entry 3)])
            (when (and cleanup (not (vector-ref entry 2)))
              (cleanup (vector-ref entry 1))))
          (loop)))))

  ;; Affine value: #(affine-box payload consumed? cleanup-or-#f)
  (define (make-affine val)
    (let ([v (vector 'affine-box val #f #f)])
      v))

  (define (make-affine/cleanup val cleanup)
    (let ([v (vector 'affine-box val #f cleanup)])
      (affine-guardian v)
      v))

  (define (affine? v)
    (and (vector? v)
         (= (vector-length v) 4)
         (eq? (vector-ref v 0) 'affine-box)))

  (define (affine-consumed? v)
    (unless (affine? v)
      (error 'affine-consumed? "not an affine value" v))
    (vector-ref v 2))

  (define (affine-use v proc)
    (unless (affine? v)
      (error 'affine-use "not an affine value" v))
    (when (vector-ref v 2)
      (error 'affine-use "affine value already consumed"))
    (vector-set! v 2 #t)
    (proc (vector-ref v 1)))

  (define (affine-peek v)
    (unless (affine? v)
      (error 'affine-peek "not an affine value" v))
    (when (vector-ref v 2)
      (error 'affine-peek "affine value already consumed"))
    (vector-ref v 1))

  (define (affine-drop! v)
    (unless (affine? v)
      (error 'affine-drop! "not an affine value" v))
    (unless (vector-ref v 2)
      (vector-set! v 2 #t)
      (let ([cleanup (vector-ref v 3)])
        (when cleanup
          (cleanup (vector-ref v 1))))))

  (define-syntax with-affine
    (syntax-rules ()
      [(_ () body ...)
       (begin body ...)]
      [(_ ((name expr) rest ...) body ...)
       (let ([name expr])
         (unless (affine? name)
           (error 'with-affine "not an affine value" name))
         (let ([result (with-affine (rest ...) body ...)])
           ;; Auto-drop if not consumed
           (unless (affine-consumed? name)
             (affine-drop! name))
           result))]))

) ;; end library
