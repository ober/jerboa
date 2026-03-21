#!chezscheme
;;; (std regex-native) — Regex backed by Rust regex crate (Thompson NFA)
;;;
;;; Guaranteed linear-time matching — ReDoS impossible.
;;; Drop-in alternative to (std pcre2) for trusted and untrusted patterns.

(library (std regex-native)
  (export
    regex-compile regex-match? regex-find
    regex-replace-all regex-free
    rust-last-error)

  (import (chezscheme))

  (define _native-loaded
    (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
        (error 'std/regex-native "libjerboa_native.so not found")))

  (define (bv-sub bv start len)
    (let ([out (make-bytevector len)])
      (bytevector-copy! bv start out 0 len)
      out))

  (define c-jerboa-regex-compile
    (foreign-procedure "jerboa_regex_compile" (u8* size_t u8*) int))

  (define c-jerboa-regex-is-match
    (foreign-procedure "jerboa_regex_is_match" (unsigned-64 u8* size_t) int))

  (define c-jerboa-regex-find
    (foreign-procedure "jerboa_regex_find" (unsigned-64 u8* size_t u8* u8*) int))

  (define c-jerboa-regex-replace-all
    (foreign-procedure "jerboa_regex_replace_all"
      (unsigned-64 u8* size_t u8* size_t u8* size_t u8*) int))

  (define c-jerboa-regex-free
    (foreign-procedure "jerboa_regex_free" (unsigned-64) int))

  (define c-jerboa-last-error
    (foreign-procedure "jerboa_last_error" (u8* size_t) size_t))

  (define (rust-last-error)
    (let ([buf (make-bytevector 512)])
      (let ([len (c-jerboa-last-error buf 512)])
        (if (> len 0)
          (utf8->string (bv-sub buf 0 (min len 511)))
          ""))))

  (define (regex-compile pattern)
    (let ([bv (string->utf8 pattern)]
          [handle-buf (make-bytevector 8)])
      (let ([rc (c-jerboa-regex-compile bv (bytevector-length bv) handle-buf)])
        (when (< rc 0)
          (error 'regex-compile "invalid pattern" pattern (rust-last-error)))
        (bytevector-u64-native-ref handle-buf 0))))

  (define (regex-match? handle text)
    (let ([bv (string->utf8 text)])
      (let ([rc (c-jerboa-regex-is-match handle bv (bytevector-length bv))])
        (when (< rc 0)
          (error 'regex-match? "match failed" (rust-last-error)))
        (= rc 1))))

  (define (regex-find handle text)
    ;; Returns (start . end) or #f
    (let ([bv (string->utf8 text)]
          [start-buf (make-bytevector 8)]
          [end-buf (make-bytevector 8)])
      (let ([rc (c-jerboa-regex-find handle bv (bytevector-length bv)
                                      start-buf end-buf)])
        (cond
          [(< rc 0) (error 'regex-find "find failed" (rust-last-error))]
          [(= rc 0) #f]
          [else (cons (bytevector-u64-native-ref start-buf 0)
                      (bytevector-u64-native-ref end-buf 0))]))))

  (define (regex-replace-all handle text replacement)
    (let ([text-bv (string->utf8 text)]
          [repl-bv (string->utf8 replacement)]
          [out-max (* 4 (+ (string-length text) (string-length replacement)))]
          [len-buf (make-bytevector 8)])
      (let ([out (make-bytevector out-max)])
        (let ([rc (c-jerboa-regex-replace-all handle
                    text-bv (bytevector-length text-bv)
                    repl-bv (bytevector-length repl-bv)
                    out out-max len-buf)])
          (when (< rc 0)
            (error 'regex-replace-all "replace failed" (rust-last-error)))
          (let ([actual-len (bytevector-u64-native-ref len-buf 0)])
            (utf8->string (bv-sub out 0 actual-len)))))))

  (define (regex-free handle)
    (c-jerboa-regex-free handle)
    (void))

  ) ;; end library
