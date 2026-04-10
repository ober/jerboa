#!chezscheme
;;; Tests for (std regex) — unified regex facade
;;; Note: #r"..." raw string literals are tested in test-reader-rawstring.ss
;;; since they require the Jerboa reader. Here we use regular strings.

(import (chezscheme)
        (std regex))

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

(define-syntax test-t (syntax-rules () [(_ name expr) (test name (if expr #t #f) #t)]))
(define-syntax test-f (syntax-rules () [(_ name expr) (test name (if expr #t #f) #f)]))

(printf "--- (std regex) unified facade ---~%~%")

;;; ========== re compilation ==========

(printf "  -- re compilation --~%")

(test-t "re from string"      (re? (re "\\d+")))
(test-t "re from SRE list"    (re? (re '(+ digit))))
(test-t "re from SRE symbol"  (re? (re 'digit)))
(test-t "re idempotent"       (let ([r (re "abc")]) (eq? r (re r))))

;;; ========== re-match? — full string match ==========

(printf "~%  -- re-match? full string match --~%")

(test   "string: match"          (re-match? "\\d+" "123")    #t)
(test   "string: no match"       (re-match? "\\d+" "abc")    #f)
(test   "string: partial fails"  (re-match? "\\d+" "12abc")  #f)
(test   "SRE: match"             (re-match? '(+ digit) "123") #t)
(test   "SRE: no match"          (re-match? '(+ digit) "abc") #f)
(test   "SRE: partial fails"     (re-match? '(: alpha (* alnum)) "hello!") #f)
(test   "SRE: alternation hit"   (re-match? '(or "cat" "dog") "cat") #t)
(test   "SRE: alternation miss"  (re-match? '(or "cat" "dog") "fish") #f)
(test-t "compiled re in match?"  (re-match? (re "\\d+") "42"))

;;; ========== re-match? — 1-arg match object predicate ==========

(printf "~%  -- re-match? as match-object predicate --~%")

(test "on match object"   (re-match? (re-search "\\d+" "abc123")) #t)
(test "on plain string"   (re-match? "hello")        #f)
(test "on re-object"      (re-match? (re "abc"))      #f)
(test "on #f"             (re-match? #f)              #f)

;;; ========== re-search ==========

(printf "~%  -- re-search --~%")

(test-t "returns match object"    (re-match? (re-search "\\d+" "abc123def")))
(test-f "returns #f on no match" (re-search "\\d+" "abc"))

(test "full text"   (re-match-full  (re-search "\\d+" "abc123def")) "123")
(test "start pos"   (re-match-start (re-search "\\d+" "abc123def")) 3)
(test "end pos"     (re-match-end   (re-search "\\d+" "abc123def")) 6)

(test "start offset"
  (re-match-full (re-search "\\d+" "1abc2" 1)) "2")

(test "SRE search"
  (re-match-full (re-search '(+ digit) "foo42bar")) "42")

;;; ========== re-find-all ==========

(printf "~%  -- re-find-all --~%")

(test "basic"        (re-find-all "\\d+" "a1b22c333")   '("1" "22" "333"))
(test "no matches"   (re-find-all "\\d+" "abc")          '())
(test "SRE"          (re-find-all '(+ digit) "x1y2z3")  '("1" "2" "3"))
(test "words"        (re-find-all "\\w+" "hello world foo") '("hello" "world" "foo"))

;;; ========== re-groups ==========

(printf "~%  -- re-groups --~%")

(test "two captures"     (re-groups "(\\w+)@(\\w+)" "user@host") '("user" "host"))
(test "no captures"      (re-groups "\\d+" "123")                '())
(test "no match"         (re-groups "\\d+" "abc")                #f)
(test "one capture"      (re-groups "^(\\w+)$" "hello")          '("hello"))

;;; ========== re-match-group and re-match-groups ==========

(printf "~%  -- re-match-group / re-match-groups --~%")

(let ([m (re-search "(\\w+)@(\\w+)" "user@host")])
  (test "group 0 = full"    (re-match-group m 0) "user@host")
  (test "group 1 = first"   (re-match-group m 1) "user")
  (test "group 2 = second"  (re-match-group m 2) "host")
  (test "groups list"       (re-match-groups m)  '("user" "host")))

;;; ========== re-replace / re-replace-all ==========

(printf "~%  -- re-replace / re-replace-all --~%")

(test "replace first"       (re-replace     "\\d+" "abc123def456" "NUM") "abcNUMdef456")
(test "replace-all"         (re-replace-all "\\d+" "1a2b3c" "N")         "NaNbNc")
(test "replace SRE"         (re-replace     '(+ digit) "test42" "?")     "test?")
(test "replace-all SRE"     (re-replace-all '(+ digit) "1x2y3z" "0")     "0x0y0z")
(test "replace backref"     (re-replace     "(\\w+)@(\\w+)" "user@host" "\\2@\\1") "host@user")

;;; ========== re-split ==========

(printf "~%  -- re-split --~%")

(test "split whitespace"  (re-split "\\s+" "a b  c")      '("a" "b" "c"))
(test "split comma"       (re-split "," "a,b,c")           '("a" "b" "c"))
(test "split SRE"         (re-split '(+ space) "one two three") '("one" "two" "three"))

;;; ========== re-fold ==========

(printf "~%  -- re-fold --~%")

(test "fold collects reversed"
  (re-fold "\\d+" (lambda (i m str acc) (cons (re-match-full m) acc)) '() "a1b2c3")
  '("3" "2" "1"))

(test "fold match indices"
  (re-fold "\\d+" (lambda (i m str acc) (cons i acc)) '() "a1b2c3")
  '(2 1 0))

(test "fold empty"
  (re-fold "\\d+" (lambda (i m str acc) (cons i acc)) 'empty "abc")
  'empty)

;;; ========== Named captures ==========

(printf "~%  -- named captures (=>) --~%")

(let ([m (re-search '(: (=> user (+ word)) "@" (=> host (+ word))) "alice@wonderland")])
  (test "named user"  (re-match-named m 'user) "alice")
  (test "named host"  (re-match-named m 'host) "wonderland"))

(let ([m (re-search '(: (=> year (= 4 digit)) "-"
                         (=> month (= 2 digit)) "-"
                         (=> day   (= 2 digit)))
                    "born 2001-03-15 here")])
  (test "named year"  (re-match-named m 'year)  "2001")
  (test "named month" (re-match-named m 'month) "03")
  (test "named day"   (re-match-named m 'day)   "15"))

(test "named unknown → #f"
  (re-match-named (re-search '(=> x (+ digit)) "42") 'y)
  #f)

;;; ========== SRE patterns ==========

(printf "~%  -- SRE patterns --~%")

(test   "sequence"        (re-match? '(: alpha (* alnum)) "hello123")  #t)
(test   "star: empty ok"  (re-match? '(* digit) "")                    #t)
(test   "plus: one ok"    (re-match? '(+ digit) "1")                   #t)
(test   "exact repeat"    (re-match? '(= 3 digit) "123")               #t)
(test   "exact rejects"   (re-match? '(= 3 digit) "12")                #f)
(test   "range repeat"    (re-match? '(** 2 4 digit) "123")            #t)
(test   "complement"      (re-match? '(+ (~ digit)) "abc")             #t)
(test   "char range"      (re-match? '(+ (/ #\a #\z)) "hello")        #t)
(test   "nocase"          (re-match? '(w/nocase (: alpha (+ alpha))) "HELLO") #t)

;;; ========== Summary ==========
(newline)
(printf "Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
