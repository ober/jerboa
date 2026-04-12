#!/usr/bin/env scheme-script
#!chezscheme
;;; Tests for security2.md parser robustness fixes

(import (chezscheme)
        (std text base64)
        (std text csv)
        (std text hex)
        (std text json)
        (std text xml)
        (std format)
        (std schema)
        (std pregexp)
        (std net dns)
        (std net websocket)
        (jerboa reader))

(define test-count 0)
(define pass-count 0)
(define fail-count 0)

(define (test name thunk)
  (set! test-count (+ test-count 1))
  (guard (e [#t
             (set! fail-count (+ fail-count 1))
             (display (string-append "FAIL: " name "\n"))
             (display (string-append "  Error: "
               (if (message-condition? e)
                 (condition-message e)
                 "unknown error")
               "\n"))])
    (thunk)
    (set! pass-count (+ pass-count 1))
    (display (string-append "PASS: " name "\n"))))

(define (assert-true msg val)
  (unless val (error 'assert-true msg)))

(define (assert-false msg val)
  (when val (error 'assert-false msg)))

(define (assert-equal msg expected actual)
  (unless (equal? expected actual)
    (error 'assert-equal msg expected actual)))

(define (assert-error msg thunk)
  (let ([got-error #f])
    (guard (e [#t (set! got-error #t)])
      (thunk))
    (unless got-error
      (error 'assert-error msg))))

(display "=== Security2 Parser Robustness Tests ===\n\n")

;;; ============ Base64 ============
(display "--- Base64 strict validation ---\n")

(test "base64: valid encode/decode roundtrip"
  (lambda ()
    (let* ([bv (string->utf8 "Hello, World!")]
           [encoded (base64-encode bv)]
           [decoded (base64-decode encoded)])
      (assert-equal "roundtrip" bv decoded))))

(test "base64: invalid character rejected"
  (lambda ()
    (assert-error "should reject @"
      (lambda () (base64-decode "abc@def=")))))

(test "base64: invalid character # rejected"
  (lambda ()
    (assert-error "should reject #"
      (lambda () (base64-decode "abc#")))))

(test "base64: padding in middle rejected"
  (lambda ()
    (assert-error "should reject = in middle"
      (lambda () (base64-decode "ab=cdefg")))))

(test "base64: empty string"
  (lambda ()
    (let ([result (base64-decode "")])
      (assert-equal "empty" (make-bytevector 0) result))))

;;; ============ CSV ============
(display "\n--- CSV strict quotes ---\n")

(test "csv: normal quoted field"
  (lambda ()
    (let* ([port (open-input-string "\"hello\",world")]
           [records (read-csv port)])
      (assert-equal "parsed" '(("hello" "world")) records))))

(test "csv: unterminated quote rejected (strict)"
  (lambda ()
    (assert-error "should reject unterminated"
      (lambda ()
        (parameterize ((*csv-strict-quotes* #t))
          (let ([port (open-input-string "\"hello\")])
            (read-csv port)))))))

(test "csv: unterminated quote accepted (permissive)"
  (lambda ()
    (parameterize ((*csv-strict-quotes* #f))
      (let* ([port (open-input-string "\"hello")]
             [records (read-csv port)])
        (assert-true "got result" (list? records))))))

(test "csv: escaped quotes"
  (lambda ()
    (let* ([port (open-input-string "\"he\"\"llo\",world")]
           [records (read-csv port)])
      (assert-equal "escaped" '(("he\"llo" "world")) records))))

;;; ============ Hex ============
(display "\n--- Hex strict validation ---\n")

(test "hex: valid encode/decode roundtrip"
  (lambda ()
    (let* ([bv #vu8(1 2 255 0 128)]
           [encoded (hex-encode bv)]
           [decoded (hex-decode encoded)])
      (assert-equal "roundtrip" bv decoded))))

(test "hex: odd-length rejected"
  (lambda ()
    (assert-error "should reject odd length"
      (lambda () (hex-decode "abc")))))

(test "hex: single char rejected"
  (lambda ()
    (assert-error "should reject single char"
      (lambda () (hex-decode "f")))))

(test "hex: invalid character rejected"
  (lambda ()
    (assert-error "should reject 'xyz'"
      (lambda () (hex-decode "xyzw")))))

(test "hex: empty string"
  (lambda ()
    (let ([result (hex-decode "")])
      (assert-equal "empty" (make-bytevector 0) result))))

;;; ============ JSON ============
(display "\n--- JSON depth & size limits ---\n")

(test "json: normal parse"
  (lambda ()
    (let ([obj (string->json-object "{\"key\":\"value\"}")])
      (assert-true "is hashtable" (hashtable? obj)))))

(test "json: array parse"
  (lambda ()
    (let ([arr (string->json-object "[1,2,3]")])
      (assert-equal "array" '(1 2 3) arr))))

(test "json: depth limit exceeded"
  (lambda ()
    (assert-error "should reject deep nesting"
      (lambda ()
        (parameterize ((*json-max-depth* 5))
          (string->json-object
            (string-append
              (make-string 10 #\[)
              "1"
              (make-string 10 #\]))))))))

(test "json: depth limit - valid depth passes"
  (lambda ()
    (parameterize ((*json-max-depth* 10))
      (let ([result (string->json-object "[[1]]")])
        (assert-true "parsed" (list? result))))))

(test "json: string length limit"
  (lambda ()
    (assert-error "should reject huge string"
      (lambda ()
        (parameterize ((*json-max-string-length* 10))
          (string->json-object
            (string-append "\"" (make-string 20 #\a) "\"")))))))

;;; ============ Format ============
(display "\n--- Safe format functions ---\n")

(test "safe-printf: no directive processing"
  (lambda ()
    (let ([port (open-output-string)])
      (parameterize ((current-output-port port))
        (safe-printf "hello ~a world"))
      (assert-equal "literal" "hello ~a world" (get-output-string port)))))

(test "safe-printf: with extra args"
  (lambda ()
    (let ([port (open-output-string)])
      (parameterize ((current-output-port port))
        (safe-printf "value: " 42))
      (assert-equal "concat" "value: 42" (get-output-string port)))))

(test "safe-fprintf: to port"
  (lambda ()
    (let ([port (open-output-string)])
      (safe-fprintf port "~a test ~s" " extra")
      (assert-equal "literal" "~a test ~s extra" (get-output-string port)))))

;;; ============ Reader ============
(display "\n--- Reader depth limits ---\n")

(test "reader: normal s-expression"
  (lambda ()
    (let ([result (jerboa-read-string "(+ 1 2)")])
      (assert-equal "parsed" '((+ 1 2)) result))))

(test "reader: depth limit exceeded"
  (lambda ()
    (assert-error "should reject deep nesting"
      (lambda ()
        (parameterize ((*max-read-depth* 5))
          (jerboa-read-string
            (string-append
              (make-string 10 #\()
              "x"
              (make-string 10 #\)))))))))

(test "reader: depth limit - valid depth passes"
  (lambda ()
    (parameterize ((*max-read-depth* 10))
      (let ([result (jerboa-read-string "((x))")])
        (assert-true "parsed" (list? result))))))

(test "reader: block comment depth limit"
  (lambda ()
    (assert-error "should reject deeply nested block comments"
      (lambda ()
        (parameterize ((*max-block-comment-depth* 3))
          (jerboa-read-string
            (string-append
              "#| #| #| #| #| deep |# |# |# |# |# 42")))))))

(test "reader: normal block comment"
  (lambda ()
    (let ([result (jerboa-read-string "#| comment |# 42")])
      (assert-equal "after comment" '(42) result))))

;;; ============ XML ============
(display "\n--- XML/SXML depth limit ---\n")

(test "xml: normal serialization"
  (lambda ()
    (let ([port (open-output-string)])
      (write-xml '(div (p "hello")) port)
      (assert-true "has content" (> (string-length (get-output-string port)) 0)))))

(test "xml: depth limit exceeded"
  (lambda ()
    ;; Build a deeply nested SXML tree
    (let ([deep-tree
            (let loop ([depth 0] [inner "leaf"])
              (if (>= depth 600)
                inner
                (loop (+ depth 1) (list 'div inner))))])
      (assert-error "should reject deep tree"
        (lambda ()
          (parameterize ((*sxml-max-depth* 100))
            (let ([port (open-output-string)])
              (write-xml deep-tree port))))))))

;;; ============ Schema ============
(display "\n--- Schema depth limit ---\n")

(test "schema: normal validation"
  (lambda ()
    (assert-true "string valid" (schema-valid? s:string "hello"))))

(test "schema: type mismatch"
  (lambda ()
    (assert-false "int not string" (schema-valid? s:string 42))))

;;; ============ DNS ============
(display "\n--- DNS bounds checks ---\n")

(test "dns: encode/decode name roundtrip"
  (lambda ()
    (let* ([encoded (dns-encode-name "www.example.com")]
           [decoded (dns-decode-name encoded 0)])
      (assert-equal "name" "www.example.com" (car decoded)))))

(test "dns: decode response too short"
  (lambda ()
    (assert-error "should reject short bv"
      (lambda () (dns-decode-response (make-bytevector 6))))))

(test "dns: decode name out of bounds"
  (lambda ()
    (assert-error "should reject OOB offset"
      (lambda () (dns-decode-name #vu8(3 119 119 119) 10)))))

(test "dns: compression pointer loop detection"
  (lambda ()
    ;; Create a bytevector with a compression pointer that points to itself
    ;; offset 0: compression pointer to offset 0 -> infinite loop
    (assert-error "should detect loop"
      (lambda ()
        (dns-decode-name #vu8(#xC0 #x00) 0)))))

;;; ============ WebSocket ============
(display "\n--- WebSocket bounds checks ---\n")

(test "ws: encode/decode roundtrip"
  (lambda ()
    (let* ([payload (string->utf8 "hello")]
           [frame (ws-text-frame payload)]
           [encoded (ws-frame-encode frame)]
           [decoded (ws-frame-decode encoded)])
      (assert-equal "payload" payload (ws-frame-payload decoded)))))

(test "ws: too short for header"
  (lambda ()
    (assert-error "should reject 1-byte"
      (lambda () (ws-frame-decode #vu8(#x81))))))

(test "ws: too short for 16-bit length"
  (lambda ()
    (assert-error "should reject short 16-bit"
      (lambda () (ws-frame-decode #vu8(#x81 126 0))))))

(test "ws: payload size cap"
  (lambda ()
    (assert-error "should reject huge payload"
      (lambda ()
        (parameterize ((*ws-max-payload-size* 10))
          ;; Frame header says 100 bytes but bv is small
          (ws-frame-decode #vu8(#x81 100 0 0 0 0 0 0 0 0 0 0)))))))

;;; ============ Pregexp ============
(display "\n--- Pregexp backtracking limit ---\n")

(test "pregexp: normal match"
  (lambda ()
    (let ([result (pregexp-match "hello" "hello world")])
      (assert-true "matched" (and result (string=? (car result) "hello"))))))

(test "pregexp: backtracking limit"
  (lambda ()
    (assert-error "should hit limit on pathological pattern"
      (lambda ()
        (parameterize ((*pregexp-max-steps* 1000))
          ;; Pathological pattern: (a+)+b against many a's and no b
          (pregexp-match "(a+)+b" (make-string 30 #\a)))))))

(test "pregexp: normal pattern within budget"
  (lambda ()
    (let ([result (pregexp-match "a+" "aaa")])
      (assert-true "matched" (and result (string=? (car result) "aaa"))))))

;;; ============ Summary ============
(display "\n=== Results ===\n")
(display (string-append "Total:  " (number->string test-count) "\n"))
(display (string-append "Passed: " (number->string pass-count) "\n"))
(display (string-append "Failed: " (number->string fail-count) "\n"))

(when (> fail-count 0)
  (exit 1))
