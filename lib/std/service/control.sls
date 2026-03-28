#!chezscheme
;;; (std service control) — Client-side service control (svc + svstat)
;;;
;;; Send commands to supervised services via control FIFO.
;;; Read service status from binary status files.

(library (std service control)
  (export
    ;; Control commands (write to FIFO)
    svc-up! svc-down! svc-once! svc-term! svc-kill!
    svc-pause! svc-continue! svc-hup! svc-alarm! svc-exit!

    ;; Status reading
    svstat svstat-string svok?

    ;; Status record
    make-svstat-info svstat-info?
    svstat-info-pid svstat-info-up? svstat-info-paused?
    svstat-info-want svstat-info-seconds)

  (import
    (chezscheme)
    (std os posix))

  ;; ========== Status Record ==========

  (define-record-type svstat-info
    (fields
      pid        ;; integer (0 if down)
      up?        ;; boolean
      paused?    ;; boolean
      want       ;; symbol: up, down, once
      seconds    ;; integer (seconds in current state)
    )
    (nongenerative svstat-info))

  ;; ========== TAI64N ==========

  (define TAI-OFFSET 4611686018427387904)

  ;; ========== Control Commands ==========

  (define (svc-send! service-dir byte)
    (let ([ctl-path (string-append service-dir "/supervise/control")])
      (let ([fd (posix-open ctl-path O_WRONLY #o0)])
        (let ([buf (make-bytevector 1)])
          (bytevector-u8-set! buf 0 (char->integer byte))
          (posix-write fd buf 1))
        (posix-close fd))))

  (define (svc-up! service-dir)       (svc-send! service-dir #\u))
  (define (svc-down! service-dir)     (svc-send! service-dir #\d))
  (define (svc-once! service-dir)     (svc-send! service-dir #\o))
  (define (svc-term! service-dir)     (svc-send! service-dir #\t))
  (define (svc-kill! service-dir)     (svc-send! service-dir #\k))
  (define (svc-pause! service-dir)    (svc-send! service-dir #\p))
  (define (svc-continue! service-dir) (svc-send! service-dir #\c))
  (define (svc-hup! service-dir)      (svc-send! service-dir #\h))
  (define (svc-alarm! service-dir)    (svc-send! service-dir #\a))
  (define (svc-exit! service-dir)     (svc-send! service-dir #\x))

  ;; ========== Status Reading ==========

  (define (svstat service-dir)
    (let ([status-path (string-append service-dir "/supervise/status")])
      (guard (e [#t #f])
        (let ([fd (posix-open status-path O_RDONLY 0)])
          (let ([buf (make-bytevector 18 0)])
            (let ([n (posix-read fd buf 18)])
              (posix-close fd)
              (if (< n 18)
                #f
                (let* ([tai-secs (bytevector-u64-ref buf 0 (endianness big))]
                       [unix-secs (- tai-secs TAI-OFFSET)]
                       [pid (bytevector-u32-ref buf 12 (endianness big))]
                       [paused? (= (bytevector-u8-ref buf 16) 1)]
                       [want-byte (bytevector-u8-ref buf 17)]
                       [want (cond
                               [(= want-byte (char->integer #\u)) 'up]
                               [(= want-byte (char->integer #\d)) 'down]
                               [else 'once])]
                       [up? (> pid 0)]
                       [now (time-second (current-time 'time-utc))]
                       [elapsed (max 0 (- now unix-secs))])
                  (make-svstat-info pid up? paused? want elapsed)))))))))

  (define (svstat-string service-dir)
    (let ([info (svstat service-dir)])
      (if (not info)
        (string-append service-dir ": unable to read status")
        (string-append
          service-dir ": "
          (if (svstat-info-up? info)
            (string-append
              "up (pid " (number->string (svstat-info-pid info)) ") "
              (number->string (svstat-info-seconds info)) " seconds")
            (string-append
              "down " (number->string (svstat-info-seconds info)) " seconds"))
          (if (svstat-info-paused? info) ", paused" "")
          (cond
            [(and (svstat-info-up? info)
                  (eq? (svstat-info-want info) 'down))
             ", want down"]
            [(and (not (svstat-info-up? info))
                  (eq? (svstat-info-want info) 'up))
             ", want up"]
            [else ""])))))

  (define (svok? service-dir)
    ;; Check if supervise is running by trying to open the ok FIFO
    (let ([ok-path (string-append service-dir "/supervise/ok")])
      (guard (e [#t #f])
        (let ([fd (posix-open ok-path
                    (bitwise-ior O_WRONLY O_NONBLOCK) 0)])
          (posix-close fd)
          #t))))

  ) ;; end library
