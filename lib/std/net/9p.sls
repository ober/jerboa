#!chezscheme
;;; (std net 9p) -- 9P2000 filesystem protocol (Plan 9)
;;;
;;; Pure encoding/decoding of 9P2000 wire-format messages.
;;; No network I/O -- works entirely with bytevectors.
;;;
;;; Wire format: [4-byte LE size][1-byte type][2-byte LE tag][fields...]
;;; Strings: [2-byte LE length][UTF-8 bytes]

(library (std net 9p)
  (export
    ;; Message type constants
    p9-type-tversion p9-type-rversion
    p9-type-tauth   p9-type-rauth
    p9-type-tattach  p9-type-rattach
    p9-type-rerror
    p9-type-twalk    p9-type-rwalk
    p9-type-topen    p9-type-ropen
    p9-type-tcreate  p9-type-rcreate
    p9-type-tread    p9-type-rread
    p9-type-twrite   p9-type-rwrite
    p9-type-tclunk   p9-type-rclunk
    p9-type-tstat    p9-type-rstat
    ;; Qid accessors
    make-p9-qid p9-qid? p9-qid-type p9-qid-version p9-qid-path
    ;; Message constructors
    make-p9-tversion make-p9-rversion
    make-p9-tauth   make-p9-rauth
    make-p9-tattach  make-p9-rattach
    make-p9-rerror
    make-p9-twalk    make-p9-rwalk
    make-p9-topen    make-p9-ropen
    make-p9-tcreate  make-p9-rcreate
    make-p9-tread    make-p9-rread
    make-p9-twrite   make-p9-rwrite
    make-p9-tclunk   make-p9-rclunk
    make-p9-tstat    make-p9-rstat
    ;; Stat record
    make-p9-stat p9-stat? p9-stat-type p9-stat-dev p9-stat-qid
    p9-stat-mode p9-stat-atime p9-stat-mtime p9-stat-length
    p9-stat-name p9-stat-uid p9-stat-gid p9-stat-muid
    ;; Message record accessors (for inspecting decoded messages)
    p9-tversion-rec-msize p9-tversion-rec-version
    p9-rversion-rec-msize p9-rversion-rec-version
    p9-tauth-rec-afid p9-tauth-rec-uname p9-tauth-rec-aname
    p9-rauth-rec-aqid
    p9-tattach-rec-fid p9-tattach-rec-afid
    p9-tattach-rec-uname p9-tattach-rec-aname
    p9-rattach-rec-qid
    p9-rerror-rec-ename
    p9-twalk-rec-fid p9-twalk-rec-newfid p9-twalk-rec-wnames
    p9-rwalk-rec-qids
    p9-topen-rec-fid p9-topen-rec-mode
    p9-ropen-rec-qid p9-ropen-rec-iounit
    p9-tcreate-rec-fid p9-tcreate-rec-name
    p9-tcreate-rec-perm p9-tcreate-rec-mode
    p9-rcreate-rec-qid p9-rcreate-rec-iounit
    p9-tread-rec-fid p9-tread-rec-offset p9-tread-rec-count
    p9-rread-rec-data
    p9-twrite-rec-fid p9-twrite-rec-offset p9-twrite-rec-data
    p9-rwrite-rec-count
    p9-tclunk-rec-fid
    p9-tstat-rec-fid
    p9-rstat-rec-stat
    ;; Encode / decode
    p9-encode p9-decode
    ;; Message accessors
    p9-message-type p9-message-tag)

  (import (chezscheme))

  ;;; ========== Message type constants (9P2000) ==========
  (define p9-type-tversion 100)
  (define p9-type-rversion 101)
  (define p9-type-tauth    102)
  (define p9-type-rauth    103)
  (define p9-type-tattach  104)
  (define p9-type-rattach  105)
  ;; 106 = Terror (never sent)
  (define p9-type-rerror   107)
  (define p9-type-twalk    110)
  (define p9-type-rwalk    111)
  (define p9-type-topen    112)
  (define p9-type-ropen    113)
  (define p9-type-tcreate  114)
  (define p9-type-rcreate  115)
  (define p9-type-tread    116)
  (define p9-type-rread    117)
  (define p9-type-twrite   118)
  (define p9-type-rwrite   119)
  (define p9-type-tclunk   120)
  (define p9-type-rclunk   121)
  (define p9-type-tstat    124)
  (define p9-type-rstat    125)

  ;;; ========== Qid record ==========
  ;; A qid is a 13-byte server-unique file identifier:
  ;;   [1-byte type][4-byte LE version][8-byte LE path]
  (define-record-type p9-qid-rec
    (fields type version path))

  (define (make-p9-qid type version path)
    (make-p9-qid-rec type version path))
  (define (p9-qid? x) (p9-qid-rec? x))
  (define (p9-qid-type q) (p9-qid-rec-type q))
  (define (p9-qid-version q) (p9-qid-rec-version q))
  (define (p9-qid-path q) (p9-qid-rec-path q))

  ;;; ========== Stat record ==========
  (define-record-type p9-stat-rec
    (fields type dev qid mode atime mtime length name uid gid muid))

  (define (make-p9-stat type dev qid mode atime mtime length name uid gid muid)
    (make-p9-stat-rec type dev qid mode atime mtime length name uid gid muid))
  (define (p9-stat? x) (p9-stat-rec? x))
  (define (p9-stat-type s) (p9-stat-rec-type s))
  (define (p9-stat-dev s) (p9-stat-rec-dev s))
  (define (p9-stat-qid s) (p9-stat-rec-qid s))
  (define (p9-stat-mode s) (p9-stat-rec-mode s))
  (define (p9-stat-atime s) (p9-stat-rec-atime s))
  (define (p9-stat-mtime s) (p9-stat-rec-mtime s))
  (define (p9-stat-length s) (p9-stat-rec-length s))
  (define (p9-stat-name s) (p9-stat-rec-name s))
  (define (p9-stat-uid s) (p9-stat-rec-uid s))
  (define (p9-stat-gid s) (p9-stat-rec-gid s))
  (define (p9-stat-muid s) (p9-stat-rec-muid s))

  ;;; ========== Message records ==========

  ;; Each message type is a distinct record.  They all carry a tag.

  (define-record-type p9-tversion-rec (fields tag msize version))
  (define-record-type p9-rversion-rec (fields tag msize version))
  (define-record-type p9-tauth-rec    (fields tag afid uname aname))
  (define-record-type p9-rauth-rec    (fields tag aqid))
  (define-record-type p9-tattach-rec  (fields tag fid afid uname aname))
  (define-record-type p9-rattach-rec  (fields tag qid))
  (define-record-type p9-rerror-rec   (fields tag ename))
  (define-record-type p9-twalk-rec    (fields tag fid newfid wnames))
  (define-record-type p9-rwalk-rec    (fields tag qids))
  (define-record-type p9-topen-rec    (fields tag fid mode))
  (define-record-type p9-ropen-rec    (fields tag qid iounit))
  (define-record-type p9-tcreate-rec  (fields tag fid name perm mode))
  (define-record-type p9-rcreate-rec  (fields tag qid iounit))
  (define-record-type p9-tread-rec    (fields tag fid offset count))
  (define-record-type p9-rread-rec    (fields tag data))
  (define-record-type p9-twrite-rec   (fields tag fid offset data))
  (define-record-type p9-rwrite-rec   (fields tag count))
  (define-record-type p9-tclunk-rec   (fields tag fid))
  (define-record-type p9-rclunk-rec   (fields tag))
  (define-record-type p9-tstat-rec    (fields tag fid))
  (define-record-type p9-rstat-rec    (fields tag stat))

  ;; Public constructors
  (define (make-p9-tversion tag msize version)
    (make-p9-tversion-rec tag msize version))
  (define (make-p9-rversion tag msize version)
    (make-p9-rversion-rec tag msize version))
  (define (make-p9-tauth tag afid uname aname)
    (make-p9-tauth-rec tag afid uname aname))
  (define (make-p9-rauth tag aqid)
    (make-p9-rauth-rec tag aqid))
  (define (make-p9-tattach tag fid afid uname aname)
    (make-p9-tattach-rec tag fid afid uname aname))
  (define (make-p9-rattach tag qid)
    (make-p9-rattach-rec tag qid))
  (define (make-p9-rerror tag ename)
    (make-p9-rerror-rec tag ename))
  (define (make-p9-twalk tag fid newfid wnames)
    (make-p9-twalk-rec tag fid newfid wnames))
  (define (make-p9-rwalk tag qids)
    (make-p9-rwalk-rec tag qids))
  (define (make-p9-topen tag fid mode)
    (make-p9-topen-rec tag fid mode))
  (define (make-p9-ropen tag qid iounit)
    (make-p9-ropen-rec tag qid iounit))
  (define (make-p9-tcreate tag fid name perm mode)
    (make-p9-tcreate-rec tag fid name perm mode))
  (define (make-p9-rcreate tag qid iounit)
    (make-p9-rcreate-rec tag qid iounit))
  (define (make-p9-tread tag fid offset count)
    (make-p9-tread-rec tag fid offset count))
  (define (make-p9-rread tag data)
    (make-p9-rread-rec tag data))
  (define (make-p9-twrite tag fid offset data)
    (make-p9-twrite-rec tag fid offset data))
  (define (make-p9-rwrite tag count)
    (make-p9-rwrite-rec tag count))
  (define (make-p9-tclunk tag fid)
    (make-p9-tclunk-rec tag fid))
  (define (make-p9-rclunk tag)
    (make-p9-rclunk-rec tag))
  (define (make-p9-tstat tag fid)
    (make-p9-tstat-rec tag fid))
  (define (make-p9-rstat tag stat)
    (make-p9-rstat-rec tag stat))

  ;;; ========== Message type dispatch ==========

  (define (p9-message-type msg)
    (cond
      [(p9-tversion-rec? msg) p9-type-tversion]
      [(p9-rversion-rec? msg) p9-type-rversion]
      [(p9-tauth-rec? msg)    p9-type-tauth]
      [(p9-rauth-rec? msg)    p9-type-rauth]
      [(p9-tattach-rec? msg)  p9-type-tattach]
      [(p9-rattach-rec? msg)  p9-type-rattach]
      [(p9-rerror-rec? msg)   p9-type-rerror]
      [(p9-twalk-rec? msg)    p9-type-twalk]
      [(p9-rwalk-rec? msg)    p9-type-rwalk]
      [(p9-topen-rec? msg)    p9-type-topen]
      [(p9-ropen-rec? msg)    p9-type-ropen]
      [(p9-tcreate-rec? msg)  p9-type-tcreate]
      [(p9-rcreate-rec? msg)  p9-type-rcreate]
      [(p9-tread-rec? msg)    p9-type-tread]
      [(p9-rread-rec? msg)    p9-type-rread]
      [(p9-twrite-rec? msg)   p9-type-twrite]
      [(p9-rwrite-rec? msg)   p9-type-rwrite]
      [(p9-tclunk-rec? msg)   p9-type-tclunk]
      [(p9-rclunk-rec? msg)   p9-type-rclunk]
      [(p9-tstat-rec? msg)    p9-type-tstat]
      [(p9-rstat-rec? msg)    p9-type-rstat]
      [else (error 'p9-message-type "unknown message type" msg)]))

  (define (p9-message-tag msg)
    (cond
      [(p9-tversion-rec? msg) (p9-tversion-rec-tag msg)]
      [(p9-rversion-rec? msg) (p9-rversion-rec-tag msg)]
      [(p9-tauth-rec? msg)    (p9-tauth-rec-tag msg)]
      [(p9-rauth-rec? msg)    (p9-rauth-rec-tag msg)]
      [(p9-tattach-rec? msg)  (p9-tattach-rec-tag msg)]
      [(p9-rattach-rec? msg)  (p9-rattach-rec-tag msg)]
      [(p9-rerror-rec? msg)   (p9-rerror-rec-tag msg)]
      [(p9-twalk-rec? msg)    (p9-twalk-rec-tag msg)]
      [(p9-rwalk-rec? msg)    (p9-rwalk-rec-tag msg)]
      [(p9-topen-rec? msg)    (p9-topen-rec-tag msg)]
      [(p9-ropen-rec? msg)    (p9-ropen-rec-tag msg)]
      [(p9-tcreate-rec? msg)  (p9-tcreate-rec-tag msg)]
      [(p9-rcreate-rec? msg)  (p9-rcreate-rec-tag msg)]
      [(p9-tread-rec? msg)    (p9-tread-rec-tag msg)]
      [(p9-rread-rec? msg)    (p9-rread-rec-tag msg)]
      [(p9-twrite-rec? msg)   (p9-twrite-rec-tag msg)]
      [(p9-rwrite-rec? msg)   (p9-rwrite-rec-tag msg)]
      [(p9-tclunk-rec? msg)   (p9-tclunk-rec-tag msg)]
      [(p9-rclunk-rec? msg)   (p9-rclunk-rec-tag msg)]
      [(p9-tstat-rec? msg)    (p9-tstat-rec-tag msg)]
      [(p9-rstat-rec? msg)    (p9-rstat-rec-tag msg)]
      [else (error 'p9-message-tag "unknown message type" msg)]))

  ;;; ========== Low-level encoding helpers ==========

  ;; Build a bytevector by appending chunks
  (define (bv-append . bvs)
    (let* ([total (apply + (map bytevector-length bvs))]
           [out (make-bytevector total)])
      (let loop ([bvs bvs] [pos 0])
        (if (null? bvs)
          out
          (let ([bv (car bvs)])
            (bytevector-copy! bv 0 out pos (bytevector-length bv))
            (loop (cdr bvs) (+ pos (bytevector-length bv))))))))

  (define (encode-u8 v)
    (let ([bv (make-bytevector 1)])
      (bytevector-u8-set! bv 0 (bitwise-and v #xFF))
      bv))

  (define (encode-u16 v)
    (let ([bv (make-bytevector 2)])
      (bytevector-u8-set! bv 0 (bitwise-and v #xFF))
      (bytevector-u8-set! bv 1 (bitwise-and (bitwise-arithmetic-shift-right v 8) #xFF))
      bv))

  (define (encode-u32 v)
    (let ([bv (make-bytevector 4)])
      (bytevector-u8-set! bv 0 (bitwise-and v #xFF))
      (bytevector-u8-set! bv 1 (bitwise-and (bitwise-arithmetic-shift-right v 8) #xFF))
      (bytevector-u8-set! bv 2 (bitwise-and (bitwise-arithmetic-shift-right v 16) #xFF))
      (bytevector-u8-set! bv 3 (bitwise-and (bitwise-arithmetic-shift-right v 24) #xFF))
      bv))

  (define (encode-u64 v)
    (let ([bv (make-bytevector 8)])
      (bytevector-u8-set! bv 0 (bitwise-and v #xFF))
      (bytevector-u8-set! bv 1 (bitwise-and (bitwise-arithmetic-shift-right v 8) #xFF))
      (bytevector-u8-set! bv 2 (bitwise-and (bitwise-arithmetic-shift-right v 16) #xFF))
      (bytevector-u8-set! bv 3 (bitwise-and (bitwise-arithmetic-shift-right v 24) #xFF))
      (bytevector-u8-set! bv 4 (bitwise-and (bitwise-arithmetic-shift-right v 32) #xFF))
      (bytevector-u8-set! bv 5 (bitwise-and (bitwise-arithmetic-shift-right v 40) #xFF))
      (bytevector-u8-set! bv 6 (bitwise-and (bitwise-arithmetic-shift-right v 48) #xFF))
      (bytevector-u8-set! bv 7 (bitwise-and (bitwise-arithmetic-shift-right v 56) #xFF))
      bv))

  ;; 9P string: [2-byte LE length][UTF-8 bytes]
  (define (encode-string s)
    (let ([utf (string->utf8 s)])
      (bv-append (encode-u16 (bytevector-length utf)) utf)))

  ;; Qid: [1-byte type][4-byte LE version][8-byte LE path]
  (define (encode-qid q)
    (bv-append (encode-u8 (p9-qid-type q))
               (encode-u32 (p9-qid-version q))
               (encode-u64 (p9-qid-path q))))

  ;; Data field: [4-byte LE count][bytes...]
  (define (encode-data bv)
    (bv-append (encode-u32 (bytevector-length bv)) bv))

  ;; Stat: encoded as [2-byte LE size][stat-body]
  ;; stat-body: type[2] dev[4] qid[13] mode[4] atime[4] mtime[4] length[8]
  ;;            name[s] uid[s] gid[s] muid[s]
  (define (encode-stat st)
    (let* ([body (bv-append
                   (encode-u16 (p9-stat-type st))
                   (encode-u32 (p9-stat-dev st))
                   (encode-qid (p9-stat-qid st))
                   (encode-u32 (p9-stat-mode st))
                   (encode-u32 (p9-stat-atime st))
                   (encode-u32 (p9-stat-mtime st))
                   (encode-u64 (p9-stat-length st))
                   (encode-string (p9-stat-name st))
                   (encode-string (p9-stat-uid st))
                   (encode-string (p9-stat-gid st))
                   (encode-string (p9-stat-muid st)))]
           [sz (bytevector-length body)])
      (bv-append (encode-u16 sz) body)))

  ;;; ========== Encoding ==========

  ;; Encode message fields (without size/type/tag header)
  (define (encode-body msg)
    (cond
      [(p9-tversion-rec? msg)
       (bv-append (encode-u32 (p9-tversion-rec-msize msg))
                  (encode-string (p9-tversion-rec-version msg)))]
      [(p9-rversion-rec? msg)
       (bv-append (encode-u32 (p9-rversion-rec-msize msg))
                  (encode-string (p9-rversion-rec-version msg)))]
      [(p9-tauth-rec? msg)
       (bv-append (encode-u32 (p9-tauth-rec-afid msg))
                  (encode-string (p9-tauth-rec-uname msg))
                  (encode-string (p9-tauth-rec-aname msg)))]
      [(p9-rauth-rec? msg)
       (encode-qid (p9-rauth-rec-aqid msg))]
      [(p9-tattach-rec? msg)
       (bv-append (encode-u32 (p9-tattach-rec-fid msg))
                  (encode-u32 (p9-tattach-rec-afid msg))
                  (encode-string (p9-tattach-rec-uname msg))
                  (encode-string (p9-tattach-rec-aname msg)))]
      [(p9-rattach-rec? msg)
       (encode-qid (p9-rattach-rec-qid msg))]
      [(p9-rerror-rec? msg)
       (encode-string (p9-rerror-rec-ename msg))]
      [(p9-twalk-rec? msg)
       (let ([wnames (p9-twalk-rec-wnames msg)])
         (apply bv-append
                (encode-u32 (p9-twalk-rec-fid msg))
                (encode-u32 (p9-twalk-rec-newfid msg))
                (encode-u16 (length wnames))
                (map encode-string wnames)))]
      [(p9-rwalk-rec? msg)
       (let ([qids (p9-rwalk-rec-qids msg)])
         (apply bv-append
                (encode-u16 (length qids))
                (map encode-qid qids)))]
      [(p9-topen-rec? msg)
       (bv-append (encode-u32 (p9-topen-rec-fid msg))
                  (encode-u8 (p9-topen-rec-mode msg)))]
      [(p9-ropen-rec? msg)
       (bv-append (encode-qid (p9-ropen-rec-qid msg))
                  (encode-u32 (p9-ropen-rec-iounit msg)))]
      [(p9-tcreate-rec? msg)
       (bv-append (encode-u32 (p9-tcreate-rec-fid msg))
                  (encode-string (p9-tcreate-rec-name msg))
                  (encode-u32 (p9-tcreate-rec-perm msg))
                  (encode-u8 (p9-tcreate-rec-mode msg)))]
      [(p9-rcreate-rec? msg)
       (bv-append (encode-qid (p9-rcreate-rec-qid msg))
                  (encode-u32 (p9-rcreate-rec-iounit msg)))]
      [(p9-tread-rec? msg)
       (bv-append (encode-u32 (p9-tread-rec-fid msg))
                  (encode-u64 (p9-tread-rec-offset msg))
                  (encode-u32 (p9-tread-rec-count msg)))]
      [(p9-rread-rec? msg)
       (encode-data (p9-rread-rec-data msg))]
      [(p9-twrite-rec? msg)
       (bv-append (encode-u32 (p9-twrite-rec-fid msg))
                  (encode-u64 (p9-twrite-rec-offset msg))
                  (encode-data (p9-twrite-rec-data msg)))]
      [(p9-rwrite-rec? msg)
       (encode-u32 (p9-rwrite-rec-count msg))]
      [(p9-tclunk-rec? msg)
       (encode-u32 (p9-tclunk-rec-fid msg))]
      [(p9-rclunk-rec? msg)
       (make-bytevector 0)]
      [(p9-tstat-rec? msg)
       (encode-u32 (p9-tstat-rec-fid msg))]
      [(p9-rstat-rec? msg)
       ;; Rstat wraps the stat in an outer 2-byte length prefix
       (let ([inner (encode-stat (p9-rstat-rec-stat msg))])
         (bv-append (encode-u16 (bytevector-length inner)) inner))]
      [else (error 'p9-encode "unknown message type" msg)]))

  (define (p9-encode msg)
    (let* ([type-byte (p9-message-type msg)]
           [tag (p9-message-tag msg)]
           [body (encode-body msg)]
           ;; total size = 4 (size) + 1 (type) + 2 (tag) + body
           [total (+ 4 1 2 (bytevector-length body))])
      (bv-append (encode-u32 total)
                 (encode-u8 type-byte)
                 (encode-u16 tag)
                 body)))

  ;;; ========== Low-level decoding helpers ==========

  ;; Extract a sub-range — Chez core bytevector-slice (Phase 67).
  (define (subbytevector bv start end)
    (bytevector-slice bv start end))

  (define (decode-u8 bv pos)
    (values (bytevector-u8-ref bv pos) (+ pos 1)))

  (define (decode-u16 bv pos)
    (values (+ (bytevector-u8-ref bv pos)
               (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ pos 1)) 8))
            (+ pos 2)))

  (define (decode-u32 bv pos)
    (values (+ (bytevector-u8-ref bv pos)
               (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ pos 1)) 8)
               (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ pos 2)) 16)
               (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ pos 3)) 24))
            (+ pos 4)))

  (define (decode-u64 bv pos)
    (values (+ (bytevector-u8-ref bv pos)
               (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ pos 1)) 8)
               (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ pos 2)) 16)
               (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ pos 3)) 24)
               (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ pos 4)) 32)
               (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ pos 5)) 40)
               (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ pos 6)) 48)
               (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ pos 7)) 56))
            (+ pos 8)))

  (define (decode-string bv pos)
    (let-values ([(len pos2) (decode-u16 bv pos)])
      (let ([str (utf8->string (subbytevector bv pos2 (+ pos2 len)))])
        (values str (+ pos2 len)))))

  (define (decode-qid bv pos)
    (let-values ([(qtype pos1) (decode-u8 bv pos)]
                 [(qver  pos2) (decode-u32 bv (+ pos 1))]
                 [(qpath pos3) (decode-u64 bv (+ pos 5))])
      (values (make-p9-qid qtype qver qpath) (+ pos 13))))

  (define (decode-data bv pos)
    (let-values ([(count pos2) (decode-u32 bv pos)])
      (values (subbytevector bv pos2 (+ pos2 count)) (+ pos2 count))))

  (define (decode-stat bv pos)
    ;; [2-byte size][stat-body]
    (let-values ([(sz pos1) (decode-u16 bv pos)])
      (let-values ([(stype pos2) (decode-u16 bv pos1)]
                   [(sdev  pos3) (decode-u32 bv (+ pos1 2))]
                   [(sqid  pos4) (decode-qid bv (+ pos1 6))])
        (let-values ([(smode  pos5) (decode-u32 bv (+ pos1 19))]
                     [(satime pos6) (decode-u32 bv (+ pos1 23))]
                     [(smtime pos7) (decode-u32 bv (+ pos1 27))]
                     [(slen   pos8) (decode-u64 bv (+ pos1 31))])
          (let-values ([(sname pos9) (decode-string bv (+ pos1 39))])
            (let-values ([(suid pos10) (decode-string bv pos9)])
              (let-values ([(sgid pos11) (decode-string bv pos10)])
                (let-values ([(smuid pos12) (decode-string bv pos11)])
                  (values (make-p9-stat stype sdev sqid smode satime smtime slen
                                        sname suid sgid smuid)
                          (+ pos1 sz))))))))))

  ;;; ========== Decoding ==========

  (define (p9-decode bv)
    (unless (>= (bytevector-length bv) 7)
      (error 'p9-decode "message too short" (bytevector-length bv)))
    (let-values ([(size pos0) (decode-u32 bv 0)]
                 [(type pos1) (decode-u8 bv 4)]
                 [(tag  pos2) (decode-u16 bv 5)])
      (let ([pos 7])  ;; start of body
        (cond
          [(= type p9-type-tversion)
           (let-values ([(msize pos2) (decode-u32 bv pos)])
             (let-values ([(ver pos3) (decode-string bv pos2)])
               (make-p9-tversion tag msize ver)))]

          [(= type p9-type-rversion)
           (let-values ([(msize pos2) (decode-u32 bv pos)])
             (let-values ([(ver pos3) (decode-string bv pos2)])
               (make-p9-rversion tag msize ver)))]

          [(= type p9-type-tauth)
           (let-values ([(afid pos2) (decode-u32 bv pos)])
             (let-values ([(uname pos3) (decode-string bv pos2)])
               (let-values ([(aname pos4) (decode-string bv pos3)])
                 (make-p9-tauth tag afid uname aname))))]

          [(= type p9-type-rauth)
           (let-values ([(aqid pos2) (decode-qid bv pos)])
             (make-p9-rauth tag aqid))]

          [(= type p9-type-tattach)
           (let-values ([(fid  pos2) (decode-u32 bv pos)])
             (let-values ([(afid pos3) (decode-u32 bv pos2)])
               (let-values ([(uname pos4) (decode-string bv pos3)])
                 (let-values ([(aname pos5) (decode-string bv pos4)])
                   (make-p9-tattach tag fid afid uname aname)))))]

          [(= type p9-type-rattach)
           (let-values ([(qid pos2) (decode-qid bv pos)])
             (make-p9-rattach tag qid))]

          [(= type p9-type-rerror)
           (let-values ([(ename pos2) (decode-string bv pos)])
             (make-p9-rerror tag ename))]

          [(= type p9-type-twalk)
           (let-values ([(fid    pos2) (decode-u32 bv pos)])
             (let-values ([(newfid pos3) (decode-u32 bv pos2)])
               (let-values ([(nwname pos4) (decode-u16 bv pos3)])
                 (let loop ([i 0] [p pos4] [acc '()])
                   (if (= i nwname)
                     (make-p9-twalk tag fid newfid (reverse acc))
                     (let-values ([(name np) (decode-string bv p)])
                       (loop (+ i 1) np (cons name acc))))))))]

          [(= type p9-type-rwalk)
           (let-values ([(nwqid pos2) (decode-u16 bv pos)])
             (let loop ([i 0] [p pos2] [acc '()])
               (if (= i nwqid)
                 (make-p9-rwalk tag (reverse acc))
                 (let-values ([(qid np) (decode-qid bv p)])
                   (loop (+ i 1) np (cons qid acc))))))]

          [(= type p9-type-topen)
           (let-values ([(fid  pos2) (decode-u32 bv pos)])
             (let-values ([(mode pos3) (decode-u8 bv pos2)])
               (make-p9-topen tag fid mode)))]

          [(= type p9-type-ropen)
           (let-values ([(qid    pos2) (decode-qid bv pos)])
             (let-values ([(iounit pos3) (decode-u32 bv pos2)])
               (make-p9-ropen tag qid iounit)))]

          [(= type p9-type-tcreate)
           (let-values ([(fid  pos2) (decode-u32 bv pos)])
             (let-values ([(name pos3) (decode-string bv pos2)])
               (let-values ([(perm pos4) (decode-u32 bv pos3)])
                 (let-values ([(mode pos5) (decode-u8 bv pos4)])
                   (make-p9-tcreate tag fid name perm mode)))))]

          [(= type p9-type-rcreate)
           (let-values ([(qid    pos2) (decode-qid bv pos)])
             (let-values ([(iounit pos3) (decode-u32 bv pos2)])
               (make-p9-rcreate tag qid iounit)))]

          [(= type p9-type-tread)
           (let-values ([(fid    pos2) (decode-u32 bv pos)])
             (let-values ([(offset pos3) (decode-u64 bv pos2)])
               (let-values ([(count  pos4) (decode-u32 bv pos3)])
                 (make-p9-tread tag fid offset count))))]

          [(= type p9-type-rread)
           (let-values ([(data pos2) (decode-data bv pos)])
             (make-p9-rread tag data))]

          [(= type p9-type-twrite)
           (let-values ([(fid    pos2) (decode-u32 bv pos)])
             (let-values ([(offset pos3) (decode-u64 bv pos2)])
               (let-values ([(data   pos4) (decode-data bv pos3)])
                 (make-p9-twrite tag fid offset data))))]

          [(= type p9-type-rwrite)
           (let-values ([(count pos2) (decode-u32 bv pos)])
             (make-p9-rwrite tag count))]

          [(= type p9-type-tclunk)
           (let-values ([(fid pos2) (decode-u32 bv pos)])
             (make-p9-tclunk tag fid))]

          [(= type p9-type-rclunk)
           (make-p9-rclunk tag)]

          [(= type p9-type-tstat)
           (let-values ([(fid pos2) (decode-u32 bv pos)])
             (make-p9-tstat tag fid))]

          [(= type p9-type-rstat)
           ;; Rstat has an outer 2-byte length prefix around the stat
           (let-values ([(outer-len pos2) (decode-u16 bv pos)])
             (let-values ([(st pos3) (decode-stat bv pos2)])
               (make-p9-rstat tag st)))]

          [else (error 'p9-decode "unknown message type" type)]))))

) ;; end library
