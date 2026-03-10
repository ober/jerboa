#!chezscheme
;;; :std/misc/alist -- Association list utilities

(library (std misc alist)
  (export agetq agetv aget
          asetq! asetv! aset!
          pgetq pgetv pget
          alist->hash-table)
  (import (except (chezscheme) make-hash-table hash-table? iota 1+ 1-)
          (jerboa runtime))

  (define agetq
    (case-lambda
      ((key alist) (agetq key alist #f))
      ((key alist default)
       (cond [(assq key alist) => cdr]
             [else default]))))

  (define agetv
    (case-lambda
      ((key alist) (agetv key alist #f))
      ((key alist default)
       (cond [(assv key alist) => cdr]
             [else default]))))

  (define aget
    (case-lambda
      ((key alist) (aget key alist #f))
      ((key alist default)
       (cond [(assoc key alist) => cdr]
             [else default]))))

  (define (asetq! key val alist)
    (cond [(assq key alist) => (lambda (p) (set-cdr! p val) alist)]
          [else (cons (cons key val) alist)]))

  (define (asetv! key val alist)
    (cond [(assv key alist) => (lambda (p) (set-cdr! p val) alist)]
          [else (cons (cons key val) alist)]))

  (define (aset! key val alist)
    (cond [(assoc key alist) => (lambda (p) (set-cdr! p val) alist)]
          [else (cons (cons key val) alist)]))

  ;; plist accessors (key val key val ...)
  (define pgetq
    (case-lambda
      ((key plist) (pgetq key plist #f))
      ((key plist default)
       (let loop ([rest plist])
         (cond
           [(null? rest) default]
           [(and (pair? (cdr rest)) (eq? (car rest) key)) (cadr rest)]
           [(pair? (cdr rest)) (loop (cddr rest))]
           [else default])))))

  (define pgetv
    (case-lambda
      ((key plist) (pgetv key plist #f))
      ((key plist default)
       (let loop ([rest plist])
         (cond
           [(null? rest) default]
           [(and (pair? (cdr rest)) (eqv? (car rest) key)) (cadr rest)]
           [(pair? (cdr rest)) (loop (cddr rest))]
           [else default])))))

  (define pget
    (case-lambda
      ((key plist) (pget key plist #f))
      ((key plist default)
       (let loop ([rest plist])
         (cond
           [(null? rest) default]
           [(and (pair? (cdr rest)) (equal? (car rest) key)) (cadr rest)]
           [(pair? (cdr rest)) (loop (cddr rest))]
           [else default])))))

  (define (alist->hash-table alist)
    (let ([ht (make-hash-table)])
      (for-each (lambda (p) (hash-put! ht (car p) (cdr p))) alist)
      ht))

  ) ;; end library
