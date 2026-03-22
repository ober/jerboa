#!chezscheme
;;; :std/srfi/116 -- Immutable Lists (SRFI-116)
;;; Immutable pairs that cannot be mutated with set-car!/set-cdr!.
;;; Implemented using a sealed record type.

(library (std srfi srfi-116)
  (export
    ipair ilist icar icdr ipair? inull? ilist?
    ilength iappend ireverse imap ifor-each ifold iunfold
    ifilter iremove itake idrop ilist-ref
    ilist->list list->ilist)

  (import (chezscheme))

  ;; The immutable null sentinel
  (define-record-type inull-type
    (sealed #t))

  (define inull (make-inull-type))

  (define (inull? x) (inull-type? x))

  ;; Immutable pair
  (define-record-type ipair-rec
    (fields (immutable kar)
            (immutable kdr))
    (sealed #t))

  (define (ipair a d) (make-ipair-rec a d))

  (define (ipair? x) (ipair-rec? x))

  (define (icar p)
    (unless (ipair? p) (error 'icar "not an ipair" p))
    (ipair-rec-kar p))

  (define (icdr p)
    (unless (ipair? p) (error 'icdr "not an ipair" p))
    (ipair-rec-kdr p))

  (define (ilist . args)
    (fold-right ipair inull args))

  (define (ilist? x)
    (or (inull? x)
        (and (ipair? x) (ilist? (icdr x)))))

  (define (ilength lst)
    (let loop ([l lst] [n 0])
      (if (inull? l) n
          (begin
            (unless (ipair? l) (error 'ilength "not an ilist" l))
            (loop (icdr l) (+ n 1))))))

  (define (iappend . lsts)
    (cond
      [(null? lsts) inull]
      [(null? (cdr lsts)) (car lsts)]
      [else
       (let append2 ([a (car lsts)] [b (apply iappend (cdr lsts))])
         (if (inull? a) b
             (ipair (icar a) (append2 (icdr a) b))))]))

  (define (ireverse lst)
    (let loop ([l lst] [acc inull])
      (if (inull? l) acc
          (loop (icdr l) (ipair (icar l) acc)))))

  (define (imap f lst)
    (if (inull? lst) inull
        (ipair (f (icar lst)) (imap f (icdr lst)))))

  (define (ifor-each f lst)
    (unless (inull? lst)
      (f (icar lst))
      (ifor-each f (icdr lst))))

  (define (ifold f seed lst)
    (if (inull? lst) seed
        (ifold f (f (icar lst) seed) (icdr lst))))

  (define (iunfold p f g seed . maybe-tail)
    (let ([tail-gen (if (null? maybe-tail) (lambda (x) inull) (car maybe-tail))])
      (let loop ([s seed])
        (if (p s)
            (tail-gen s)
            (ipair (f s) (loop (g s)))))))

  (define (ifilter pred lst)
    (if (inull? lst) inull
        (if (pred (icar lst))
            (ipair (icar lst) (ifilter pred (icdr lst)))
            (ifilter pred (icdr lst)))))

  (define (iremove pred lst)
    (ifilter (lambda (x) (not (pred x))) lst))

  (define (itake lst n)
    (if (zero? n) inull
        (ipair (icar lst) (itake (icdr lst) (- n 1)))))

  (define (idrop lst n)
    (if (zero? n) lst
        (idrop (icdr lst) (- n 1))))

  (define (ilist-ref lst n)
    (icar (idrop lst n)))

  (define (ilist->list lst)
    (if (inull? lst) '()
        (cons (icar lst) (ilist->list (icdr lst)))))

  (define (list->ilist lst)
    (fold-right ipair inull lst))
)
