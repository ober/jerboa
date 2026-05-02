#!chezscheme
;;; Tests for (std security seatbelt) — macOS Seatbelt sandbox profiles

(import (chezscheme)
        (std security seatbelt))

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

(printf "--- Seatbelt Tests ---~%~%")

;; ========== Availability ==========

(printf "-- Availability --~%")

(test "seatbelt-available? returns boolean"
  (boolean? (seatbelt-available?))
  #t)

;; On non-macOS, seatbelt-available? should return #f
(let ([mt (symbol->string (machine-type))])
  (define (has-osx?)
    (let loop ([i 0])
      (cond
        [(> (+ i 3) (string-length mt)) #f]
        [(string=? (substring mt i (+ i 3)) "osx") #t]
        [else (loop (+ i 1))])))
  (unless (has-osx?)
    (test "seatbelt-available? is #f on non-macOS"
      (seatbelt-available?)
      #f)))

;; ========== Profile builders ==========

(printf "~%-- Profile builders --~%")

(test "seatbelt-compute-only-profile returns string"
  (string? (seatbelt-compute-only-profile))
  #t)

(test "seatbelt-compute-only-profile contains (version 1)"
  (let ([p (seatbelt-compute-only-profile)])
    (and (string? p)
         (let loop ([i 0])
           (cond
             [(> (+ i 11) (string-length p)) #f]
             [(string=? (substring p i (+ i 11)) "(version 1)") #t]
             [else (loop (+ i 1))]))))
  #t)

(test "seatbelt-compute-only-profile contains (deny default)"
  (let ([p (seatbelt-compute-only-profile)])
    (and (string? p)
         (let loop ([i 0])
           (cond
             [(> (+ i 14) (string-length p)) #f]
             [(string=? (substring p i (+ i 14)) "(deny default)") #t]
             [else (loop (+ i 1))]))))
  #t)

(test "seatbelt-read-only-profile returns string"
  (string? (seatbelt-read-only-profile "/tmp"))
  #t)

(test "seatbelt-read-only-profile includes user path"
  (let ([p (seatbelt-read-only-profile "/tmp")])
    (and (string? p)
         (let loop ([i 0])
           (cond
             [(> (+ i 6) (string-length p)) #f]
             [(string=? (substring p i (+ i 6)) "/tmp\")") #t]
             [else (loop (+ i 1))]))))
  #t)

(test "seatbelt-no-network-profile returns string"
  (string? (seatbelt-no-network-profile))
  #t)

(test "seatbelt-no-write-profile returns string"
  (string? (seatbelt-no-write-profile))
  #t)

;; ========== Cage profile builder ==========

(printf "~%-- Cage profile builder --~%")

(define (contains? haystack needle)
  (let ([h-len (string-length haystack)]
        [n-len (string-length needle)])
    (let loop ([i 0])
      (cond
        [(> (+ i n-len) h-len) #f]
        [(string=? (substring haystack i (+ i n-len)) needle) #t]
        [else (loop (+ i 1))]))))

(test "seatbelt-cage-profile returns string"
  (string? (seatbelt-cage-profile 'read-write: '("/tmp")))
  #t)

(test "seatbelt-cage-profile starts with (version 1)"
  (let ([p (seatbelt-cage-profile 'read-write: '("/tmp"))])
    (and (string? p)
         (>= (string-length p) 11)
         (string=? (substring p 0 11) "(version 1)")))
  #t)

(test "seatbelt-cage-profile denies by default"
  (contains? (seatbelt-cage-profile 'read-write: '("/tmp"))
             "(deny default)")
  #t)

(test "seatbelt-cage-profile includes read-write path"
  (contains? (seatbelt-cage-profile 'read-write: '("/tmp"))
             "/tmp")
  #t)

(test "seatbelt-cage-profile read-write grants both read and write"
  (let ([p (seatbelt-cage-profile 'read-write: '("/tmp"))])
    (and (contains? p "file-read*")
         (contains? p "file-write*")))
  #t)

(test "seatbelt-cage-profile network: #t allows network*"
  (contains? (seatbelt-cage-profile 'read-only: '("/usr") 'network: #t)
             "(allow network*)")
  #t)

(test "seatbelt-cage-profile network: #f omits network*"
  (not (contains? (seatbelt-cage-profile 'read-only: '("/usr") 'network: #f)
                  "(allow network*)"))
  #t)

(test "seatbelt-cage-profile execute: adds process-exec*"
  (contains? (seatbelt-cage-profile
               'read-only: '("/usr/lib")
               'execute:   '("/usr/bin"))
             "process-exec*")
  #t)

(test "seatbelt-cage-profile rejects unknown keyword"
  (guard (exn [#t #t])
    (seatbelt-cage-profile 'bogus: '("/tmp"))
    #f)
  #t)

(test "seatbelt-macos-system-read-paths is a list"
  (list? seatbelt-macos-system-read-paths)
  #t)

(test "seatbelt-macos-system-execute-paths is a list"
  (list? seatbelt-macos-system-execute-paths)
  #t)

;; ========== Error handling for non-macOS ==========

(printf "~%-- Error handling --~%")

(unless (seatbelt-available?)
  (test "seatbelt-install! raises on non-macOS"
    (guard (exn [#t #t])
      (seatbelt-install! 'pure-computation)
      #f)
    #t)

  (test "seatbelt-install-profile! raises on non-macOS"
    (guard (exn [#t #t])
      (seatbelt-install-profile! "(version 1)(deny default)")
      #f)
    #t))

;; ========== Summary ==========

(printf "~%Seatbelt tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
