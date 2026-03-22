#!/usr/bin/env -S scheme --libdirs lib --script
;;; hello-api.ss — A simple JSON API server
;;;
;;; Demonstrates: httpd, router, JSON, hash tables, format, error handling
;;;
;;; Run: bin/jerboa run examples/hello-api.ss
;;; Test: curl http://localhost:8080/api/greeting?name=World

(import (except (chezscheme)
          make-hash-table hash-table?
          sort sort! format printf fprintf
          iota 1+ 1-
          path-extension path-absolute?
          with-input-from-string with-output-to-string)
        (jerboa prelude)
        (std net httpd)
        (std net router)
        (std misc thread))

;; --- In-memory data store ---

(define *items* (make-hash-table))
(define *next-id* 1)

(def (add-item! name)
  (let ([id *next-id*])
    (set! *next-id* (+ id 1))
    (hash-put! *items* id
      (list->hash-table `(("id" . ,id) ("name" . ,name))))
    id))

(def (get-item id)
  (hash-get *items* id))

(def (all-items)
  (hash-values *items*))

(def (delete-item! id)
  (hash-remove! *items* id))

;; --- JSON helpers ---

(def (json-response body (status 200))
  `((status . ,status)
    (headers . (("Content-Type" . "application/json")))
    (body . ,(json-object->string body))))

(def (text-response body (status 200))
  `((status . ,status)
    (headers . (("Content-Type" . "text/plain")))
    (body . ,body)))

;; --- Route handlers ---

(def (handle-root req)
  (text-response "Jerboa API Server\n\nEndpoints:\n  GET  /api/items\n  POST /api/items?name=...\n  GET  /api/items/:id\n  DELETE /api/items/:id\n  GET  /api/greeting?name=...\n"))

(def (handle-greeting req)
  (let* ([query (or (request-query req) "")]
         [name (or (query-param query "name") "Jerboa")])
    (json-response
      (list->hash-table
        `(("message" . ,(format "Hello, ~a!" name))
          ("timestamp" . ,(format "~a" (current-time))))))))

(def (handle-list-items req)
  (json-response (all-items)))

(def (handle-create-item req)
  (let* ([query (or (request-query req) "")]
         [name (or (query-param query "name") #f)])
    (if name
      (let ([id (add-item! name)])
        (json-response (get-item id) 201))
      (json-response
        (list->hash-table '(("error" . "missing 'name' parameter")))
        400))))

(def (handle-get-item req)
  (let ([id (string->number (or (route-param req "id") "0"))])
    (let ([item (get-item id)])
      (if item
        (json-response item)
        (json-response
          (list->hash-table '(("error" . "not found")))
          404)))))

(def (handle-delete-item req)
  (let ([id (string->number (or (route-param req "id") "0"))])
    (if (get-item id)
      (begin
        (delete-item! id)
        (json-response
          (list->hash-table '(("deleted" . #t)))))
      (json-response
        (list->hash-table '(("error" . "not found")))
        404))))

;; --- Query string parser ---

(def (query-param query name)
  (let loop ([pairs (string-split query "&")])
    (if (null? pairs) #f
      (let ([kv (string-split (car pairs) "=")])
        (if (and (= (length kv) 2)
                 (string=? (car kv) name))
          (cadr kv)
          (loop (cdr pairs)))))))

;; --- Seed data ---

(add-item! "Learn Jerboa")
(add-item! "Build something cool")
(add-item! "Port from Gerbil")

;; --- Start server ---

(printf "Jerboa API server starting on port 8080...\n")
(printf "Try: curl http://localhost:8080/api/greeting?name=World\n")
(printf "     curl http://localhost:8080/api/items\n")
(printf "     curl -X POST 'http://localhost:8080/api/items?name=NewItem'\n")

(define routes
  (make-router
    (route "GET" "/" handle-root)
    (route "GET" "/api/greeting" handle-greeting)
    (route "GET" "/api/items" handle-list-items)
    (route "POST" "/api/items" handle-create-item)
    (route "GET" "/api/items/:id" handle-get-item)
    (route "DELETE" "/api/items/:id" handle-delete-item)))

(start-httpd 8080 routes)
