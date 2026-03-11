#!chezscheme
;;; (std stream async) — Lazy Async Streams with Backpressure
;;;
;;; Async streams are lazy sequences backed by channels. Each element is
;;; produced asynchronously. Backpressure is achieved via bounded channels:
;;; producers block when the buffer is full; consumers drive pulling.
;;;
;;; Stream representation: a channel that carries either:
;;;   - a pair (value . stream-tail-thunk)  — next element + rest
;;;   - the symbol 'eos                     — end of stream
;;;
;;; API:
;;;   (make-async-stream producer-thunk [buffer-size])
;;;     producer-thunk: (lambda (emit! done!) ...) — call emit! for each value, done! at end
;;;   (async-stream-next! stream)  → (values val #t) or (values #f #f) at end
;;;   (async-stream-map f stream)
;;;   (async-stream-filter pred stream)
;;;   (async-stream-take n stream)
;;;   (async-stream-for-each f stream)
;;;   (async-stream-fold f init stream)
;;;   (async-stream->list stream)
;;;   (async-stream-empty? stream)
;;;   (list->async-stream lst)

(library (std stream async)
  (export
    make-async-stream
    async-stream-next!
    async-stream-map
    async-stream-filter
    async-stream-take
    async-stream-for-each
    async-stream-fold
    async-stream->list
    async-stream-empty?
    list->async-stream)

  (import (chezscheme) (std misc channel))

  ;; ========== Async Stream Type ==========
  ;; An async stream is a record wrapping a channel.
  ;; The channel delivers items one at a time. The end-of-stream marker is 'eos.

  (define-record-type (async-stream %make-async-stream async-stream?)
    (fields (immutable ch async-stream-ch)))

  ;; ========== Construction ==========

  (define make-async-stream
    (case-lambda
      [(producer-thunk) (make-async-stream producer-thunk 16)]
      [(producer-thunk buffer-size)
       (let ([ch (make-channel buffer-size)])
         (fork-thread
           (lambda ()
             (guard (exn [#t (channel-put ch 'eos)])
               (let ([emit! (lambda (val) (channel-put ch val))]
                     [done! (lambda () (channel-put ch 'eos))])
                 (producer-thunk emit! done!)))))
         (%make-async-stream ch))]))

  (define (list->async-stream lst)
    (make-async-stream
      (lambda (emit! done!)
        (for-each emit! lst)
        (done!))))

  ;; ========== Consumption ==========

  (define (async-stream-next! stream)
    ;; Returns (values val #t) or (values #f #f) at EOS
    (let ([item (channel-get (async-stream-ch stream))])
      (if (eq? item 'eos)
        (begin
          ;; Put eos back so repeated calls work correctly
          (channel-put (async-stream-ch stream) 'eos)
          (values #f #f))
        (values item #t))))

  (define (async-stream-empty? stream)
    ;; Peek: non-blocking check
    (let-values ([(val ok) (channel-try-get (async-stream-ch stream))])
      (if ok
        (if (eq? val 'eos)
          (begin (channel-put (async-stream-ch stream) 'eos) #t)
          (begin (channel-put (async-stream-ch stream) val) #f))
        #f)))  ;; unknown — not empty yet

  ;; ========== Derived Streams ==========

  (define (async-stream-map f stream)
    (make-async-stream
      (lambda (emit! done!)
        (let loop ()
          (let-values ([(val ok) (async-stream-next! stream)])
            (if ok
              (begin (emit! (f val)) (loop))
              (done!)))))))

  (define (async-stream-filter pred stream)
    (make-async-stream
      (lambda (emit! done!)
        (let loop ()
          (let-values ([(val ok) (async-stream-next! stream)])
            (if ok
              (begin (when (pred val) (emit! val)) (loop))
              (done!)))))))

  (define (async-stream-take n stream)
    (make-async-stream
      (lambda (emit! done!)
        (let loop ([remaining n])
          (if (= remaining 0)
            (done!)
            (let-values ([(val ok) (async-stream-next! stream)])
              (if ok
                (begin (emit! val) (loop (- remaining 1)))
                (done!))))))))

  ;; ========== Terminal Operations ==========

  (define (async-stream-for-each f stream)
    (let loop ()
      (let-values ([(val ok) (async-stream-next! stream)])
        (when ok
          (f val)
          (loop)))))

  (define (async-stream-fold f init stream)
    (let loop ([acc init])
      (let-values ([(val ok) (async-stream-next! stream)])
        (if ok
          (loop (f acc val))
          acc))))

  (define (async-stream->list stream)
    (let loop ([acc '()])
      (let-values ([(val ok) (async-stream-next! stream)])
        (if ok
          (loop (cons val acc))
          (reverse acc)))))

) ;; end library
