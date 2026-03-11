#!chezscheme
;;; Tests for Phase 10: Capability-Based Security

(import (chezscheme)
        (std capability))

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

(printf "--- Phase 10: Capability-Based Security ---~%")

;;; ======== Root Capability ========

(printf "~%-- Root Capability --~%")

(let ([root (make-root-capability)])
  (test "root-capability? true"
    (root-capability? root)
    #t)
  (test "capability? true"
    (capability? root)
    #t)
  (test "capability-valid? true"
    (capability-valid? root)
    #t)
  (test "capability-type is root"
    (capability-type root)
    'root))

;;; ======== FS Capability ========

(printf "~%-- FS Capability --~%")

(let ([root (make-root-capability)])
  ;; Attenuate to read-only
  (let ([ro-cap (attenuate-fs root
                  'read-only: #t
                  'paths: (list "/tmp/"))])
    (test "fs-capability? true"
      (fs-capability? ro-cap)
      #t)
    (test "fs-cap-readable? true"
      (fs-cap-readable? ro-cap)
      #t)
    (test "fs-cap-writable? false (read-only)"
      (fs-cap-writable? ro-cap)
      #f)
    (test "fs-cap-paths set"
      (fs-cap-paths ro-cap)
      (list "/tmp/"))

    ;; Write access denied
    (let ([write-denied? #f])
      (guard (exn [#t (set! write-denied? #t)])
        (cap-file-open ro-cap "/tmp/test.txt" 'w))
      (test "write denied on read-only cap"
        write-denied?
        #t))

    ;; Path outside allowed
    (let ([path-denied? #f])
      (guard (exn [#t (set! path-denied? #t)])
        (cap-file-open ro-cap "/etc/passwd" 'r))
      (test "path outside allowed denied"
        path-denied?
        #t)))

  ;; Full FS capability
  (let ([rw-cap (attenuate-fs root)])
    (test "full cap readable"
      (fs-cap-readable? rw-cap)
      #t)
    (test "full cap writable"
      (fs-cap-writable? rw-cap)
      #t)
    (test "full cap paths unrestricted"
      (fs-cap-paths rw-cap)
      #f))

  ;; File read/write with capability
  (let ([cap (attenuate-fs root 'paths: (list "/tmp/"))])
    (cap-file-write cap "/tmp/cap-test.txt" "hello capability")
    (test "cap-file-write and read"
      (cap-file-read cap "/tmp/cap-test.txt")
      "hello capability")))

;;; ======== Net Capability ========

(printf "~%-- Net Capability --~%")

(let ([root (make-root-capability)])
  (let ([net-cap (attenuate-net root
                   'allow: (list "api.example.com" "db.local")
                   'deny-all-others: #t)])
    (test "net-capability? true"
      (net-capability? net-cap)
      #t)
    (test "allowed hosts"
      (net-cap-allowed-hosts net-cap)
      (list "api.example.com" "db.local"))
    (test "deny-others? true"
      (net-cap-deny-others? net-cap)
      #t)

    ;; Allowed host works
    (test "cap-connect allowed host"
      (cap-connect net-cap "api.example.com" 443)
      (list "api.example.com" 443))

    ;; Denied host fails
    (let ([denied? #f])
      (guard (exn [#t (set! denied? #t)])
        (cap-connect net-cap "evil.com" 80))
      (test "cap-connect denied host"
        denied?
        #t))))

;;; ======== Eval Capability ========

(printf "~%-- Eval Capability --~%")

(let ([root (make-root-capability)])
  (let ([eval-cap (attenuate-eval root
                    'modules: (list 'std/json 'std/http))])
    (test "eval-capability? true"
      (eval-capability? eval-cap)
      #t)
    (test "eval-cap-allowed-modules"
      (eval-cap-allowed-modules eval-cap)
      (list 'std/json 'std/http))))

;;; ======== Sandbox ========

(printf "~%-- Sandbox --~%")

;; Basic sandbox execution
(let ([result (with-sandbox (lambda () (+ 1 2)))])
  (test "with-sandbox: basic result"
    result
    3))

;; Sandbox catches exceptions
(let ([caught? #f]
      [err-msg #f])
  (guard (exn [#t
               (set! caught? #t)
               (set! err-msg (if (message-condition? exn)
                               (condition-message exn)
                               "error"))])
    (with-sandbox (lambda () (error "test" "sandbox error"))))
  (test "with-sandbox: exception propagates"
    caught?
    #t))

;; Sandbox with timeout
(let ([timed-out? #f])
  (guard (exn [#t (set! timed-out? #t)])
    (with-sandbox
      (lambda ()
        (let loop ([i 0])
          (if (> i 1000000000)
            i
            (loop (+ i 1)))))
      'timeout-ms: 10))
  (test "with-sandbox: timeout fires"
    timed-out?
    #t))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
