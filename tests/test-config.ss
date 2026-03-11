#!chezscheme
;;; tests/test-config.ss -- Tests for (std config)

(import (chezscheme) (std config))

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

(printf "--- Phase 2e: Config ---~%~%")

;; ---- 1. make-config / config? ----
(let ([cfg (make-config)])
  (test "config?" (config? cfg) #t)
  (test "empty-get" (config-get cfg 'foo) #f)
  (test "empty-get-default" (config-get cfg 'foo "bar") "bar"))

;; ---- 2. config-set! / config-get ----
(let ([cfg (make-config)])
  (config-set! cfg 'name "Alice")
  (config-set! cfg 'age  30)
  (test "config-set-string" (config-get cfg 'name) "Alice")
  (test "config-set-int"    (config-get cfg 'age)  30))

;; ---- 3. config-ref ----
(let ([cfg (make-config)])
  (config-set! cfg 'key "value")
  (test "config-ref" (config-ref cfg 'key) "value")
  (test "config-ref-missing" (config-ref cfg 'missing) #f))

;; ---- 4. config-ref* ----
(let ([cfg (make-config)])
  (config-set! cfg 'a 1)
  (config-set! cfg 'b 2)
  (test "config-ref*" (config-ref* cfg 'a 'b) '(1 2)))

;; ---- 5. config-merge! with alist ----
(let ([cfg (make-config)])
  (config-merge! cfg '((x . 10) (y . 20) (z . "hello")))
  (test "merge-x" (config-get cfg 'x) 10)
  (test "merge-y" (config-get cfg 'y) 20)
  (test "merge-z" (config-get cfg 'z) "hello"))

;; ---- 6. config-schema / validate-config ----
(let ([cfg (make-config)]
      [schema '((name string "default") (port integer 8080) (debug boolean #f))])
  (config-set! cfg 'name "myapp")
  (config-set! cfg 'port 3000)
  (config-set! cfg 'debug #t)
  (let ([errors (validate-config cfg)])
    (test "validate-ok" errors '()))
  (test "config-valid?" (config-valid? cfg) #t))

;; ---- 7. validate-config catches type errors ----
;; Load config with schema - schema is attached at load time
(let* ([tmpfile "/tmp/test-config-schema.sexp"]
       [_ (call-with-output-file tmpfile
            (lambda (p) (write '((count . "not-a-number")) p))
            'truncate)]
       [schema '((count integer 0))]
       [cfg (load-config tmpfile schema)])
  (let ([errors (validate-config cfg)])
    (test "validate-error-count" (length errors) 1)
    (test "validate-error-key"   (caar errors) 'count))
  (delete-file tmpfile))

;; ---- 8. watch-config! triggers on set ----
(let ([cfg (make-config)]
      [watch-log '()])
  (watch-config! cfg (lambda (k v) (set! watch-log (cons (cons k v) watch-log))))
  (config-set! cfg 'foo 42)
  (config-set! cfg 'bar "baz")
  (test "watch-count" (length watch-log) 2)
  (test "watch-first"  (cdar watch-log) "baz"))

;; ---- 9. save-config and load-config ----
(let ([tmpfile "/tmp/test-config.sexp"]
      [cfg (make-config)])
  (config-set! cfg 'host "localhost")
  (config-set! cfg 'port 9090)
  (save-config cfg tmpfile)
  (test "save-creates-file" (file-exists? tmpfile) #t)
  ;; Load it back
  (let ([cfg2 (load-config tmpfile)])
    (test "load-config-host" (config-get cfg2 'host) "localhost")
    (test "load-config-port" (config-get cfg2 'port) 9090))
  (delete-file tmpfile))

;; ---- 10. load-config from non-existent file returns empty config ----
(let ([cfg (load-config "/tmp/nonexistent-config-999.sexp")])
  (test "load-nonexistent" (config? cfg) #t)
  (test "load-nonexistent-empty" (config-get cfg 'x) #f))

;; ---- 11. with-config macro ----
(let ([cfg (make-config)])
  (config-set! cfg 'width 800)
  (config-set! cfg 'height 600)
  ;; with-config binds vars from config by key
  (with-config cfg ([w width] [h height])
    (test "with-config-w" w 800)
    (test "with-config-h" h 600)))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
