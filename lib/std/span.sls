#!chezscheme
;;; (std span) -- Distributed tracing: spans and trace contexts
;;;
;;; Spans are named time intervals with tags and timestamped log events.
;;; Trace IDs and span IDs are random 64-bit integers.
;;; Context propagation uses string maps (e.g. HTTP header alists).

(library (std span)
  (export
    ;; Tracer
    make-tracer tracer? make-noop-tracer
    ;; Span operations
    start-span finish-span! span-set-tag! span-log!
    ;; Dynamic scoping
    with-span current-span
    ;; Accessors
    span-context span-id trace-id span-duration
    ;; Context propagation
    inject-context extract-context)

  (import (chezscheme))

  ;;; ========== ID generation ==========
  ;; Random 64-bit integers using Chez's random
  (define (gen-id)
    ;; Chez random takes a max; use two 32-bit halves
    (let ([hi (random (expt 2 31))]
          [lo (random (expt 2 31))])
      (+ (* hi (expt 2 31)) lo)))

  ;;; ========== Span context ==========
  ;; Carries trace-id and span-id for propagation
  (define-record-type %span-context
    (fields trace-id span-id))

  (define (span-context sp)
    (make-%span-context (%span-trace-id sp) (%span-id sp)))

  (define (trace-id ctx-or-span)
    (cond
      [(%span-context? ctx-or-span) (%span-context-trace-id ctx-or-span)]
      [(%span? ctx-or-span)         (%span-trace-id ctx-or-span)]
      [else (error 'trace-id "expected span or span-context" ctx-or-span)]))

  (define (span-id ctx-or-span)
    (cond
      [(%span-context? ctx-or-span) (%span-context-span-id ctx-or-span)]
      [(%span? ctx-or-span)         (%span-id ctx-or-span)]
      [else (error 'span-id "expected span or span-context" ctx-or-span)]))

  ;;; ========== Span record ==========
  ;; name       — string
  ;; trace-id   — integer
  ;; id         — integer
  ;; parent-id  — integer or #f
  ;; start-time — time object
  ;; end-time   — mutable, time or #f
  ;; tags       — mutable alist
  ;; logs       — mutable list of (time . alist)
  ;; finished?  — mutable boolean
  (define-record-type %span
    (fields name trace-id id parent-id start-time
            (mutable end-time)
            (mutable tags)
            (mutable logs)
            (mutable finished?))
    (protocol
      (lambda (new)
        (lambda (name trace-id id parent-id start)
          (new name trace-id id parent-id start #f '() '() #f)))))

  ;;; ========== Tracer record ==========
  ;; finished-spans — mutable list (for noop: discarded)
  (define-record-type %tracer
    (fields noop? (mutable finished-spans))
    (protocol
      (lambda (new)
        (lambda (noop?)
          (new noop? '())))))

  (define (tracer? x) (%tracer? x))

  (define (make-tracer) (make-%tracer #f))
  (define (make-noop-tracer) (make-%tracer #t))

  ;;; ========== current-span parameter ==========
  (define current-span (make-parameter #f))

  ;;; ========== start-span ==========
  ;; (start-span tracer name)          — new root span
  ;; (start-span tracer name parent)   — child of parent span
  (define (start-span tracer name . parent-opt)
    (let* ([parent    (if (pair? parent-opt) (car parent-opt) (current-span))]
           [trace-id  (if parent (%span-trace-id parent) (gen-id))]
           [parent-id (if parent (%span-id parent) #f)]
           [id        (gen-id)]
           [sp        (make-%span name trace-id id parent-id (current-time))])
      sp))

  ;;; ========== finish-span! ==========
  (define (finish-span! tracer sp)
    (unless (%span-finished? sp)
      (%span-end-time-set!  sp (current-time))
      (%span-finished?-set! sp #t)
      (unless (%tracer-noop? tracer)
        (%tracer-finished-spans-set! tracer
          (cons sp (%tracer-finished-spans tracer))))))

  ;;; ========== span-duration ==========
  ;; Returns duration in milliseconds (or #f if not finished)
  (define (span-duration sp)
    (let ([end (%span-end-time sp)]
          [start (%span-start-time sp)])
      (if end
        (let ([ds (- (time-second end) (time-second start))]
              [dns (- (time-nanosecond end) (time-nanosecond start))])
          (+ (* ds 1000) (div dns 1000000)))
        #f)))

  ;;; ========== span-set-tag! ==========
  (define (span-set-tag! sp key value)
    (%span-tags-set! sp (cons (cons key value) (%span-tags sp))))

  ;;; ========== span-log! ==========
  ;; (span-log! sp key val … ) — append a timestamped event
  (define (span-log! sp . kv)
    (let ([ts (current-time)]
          [fields (parse-kv kv)])
      (%span-logs-set! sp
        (cons (cons ts fields) (%span-logs sp)))))

  (define (parse-kv lst)
    (let loop ([lst lst] [acc '()])
      (if (null? lst)
        (reverse acc)
        (if (null? (cdr lst))
          (error 'span-log! "odd number of key/value arguments")
          (loop (cddr lst)
                (cons (cons (car lst) (cadr lst)) acc))))))

  ;;; ========== with-span ==========
  (define-syntax with-span
    (syntax-rules ()
      [(_ tracer name body ...)
       (let* ([parent  (current-span)]
              [sp      (start-span tracer name parent)])
         (parameterize ([current-span sp])
           (let ([result (begin body ...)])
             (finish-span! tracer sp)
             result)))]
      [(_ tracer name parent body ...)
       (let ([sp (start-span tracer name parent)])
         (parameterize ([current-span sp])
           (let ([result (begin body ...)])
             (finish-span! tracer sp)
             result)))]))

  ;;; ========== Context propagation ==========
  ;; Inject: write trace-id and span-id into a map (alist)
  (define (inject-context sp . map-opt)
    (let ([m (if (pair? map-opt) (car map-opt) '())])
      (list (cons "X-Trace-Id" (number->string (%span-trace-id sp)))
            (cons "X-Span-Id"  (number->string (%span-id sp))))))

  ;; Extract: read a span-context from a map (alist)
  (define (extract-context m)
    (let ([tid-pair (assoc "X-Trace-Id" m)]
          [sid-pair (assoc "X-Span-Id"  m)])
      (if (and tid-pair sid-pair)
        (make-%span-context
          (string->number (cdr tid-pair))
          (string->number (cdr sid-pair)))
        #f)))

) ;; end library
