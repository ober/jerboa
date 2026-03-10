#!chezscheme
;;; :std/misc/channel -- Bounded channels with ring buffer and select
;;;
;;; - O(1) put/get via ring buffer (vector + head/tail indices)
;;; - Optional bounded capacity with backpressure
;;; - channel-select: multiplex across multiple channels (like Go select)
;;; - Backward compatible: (make-channel) still creates unbounded channel

(library (std misc channel)
  (export make-channel channel-put channel-get channel-try-get
          channel-close channel-closed? channel?
          channel-length channel-empty?
          channel-select)
  (import (chezscheme))

  ;; Ring buffer: vector-based circular queue
  ;; When capacity is #f, the buffer grows dynamically (unbounded mode)
  (define-record-type channel
    (fields
      (mutable buf)          ;; vector (ring buffer storage)
      (mutable head)         ;; index of next item to read
      (mutable tail)         ;; index of next slot to write
      (mutable count)        ;; current number of items
      (mutable capacity)     ;; max items (#f = unbounded)
      (immutable mutex)
      (immutable not-empty)  ;; condition: signaled when item added
      (immutable not-full)   ;; condition: signaled when item removed
      (mutable closed?))
    (protocol
      (lambda (new)
        (case-lambda
          [()  ;; unbounded (default)
           (new (make-vector 16) 0 0 0 #f
                (make-mutex) (make-condition) (make-condition) #f)]
          [(cap)  ;; bounded
           (assert (and (fixnum? cap) (fx> cap 0)))
           (new (make-vector cap) 0 0 0 cap
                (make-mutex) (make-condition) (make-condition) #f)]))))

  ;; Grow the ring buffer (only for unbounded channels)
  (define (grow-buffer! ch)
    (let* ([old-buf (channel-buf ch)]
           [old-cap (vector-length old-buf)]
           [new-cap (fx* old-cap 2)]
           [new-buf (make-vector new-cap)]
           [head (channel-head ch)]
           [count (channel-count ch)])
      ;; Copy items in logical order
      (do ([i 0 (fx+ i 1)])
          ((fx= i count))
        (vector-set! new-buf i
          (vector-ref old-buf (fxmod (fx+ head i) old-cap))))
      (channel-buf-set! ch new-buf)
      (channel-head-set! ch 0)
      (channel-tail-set! ch count)))

  (define (channel-length ch)
    (channel-count ch))

  (define (channel-empty? ch)
    (fx= (channel-count ch) 0))

  (define (channel-put ch val)
    (with-mutex (channel-mutex ch)
      (when (channel-closed? ch)
        (error 'channel-put "channel is closed"))
      (let ([cap (channel-capacity ch)])
        ;; Bounded: wait until not full
        (when cap
          (let loop ()
            (when (fx= (channel-count ch) cap)
              (condition-wait (channel-not-full ch) (channel-mutex ch))
              (when (channel-closed? ch)
                (error 'channel-put "channel is closed"))
              (loop))))
        ;; Unbounded: grow if needed
        (unless cap
          (when (fx= (channel-count ch) (vector-length (channel-buf ch)))
            (grow-buffer! ch)))
        ;; Enqueue
        (let ([buf (channel-buf ch)]
              [tail (channel-tail ch)])
          (vector-set! buf tail val)
          (channel-tail-set! ch (fxmod (fx+ tail 1) (vector-length buf)))
          (channel-count-set! ch (fx+ (channel-count ch) 1)))
        (condition-signal (channel-not-empty ch)))))

  (define (channel-get ch)
    (with-mutex (channel-mutex ch)
      (let loop ()
        (cond
          [(fx> (channel-count ch) 0)
           (let* ([buf (channel-buf ch)]
                  [head (channel-head ch)]
                  [val (vector-ref buf head)])
             (vector-set! buf head #f) ;; help GC
             (channel-head-set! ch (fxmod (fx+ head 1) (vector-length buf)))
             (channel-count-set! ch (fx- (channel-count ch) 1))
             (condition-signal (channel-not-full ch))
             val)]
          [(channel-closed? ch)
           (error 'channel-get "channel is closed and empty")]
          [else
           (condition-wait (channel-not-empty ch) (channel-mutex ch))
           (loop)]))))

  (define (channel-try-get ch)
    (with-mutex (channel-mutex ch)
      (if (fx> (channel-count ch) 0)
        (let* ([buf (channel-buf ch)]
               [head (channel-head ch)]
               [val (vector-ref buf head)])
          (vector-set! buf head #f)
          (channel-head-set! ch (fxmod (fx+ head 1) (vector-length buf)))
          (channel-count-set! ch (fx- (channel-count ch) 1))
          (condition-signal (channel-not-full ch))
          (values val #t))
        (values #f #f))))

  (define (channel-close ch)
    (with-mutex (channel-mutex ch)
      (channel-closed?-set! ch #t)
      (condition-broadcast (channel-not-empty ch))
      (condition-broadcast (channel-not-full ch))))

  ;; ========== channel-select ==========
  ;;
  ;; (channel-select
  ;;   ((ch1 msg) body ...)       ;; receive from ch1
  ;;   ((ch2 msg) body ...)       ;; receive from ch2
  ;;   (timeout: seconds body ...) ;; optional timeout
  ;;   (else body ...))            ;; non-blocking fallback
  ;;
  ;; Multiplexes across multiple channels. Returns the result of the
  ;; first channel that has data available. If none ready and no else/timeout,
  ;; blocks until one becomes ready.

  (define-syntax channel-select
    (lambda (stx)
      (syntax-case stx (else)
        ;; Parse clauses into a runtime call
        [(k clause ...)
         (let ()
           (define clauses '())
           (define timeout-clause #f)
           (define else-clause #f)
           (for-each
             (lambda (c)
               (syntax-case c (else)
                 ;; else clause
                 [(else body ...)
                  (set! else-clause #'(lambda () body ...))]
                 ;; timeout or channel clause - check at runtime
                 [((ch-or-kw args ...) body ...)
                  (if (eq? (syntax->datum #'ch-or-kw) 'timeout:)
                    ;; (timeout: seconds body ...)
                    (syntax-case c ()
                      [((kw secs) body ...)
                       (set! timeout-clause
                         (list #'secs #'(lambda () body ...)))])
                    ;; ((ch msg) body ...) — channel receive
                    (syntax-case c ()
                      [((ch msg) body ...)
                       (set! clauses
                         (cons (list #'ch #'(lambda (msg) body ...))
                               clauses))]))]))
             (syntax->list #'(clause ...)))
           (set! clauses (reverse clauses))
           (with-syntax ([(ch ...) (map car clauses)]
                         [(handler ...) (map cadr clauses)])
             (cond
               [else-clause
                (with-syntax ([else-thunk else-clause])
                  #'(channel-select-now (list ch ...) (list handler ...) else-thunk))]
               [timeout-clause
                (with-syntax ([secs (car timeout-clause)]
                              [timeout-thunk (cadr timeout-clause)])
                  #'(channel-select-wait (list ch ...) (list handler ...)
                                         secs timeout-thunk))]
               [else
                #'(channel-select-wait (list ch ...) (list handler ...) #f #f)])))])))

  ;; Non-blocking select: try each channel, call else if none ready
  (define (channel-select-now channels handlers else-thunk)
    (let loop ([chs channels] [hs handlers])
      (if (null? chs)
        (else-thunk)
        (let-values ([(val ok) (channel-try-get (car chs))])
          (if ok
            ((car hs) val)
            (loop (cdr chs) (cdr hs)))))))

  ;; Blocking select with optional timeout
  ;; Strategy: shared condition variable that all channels signal
  (define (channel-select-wait channels handlers timeout-secs timeout-thunk)
    ;; First, try non-blocking
    (let try-loop ([chs channels] [hs handlers])
      (if (null? chs)
        ;; None ready — block
        (let ([shared-cond (make-condition)]
              [shared-mutex (make-mutex)])
          ;; Install watchers: for each channel, spawn a thread that waits
          ;; and signals the shared condition when data arrives
          (let ([watchers
                 (map (lambda (ch)
                        (fork-thread
                          (lambda ()
                            (with-mutex (channel-mutex ch)
                              (let loop ()
                                (cond
                                  [(fx> (channel-count ch) 0)
                                   ;; Data available — signal main
                                   (mutex-acquire shared-mutex)
                                   (condition-signal shared-cond)
                                   (mutex-release shared-mutex)]
                                  [(channel-closed? ch)
                                   (mutex-acquire shared-mutex)
                                   (condition-signal shared-cond)
                                   (mutex-release shared-mutex)]
                                  [else
                                   (condition-wait (channel-not-empty ch)
                                                   (channel-mutex ch))
                                   (loop)]))))))
                      channels)])
            ;; Wait on shared condition
            (mutex-acquire shared-mutex)
            (if timeout-secs
              (let ([ns (exact (floor (* timeout-secs 1000000000)))]
                    [s  (exact (floor timeout-secs))])
                (let ([ns-part (exact (floor (* (- timeout-secs s) 1000000000)))])
                  (condition-wait shared-cond shared-mutex
                                 (make-time 'time-duration ns-part s))))
              (condition-wait shared-cond shared-mutex))
            (mutex-release shared-mutex)
            ;; Try again non-blocking
            (let select-loop ([chs channels] [hs handlers])
              (if (null? chs)
                (if (and timeout-secs timeout-thunk)
                  (timeout-thunk)
                  ;; Spurious wake — retry
                  (channel-select-wait channels handlers timeout-secs timeout-thunk))
                (let-values ([(val ok) (channel-try-get (car chs))])
                  (if ok
                    ((car hs) val)
                    (select-loop (cdr chs) (cdr hs))))))))
        ;; Found data in non-blocking try
        (let-values ([(val ok) (channel-try-get (car chs))])
          (if ok
            ((car hs) val)
            (try-loop (cdr chs) (cdr hs)))))))

  ) ;; end library
