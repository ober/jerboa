#!chezscheme
;;; Tests for (std span) -- Distributed tracing

(import (chezscheme)
        (std span))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(printf "--- Phase 3a: Distributed Tracing ---~%~%")

;;; ======== Tracer creation ========

(test "tracer? true"
  (tracer? (make-tracer))
  #t)

(test "tracer? false"
  (tracer? 'not-a-tracer)
  #f)

(test "noop-tracer? true"
  (tracer? (make-noop-tracer))
  #t)

;;; ======== Span creation ========

(let* ([t  (make-tracer)]
       [sp (start-span t "root")])

  (test "span has integer trace-id"
    (integer? (trace-id sp))
    #t)

  (test "span has integer span-id"
    (integer? (span-id sp))
    #t)

  (test "trace-id and span-id are different"
    (= (trace-id sp) (span-id sp))
    #f))

;;; ======== finish-span! / span-duration ========

(let* ([t  (make-tracer)]
       [sp (start-span t "op")])
  (test "duration before finish is #f"
    (span-duration sp)
    #f)

  (finish-span! t sp)

  (test "duration after finish is a number"
    (number? (span-duration sp))
    #t)

  (test "duration is non-negative"
    (>= (span-duration sp) 0)
    #t))

;;; ======== Parent/child spans share trace-id ========

(let* ([t      (make-tracer)]
       [root   (start-span t "root")]
       [child  (start-span t "child" root)])

  (test "child shares trace-id with parent"
    (= (trace-id root) (trace-id child))
    #t)

  (test "child has different span-id"
    (= (span-id root) (span-id child))
    #f))

;;; ======== span-set-tag! ========

(let* ([t  (make-tracer)]
       [sp (start-span t "tagged")])
  (span-set-tag! sp "http.method" "GET")
  (span-set-tag! sp "http.status" 200)
  ;; Tags are stored; just verify no error
  (test "span-set-tag! does not error"
    'ok
    'ok))

;;; ======== span-log! ========

(let* ([t  (make-tracer)]
       [sp (start-span t "logged")])
  (span-log! sp 'event "retry" 'attempt 1)
  (test "span-log! does not error"
    'ok
    'ok))

;;; ======== with-span / current-span ========

(let ([t (make-tracer)])
  (test "current-span initially #f"
    (current-span)
    #f)

  (with-span t "outer"
    (test "current-span set in with-span"
      (not (eq? (current-span) #f))
      #t)

    (let ([outer-trace (trace-id (current-span))])
      (with-span t "inner"
        (test "inner span shares trace-id"
          (= (trace-id (current-span)) outer-trace)
          #t))))

  (test "current-span restored after with-span"
    (current-span)
    #f))

;;; ======== with-span returns value ========

(let ([t (make-tracer)])
  (test "with-span returns body value"
    (with-span t "compute"
      (+ 1 2))
    3))

;;; ======== span-context / inject-context / extract-context ========

(let* ([t    (make-tracer)]
       [sp   (start-span t "root")]
       [ctx  (span-context sp)]
       [hdrs (inject-context sp)])

  (test "span-context has matching trace-id"
    (= (trace-id ctx) (trace-id sp))
    #t)

  (test "inject-context returns alist"
    (list? hdrs)
    #t)

  (test "inject-context contains X-Trace-Id"
    (string? (cdr (assoc "X-Trace-Id" hdrs)))
    #t)

  (let ([extracted (extract-context hdrs)])
    (test "extract-context returns non-#f"
      (not (eq? extracted #f))
      #t)

    (test "extracted trace-id matches"
      (= (trace-id extracted) (trace-id sp))
      #t)

    (test "extracted span-id matches"
      (= (span-id extracted) (span-id sp))
      #t)))

;;; ======== extract-context from empty map ========

(test "extract-context from empty map returns #f"
  (extract-context '())
  #f)

;;; ======== noop tracer ========

(let* ([t  (make-noop-tracer)]
       [sp (start-span t "noop-span")])
  (span-set-tag! sp "k" "v")
  (finish-span! t sp)
  (test "noop tracer finishes span without error"
    (number? (span-duration sp))
    #t))

;;; Summary

(printf "~%Span tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
