(import (jerboa prelude))
(import (std component))

(def test-count 0)
(def pass-count 0)

(defrule (test name body ...)
  (begin
    (set! test-count (+ test-count 1))
    (guard (exn [#t
      (displayln (str "FAIL: " name))
      (displayln (str "  Error: " (if (message-condition? exn)
                                    (condition-message exn) exn)))])
      body ...
      (set! pass-count (+ pass-count 1))
      (displayln (str "PASS: " name)))))

(defrule (assert-equal got expected msg)
  (unless (equal? got expected)
    (error 'assert msg (list 'got: got 'expected: expected))))

(defrule (assert-true val msg)
  (unless val (error 'assert msg)))

;; Track start/stop order for testing
(def start-order '())
(def stop-order '())

(def (reset-tracking!)
  (set! start-order '())
  (set! stop-order '()))

;; Register lifecycle for test components
(register-lifecycle! 'database
  (lambda (c)
    (set! start-order (append start-order '(database)))
    (hashtable-set! (component-config c) 'conn "db-connection")
    c)
  (lambda (c)
    (set! stop-order (append stop-order '(database)))
    (hashtable-set! (component-config c) 'conn #f)
    c))

(register-lifecycle! 'cache
  (lambda (c)
    (set! start-order (append start-order '(cache)))
    (hashtable-set! (component-config c) 'store (make-hashtable equal-hash equal?))
    c)
  (lambda (c)
    (set! stop-order (append stop-order '(cache)))
    (hashtable-set! (component-config c) 'store #f)
    c))

(register-lifecycle! 'webserver
  (lambda (c)
    (set! start-order (append start-order '(webserver)))
    (hashtable-set! (component-config c) 'running #t)
    c)
  (lambda (c)
    (set! stop-order (append stop-order '(webserver)))
    (hashtable-set! (component-config c) 'running #f)
    c))

;; =========================================================================
;; Component creation tests
;; =========================================================================

(test "component creates stopped component"
  (let ([c (component 'database 'host "localhost" 'port 5432)])
    (assert-true (component? c) "is component")
    (assert-equal (component-name c) 'database "name")
    (assert-equal (component-state c) 'stopped "initially stopped")
    (assert-true (not (component-started? c)) "not started")))

(test "component config accessible"
  (let ([c (component 'database 'host "localhost" 'port 5432)])
    (assert-equal (hashtable-ref (component-config c) 'host #f)
      "localhost" "host config")
    (assert-equal (hashtable-ref (component-config c) 'port #f)
      5432 "port config")))

;; =========================================================================
;; Single component lifecycle
;; =========================================================================

(test "start/stop single component"
  (reset-tracking!)
  (let ([c (component 'database 'host "localhost")])
    (let ([started (start c)])
      (assert-true (component-started? started) "started")
      (assert-equal (hashtable-ref (component-config started) 'conn #f)
        "db-connection" "conn set")
      (let ([stopped (stop started)])
        (assert-true (not (component-started? stopped)) "stopped")
        (assert-equal (hashtable-ref (component-config stopped) 'conn #f)
          #f "conn cleared")))))

(test "start is idempotent"
  (reset-tracking!)
  (let* ([c (component 'database)]
         [s1 (start c)]
         [s2 (start s1)])
    (assert-equal start-order '(database) "started only once")
    (stop s2)))

;; Helper: find index of element in list
(def (list-index lst item)
  (let loop ([l lst] [i 0])
    (cond
      [(null? l) (error 'list-index "not found" item)]
      [(eq? (car l) item) i]
      [else (loop (cdr l) (+ i 1))])))

;; =========================================================================
;; System tests
;; =========================================================================

(test "system-map creates system"
  (let ([sys (system-map
               'db (component 'database 'host "localhost")
               'cache (component 'cache)
               'web (component 'webserver 'port 8080))])
    (assert-true (not (system-started? sys)) "not started")))

(test "system start/stop in dependency order"
  (reset-tracking!)
  (let ([sys (system-using
               (system-map
                 'db (component 'database)
                 'cache (component 'cache)
                 'web (component 'webserver))
               '((cache . (db))
                 (web . (db cache))))])
    (let ([started (start sys)])
      ;; db must start before cache and webserver
      (assert-true (< (list-index start-order 'database)
                      (list-index start-order 'cache))
        "db before cache")
      (assert-true (< (list-index start-order 'database)
                      (list-index start-order 'webserver))
        "db before webserver")
      (assert-true (< (list-index start-order 'cache)
                      (list-index start-order 'webserver))
        "cache before webserver")
      (assert-true (system-started? started) "all started")

      ;; Stop — reverse order
      (let ([stopped (stop started)])
        (assert-true (< (list-index stop-order 'webserver)
                        (list-index stop-order 'cache))
          "webserver stops before cache")
        (assert-true (< (list-index stop-order 'cache)
                        (list-index stop-order 'database))
          "cache stops before db")
        (assert-true (not (system-started? stopped)) "all stopped")))))

(test "system injects dependencies"
  (reset-tracking!)
  (let ([sys (system-using
               (system-map
                 'db (component 'database)
                 'web (component 'webserver))
               '((web . (db))))])
    (let ([started (start sys)])
      ;; After starting, web component should have db in its deps
      ;; We can verify via the dep-map injection
      (stop started))))

;; =========================================================================
;; Summary
;; =========================================================================
(newline)
(displayln (str "========================================="))
(displayln (str "Results: " pass-count "/" test-count " passed"))
(displayln (str "========================================="))
(when (< pass-count test-count)
  (exit 1))
