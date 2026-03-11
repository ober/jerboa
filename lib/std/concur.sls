#!chezscheme
;;; (std concur) — Concurrency Safety Toolkit (Steps 45-47)
;;;
;;; Step 45: Thread-safety annotations for data structures.
;;; Step 46: Runtime deadlock detection via lock-order tracking.
;;; Step 47: Resource leak detection for open handles.

(library (std concur)
  (export
    ;; Step 45: Thread-safety annotations
    defstruct/immutable
    defstruct/thread-local
    defstruct/thread-safe
    thread-safety-of
    immutable?
    thread-local-marker?

    ;; Step 46: Deadlock detection
    make-tracked-mutex
    tracked-mutex?
    tracked-lock!
    tracked-unlock!
    with-tracked-mutex
    deadlock-check!
    lock-order-violations
    reset-lock-tracking!

    ;; Step 47: Resource leak detection
    register-resource!
    close-resource!
    task-resources
    check-resource-leaks!
    with-resource-tracking
    open-resource-count)

  (import (chezscheme))

  ;; ========== Annotation Store ==========

  ;; Global table mapping struct instances to their safety annotation.
  (define *safety-annotations* (make-eq-hashtable))

  (define (annotate-safety! obj tag)
    (hashtable-set! *safety-annotations* obj tag))

  (define (thread-safety-of obj)
    (hashtable-ref *safety-annotations* obj 'unannotated))

  (define (immutable? obj)
    (eq? (thread-safety-of obj) 'immutable))

  (define (thread-local-marker? obj)
    (eq? (thread-safety-of obj) 'thread-local))

  ;; ========== Step 45: Thread-Safety Annotation Macros ==========

  ;; Helper: generate a symbol by prepending a prefix to a symbol.
  (define (sym-prefix prefix sym)
    (string->symbol (string-append prefix (symbol->string sym))))

  ;; We define the record type with a private constructor name,
  ;; then export a wrapper constructor that annotates the instance.

  (define-syntax defstruct/immutable
    (lambda (stx)
      (syntax-case stx ()
        ((_ sname (field ...))
         (let* ((sn     (syntax->datum #'sname))
                (make-n (datum->syntax #'sname (string->symbol (string-append "make-" (symbol->string sn)))))
                (pred-n (datum->syntax #'sname (string->symbol (string-append (symbol->string sn) "?"))))
                (raw-n  (datum->syntax #'sname (string->symbol (string-append "%imraw-" (symbol->string sn)))))
                (rawp-n (datum->syntax #'sname (string->symbol (string-append "%imrawp-" (symbol->string sn))))))
           #`(begin
               (define-record-type (sname #,raw-n #,rawp-n)
                 (fields (immutable field) ...))
               (define (#,make-n . args)
                 (let ((inst (apply #,raw-n args)))
                   (annotate-safety! inst 'immutable)
                   inst))
               (define #,pred-n #,rawp-n)))))))

  (define-syntax defstruct/thread-local
    (lambda (stx)
      (syntax-case stx ()
        ((_ sname (field ...))
         (let* ((sn     (syntax->datum #'sname))
                (make-n (datum->syntax #'sname (string->symbol (string-append "make-" (symbol->string sn)))))
                (pred-n (datum->syntax #'sname (string->symbol (string-append (symbol->string sn) "?"))))
                (raw-n  (datum->syntax #'sname (string->symbol (string-append "%tlraw-" (symbol->string sn)))))
                (rawp-n (datum->syntax #'sname (string->symbol (string-append "%tlrawp-" (symbol->string sn))))))
           #`(begin
               (define-record-type (sname #,raw-n #,rawp-n)
                 (fields (mutable field) ...))
               (define (#,make-n . args)
                 (let ((inst (apply #,raw-n args)))
                   (annotate-safety! inst 'thread-local)
                   inst))
               (define #,pred-n #,rawp-n)))))))

  (define-syntax defstruct/thread-safe
    (lambda (stx)
      (syntax-case stx ()
        ((_ sname (field ...))
         (let* ((sn     (syntax->datum #'sname))
                (make-n (datum->syntax #'sname (string->symbol (string-append "make-" (symbol->string sn)))))
                (pred-n (datum->syntax #'sname (string->symbol (string-append (symbol->string sn) "?"))))
                (raw-n  (datum->syntax #'sname (string->symbol (string-append "%tsraw-" (symbol->string sn)))))
                (rawp-n (datum->syntax #'sname (string->symbol (string-append "%tsrawp-" (symbol->string sn))))))
           #`(begin
               (define-record-type (sname #,raw-n #,rawp-n)
                 (fields (mutable field) ...))
               (define (#,make-n . args)
                 (let ((inst (apply #,raw-n args)))
                   (annotate-safety! inst 'thread-safe)
                   inst))
               (define #,pred-n #,rawp-n)))))))

  ;; ========== Step 46: Deadlock Detection ==========

  ;; Track mutex acquisition order per thread.
  ;; Maintain a directed graph: if T holds A then acquires B → edge A→B.
  ;; A cycle indicates a potential deadlock.

  (define *lock-graph*    (make-hashtable equal-hash equal?))
  (define *thread-holds*  (make-eq-hashtable))
  (define *lock-mutex*    (make-mutex))
  (define *mutex-id-seq*  0)
  (define *violations*    '())

  (define (make-tracked-mutex . name-args)
    (set! *mutex-id-seq* (+ *mutex-id-seq* 1))
    (let* ([name (if (null? name-args) *mutex-id-seq* (car name-args))]
           [m    (make-mutex)])
      (vector 'tracked-mutex *mutex-id-seq* name m)))

  (define (tracked-mutex? x)
    (and (vector? x) (= (vector-length x) 4) (eq? (vector-ref x 0) 'tracked-mutex)))

  (define (tmx-id   m) (vector-ref m 1))
  (define (tmx-name m) (vector-ref m 2))
  (define (tmx-raw  m) (vector-ref m 3))

  ;; Thread-local ID assignment
  (define *thread-id-counter* 0)
  (define *thread-id-mutex*   (make-mutex))
  (define *thread-id-param*   (make-thread-parameter 0))

  (define (current-thread-id)
    (when (= (*thread-id-param*) 0)
      (with-mutex *thread-id-mutex*
        (set! *thread-id-counter* (+ *thread-id-counter* 1))
        (*thread-id-param* *thread-id-counter*)))
    (*thread-id-param*))

  (define (tracked-lock! m)
    (with-mutex *lock-mutex*
      (let* ([tid  (current-thread-id)]
             [held (hashtable-ref *thread-holds* tid '())]
             [mid  (tmx-id m)])
        ;; Check for potential cycle BEFORE adding edges:
        ;; if mid can already reach any held mutex, adding held→mid creates a cycle.
        (when (any-path? mid held)
          (set! *violations*
            (cons (list 'lock-order-violation (tmx-name m) held)
                  *violations*)))
        ;; Add edges from each held mutex to this one (after cycle check)
        (for-each
          (lambda (held-id)
            (let ([edges (hashtable-ref *lock-graph* held-id '())])
              (unless (member mid edges)
                (hashtable-set! *lock-graph* held-id (cons mid edges)))))
          held)
        (hashtable-set! *thread-holds* tid (cons mid held))))
    (mutex-acquire (tmx-raw m)))

  (define (any-path? start targets)
    ;; BFS: is any element of targets reachable FROM start via lock-graph?
    ;; Detects if adding edges held→mid would create a cycle (mid→held path exists).
    (let loop ([queue (list start)] [visited '()])
      (if (null? queue)
        #f
        (let ([node (car queue)])
          (cond
            [(member node targets) #t]
            [(member node visited) (loop (cdr queue) visited)]
            [else
             (let ([neighbors (hashtable-ref *lock-graph* node '())])
               (loop (append (cdr queue) neighbors)
                     (cons node visited)))])))))

  (define (tracked-unlock! m)
    (mutex-release (tmx-raw m))
    (with-mutex *lock-mutex*
      (let* ([tid  (current-thread-id)]
             [held (hashtable-ref *thread-holds* tid '())]
             [mid  (tmx-id m)])
        (hashtable-set! *thread-holds* tid
          (filter (lambda (id) (not (= id mid))) held)))))

  (define-syntax with-tracked-mutex
    (syntax-rules ()
      [(_ m body ...)
       (dynamic-wind
         (lambda () (tracked-lock! m))
         (lambda () body ...)
         (lambda () (tracked-unlock! m)))]))

  (define (deadlock-check!)
    ;; Check lock-order graph for cycles using DFS.
    ;; Returns list of (node . path) for detected cycles.
    (let ([all-nodes (let-values ([(ks _) (hashtable-entries *lock-graph*)])
                       (vector->list ks))]
          [cycles '()])
      (for-each
        (lambda (start)
          (let dfs ([node start] [path '()] [visited '()])
            (cond
              [(member node path)
               (set! cycles (cons (cons node (reverse path)) cycles))]
              [(member node visited) (void)]
              [else
               (for-each
                 (lambda (next)
                   (dfs next (cons node path) (cons node visited)))
                 (hashtable-ref *lock-graph* node '()))])))
        all-nodes)
      cycles))

  (define (lock-order-violations)
    *violations*)

  (define (reset-lock-tracking!)
    (with-mutex *lock-mutex*
      (let-values ([(ks _) (hashtable-entries *lock-graph*)])
        (vector-for-each (lambda (k) (hashtable-delete! *lock-graph* k)) ks))
      (let-values ([(ks _) (hashtable-entries *thread-holds*)])
        (vector-for-each (lambda (k) (hashtable-delete! *thread-holds* k)) ks))
      (set! *violations* '())))

  ;; ========== Step 47: Resource Leak Detection ==========

  (define *resource-table*  (make-eq-hashtable))
  (define *resource-mutex*  (make-mutex))
  (define *resource-id-seq* 0)

  (define (register-resource! type . desc-args)
    ;; Register a new open resource. Returns a resource-id.
    (set! *resource-id-seq* (+ *resource-id-seq* 1))
    (let* ([rid  *resource-id-seq*]
           [desc (if (null? desc-args) "" (car desc-args))]
           [tid  (current-thread-id)])
      (with-mutex *resource-mutex*
        (let ([task-res (hashtable-ref *resource-table* tid '())])
          (hashtable-set! *resource-table* tid
            (cons (list rid type desc) task-res))))
      rid))

  (define (close-resource! rid)
    (let ([tid (current-thread-id)])
      (with-mutex *resource-mutex*
        (let ([task-res (hashtable-ref *resource-table* tid '())])
          (hashtable-set! *resource-table* tid
            (filter (lambda (r) (not (= (car r) rid))) task-res))))))

  (define (task-resources)
    (let ([tid (current-thread-id)])
      (hashtable-ref *resource-table* tid '())))

  (define (open-resource-count)
    (length (task-resources)))

  (define (check-resource-leaks!)
    (with-mutex *resource-mutex*
      (let-values ([(tids res-lists) (hashtable-entries *resource-table*)])
        (let ([leaks '()])
          (vector-for-each
            (lambda (tid res-list)
              (unless (null? res-list)
                (set! leaks (cons (cons tid res-list) leaks))))
            tids res-lists)
          leaks))))

  (define (with-resource-tracking thunk)
    (let* ([tid    (current-thread-id)]
           [result (thunk)]
           [after  (task-resources)])
      (values result after)))

  ) ;; end library
