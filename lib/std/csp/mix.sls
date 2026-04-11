#!chezscheme
;;; (std csp mix) — Clojure core.async `mix` / `admix` / `toggle`
;;;
;;; A `mix` is a dynamic fan-in. You create one with `(make-mix out)`
;;; pointing to a destination channel, then add inputs with
;;; `(admix! m ch)`, remove them with `(unmix! m ch)`, and per-input
;;; mute / pause / solo with `(toggle! m state-map)`.
;;;
;;; Per-input state flags
;;; ---------------------
;;;   muted?   read from the input but drop its values
;;;   paused?  skip the input entirely
;;;   solo?    mark the input as solo
;;;
;;; If ANY input has `solo?` set, the mix behaves as if only solo'd
;;; inputs exist, plus non-solo'd inputs get treated according to the
;;; mix's `solo-mode` (`'mute` by default, `'pause` is the other
;;; option). This matches core.async's solo semantics.
;;;
;;; Control channel
;;; ---------------
;;; Every reconfig (admix, unmix, toggle, solo-mode) pokes a size-1
;;; control channel so the mix loop's `alts!!` unblocks and re-reads
;;; its input set. The poke is non-blocking — if the control channel
;;; is already full the mix loop will re-read anyway on its next pass,
;;; so dropped control signals are benign.
;;;
;;; This module is layered under (std csp ops) which re-exports the
;;; public API. Clojure-style short names (mix, admix, unmix, toggle,
;;; solo-mode) live in (std csp clj).

