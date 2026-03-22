#!chezscheme
;;; (std misc plist) -- Property Lists
;;;
;;; A plist is a flat list of alternating keys and values:
;;;   '(key1 val1 key2 val2 ...)
;;; Keys must be symbols. Operations are functional (non-destructive).
;;;
;;; Usage:
;;;   (import (std misc plist))
;;;   (define pl '(name "Alice" age 30))
;;;   (pget pl 'name)            ; => "Alice"
;;;   (pget pl 'missing 'nope)   ; => nope
;;;   (pput pl 'age 31)          ; => (name "Alice" age 31)
;;;   (pdel pl 'age)             ; => (name "Alice")
;;;   (plist? pl)                ; => #t
;;;   (plist->alist pl)          ; => ((name . "Alice") (age . 30))
;;;   (plist-keys pl)            ; => (name age)
;;;   (plist-fold (lambda (k v acc) (+ acc 1)) 0 pl) ; => 2

(library (std misc plist)
  (export
    pget
    pput
    pdel
    plist?
    plist->alist
    alist->plist
    plist-keys
    plist-values
    plist-fold)

  (import (chezscheme))

  ;; Check if obj is a valid plist: list of even length with symbol keys
  (define (plist? obj)
    (and (list? obj)
         (even? (length obj))
         (let loop ([lst obj])
           (cond
             [(null? lst) #t]
             [(not (symbol? (car lst))) #f]
             [else (loop (cddr lst))]))))

  ;; Lookup key in plist, return value or default.
  ;; Uses case-lambda for optional default argument.
  (define pget
    (case-lambda
      [(plist key)
       (pget plist key #f)]
      [(plist key default)
       (let loop ([lst plist])
         (cond
           [(null? lst) default]
           [(eq? (car lst) key) (cadr lst)]
           [else (loop (cddr lst))]))]))

  ;; Return new plist with key set to val. If key exists, replaces it
  ;; in place (preserving order). If not, appends at end.
  (define (pput plist key val)
    (let loop ([lst plist] [acc '()] [found? #f])
      (cond
        [(null? lst)
         (if found?
           (reverse acc)
           (reverse (cons val (cons key acc))))]
        [(eq? (car lst) key)
         (loop (cddr lst)
               (cons val (cons key acc))
               #t)]
        [else
         (loop (cddr lst)
               (cons (cadr lst) (cons (car lst) acc))
               found?)])))

  ;; Return new plist with key removed
  (define (pdel plist key)
    (let loop ([lst plist] [acc '()])
      (cond
        [(null? lst) (reverse acc)]
        [(eq? (car lst) key)
         (loop (cddr lst) acc)]
        [else
         (loop (cddr lst)
               (cons (cadr lst) (cons (car lst) acc)))])))

  ;; Convert plist to association list
  (define (plist->alist plist)
    (let loop ([lst plist] [acc '()])
      (if (null? lst)
        (reverse acc)
        (loop (cddr lst)
              (cons (cons (car lst) (cadr lst)) acc)))))

  ;; Convert association list to plist
  (define (alist->plist alist)
    (let loop ([lst alist] [acc '()])
      (if (null? lst)
        (reverse acc)
        (loop (cdr lst)
              (cons (cdar lst) (cons (caar lst) acc))))))

  ;; Return list of keys in plist order
  (define (plist-keys plist)
    (let loop ([lst plist] [acc '()])
      (if (null? lst)
        (reverse acc)
        (loop (cddr lst) (cons (car lst) acc)))))

  ;; Return list of values in plist order
  (define (plist-values plist)
    (let loop ([lst plist] [acc '()])
      (if (null? lst)
        (reverse acc)
        (loop (cddr lst) (cons (cadr lst) acc)))))

  ;; Fold over plist key-value pairs: (proc key value accum)
  (define (plist-fold proc init plist)
    (let loop ([lst plist] [acc init])
      (if (null? lst)
        acc
        (loop (cddr lst) (proc (car lst) (cadr lst) acc)))))

) ;; end library
