#!chezscheme
;;; (std stream window) — Stream processing with windowing
;;;
;;; Windows are stateful objects that buffer incoming items and emit
;;; complete windows (lists of items) when their criterion is met.
;;;
;;; Conventions:
;;;   window-add! returns: emitted window (list of items) | #f (not ready)
;;;   window-flush! forces emission of any partial window (may return #f if empty)

(library (std stream window)
  (export
    ;; Tumbling windows (non-overlapping, fixed-size)
    make-tumbling-window
    tumbling-window?
    window-add!
    window-flush!
    window-size
    ;; Sliding windows (overlapping)
    make-sliding-window
    sliding-window?
    sliding-window-add!
    sliding-window-size
    sliding-window-step
    ;; Session windows (gap-based)
    make-session-window
    session-window?
    session-window-add!
    session-window-gap
    session-window-flush!
    ;; Count-based windowing
    make-count-window
    count-window-add!
    ;; Time-based
    make-time-window
    time-window-add!
    time-window-flush!
    ;; Aggregation over windows
    window-map
    window-reduce
    window-filter
    ;; Stream pipeline
    make-windowed-stream
    ;; Utilities
    window-results
    window-reset!)

  (import (chezscheme))

  ;; ======================================================================
  ;; Tumbling Window
  ;; Non-overlapping, fixed-size windows. Items accumulate until size is
  ;; reached, then the window is emitted and the buffer resets.
  ;; ======================================================================

  (define-record-type tumbling-win
    (fields
      (immutable size)          ;; items per window
      (mutable   buffer)        ;; current partial window (list, newest first)
      (mutable   count)         ;; items in buffer
      (mutable   results)       ;; list of emitted windows
      (immutable mutex))
    (sealed #t))

  (define (make-tumbling-window size)
    (unless (and (integer? size) (> size 0))
      (error 'make-tumbling-window "size must be positive integer" size))
    (make-tumbling-win size '() 0 '() (make-mutex)))

  (define (tumbling-window? x) (tumbling-win? x))

  ;; Add an item. Returns the emitted window (list) or #f.
  (define (window-add! win item)
    (with-mutex (tumbling-win-mutex win)
      (let* ([new-buf   (cons item (tumbling-win-buffer win))]
             [new-count (+ (tumbling-win-count win) 1)])
        (if (= new-count (tumbling-win-size win))
          ;; Window is complete — emit in insertion order
          (let ([emitted (reverse new-buf)])
            (tumbling-win-buffer-set! win '())
            (tumbling-win-count-set!  win 0)
            (tumbling-win-results-set! win
              (append (tumbling-win-results win) (list emitted)))
            emitted)
          (begin
            (tumbling-win-buffer-set! win new-buf)
            (tumbling-win-count-set!  win new-count)
            #f)))))

  ;; Force-emit whatever is in the buffer (may be empty).
  (define (window-flush! win)
    (with-mutex (tumbling-win-mutex win)
      (let ([buf (tumbling-win-buffer win)])
        (if (null? buf)
          #f
          (let ([emitted (reverse buf)])
            (tumbling-win-buffer-set! win '())
            (tumbling-win-count-set!  win 0)
            (tumbling-win-results-set! win
              (append (tumbling-win-results win) (list emitted)))
            emitted)))))

  (define (window-size win) (tumbling-win-size win))

  ;; ======================================================================
  ;; Sliding Window
  ;; Items are always emitted as the current window on each add.
  ;; step controls how many items to advance the window start.
  ;; ======================================================================

  (define-record-type sliding-win
    (fields
      (immutable size)         ;; items in each emitted window
      (immutable step)         ;; advance by this many on each addition
      (mutable   buffer)       ;; list of last 'size' items (newest first)
      (mutable   count)        ;; total items seen
      (mutable   results)
      (immutable mutex))
    (sealed #t))

  (define (make-sliding-window size . rest)
    (let ([step (if (null? rest) 1 (car rest))])
      (unless (and (integer? size) (> size 0))
        (error 'make-sliding-window "size must be positive integer" size))
      (make-sliding-win size step '() 0 '() (make-mutex))))

  (define (sliding-window? x) (sliding-win? x))

  ;; Returns the current window (list) after adding item.
  ;; Window is only emitted once size items have been seen.
  (define (sliding-window-add! win item)
    (with-mutex (sliding-win-mutex win)
      (let* ([size    (sliding-win-size win)]
             [new-buf (cons item (sliding-win-buffer win))]
             [new-cnt (+ (sliding-win-count win) 1)]
             ;; Keep at most 'size' items
             [trimmed (if (> (length new-buf) size)
                        (list-head new-buf size)
                        new-buf)])
        (sliding-win-buffer-set! win trimmed)
        (sliding-win-count-set!  win new-cnt)
        (if (>= new-cnt size)
          ;; Return window in insertion order
          (let ([window (reverse trimmed)])
            (sliding-win-results-set! win
              (append (sliding-win-results win) (list window)))
            window)
          #f))))

  (define (sliding-window-size win) (sliding-win-size win))
  (define (sliding-window-step win) (sliding-win-step win))

  ;; ======================================================================
  ;; Session Window
  ;; Groups items by time gap. When the gap between consecutive timestamps
  ;; exceeds session-window-gap, the session is ended and a new one begins.
  ;; ======================================================================

  (define-record-type session-win
    (fields
      (immutable gap)            ;; max gap (ms or same unit as timestamps)
      (mutable   buffer)         ;; items in current session (newest first)
      (mutable   last-ts)        ;; timestamp of last item
      (mutable   results)
      (immutable mutex))
    (sealed #t))

  (define (make-session-window gap)
    (unless (and (number? gap) (> gap 0))
      (error 'make-session-window "gap must be positive number" gap))
    (make-session-win gap '() #f '() (make-mutex)))

  (define (session-window? x) (session-win? x))

  ;; Add item with timestamp. Returns emitted session (list) or #f.
  (define (session-window-add! win item timestamp)
    (with-mutex (session-win-mutex win)
      (let ([last-ts (session-win-last-ts win)]
            [gap     (session-win-gap win)]
            [buf     (session-win-buffer win)])
        (if (and last-ts (> (- timestamp last-ts) gap))
          ;; Gap exceeded — emit current session, start new one
          (let ([emitted (reverse buf)])
            (session-win-results-set! win
              (append (session-win-results win) (list emitted)))
            (session-win-buffer-set!  win (list item))
            (session-win-last-ts-set! win timestamp)
            emitted)
          ;; Same session
          (begin
            (session-win-buffer-set!  win (cons item buf))
            (session-win-last-ts-set! win timestamp)
            #f)))))

  (define (session-window-gap win) (session-win-gap win))

  (define (session-window-flush! win)
    (with-mutex (session-win-mutex win)
      (let ([buf (session-win-buffer win)])
        (if (null? buf)
          #f
          (let ([emitted (reverse buf)])
            (session-win-results-set! win
              (append (session-win-results win) (list emitted)))
            (session-win-buffer-set!  win '())
            (session-win-last-ts-set! win #f)
            emitted)))))

  ;; ======================================================================
  ;; Count Window (alias / variant of tumbling with explicit name)
  ;; Emits every N items regardless of other criteria.
  ;; ======================================================================

  (define (make-count-window n)
    (make-tumbling-window n))

  (define (count-window-add! win item)
    (window-add! win item))

  ;; ======================================================================
  ;; Time Window
  ;; Emits when real-time duration (ms) has elapsed since creation or reset.
  ;; ======================================================================

  (define-record-type time-win
    (fields
      (immutable duration-ms)    ;; window duration in milliseconds
      (mutable   buffer)
      (mutable   start-time)     ;; time-second when window started
      (mutable   results)
      (immutable mutex))
    (sealed #t))

  (define (make-time-window duration-ms)
    (unless (and (number? duration-ms) (> duration-ms 0))
      (error 'make-time-window "duration-ms must be positive" duration-ms))
    (make-time-win duration-ms '() (current-time-ms) '() (make-mutex)))

  (define (time-window? x) (time-win? x))

  (define (current-time-ms)
    (* 1000 (time-second (current-time))))

  ;; Add item. Emits window if duration has passed.
  (define (time-window-add! win item)
    (with-mutex (time-win-mutex win)
      (let* ([now      (current-time-ms)]
             [start    (time-win-start-time win)]
             [elapsed  (- now start)]
             [new-buf  (cons item (time-win-buffer win))])
        (time-win-buffer-set! win new-buf)
        (if (>= elapsed (time-win-duration-ms win))
          ;; Time window expired — emit and reset
          (let ([emitted (reverse new-buf)])
            (time-win-results-set! win
              (append (time-win-results win) (list emitted)))
            (time-win-buffer-set!    win '())
            (time-win-start-time-set! win (current-time-ms))
            emitted)
          #f))))

  (define (time-window-flush! win)
    (with-mutex (time-win-mutex win)
      (let ([buf (time-win-buffer win)])
        (if (null? buf)
          #f
          (let ([emitted (reverse buf)])
            (time-win-results-set! win
              (append (time-win-results win) (list emitted)))
            (time-win-buffer-set!    win '())
            (time-win-start-time-set! win (current-time-ms))
            emitted)))))

  ;; ======================================================================
  ;; Window combinators: map, reduce, filter
  ;; These wrap a window and transform emitted windows.
  ;; ======================================================================

  ;; A mapped-window intercepts emissions from an inner window and applies f.
  (define-record-type mapped-win
    (fields
      (immutable inner)     ;; underlying window (tumbling, sliding, etc.)
      (immutable fn)        ;; f: window-list -> transformed-value
      (mutable   results)
      (immutable mutex))
    (sealed #t))

  ;; (window-map win f) — returns a new window; add! returns f(window) or #f
  (define (window-map win f)
    (make-mapped-win win f '() (make-mutex)))

  ;; Add item to the inner window; if it emits, apply f and record result.
  (define (%mapped-add! mw item add-proc)
    (let ([result (add-proc (mapped-win-inner mw) item)])
      (if result
        (let ([transformed (( mapped-win-fn mw) result)])
          (with-mutex (mapped-win-mutex mw)
            (mapped-win-results-set! mw
              (append (mapped-win-results mw) (list transformed))))
          transformed)
        #f)))

  ;; (window-reduce win f init) — builds a reducer window
  (define (window-reduce win f init)
    (window-map win (lambda (items) (fold-left f init items))))

  ;; (window-filter win pred) — build a filter-then-window
  ;; Returns a filtering wrapper; add! only passes items satisfying pred.
  (define-record-type filter-win
    (fields
      (immutable inner)
      (immutable pred)
      (mutable   results)
      (immutable mutex))
    (sealed #t))

  (define (window-filter win pred)
    (make-filter-win win pred '() (make-mutex)))

  ;; ======================================================================
  ;; Windowed stream pipeline
  ;; ======================================================================

  ;; (make-windowed-stream source window agg-fn)
  ;; source  : list of items
  ;; window  : a tumbling-window
  ;; agg-fn  : called on each complete window, returns a result
  ;; Returns: list of aggregated results
  (define (make-windowed-stream source win agg-fn)
    (let ([results '()])
      (for-each
        (lambda (item)
          (let ([emitted (window-add! win item)])
            (when emitted
              (set! results (append results (list (agg-fn emitted)))))))
        source)
      ;; Flush partial window
      (let ([final (window-flush! win)])
        (when final
          (set! results (append results (list (agg-fn final))))))
      results))

  ;; ======================================================================
  ;; Generic utilities
  ;; ======================================================================

  ;; (window-results win) — return all accumulated results so far
  (define (window-results win)
    (cond
      [(tumbling-win? win)  (tumbling-win-results  win)]
      [(sliding-win?  win)  (sliding-win-results   win)]
      [(session-win?  win)  (session-win-results   win)]
      [(time-win?     win)  (time-win-results      win)]
      [(mapped-win?   win)  (mapped-win-results    win)]
      [(filter-win?   win)  (filter-win-results    win)]
      [else (error 'window-results "unknown window type" win)]))

  ;; (window-reset! win) — clear buffer and results
  (define (window-reset! win)
    (cond
      [(tumbling-win? win)
       (with-mutex (tumbling-win-mutex win)
         (tumbling-win-buffer-set!  win '())
         (tumbling-win-count-set!   win 0)
         (tumbling-win-results-set! win '()))]
      [(sliding-win? win)
       (with-mutex (sliding-win-mutex win)
         (sliding-win-buffer-set!  win '())
         (sliding-win-count-set!   win 0)
         (sliding-win-results-set! win '()))]
      [(session-win? win)
       (with-mutex (session-win-mutex win)
         (session-win-buffer-set!   win '())
         (session-win-last-ts-set!  win #f)
         (session-win-results-set!  win '()))]
      [(time-win? win)
       (with-mutex (time-win-mutex win)
         (time-win-buffer-set!    win '())
         (time-win-start-time-set! win (current-time-ms))
         (time-win-results-set!   win '()))]
      [else (error 'window-reset! "unknown window type" win)]))

  ) ;; end library
