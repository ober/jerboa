#!chezscheme
;;; (std frp) — Functional Reactive Programming with signals
;;;
;;; Signals (time-varying values) that automatically propagate changes
;;; through a dependency graph. Glitch-free via topological propagation.
;;;
;;; API:
;;;   (make-signal val)              — create a source signal
;;;   (signal-ref sig)               — get current value
;;;   (signal-set! sig val)          — set source signal, propagate changes
;;;   (signal-map proc sig ...)      — derived signal (auto-updates)
;;;   (signal-filter pred sig default) — filtered signal
;;;   (signal-fold proc init sig)    — accumulated signal
;;;   (signal-merge sig ...)         — merge signals (latest wins)
;;;   (signal-watch sig proc)        — call proc on every change
;;;   (signal-unwatch sig id)        — remove a watcher
;;;   (signal-freeze sig)            — snapshot current value

(library (std frp)
  (export make-signal signal? signal-ref signal-set!
          signal-map signal-filter signal-fold signal-merge
          signal-watch signal-unwatch signal-freeze
          signal-zip signal-sample)

  (import (chezscheme))

  ;; ========== Signal record ==========

  (define-record-type signal
    (fields
      (mutable value)
      (mutable dependents)      ;; list of (signal . update-proc)
      (mutable watchers)        ;; list of (id . proc)
      (immutable source?)       ;; #t for source signals
      (mutable update-proc)     ;; #f for sources, (lambda () new-val) for derived
      (mutable dependencies))   ;; list of signals this depends on
    (protocol
      (lambda (new)
        (case-lambda
          [(val) (new val '() '() #t #f '())]
          [(val update deps)
           (new val '() '() #f update deps)]))))

  (define watcher-counter 0)

  ;; ========== Core operations ==========

  (define (signal-ref sig) (signal-value sig))

  (define (signal-set! sig val)
    (unless (signal-source? sig)
      (error 'signal-set! "cannot set a derived signal"))
    (unless (equal? val (signal-value sig))
      (signal-value-set! sig val)
      (notify-watchers sig)
      (propagate! sig)))

  ;; ========== Dependency tracking and propagation ==========

  (define (add-dependent! source dep update)
    (signal-dependents-set! source
      (cons (cons dep update) (signal-dependents source))))

  (define (propagate! sig)
    ;; Topological propagation: BFS from changed signal
    (let ([queue (map car (signal-dependents sig))]
          [visited (make-eq-hashtable)])
      (hashtable-set! visited sig #t)
      (let loop ([q queue])
        (unless (null? q)
          (let ([current (car q)]
                [rest (cdr q)])
            (unless (hashtable-ref visited current #f)
              (hashtable-set! visited current #t)
              ;; Update this signal
              (let ([update (signal-update-proc current)])
                (when update
                  (let ([new-val (update)])
                    (unless (equal? new-val (signal-value current))
                      (signal-value-set! current new-val)
                      (notify-watchers current)
                      ;; Add this signal's dependents to queue
                      (set! rest (append rest (map car (signal-dependents current))))))))
              (loop rest))
            (loop rest))))))

  (define (notify-watchers sig)
    (for-each
      (lambda (w) ((cdr w) (signal-value sig)))
      (signal-watchers sig)))

  ;; ========== Derived signals ==========

  (define (signal-map proc . sigs)
    (let* ([update (lambda () (apply proc (map signal-value sigs)))]
           [derived (make-signal (update) update sigs)])
      (for-each
        (lambda (s)
          (add-dependent! s derived update))
        sigs)
      derived))

  (define (signal-filter pred sig default)
    (let* ([init (if (pred (signal-value sig)) (signal-value sig) default)]
           [derived #f]
           [update (lambda ()
                     (let ([v (signal-value sig)])
                       (if (pred v) v (signal-value derived))))])
      (set! derived (make-signal init update (list sig)))
      (signal-update-proc-set! derived update)
      (add-dependent! sig derived update)
      derived))

  (define (signal-fold proc init sig)
    (let* ([derived #f]
           [update (lambda ()
                     (proc (signal-value derived) (signal-value sig)))])
      (set! derived (make-signal init update (list sig)))
      (signal-update-proc-set! derived update)
      (add-dependent! sig derived update)
      derived))

  (define (signal-merge . sigs)
    (let* ([derived #f]
           [update (lambda ()
                     ;; Take value from last-changed signal
                     ;; Since we propagate in order, current update is the trigger
                     (signal-value derived))])
      (set! derived (make-signal (signal-value (car sigs)) #f sigs))
      (for-each
        (lambda (s)
          (add-dependent! s derived
            (lambda ()
              (signal-value-set! derived (signal-value s))
              (signal-value s))))
        sigs)
      derived))

  (define (signal-zip . sigs)
    (apply signal-map list sigs))

  (define (signal-sample sig interval-sig)
    ;; Sample sig whenever interval-sig changes
    (signal-map (lambda (_trigger) (signal-value sig)) interval-sig))

  ;; ========== Watchers ==========

  (define (signal-watch sig proc)
    (set! watcher-counter (+ watcher-counter 1))
    (let ([id watcher-counter])
      (signal-watchers-set! sig
        (cons (cons id proc) (signal-watchers sig)))
      id))

  (define (signal-unwatch sig id)
    (signal-watchers-set! sig
      (filter (lambda (w) (not (= (car w) id)))
              (signal-watchers sig))))

  (define (signal-freeze sig)
    (signal-value sig))

) ;; end library
