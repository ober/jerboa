#!chezscheme
;;; (std ref) — Generic polymorphic accessor
;;;
;;; Provides a unified interface for accessing elements in different
;;; collection types: lists, vectors, hashtables, strings, and alists.
;;;
;;; API:
;;;   (ref obj key)              — polymorphic access
;;;   (ref obj k1 k2 ...)       — nested/chained access
;;;   (ref-set! obj key val)    — polymorphic mutation
;;;   (~ obj key ...)           — alias for ref

(library (std ref)
  (export ref ref-set! ~)

  (import (chezscheme))

  ;; Single-key polymorphic access
  (define (ref-1 obj key)
    (cond
      [(vector? obj)
       (vector-ref obj key)]
      [(hashtable? obj)
       (hashtable-ref obj key #f)]
      [(string? obj)
       (string-ref obj key)]
      [(and (pair? obj) (symbol? key))
       ;; Alist lookup: key is a symbol, obj is an association list
       (let ([result (assoc key obj)])
         (if result
             (cdr result)
             #f))]
      [(pair? obj)
       ;; Treat as a list with integer index
       (list-ref obj key)]
      [else
       (error 'ref "unsupported type for ref" obj key)]))

  ;; Polymorphic mutation
  (define (ref-set! obj key val)
    (cond
      [(vector? obj)
       (vector-set! obj key val)]
      [(hashtable? obj)
       (hashtable-set! obj key val)]
      [(string? obj)
       (string-set! obj key val)]
      [else
       (error 'ref-set! "unsupported type for ref-set!" obj key)]))

  ;; Multi-key (nested) polymorphic access
  (define (ref obj . keys)
    (if (null? keys)
        (error 'ref "ref requires at least one key")
        (let loop ([current obj] [ks keys])
          (if (null? ks)
              current
              (loop (ref-1 current (car ks)) (cdr ks))))))

  ;; Alias
  (define ~ ref)

) ;; end library
