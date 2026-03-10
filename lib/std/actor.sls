#!chezscheme
;;; (std actor) — Facade re-exporting all actor system layers
;;;
;;; Provides a single import for common use:
;;;   (import (std actor))
;;;
;;; For distributed transport, also import separately:
;;;   (import (std actor) (std actor transport))

(library (std actor)
  (export
    ;; Core (Layer 3)
    spawn-actor spawn-actor/linked
    send self actor-id actor-alive? actor-kill! actor-wait!
    actor-ref? actor-ref-id actor-ref-node actor-ref-name
    actor-ref-links actor-ref-links-set!
    actor-ref-monitors actor-ref-monitors-set!
    set-dead-letter-handler!
    set-remote-send-handler!
    lookup-local-actor
    make-remote-actor-ref

    ;; Protocol (Layer 4)
    defprotocol with-ask-context
    ask ask-sync tell reply reply-to

    ;; Supervision (Layer 5)
    make-child-spec child-spec?
    child-spec-id child-spec-start-thunk
    child-spec-restart child-spec-shutdown child-spec-type
    start-supervisor
    supervisor-which-children supervisor-count-children
    supervisor-terminate-child! supervisor-restart-child!
    supervisor-start-child! supervisor-delete-child!

    ;; Registry (Layer 6)
    start-registry! register! unregister! whereis registered-names
    registry-actor

    ;; Scheduler (Layer 2)
    make-scheduler scheduler?
    scheduler-start! scheduler-stop!
    scheduler-submit! scheduler-worker-count
    current-scheduler default-scheduler
    cpu-count
    set-actor-scheduler!
  )

  (import
    (std actor core)
    (std actor protocol)
    (std actor supervisor)
    (std actor registry)
    (std actor scheduler))

  ) ;; end library
