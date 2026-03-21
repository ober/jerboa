#!chezscheme
;;; (std security capability) — Capability-based security model
;;;
;;; Track 29: Programs declare required capabilities (filesystem, network,
;;; process, environment) and the runtime enforces them. Works in static
;;; binaries without kernel sandbox support.
;;;
;;; HARDENED: Capabilities use sealed opaque record types (unforgeable)
;;; and CSPRNG nonces (unpredictable).

(library (std security capability)
  (export
    ;; Capability types
    capability?
    capability-type capability-permissions

    ;; Filesystem capabilities
    make-fs-capability
    fs-read? fs-write? fs-execute?
    fs-allowed-path?

    ;; Network capabilities
    make-net-capability
    net-connect? net-listen? net-allowed-host?

    ;; Process capabilities
    make-process-capability
    process-spawn? process-signal?

    ;; Environment capabilities
    make-env-capability
    env-read? env-write?

    ;; Capability context
    with-capabilities
    current-capabilities
    check-capability!
    &capability-violation make-capability-violation capability-violation?
    capability-violation-type capability-violation-detail

    ;; Attenuation
    attenuate-capability)

  (import (chezscheme)
          (std crypto random))

  ;; ========== Capability Record ==========
  ;;
  ;; Sealed: cannot be subtyped.
  ;; Opaque: cannot be inspected via record-type-descriptor.
  ;; Constructor NOT exported: only this module can mint capabilities.

  (define-record-type (%capability %make-capability capability?)
    (sealed #t)
    (opaque #t)
    (nongenerative std-security-capability)
    (fields
      (immutable nonce %capability-nonce)
      (immutable type  capability-type)
      (immutable permissions capability-permissions)))

  (define (make-cap type perms)
    (%make-capability (random-bytes 16) type perms))

  ;; ========== Capability Violation Condition ==========

  (define-condition-type &capability-violation &violation
    make-capability-violation capability-violation?
    (type capability-violation-type)
    (detail capability-violation-detail))

  ;; ========== Filesystem Capability ==========

  (define (make-fs-capability . opts)
    ;; Options: read: #t/#f, write: #t/#f, execute: #t/#f, paths: '("/path" ...)
    (make-cap 'filesystem
      (list (cons 'read    (extract-opt opts 'read: #t))
            (cons 'write   (extract-opt opts 'write: #f))
            (cons 'execute (extract-opt opts 'execute: #f))
            (cons 'paths   (extract-opt opts 'paths: '("/"))))))

  (define (fs-read? cap)
    (and (eq? (capability-type cap) 'filesystem)
         (cdr (assq 'read (capability-permissions cap)))))

  (define (fs-write? cap)
    (and (eq? (capability-type cap) 'filesystem)
         (cdr (assq 'write (capability-permissions cap)))))

  (define (fs-execute? cap)
    (and (eq? (capability-type cap) 'filesystem)
         (cdr (assq 'execute (capability-permissions cap)))))

  (define (fs-allowed-path? cap path)
    ;; Check if path is under one of the allowed paths
    (and (eq? (capability-type cap) 'filesystem)
         (let ([allowed (cdr (assq 'paths (capability-permissions cap)))]
               [canonical (canonicalize-path path)])
           (exists (lambda (p) (string-prefix? p canonical)) allowed))))

  ;; FFI binding for realpath(3) — resolves symlinks and . / ..
  (define c-realpath
    (guard (exn [#t #f])
      (let ([f (foreign-procedure "realpath" (string void*) string)])
        (lambda (path) (f path 0)))))

  (define (canonicalize-path path)
    ;; HARDENED: Uses realpath(3) to resolve symlinks when available.
    ;; Falls back to string-based canonicalization if FFI fails.
    (or (and c-realpath
             (guard (exn [#t #f])
               (c-realpath path)))
        ;; Fallback: string-based canonicalization (no symlink resolution)
        (canonicalize-path/string-only path)))

  (define (canonicalize-path/string-only path)
    ;; String-only path canonicalization (resolve . and ..)
    (let ([parts (string-split path #\/)]
          [result '()])
      (let lp ([parts parts] [stack '()])
        (cond
          [(null? parts)
           (let ([r (reverse stack)])
             (if (null? r) "/"
               (apply string-append
                      (map (lambda (p) (string-append "/" p)) r))))]
          [(string=? (car parts) ".") (lp (cdr parts) stack)]
          [(string=? (car parts) "..")
           (lp (cdr parts) (if (pair? stack) (cdr stack) stack))]
          [(string=? (car parts) "") (lp (cdr parts) stack)]
          [else (lp (cdr parts) (cons (car parts) stack))]))))

  (define (string-prefix? prefix str)
    (let ([plen (string-length prefix)]
          [slen (string-length str)])
      (and (<= plen slen)
           (string=? (substring str 0 plen) prefix))))

  (define (string-split str ch)
    (let ([n (string-length str)])
      (let lp ([i 0] [start 0] [result '()])
        (cond
          [(>= i n)
           (reverse (cons (substring str start n) result))]
          [(char=? (string-ref str i) ch)
           (lp (+ i 1) (+ i 1)
               (cons (substring str start i) result))]
          [else (lp (+ i 1) start result)]))))

  ;; ========== Network Capability ==========

  (define (make-net-capability . opts)
    (make-cap 'network
      (list (cons 'connect  (extract-opt opts 'connect: #f))
            (cons 'listen   (extract-opt opts 'listen: #f))
            (cons 'hosts    (extract-opt opts 'hosts: '())))))

  (define (net-connect? cap)
    (and (eq? (capability-type cap) 'network)
         (cdr (assq 'connect (capability-permissions cap)))))

  (define (net-listen? cap)
    (and (eq? (capability-type cap) 'network)
         (cdr (assq 'listen (capability-permissions cap)))))

  (define (net-allowed-host? cap host)
    ;; HARDENED: Empty hosts list = NO hosts allowed (default deny).
    ;; Use hosts: '("*") for explicit wildcard access.
    (and (eq? (capability-type cap) 'network)
         (let ([hosts (cdr (assq 'hosts (capability-permissions cap)))])
           (cond
             [(null? hosts) #f]                  ;; empty = none allowed
             [(member "*" hosts) #t]             ;; explicit wildcard
             [else (member host hosts)]))))

  ;; ========== Process Capability ==========

  (define (make-process-capability . opts)
    (make-cap 'process
      (list (cons 'spawn  (extract-opt opts 'spawn: #f))
            (cons 'signal (extract-opt opts 'signal: #f)))))

  (define (process-spawn? cap)
    (and (eq? (capability-type cap) 'process)
         (cdr (assq 'spawn (capability-permissions cap)))))

  (define (process-signal? cap)
    (and (eq? (capability-type cap) 'process)
         (cdr (assq 'signal (capability-permissions cap)))))

  ;; ========== Environment Capability ==========

  (define (make-env-capability . opts)
    (make-cap 'environment
      (list (cons 'read  (extract-opt opts 'read: #t))
            (cons 'write (extract-opt opts 'write: #f)))))

  (define (env-read? cap)
    (and (eq? (capability-type cap) 'environment)
         (cdr (assq 'read (capability-permissions cap)))))

  (define (env-write? cap)
    (and (eq? (capability-type cap) 'environment)
         (cdr (assq 'write (capability-permissions cap)))))

  ;; ========== Capability Context ==========

  (define current-capabilities
    (make-thread-parameter '()))

  (define (check-capability! type permission . detail)
    ;; Check if current context has the required capability.
    ;; Raises &capability-violation if not.
    (let ([caps (current-capabilities)])
      (unless (exists
                (lambda (cap)
                  (and (eq? (capability-type cap) type)
                       (let ([perms (capability-permissions cap)])
                         (cdr (or (assq permission perms) '(#f . #f))))))
                caps)
        (raise (condition
                 (make-capability-violation type
                   (if (pair? detail) (car detail) ""))
                 (make-message-condition
                   (format "capability denied: ~a ~a" type permission)))))))

  (define (with-capabilities caps thunk)
    ;; Execute thunk with the given capabilities.
    ;; If already in a capability context, the new caps must be
    ;; a subset of the current caps (monotonic restriction).
    (let ([existing (current-capabilities)])
      (let ([effective (if (null? existing)
                        caps
                        (intersect-capabilities existing caps))])
        (parameterize ([current-capabilities effective])
          (thunk)))))

  (define (intersect-capabilities parent child)
    ;; Each child capability must be covered by a parent capability
    ;; of the same type. HARDENED: Per-permission intersection —
    ;; booleans are ANDed, lists are set-intersected.
    (filter-map
      (lambda (c)
        (let ([matching-parent
               (find (lambda (p) (eq? (capability-type p) (capability-type c)))
                     parent)])
          (and matching-parent
               (%attenuate-to-parent-bounds matching-parent c))))
      child))

  (define (filter-map f lst)
    (let loop ([lst lst] [acc '()])
      (if (null? lst) (reverse acc)
        (let ([result (f (car lst))])
          (loop (cdr lst) (if result (cons result acc) acc))))))

  (define (%attenuate-to-parent-bounds parent-cap child-cap)
    ;; Create a new capability whose permissions are the intersection
    ;; of parent and child: booleans ANDed, lists set-intersected.
    (let ([parent-perms (capability-permissions parent-cap)]
          [child-perms  (capability-permissions child-cap)])
      (make-cap (capability-type child-cap)
        (map (lambda (child-perm)
               (let* ([key (car child-perm)]
                      [child-val (cdr child-perm)]
                      [parent-pair (assq key parent-perms)]
                      [parent-val (if parent-pair (cdr parent-pair) #f)])
                 (cons key
                   (cond
                     ;; Both booleans: AND them (child can only restrict)
                     [(and (boolean? child-val) (boolean? parent-val))
                      (and child-val parent-val)]
                     ;; Both lists: intersect (child can only narrow)
                     [(and (list? child-val) (list? parent-val))
                      (filter (lambda (x) (member x parent-val)) child-val)]
                     ;; Parent is #f (denied): always deny
                     [(eq? parent-val #f) #f]
                     ;; Fallback: use parent's value (more restrictive)
                     [else parent-val]))))
             child-perms))))

  ;; ========== Attenuation ==========

  (define (attenuate-capability cap . restrictions)
    ;; Create a new capability with tighter restrictions.
    ;; Only restricts — never adds permissions.
    (let ([type (capability-type cap)]
          [perms (capability-permissions cap)])
      (make-cap type
        (map (lambda (perm)
               (let ([key (car perm)]
                     [val (cdr perm)])
                 (let ([restriction (extract-opt restrictions
                                     (string->symbol
                                       (string-append (symbol->string key) ":"))
                                     val)])
                   (cons key
                         (if (boolean? val)
                           (and val restriction)  ;; can only restrict to #f
                           (if (list? val)
                             ;; For lists (like paths), intersect
                             (if (list? restriction)
                               (filter (lambda (x) (member x val)) restriction)
                               val)
                             restriction))))))
             perms))))

  (define (extract-opt opts key default)
    (let lp ([opts opts])
      (cond
        [(null? opts) default]
        [(and (pair? opts) (pair? (cdr opts)) (eq? (car opts) key))
         (cadr opts)]
        [(pair? opts) (lp (cdr opts))]
        [else default])))

  ) ;; end library
