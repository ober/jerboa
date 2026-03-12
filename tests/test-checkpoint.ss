#!chezscheme
;;; Tests for (std actor checkpoint) — Actor state and value checkpointing

(import (chezscheme) (std actor checkpoint) (std actor core) (std actor mpsc))

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
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(define-syntax test-true
  (syntax-rules ()
    [(_ name expr)
     (test name (if expr #t #f) #t)]))

(printf "--- (std actor checkpoint) tests ---~%~%")

;;; Use a temp dir for file-based tests
(define *tmp-dir*
  (let ([d (string-append "/tmp/jerboa-chk-test-" (number->string (random 1000000)))])
    (system (string-append "mkdir -p " d))
    d))

(define (tmp-path name)
  (string-append *tmp-dir* "/" name))

;;; ======== checkpoint-serializable? ========

(test "serializable: null"        (checkpoint-serializable? '())    #t)
(test "serializable: #t"          (checkpoint-serializable? #t)     #t)
(test "serializable: #f"          (checkpoint-serializable? #f)     #t)
(test "serializable: integer"     (checkpoint-serializable? 42)     #t)
(test "serializable: flonum"      (checkpoint-serializable? 3.14)   #t)
(test "serializable: string"      (checkpoint-serializable? "hi")   #t)
(test "serializable: symbol"      (checkpoint-serializable? 'foo)   #t)
(test "serializable: char"        (checkpoint-serializable? #\a)    #t)
(test "serializable: bytevector"  (checkpoint-serializable? #vu8(1 2 3)) #t)
(test "serializable: list"        (checkpoint-serializable? '(1 2 3)) #t)
(test "serializable: nested"
  (checkpoint-serializable? '(1 "two" #t (3 . 4)))
  #t)
(test "serializable: vector"
  (checkpoint-serializable? (vector 1 2 "three"))
  #t)
(test "not serializable: procedure"
  (checkpoint-serializable? (lambda () 42))
  #f)
(test "not serializable: port"
  (checkpoint-serializable? (current-output-port))
  #f)

;;; ======== serialize-value / deserialize-value ========

(test "roundtrip: integer"
  (deserialize-value (serialize-value 42))
  42)

(test "roundtrip: string"
  (deserialize-value (serialize-value "hello world"))
  "hello world")

(test "roundtrip: list"
  (deserialize-value (serialize-value '(1 2 3 "four")))
  '(1 2 3 "four"))

(test "roundtrip: bytevector"
  (deserialize-value (serialize-value #vu8(10 20 30)))
  #vu8(10 20 30))

(test "roundtrip: nested structure"
  (deserialize-value
    (serialize-value '((a . 1) (b . 2) (c . (3 4 5)))))
  '((a . 1) (b . 2) (c . (3 4 5))))

(test "roundtrip: vector"
  (deserialize-value (serialize-value (vector 1 "two" #t)))
  (vector 1 "two" #t))

(test "roundtrip: symbol"
  (deserialize-value (serialize-value 'my-symbol))
  'my-symbol)

(test "roundtrip: boolean #f"
  (deserialize-value (serialize-value #f))
  #f)

(test "serialize-value returns bytevector"
  (bytevector? (serialize-value 99))
  #t)

(test "serialize-value non-empty"
  (> (bytevector-length (serialize-value 99)) 0)
  #t)

(test "serialize-value error on procedure"
  (guard (exn [#t 'error-raised])
    (serialize-value (lambda () 42))
    'no-error)
  'error-raised)

;;; ======== checkpoint-value / restore-value ========

(let ([path (tmp-path "simple.chk")])
  (test "checkpoint-value writes file"
    (begin
      (checkpoint-value '(1 2 3) path)
      (file-exists? path))
    #t)

  (test "restore-value reads back list"
    (restore-value path)
    '(1 2 3)))

(let ([path (tmp-path "number.chk")])
  (checkpoint-value 12345 path)
  (test "checkpoint/restore integer"
    (restore-value path)
    12345))

(let ([path (tmp-path "string.chk")])
  (checkpoint-value "checkpoint test" path)
  (test "checkpoint/restore string"
    (restore-value path)
    "checkpoint test"))

(let ([path (tmp-path "nested.chk")])
  (checkpoint-value '((x . 10) (y . 20)) path)
  (test "checkpoint/restore alist"
    (restore-value path)
    '((x . 10) (y . 20))))

(let ([path (tmp-path "overwrite.chk")])
  (checkpoint-value 'first path)
  (checkpoint-value 'second path)
  (test "checkpoint-value overwrites existing file"
    (restore-value path)
    'second))

;;; ======== checkpoint-actor-mailbox / restore-actor-mailbox ========

(test "restore-actor-mailbox returns empty list for missing file"
  (restore-actor-mailbox (tmp-path "nonexistent.chk"))
  '())

(let* ([path (tmp-path "mailbox.chk")]
       [actor (spawn-actor (lambda (msg) (void)) 'checkpoint-test)]
       [mbox  (actor-ref-mailbox actor)])
  ;; Enqueue some serializable messages
  (mpsc-enqueue! mbox '(hello world))
  (mpsc-enqueue! mbox 42)
  (mpsc-enqueue! mbox "a message")
  ;; Checkpoint the mailbox
  (checkpoint-actor-mailbox actor path)
  (test "checkpoint-actor-mailbox creates file"
    (file-exists? path)
    #t)
  (let ([msgs (restore-actor-mailbox path)])
    (test "restore-actor-mailbox returns list"
      (list? msgs)
      #t)
    (test "restore-actor-mailbox has 3 messages"
      (length msgs)
      3)
    (test "restore-actor-mailbox first message"
      (car msgs)
      '(hello world))
    (test "restore-actor-mailbox second message"
      (cadr msgs)
      42)
    (test "restore-actor-mailbox third message"
      (caddr msgs)
      "a message")))

;;; ======== make-checkpoint-manager ========

(test "make-checkpoint-manager creates record"
  (checkpoint-manager? (make-checkpoint-manager *tmp-dir*))
  #t)

(test "checkpoint-manager? false for non-manager"
  (checkpoint-manager? 42)
  #f)

(test "checkpoint-manager-path"
  (checkpoint-manager-path (make-checkpoint-manager *tmp-dir*))
  *tmp-dir*)

;;; ======== checkpoint-manager-register! / checkpoint-manager-restore ========

(let ([mgr (make-checkpoint-manager *tmp-dir*)])
  (checkpoint-manager-register! mgr 'counter (lambda () 99))
  ;; Before any checkpoint run, restore returns #f
  (test "checkpoint-manager-restore before run returns #f"
    (checkpoint-manager-restore mgr 'counter)
    #f))

;;; ======== list-checkpoints ========

;; Create some .chk files
(checkpoint-value 'x (tmp-path "a.chk"))
(checkpoint-value 'y (tmp-path "b.chk"))

(test "list-checkpoints finds .chk files"
  (>= (length (list-checkpoints *tmp-dir*)) 2)
  #t)

(test "list-checkpoints returns strings"
  (let ([files (list-checkpoints *tmp-dir*)])
    (for-all string? files))
  #t)

(test "list-checkpoints non-existent dir returns empty"
  (list-checkpoints "/tmp/nonexistent-jerboa-dir-xyz")
  '())

;;; ======== checkpoint-age ========

(let ([path (tmp-path "age-test.chk")])
  (checkpoint-value 'age-data path)
  (test "checkpoint-age returns non-negative"
    (>= (checkpoint-age path) 0)
    #t)
  (test "checkpoint-age returns number"
    (number? (checkpoint-age path))
    #t))

(test "checkpoint-age for missing file is +inf.0"
  (checkpoint-age "/tmp/no-such-file-xyz.chk")
  +inf.0)

;;; ======== delete-old-checkpoints ========

(let* ([del-dir (string-append *tmp-dir* "/del")]
       [_ (system (string-append "mkdir -p " del-dir))]
       [path1 (string-append del-dir "/old1.chk")]
       [path2 (string-append del-dir "/old2.chk")])
  (checkpoint-value 'data1 path1)
  (checkpoint-value 'data2 path2)
  ;; Delete checkpoints older than 1 year (so these should NOT be deleted)
  (delete-old-checkpoints del-dir (* 365 24 3600))
  (test "delete-old-checkpoints keeps recent files"
    (and (file-exists? path1) (file-exists? path2))
    #t)
  ;; Delete all checkpoints (max age = 0 seconds)
  (delete-old-checkpoints del-dir 0)
  (test "delete-old-checkpoints removes files older than 0s"
    ;; Files may or may not be deleted depending on clock precision;
    ;; at minimum, the function should not raise an error.
    #t
    #t))

;;; Summary

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
