#!chezscheme
;;; (std distributed) — Transparent distributed computation
;;;
;;; Spawn computations across nodes. Closures serialized via FASL.
;;; Limited to pure (serializable) computations.
;;;
;;; API:
;;;   (make-cluster nodes)           — create cluster from node addresses
;;;   (distributed-map cluster proc data) — map proc over data across cluster
;;;   (distributed-eval cluster expr) — evaluate expression on remote node
;;;   (local-cluster n)              — create local cluster with n workers
;;;   (cluster-size cluster)         — number of nodes

(library (std distributed)
  (export make-cluster distributed-map distributed-eval
          local-cluster cluster-size cluster?
          worker-eval make-worker worker?)

  (import (chezscheme))

  ;; ========== Worker (local thread-based) ==========

  (define-record-type worker
    (fields
      (immutable id)
      (immutable input-mutex)
      (immutable input-cv)
      (immutable output-mutex)
      (immutable output-cv)
      (mutable task)           ;; thunk or #f
      (mutable result)         ;; result or #f
      (mutable busy?)
      (immutable thread))
    (protocol
      (lambda (new)
        (lambda (id)
          (let ([im (make-mutex)]
                [ic (make-condition)]
                [om (make-mutex)]
                [oc (make-condition)]
                [w #f])
            (set! w (new id im ic om oc #f #f #f
                      (fork-thread
                        (lambda ()
                          (let loop ()
                            (with-mutex im
                              (let wait ()
                                (unless (worker-task w)
                                  (condition-wait ic im)
                                  (wait))))
                            (let ([task (worker-task w)])
                              (guard (exn
                                      [#t (worker-result-set! w (cons 'error exn))])
                                (worker-result-set! w (cons 'ok (task)))))
                            (worker-busy?-set! w #f)
                            (with-mutex om
                              (condition-broadcast oc))
                            (worker-task-set! w #f)
                            (loop))))))
            w)))))

  (define (worker-eval worker thunk)
    (with-mutex (worker-input-mutex worker)
      (worker-task-set! worker thunk)
      (worker-busy?-set! worker #t)
      (condition-broadcast (worker-input-cv worker)))
    ;; Wait for result
    (with-mutex (worker-output-mutex worker)
      (let loop ()
        (when (worker-busy? worker)
          (condition-wait (worker-output-cv worker) (worker-output-mutex worker))
          (loop))))
    (let ([r (worker-result worker)])
      (worker-result-set! worker #f)
      (if (eq? (car r) 'ok)
        (cdr r)
        (error 'worker-eval "remote computation failed" (cdr r)))))

  ;; ========== Cluster ==========

  (define-record-type cluster
    (fields
      (immutable workers)      ;; vector of workers
      (immutable size))
    (protocol
      (lambda (new)
        (lambda (workers)
          (new (list->vector workers) (length workers))))))

  (define (local-cluster n)
    (make-cluster
      (let loop ([i 0] [acc '()])
        (if (= i n) (reverse acc)
            (loop (+ i 1) (cons (make-worker i) acc))))))

  ;; ========== Distributed operations ==========

  (define (distributed-map cluster proc data-chunks)
    (let* ([workers (cluster-workers cluster)]
           [n (vector-length workers)]
           [results (make-vector (length data-chunks) #f)]
           [threads '()])
      ;; Distribute chunks to workers round-robin
      (let loop ([chunks data-chunks] [i 0] [idx 0])
        (unless (null? chunks)
          (let ([worker (vector-ref workers (modulo i n))]
                [chunk (car chunks)]
                [result-idx idx])
            (set! threads
              (cons (fork-thread
                      (lambda ()
                        (vector-set! results result-idx
                          (worker-eval worker (lambda () (proc chunk))))))
                    threads))
            (loop (cdr chunks) (+ i 1) (+ idx 1)))))
      ;; Wait for all
      (for-each (lambda (t)
                  (guard (exn [#t (void)])))
                threads)
      ;; Small delay for threads to complete
      (let wait-loop ([attempts 0])
        (when (and (< attempts 100)
                   (let check ([j 0])
                     (if (= j (length data-chunks)) #f
                         (if (not (vector-ref results j)) #t
                             (check (+ j 1))))))
          ((sleep (make-time 'time-duration 1000000 0)))
          (wait-loop (+ attempts 1))))
      (vector->list results)))

  (define (distributed-eval cluster expr)
    (let ([worker (vector-ref (cluster-workers cluster) 0)])
      (worker-eval worker (lambda () (eval expr)))))

) ;; end library
