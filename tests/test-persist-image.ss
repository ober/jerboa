#!chezscheme
;;; Tests for (std persist image) — Image-Based Development

(import (chezscheme) (std persist image))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn)
                           (condition-message exn)
                           exn))])
       (let ([got expr])
         (if (equal? got expected)
             (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
             (begin (set! fail (+ fail 1))
                    (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(define-syntax test-true
  (syntax-rules ()
    [(_ name expr)
     (test name (if expr #t #f) #t)]))

(printf "--- (std persist image) tests ---~%~%")

;;; Reset image state before each section to keep tests independent
(define (reset!) (image-clear!))

;;; Temp directory for file tests
(define *tmp-dir*
  (let ([d (string-append "/tmp/jerboa-image-test-"
                          (number->string (random 1000000)))])
    (system (string-append "mkdir -p " d))
    d))

(define (tmp-path name)
  (string-append *tmp-dir* "/" name))

;;; ======== image-set! / image-ref ========

(reset!)

(test "image-ref returns default when key absent"
  (image-ref 'absent 'default)
  'default)

(image-set! 'x 42)
(test "image-ref after image-set!"
  (image-ref 'x)
  42)

(image-set! 'name "alice")
(test "image-ref string value"
  (image-ref 'name)
  "alice")

(image-set! 'data '(1 2 3))
(test "image-ref list value"
  (image-ref 'data)
  '(1 2 3))

(image-set! 'flag #t)
(test "image-ref boolean value"
  (image-ref 'flag)
  #t)

(image-set! 'x 99)
(test "image-set! overwrites existing key"
  (image-ref 'x)
  99)

;;; ======== image-keys ========

(reset!)
(test "image-keys empty after clear"
  (image-keys)
  '())

(image-set! 'a 1)
(image-set! 'b 2)
(image-set! 'c 3)
(test "image-keys length"
  (length (image-keys))
  3)

(test-true "image-keys contains 'a"
  (member 'a (image-keys)))

(test-true "image-keys contains 'b"
  (member 'b (image-keys)))

(test-true "image-keys contains 'c"
  (member 'c (image-keys)))

;;; ======== image-clear! ========

(reset!)
(image-set! 'k1 100)
(image-set! 'k2 200)
(image-clear!)
(test "image-clear! removes all keys"
  (image-keys)
  '())

(test "image-ref returns default after clear"
  (image-ref 'k1 'gone)
  'gone)

;;; ======== image-ref missing key raises error ========

(reset!)
(test "image-ref no default raises error"
  (guard (exn [#t 'error-raised])
    (image-ref 'no-such-key)
    'no-error)
  'error-raised)

;;; ======== save-image / load-image ========

(reset!)
(image-set! 'counter 0)
(image-set! 'message "hello")
(image-set! 'items '(a b c))

(define img-path (tmp-path "test.img"))
(save-image img-path)

(test-true "save-image creates file"
  (file-exists? img-path))

;; Clear and reload
(image-clear!)
(test "image is empty after clear"
  (image-ref 'counter 'missing)
  'missing)

(load-image img-path)
(test "load-image restores counter"
  (image-ref 'counter)
  0)

(test "load-image restores string"
  (image-ref 'message)
  "hello")

(test "load-image restores list"
  (image-ref 'items)
  '(a b c))

;;; ======== load-image merges (does not clear existing) ========

(reset!)
(image-set! 'existing 'stays)
(image-set! 'override 'old)

;; Save a partial image
(define partial-path (tmp-path "partial.img"))
(image-clear!)
(image-set! 'override 'new)
(image-set! 'fresh 'added)
(save-image partial-path)

;; Restore existing and then merge
(image-clear!)
(image-set! 'existing 'stays)
(image-set! 'override 'old)

(load-image partial-path)

(test "load-image merges: existing key preserved"
  (image-ref 'existing)
  'stays)

(test "load-image merges: overlapping key overwritten"
  (image-ref 'override)
  'new)

(test "load-image merges: new key added"
  (image-ref 'fresh)
  'added)

;;; ======== save/load with various value types ========

(reset!)
(image-set! 'int-val 12345)
(image-set! 'float-val 2.718)
(image-set! 'bool-f #f)
(image-set! 'char-val #\Z)
(image-set! 'bvec #vu8(1 2 3))
(image-set! 'nested '((k . v) (n . 42)))

(define types-path (tmp-path "types.img"))
(save-image types-path)
(image-clear!)
(load-image types-path)

(test "save/load: integer"
  (image-ref 'int-val)
  12345)

(test "save/load: flonum"
  (image-ref 'float-val)
  2.718)

(test "save/load: boolean #f"
  (image-ref 'bool-f)
  #f)

(test "save/load: char"
  (image-ref 'char-val)
  #\Z)

(test "save/load: bytevector"
  (image-ref 'bvec)
  #vu8(1 2 3))

(test "save/load: nested alist"
  (image-ref 'nested)
  '((k . v) (n . 42)))

;;; ======== multiple save/load cycles ========

(reset!)
(define cycle-path (tmp-path "cycle.img"))

(image-set! 'step 1)
(save-image cycle-path)

(image-set! 'step 2)
(save-image cycle-path)

(image-clear!)
(load-image cycle-path)
(test "multiple saves: last save wins"
  (image-ref 'step)
  2)

;;; Summary

(printf "~%~a tests: ~a passed, ~a failed~%" (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
