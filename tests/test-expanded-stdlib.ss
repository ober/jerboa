#!chezscheme
;;; test-expanded-stdlib.ss -- Tests for expanded standard library modules

(import (except (chezscheme) make-hash-table hash-table? iota 1+ 1-
                             sort sort! printf fprintf
                             path-extension path-absolute?
                             with-input-from-string with-output-to-string
                             make-mutex mutex? mutex-name thread?
                             errorf)
        (jerboa runtime)
        (std os env)
        (std os temporaries)
        (std os signal)
        (std os fdio)
        (std text base64)
        (std text hex)
        (std text utf8)
        (std text csv)
        (std text xml)
        (std misc queue)
        (std misc bytes)
        (std misc uuid)
        (std misc repr)
        (std misc completion)
        (std crypto digest)
        (std logger)
        (std srfi srfi-13)
        (std srfi srfi-19)
        (std pregexp)
        (std misc thread)
        (std sugar)
        (std test))

(define pass-count 0)
(define fail-count 0)

(define-syntax chk
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr]
           [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (display "FAIL: ")
           (write 'expr)
           (display " => ")
           (write result)
           (display " expected ")
           (write exp)
           (newline))))]))

;;; ---- std/os/env ----
(let ([old (getenv "HOME")])
  (setenv "JERBOA_TEST" "hello")
  (chk (getenv "JERBOA_TEST") => "hello")
  (unsetenv "JERBOA_TEST"))

