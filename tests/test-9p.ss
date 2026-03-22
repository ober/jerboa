#!chezscheme
;;; Tests for (std net 9p) -- 9P2000 filesystem protocol

(import (chezscheme) (std net 9p))

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

;; Helper: encode then decode, return decoded message
(define (roundtrip msg)
  (p9-decode (p9-encode msg)))

;; Helper: compare qids
(define (qid=? a b)
  (and (= (p9-qid-type a) (p9-qid-type b))
       (= (p9-qid-version a) (p9-qid-version b))
       (= (p9-qid-path a) (p9-qid-path b))))

(printf "--- 9P2000 Protocol Tests ---~%~%")

;;; ========== Wire format basics ==========

(printf "~%== Wire format ==~%")

(test "encode-size-prefix"
  ;; Tversion with msize=8192, version="9P2000" should have correct size
  ;; size[4] + type[1] + tag[2] + msize[4] + strlen[2] + "9P2000"[6] = 19
  (let ([bv (p9-encode (make-p9-tversion 0 8192 "9P2000"))])
    (+ (bytevector-u8-ref bv 0)
       (bitwise-arithmetic-shift-left (bytevector-u8-ref bv 1) 8)
       (bitwise-arithmetic-shift-left (bytevector-u8-ref bv 2) 16)
       (bitwise-arithmetic-shift-left (bytevector-u8-ref bv 3) 24)))
  19)

(test "encode-type-byte"
  ;; Type byte is at offset 4
  (bytevector-u8-ref (p9-encode (make-p9-tversion 0 8192 "9P2000")) 4)
  100)  ;; Tversion = 100

