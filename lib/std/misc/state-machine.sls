#!chezscheme
;;; (std misc state-machine) -- Finite State Machine
;;;
;;; Declarative FSM with states, transitions, guards, and actions.
;;;
;;; Usage:
;;;   (import (std misc state-machine))
;;;   (define traffic-light
;;;     (make-state-machine 'red
;;;       `((red    (timer)   green  ,void)
;;;         (green  (timer)   yellow ,void)
;;;         (yellow (timer)   red    ,void))))
;;;
;;;   (sm-state traffic-light)          ; => red
;;;   (sm-send! traffic-light 'timer)   ; transitions to green
;;;   (sm-state traffic-light)          ; => green

(library (std misc state-machine)
  (export
    make-state-machine
    state-machine?
    sm-state
    sm-send!
    sm-can-send?
    sm-transitions
    sm-history
    sm-on-transition!
    sm-reset!)

  (import (chezscheme))

  ;; Transition: (from-state (event ...) to-state action-or-#f guard-or-#f)
  ;; Simplified: (from event to action)

  (define-record-type state-machine-rec
    (fields (immutable initial-state)
            (immutable transitions)    ;; list of (from event to action guard)
            (mutable current-state)
            (mutable history-log)       ;; list of (from event to timestamp)
            (mutable on-transition-cb)) ;; callback or #f
    (protocol (lambda (new)
      (lambda (initial transitions)
        (new initial (normalize-transitions transitions) initial '() #f)))))

  (define (normalize-transitions txns)
    ;; Accept: (from (event) to action) or (from (event) to action guard)
    ;; or simplified: (from event to action)
    (map (lambda (t)
           (cond
             [(= (length t) 4)
              ;; (from event to action)
              (let ([from (car t)]
                    [event (cadr t)]
                    [to (caddr t)]
                    [action (cadddr t)])
                (list from
                      (if (list? event) event (list event))
                      to action #f))]
             [(= (length t) 5)
              ;; (from event to action guard)
              (let ([from (car t)]
                    [event (cadr t)]
                    [to (caddr t)]
                    [action (cadddr t)]
                    [guard (car (cddddr t))])
                (list from
                      (if (list? event) event (list event))
                      to action guard))]
             [else (error 'make-state-machine "invalid transition" t)]))
         txns))

  (define (make-state-machine initial transitions)
    (make-state-machine-rec initial transitions))

  (define (state-machine? x) (state-machine-rec? x))

  (define (sm-state sm) (state-machine-rec-current-state sm))

  (define (sm-send! sm event . args)
    ;; Send an event, trigger transition if valid
    (let ([current (state-machine-rec-current-state sm)])
      (let loop ([txns (state-machine-rec-transitions sm)])
        (cond
          [(null? txns)
           (error 'sm-send! "no valid transition"
                  `(state: ,current event: ,event))]
          [(and (eq? (caar txns) current)
                (memq event (cadar txns)))
           (let* ([txn (car txns)]
                  [to (caddr txn)]
                  [action (cadddr txn)]
                  [guard (car (cddddr txn))])
             ;; Check guard
             (if (and guard (not (apply guard current event args)))
               (loop (cdr txns))  ;; guard failed, try next
               (begin
                 ;; Execute action
                 (when action (apply action args))
                 ;; Update state
                 (state-machine-rec-current-state-set! sm to)
                 ;; Log transition
                 (state-machine-rec-history-log-set! sm
                   (cons (list current event to)
                         (state-machine-rec-history-log sm)))
                 ;; Callback
                 (when (state-machine-rec-on-transition-cb sm)
                   ((state-machine-rec-on-transition-cb sm) current event to))
                 to)))]
          [else (loop (cdr txns))]))))

  (define (sm-can-send? sm event)
    ;; Check if event can trigger a transition from current state
    (let ([current (state-machine-rec-current-state sm)])
      (let loop ([txns (state-machine-rec-transitions sm)])
        (cond
          [(null? txns) #f]
          [(and (eq? (caar txns) current)
                (memq event (cadar txns)))
           #t]
          [else (loop (cdr txns))]))))

  (define (sm-transitions sm)
    ;; Return valid transitions from current state
    (let ([current (state-machine-rec-current-state sm)])
      (filter (lambda (t) (eq? (car t) current))
              (state-machine-rec-transitions sm))))

  (define (sm-history sm)
    ;; Return transition history (newest first)
    (state-machine-rec-history-log sm))

  (define (sm-on-transition! sm callback)
    ;; Set callback: (lambda (from event to) ...)
    (state-machine-rec-on-transition-cb-set! sm callback))

  (define (sm-reset! sm)
    ;; Reset to initial state
    (state-machine-rec-current-state-set! sm
      (state-machine-rec-initial-state sm))
    (state-machine-rec-history-log-set! sm '()))

) ;; end library
