#!chezscheme
(import (chezscheme) (std pcre2))

(define pass-count 0)
(define fail-count 0)

(define-syntax chk
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr] [exp expected])
       (if (equal? result exp) (set! pass-count (+ pass-count 1))
         (begin (set! fail-count (+ fail-count 1))
                (display "FAIL: ") (write 'expr)
                (display " => ") (write result)
                (display " expected ") (write exp) (newline))))]))

(chk (pcre2-matches? "\\d+" "abc123") => #t)
(chk (pcre2-matches? "\\d+" "abc") => #f)
(chk (pcre2-extract "\\d+" "a1 b22 c333") => '("1" "22" "333"))
(chk (pcre2-split ",\\s*" "a, b, c") => '("a" "b" "c"))
(chk (pcre2-replace-all "o" "foobar" "0") => "f00bar")

(let ([m (pcre2-search "h(e+)llo" "heeello")])
  (chk (pcre-match-group m 0) => "heeello")
  (chk (pcre-match-group m 1) => "eee"))

(display "  pcre2: ") (display pass-count) (display " passed")
(when (> fail-count 0) (display ", ") (display fail-count) (display " failed"))
(newline)
(when (> fail-count 0) (exit 1))
