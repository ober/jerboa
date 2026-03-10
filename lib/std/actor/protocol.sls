#!chezscheme
;;; (std actor protocol) — ask/tell/reply, defprotocol macro
;;;
;;; ask wraps the message in a ('$ask reply-channel sender msg) envelope.
;;; The behavior unwraps it via (with-ask-context msg (lambda (actual) ...))
;;; and calls (reply value) to complete the future.

(library (std actor protocol)
  (export
    defprotocol

    ;; Core ask/tell/call
    ask          ;; (ask actor-ref msg) → future
    ask-sync     ;; (ask-sync actor-ref msg [timeout-secs]) → value
    tell         ;; alias for send

    ;; Reply inside a behavior
    reply        ;; (reply value) — must be in ask context
    reply-to     ;; (reply-to) → sender actor-ref or #f

    ;; ask envelope unwrapping
    with-ask-context

    ;; One-shot reply channels (exposed for advanced use)
    make-reply-channel
    reply-channel?
    reply-channel-get
    reply-channel-put!
  )
  (import (chezscheme)
          (std actor core)
          (std task))

  ;; -------- Reply channels --------
  ;; A thin wrapper around (std task) futures.

  (define-record-type reply-channel
    (fields (immutable future))
    (protocol (lambda (new) (lambda () (new (make-future)))))
    (sealed #t))

  (define (reply-channel-get rc)
    (future-get (reply-channel-future rc)))

  (define (reply-channel-put! rc value)
    (future-complete! (reply-channel-future rc) value))

  ;; Thread-local context set by with-ask-context
  (define current-reply-channel (make-thread-parameter #f))
  (define current-sender-ref    (make-thread-parameter #f))

  (define (reply value)
    (let ([rc (current-reply-channel)])
      (unless rc
        (error 'reply "not in an ask context — no reply channel present"))
      (reply-channel-put! rc value)))

  (define (reply-to) (current-sender-ref))

  ;; -------- ask --------

  (define *ask-tag* '$ask)  ;; private envelope tag

  (define (ask actor-ref msg)
    (let* ([rc  (make-reply-channel)]
           [env (list *ask-tag* rc (self) msg)])
      (send actor-ref env)
      (reply-channel-future rc)))  ;; caller calls future-get

  (define ask-sync
    (case-lambda
      [(actor-ref msg)
       (future-get (ask actor-ref msg))]
      [(actor-ref msg timeout-secs)
       ;; Polling timeout — 10ms intervals.
       ;; For finer granularity, submit a delayed cancellation to the scheduler.
       (let ([fut (ask actor-ref msg)])
         (let loop ([remaining timeout-secs])
           (if (future-done? fut)
             (future-get fut)
             (if (<= remaining 0)
               (error 'ask-sync "timeout waiting for reply" actor-ref msg)
               (begin
                 (sleep (make-time 'time-duration 10000000 0)) ;; 10ms
                 (loop (- remaining 0.01)))))))]))

  ;; -------- tell --------

  (define (tell actor-ref msg)
    (send actor-ref msg))

  ;; -------- with-ask-context --------
  ;; Unwraps a '$ask envelope and binds the reply channel.
  ;; If msg is not an ask envelope, calls body-proc with msg as-is.

  (define-syntax with-ask-context
    (syntax-rules ()
      [(_ msg body-proc)
       (if (and (pair? msg) (eq? (car msg) '$ask))
         (let ([rc     (cadr   msg)]
               [sender (caddr  msg)]
               [actual (cadddr msg)])
           (parameterize ([current-reply-channel rc]
                          [current-sender-ref    sender])
             (body-proc actual)))
         (body-proc msg))]))

  ;; -------- defprotocol macro --------
  ;;
  ;; (defprotocol service-name
  ;;   (msg-name field ... [-> result])
  ;;   ...)
  ;;
  ;; Generates for each clause:
  ;;   - define-record-type  service-name:msg-name
  ;;   - tell helper          service-name:msg-name!   (always)
  ;;   - ask helper           service-name:msg-name?!  (only if -> present)

  (define-syntax defprotocol
    (lambda (stx)
      (syntax-case stx ()
        [(_ proto-name clause ...)
         (let* ([proto  (syntax->datum #'proto-name)]
                [prefix (symbol->string proto)])

           (define (parse-clause datum)
             ;; Returns (values name fields has-reply?)
             (let loop ([rest (cdr datum)] [fields '()])
               (cond
                 [(null? rest)
                  (values (car datum) (reverse fields) #f)]
                 [(eq? (car rest) '->)
                  (values (car datum) (reverse fields) #t)]
                 [else
                  (loop (cdr rest) (cons (car rest) fields))])))

           (define (sym . parts)
             (string->symbol
               (apply string-append
                 (map (lambda (p)
                        (if (symbol? p) (symbol->string p) p))
                      parts))))

           (with-syntax
             ([(expanded ...)
               (map (lambda (c)
                      (let ([datum (syntax->datum c)])
                        (let-values ([(name fields has-reply?) (parse-clause datum)])
                          (let* ([struct-name (sym prefix ":" name)]
                                 [make-name   (sym "make-" prefix ":" name)]
                                 [pred-name   (sym prefix ":" name "?")]
                                 [tell-name   (sym prefix ":" name "!")]
                                 [ask-name    (sym prefix ":" name "?!")])
                            (datum->syntax #'proto-name
                              `(begin
                                 (define-record-type ,struct-name
                                   (fields ,@(map (lambda (f) `(immutable ,f)) fields))
                                   (sealed #t))
                                 (define (,tell-name actor ,@fields)
                                   (tell actor (,make-name ,@fields)))
                                 ,@(if has-reply?
                                     `((define (,ask-name actor ,@fields)
                                         (ask-sync actor (,make-name ,@fields))))
                                     '())))))))
                    (syntax->list #'(clause ...)))])
             #'(begin expanded ...)))])))

  ) ;; end library
