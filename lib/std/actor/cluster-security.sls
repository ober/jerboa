#!chezscheme
;;; (std actor cluster-security) — Distributed Actor Security
;;;
;;; D1: Encrypted transport config (TLS for inter-node)
;;; D2: Message authentication and replay protection
;;; D3: Capability delegation across nodes
;;; D4: Cluster security policies

(library (std actor cluster-security)
  (export
    ;; D1: Transport encryption config
    make-node-tls-config
    node-tls-config?
    node-tls-config-certificate
    node-tls-config-private-key
    node-tls-config-ca-certificate
    node-tls-config-verify-peer?

    ;; D2: Authenticated messages
    make-authenticated-message
    authenticated-message?
    authenticated-message-sender
    authenticated-message-sequence
    authenticated-message-timestamp
    authenticated-message-payload
    authenticated-message-hmac
    verify-message-auth
    make-replay-window
    replay-window?
    replay-window-check!

    ;; D3: Capability delegation
    make-delegation-token
    delegation-token?
    delegation-token-capability-type
    delegation-token-permissions
    delegation-token-target-node
    delegation-token-expiry
    verify-delegation-token

    ;; D4: Cluster policies
    make-cluster-policy
    cluster-policy?
    cluster-policy-auth-method
    cluster-policy-node-roles
    cluster-policy-role-permissions
    cluster-policy-allowed-connections
    cluster-policy-max-message-rate
    cluster-policy-max-message-size
    node-has-permission?
    connection-allowed?)

  (import (chezscheme))

  ;; ========== D1: Transport Encryption Config ==========

  (define-record-type (node-tls-config %make-node-tls-config node-tls-config?)
    (sealed #t)
    (fields
      (immutable certificate node-tls-config-certificate)
      (immutable private-key node-tls-config-private-key)
      (immutable ca-certificate node-tls-config-ca-certificate)
      (immutable verify-peer? node-tls-config-verify-peer?)))

  (define (make-node-tls-config . opts)
    (let loop ([o opts] [cert #f] [key #f] [ca #f] [verify #t])
      (if (or (null? o) (null? (cdr o)))
        (%make-node-tls-config cert key ca verify)
        (let ([k (car o)] [v (cadr o)])
          (loop (cddr o)
                (if (eq? k 'certificate:) v cert)
                (if (eq? k 'private-key:) v key)
                (if (eq? k 'ca-certificate:) v ca)
                (if (eq? k 'verify-peer:) v verify))))))

  ;; ========== D2: Message Authentication ==========

  (define-record-type (authenticated-message %make-auth-msg authenticated-message?)
    (sealed #t)
    (fields
      (immutable sender authenticated-message-sender)
      (immutable sequence authenticated-message-sequence)
      (immutable timestamp authenticated-message-timestamp)
      (immutable payload authenticated-message-payload)
      (immutable hmac authenticated-message-hmac)))

  (define (make-authenticated-message sender sequence payload hmac-key)
    ;; Create an authenticated message with HMAC.
    (let* ([ts (time-second (current-time 'time-utc))]
           [data (format #f "~a|~a|~a|~a" sender sequence ts payload)]
           [hmac (simple-hmac hmac-key data)])
      (%make-auth-msg sender sequence ts payload hmac)))

  (define (verify-message-auth msg hmac-key)
    ;; Verify the HMAC on an authenticated message.
    (let* ([data (format #f "~a|~a|~a|~a"
                         (authenticated-message-sender msg)
                         (authenticated-message-sequence msg)
                         (authenticated-message-timestamp msg)
                         (authenticated-message-payload msg))]
           [expected (simple-hmac hmac-key data)])
      (string=? expected (authenticated-message-hmac msg))))

  ;; Simple HMAC using XOR-based keyed hash (placeholder for real HMAC-SHA256)
  (define (simple-hmac key data)
    (let* ([key-bv (string->utf8 key)]
           [data-bv (string->utf8 data)]
           [key-len (bytevector-length key-bv)]
           [data-len (bytevector-length data-bv)]
           [h #xcbf29ce484222325]
           [prime #x100000001b3]
           [mask #xffffffffffffffff])
      ;; FNV-1a with key prefix
      (let loop ([i 0] [hash h])
        (if (= i key-len)
          ;; Continue with data
          (let loop2 ([j 0] [hash2 hash])
            (if (= j data-len)
              (number->string hash2 16)
              (loop2 (+ j 1)
                     (bitwise-and
                       (* (bitwise-xor hash2 (bytevector-u8-ref data-bv j)) prime)
                       mask))))
          (loop (+ i 1)
                (bitwise-and
                  (* (bitwise-xor hash (bytevector-u8-ref key-bv i)) prime)
                  mask))))))

  ;; ========== Replay Window ==========

  (define-record-type (replay-window %make-replay-window replay-window?)
    (sealed #t)
    (fields
      (immutable size %replay-window-size)
      (mutable seen %replay-window-seen %replay-window-set-seen!)  ;; hashtable: sender -> last-seq
      (mutable mutex %replay-window-mutex %replay-window-set-mutex!)))

  (define (make-replay-window . opts)
    (let ([size (if (pair? opts) (car opts) 1024)])
      (%make-replay-window size (make-hashtable equal-hash equal?) (make-mutex))))

  (define (replay-window-check! window msg)
    ;; Check if message is a replay. Returns #t if OK, #f if replay.
    (with-mutex (%replay-window-mutex window)
      (let* ([sender (authenticated-message-sender msg)]
             [seq (authenticated-message-sequence msg)]
             [last-seq (hashtable-ref (%replay-window-seen window) sender -1)])
        (cond
          [(<= seq last-seq) #f]  ;; replay or out-of-order
          [else
           (hashtable-set! (%replay-window-seen window) sender seq)
           #t]))))

  ;; ========== D3: Capability Delegation ==========

  (define-record-type (delegation-token %make-delegation-token delegation-token?)
    (sealed #t)
    (fields
      (immutable capability-type delegation-token-capability-type)
      (immutable permissions delegation-token-permissions)    ;; list of symbols
      (immutable target-node delegation-token-target-node)   ;; string
      (immutable expiry delegation-token-expiry)             ;; epoch seconds or #f
      (immutable signature delegation-token-signature)))     ;; string

  (define (make-delegation-token cap-type permissions target-node signing-key . opts)
    (let ([expiry (if (pair? opts) (car opts) #f)])
      (let* ([data (format #f "~a|~a|~a|~a" cap-type permissions target-node
                           (or expiry "none"))]
             [sig (simple-hmac signing-key data)])
        (%make-delegation-token cap-type permissions target-node expiry sig))))

  (define (verify-delegation-token token signing-key)
    ;; Verify token signature and check expiry.
    (let* ([data (format #f "~a|~a|~a|~a"
                         (delegation-token-capability-type token)
                         (delegation-token-permissions token)
                         (delegation-token-target-node token)
                         (or (delegation-token-expiry token) "none"))]
           [expected-sig (simple-hmac signing-key data)]
           [now (time-second (current-time 'time-utc))])
      (and (string=? expected-sig (delegation-token-signature token))
           (or (not (delegation-token-expiry token))
               (> (delegation-token-expiry token) now)))))

  ;; ========== D4: Cluster Policies ==========

  (define-record-type (cluster-policy %make-cluster-policy cluster-policy?)
    (sealed #t)
    (fields
      (immutable auth-method cluster-policy-auth-method)
      (immutable node-roles cluster-policy-node-roles)             ;; alist: (node . role)
      (immutable role-permissions cluster-policy-role-permissions)  ;; alist: (role . (perm ...))
      (immutable allowed-connections cluster-policy-allowed-connections) ;; alist: (role . (role ...))
      (immutable max-message-rate cluster-policy-max-message-rate)
      (immutable max-message-size cluster-policy-max-message-size)))

  (define (make-cluster-policy . opts)
    (let loop ([o opts] [auth 'mutual-tls] [roles '()] [perms '()] [conns '()]
               [rate 10000] [size (* 1 1024 1024)])
      (if (or (null? o) (null? (cdr o)))
        (%make-cluster-policy auth roles perms conns rate size)
        (let ([k (car o)] [v (cadr o)])
          (loop (cddr o)
                (if (eq? k 'auth-method:) v auth)
                (if (eq? k 'node-roles:) v roles)
                (if (eq? k 'role-permissions:) v perms)
                (if (eq? k 'allowed-connections:) v conns)
                (if (eq? k 'max-message-rate:) v rate)
                (if (eq? k 'max-message-size:) v size))))))

  (define (node-has-permission? policy node-name permission)
    ;; Check if a node has a specific permission based on its role.
    (let ([role-entry (assoc node-name (cluster-policy-node-roles policy))])
      (and role-entry
           (let ([perm-entry (assq (cdr role-entry)
                                   (cluster-policy-role-permissions policy))])
             (and perm-entry
                  (memq permission (cdr perm-entry))
                  #t)))))

  (define (connection-allowed? policy from-node to-node)
    ;; Check if a connection between two nodes is allowed.
    (let ([from-role (assoc from-node (cluster-policy-node-roles policy))]
          [to-role (assoc to-node (cluster-policy-node-roles policy))])
      (and from-role to-role
           (let ([allowed (assq (cdr from-role)
                                (cluster-policy-allowed-connections policy))])
             (and allowed
                  (memq (cdr to-role) (cdr allowed))
                  #t)))))

) ;; end library
