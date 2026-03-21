#!chezscheme
;;; (std mvcc) — Multi-Version Concurrency Control
;;;
;;; Persistent data structures with transactional time-travel.
;;; Every write creates a new version; reads never block writes.
;;;
;;; API:
;;;   (make-mvcc-store)              — create MVCC store
;;;   (mvcc-transact! store proc)    — execute transaction (proc takes tx)
;;;   (tx-get tx key)                — read within transaction
;;;   (tx-put! tx key val)           — write within transaction
;;;   (tx-delete! tx key)            — delete within transaction
;;;   (mvcc-get store key)           — read latest committed value
;;;   (mvcc-as-of store version proc) — read at historical version
;;;   (mvcc-version store)           — current version number
;;;   (mvcc-history store key)       — all versions of a key

(library (std mvcc)
  (export make-mvcc-store mvcc-transact! mvcc-get mvcc-as-of
          mvcc-version mvcc-history mvcc-keys
          tx-get tx-put! tx-delete!)

  (import (chezscheme))

  ;; ========== Store ==========
  ;; key -> list of (version . value), most recent first

  (define-record-type mvcc-store
    (fields
      (immutable data)         ;; eq-hashtable: key -> ((ver . val) ...)
      (mutable version)
      (immutable mutex))
    (protocol
      (lambda (new)
        (lambda () (new (make-eq-hashtable) 0 (make-mutex))))))

  ;; ========== Transaction ==========

  (define-record-type mvcc-tx
    (fields
      (immutable store)
      (immutable read-version)
      (mutable writes)         ;; alist: key -> val or 'deleted
      (mutable reads))         ;; list of keys read
    (protocol
      (lambda (new)
        (lambda (store ver)
          (new store ver '() '())))))

  (define (tx-get tx key)
    ;; Check local writes first
    (let ([local (assq key (mvcc-tx-writes tx))])
      (if local
        (if (eq? (cdr local) 'deleted) #f (cdr local))
        ;; Read from store at read-version
        (let ([versions (hashtable-ref
                          (mvcc-store-data (mvcc-tx-store tx))
                          key '())])
          (mvcc-tx-reads-set! tx (cons key (mvcc-tx-reads tx)))
          (let loop ([vs versions])
            (cond
              [(null? vs) #f]
              [(<= (caar vs) (mvcc-tx-read-version tx))
               (let ([val (cdar vs)])
                 (if (eq? val 'deleted) #f val))]
              [else (loop (cdr vs))]))))))

  (define (tx-put! tx key val)
    (mvcc-tx-writes-set! tx
      (cons (cons key val)
            (filter (lambda (w) (not (eq? (car w) key)))
                    (mvcc-tx-writes tx)))))

  (define (tx-delete! tx key)
    (tx-put! tx key 'deleted))

  ;; ========== Commit ==========

  (define (mvcc-transact! store proc)
    (with-mutex (mvcc-store-mutex store)
      (let* ([ver (mvcc-store-version store)]
             [tx (make-mvcc-tx store ver)]
             [result (proc tx)]
             [new-ver (+ ver 1)])
        ;; Apply writes
        (for-each
          (lambda (write)
            (let* ([key (car write)]
                   [val (cdr write)]
                   [existing (hashtable-ref (mvcc-store-data store) key '())])
              (hashtable-set! (mvcc-store-data store) key
                (cons (cons new-ver val) existing))))
          (mvcc-tx-writes tx))
        (mvcc-store-version-set! store new-ver)
        result)))

  ;; ========== Direct reads ==========

  (define (mvcc-get store key)
    (let ([versions (hashtable-ref (mvcc-store-data store) key '())])
      (if (null? versions)
        #f
        (let ([val (cdar versions)])
          (if (eq? val 'deleted) #f val)))))

  (define (mvcc-as-of store version proc)
    (let ([tx (make-mvcc-tx store version)])
      (proc tx)))

  (define (mvcc-version store)
    (mvcc-store-version store))

  (define (mvcc-keys store)
    (let-values ([(keys vals) (hashtable-entries (mvcc-store-data store))])
      (let ([result '()])
        (vector-for-each
          (lambda (k v)
            ;; Only include if latest version is not deleted
            (when (and (pair? v) (not (eq? (cdar v) 'deleted)))
              (set! result (cons k result))))
          keys vals)
        result)))

  (define (mvcc-history store key)
    (let ([versions (hashtable-ref (mvcc-store-data store) key '())])
      (map (lambda (v) (cons (car v)
                              (if (eq? (cdr v) 'deleted) #f (cdr v))))
           (reverse versions))))

) ;; end library
