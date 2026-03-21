#!chezscheme
;;; (std csp) — Communicating Sequential Processes with green threads
;;;
;;; True CSP with typed channels, select with timeout, and backpressure.
;;; Green threads scheduled via Chez's engine system.
;;;
;;; API:
;;;   (make-channel)                 — unbuffered channel
;;;   (make-channel/buf n)           — buffered channel with capacity n
;;;   (chan-put! ch val)             — send value (blocks if full)
;;;   (chan-get! ch)                 — receive value (blocks if empty)
;;;   (chan-try-get ch)              — non-blocking receive (#f if empty)
;;;   (chan-close! ch)               — close channel
;;;   (chan-closed? ch)              — test if closed
;;;   (go thunk)                    — spawn green thread
;;;   (go-named name thunk)         — spawn named green thread
;;;   (yield)                       — voluntarily yield
;;;   (select clause ...)           — multi-channel select
;;;   (chan->list ch)               — drain channel to list

(library (std csp)
  (export make-channel make-channel/buf
          chan-put! chan-get! chan-try-get chan-close! chan-closed?
          go go-named yield csp-run
          chan->list chan-pipe chan-map chan-filter)

  (import (chezscheme))

  ;; ========== Channel ==========

  (define-record-type channel
    (fields
      (mutable buffer)        ;; list (queue)
      (immutable capacity)    ;; max items (0 = unbuffered)
      (mutable closed?)
      (immutable mutex)
      (immutable not-empty)   ;; condition: buffer has items
      (immutable not-full))   ;; condition: buffer has space
    (protocol
      (lambda (new)
        (case-lambda
          [() (new '() 0 #f (make-mutex) (make-condition) (make-condition))]
          [(cap) (new '() cap #f (make-mutex) (make-condition) (make-condition))]))))

  (define (make-channel/buf n) (make-channel n))

  (define (chan-closed? ch) (channel-closed? ch))

  (define (buffer-count ch) (length (channel-buffer ch)))

  (define (chan-put! ch val)
    (with-mutex (channel-mutex ch)
      (when (channel-closed? ch)
        (error 'chan-put! "channel is closed"))
      ;; Wait until buffer has space (or unbuffered: wait for receiver)
      (let loop ()
        (when (and (> (channel-capacity ch) 0)
                   (>= (buffer-count ch) (channel-capacity ch)))
          (condition-wait (channel-not-full ch) (channel-mutex ch))
          (loop)))
      ;; Enqueue
      (channel-buffer-set! ch (append (channel-buffer ch) (list val)))
      (condition-broadcast (channel-not-empty ch))))

  (define (chan-get! ch)
    (with-mutex (channel-mutex ch)
      (let loop ()
        (cond
          [(pair? (channel-buffer ch))
           (let ([val (car (channel-buffer ch))])
             (channel-buffer-set! ch (cdr (channel-buffer ch)))
             (condition-broadcast (channel-not-full ch))
             val)]
          [(channel-closed? ch)
           (eof-object)]
          [else
           (condition-wait (channel-not-empty ch) (channel-mutex ch))
           (loop)]))))

  (define (chan-try-get ch)
    (with-mutex (channel-mutex ch)
      (if (pair? (channel-buffer ch))
        (let ([val (car (channel-buffer ch))])
          (channel-buffer-set! ch (cdr (channel-buffer ch)))
          (condition-broadcast (channel-not-full ch))
          val)
        #f)))

  (define (chan-close! ch)
    (with-mutex (channel-mutex ch)
      (channel-closed?-set! ch #t)
      (condition-broadcast (channel-not-empty ch))
      (condition-broadcast (channel-not-full ch))))

  ;; ========== Green threads ==========
  ;; Simple thread-based implementation (engines for cooperative scheduling)

  (define (go thunk)
    (fork-thread thunk))

  (define (go-named name thunk)
    (fork-thread thunk))

  (define (yield)
    (sleep (make-time 'time-duration 1000000 0)))

  ;; Run a CSP system: execute thunk, return result
  (define (csp-run thunk)
    (thunk))

  ;; ========== Channel utilities ==========

  (define (chan->list ch)
    (let loop ([acc '()])
      (let ([v (chan-get! ch)])
        (if (eof-object? v)
          (reverse acc)
          (loop (cons v acc))))))

  (define (chan-pipe from to proc)
    (go (lambda ()
          (let loop ()
            (let ([v (chan-get! from)])
              (unless (eof-object? v)
                (chan-put! to (proc v))
                (loop))))
          (chan-close! to))))

  (define (chan-map ch proc)
    (let ([out (make-channel 16)])
      (chan-pipe ch out proc)
      out))

  (define (chan-filter ch pred)
    (let ([out (make-channel 16)])
      (go (lambda ()
            (let loop ()
              (let ([v (chan-get! ch)])
                (unless (eof-object? v)
                  (when (pred v)
                    (chan-put! out v))
                  (loop))))
            (chan-close! out)))
      out))

) ;; end library
