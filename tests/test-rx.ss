#!chezscheme
;;; Tests for (std rx) — composable regex macro and (std rx patterns)

(import (chezscheme)
        (std regex)
        (std rx)
        (std rx patterns))

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

(printf "--- (std rx) macro and patterns ---~%~%")

;;; ========== rx macro — basic compilation ==========

(printf "  -- rx macro --~%")

(test-t "rx digit produces re?" (re? (rx digit)))
(test-t "rx+ digit produces re?" (re? (rx (+ digit))))
(test-t "rx sequence produces re?" (re? (rx (: alpha (* alnum)))))
(test-t "rx multi-form is sequence" (re? (rx alpha digit alpha)))

(test-t "rx: digit matches one digit" (re-match? (rx digit) "5"))
(test-f "rx: digit rejects two digits" (re-match? (rx digit) "55"))
(test-t "rx: (+ digit) matches many" (re-match? (rx (+ digit)) "12345"))
(test-f "rx: (+ digit) rejects empty" (re-match? (rx (+ digit)) ""))
(test-t "rx: alternation" (re-match? (rx (or "yes" "no")) "yes"))
(test-f "rx: alternation misses" (re-match? (rx (or "yes" "no")) "maybe"))
(test-t "rx: sequence" (re-match? (rx alpha digit) "a1"))
(test-f "rx: sequence wrong order" (re-match? (rx alpha digit) "1a"))
;; Note: #r"..." raw string literals require the Jerboa reader (see test-reader-rawstring.ss)
;; Here we verify string patterns in rx work correctly:
(test-t "rx: string pattern in rx" (re-match? (rx "\\d+") "123"))
(test-t "rx: string literal in rx" (re-match? (rx "hello") "hello"))

;;; ========== define-rx — naming and composition ==========

(printf "~%  -- define-rx --~%")

(define-rx my-int (+ digit))
(define-rx my-alpha (+ alpha))
(define-rx my-word (: alpha (* alnum)))

(test-t "define-rx: int is re?" (re? my-int))
(test-t "define-rx: alpha is re?" (re? my-alpha))
(test-t "define-rx: my-int matches digits" (re-match? my-int "42"))
(test-f "define-rx: my-int rejects letters" (re-match? my-int "abc"))
(test-t "define-rx: my-alpha matches letters" (re-match? my-alpha "hello"))
(test-t "define-rx: my-word matches identifier" (re-match? my-word "hello123"))
(test-f "define-rx: my-word rejects digit start" (re-match? my-word "1bad"))

;;; ========== define-rx composition ==========

(printf "~%  -- define-rx composition --~%")

(define-rx octet (** 1 3 digit))
(define-rx ip4   (: octet "." octet "." octet "." octet))

