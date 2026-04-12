#!chezscheme
;;; (std nrepl) — nREPL server for Clojure editor integration
;;;
;;; Implements the nREPL protocol (bencode over TCP) so that Clojure
;;; editors like CIDER (Emacs), Calva (VS Code), and Cursive (IntelliJ)
;;; can connect to a running Jerboa process.
;;;
;;; Usage:
;;;   (import (std nrepl))
;;;   (nrepl-start! 7888)              ;; start on port 7888
;;;   (nrepl-start!)                   ;; start on random port, prints it
;;;   (nrepl-stop!)                    ;; stop the server
;;;
;;; Supported ops: clone, close, describe, eval, load-file,
;;;   completions, lookup, interrupt, stdin (no-op)
;;;
;;; Writes .nrepl-port in current directory so editors auto-discover.
;;;
;;; Protocol reference: https://nrepl.org/nrepl/building_servers.html

(library (std nrepl)
  (export nrepl-start! nrepl-stop!
          nrepl-server-port nrepl-running?)

  (import (chezscheme)
          (std repl))

  ;; ================================================================
  ;; Bencode Encoder/Decoder (binary, self-contained)
  ;; ================================================================
  ;; Bencode is a byte-oriented format:
  ;;   Integer:  i<decimal-ascii>e       e.g. i42e
  ;;   String:   <length>:<bytes>        e.g. 5:hello
  ;;   List:     l<items>e
  ;;   Dict:     d<key><value>...e       keys are strings, sorted
  ;;
  ;; We work on binary ports and convert strings to/from UTF-8.

  (define (string->bv s)
    (string->bytevector s (make-transcoder (utf-8-codec))))

  (define (bv->string bv)
    (bytevector->string bv (make-transcoder (utf-8-codec))))

  (define (bencode-encode obj)
    (let-values ([(out extract) (open-bytevector-output-port)])
      (bencode-write obj out)
      (extract)))

  (define (bencode-write obj port)
    (cond
      [(and (integer? obj) (exact? obj))
       (put-u8 port (char->integer #\i))
       (put-bytevector port (string->bv (number->string obj)))
       (put-u8 port (char->integer #\e))]
      [(string? obj)
       (let ([bv (string->bv obj)])
         (put-bytevector port (string->bv (number->string (bytevector-length bv))))
         (put-u8 port (char->integer #\:))
         (put-bytevector port bv))]
      [(symbol? obj)
       (bencode-write (symbol->string obj) port)]
      [(list? obj)
       (put-u8 port (char->integer #\l))
       (for-each (lambda (item) (bencode-write item port)) obj)
       (put-u8 port (char->integer #\e))]
      [(hashtable? obj)
       (put-u8 port (char->integer #\d))
       (let-values ([(keys vals) (hashtable-entries obj)])
         (let* ([n (vector-length keys)]
                [pairs (let lp ([i 0] [acc '()])
                         (if (= i n) acc
                             (lp (+ i 1)
                                 (cons (cons (if (string? (vector-ref keys i))
                                                 (vector-ref keys i)
                                                 (format "~a" (vector-ref keys i)))
                                             (vector-ref vals i))
                                       acc))))]
                [sorted (sort (lambda (a b) (string<? (car a) (car b))) pairs)])
           (for-each (lambda (pair)
                       (bencode-write (car pair) port)
                       (bencode-write (cdr pair) port))
                     sorted)))
       (put-u8 port (char->integer #\e))]
      [(boolean? obj)
       (bencode-write (if obj "true" "false") port)]
      [else
       (bencode-write (format "~a" obj) port)]))

  ;; Read a bencode value from a binary input port.
  ;; Returns the decoded value or (eof-object).
  (define (bencode-read port)
    (let ([b (get-u8 port)])
      (cond
        [(eof-object? b) b]
        [(= b (char->integer #\i)) (bencode-read-int port)]
        [(= b (char->integer #\l)) (bencode-read-list port)]
        [(= b (char->integer #\d)) (bencode-read-dict port)]
        [(<= (char->integer #\0) b (char->integer #\9))
         (bencode-read-string b port)]
        [else (error 'bencode-read "unexpected byte in bencode stream" b)])))

  (define (bencode-read-int port)
    ;; 'i' already consumed; read digits until 'e'
    (let lp ([acc '()])
      (let ([b (get-u8 port)])
        (cond
          [(eof-object? b) (error 'bencode-read-int "unexpected EOF in integer")]
          [(= b (char->integer #\e))
           (string->number (list->string (reverse acc)))]
          [else (lp (cons (integer->char b) acc))]))))

  (define (bencode-read-string first-byte port)
    ;; first digit already read; read remaining length digits, then ':'
    (let lp ([acc (list (integer->char first-byte))])
      (let ([b (get-u8 port)])
        (cond
          [(eof-object? b) (error 'bencode-read-string "unexpected EOF in string length")]
          [(= b (char->integer #\:))
           (let* ([len (string->number (list->string (reverse acc)))]
                  [bv (get-bytevector-n port len)])
             (if (eof-object? bv)
                 (error 'bencode-read-string "unexpected EOF in string data")
                 (bv->string bv)))]
          [else (lp (cons (integer->char b) acc))]))))

  (define (bencode-read-list port)
    ;; 'l' already consumed; read items until 'e'
    (let lp ([acc '()])
      (let ([b (lookahead-u8 port)])
        (cond
          [(eof-object? b) (error 'bencode-read-list "unexpected EOF in list")]
          [(= b (char->integer #\e))
           (get-u8 port)  ;; consume 'e'
           (reverse acc)]
          [else (lp (cons (bencode-read port) acc))]))))

  (define (bencode-read-dict port)
    ;; 'd' already consumed; read key-value pairs until 'e'
    (let ([ht (make-hashtable string-hash string=?)])
      (let lp ()
        (let ([b (lookahead-u8 port)])
          (cond
            [(eof-object? b) (error 'bencode-read-dict "unexpected EOF in dict")]
            [(= b (char->integer #\e))
             (get-u8 port)  ;; consume 'e'
             ht]
            [else
             (let* ([key (bencode-read port)]
                    [val (bencode-read port)])
               (hashtable-set! ht
                 (if (string? key) key (format "~a" key))
                 val)
               (lp))])))))

  ;; ================================================================
  ;; UUID Generation
  ;; ================================================================
  ;; Read from /dev/urandom for proper randomness.

  (define (generate-uuid)
    (let ([bv (make-bytevector 16)])
      (guard (exn
               [#t
                ;; Fallback: use time + random if /dev/urandom unavailable
                (let ([t (time-nanosecond (current-time))]
                      [r (random (expt 2 48))])
                  (format "~8,'0x-~4,'0x-~4,'0x-~4,'0x-~12,'0x"
                    (bitwise-and t #xFFFFFFFF)
                    (bitwise-and (bitwise-arithmetic-shift-right t 32) #xFFFF)
                    (bitwise-ior #x4000 (bitwise-and r #x0FFF))
                    (bitwise-ior #x8000 (bitwise-and (bitwise-arithmetic-shift-right r 12) #x3FFF))
                    (bitwise-and (bitwise-arithmetic-shift-right r 26) #xFFFFFFFFFFFF)))])
        (let ([p (open-file-input-port "/dev/urandom")])
          (get-bytevector-n! p bv 0 16)
          (close-port p)
          ;; Set version 4 (random) and variant 1 bits
          (bytevector-u8-set! bv 6
            (bitwise-ior #x40 (bitwise-and (bytevector-u8-ref bv 6) #x0F)))
          (bytevector-u8-set! bv 8
            (bitwise-ior #x80 (bitwise-and (bytevector-u8-ref bv 8) #x3F)))
          (format "~2,'0x~2,'0x~2,'0x~2,'0x-~2,'0x~2,'0x-~2,'0x~2,'0x-~2,'0x~2,'0x-~2,'0x~2,'0x~2,'0x~2,'0x~2,'0x~2,'0x"
            (bytevector-u8-ref bv 0) (bytevector-u8-ref bv 1)
            (bytevector-u8-ref bv 2) (bytevector-u8-ref bv 3)
            (bytevector-u8-ref bv 4) (bytevector-u8-ref bv 5)
            (bytevector-u8-ref bv 6) (bytevector-u8-ref bv 7)
            (bytevector-u8-ref bv 8) (bytevector-u8-ref bv 9)
            (bytevector-u8-ref bv 10) (bytevector-u8-ref bv 11)
            (bytevector-u8-ref bv 12) (bytevector-u8-ref bv 13)
            (bytevector-u8-ref bv 14) (bytevector-u8-ref bv 15))))))

  ;; ================================================================
  ;; Session Management
  ;; ================================================================
  ;; Each session has an eval environment (shared interaction-environment
  ;; for now—Chez doesn't cheaply clone environments).

  (define *sessions* (make-hashtable string-hash string=?))
  (define *sessions-mutex* (make-mutex))

  (define (create-session!)
    (let ([id (generate-uuid)])
      (with-mutex *sessions-mutex*
        (hashtable-set! *sessions* id (interaction-environment)))
      id))

  (define (session-env session-id)
    (with-mutex *sessions-mutex*
      (hashtable-ref *sessions* session-id (interaction-environment))))

  (define (close-session! id)
    (with-mutex *sessions-mutex*
      (hashtable-delete! *sessions* id)))

  ;; ================================================================
  ;; Response Helpers
  ;; ================================================================

  (define (dict-ref ht key . default)
    (if (and (hashtable? ht) (hashtable-contains? ht key))
        (hashtable-ref ht key #f)
        (if (pair? default) (car default) #f)))

  (define (make-dict . kvs)
    (let ([ht (make-hashtable string-hash string=?)])
      (let lp ([rest kvs])
        (cond
          [(null? rest) ht]
          [(null? (cdr rest)) (error 'make-dict "odd number of arguments")]
          [else
           (hashtable-set! ht (car rest) (cadr rest))
           (lp (cddr rest))]))))

  (define (make-response msg . kvs)
    ;; Build a response dict, echoing "id" and "session" from request.
    (let ([ht (apply make-dict kvs)])
      (let ([id (dict-ref msg "id")])
        (when id (hashtable-set! ht "id" id)))
      (let ([session (dict-ref msg "session")])
        (when session (hashtable-set! ht "session" session)))
      ht))

  (define (send-response! port msg)
    (let ([bv (bencode-encode msg)])
      (put-bytevector port bv)
      (flush-output-port port)))

  ;; ================================================================
  ;; nREPL Operation Handlers
  ;; ================================================================

  (define (handle-clone msg out)
    (let ([new-id (create-session!)])
      (send-response! out
        (make-response msg
          "new-session" new-id
          "status" (list "done")))))

  (define (handle-close msg out)
    (let ([session (dict-ref msg "session")])
      (when session (close-session! session)))
    (send-response! out
      (make-response msg "status" (list "done"))))

  (define (handle-describe msg out)
    (send-response! out
      (make-response msg
        "ops" (make-dict
                "clone"        (make-dict)
                "close"        (make-dict)
                "describe"     (make-dict)
                "eval"         (make-dict)
                "load-file"    (make-dict)
                "completions"  (make-dict)
                "lookup"       (make-dict)
                "interrupt"    (make-dict)
                "stdin"        (make-dict))
        "versions" (make-dict
                     "nrepl"  (make-dict "major" 1 "minor" 0 "incremental" 0)
                     "jerboa" (make-dict "major" 1 "minor" 0 "incremental" 0))
        "aux" (make-dict
                "current-ns" "user")
        "status" (list "done"))))

  (define (handle-eval msg out)
    (let ([code    (dict-ref msg "code" "")]
          [session (dict-ref msg "session")]
          [ns      (dict-ref msg "ns" "user")])
      (let ([env (if session (session-env session) (interaction-environment))])
        (guard (exn
                 [#t
                  (let ([err-msg (if (message-condition? exn)
                                     (condition-message exn)
                                     (format "~a" exn))]
                        [err-class (if (condition? exn)
                                       (with-output-to-string
                                         (lambda ()
                                           (display-condition exn)))
                                       (format "~a" exn))])
                    ;; Send stderr
                    (send-response! out
                      (make-response msg "err" (string-append err-class "\n")))
                    ;; Send error status
                    (send-response! out
                      (make-response msg
                        "ex" err-class
                        "root-ex" err-class
                        "status" (list "eval-error" "done"))))])
          ;; Capture stdout/stderr during eval
          (let ([stdout-capture (open-output-string)]
                [stderr-capture (open-output-string)])
            ;; Read all forms from the code string and evaluate them
            (let ([inp (open-input-string code)])
              (let lp ([last-val (void)])
                (let ([form (read inp)])
                  (if (eof-object? form)
                      (begin
                        ;; Flush captured stdout
                        (let ([stdout-str (get-output-string stdout-capture)])
                          (when (> (string-length stdout-str) 0)
                            (send-response! out
                              (make-response msg "out" stdout-str))))
                        ;; Flush captured stderr
                        (let ([stderr-str (get-output-string stderr-capture)])
                          (when (> (string-length stderr-str) 0)
                            (send-response! out
                              (make-response msg "err" stderr-str))))
                        ;; Send value
                        (unless (eq? last-val (void))
                          (send-response! out
                            (make-response msg
                              "value" (format "~s" last-val)
                              "ns" ns)))
                        ;; Send done
                        (send-response! out
                          (make-response msg "status" (list "done"))))
                      (let ([result
                              (parameterize ([current-output-port stdout-capture]
                                             [current-error-port stderr-capture])
                                (eval form env))])
                        ;; Flush incremental stdout between forms
                        (let ([s (get-output-string stdout-capture)])
                          (when (> (string-length s) 0)
                            (send-response! out
                              (make-response msg "out" s))
                            ;; Reset the capture port
                            (set! stdout-capture (open-output-string))))
                        (lp result)))))))))))

  (define (handle-load-file msg out)
    (let ([file-content (dict-ref msg "file" "")]
          [file-name    (dict-ref msg "file-name" "unknown")]
          [file-path    (dict-ref msg "file-path" "")]
          [session      (dict-ref msg "session")])
      (let ([env (if session (session-env session) (interaction-environment))])
        (guard (exn
                 [#t
                  (let ([err-msg (if (message-condition? exn)
                                     (condition-message exn)
                                     (format "~a" exn))])
                    (send-response! out
                      (make-response msg
                        "ex" err-msg
                        "root-ex" err-msg
                        "status" (list "eval-error" "done"))))])
          (let ([inp (open-input-string file-content)])
            (let lp ([last-val (void)])
              (let ([form (read inp)])
                (if (eof-object? form)
                    (begin
                      (send-response! out
                        (make-response msg
                          "value" (format "~s" last-val)
                          "ns" "user"))
                      (send-response! out
                        (make-response msg "status" (list "done"))))
                    (lp (eval form env))))))))))

  (define (handle-completions msg out)
    (let ([prefix  (or (dict-ref msg "prefix")
                       (dict-ref msg "symbol")
                       "")]
          [session (dict-ref msg "session")])
      (let* ([env (if session (session-env session) (interaction-environment))]
             [matches (repl-complete prefix env)]
             [completions
               (map (lambda (sym)
                      (make-dict "candidate" (symbol->string sym)))
                    (take-up-to matches 100))])
        (send-response! out
          (make-response msg
            "completions" completions
            "status" (list "done"))))))

  (define (handle-lookup msg out)
    (let ([sym-name (or (dict-ref msg "sym")
                        (dict-ref msg "symbol")
                        "")]
          [session  (dict-ref msg "session")])
      (let ([env (if session (session-env session) (interaction-environment))]
            [sym (string->symbol sym-name)])
        (guard (exn
                 [#t
                  (send-response! out
                    (make-response msg "status" (list "no-info" "done")))])
          (let ([val (eval sym env)])
            (let ([info (make-dict "name" sym-name "ns" "user")])
              (cond
                [(procedure? val)
                 (hashtable-set! info "arglists-str" "(args...)")
                 (hashtable-set! info "doc"
                   (let ([doc (repl-doc sym)])
                     (if (string? doc) doc (format "~a" doc))))]
                [else
                 (hashtable-set! info "doc"
                   (format "~a : ~a" sym-name (value->type-string val)))])
              (send-response! out
                (make-response msg
                  "info" info
                  "status" (list "done")))))))))

  (define (handle-interrupt msg out)
    ;; No-op for now — interrupt support requires engine/thread tracking
    (send-response! out
      (make-response msg
        "status" (list "done"))))

  (define (handle-stdin msg out)
    ;; stdin forwarding — acknowledge but no-op
    (send-response! out
      (make-response msg
        "status" (list "done"))))

  ;; ================================================================
  ;; Message Dispatch
  ;; ================================================================

  (define (handle-message msg out)
    (let ([op (dict-ref msg "op" "")])
      (cond
        [(string=? op "clone")       (handle-clone msg out)]
        [(string=? op "close")       (handle-close msg out)]
        [(string=? op "describe")    (handle-describe msg out)]
        [(string=? op "eval")        (handle-eval msg out)]
        [(string=? op "load-file")   (handle-load-file msg out)]
        [(string=? op "completions") (handle-completions msg out)]
        [(string=? op "lookup")      (handle-lookup msg out)]
        [(string=? op "interrupt")   (handle-interrupt msg out)]
        [(string=? op "stdin")       (handle-stdin msg out)]
        [else
         (send-response! out
           (make-response msg
             "status" (list "error" "unknown-op" "done")))])))

  ;; ================================================================
  ;; Client Connection Handler
  ;; ================================================================

  (define (handle-client in out)
    (let lp ()
      (guard (exn
               [#t (void)])  ;; client disconnected or protocol error
        (let ([msg (bencode-read in)])
          (unless (eof-object? msg)
            (guard (exn
                     [#t
                      ;; Handler error — send error response, keep connection alive
                      (guard (e2 [#t (void)])
                        (send-response! out
                          (make-response msg
                            "status" (list "error" "done")
                            "ex" (if (message-condition? exn)
                                     (condition-message exn)
                                     (format "~a" exn)))))])
              (handle-message msg out))
            (lp))))))

  ;; ================================================================
  ;; Utility
  ;; ================================================================

  (define (take-up-to lst n)
    (let lp ([l lst] [n n] [acc '()])
      (if (or (zero? n) (null? l))
          (reverse acc)
          (lp (cdr l) (- n 1) (cons (car l) acc)))))

  ;; ================================================================
  ;; TCP Server (inline socket FFI — same pattern as (std repl server))
  ;; ================================================================
  ;; Self-contained to avoid circular dependencies with (std net tcp).

  (define _libc-loaded
    (let ((v (getenv "JEMACS_STATIC")))
      (if (and v (not (string=? v "")) (not (string=? v "0")))
          #f  ;; symbols already in static binary
          (load-shared-object #f))))

  (define c-socket      (foreign-procedure "socket" (int int int) int))
  (define c-bind        (foreign-procedure "bind" (int u8* int) int))
  (define c-listen      (foreign-procedure "listen" (int int) int))
  (define c-accept      (foreign-procedure "accept" (int u8* u8*) int))
  (define c-close       (foreign-procedure "close" (int) int))
  (define c-setsockopt  (foreign-procedure "setsockopt" (int int int u8* int) int))
  (define c-htons       (foreign-procedure "htons" (unsigned-short) unsigned-short))
  (define c-fcntl       (foreign-procedure "fcntl" (int int int) int))
  (define c-getsockname (foreign-procedure "getsockname" (int u8* u8*) int))
  (define c-read        (foreign-procedure "read" (int u8* size_t) ssize_t))
  (define c-write       (foreign-procedure "write" (int u8* size_t) ssize_t))

  ;; errno access — platform-specific symbol
  (define c-errno-location
    (let ((mt (symbol->string (machine-type))))
      (cond
        ((or (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb))
             (and (>= (string-length mt) 3)
                  (string=? (substring mt (- (string-length mt) 3) (string-length mt)) "osx")))
         (foreign-procedure "__error" () void*))
        ((foreign-entry? "__errno_location")
         (foreign-procedure "__errno_location" () void*))
        ((foreign-entry? "__errno")
         (foreign-procedure "__errno" () void*))
        (else
         (foreign-procedure "__errno_location" () void*)))))
  (define (get-errno) (foreign-ref 'int (c-errno-location) 0))
  (define EINTR 4)
  (define *freebsd?* (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb)))
  (define EAGAIN (if *freebsd?* 35 11))

  ;; fcntl constants
  (define F_GETFL 3)
  (define F_SETFL 4)
  (define O_NONBLOCK
    (if (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb)) #x4 #x800))

  ;; Socket constants
  (define AF_INET 2)
  (define SOCK_STREAM 1)
  (define SOL_SOCKET (if *freebsd?* #xffff 1))
  (define SO_REUSEADDR (if *freebsd?* 4 2))

  ;; GC-safe retry delay: 10ms (Chez sleep responds to GC signals)
  (define *retry-delay* (make-time 'time-duration 10000000 0))

  (define (set-nonblocking! fd)
    (let ([flags (c-fcntl fd F_GETFL 0)])
      (c-fcntl fd F_SETFL (fxior flags O_NONBLOCK))))

  (define (make-sockaddr-in port)
    ;; struct sockaddr_in: family(2) + port(2) + addr(4) + zero(8) = 16 bytes
    ;; Binds to 127.0.0.1 (localhost only)
    (let ([buf (make-bytevector 16 0)])
      (if *freebsd?*
          (begin
            (bytevector-u8-set! buf 0 16)        ;; sin_len
            (bytevector-u8-set! buf 1 AF_INET))  ;; sin_family (uint8)
          (bytevector-u16-native-set! buf 0 AF_INET))
      (bytevector-u16-set! buf 2 (c-htons port) 'big)
      ;; sin_addr = 127.0.0.1
      (bytevector-u8-set! buf 4 127)
      (bytevector-u8-set! buf 5 0)
      (bytevector-u8-set! buf 6 0)
      (bytevector-u8-set! buf 7 1)
      buf))

  (define (tcp-listen* port)
    (let ([sock (c-socket AF_INET SOCK_STREAM 0)])
      (when (< sock 0) (error 'nrepl-start! "socket() failed"))
      ;; SO_REUSEADDR
      (let ([one (make-bytevector 4 0)])
        (bytevector-s32-native-set! one 0 1)
        (c-setsockopt sock SOL_SOCKET SO_REUSEADDR one 4))
      ;; Bind
      (let ([addr (make-sockaddr-in port)])
        (when (< (c-bind sock addr 16) 0)
          (c-close sock)
          (error 'nrepl-start! "bind() failed — port may be in use" port)))
      ;; Listen
      (when (< (c-listen sock 8) 0)
        (c-close sock)
        (error 'nrepl-start! "listen() failed"))
      ;; Set non-blocking for GC-safe accept loop
      (set-nonblocking! sock)
      ;; Get actual port (important when port=0)
      (let ([addr-out (make-bytevector 16 0)]
            [len-buf  (make-bytevector 4 0)])
        (bytevector-s32-native-set! len-buf 0 16)
        (c-getsockname sock addr-out len-buf)
        (let ([actual-port (bytevector-u16-ref addr-out 2 'big)])
          (values sock actual-port)))))

  ;; Wrap a socket FD as binary input/output port pair.
  ;; Uses non-blocking I/O with Chez-native sleep for GC safety.
  (define (fd->binary-ports fd)
    (let ([closed? #f])
      (let ([in (make-custom-binary-input-port "nrepl-in"
                  (lambda (bv start count)
                    (if closed? 0
                        (let ([buf (make-bytevector count)])
                          (let retry ()
                            (let ([n (c-read fd buf count)])
                              (cond
                                [(> n 0)
                                 (bytevector-copy! buf 0 bv start n)
                                 n]
                                [(and (< n 0)
                                      (let ([e (get-errno)])
                                        (or (= e EINTR) (= e EAGAIN))))
                                 (sleep *retry-delay*)
                                 (retry)]
                                [else 0]))))))
                  #f #f
                  (lambda ()
                    (unless closed?
                      (set! closed? #t)
                      (c-close fd))))]
            [out (make-custom-binary-output-port "nrepl-out"
                   (lambda (bv start count)
                     (if closed? 0
                         (let ([buf (make-bytevector count)])
                           (bytevector-copy! bv start buf 0 count)
                           (let lp ([written 0])
                             (if (= written count)
                                 count
                                 (let ([n (c-write fd
                                            (let ([tmp (make-bytevector (- count written))])
                                              (bytevector-copy! buf written tmp 0 (- count written))
                                              tmp)
                                            (- count written))])
                                   (cond
                                     [(> n 0) (lp (+ written n))]
                                     [(and (< n 0)
                                           (let ([e (get-errno)])
                                             (or (= e EINTR) (= e EAGAIN))))
                                      (sleep *retry-delay*)
                                      (lp written)]
                                     [else written])))))))
                   #f #f #f)])
        (values in out))))

  ;; ================================================================
  ;; Server State
  ;; ================================================================

  (define *server-socket*  #f)
  (define *server-port*    #f)
  (define *server-running* #f)
  (define *server-thread*  #f)

  (define (nrepl-server-port) *server-port*)
  (define (nrepl-running?) (and *server-running* #t))

  ;; ================================================================
  ;; Server Start/Stop
  ;; ================================================================

  (define nrepl-start!
    (case-lambda
      [() (nrepl-start! 0)]   ;; 0 = OS-assigned port
      [(port)
       (when *server-running*
         (error 'nrepl-start! "nREPL server already running"))
       (let-values ([(sock actual-port) (tcp-listen* port)])
         (set! *server-socket* sock)
         (set! *server-port* actual-port)
         (set! *server-running* #t)
         ;; Write .nrepl-port for editor auto-discovery
         (let ([port-file (string-append (current-directory) "/.nrepl-port")])
           (call-with-output-file port-file
             (lambda (p) (display actual-port p))
             'replace))
         (fprintf (current-output-port)
           "nREPL server started on port ~a on host 127.0.0.1 - nrepl://127.0.0.1:~a~n"
           actual-port actual-port)
         (flush-output-port (current-output-port))
         ;; Accept loop in background thread
         (set! *server-thread*
           (fork-thread
             (lambda ()
               (let accept-loop ()
                 (when *server-running*
                   (let ([addr (make-bytevector 16 0)]
                         [len  (make-bytevector 4 0)])
                     (bytevector-s32-native-set! len 0 16)
                     (let ([client-fd (c-accept sock addr len)])
                       (cond
                         [(> client-fd 0)
                          ;; New connection — handle in its own thread
                          (fork-thread
                            (lambda ()
                              (guard (exn [#t (void)])
                                (set-nonblocking! client-fd)
                                (let-values ([(in out) (fd->binary-ports client-fd)])
                                  (handle-client in out)
                                  (close-port in)))))
                          (accept-loop)]
                         [else
                          ;; No connection pending — GC-safe sleep, retry
                          (sleep *retry-delay*)
                          (accept-loop)]))))))))
         actual-port)]))  ;; close let-values, [(port) clause, case-lambda, define

  (define (nrepl-stop!)
    (when *server-running*
      (set! *server-running* #f)
      (when *server-socket*
        (guard (exn [#t (void)])
          (c-close *server-socket*))
        (set! *server-socket* #f))
      ;; Remove .nrepl-port file
      (let ([port-file (string-append (current-directory) "/.nrepl-port")])
        (when (file-exists? port-file)
          (delete-file port-file)))
      (set! *server-port* #f)
      (fprintf (current-output-port) "nREPL server stopped~n")
      (flush-output-port (current-output-port))))

) ;; end library
