#!chezscheme
;;; (std error conditions) — Structured error condition hierarchy
;;;
;;; Every subsystem gets its own condition type so that guard/catch clauses
;;; can pattern-match on error kind instead of parsing strings.
;;;
;;; Hierarchy:
;;;   &jerboa                          (root for all jerboa conditions)
;;;     &jerboa-network                (networking)
;;;       &connection-refused
;;;       &connection-timeout
;;;       &dns-failure
;;;       &tls-error
;;;       &network-read-error
;;;       &network-write-error
;;;     &jerboa-db                     (databases)
;;;       &db-connection-error
;;;       &db-query-error
;;;       &db-constraint-violation
;;;       &db-timeout
;;;     &jerboa-actor                  (actor system)
;;;       &actor-dead
;;;       &mailbox-full
;;;       &supervision-failure
;;;       &actor-timeout
;;;     &jerboa-resource               (resource management)
;;;       &resource-leak
;;;       &resource-already-closed
;;;       &resource-exhausted
;;;     &jerboa-timeout                (generic timeout)
;;;     &jerboa-serialization          (FASL / serialization)
;;;       &unsafe-deserialize
;;;       &serialize-size-exceeded
;;;     &jerboa-parse                  (parsers: JSON, XML, CSV, etc.)
;;;       &parse-depth-exceeded
;;;       &parse-size-exceeded
;;;       &parse-invalid-input

