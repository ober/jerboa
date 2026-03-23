#!chezscheme
;;; Tests for (std security capsicum) — FreeBSD Capsicum capability mode

(import (chezscheme)
        (std security capsicum))

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

(printf "--- Capsicum Tests ---~%~%")

;; ========== Availability ==========

(printf "-- Availability --~%")

(test "capsicum-available? returns boolean"
  (boolean? (capsicum-available?))
  #t)

;; On non-FreeBSD, capsicum-available? should return #f
(let ([mt (symbol->string (machine-type))])
  (define (has-fb?)
    (let loop ([i 0])
      (cond
        [(> (+ i 2) (string-length mt)) #f]
        [(string=? (substring mt i (+ i 2)) "fb") #t]
        [else (loop (+ i 1))])))
  (unless (has-fb?)
    (test "capsicum-available? is #f on non-FreeBSD"
      (capsicum-available?)
      #f)))

;; ========== Capability mode query ==========

(printf "~%-- Capability mode --~%")

(test "capsicum-in-capability-mode? returns boolean"
  (boolean? (capsicum-in-capability-mode?))
  #t)

(test "not in capability mode initially"
  (capsicum-in-capability-mode?)
  #f)

;; ========== Rights constants ==========

(printf "~%-- Rights constants --~%")

(test "capsicum-right-read is positive integer"
  (and (integer? capsicum-right-read)
       (> capsicum-right-read 0))
  #t)

(test "capsicum-right-write is positive integer"
  (and (integer? capsicum-right-write)
       (> capsicum-right-write 0))
  #t)

(test "capsicum-right-read != capsicum-right-write"
  (not (= capsicum-right-read capsicum-right-write))
  #t)

;; ========== Presets ==========

(printf "~%-- Presets --~%")

(test "capsicum-compute-only-preset returns alist"
  (let ([preset (capsicum-compute-only-preset 5)])
    (and (list? preset)
         (pair? preset)
         (pair? (car preset))))
  #t)

(test "capsicum-compute-only-preset includes pipe fd"
  (let ([preset (capsicum-compute-only-preset 7)])
    (assv 7 preset))
  '(7 . (write fstat)))

(test "capsicum-compute-only-preset includes stdin"
  (let ([preset (capsicum-compute-only-preset 5)])
    (assv 0 preset))
  '(0 . (read fstat)))

(test "capsicum-compute-only-preset includes stdout"
  (let ([preset (capsicum-compute-only-preset 5)])
    (assv 1 preset))
  '(1 . (write fstat)))

(test "capsicum-io-only-preset includes extra fds"
  (let ([preset (capsicum-io-only-preset 5 '((10 . (read fstat seek))))])
    (assv 10 preset))
  '(10 . (read fstat seek)))

(test "capsicum-io-only-preset includes compute-only fds"
  (let ([preset (capsicum-io-only-preset 5 '((10 . (read))))])
    (and (assv 0 preset)   ;; stdin
         (assv 1 preset)   ;; stdout
         (assv 5 preset)   ;; pipe
         (assv 10 preset)  ;; extra
         #t))
  #t)

;; ========== Error handling for non-FreeBSD ==========

(printf "~%-- Error handling --~%")

(unless (capsicum-available?)
  (test "capsicum-enter! raises on non-FreeBSD"
    (guard (exn [#t #t])
      (capsicum-enter!)
      #f)
    #t)

  (test "capsicum-limit-fd! raises on non-FreeBSD"
    (guard (exn [#t #t])
      (capsicum-limit-fd! 0 '(read))
      #f)
    #t)

  (test "capsicum-apply-preset! raises on non-FreeBSD"
    (guard (exn [#t #t])
      (capsicum-apply-preset! '((0 . (read fstat))))
      #f)
    #t)

  (test "capsicum-open-path raises on non-FreeBSD"
    (guard (exn [#t #t])
      (capsicum-open-path "/tmp" '(read fstat))
      #f)
    #t))

;; ========== Summary ==========

(printf "~%Capsicum tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
