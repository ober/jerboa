#!chezscheme
;;; :std/misc/channel -- Gerbil-compatible channels using Chez threads

(library (std misc channel)
  (export make-channel channel-put channel-get channel-try-get
          channel-close channel-closed? channel?)
  (import (chezscheme))

  (define-record-type channel
    (fields
      (mutable queue)
      (immutable mutex)
      (immutable condvar)
      (mutable closed?))
    (protocol
      (lambda (new)
        (lambda ()
          (new '() (make-mutex) (make-condition) #f)))))

  (define (channel-put ch val)
    (when (channel-closed? ch)
      (error 'channel-put "channel is closed"))
    (with-mutex (channel-mutex ch)
      (channel-queue-set! ch (append (channel-queue ch) (list val)))
      (condition-signal (channel-condvar ch))))

  (define (channel-get ch)
    (with-mutex (channel-mutex ch)
      (let loop ()
        (cond
          [(pair? (channel-queue ch))
           (let ([val (car (channel-queue ch))])
             (channel-queue-set! ch (cdr (channel-queue ch)))
             val)]
          [(channel-closed? ch)
           (error 'channel-get "channel is closed and empty")]
          [else
           (condition-wait (channel-condvar ch) (channel-mutex ch))
           (loop)]))))

  (define (channel-try-get ch)
    (with-mutex (channel-mutex ch)
      (if (pair? (channel-queue ch))
        (let ([val (car (channel-queue ch))])
          (channel-queue-set! ch (cdr (channel-queue ch)))
          (values val #t))
        (values #f #f))))

  (define (channel-close ch)
    (with-mutex (channel-mutex ch)
      (channel-closed?-set! ch #t)
      (condition-broadcast (channel-condvar ch))))

  ) ;; end library