(test-t "composed ip4 matches valid IP" (re-match? ip4 "192.168.1.1"))
(test-t "composed ip4 matches minimal IP" (re-match? ip4 "1.2.3.4"))
(test-f "composed ip4 rejects non-IP" (re-match? ip4 "not-an-ip"))
(test-f "composed ip4 rejects too few octets" (re-match? ip4 "192.168.1"))
(test "composed ip4 finds in text"
  (re-find-all ip4 "hosts: 10.0.0.1 and 192.168.1.254")
  '("10.0.0.1" "192.168.1.254"))

(define-rx kv-sep (or "=" ":"))
(define-rx kv-key (+ (~ (or "=" ":" "\n" " "))))
(define-rx kv-val (* (~ (or "\n"))))
(define-rx kv-pair (: kv-key kv-sep kv-val))

(test-t "composed kv pair matches foo=bar" (re-search kv-pair "foo=bar"))
(test-t "composed kv pair matches x:42" (re-search kv-pair "x:42"))

;;; ========== Named captures in define-rx ==========

(printf "~%  -- named captures (=>) in define-rx --~%")

(define-rx dated
  (: (=> year  (= 4 digit)) "-"
     (=> month (= 2 digit)) "-"
     (=> day   (= 2 digit))))

(let ([m (re-search dated "Event on 2026-04-09 here")])
  (test "named year"  (re-match-named m 'year)  "2026")
  (test "named month" (re-match-named m 'month) "04")
  (test "named day"   (re-match-named m 'day)   "09"))

(define-rx email-cap
  (: (=> local  (+ (or alnum "." "_" "+" "-")))
     "@"
     (=> domain (+ (or alnum "." "-")))))

(let ([m (re-search email-cap "from: user@example.com")])
  (test "named email local"  (re-match-named m 'local)  "user")
  (test "named email domain" (re-match-named m 'domain) "example.com"))

;;; ========== (std rx patterns) ==========

(printf "~%  -- rx:ipv4 --~%")

(test-t "rx:ipv4-octet matches 0"   (re-match? rx:ipv4-octet "0"))
(test-t "rx:ipv4-octet matches 255" (re-match? rx:ipv4-octet "255"))
(test-t "rx:ipv4 matches 192.168.1.1" (re-match? rx:ipv4 "192.168.1.1"))
(test-t "rx:ipv4 matches 10.0.0.1"    (re-match? rx:ipv4 "10.0.0.1"))
(test-f "rx:ipv4 rejects letters"      (re-match? rx:ipv4 "abc.def.ghi.jkl"))
(test-f "rx:ipv4 rejects 3 octets"    (re-match? rx:ipv4 "192.168.1"))
(test "rx:ipv4 find-all"
  (re-find-all rx:ipv4 "10.0.0.1, 172.16.0.1")
  '("10.0.0.1" "172.16.0.1"))

(printf "~%  -- rx:email --~%")

(test-t "rx:email matches simple"    (re-match? rx:email "user@example.com"))
(test-t "rx:email matches with dots" (re-match? rx:email "first.last@sub.example.co"))
(test-f "rx:email rejects no @"      (re-match? rx:email "notanemail"))
(test-f "rx:email rejects no domain" (re-match? rx:email "user@"))

(printf "~%  -- rx:uuid --~%")

(test-t "rx:uuid matches v4"
  (re-match? rx:uuid "550e8400-e29b-41d4-a716-446655440000"))
(test-t "rx:uuid matches uppercase"
  (re-match? rx:uuid "550E8400-E29B-41D4-A716-446655440000"))
(test-f "rx:uuid rejects short"   (re-match? rx:uuid "550e8400-e29b-41d4"))
(test-f "rx:uuid rejects no dashes" (re-match? rx:uuid "550e8400e29b41d4a716446655440000"))

(printf "~%  -- rx:semver --~%")

(test-t "rx:semver: 1.2.3"           (re-match? rx:semver "1.2.3"))
(test-t "rx:semver: 0.0.1"           (re-match? rx:semver "0.0.1"))
(test-t "rx:semver: with pre-release" (re-match? rx:semver "1.2.3-beta.1"))
(test-t "rx:semver: with build"      (re-match? rx:semver "1.2.3+build.42"))
(test-t "rx:semver: both"            (re-match? rx:semver "1.2.3-alpha.1+build.99"))
(test-f "rx:semver: missing patch"   (re-match? rx:semver "1.2"))
(test-f "rx:semver: missing all"     (re-match? rx:semver "1"))

(printf "~%  -- rx:iso8601-date --~%")

(test-t "rx:iso8601-date: 2026-04-09" (re-match? rx:iso8601-date "2026-04-09"))
(test-t "rx:iso8601-date: 2000-01-01" (re-match? rx:iso8601-date "2000-01-01"))
(test-f "rx:iso8601-date: short year" (re-match? rx:iso8601-date "26-04-09"))
(test-f "rx:iso8601-date: no dashes"  (re-match? rx:iso8601-date "20260409"))

(printf "~%  -- rx:iso8601-datetime --~%")

(test-t "rx:iso8601-datetime with T"
  (re-match? rx:iso8601-datetime "2026-04-09T12:30:00"))
(test-t "rx:iso8601-datetime with space"
  (re-match? rx:iso8601-datetime "2026-04-09 12:30:00"))
(test-t "rx:iso8601-datetime with Z"
  (re-match? rx:iso8601-datetime "2026-04-09T12:30:00Z"))
(test-t "rx:iso8601-datetime with offset"
  (re-match? rx:iso8601-datetime "2026-04-09T12:30:00+05:30"))

(printf "~%  -- rx:identifier --~%")

(test-t "rx:identifier: hello"   (re-match? rx:identifier "hello"))
(test-t "rx:identifier: _private" (re-match? rx:identifier "_private"))
(test-t "rx:identifier: foo123"  (re-match? rx:identifier "foo123"))
(test-f "rx:identifier: 123bad"  (re-match? rx:identifier "123bad"))
(test-f "rx:identifier: has-hyphen" (re-match? rx:identifier "has-hyphen"))

(printf "~%  -- rx:hex-color --~%")

(test-t "rx:hex-color: #RRGGBB"   (re-match? rx:hex-color "#FF8800"))
(test-t "rx:hex-color: #rrggbb"   (re-match? rx:hex-color "#ff8800"))
(test-t "rx:hex-color: #RRGGBBAA" (re-match? rx:hex-color "#FF8800CC"))
(test-f "rx:hex-color: no hash"   (re-match? rx:hex-color "FF8800"))
(test-f "rx:hex-color: too short" (re-match? rx:hex-color "#FF88"))
(test-t "rx:hex-color-short: #RGB" (re-match? rx:hex-color-short "#F80"))

(printf "~%  -- rx:numbers --~%")

(test-t "rx:integer: positive"  (re-match? rx:integer "42"))
(test-t "rx:integer: negative"  (re-match? rx:integer "-42"))
(test-t "rx:integer: plus sign" (re-match? rx:integer "+42"))
(test-f "rx:integer: float"     (re-match? rx:integer "3.14"))
(test-t "rx:float: 3.14"        (re-match? rx:float "3.14"))
(test-t "rx:float: -0.5"        (re-match? rx:float "-0.5"))
(test-t "rx:scientific: 1.5e10" (re-match? rx:scientific "1.5e10"))
(test-t "rx:scientific: -2.0E-3" (re-match? rx:scientific "-2.0E-3"))

(printf "~%  -- rx:quoted-string --~%")

(test-t "rx:quoted-string: simple"    (re-match? rx:quoted-string "\"hello\""))
(test-t "rx:quoted-string: with space" (re-match? rx:quoted-string "\"hello world\""))
(test-t "rx:quoted-string: with escape" (re-match? rx:quoted-string "\"say \\\"hi\\\"\""))
(test-t "rx:quoted-string: empty"     (re-match? rx:quoted-string "\"\""))
(test-f "rx:quoted-string: unclosed"  (re-match? rx:quoted-string "\"unclosed"))

;;; ========== Summary ==========
(newline)
(printf "Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
