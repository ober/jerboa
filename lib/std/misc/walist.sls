#!chezscheme
;;; :std/misc/walist -- Weak association list (GC-friendly cache)
;;;
;;; Uses Chez Scheme's weak eq-hashtable so that keys can be
;;; reclaimed by the garbage collector.

(library (std misc walist)
  (export make-walist
          walist-ref
          walist-set!
          walist-delete!
          walist-keys
          walist->alist
          walist-length)
  (import (chezscheme))

  ;; A walist is just a wrapper around a weak eq-hashtable.
  (define-record-type walist
    (fields (immutable ht))
    (protocol
      (lambda (new)
        (lambda ()
          (new (make-weak-eq-hashtable))))))

  (define (walist-ref w key)
    (let ([ht (walist-ht w)])
      (hashtable-ref ht key #f)))

  (define (walist-set! w key val)
    (let ([ht (walist-ht w)])
      (hashtable-set! ht key val)))

  (define (walist-delete! w key)
    (let ([ht (walist-ht w)])
      (hashtable-delete! ht key)))

  (define (walist-keys w)
    (let ([ht (walist-ht w)])
      (vector->list (hashtable-keys ht))))

  (define (walist->alist w)
    (let ([ht (walist-ht w)])
      (let-values ([(keys vals) (hashtable-entries ht)])
        (let lp ([i 0] [acc '()])
          (if (>= i (vector-length keys))
            (reverse acc)
            (lp (+ i 1)
                (cons (cons (vector-ref keys i)
                            (vector-ref vals i))
                      acc)))))))

  (define (walist-length w)
    (hashtable-size (walist-ht w)))

  ) ;; end library
