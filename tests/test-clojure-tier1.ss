(import (except (jerboa prelude) hash-map)
        (std clojure)
        (std clojure walk))

(define pass 0)
(define fail 0)
(define-syntax chk
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([r expr] [e expected])
       (if (equal? r e)
         (set! pass (+ pass 1))
         (begin (set! fail (+ fail 1))
                (display "FAIL: ") (write 'expr)
                (display " => ") (write r)
                (display " expected ") (write e) (newline))))]))

;; ========== merge-with ==========
(chk (let ([m (merge-with + (hash-map 'a 1 'b 2) (hash-map 'b 3 'c 4))])
       (list (get m 'a) (get m 'b) (get m 'c)))
     => '(1 5 4))

;; ========== zipmap ==========
(chk (let ([m (zipmap '(a b c) '(1 2 3))])
       (list (get m 'a) (get m 'b) (get m 'c)))
     => '(1 2 3))
;; extra keys ignored
(chk (let ([m (zipmap '(a b) '(1 2 3))])
       (count m))
     => 2)

;; ========== reduce-kv ==========
(chk (reduce-kv (lambda (acc k v) (+ acc v)) 0 (hash-map 'a 1 'b 2 'c 3))
     => 6)

;; ========== min-key / max-key ==========
(chk (min-key string-length "aa" "b" "ccc") => "b")
(chk (max-key string-length "aa" "b" "ccc") => "ccc")
(chk (min-key car '(3 x) '(1 x) '(2 x)) => '(1 x))

;; ========== memoize ==========
(chk (let* ([calls 0]
            [f (memoize (lambda (x) (set! calls (+ calls 1)) (* x x)))])
       (f 4) (f 4) (f 5) (f 4)
       (list (f 4) (f 5) calls))
     => '(16 25 2))

;; ========== iterate ==========
(chk (iterate 5 (lambda (x) (* x 2)) 1) => '(1 2 4 8 16))
(chk (iterate 0 (lambda (x) x) 1) => '())

;; ========== repeatedly ==========
(chk (repeatedly 3 (lambda () 42)) => '(42 42 42))
(chk (repeatedly 0 (lambda () 1)) => '())

;; ========== doto ==========
(chk (let ([h (doto (make-hash-table)
               (hash-put! 'a 1)
               (hash-put! 'b 2))])
       (list (hash-ref h 'a) (hash-ref h 'b)))
     => '(1 2))

;; ========== def-dynamic / binding ==========
;; tested via script rather than inline (requires top-level define)

;; ========== ex-info / ex-data ==========
(chk (try (raise (ex-info "oops" (hash-map 'reason 'nsf 'amount 100)))
       (catch (e)
         (list (ex-info? e) (ex-message e) (get (ex-data e) 'reason))))
     => '(#t "oops" nsf))

(chk (try (raise (ex-info "fail" (hash-map 'code 42) (make-message-condition "cause")))
       (catch (e) (ex-info? e)))
     => #t)

(chk (ex-data (make-message-condition "not ex-info")) => #f)

;; ========== dlet — list destructure ==========
(chk (dlet ([(a b c) '(1 2 3)]) (+ a b c)) => 6)
(chk (dlet ([(h & t) '(10 20 30)]) (list h t)) => '(10 (20 30)))

;; ========== dlet — map destructure ==========
(chk (dlet ([(keys: x y) (hash-map 'x: 10 'y: 20)]) (+ x y)) => 30)

;; ========== dlet — :as ==========
(chk (dlet ([(keys: x as: m) (hash-map 'x: 42)])
       (list x (persistent-map? m)))
     => '(42 #t))

;; ========== dlet — :or defaults ==========
(chk (dlet ([(keys: x y or: ([y 99])) (hash-map 'x: 10)])
       (list x y))
     => '(10 99))

;; ========== dlet — multiple bindings ==========
(chk (dlet ([a 1] [(b c) '(2 3)] [(keys: d) (hash-map 'd: 4)])
       (+ a b c d))
     => 10)

;; ========== dfn ==========
(dfn (sum-pair (a b)) (+ a b))
(chk (sum-pair '(3 7)) => 10)

(dfn (get-x (keys: x)) x)
(chk (get-x (hash-map 'x: 42)) => 42)

(dfn (mixed (keys: x) y) (+ x y))
(chk (mixed (hash-map 'x: 10) 20) => 30)

;; ========== clojure.walk — postwalk ==========
(chk (postwalk (lambda (x) (if (number? x) (* x 2) x))
               '(1 (2 3) 4))
     => '(2 (4 6) 8))

;; ========== clojure.walk — prewalk ==========
(chk (prewalk (lambda (x) (if (and (list? x) (not (null? x)) (eq? (car x) 'skip))
                               'SKIPPED x))
              '(a (skip b) c))
     => '(a SKIPPED c))

;; ========== clojure.walk — postwalk-replace ==========
(chk (postwalk-replace (hash-map 'x 1 'y 2) '(x y z))
     => '(1 2 z))

;; ========== clojure.walk — keywordize-keys ==========
(chk (let ([m (keywordize-keys (hash-map "a" 1 "b" 2))])
       (sort (keys m)
             (lambda (a b) (string<? (symbol->string a) (symbol->string b)))))
     => (list (string->keyword "a") (string->keyword "b")))

;; ========== clojure.walk — stringify-keys ==========
(chk (let ([m (stringify-keys (hash-map (string->keyword "a") 1))])
       (keys m))
     => '("a"))

(newline)
(display "clojure tier-1: ")
(display pass) (display " passed, ")
(display fail) (display " failed") (newline)
(when (> fail 0) (exit 1))