(library (std error conditions)
  (export
    ;; Root
    &jerboa make-jerboa-condition jerboa-condition?
    jerboa-condition-subsystem

    ;; Network
    &jerboa-network make-network-error network-error?
    network-error-address network-error-port-number

    &connection-refused make-connection-refused connection-refused?
    &connection-timeout make-connection-timeout connection-timeout?
    connection-timeout-seconds
    &dns-failure make-dns-failure dns-failure?
    dns-failure-hostname
    &tls-error make-tls-error tls-error?
    tls-error-reason
    &network-read-error make-network-read-error network-read-error?
    &network-write-error make-network-write-error network-write-error?

    ;; Database
    &jerboa-db make-db-error db-error?
    db-error-backend

    &db-connection-error make-db-connection-error db-connection-error?
    &db-query-error make-db-query-error db-query-error?
    db-query-error-sql
    &db-constraint-violation make-db-constraint-violation db-constraint-violation?
    db-constraint-violation-constraint
    &db-timeout make-db-timeout db-timeout?
    db-timeout-seconds

    ;; Actor
    &jerboa-actor make-actor-error actor-error?
    actor-error-actor-id

    &actor-dead make-actor-dead actor-dead?
    &mailbox-full make-mailbox-full mailbox-full?
    mailbox-full-capacity
    &supervision-failure make-supervision-failure supervision-failure?
    supervision-failure-child-id supervision-failure-reason
    &actor-timeout make-actor-timeout actor-timeout?
    actor-timeout-seconds

    ;; Resource
    &jerboa-resource make-resource-error resource-error?
    resource-error-resource-type

    &resource-leak make-resource-leak resource-leak?
    &resource-already-closed make-resource-already-closed resource-already-closed?
    &resource-exhausted make-resource-exhausted resource-exhausted?
    resource-exhausted-limit

    ;; Timeout (generic)
    &jerboa-timeout make-timeout-error timeout-error?
    timeout-error-seconds timeout-error-operation

    ;; Serialization
    &jerboa-serialization make-serialization-error serialization-error?

    &unsafe-deserialize make-unsafe-deserialize unsafe-deserialize?
    unsafe-deserialize-type-name
    &serialize-size-exceeded make-serialize-size-exceeded serialize-size-exceeded?
    serialize-size-exceeded-limit serialize-size-exceeded-actual

    ;; Parse
    &jerboa-parse make-parse-error parse-error?
    parse-error-format

    &parse-depth-exceeded make-parse-depth-exceeded parse-depth-exceeded?
    parse-depth-exceeded-limit parse-depth-exceeded-actual
    &parse-size-exceeded make-parse-size-exceeded parse-size-exceeded?
    parse-size-exceeded-limit parse-size-exceeded-actual
    &parse-invalid-input make-parse-invalid-input parse-invalid-input?
    parse-invalid-input-position

    ;; Helpers
    raise-network-error
    raise-db-error
    raise-timeout-error
    raise-parse-error)

  (import (chezscheme))

  ;; =========================================================================
  ;; Root condition
  ;; =========================================================================

  (define-condition-type &jerboa &serious
    make-jerboa-condition jerboa-condition?
    (subsystem jerboa-condition-subsystem))  ;; symbol: 'network, 'db, 'actor, etc.

  ;; =========================================================================
  ;; Network conditions
  ;; =========================================================================

  (define-condition-type &jerboa-network &jerboa
    make-network-error network-error?
    (address network-error-address)          ;; string or #f
    (port-number network-error-port-number)) ;; integer or #f

  (define-condition-type &connection-refused &jerboa-network
    make-connection-refused connection-refused?)

  (define-condition-type &connection-timeout &jerboa-network
    make-connection-timeout connection-timeout?
    (seconds connection-timeout-seconds))

  (define-condition-type &dns-failure &jerboa-network
    make-dns-failure dns-failure?
    (hostname dns-failure-hostname))

  (define-condition-type &tls-error &jerboa-network
    make-tls-error tls-error?
    (reason tls-error-reason))

  (define-condition-type &network-read-error &jerboa-network
    make-network-read-error network-read-error?)

  (define-condition-type &network-write-error &jerboa-network
    make-network-write-error network-write-error?)

  ;; =========================================================================
  ;; Database conditions
  ;; =========================================================================

  (define-condition-type &jerboa-db &jerboa
    make-db-error db-error?
    (backend db-error-backend))              ;; symbol: 'sqlite, 'postgresql, 'leveldb

  (define-condition-type &db-connection-error &jerboa-db
    make-db-connection-error db-connection-error?)

  (define-condition-type &db-query-error &jerboa-db
    make-db-query-error db-query-error?
    (sql db-query-error-sql))

  (define-condition-type &db-constraint-violation &jerboa-db
    make-db-constraint-violation db-constraint-violation?
    (constraint db-constraint-violation-constraint))

  (define-condition-type &db-timeout &jerboa-db
    make-db-timeout db-timeout?
    (seconds db-timeout-seconds))

  ;; =========================================================================
  ;; Actor conditions
  ;; =========================================================================

  (define-condition-type &jerboa-actor &jerboa
    make-actor-error actor-error?
    (actor-id actor-error-actor-id))         ;; integer or #f

  (define-condition-type &actor-dead &jerboa-actor
    make-actor-dead actor-dead?)

  (define-condition-type &mailbox-full &jerboa-actor
    make-mailbox-full mailbox-full?
    (capacity mailbox-full-capacity))

  (define-condition-type &supervision-failure &jerboa-actor
    make-supervision-failure supervision-failure?
    (child-id supervision-failure-child-id)
    (reason supervision-failure-reason))

  (define-condition-type &actor-timeout &jerboa-actor
    make-actor-timeout actor-timeout?
    (seconds actor-timeout-seconds))

  ;; =========================================================================
  ;; Resource conditions
  ;; =========================================================================

  (define-condition-type &jerboa-resource &jerboa
    make-resource-error resource-error?
    (resource-type resource-error-resource-type))  ;; symbol: 'file, 'socket, 'db, etc.

  (define-condition-type &resource-leak &jerboa-resource
    make-resource-leak resource-leak?)

  (define-condition-type &resource-already-closed &jerboa-resource
    make-resource-already-closed resource-already-closed?)

  (define-condition-type &resource-exhausted &jerboa-resource
    make-resource-exhausted resource-exhausted?
    (limit resource-exhausted-limit))

  ;; =========================================================================
  ;; Timeout (generic, for any subsystem)
  ;; =========================================================================

  (define-condition-type &jerboa-timeout &jerboa
    make-timeout-error timeout-error?
    (seconds timeout-error-seconds)
    (operation timeout-error-operation))     ;; symbol: 'tcp-read, 'db-query, etc.

  ;; =========================================================================
  ;; Serialization conditions
  ;; =========================================================================

  (define-condition-type &jerboa-serialization &jerboa
    make-serialization-error serialization-error?)

  (define-condition-type &unsafe-deserialize &jerboa-serialization
    make-unsafe-deserialize unsafe-deserialize?
    (type-name unsafe-deserialize-type-name))

  (define-condition-type &serialize-size-exceeded &jerboa-serialization
    make-serialize-size-exceeded serialize-size-exceeded?
    (limit serialize-size-exceeded-limit)
    (actual serialize-size-exceeded-actual))

  ;; =========================================================================
  ;; Parse conditions
  ;; =========================================================================

  (define-condition-type &jerboa-parse &jerboa
    make-parse-error parse-error?
    (format parse-error-format))             ;; symbol: 'json, 'xml, 'csv, 'fasl

  (define-condition-type &parse-depth-exceeded &jerboa-parse
    make-parse-depth-exceeded parse-depth-exceeded?
    (limit parse-depth-exceeded-limit)
    (actual parse-depth-exceeded-actual))

  (define-condition-type &parse-size-exceeded &jerboa-parse
    make-parse-size-exceeded parse-size-exceeded?
    (limit parse-size-exceeded-limit)
    (actual parse-size-exceeded-actual))

  (define-condition-type &parse-invalid-input &jerboa-parse
    make-parse-invalid-input parse-invalid-input?
    (position parse-invalid-input-position)) ;; integer offset or #f

  ;; =========================================================================
  ;; Convenience raisers — compound conditions with message
  ;; =========================================================================

  (define (raise-network-error type msg . args)
    ;; type is one of the make-* constructors for network subtypes
    ;; For simple cases, use make-network-error directly
    (raise (condition
            (make-network-error 'network #f #f)
            (make-message-condition (apply format #f msg args)))))

  (define (raise-db-error backend msg . args)
    (raise (condition
            (make-db-error 'db backend)
            (make-message-condition (apply format #f msg args)))))

  (define (raise-timeout-error seconds operation msg . args)
    (raise (condition
            (make-timeout-error 'timeout seconds operation)
            (make-message-condition (apply format #f msg args)))))

  (define (raise-parse-error fmt msg . args)
    (raise (condition
            (make-parse-error 'parse fmt)
            (make-message-condition (apply format #f msg args)))))

) ;; end library
