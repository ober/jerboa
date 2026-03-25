#!chezscheme
;;; :std/misc/alist -- Association list utilities

(library (std misc alist)
  (export agetq agetv aget
          asetq! asetv! aset!
          pgetq pgetv pget
          alist->hash-table
          ;; Gerbil v0.19 compatibility
          alist? acons
          asetq asetv aset          ; pure functional set
          aremq aremv arem          ; pure remove
          aremq! aremv! arem!       ; destructive remove
          psetq psetv pset          ; pure plist set
          psetq! psetv! pset!       ; destructive plist set
          premq premv prem          ; pure plist remove
          premq! premv! prem!       ; destructive plist remove
          plist->alist* alist->plist*)
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

  ;; ---- Gerbil v0.19 compatibility ----

  ;; alist? predicate: proper list of pairs
  (define (alist? obj)
    (let loop ((lst obj))
      (cond
        ((null? lst) #t)
        ((and (pair? lst) (pair? (car lst)))
         (loop (cdr lst)))
        (else #f))))

  ;; acons: prepend a key-value pair
  (define (acons key val alist)
    (cons (cons key val) alist))

  ;; Pure functional alist set (returns new alist, replaces existing key)
  (define (asetq key val alist)
    (%aset eq? key val alist))

  (define (asetv key val alist)
    (%aset eqv? key val alist))

  (define (aset key val alist)
    (%aset equal? key val alist))

  (define (%aset cmp key val alist)
    (let loop ((rest alist) (acc '()))
      (cond
        ((null? rest)
         (cons (cons key val) alist))  ; not found, prepend
        ((cmp (caar rest) key)
         (append (reverse acc) (cons (cons key val) (cdr rest))))
        (else
         (loop (cdr rest) (cons (car rest) acc))))))

  ;; Pure alist remove (returns new alist without key)
  (define (aremq key alist)
    (%arem eq? key alist))

  (define (aremv key alist)
    (%arem eqv? key alist))

  (define (arem key alist)
    (%arem equal? key alist))

  (define (%arem cmp key alist)
    (let loop ((rest alist) (acc '()))
      (cond
        ((null? rest) alist)  ; not found, return original
        ((cmp (caar rest) key)
         (append (reverse acc) (cdr rest)))
        (else
         (loop (cdr rest) (cons (car rest) acc))))))

  ;; Destructive alist remove
  (define (aremq! key alist)
    (%arem! eq? key alist))

  (define (aremv! key alist)
    (%arem! eqv? key alist))

  (define (arem! key alist)
    (%arem! equal? key alist))

  (define (%arem! cmp key alist)
    (cond
      ((null? alist) alist)
      ((cmp (caar alist) key) (cdr alist))
      (else
       (let loop ((prev alist) (rest (cdr alist)))
         (cond
           ((null? rest) alist)
           ((cmp (caar rest) key)
            (set-cdr! prev (cdr rest))
            alist)
           (else (loop rest (cdr rest))))))))

  ;; Pure plist set (with comparison variants)
  (define (psetq key val plist)
    (%pset eq? key val plist))

  (define (psetv key val plist)
    (%pset eqv? key val plist))

  (define (pset key val plist)
    (%pset equal? key val plist))

  (define (%pset cmp key val plist)
    (let loop ((rest plist) (acc '()))
      (cond
        ((null? rest)
         (append (reverse acc) (list key val)))  ; not found, append
        ((and (pair? (cdr rest)) (cmp (car rest) key))
         (append (reverse acc) (cons key (cons val (cddr rest)))))
        ((pair? (cdr rest))
         (loop (cddr rest) (cons (cadr rest) (cons (car rest) acc))))
        (else
         (append (reverse acc) (list key val))))))

  ;; Destructive plist set
  (define (psetq! key val plist)
    (%pset! eq? key val plist))

  (define (psetv! key val plist)
    (%pset! eqv? key val plist))

  (define (pset! key val plist)
    (%pset! equal? key val plist))

  (define (%pset! cmp key val plist)
    (let loop ((rest plist))
      (cond
        ((null? rest)
         (error '%pset! "cannot destructively set on empty plist" key val))
        ((and (pair? (cdr rest)) (cmp (car rest) key))
         (set-car! (cdr rest) val)
         plist)
        ((pair? (cdr rest))
         (loop (cddr rest)))
        (else
         ;; Key not found — prepend by mutation
         (let ((old-key (car plist))
               (old-rest (cdr plist)))
           (set-car! plist key)
           (set-cdr! plist (cons val (cons old-key old-rest)))
           plist)))))

  ;; Pure plist remove
  (define (premq key plist)
    (%prem eq? key plist))

  (define (premv key plist)
    (%prem eqv? key plist))

  (define (prem key plist)
    (%prem equal? key plist))

  (define (%prem cmp key plist)
    (let loop ((rest plist) (acc '()))
      (cond
        ((null? rest) plist)  ; not found
        ((and (pair? (cdr rest)) (cmp (car rest) key))
         (append (reverse acc) (cddr rest)))
        ((pair? (cdr rest))
         (loop (cddr rest) (cons (cadr rest) (cons (car rest) acc))))
        (else plist))))

  ;; Destructive plist remove
  (define (premq! key plist)
    (%prem! eq? key plist))

  (define (premv! key plist)
    (%prem! eqv? key plist))

  (define (prem! key plist)
    (%prem! equal? key plist))

  (define (%prem! cmp key plist)
    (cond
      ((null? plist) plist)
      ((and (pair? (cdr plist)) (cmp (car plist) key))
       (cddr plist))  ; remove head pair
      (else
       (let loop ((prev plist) (rest (cddr plist)))
         (cond
           ((null? rest) plist)
           ((and (pair? (cdr rest)) (cmp (car rest) key))
            (set-cdr! (cdr prev) (cddr rest))
            plist)
           ((pair? (cdr rest))
            (loop (cdr rest) (cddr rest)))
           (else plist))))))

  ;; plist->alist conversion (any key type, uses comparison)
  (define (plist->alist* plist)
    (let loop ((rest plist) (acc '()))
      (if (or (null? rest) (null? (cdr rest)))
        (reverse acc)
        (loop (cddr rest)
              (cons (cons (car rest) (cadr rest)) acc)))))

  ;; alist->plist conversion
  (define (alist->plist* alist)
    (let loop ((rest alist) (acc '()))
      (if (null? rest)
        (reverse acc)
        (loop (cdr rest)
              (cons (cdar rest) (cons (caar rest) acc))))))

  ) ;; end library
