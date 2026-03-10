#!chezscheme
;;; (std actor registry) — Named actor registry
;;;
;;; The registry is itself an actor. Names map to actor-refs.
;;; When a registered actor dies, its name is auto-removed via a monitor.

(library (std actor registry)
  (export
    start-registry!
    register!           ;; (register! name actor-ref) → 'ok | 'already-registered
    unregister!         ;; (unregister! name) → 'ok
    whereis             ;; (whereis name) → actor-ref or #f
    registered-names    ;; → list of registered names
    registry-actor      ;; → the registry actor-ref itself
  )
  (import (chezscheme)
          (only (jerboa core) match)
          (std actor core)
          (std actor protocol))

  (define *registry-actor* #f)
  (define (registry-actor) *registry-actor*)

  ;; -------- Registry behavior --------

  (define (make-registry-behavior)
    (let ([table (make-eq-hashtable)])
      (lambda (msg)
        (with-ask-context msg
          (lambda (actual)
            (match actual
              [('register name ref)
               (if (hashtable-ref table name #f)
                 (reply 'already-registered)
                 (begin
                   ;; Monitor the actor: auto-unregister on death
                   (actor-ref-monitors-set! ref
                     (cons (cons (self) name)
                           (actor-ref-monitors ref)))
                   (hashtable-set! table name ref)
                   (reply 'ok)))]

              [('unregister name)
               (let ([ref (hashtable-ref table name #f)])
                 (when ref
                   ;; Remove our monitor from the actor's list
                   (when (actor-alive? ref)
                     (actor-ref-monitors-set! ref
                       (filter (lambda (mon)
                                 (not (and (eq? (car mon) (self))
                                           (eq? (cdr mon) name))))
                               (actor-ref-monitors ref)))))
               (hashtable-delete! table name)
               (reply 'ok))]

              [('whereis name)
               (reply (hashtable-ref table name #f))]

              [('names)
               (reply (vector->list (hashtable-keys table)))]

              ;; Actor died — auto-unregister its name (from monitor DOWN)
              [('DOWN name dead-id reason)
               (hashtable-delete! table name)]

              [_ (void)]))))))

  ;; -------- Public API --------

  (define (start-registry!)
    (set! *registry-actor*
          (spawn-actor (make-registry-behavior) 'registry)))

  (define (register! name actor-ref)
    (ask-sync *registry-actor* (list 'register name actor-ref)))

  (define (unregister! name)
    (ask-sync *registry-actor* (list 'unregister name)))

  (define (whereis name)
    (ask-sync *registry-actor* (list 'whereis name)))

  (define (registered-names)
    (ask-sync *registry-actor* '(names)))

  ) ;; end library
