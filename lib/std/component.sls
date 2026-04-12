#!chezscheme
;;; (std component) — Stuart Sierra-style Component Lifecycle
;;;
;;; Composable systems of stateful services with dependency ordering.
;;;
;;; Each component is a record implementing start/stop via a registry
;;; of lifecycle handlers. Systems are maps of named components with
;;; declared dependencies, started/stopped in topological order.
;;;
;;; API:
;;;   (component name . key-vals) → component record
;;;   (system-map . name-component-pairs) → system
;;;   (system-using sys dep-map) → system with dependency declarations
;;;   (start sys) → started system
;;;   (stop sys) → stopped system
;;;   (defcomponent name fields start-body stop-body) → macro
;;;
;;; Example:
;;;   (defcomponent database (host port conn)
;;;     :start (lambda (this)
;;;              (database-conn-set! this (connect (database-host this)))
;;;              this)
;;;     :stop  (lambda (this)
;;;              (disconnect (database-conn this))
;;;              (database-conn-set! this #f)
;;;              this))

(library (std component)
  (export
    ;; Core types
    component component? component-name component-state
    component-config component-deps

    ;; Lifecycle protocol
    register-lifecycle! start-component stop-component

    ;; System operations
    system-map system-using start stop

    ;; Status
    component-started? system-started?)

  (import (except (chezscheme)
            make-hash-table hash-table? iota 1+ 1-)
          (jerboa runtime))

  ;; =========================================================================
  ;; Component record
  ;; =========================================================================

  (define-record-type component-rec
    (nongenerative std-component-rec)
    (fields name
            (mutable state)    ;; 'stopped or 'started
            (mutable config)   ;; hashtable of key-value config
            (mutable deps)     ;; alist of (dep-key . resolved-component)
            (mutable data))    ;; user data (the actual service state)
    (sealed #t))

  ;; =========================================================================
  ;; Lifecycle registry
  ;;
  ;; Maps component name → (start-fn . stop-fn)
  ;; start-fn: (component deps-map) → component (with data set)
  ;; stop-fn:  (component) → component (with data cleared)
  ;; =========================================================================

  (define *lifecycle-registry*
    (make-hashtable symbol-hash eq?))

  (define (register-lifecycle! name start-fn stop-fn)
    (hashtable-set! *lifecycle-registry* name (cons start-fn stop-fn)))

  ;; =========================================================================
  ;; Component constructor
  ;; =========================================================================

  (define (component name . kv-pairs)
    (let ([cfg (make-hashtable equal-hash equal?)])
      (let loop ([rest kv-pairs])
        (cond
          [(null? rest) (void)]
          [(null? (cdr rest)) (error 'component "odd number of key-value args")]
          [else
           (hashtable-set! cfg (car rest) (cadr rest))
           (loop (cddr rest))]))
      (make-component-rec name 'stopped cfg '() #f)))

  (define (component? x) (component-rec? x))
  (define (component-name c) (component-rec-name c))
  (define (component-state c) (component-rec-state c))
  (define (component-config c) (component-rec-config c))
  (define (component-deps c) (component-rec-deps c))
  (define (component-started? c) (eq? (component-rec-state c) 'started))

  ;; =========================================================================
  ;; Start/stop individual components
  ;; =========================================================================

  (define (start-component c)
    (if (component-started? c) c
      (let ([entry (hashtable-ref *lifecycle-registry*
                                  (component-rec-name c) #f)])
        (if entry
          (let ([started ((car entry) c)])
            (component-rec-state-set! started 'started)
            started)
          (begin
            (component-rec-state-set! c 'started)
            c)))))

  (define (stop-component c)
    (if (not (component-started? c)) c
      (let ([entry (hashtable-ref *lifecycle-registry*
                                  (component-rec-name c) #f)])
        (if entry
          (let ([stopped ((cdr entry) c)])
            (component-rec-state-set! stopped 'stopped)
            stopped)
          (begin
            (component-rec-state-set! c 'stopped)
            c)))))

  ;; =========================================================================
  ;; System — a named collection of components with dependencies
  ;; =========================================================================

  ;; A system is a hashtable: name → component
  ;; Plus a dependency map: name → alist of (dep-key . provider-name)

  (define-record-type system-rec
    (nongenerative std-component-system)
    (fields components    ;; hashtable: symbol → component
            dep-map)      ;; hashtable: symbol → alist of (key . provider)
    (sealed #t))

  (define (system-map . pairs)
    (let ([ht (make-hashtable symbol-hash eq?)])
      (let loop ([rest pairs])
        (cond
          [(null? rest) (void)]
          [(null? (cdr rest)) (error 'system-map "odd number of name-component pairs")]
          [else
           (hashtable-set! ht (car rest) (cadr rest))
           (loop (cddr rest))]))
      (make-system-rec ht (make-hashtable symbol-hash eq?))))

  ;; system-using — declare dependencies
  ;; dep-map: alist of (component-name . deps)
  ;; where deps is either:
  ;;   - a list of symbols (dep names = provider names)
  ;;   - an alist of (dep-key . provider-name)
  (define (system-using sys deps)
    (let ([dm (system-rec-dep-map sys)])
      (for-each
        (lambda (entry)
          (let ([name (car entry)]
                [dep-spec (cdr entry)])
            (hashtable-set! dm name
              (if (and (pair? dep-spec) (pair? (car dep-spec)))
                ;; alist form: ((key . provider) ...)
                dep-spec
                ;; list form: (dep1 dep2 ...) — key = provider name
                (map (lambda (d) (cons d d))
                     (if (list? dep-spec) dep-spec (list dep-spec)))))))
        deps))
    sys)

  ;; =========================================================================
  ;; Topological sort for dependency ordering
  ;; =========================================================================

  (define (topo-sort components dep-map)
    (let ([visited (make-hashtable symbol-hash eq?)]
          [result '()])
      (define (visit name)
        (unless (hashtable-ref visited name #f)
          (hashtable-set! visited name #t)
          (let ([deps (hashtable-ref dep-map name '())])
            (for-each (lambda (dep-pair)
                        (visit (cdr dep-pair)))
                      deps))
          (set! result (cons name result))))
      (let-values ([(keys vals) (hashtable-entries components)])
        (vector-for-each visit keys))
      (reverse result)))

  ;; =========================================================================
  ;; System start/stop
  ;; =========================================================================

  (define (start sys)
    (if (component? sys)
      (start-component sys)
      (let* ([components (system-rec-components sys)]
             [dep-map (system-rec-dep-map sys)]
             [order (topo-sort components dep-map)])
        (for-each
          (lambda (name)
            (let ([c (hashtable-ref components name #f)])
              (when c
                ;; Inject dependencies
                (let ([deps (hashtable-ref dep-map name '())])
                  (component-rec-deps-set! c
                    (map (lambda (dep-pair)
                           (cons (car dep-pair)
                                 (hashtable-ref components (cdr dep-pair) #f)))
                         deps)))
                ;; Start the component
                (let ([started (start-component c)])
                  (hashtable-set! components name started)))))
          order)
        sys)))

  (define (stop sys)
    (if (component? sys)
      (stop-component sys)
      (let* ([components (system-rec-components sys)]
             [dep-map (system-rec-dep-map sys)]
             [order (reverse (topo-sort components dep-map))])
        (for-each
          (lambda (name)
            (let ([c (hashtable-ref components name #f)])
              (when c
                (let ([stopped (stop-component c)])
                  (hashtable-set! components name stopped)))))
          order)
        sys)))

  (define (system-started? sys)
    (let ([components (system-rec-components sys)])
      (let-values ([(keys vals) (hashtable-entries components)])
        (let loop ([i 0])
          (if (= i (vector-length vals)) #t
            (if (component-started? (vector-ref vals i))
              (loop (+ i 1))
              #f))))))

) ;; end library
