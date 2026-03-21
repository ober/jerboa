#!chezscheme
;;; (std notebook) — Interactive computational notebook
;;;
;;; Reactive cells with dependency tracking. Cells re-execute when
;;; dependencies change. DAG-based evaluation order.
;;;
;;; API:
;;;   (make-notebook name)           — create a notebook
;;;   (nb-cell! nb name deps thunk)  — add a cell
;;;   (nb-eval! nb)                  — evaluate all cells in dependency order
;;;   (nb-eval-cell! nb name)        — evaluate a specific cell
;;;   (nb-ref nb name)               — get cell result
;;;   (nb-cell-names nb)             — list cell names
;;;   (nb-dirty? nb name)            — check if cell needs re-eval
;;;   (nb-reset! nb)                 — reset all cells

(library (std notebook)
  (export make-notebook nb-cell! nb-eval! nb-eval-cell!
          nb-ref nb-cell-names nb-dirty? nb-reset! nb-remove!
          notebook-name notebook?)

  (import (chezscheme))

  ;; ========== Cell ==========

  (define-record-type nb-cell
    (fields
      (immutable name)
      (immutable deps)         ;; list of cell names this depends on
      (immutable thunk)        ;; (lambda () result)
      (mutable result)
      (mutable evaluated?)
      (mutable error))
    (protocol
      (lambda (new)
        (lambda (name deps thunk)
          (new name deps thunk #f #f #f)))))

  ;; ========== Notebook ==========

  (define-record-type notebook
    (fields
      (immutable name)
      (immutable cells-ht))    ;; eq-hashtable: name -> nb-cell
    (protocol
      (lambda (new)
        (lambda (name)
          (new name (make-eq-hashtable))))))

  (define (nb-cell! nb name deps thunk)
    (hashtable-set! (notebook-cells-ht nb) name
      (make-nb-cell name deps thunk)))

  (define (nb-cell-names nb)
    (vector->list (hashtable-keys (notebook-cells-ht nb))))

  (define (nb-ref nb name)
    (let ([c (hashtable-ref (notebook-cells-ht nb) name #f)])
      (and c (nb-cell-result c))))

  (define (nb-dirty? nb name)
    (let ([c (hashtable-ref (notebook-cells-ht nb) name #f)])
      (and c (not (nb-cell-evaluated? c)))))

  (define (nb-remove! nb name)
    (hashtable-delete! (notebook-cells-ht nb) name))

  (define (nb-reset! nb)
    (let-values ([(keys vals) (hashtable-entries (notebook-cells-ht nb))])
      (vector-for-each
        (lambda (k v)
          (nb-cell-evaluated?-set! v #f)
          (nb-cell-result-set! v #f)
          (nb-cell-error-set! v #f))
        keys vals)))

  ;; ========== Topological sort ==========

  (define (topo-sort nb)
    (let ([cells (notebook-cells-ht nb)]
          [visited (make-eq-hashtable)]
          [order '()])
      (define (visit name)
        (unless (hashtable-ref visited name #f)
          (hashtable-set! visited name #t)
          (let ([c (hashtable-ref cells name #f)])
            (when c
              (for-each visit (nb-cell-deps c))))
          (set! order (cons name order))))
      (vector-for-each
        (lambda (k) (visit k))
        (hashtable-keys cells))
      (reverse order)))

  ;; ========== Evaluation ==========

  (define (nb-eval-cell! nb name)
    (let ([c (hashtable-ref (notebook-cells-ht nb) name #f)])
      (when c
        (for-each
          (lambda (dep)
            (let ([dc (hashtable-ref (notebook-cells-ht nb) dep #f)])
              (when (and dc (not (nb-cell-evaluated? dc)))
                (nb-eval-cell! nb dep))))
          (nb-cell-deps c))
        (guard (exn
                [#t (nb-cell-error-set! c exn)
                    (nb-cell-evaluated?-set! c #t)])
          (let ([result ((nb-cell-thunk c))])
            (nb-cell-result-set! c result)
            (nb-cell-evaluated?-set! c #t)
            (nb-cell-error-set! c #f))))))

  (define (nb-eval! nb)
    (let ([order (topo-sort nb)])
      (for-each
        (lambda (name) (nb-eval-cell! nb name))
        order)))

) ;; end library