(library (std csp mix)
  (export
    make-mix mix? mix-out mix-solo-mode
    admix! unmix! unmix-all!
    toggle! solo-mode!)

  (import (chezscheme)
          (std csp)
          (std csp select))

  ;; ======================================================
  ;; Per-input state
  ;; ======================================================

  (define-record-type %mix-input-state
    (fields (mutable muted?)
            (mutable paused?)
            (mutable solo?)))

  (define (%make-default-state)
    (make-%mix-input-state #f #f #f))

  ;; ======================================================
  ;; Mix record
  ;; ======================================================

  (define-record-type %mix
    (fields (immutable out)
            (mutable   inputs)      ;; alist: (ch . %mix-input-state)
            (immutable lock)        ;; guards inputs + solo-mode
            (immutable control-ch)  ;; size-1 reconfig signal
            (mutable   solo-mode))) ;; 'mute | 'pause

  (define (mix? x) (%mix? x))
  (define (mix-out m) (%mix-out m))
  (define (mix-solo-mode m) (%mix-solo-mode m))

  (define (make-mix out)
    (let ([m (make-%mix out '() (make-mutex) (make-channel 1) 'mute)])
      (fork-thread (lambda () (%mix-loop m)))
      m))

  ;; ======================================================
  ;; Internal helpers
  ;; ======================================================

  ;; Non-blocking poke of the control channel so a running alts!!
  ;; unblocks and re-reads the input set. Failures (channel full)
  ;; are fine — the loop re-reads anyway on each iteration.
  (define (%poke-control! m)
    (chan-try-put! (%mix-control-ch m) 'reconfigure))

  (define (%find-entry m ch)
    (assq ch (%mix-inputs m)))

  ;; Snapshot of current configuration under the lock. Returns
  ;; (list solo-mode inputs-alist) where inputs-alist is a shallow
  ;; copy so the loop can safely iterate without further locking.
  (define (%snapshot m)
    (with-mutex (%mix-lock m)
      (list (%mix-solo-mode m)
            (map (lambda (e) (cons (car e) (cdr e)))
                 (%mix-inputs m)))))

  ;; Given a snapshot, compute:
  ;;   active — channels to read from on this pass
  ;;   muted  — subset of `active` whose values should be dropped
  (define (%effective-sets snap)
    (let* ([solo-mode (car snap)]
           [inputs    (cadr snap)]
           [any-solo?
             (let loop ([xs inputs])
               (cond
                 [(null? xs) #f]
                 [(%mix-input-state-solo? (cdr (car xs))) #t]
                 [else (loop (cdr xs))]))])
      (let loop ([xs inputs] [active '()] [muted '()])
        (cond
          [(null? xs) (list (reverse active) (reverse muted))]
          [else
            (let* ([entry (car xs)]
                   [ch    (car entry)]
                   [st    (cdr entry)]
                   [paused? (%mix-input-state-paused? st)]
                   [muted?  (%mix-input-state-muted? st)]
                   [solo?   (%mix-input-state-solo? st)]
                   [eff-paused?
                    (or paused?
                        (and any-solo?
                             (not solo?)
                             (eq? solo-mode 'pause)))]
                   [eff-muted?
                    (or muted?
                        (and any-solo?
                             (not solo?)
                             (eq? solo-mode 'mute)))])
              (cond
                [eff-paused? (loop (cdr xs) active muted)]
                [eff-muted?  (loop (cdr xs) (cons ch active) (cons ch muted))]
                [else        (loop (cdr xs) (cons ch active) muted)]))]))))

  ;; Remove a closed input from the alist. Idempotent.
  (define (%unmix-internal! m ch)
    (with-mutex (%mix-lock m)
      (%mix-inputs-set! m
        (remp (lambda (e) (eq? (car e) ch)) (%mix-inputs m)))))

  ;; ======================================================
  ;; Fan-in loop
  ;; ======================================================
  ;;
  ;; Every iteration: snapshot state, compute active+muted sets,
  ;; alts!! over [control-ch + active inputs]. If nothing is tapped,
  ;; still block on control-ch so we wake up when someone admixes
  ;; the first input.

  (define (%mix-loop m)
    (let loop ()
      (let* ([snap   (%snapshot m)]
             [sets   (%effective-sets snap)]
             [active (car sets)]
             [specs  (cons (%mix-control-ch m) active)])
        (let* ([pick (alts!! specs)]
               [v    (car pick)]
               [ch   (cadr pick)])
          (cond
            ;; control-channel fired — just re-read state.
            [(eq? ch (%mix-control-ch m))
             (cond
               [(eof-object? v)
                ;; Caller closed the control channel — tear down.
                (void)]
               [else (loop)])]
            ;; an input closed — drop it from the alist and continue.
            [(eof-object? v)
             (%unmix-internal! m ch)
             (loop)]
            ;; normal value. We may have lost a race with a concurrent
            ;; unmix/toggle: the input was active when we snapshotted
            ;; but might have been removed, muted, or paused by the
            ;; time alts!! returned. Re-snapshot and drop values that
            ;; no longer belong to an effective-active, non-muted sub.
            [else
             (let* ([now-sets  (%effective-sets (%snapshot m))]
                    [now-active (car now-sets)]
                    [now-muted  (cadr now-sets)])
               (cond
                 [(not (memq ch now-active))
                  ;; input was removed or paused since we snapshotted
                  (loop)]
                 [(memq ch now-muted)
                  ;; input became muted since we snapshotted
                  (loop)]
                 [else
                  (guard (_ [else (void)])
                    (chan-put! (%mix-out m) v))
                  (loop)]))])))))

  ;; ======================================================
  ;; Public mutators
  ;; ======================================================

  (define (admix! m ch)
    (with-mutex (%mix-lock m)
      (unless (%find-entry m ch)
        (%mix-inputs-set! m
          (cons (cons ch (%make-default-state))
                (%mix-inputs m)))))
    (%poke-control! m)
    m)

  (define (unmix! m ch)
    (with-mutex (%mix-lock m)
      (%mix-inputs-set! m
        (remp (lambda (e) (eq? (car e) ch)) (%mix-inputs m))))
    (%poke-control! m)
    m)

  (define (unmix-all! m)
    (with-mutex (%mix-lock m)
      (%mix-inputs-set! m '()))
    (%poke-control! m)
    m)

  ;; toggle! m state-map
  ;;
  ;; `state-map` is an association list / hashtable mapping
  ;; `channel → flags-alist`, where flags-alist is an alist of
  ;; 'mute / 'pause / 'solo → boolean. Unspecified flags are left
  ;; unchanged. If a channel isn't currently in the mix, it is added
  ;; first (this matches Clojure's `toggle`, which accepts channels
  ;; you haven't explicitly admixed yet).
  ;;
  ;; Accepts either an alist or a hashtable for state-map.
  (define (toggle! m state-map)
    (let ([pairs (%state-map->pairs state-map)])
      (with-mutex (%mix-lock m)
        (for-each
          (lambda (pair)
            (let* ([ch    (car pair)]
                   [flags (cdr pair)]
                   [entry (assq ch (%mix-inputs m))])
              (unless entry
                (%mix-inputs-set! m
                  (cons (cons ch (%make-default-state)) (%mix-inputs m)))
                (set! entry (assq ch (%mix-inputs m))))
              (let ([st (cdr entry)])
                (%apply-flags! st flags))))
          pairs))
      (%poke-control! m)
      m))

  (define (%state-map->pairs x)
    (cond
      [(hashtable? x)
       (let-values ([(ks vs) (hashtable-entries x)])
         (let loop ([i 0] [acc '()])
           (cond
             [(= i (vector-length ks)) (reverse acc)]
             [else (loop (+ i 1)
                     (cons (cons (vector-ref ks i) (vector-ref vs i))
                           acc))])))]
      [(pair? x) x]
      [(null? x) '()]
      [else (error 'toggle! "state-map must be alist or hashtable" x)]))

  (define (%apply-flags! st flags)
    (let ([apply-one!
           (lambda (key val)
             (case key
               [(mute)  (%mix-input-state-muted?-set!  st val)]
               [(pause) (%mix-input-state-paused?-set! st val)]
               [(solo)  (%mix-input-state-solo?-set!   st val)]
               [else (error 'toggle! "unknown flag key" key)]))])
      (cond
        [(hashtable? flags)
         (let-values ([(ks vs) (hashtable-entries flags)])
           (let loop ([i 0])
             (unless (= i (vector-length ks))
               (apply-one! (vector-ref ks i) (vector-ref vs i))
               (loop (+ i 1)))))]
        [(list? flags)
         ;; accept either alist ((mute . #t) ...) or property list
         ;; (mute #t pause #f ...)
         (cond
           [(and (pair? flags) (pair? (car flags)))
            (for-each
              (lambda (p) (apply-one! (car p) (cdr p)))
              flags)]
           [else
            (let loop ([xs flags])
              (cond
                [(null? xs) (void)]
                [(null? (cdr xs))
                 (error 'toggle! "odd-length flags plist" flags)]
                [else (apply-one! (car xs) (cadr xs)) (loop (cddr xs))]))])]
        [else (error 'toggle! "flags must be alist, plist, or hashtable" flags)])))

  ;; (solo-mode! m 'mute)  — non-solo inputs get muted when any sub is solo
  ;; (solo-mode! m 'pause) — non-solo inputs get paused when any sub is solo
  (define (solo-mode! m mode)
    (unless (memq mode '(mute pause))
      (error 'solo-mode! "mode must be 'mute or 'pause" mode))
    (with-mutex (%mix-lock m)
      (%mix-solo-mode-set! m mode))
    (%poke-control! m)
    m)

) ;; end library
