#!chezscheme
;;; (jerboa lock) — Lockfile Management
;;;
;;; S-expression lockfile for exact package pinning.

(library (jerboa lock)
  (export
    ;; Lockfile
    make-lockfile lockfile? lockfile-entries
    lockfile-add! lockfile-remove! lockfile-lookup lockfile-has?

    ;; Lock entry
    make-lock-entry lock-entry? lock-entry-name lock-entry-version
    lock-entry-hash lock-entry-deps

    ;; Serialization
    lockfile->sexp sexp->lockfile lockfile-write lockfile-read

    ;; Operations
    lockfile-merge lockfile-diff)

  (import (chezscheme))

  ;; ========== Lock Entry ==========

  (define-record-type (%lock-entry make-lock-entry lock-entry?)
    (fields (immutable name    lock-entry-name)     ;; string
            (immutable version lock-entry-version)  ;; string "1.2.3"
            (immutable hash    lock-entry-hash)     ;; string SHA-256 hex
            (immutable deps    lock-entry-deps)))   ;; list of strings (names)

  ;; ========== Lockfile ==========

  (define-record-type (%lockfile make-lockfile lockfile?)
    (fields (mutable entries lockfile-entries lockfile-entries-set!)))    ;; list of lock-entry

  (define (lockfile-add! lf entry)
    ;; Add or replace an entry by name.
    (let ([existing (filter (lambda (e)
                              (not (equal? (lock-entry-name e)
                                           (lock-entry-name entry))))
                            (lockfile-entries lf))])
      (lockfile-entries-set! lf (cons entry existing))))

  (define (lockfile-remove! lf name)
    (lockfile-entries-set! lf
      (filter (lambda (e) (not (equal? (lock-entry-name e) name)))
              (lockfile-entries lf))))

  (define (lockfile-lookup lf name)
    ;; Returns lock-entry or #f.
    (let loop ([es (lockfile-entries lf)])
      (cond
        [(null? es) #f]
        [(equal? (lock-entry-name (car es)) name) (car es)]
        [else (loop (cdr es))])))

  (define (lockfile-has? lf name)
    (if (lockfile-lookup lf name) #t #f))

  ;; ========== Serialization ==========

  (define (lockfile->sexp lf)
    ;; Returns: (lockfile (entry name ver hash (dep ...)) ...)
    `(lockfile
       ,@(map (lambda (e)
                `(entry ,(lock-entry-name e)
                        ,(lock-entry-version e)
                        ,(lock-entry-hash e)
                        ,(lock-entry-deps e)))
              (lockfile-entries lf))))

  (define (sexp->lockfile sexp)
    ;; Parse: (lockfile (entry name ver hash (deps ...)) ...)
    (unless (and (pair? sexp) (eq? (car sexp) 'lockfile))
      (error 'sexp->lockfile "invalid lockfile sexp" sexp))
    (let ([entries
           (map (lambda (form)
                  (unless (and (pair? form)
                               (eq? (car form) 'entry)
                               (>= (length form) 5))
                    (error 'sexp->lockfile "invalid entry form" form))
                  (make-lock-entry
                    (list-ref form 1)
                    (list-ref form 2)
                    (list-ref form 3)
                    (list-ref form 4)))
                (cdr sexp))])
      (make-lockfile entries)))

  (define (lockfile-write lf port)
    ;; Write lockfile as S-expression to port.
    (write (lockfile->sexp lf) port)
    (newline port))

  (define (lockfile-read port)
    ;; Read a lockfile from port.
    (let ([sexp (read port)])
      (if (eof-object? sexp)
        (make-lockfile '())
        (sexp->lockfile sexp))))

  ;; ========== Merge and Diff ==========

  (define (lockfile-merge lf1 lf2)
    ;; Merge lf1 and lf2; lf2 entries take precedence on conflicts.
    (let ([result (make-lockfile '())])
      ;; Add all lf1 entries first
      (for-each (lambda (e) (lockfile-add! result e))
                (lockfile-entries lf1))
      ;; Add all lf2 entries (overrides lf1 on same name)
      (for-each (lambda (e) (lockfile-add! result e))
                (lockfile-entries lf2))
      result))

  (define (lockfile-diff lf1 lf2)
    ;; Returns (added removed changed):
    ;;   added   = entries in lf2 not in lf1 (by name)
    ;;   removed = entries in lf1 not in lf2 (by name)
    ;;   changed = entries in both but with different version or hash
    (let* ([e1 (lockfile-entries lf1)]
           [e2 (lockfile-entries lf2)]
           [names1 (map lock-entry-name e1)]
           [names2 (map lock-entry-name e2)]
           [added   (filter (lambda (e) (not (member (lock-entry-name e) names1))) e2)]
           [removed (filter (lambda (e) (not (member (lock-entry-name e) names2))) e1)]
           [changed
            (filter (lambda (e2-entry)
                      (let ([e1-entry (lockfile-lookup lf1 (lock-entry-name e2-entry))])
                        (and e1-entry
                             (not (and (equal? (lock-entry-version e1-entry)
                                               (lock-entry-version e2-entry))
                                       (equal? (lock-entry-hash e1-entry)
                                               (lock-entry-hash e2-entry)))))))
                    e2)])
      (list added removed changed)))

) ;; end library
