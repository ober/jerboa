#!chezscheme
;;; (std misc ck-macros) — CK abstract machine for composable higher-order macros
;;;
;;; Based on Oleg Kiselyov's CK machine: composable macros built entirely
;;; with syntax-rules, no syntax-case needed.  CK macros pass their results
;;; to a continuation stack, enabling composition at macro-expansion time.
;;;
;;; Usage:
;;;   (ck () (c-cons '1 '(2 3)))              => (1 2 3)
;;;   (ck () (c-map (c-cons 'x) '(1 2 3)))   => ((x . 1) (x . 2) (x . 3))
;;;   (ck () (c-reverse '(a b c)))            => (c b a)
;;;
;;; All CK macro arguments must be either:
;;;   - Quoted values: '(datum) or 'atom
;;;   - CK expressions: (c-op args ...)
;;; The ck machine evaluates nested CK expressions automatically.

(library (std misc ck-macros)
  (export ck c-quote c-cons c-car c-cdr c-null? c-if
          c-map c-filter c-foldr c-append c-reverse c-length)
  (import (chezscheme))

  ;; ---------------------------------------------------------------------------
  ;; The CK machine
  ;;
  ;; Stack frames are lists (op saved-arg ...).  When a value 'v is produced,
  ;; the machine calls (op s 'v saved-arg ...) where s is the remaining stack.
  ;; ---------------------------------------------------------------------------

  (define-syntax ck
    (syntax-rules (quote)
      ;; Value with empty stack: done
      [(ck () 'v) 'v]
      ;; Value with stack: apply top frame
      ;; Frame = (op saved ...), call as (op remaining-stack 'v saved ...)
      [(ck ((op saved ...) . s) 'v)
       (op s 'v saved ...)]
      ;; CK expression: dispatch to operator
      [(ck s (op arg ...))
       (op s arg ...)]))

  ;; ---------------------------------------------------------------------------
  ;; c-quote
  ;; ---------------------------------------------------------------------------

  (define-syntax c-quote
    (syntax-rules ()
      [(c-quote s v) (ck s 'v)]))

  ;; ---------------------------------------------------------------------------
  ;; c-cons
  ;; ---------------------------------------------------------------------------

  (define-syntax c-cons
    (syntax-rules (quote)
      [(c-cons s 'a 'b) (ck s '(a . b))]
      ;; Second arg needs evaluation
      [(c-cons s 'a b)
       (ck ((c-cons-k 'a) . s) b)]
      ;; First arg needs evaluation
      [(c-cons s a b)
       (ck ((c-cons-k2 b) . s) a)]))

  ;; Called as (c-cons-k s 'v 'a) — v is evaluated second arg, a is saved first
  (define-syntax c-cons-k
    (syntax-rules (quote)
      [(c-cons-k s 'b 'a) (ck s '(a . b))]))

  ;; Called as (c-cons-k2 s 'v b) — v is evaluated first arg, b still needs eval
  (define-syntax c-cons-k2
    (syntax-rules (quote)
      [(c-cons-k2 s 'a b) (c-cons s 'a b)]))

  ;; ---------------------------------------------------------------------------
  ;; c-car / c-cdr
  ;; ---------------------------------------------------------------------------

  (define-syntax c-car
    (syntax-rules (quote)
      [(c-car s '(h . t)) (ck s 'h)]
      [(c-car s e) (ck ((c-car-k) . s) e)]))

  (define-syntax c-car-k
    (syntax-rules (quote)
      [(c-car-k s 'v) (c-car s 'v)]))

  (define-syntax c-cdr
    (syntax-rules (quote)
      [(c-cdr s '(h . t)) (ck s 't)]
      [(c-cdr s e) (ck ((c-cdr-k) . s) e)]))

  (define-syntax c-cdr-k
    (syntax-rules (quote)
      [(c-cdr-k s 'v) (c-cdr s 'v)]))

  ;; ---------------------------------------------------------------------------
  ;; c-null?
  ;; ---------------------------------------------------------------------------

  (define-syntax c-null?
    (syntax-rules (quote)
      [(c-null? s '()) (ck s '#t)]
      [(c-null? s '(h . t)) (ck s '#f)]
      [(c-null? s 'v) (ck s '#f)]
      [(c-null? s e) (ck ((c-null?-k) . s) e)]))

  (define-syntax c-null?-k
    (syntax-rules (quote)
      [(c-null?-k s 'v) (c-null? s 'v)]))

  ;; ---------------------------------------------------------------------------
  ;; c-if
  ;; ---------------------------------------------------------------------------

  (define-syntax c-if
    (syntax-rules (quote)
      [(c-if s '#f then else) (ck s else)]
      [(c-if s '#t then else) (ck s then)]
      [(c-if s 'other then else) (ck s then)]
      [(c-if s test then else)
       (ck ((c-if-k then else) . s) test)]))

  ;; Called as (c-if-k s 'v then else)
  (define-syntax c-if-k
    (syntax-rules (quote)
      [(c-if-k s 'v then else) (c-if s 'v then else)]))

  ;; ---------------------------------------------------------------------------
  ;; c-map
  ;; ---------------------------------------------------------------------------

  (define-syntax c-map
    (syntax-rules (quote)
      [(c-map s (f ...) '()) (ck s '())]
      [(c-map s (f ...) '(h . t))
       (ck ((c-map-k (f ...) 't) . s) (f ... 'h))]
      [(c-map s f e) (ck ((c-map-k2 f) . s) e)]))

  ;; Head mapped to 'v; now map tail
  ;; Called as (c-map-k s 'v (f ...) 't)
  (define-syntax c-map-k
    (syntax-rules (quote)
      [(c-map-k s 'v (f ...) 'tail)
       (ck ((c-map-k3 'v) . s) (c-map (f ...) 'tail))]))

  ;; Tail mapped to 'rest; cons with head
  ;; Called as (c-map-k3 s 'rest 'head)
  (define-syntax c-map-k3
    (syntax-rules (quote)
      [(c-map-k3 s 'rest 'head) (ck s '(head . rest))]))

  ;; List evaluated to 'v; now map
  (define-syntax c-map-k2
    (syntax-rules (quote)
      [(c-map-k2 s 'v f) (c-map s f 'v)]))

  ;; ---------------------------------------------------------------------------
  ;; c-filter
  ;; ---------------------------------------------------------------------------

  (define-syntax c-filter
    (syntax-rules (quote)
      [(c-filter s (p ...) '()) (ck s '())]
      [(c-filter s (p ...) '(h . t))
       (ck ((c-filter-k (p ...) 'h 't) . s) (p ... 'h))]
      [(c-filter s p e) (ck ((c-filter-k2 p) . s) e)]))

  ;; Predicate result: (c-filter-k s 'v (p ...) 'h 't)
  (define-syntax c-filter-k
    (syntax-rules (quote)
      [(c-filter-k s '#f (p ...) 'h 't)
       (ck s (c-filter (p ...) 't))]
      [(c-filter-k s 'v (p ...) 'h 't)
       (ck ((c-filter-k3 'h) . s) (c-filter (p ...) 't))]))

  ;; Filtered tail ready; cons head
  (define-syntax c-filter-k3
    (syntax-rules (quote)
      [(c-filter-k3 s 'rest 'h) (ck s '(h . rest))]))

  (define-syntax c-filter-k2
    (syntax-rules (quote)
      [(c-filter-k2 s 'v p) (c-filter s p 'v)]))

  ;; ---------------------------------------------------------------------------
  ;; c-foldr
  ;; ---------------------------------------------------------------------------

  (define-syntax c-foldr
    (syntax-rules (quote)
      [(c-foldr s (f ...) 'init '()) (ck s 'init)]
      [(c-foldr s (f ...) 'init '(h . t))
       (ck ((c-foldr-k (f ...) 'h) . s) (c-foldr (f ...) 'init 't))]
      [(c-foldr s f init e) (ck ((c-foldr-k2 f init) . s) e)]))

  ;; Tail folded to 'v; apply f to h and v
  (define-syntax c-foldr-k
    (syntax-rules (quote)
      [(c-foldr-k s 'v (f ...) 'h) (ck s (f ... 'h 'v))]))

  (define-syntax c-foldr-k2
    (syntax-rules (quote)
      [(c-foldr-k2 s 'v f init) (c-foldr s f init 'v)]))

  ;; ---------------------------------------------------------------------------
  ;; c-append
  ;; ---------------------------------------------------------------------------

  (define-syntax c-append
    (syntax-rules (quote)
      [(c-append s '() 'b) (ck s 'b)]
      [(c-append s '(h . t) 'b)
       (ck ((c-append-k 'h) . s) (c-append 't 'b))]
      [(c-append s 'a b) (ck ((c-append-k2 'a) . s) b)]
      [(c-append s a b) (ck ((c-append-k3 b) . s) a)]))

  (define-syntax c-append-k
    (syntax-rules (quote)
      [(c-append-k s 'rest 'h) (ck s '(h . rest))]))

  (define-syntax c-append-k2
    (syntax-rules (quote)
      [(c-append-k2 s 'b 'a) (c-append s 'a 'b)]))

  (define-syntax c-append-k3
    (syntax-rules (quote)
      [(c-append-k3 s 'a b) (c-append s 'a b)]))

  ;; ---------------------------------------------------------------------------
  ;; c-reverse (accumulator-based, O(n))
  ;; ---------------------------------------------------------------------------

  (define-syntax c-reverse
    (syntax-rules (quote)
      [(c-reverse s 'lst) (c-reverse* s '() 'lst)]
      [(c-reverse s e) (ck ((c-reverse-k) . s) e)]))

  (define-syntax c-reverse-k
    (syntax-rules (quote)
      [(c-reverse-k s 'v) (c-reverse s 'v)]))

  (define-syntax c-reverse*
    (syntax-rules (quote)
      [(c-reverse* s 'acc '()) (ck s 'acc)]
      [(c-reverse* s 'acc '(h . t)) (c-reverse* s '(h . acc) 't)]))

  ;; ---------------------------------------------------------------------------
  ;; c-length
  ;;
  ;; Returns length as a Peano-encoded list: '() = 0, '(s) = 1, '(s s) = 2.
  ;; Use (length (ck () (c-length ...))) to get a runtime number.
  ;; ---------------------------------------------------------------------------

  (define-syntax c-length
    (syntax-rules (quote)
      [(c-length s 'lst) (c-length* s '() 'lst)]
      [(c-length s e) (ck ((c-length-k) . s) e)]))

  (define-syntax c-length-k
    (syntax-rules (quote)
      [(c-length-k s 'v) (c-length s 'v)]))

  (define-syntax c-length*
    (syntax-rules (quote)
      [(c-length* s 'acc '()) (ck s 'acc)]
      [(c-length* s 'acc '(h . t)) (c-length* s '(s . acc) 't)]))

) ;; end library