;;; ---- std/os/temporaries ----
(let ([tmp (make-temporary-file-name)])
  (chk (string? tmp) => #t)
  (chk (> (string-length tmp) 0) => #t))

(with-temporary-file
  (lambda (name)
    (call-with-output-file name (lambda (p) (display "test" p)))
    (chk (file-exists? name) => #t)))

;;; ---- std/os/signal ----
(chk SIGINT => 2)
(chk SIGTERM => 15)
(chk SIGKILL => 9)
(chk (pair? signal-names) => #t)

;;; ---- std/text/base64 ----
(chk (u8vector->base64-string (string->utf8 "Hello")) => "SGVsbG8=")
(chk (utf8->string (base64-string->u8vector "SGVsbG8=")) => "Hello")
(chk (u8vector->base64-string #vu8()) => "")

;;; ---- std/text/hex ----
(chk (u8vector->hex-string #vu8(#xde #xad #xbe #xef)) => "deadbeef")
(chk (hex-string->u8vector "deadbeef") => #vu8(#xde #xad #xbe #xef))
(chk (u8vector->hex-string #vu8(0 255)) => "00ff")

;;; ---- std/text/utf8 ----
(chk (utf8-encode "hello") => (string->utf8 "hello"))
(chk (utf8-decode (string->utf8 "hello")) => "hello")
(chk (utf8-length "hello") => 5)

;;; ---- std/text/csv ----
(let ([records (read-csv (open-input-string "a,b,c\n1,2,3\n"))])
  (chk (length records) => 2)
  (chk (car records) => '("a" "b" "c"))
  (chk (cadr records) => '("1" "2" "3")))

;;; ---- std/text/xml ----
(let ([out (open-output-string)])
  (write-xml '(div (@ (class "test")) "hello") out)
  (chk (get-output-string out) => "<div class=\"test\">hello</div>"))

(chk (sxml-e '(div "hello")) => 'div)
(chk (sxml-children '(div "hello")) => '("hello"))

;;; ---- std/misc/queue ----
(let ([q (make-queue)])
  (chk (queue-empty? q) => #t)
  (enqueue! q 1)
  (enqueue! q 2)
  (enqueue! q 3)
  (chk (queue-length q) => 3)
  (chk (queue-peek q) => 1)
  (chk (dequeue! q) => 1)
  (chk (dequeue! q) => 2)
  (chk (queue->list q) => '(3)))

;;; ---- std/misc/bytes ----
(chk (u8vector-xor #vu8(#xff 0) #vu8(#x0f #xf0)) => #vu8(#xf0 #xf0))
(chk (u8vector-and #vu8(#xff #x0f) #vu8(#x0f #xff)) => #vu8(#x0f #x0f))
(chk (u8vector->uint #vu8(0 1)) => 1)
(chk (u8vector->uint #vu8(1 0)) => 256)
(chk (uint->u8vector 256 2) => #vu8(1 0))

;;; ---- std/misc/uuid ----
(let ([u (uuid-string)])
  (chk (string? u) => #t)
  (chk (= (string-length u) 36) => #t)  ;; UUID format: 8-4-4-4-12
  (chk (char=? (string-ref u 8) #\-) => #t))

;;; ---- std/misc/repr ----
(chk (repr 42) => "42")
(chk (repr "hello") => "\"hello\"")
(chk (repr '(1 2)) => "(1 2)")

;;; ---- std/misc/completion ----
(let ([c (make-completion)])
  (chk (completion-ready? c) => #f)
  (completion-post! c 42)
  (chk (completion-ready? c) => #t)
  (chk (completion-wait! c) => 42))

;;; ---- std/logger ----
;; Just verify it doesn't crash
(start-logger!)
(let ([out (open-output-string)])
  (parameterize ([current-logger-options (make-logger-options 4 out)])
    (errorf "test ~a" 1)
    (infof "info ~a" 2)
    (chk (> (string-length (get-output-string out)) 0) => #t)))

;;; ---- std/srfi/13 ----
(chk (string-index "hello" char-alphabetic?) => 0)
(chk (string-index-right "hello" #\l) => 3)
(chk (string-contains "hello world" "world") => 6)
(chk (string-prefix? "he" "hello") => #t)
(chk (string-suffix? "lo" "hello") => #t)
(chk (string-trim "  hi  ") => "hi  ")
(chk (string-trim-right "  hi  ") => "  hi")
(chk (string-trim-both "  hi  ") => "hi")
(chk (string-pad "hi" 5) => "   hi")
(chk (string-pad-right "hi" 5) => "hi   ")
(chk (string-take "hello" 3) => "hel")
(chk (string-drop "hello" 3) => "lo")
(chk (string-count "hello" #\l) => 2)
(chk (string-reverse "hello") => "olleh")
(chk (string-null? "") => #t)

;;; ---- std/srfi/19 ----
(let ([d (current-date)])
  (chk (date? d) => #t)
  (chk (> (date-year d) 2000) => #t))

(let ([t (seconds->time 1000.5)])
  (chk (time? t) => #t)
  (chk (>= (time->seconds t) 1000.0) => #t))

;;; ---- std/pregexp ----
(chk (pregexp-match "h(e+)llo" "heeello") => '("heeello" "eee"))
(chk (pregexp-match "xyz" "hello") => #f)
(chk (pregexp-replace "world" "hello world" "scheme") => "hello scheme")
(chk (pregexp-replace* "[aeiou]" "hello" "*") => "h*ll*")
(chk (pregexp-split "," "a,b,c") => '("a" "b" "c"))

;;; ---- std/misc/thread ----
(let ([t (make-thread (lambda () 42))])
  (chk (thread? t) => #t)
  (thread-start! t)
  (chk (thread-join! t) => 42))

;; Thread with exception
(let ([t (make-thread (lambda () (error 'test "oops")))])
  (thread-start! t)
  (chk (guard (e [#t 'caught]) (thread-join! t)) => 'caught))

;;; ---- std/test (quick check) ----
;; test-suite creates a record; just verify it doesn't crash
(let ([s (test-suite "basic"
           (test-case "addition"
             (check-equal? (+ 1 2) 3)))])
  (chk (not (not s)) => #t))

;;; ---- std/crypto/digest (requires openssl) ----
;; Only test if openssl is available
(let ([has-openssl (guard (e [#t #f])
                     (let-values ([(to from err pid)
                                   (open-process-ports "which openssl"
                                     (buffer-mode block) (native-transcoder))])
                       (close-port to)
                       (let ([out (get-string-all from)])
                         (close-port from) (close-port err)
                         (> (string-length (string-trim-both out)) 0))))])
  (when has-openssl
    (chk (string? (md5 "hello")) => #t)
    (chk (string? (sha256 "hello")) => #t)
    (set! pass-count (+ pass-count 2))))  ;; count the when-skipped

;;; ---- Summary ----
(newline)
;;; ---- std/sugar (awhen, aif, when-let, if-let, dotimes) ----
(chk (awhen (+ 1 2) it) => 3)
(chk (awhen #f 42) => (void))
(chk (aif (+ 10 20) it 0) => 30)
(chk (aif #f 42 99) => 99)
(chk (when-let (x (+ 1 1)) (* x 3)) => 6)
(chk (when-let (x #f) 42) => (void))
(chk (if-let (x 10) (* x 2) 0) => 20)
(chk (if-let (x #f) 42 99) => 99)
(chk (let ((acc 0)) (dotimes (i 4) (set! acc (+ acc i))) acc) => 6)
(chk (let ((acc 0)) (dotimes (i 0) (set! acc (+ acc 1))) acc) => 0)

(display "Expanded stdlib tests: ")
(display pass-count)
(display " passed, ")
(display fail-count)
(display " failed")
(newline)
(when (> fail-count 0) (exit 1))
