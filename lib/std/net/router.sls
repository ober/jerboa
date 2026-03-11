#!chezscheme
;;; (std net router) -- HTTP request routing
;;;
;;; Pattern matching: /users/:id/posts/:post-id -> params alist
;;; Route precedence: static > parameterized > wildcard
;;; Middleware: ordered list of wrappers

(library (std net router)
  (export
    make-router router?
    router-add! router-match
    route-match? route-params route-handler route-middleware
    router-get! router-post! router-put! router-delete! router-patch! router-any!
    route-not-found make-route router-middleware!)

  (import (chezscheme))

  ;;; ========== Route record ==========
  (define-record-type route-rec
    (fields method pattern handler priority (mutable middleware))
    (protocol
      (lambda (new)
        (lambda (method pattern handler priority)
          (new method pattern handler priority '())))))

  (define (make-route method pattern handler)
    (let ([priority (pattern-priority pattern)])
      (make-route-rec method pattern handler priority)))

  ;;; ========== Route match result ==========
  (define-record-type route-match-rec
    (fields handler params middleware))

  (define (route-match? x)    (route-match-rec? x))
  (define (route-params m)    (route-match-rec-params m))
  (define (route-handler m)   (route-match-rec-handler m))
  (define (route-middleware m) (route-match-rec-middleware m))

  ;; Sentinel for not-found
  (define route-not-found #f)

  ;;; ========== Router record ==========
  (define-record-type router-rec
    (fields (mutable routes) (mutable middleware))
    (protocol
      (lambda (new)
        (lambda ()
          (new '() '())))))

  (define (router? x) (router-rec? x))

  (define (make-router)
    (make-router-rec))

  ;;; ========== Pattern parsing ==========
  ;; Parse a path pattern into segments: each segment is either
  ;;   'static   -> exact string match
  ;;   'param    -> :name capture
  ;;   'wildcard -> * matches rest
  (define (parse-pattern pattern)
    (let ([segs (string-split pattern #\/)])
      ;; Remove empty leading segment from leading /
      (let ([parts (if (and (not (null? segs)) (string=? (car segs) ""))
                     (cdr segs)
                     segs)])
        (map (lambda (s)
               (cond
                 [(string=? s "*") (cons 'wildcard s)]
                 [(and (> (string-length s) 0) (char=? (string-ref s 0) #\:))
                  (cons 'param (substring s 1 (string-length s)))]
                 [else (cons 'static s)]))
             parts))))

  ;; Compute priority: number of static segments (higher = more specific)
  ;; Wildcard gets lowest priority (-1), params get 0, statics get 1 each.
  (define (pattern-priority pattern)
    (let ([segs (parse-pattern pattern)])
      (if (any-wildcard? segs)
        -1
        (fold-left (lambda (acc seg)
                     (+ acc (if (eq? (car seg) 'static) 1 0)))
                   0 segs))))

  (define (any-wildcard? segs)
    (exists (lambda (s) (eq? (car s) 'wildcard)) segs))

  ;;; ========== Path matching ==========
  ;; Match a request path against a route pattern.
  ;; Returns alist of (param-name . value) on success, #f on failure.
  (define (match-pattern pattern path)
    (let* ([pat-segs (parse-pattern pattern)]
           [path-segs (let ([parts (string-split path #\/)])
                        (if (and (not (null? parts)) (string=? (car parts) ""))
                          (cdr parts)
                          parts))])
      (let loop ([pats pat-segs] [paths path-segs] [params '()])
        (cond
          ;; Both exhausted: match!
          [(and (null? pats) (null? paths))
           (reverse params)]
          ;; Wildcard: match rest of path
          [(and (not (null? pats)) (eq? (caar pats) 'wildcard))
           (reverse (cons (cons '* (string-join path-segs "/")) params))]
          ;; Pattern exhausted but path has more: no match
          [(null? pats) #f]
          ;; Path exhausted but pattern has more: no match
          [(null? paths) #f]
          ;; Static segment: must match exactly
          [(eq? (caar pats) 'static)
           (if (string=? (cdar pats) (car paths))
             (loop (cdr pats) (cdr paths) params)
             #f)]
          ;; Param segment: capture
          [(eq? (caar pats) 'param)
           (loop (cdr pats) (cdr paths)
                 (cons (cons (string->symbol (cdar pats)) (car paths))
                       params))]
          [else #f]))))

  ;;; ========== Router operations ==========
  ;; Add a route to the router. Inserts in priority order (highest first).
  (define (router-add! router method pattern handler)
    (let* ([route  (make-route method pattern handler)]
           [routes (router-rec-routes router)]
           [new-routes (insert-route route routes)])
      (router-rec-routes-set! router new-routes)))

  ;; Insert route maintaining descending priority order.
  (define (insert-route route routes)
    (cond
      [(null? routes) (list route)]
      [(>= (route-rec-priority route) (route-rec-priority (car routes)))
       (cons route routes)]
      [else
       (cons (car routes) (insert-route route (cdr routes)))]))

  ;; Match a request: returns route-match-rec or #f.
  (define (router-match router method path)
    (let ([routes     (router-rec-routes router)]
          [global-mw  (router-rec-middleware router)])
      (let loop ([rs routes])
        (if (null? rs)
          route-not-found
          (let* ([r       (car rs)]
                 [rmeth   (route-rec-method r)]
                 [rpat    (route-rec-pattern r)])
            (if (and (or (eq? rmeth 'ANY)
                         (equal? rmeth method))
                     (match-pattern rpat path))
              (let ([params (match-pattern rpat path)]
                    [mw     (append global-mw (route-rec-middleware r))])
                (make-route-match-rec (route-rec-handler r) params mw))
              (loop (cdr rs))))))))

  ;; Add global middleware
  (define (router-middleware! router mw)
    (router-rec-middleware-set! router
      (append (router-rec-middleware router) (list mw))))

  ;; Convenience methods
  (define (router-get!    router pattern handler) (router-add! router "GET"    pattern handler))
  (define (router-post!   router pattern handler) (router-add! router "POST"   pattern handler))
  (define (router-put!    router pattern handler) (router-add! router "PUT"    pattern handler))
  (define (router-delete! router pattern handler) (router-add! router "DELETE" pattern handler))
  (define (router-patch!  router pattern handler) (router-add! router "PATCH"  pattern handler))
  (define (router-any!    router pattern handler) (router-add! router 'ANY     pattern handler))

  ;;; ========== Helpers ==========
  (define (string-split str delim)
    (let loop ([i 0] [start 0] [acc '()])
      (cond
        [(= i (string-length str))
         (reverse (cons (substring str start i) acc))]
        [(char=? (string-ref str i) delim)
         (loop (+ i 1) (+ i 1) (cons (substring str start i) acc))]
        [else
         (loop (+ i 1) start acc)])))

  (define (string-join strs sep)
    (if (null? strs)
      ""
      (fold-left (lambda (acc s) (string-append acc sep s))
                 (car strs) (cdr strs))))

) ;; end library
