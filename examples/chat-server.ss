#!/usr/bin/env -S scheme --libdirs lib --script
;;; chat-server.ss — Multi-room chat server
;;;
;;; Demonstrates: channels, spawn, hash tables, format, concurrency
;;;
;;; Run: bin/jerboa run examples/chat-server.ss
;;;
;;; This is a demonstration of Jerboa's concurrency primitives.
;;; In production, you'd use websockets; here we simulate clients
;;; with threads to show the patterns.

(import (except (chezscheme)
          make-hash-table hash-table?
          sort sort! format printf fprintf
          iota 1+ 1-
          path-extension path-absolute?
          with-input-from-string with-output-to-string)
        (jerboa prelude)
        (std misc thread)
        (std misc channel))

;; --- Chat Room ---

(defstruct room (name members messages))

(def (make-chat-room name)
  (make-room name (make-hash-table) (make-channel)))

(def (room-join! room username output-ch)
  (hash-put! (room-members room) username output-ch)
  (room-broadcast! room "system"
    (format "~a joined #~a" username (room-name room))))

(def (room-leave! room username)
  (hash-remove! (room-members room) username)
  (room-broadcast! room "system"
    (format "~a left #~a" username (room-name room))))

(def (room-broadcast! room sender message)
  (let ([formatted (format "[#~a] ~a: ~a" (room-name room) sender message)])
    (hash-for-each
      (lambda (username ch)
        (channel-try-put ch formatted))
      (room-members room))))

;; --- Chat Server ---

(defstruct server (rooms))

(def (make-chat-server)
  (let ([s (make-server (make-hash-table))])
    ;; Create default rooms
    (server-create-room! s "general")
    (server-create-room! s "random")
    (server-create-room! s "tech")
    s))

(def (server-create-room! server name)
  (hash-put! (server-rooms server) name (make-chat-room name)))

(def (server-get-room server name)
  (hash-get (server-rooms server) name))

(def (server-list-rooms server)
  (hash-keys (server-rooms server)))

;; --- Simulated Client ---

(def (simulate-client server username actions)
  "Simulate a chat client performing a sequence of actions."
  (let ([output-ch (make-channel)])
    ;; Receiver thread — prints messages for this client
    (spawn/name (format "~a-receiver" username)
      (lambda ()
        (let loop ()
          (let ([msg (channel-try-get output-ch)])
            (when msg
              (printf "  [~a sees] ~a\n" username msg)))
          (thread-sleep! 0.05)
          (loop))))

    ;; Execute actions
    (for-each
      (lambda (action)
        (match action
          ((list 'join room-name)
           (let ([room (server-get-room server room-name)])
             (when room
               (room-join! room username output-ch)
               (printf "* ~a joined #~a\n" username room-name))))
          ((list 'say room-name message)
           (let ([room (server-get-room server room-name)])
             (when room
               (room-broadcast! room username message))))
          ((list 'leave room-name)
           (let ([room (server-get-room server room-name)])
             (when room
               (room-leave! room username)
               (printf "* ~a left #~a\n" username room-name))))
          ((list 'wait seconds)
           (thread-sleep! seconds))
          (_
           (printf "Unknown action: ~a\n" action))))
      actions)))

;; --- Run the simulation ---

(printf "=== Jerboa Chat Server Demo ===\n\n")
(printf "Rooms: #general #random #tech\n\n")

(define server (make-chat-server))

;; Simulate multiple clients concurrently
(define alice-thread
  (spawn/name "alice"
    (lambda ()
      (simulate-client server "Alice"
        '((join "general")
          (wait 0.1)
          (say "general" "Hey everyone!")
          (wait 0.2)
          (join "tech")
          (say "tech" "Anyone tried Jerboa?")
          (wait 0.3)
          (say "general" "Check out #tech!")
          (wait 0.2)
          (leave "general"))))))

(define bob-thread
  (spawn/name "bob"
    (lambda ()
      (simulate-client server "Bob"
        '((wait 0.05)
          (join "general")
          (wait 0.15)
          (say "general" "Hi Alice!")
          (wait 0.1)
          (join "tech")
          (wait 0.15)
          (say "tech" "Yes! It's great for concurrency")
          (wait 0.2)
          (leave "tech")
          (leave "general"))))))

(define carol-thread
  (spawn/name "carol"
    (lambda ()
      (simulate-client server "Carol"
        '((wait 0.2)
          (join "general")
          (say "general" "Hello from Carol!")
          (wait 0.3)
          (join "random")
          (say "random" "Anyone here?")
          (wait 0.2)
          (leave "random")
          (leave "general"))))))

;; Wait for all clients to finish
(thread-join! alice-thread)
(thread-join! bob-thread)
(thread-join! carol-thread)

;; Give receiver threads time to print
(thread-sleep! 0.2)

(printf "\n=== Chat session complete ===\n")
(printf "Rooms active: ~a\n" (string-join (server-list-rooms server) ", "))
