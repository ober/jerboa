#!chezscheme
;;; Tests for (std net router) -- HTTP request routing

(import (chezscheme) (std net router))

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

(printf "--- Phase 3b: Router ---~%~%")

;;; ======== Router construction ========

(test "make-router"
  (router? (make-router))
  #t)

(test "router-not-type"
  (router? '())
  #f)

;;; ======== Route record ========

(test "make-route"
  (let ([r (make-route "GET" "/hello" (lambda (p) "hi"))])
    (not (eq? r #f)))
  #t)

;;; ======== Static routes ========

(test "static-route-match"
  (let ([r (make-router)])
    (router-get! r "/hello" (lambda (p) "hello"))
    (route-match? (router-match r "GET" "/hello")))
  #t)

(test "static-route-no-match"
  (let ([r (make-router)])
    (router-get! r "/hello" (lambda (p) "hello"))
    (router-match r "GET" "/world"))
  route-not-found)

(test "static-route-handler-call"
  (let* ([r (make-router)]
         [_ (router-get! r "/hello" (lambda (p) "world"))]
         [m (router-match r "GET" "/hello")])
    ((route-handler m) (route-params m)))
  "world")

(test "static-route-empty-params"
  (let* ([r (make-router)]
         [_ (router-get! r "/foo" (lambda (p) p))]
         [m (router-match r "GET" "/foo")])
    (route-params m))
  '())

;;; ======== Method matching ========

(test "get-only"
  (let ([r (make-router)])
    (router-get! r "/api" (lambda (p) "get"))
    (router-match r "POST" "/api"))
  route-not-found)

(test "post-route"
  (let ([r (make-router)])
    (router-post! r "/api" (lambda (p) "post"))
    (route-match? (router-match r "POST" "/api")))
  #t)

(test "put-route"
  (let ([r (make-router)])
    (router-put! r "/api" (lambda (p) "put"))
    (route-match? (router-match r "PUT" "/api")))
  #t)

(test "delete-route"
  (let ([r (make-router)])
    (router-delete! r "/api" (lambda (p) "delete"))
    (route-match? (router-match r "DELETE" "/api")))
  #t)

(test "patch-route"
  (let ([r (make-router)])
    (router-patch! r "/api" (lambda (p) "patch"))
    (route-match? (router-match r "PATCH" "/api")))
  #t)

;;; ======== ANY method ========

(test "any-route-get"
  (let ([r (make-router)])
    (router-any! r "/ping" (lambda (p) "pong"))
    (route-match? (router-match r "GET" "/ping")))
  #t)

(test "any-route-post"
  (let ([r (make-router)])
    (router-any! r "/ping" (lambda (p) "pong"))
    (route-match? (router-match r "POST" "/ping")))
  #t)

;;; ======== Parameterized routes ========

(test "param-route-match"
  (let ([r (make-router)])
    (router-get! r "/users/:id" (lambda (p) p))
    (route-match? (router-match r "GET" "/users/42")))
  #t)

(test "param-route-capture"
  (let* ([r (make-router)]
         [_ (router-get! r "/users/:id" (lambda (p) p))]
         [m (router-match r "GET" "/users/42")])
    (cdr (assq 'id (route-params m))))
  "42")

(test "multi-param-route"
  (let* ([r (make-router)]
         [_ (router-get! r "/users/:id/posts/:post-id" (lambda (p) p))]
         [m (router-match r "GET" "/users/10/posts/99")])
    (list (cdr (assq 'id (route-params m)))
          (cdr (assq 'post-id (route-params m)))))
  '("10" "99"))

;;; ======== Wildcard routes ========

(test "wildcard-route-match"
  (let ([r (make-router)])
    (router-get! r "/static/*" (lambda (p) "static"))
    (route-match? (router-match r "GET" "/static/css/style.css")))
  #t)

(test "wildcard-no-match-static-prefix"
  ;; Static route takes precedence
  (let ([r (make-router)])
    (router-get! r "/static/main.css" (lambda (p) "specific"))
    (router-get! r "/static/*"        (lambda (p) "wildcard"))
    (let ([m (router-match r "GET" "/static/main.css")])
      ((route-handler m) (route-params m))))
  "specific")

;;; ======== Middleware ========

(test "route-middleware-empty"
  (let* ([r (make-router)]
         [_ (router-get! r "/hi" (lambda (p) "hi"))]
         [m (router-match r "GET" "/hi")])
    (route-middleware m))
  '())

(test "global-middleware-added"
  (let* ([r   (make-router)]
         [mw  (lambda (h) h)]
         [_   (router-middleware! r mw)]
         [_   (router-get! r "/hi" (lambda (p) "hi"))]
         [m   (router-match r "GET" "/hi")])
    (length (route-middleware m)))
  1)

;;; Summary

(printf "~%Router tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
