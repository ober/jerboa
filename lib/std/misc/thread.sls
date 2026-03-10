#!chezscheme
;;; thread.sls -- Gambit thread API → Chez Scheme threads
;;;
;;; Gambit's thread model:
;;;   (make-thread thunk [name]) → thread object (not started)
;;;   (thread-start! thread) → starts the thread, returns thread
;;;   (thread-join! thread) → waits for thread, returns result
;;;   (thread-yield!) → yield current thread
;;;   (thread-sleep! timeout) → sleep
;;;   (current-thread) → current thread object
;;;
;;; Chez Scheme's thread model:
;;;   (fork-thread thunk) → starts immediately, returns thread-id
;;;   No explicit join in v9; thread-join in v10+
;;;   (get-thread-id) → current thread id (integer)
;;;   Mutex: make-mutex, mutex-acquire, mutex-release
;;;   Condition: make-condition, condition-wait, condition-signal, condition-broadcast

(library (std misc thread)
  (export
    ;; Thread operations
    make-thread thread-start! thread-join!
    thread-yield! thread-sleep!
    current-thread thread-name
    thread? thread-specific thread-specific-set!

    ;; Mutex operations (Gambit API names)
    make-mutex make-mutex-gambit mutex? mutex-name
    mutex-lock! mutex-unlock!
    mutex-specific mutex-specific-set!

    ;; Condition variable operations (Gambit API names)
    make-condition-variable condition-variable?
    condition-variable-signal! condition-variable-broadcast!
    condition-variable-specific condition-variable-specific-set!

    ;; Mailbox (Gambit thread mailboxes)
    thread-send thread-receive thread-mailbox-next
    )

  (import (except (chezscheme)
            thread?                    ;; we define our own thread? for gerbil-thread
            make-mutex mutex? mutex-name ;; we wrap with our own types
            )
          (rename (only (chezscheme) make-mutex mutex? mutex-name)
            (make-mutex chez:make-mutex)
            (mutex? chez:mutex?)
            (mutex-name chez:mutex-name)))

  ;;;; Thread wrapper
  ;;;; Gambit threads are objects you create, then start.
  ;;;; Chez threads start immediately on fork-thread.
  ;;;; We wrap to provide the Gambit API.

  (define-record-type gerbil-thread
    (fields
      thunk                    ;; the procedure to run
      (mutable name-val)       ;; thread name (symbol or string)
      (mutable chez-tid)       ;; Chez thread id (set on start!)
      (mutable result)         ;; result value (set on completion)
      (mutable exception)      ;; exception (set on failure)
      (mutable done?)          ;; #t when finished
      (mutable specific)       ;; thread-specific storage
      done-mutex               ;; mutex for join synchronization
      done-cond                ;; condition for join notification
      (mutable mailbox)        ;; list of pending messages
      mailbox-mutex            ;; protects mailbox
      mailbox-cond)            ;; signal when message arrives
    (sealed #t))

  (define (make-thread thunk . name)
    (make-gerbil-thread
      thunk
      (if (null? name) 'anonymous (car name))
      #f                       ;; chez-tid (not started)
      (void)                   ;; result
      #f                       ;; exception
      #f                       ;; done?
      (void)                   ;; specific
      (chez:make-mutex)
      (make-condition)
      '()                      ;; mailbox
      (chez:make-mutex)
      (make-condition)))

  (define (thread? x) (gerbil-thread? x))
  (define (thread-name t) (gerbil-thread-name-val t))
  (define (thread-specific t) (gerbil-thread-specific t))
  (define (thread-specific-set! t v) (gerbil-thread-specific-set! t v))

  ;; Thread-local storage for current gerbil-thread (no global lock!)
  ;; make-thread-parameter is Chez's SMP-safe thread-local mechanism.
  (define main-thread
    (let ([t (make-thread (lambda () (void)) 'main)])
      (gerbil-thread-chez-tid-set! t (get-thread-id))
      t))

  (define current-gerbil-thread (make-thread-parameter main-thread))

  (define (current-thread)
    (current-gerbil-thread))

  (define (thread-start! t)
    (let ([thunk (gerbil-thread-thunk t)])
      (fork-thread
        (lambda ()
          ;; Set thread-local identity (no global lock needed)
          (gerbil-thread-chez-tid-set! t (get-thread-id))
          (current-gerbil-thread t)
          ;; Run the thunk
          (guard (exn
                  [#t
                   (gerbil-thread-exception-set! t exn)
                   (gerbil-thread-done?-set! t #t)
                   (mutex-acquire (gerbil-thread-done-mutex t))
                   (condition-broadcast (gerbil-thread-done-cond t))
                   (mutex-release (gerbil-thread-done-mutex t))])
            (let ([result (thunk)])
              (gerbil-thread-result-set! t result)
              (gerbil-thread-done?-set! t #t)
              (mutex-acquire (gerbil-thread-done-mutex t))
              (condition-broadcast (gerbil-thread-done-cond t))
              (mutex-release (gerbil-thread-done-mutex t)))))))
    t)

  (define (thread-join! t . timeout)
    (let ([m (gerbil-thread-done-mutex t)]
          [c (gerbil-thread-done-cond t)])
      (mutex-acquire m)
      (let loop ()
        (cond
          [(gerbil-thread-done? t)
           (mutex-release m)
           (if (gerbil-thread-exception t)
               (raise (gerbil-thread-exception t))
               (gerbil-thread-result t))]
          [else
           (if (and (not (null? timeout)) (car timeout))
               ;; Timed wait
               (let ([ns (inexact->exact
                           (floor (* (car timeout) 1000000000)))])
                 (let ([abstime (make-time 'time-duration ns 0)])
                   (condition-wait c m abstime))
                 (mutex-release m)
                 (if (gerbil-thread-done? t)
                     (if (gerbil-thread-exception t)
                         (raise (gerbil-thread-exception t))
                         (gerbil-thread-result t))
                     (error 'thread-join! "timeout")))
               ;; Indefinite wait
               (begin
                 (condition-wait c m)
                 (loop)))]))))

  (define (thread-yield!)
    ;; Chez doesn't have an explicit yield; sleep briefly
    (sleep (make-time 'time-duration 0 0)))

  (define (thread-sleep! seconds)
    (let* ([secs (exact (floor seconds))]
           [nsecs (exact (floor (* (- seconds secs) 1000000000)))])
      (sleep (make-time 'time-duration nsecs secs))))

  ;;;; Mutex wrapper (Gambit names → Chez)

  (define-record-type gerbil-mutex
    (fields
      chez-mutex
      (mutable name-val)
      (mutable specific))
    (sealed #t))

  (define make-mutex-gambit
    (case-lambda
      [() (make-gerbil-mutex (chez:make-mutex) 'anonymous (void))]
      [(name) (make-gerbil-mutex (chez:make-mutex) name (void))]))

  ;; Gambit-compatible make-mutex: accepts optional string/symbol name
  (define make-mutex make-mutex-gambit)

  (define (mutex? x) (gerbil-mutex? x))
  (define (mutex-name m) (gerbil-mutex-name-val m))
  (define (mutex-specific m) (gerbil-mutex-specific m))
  (define (mutex-specific-set! m v) (gerbil-mutex-specific-set! m v))

  (define mutex-lock!
    (case-lambda
      [(m) (mutex-acquire (gerbil-mutex-chez-mutex m))]
      [(m timeout)
       (if timeout
           (mutex-acquire (gerbil-mutex-chez-mutex m))  ;; Chez doesn't have timed acquire in v9
           (mutex-acquire (gerbil-mutex-chez-mutex m)))]
      [(m timeout thread)
       (mutex-acquire (gerbil-mutex-chez-mutex m))]))

  (define mutex-unlock!
    (case-lambda
      [(m) (mutex-release (gerbil-mutex-chez-mutex m))]
      [(m condvar)
       ;; Gambit: unlock mutex and wait on condition variable atomically
       (let ([cv (gerbil-condvar-chez-cond condvar)]
             [mx (gerbil-mutex-chez-mutex m)])
         (condition-wait cv mx)
         (mutex-release mx))]
      [(m condvar timeout)
       (let ([cv (gerbil-condvar-chez-cond condvar)]
             [mx (gerbil-mutex-chez-mutex m)])
         (if timeout
             (let* ([secs (exact (floor timeout))]
                    [nsecs (exact (floor (* (- timeout secs) 1000000000)))])
               (condition-wait cv mx (make-time 'time-duration nsecs secs)))
             (condition-wait cv mx))
         (mutex-release mx))]))

  ;;;; Condition variable wrapper

  (define-record-type gerbil-condvar
    (fields
      chez-cond
      (mutable name-val)
      (mutable specific))
    (sealed #t))

  (define make-condition-variable
    (case-lambda
      [() (make-gerbil-condvar (make-condition) 'anonymous (void))]
      [(name) (make-gerbil-condvar (make-condition) name (void))]))

  (define (condition-variable? x) (gerbil-condvar? x))
  (define (condition-variable-specific cv) (gerbil-condvar-specific cv))
  (define (condition-variable-specific-set! cv v) (gerbil-condvar-specific-set! cv v))

  (define (condition-variable-signal! cv)
    (condition-signal (gerbil-condvar-chez-cond cv)))

  (define (condition-variable-broadcast! cv)
    (condition-broadcast (gerbil-condvar-chez-cond cv)))

  ;;;; Thread mailbox (Gambit-style message passing)

  (define (thread-send t msg)
    (let ([mx (gerbil-thread-mailbox-mutex t)]
          [cv (gerbil-thread-mailbox-cond t)])
      (mutex-acquire mx)
      (gerbil-thread-mailbox-set! t
        (append (gerbil-thread-mailbox t) (list msg)))
      (condition-signal cv)
      (mutex-release mx)))

  (define thread-receive
    (case-lambda
      [() (thread-receive-impl (current-thread) #f)]
      [(timeout) (thread-receive-impl (current-thread) timeout)]))

  (define (thread-receive-impl t timeout)
    (let ([mx (gerbil-thread-mailbox-mutex t)]
          [cv (gerbil-thread-mailbox-cond t)])
      (mutex-acquire mx)
      (let loop ()
        (let ([mb (gerbil-thread-mailbox t)])
          (cond
            [(pair? mb)
             (let ([msg (car mb)])
               (gerbil-thread-mailbox-set! t (cdr mb))
               (mutex-release mx)
               msg)]
            [timeout
             (let* ([secs (exact (floor timeout))]
                    [nsecs (exact (floor (* (- timeout secs) 1000000000)))])
               (condition-wait cv mx (make-time 'time-duration nsecs secs)))
             (let ([mb (gerbil-thread-mailbox t)])
               (cond
                 [(pair? mb)
                  (let ([msg (car mb)])
                    (gerbil-thread-mailbox-set! t (cdr mb))
                    (mutex-release mx)
                    msg)]
                 [else
                  (mutex-release mx)
                  (error 'thread-receive "timeout")]))]
            [else
             (condition-wait cv mx)
             (loop)])))))

  (define (thread-mailbox-next t . timeout)
    (let ([mx (gerbil-thread-mailbox-mutex t)]
          [cv (gerbil-thread-mailbox-cond t)])
      (mutex-acquire mx)
      (let ([mb (gerbil-thread-mailbox t)])
        (cond
          [(pair? mb)
           (mutex-release mx)
           (car mb)]
          [else
           (mutex-release mx)
           #f]))))

  ) ;; end library
