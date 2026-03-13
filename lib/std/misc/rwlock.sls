#!chezscheme
;;; :std/misc/rwlock -- Read-write locks
;;;
;;; Concurrent readers, exclusive writers. Multiple threads can hold
;;; the read lock simultaneously, but the write lock is exclusive.
;;;
;;; (define lock (make-rwlock))
;;; (with-read-lock lock (lambda () (read-shared-data)))
;;; (with-write-lock lock (lambda () (update-shared-data!)))

(library (std misc rwlock)
  (export make-rwlock rwlock?
          read-lock! read-unlock!
          write-lock! write-unlock!
          with-read-lock with-write-lock)

  (import (chezscheme))

  (define-record-type rwlock
    (fields
      (immutable mtx)           ;; mutex protecting state
      (immutable read-ok)       ;; condition: readers can proceed
      (immutable write-ok)      ;; condition: writer can proceed
      (mutable readers)         ;; number of active readers
      (mutable writer?)         ;; #t if a writer holds the lock
      (mutable waiting-writers));; number of writers waiting
    (protocol
      (lambda (new)
        (lambda ()
          (new (make-mutex) (make-condition) (make-condition) 0 #f 0)))))

  (define (read-lock! rw)
    (let ([m (rwlock-mtx rw)])
      (mutex-acquire m)
      ;; Wait while a writer holds or writers are waiting (writer preference)
      (let lp ()
        (when (or (rwlock-writer? rw) (> (rwlock-waiting-writers rw) 0))
          (condition-wait (rwlock-read-ok rw) m)
          (lp)))
      (rwlock-readers-set! rw (+ (rwlock-readers rw) 1))
      (mutex-release m)))

  (define (read-unlock! rw)
    (let ([m (rwlock-mtx rw)])
      (mutex-acquire m)
      (rwlock-readers-set! rw (- (rwlock-readers rw) 1))
      (when (= (rwlock-readers rw) 0)
        ;; Last reader out — wake a waiting writer
        (condition-signal (rwlock-write-ok rw)))
      (mutex-release m)))

  (define (write-lock! rw)
    (let ([m (rwlock-mtx rw)])
      (mutex-acquire m)
      (rwlock-waiting-writers-set! rw (+ (rwlock-waiting-writers rw) 1))
      ;; Wait until no readers and no writer
      (let lp ()
        (when (or (rwlock-writer? rw) (> (rwlock-readers rw) 0))
          (condition-wait (rwlock-write-ok rw) m)
          (lp)))
      (rwlock-waiting-writers-set! rw (- (rwlock-waiting-writers rw) 1))
      (rwlock-writer?-set! rw #t)
      (mutex-release m)))

  (define (write-unlock! rw)
    (let ([m (rwlock-mtx rw)])
      (mutex-acquire m)
      (rwlock-writer?-set! rw #f)
      ;; Wake all waiting readers and one waiting writer
      (condition-broadcast (rwlock-read-ok rw))
      (condition-signal (rwlock-write-ok rw))
      (mutex-release m)))

  (define (with-read-lock rw thunk)
    (dynamic-wind
      (lambda () (read-lock! rw))
      thunk
      (lambda () (read-unlock! rw))))

  (define (with-write-lock rw thunk)
    (dynamic-wind
      (lambda () (write-lock! rw))
      thunk
      (lambda () (write-unlock! rw))))

  ) ;; end library