(test "encode-tag-le"
  ;; Tag at offset 5-6, little-endian
  (let ([bv (p9-encode (make-p9-tversion #x0102 8192 "9P2000"))])
    (list (bytevector-u8-ref bv 5) (bytevector-u8-ref bv 6)))
  '(2 1))  ;; LE: low byte first

;;; ========== Tversion / Rversion ==========

(printf "~%== Version ==~%")

(test "tversion-roundtrip-type"
  (p9-message-type (roundtrip (make-p9-tversion 1 8192 "9P2000")))
  p9-type-tversion)

(test "tversion-roundtrip-tag"
  (p9-message-tag (roundtrip (make-p9-tversion 42 8192 "9P2000")))
  42)

(let ([msg (roundtrip (make-p9-tversion #xFFFF 8192 "9P2000"))])
  (test "tversion-msize"
    (p9-tversion-rec-msize msg)
    8192)
  (test "tversion-version-string"
    (p9-tversion-rec-version msg)
    "9P2000")
  (test "tversion-notag"
    (p9-message-tag msg)
    #xFFFF))

(let ([msg (roundtrip (make-p9-rversion 1 4096 "9P2000"))])
  (test "rversion-roundtrip"
    (and (= (p9-message-type msg) p9-type-rversion)
         (= (p9-rversion-rec-msize msg) 4096)
         (string=? (p9-rversion-rec-version msg) "9P2000"))
    #t))

;;; ========== Tauth / Rauth ==========

(printf "~%== Auth ==~%")

(let ([msg (roundtrip (make-p9-tauth 5 100 "glenda" ""))])
  (test "tauth-roundtrip-type" (p9-message-type msg) p9-type-tauth)
  (test "tauth-afid" (p9-tauth-rec-afid msg) 100)
  (test "tauth-uname" (p9-tauth-rec-uname msg) "glenda")
  (test "tauth-aname" (p9-tauth-rec-aname msg) ""))

(let* ([qid (make-p9-qid #x80 1 12345)]
       [msg (roundtrip (make-p9-rauth 5 qid))])
  (test "rauth-roundtrip-type" (p9-message-type msg) p9-type-rauth)
  (test "rauth-qid"
    (qid=? (p9-rauth-rec-aqid msg) qid)
    #t))

;;; ========== Tattach / Rattach ==========

(printf "~%== Attach ==~%")

(let ([msg (roundtrip (make-p9-tattach 1 0 #xFFFFFFFF "glenda" "/"))])
  (test "tattach-type" (p9-message-type msg) p9-type-tattach)
  (test "tattach-fid" (p9-tattach-rec-fid msg) 0)
  (test "tattach-afid" (p9-tattach-rec-afid msg) #xFFFFFFFF)
  (test "tattach-uname" (p9-tattach-rec-uname msg) "glenda")
  (test "tattach-aname" (p9-tattach-rec-aname msg) "/"))

(let* ([qid (make-p9-qid #x80 0 99)]
       [msg (roundtrip (make-p9-rattach 1 qid))])
  (test "rattach-type" (p9-message-type msg) p9-type-rattach)
  (test "rattach-qid"
    (qid=? (p9-rattach-rec-qid msg) qid)
    #t))

;;; ========== Rerror ==========

(printf "~%== Error ==~%")

(let ([msg (roundtrip (make-p9-rerror 3 "file not found"))])
  (test "rerror-type" (p9-message-type msg) p9-type-rerror)
  (test "rerror-ename" (p9-rerror-rec-ename msg) "file not found"))

;;; ========== Twalk / Rwalk ==========

(printf "~%== Walk ==~%")

(let ([msg (roundtrip (make-p9-twalk 7 0 1 '("usr" "glenda" "lib")))])
  (test "twalk-type" (p9-message-type msg) p9-type-twalk)
  (test "twalk-fid" (p9-twalk-rec-fid msg) 0)
  (test "twalk-newfid" (p9-twalk-rec-newfid msg) 1)
  (test "twalk-wnames" (p9-twalk-rec-wnames msg) '("usr" "glenda" "lib"))
  (test "twalk-wname-count" (length (p9-twalk-rec-wnames msg)) 3))

;; Walk with empty path (clone fid)
(let ([msg (roundtrip (make-p9-twalk 8 5 6 '()))])
  (test "twalk-empty" (p9-twalk-rec-wnames msg) '()))

;; Walk with single element
(let ([msg (roundtrip (make-p9-twalk 9 0 2 '("bin")))])
  (test "twalk-single" (p9-twalk-rec-wnames msg) '("bin")))

(let* ([q1 (make-p9-qid #x80 0 100)]
       [q2 (make-p9-qid #x80 0 200)]
       [q3 (make-p9-qid 0 0 300)]
       [msg (roundtrip (make-p9-rwalk 7 (list q1 q2 q3)))])
  (test "rwalk-type" (p9-message-type msg) p9-type-rwalk)
  (test "rwalk-qid-count" (length (p9-rwalk-rec-qids msg)) 3)
  (test "rwalk-qid-1"
    (qid=? (car (p9-rwalk-rec-qids msg)) q1) #t)
  (test "rwalk-qid-3"
    (qid=? (caddr (p9-rwalk-rec-qids msg)) q3) #t))

;; Empty Rwalk (no qids)
(let ([msg (roundtrip (make-p9-rwalk 10 '()))])
  (test "rwalk-empty" (p9-rwalk-rec-qids msg) '()))

;;; ========== Topen / Ropen ==========

(printf "~%== Open ==~%")

(let ([msg (roundtrip (make-p9-topen 11 5 0))])  ;; mode=0 = OREAD
  (test "topen-type" (p9-message-type msg) p9-type-topen)
  (test "topen-fid" (p9-topen-rec-fid msg) 5)
  (test "topen-mode" (p9-topen-rec-mode msg) 0))

(let* ([qid (make-p9-qid 0 3 555)]
       [msg (roundtrip (make-p9-ropen 11 qid 8168))])
  (test "ropen-type" (p9-message-type msg) p9-type-ropen)
  (test "ropen-qid" (qid=? (p9-ropen-rec-qid msg) qid) #t)
  (test "ropen-iounit" (p9-ropen-rec-iounit msg) 8168))

;;; ========== Tcreate / Rcreate ==========

(printf "~%== Create ==~%")

(let ([msg (roundtrip (make-p9-tcreate 12 5 "hello.txt" #o0644 1))])  ;; mode=1 = OWRITE
  (test "tcreate-type" (p9-message-type msg) p9-type-tcreate)
  (test "tcreate-fid" (p9-tcreate-rec-fid msg) 5)
  (test "tcreate-name" (p9-tcreate-rec-name msg) "hello.txt")
  (test "tcreate-perm" (p9-tcreate-rec-perm msg) #o0644)
  (test "tcreate-mode" (p9-tcreate-rec-mode msg) 1))

(let* ([qid (make-p9-qid 0 1 777)]
       [msg (roundtrip (make-p9-rcreate 12 qid 8168))])
  (test "rcreate-type" (p9-message-type msg) p9-type-rcreate)
  (test "rcreate-qid" (qid=? (p9-rcreate-rec-qid msg) qid) #t)
  (test "rcreate-iounit" (p9-rcreate-rec-iounit msg) 8168))

;;; ========== Tread / Rread ==========

(printf "~%== Read ==~%")

(let ([msg (roundtrip (make-p9-tread 13 5 0 4096))])
  (test "tread-type" (p9-message-type msg) p9-type-tread)
  (test "tread-fid" (p9-tread-rec-fid msg) 5)
  (test "tread-offset" (p9-tread-rec-offset msg) 0)
  (test "tread-count" (p9-tread-rec-count msg) 4096))

;; Read with large offset
(let ([msg (roundtrip (make-p9-tread 14 5 #x100000000 1024))])
  (test "tread-large-offset" (p9-tread-rec-offset msg) #x100000000))

;; Rread with data payload
(let* ([data (string->utf8 "Hello, Plan 9!")]
       [msg (roundtrip (make-p9-rread 13 data))])
  (test "rread-type" (p9-message-type msg) p9-type-rread)
  (test "rread-data"
    (utf8->string (p9-rread-rec-data msg))
    "Hello, Plan 9!"))

;; Rread with empty data
(let ([msg (roundtrip (make-p9-rread 15 (make-bytevector 0)))])
  (test "rread-empty" (bytevector-length (p9-rread-rec-data msg)) 0))

;; Rread with binary data
(let* ([data (u8-list->bytevector '(0 1 2 255 254 253 128))]
       [msg (roundtrip (make-p9-rread 16 data))])
  (test "rread-binary"
    (bytevector->u8-list (p9-rread-rec-data msg))
    '(0 1 2 255 254 253 128)))

;;; ========== Twrite / Rwrite ==========

(printf "~%== Write ==~%")

(let* ([data (string->utf8 "Hello from client")]
       [msg (roundtrip (make-p9-twrite 17 5 100 data))])
  (test "twrite-type" (p9-message-type msg) p9-type-twrite)
  (test "twrite-fid" (p9-twrite-rec-fid msg) 5)
  (test "twrite-offset" (p9-twrite-rec-offset msg) 100)
  (test "twrite-data"
    (utf8->string (p9-twrite-rec-data msg))
    "Hello from client"))

(let ([msg (roundtrip (make-p9-rwrite 17 512))])
  (test "rwrite-type" (p9-message-type msg) p9-type-rwrite)
  (test "rwrite-count" (p9-rwrite-rec-count msg) 512))

;;; ========== Tclunk / Rclunk ==========

(printf "~%== Clunk ==~%")

(let ([msg (roundtrip (make-p9-tclunk 18 5))])
  (test "tclunk-type" (p9-message-type msg) p9-type-tclunk)
  (test "tclunk-fid" (p9-tclunk-rec-fid msg) 5))

(let ([msg (roundtrip (make-p9-rclunk 18))])
  (test "rclunk-type" (p9-message-type msg) p9-type-rclunk)
  (test "rclunk-tag" (p9-message-tag msg) 18))

;;; ========== Tstat / Rstat ==========

(printf "~%== Stat ==~%")

(let ([msg (roundtrip (make-p9-tstat 19 5))])
  (test "tstat-type" (p9-message-type msg) p9-type-tstat)
  (test "tstat-fid" (p9-tstat-rec-fid msg) 5))

(let* ([qid (make-p9-qid 0 1 42)]
       [st (make-p9-stat 0 0 qid #o0644 1000000 1000001 4096
                         "hello.txt" "glenda" "glenda" "glenda")]
       [msg (roundtrip (make-p9-rstat 19 st))])
  (test "rstat-type" (p9-message-type msg) p9-type-rstat)
  (let ([s (p9-rstat-rec-stat msg)])
    (test "rstat-name" (p9-stat-name s) "hello.txt")
    (test "rstat-uid" (p9-stat-uid s) "glenda")
    (test "rstat-gid" (p9-stat-gid s) "glenda")
    (test "rstat-muid" (p9-stat-muid s) "glenda")
    (test "rstat-mode" (p9-stat-mode s) #o0644)
    (test "rstat-length" (p9-stat-length s) 4096)
    (test "rstat-atime" (p9-stat-atime s) 1000000)
    (test "rstat-mtime" (p9-stat-mtime s) 1000001)
    (test "rstat-qid" (qid=? (p9-stat-qid s) qid) #t)))

;;; ========== Version negotiation scenario ==========

(printf "~%== Version negotiation scenario ==~%")

;; Client sends Tversion, server responds with Rversion
(let* ([client-msg (make-p9-tversion #xFFFF 8192 "9P2000")]
       [wire (p9-encode client-msg)]
       [server-sees (p9-decode wire)])
  (test "negotiate-client-type" (p9-message-type server-sees) p9-type-tversion)
  (test "negotiate-client-msize" (p9-tversion-rec-msize server-sees) 8192)
  (test "negotiate-client-version" (p9-tversion-rec-version server-sees) "9P2000")
  ;; Server responds
  (let* ([server-msg (make-p9-rversion #xFFFF 4096 "9P2000")]
         [wire2 (p9-encode server-msg)]
         [client-sees (p9-decode wire2)])
    (test "negotiate-server-type" (p9-message-type client-sees) p9-type-rversion)
    (test "negotiate-server-msize" (p9-rversion-rec-msize client-sees) 4096)
    (test "negotiate-server-version" (p9-rversion-rec-version client-sees) "9P2000")))

;;; ========== Multi-element walk scenario ==========

(printf "~%== Walk scenario ==~%")

;; Walk /usr/glenda/lib/profile
(let* ([walk-msg (make-p9-twalk 1 0 1 '("usr" "glenda" "lib" "profile"))]
       [wire (p9-encode walk-msg)]
       [decoded (p9-decode wire)])
  (test "walk-scenario-count" (length (p9-twalk-rec-wnames decoded)) 4)
  (test "walk-scenario-first" (car (p9-twalk-rec-wnames decoded)) "usr")
  (test "walk-scenario-last" (list-ref (p9-twalk-rec-wnames decoded) 3) "profile"))

;;; ========== UTF-8 string handling ==========

(printf "~%== UTF-8 ==~%")

;; Error message with non-ASCII characters
(let ([msg (roundtrip (make-p9-rerror 20 "permission denied: \x3BB;"))])
  (test "utf8-error" (p9-rerror-rec-ename msg) "permission denied: \x3BB;"))

;;; ========== Summary ==========

(printf "~%--- Results: ~a passed, ~a failed ---~%" pass fail)
(when (> fail 0) (exit 1))
