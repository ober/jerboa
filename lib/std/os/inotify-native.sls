#!chezscheme
;;; (std os inotify-native) — Linux inotify via Rust/libc
;;;
;;; Replaces chez-inotify dependency with Rust native implementation.

(library (std os inotify-native)
  (export
    inotify-init inotify-close
    inotify-add-watch inotify-rm-watch
    inotify-read-events
    make-inotify-event inotify-event?
    inotify-event-wd inotify-event-mask inotify-event-name
    IN_ACCESS IN_ATTRIB IN_CLOSE_WRITE IN_CLOSE_NOWRITE
    IN_CREATE IN_DELETE IN_DELETE_SELF IN_MODIFY
    IN_MOVE_SELF IN_MOVED_FROM IN_MOVED_TO IN_OPEN
    IN_ALL_EVENTS IN_MOVE IN_CLOSE
    IN_DONT_FOLLOW IN_EXCL_UNLINK IN_MASK_ADD IN_ONESHOT IN_ONLYDIR
    IN_IGNORED IN_ISDIR IN_Q_OVERFLOW IN_UNMOUNT)

  (import (chezscheme))

  (define _native-loaded
    (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "./lib/libjerboa_native.so") #t)
        (error 'std/os/inotify-native "libjerboa_native.so not found")))

  ;; Constants
  (define IN_ACCESS        #x00000001)
  (define IN_MODIFY        #x00000002)
  (define IN_ATTRIB        #x00000004)
  (define IN_CLOSE_WRITE   #x00000008)
  (define IN_CLOSE_NOWRITE #x00000010)
  (define IN_OPEN          #x00000020)
  (define IN_MOVED_FROM    #x00000040)
  (define IN_MOVED_TO      #x00000080)
  (define IN_CREATE        #x00000100)
  (define IN_DELETE        #x00000200)
  (define IN_DELETE_SELF   #x00000400)
  (define IN_MOVE_SELF     #x00000800)

  (define IN_CLOSE     (bitwise-ior IN_CLOSE_WRITE IN_CLOSE_NOWRITE))
  (define IN_MOVE      (bitwise-ior IN_MOVED_FROM IN_MOVED_TO))
  (define IN_ALL_EVENTS
    (bitwise-ior IN_ACCESS IN_MODIFY IN_ATTRIB IN_CLOSE_WRITE
      IN_CLOSE_NOWRITE IN_OPEN IN_MOVED_FROM IN_MOVED_TO
      IN_CREATE IN_DELETE IN_DELETE_SELF IN_MOVE_SELF))

  (define IN_UNMOUNT       #x00002000)
  (define IN_Q_OVERFLOW    #x00004000)
  (define IN_IGNORED       #x00008000)
  (define IN_ONLYDIR       #x01000000)
  (define IN_DONT_FOLLOW   #x02000000)
  (define IN_EXCL_UNLINK   #x04000000)
  (define IN_MASK_ADD      #x20000000)
  (define IN_ISDIR         #x40000000)
  (define IN_ONESHOT       #x80000000)

  ;; Event record
  (define-record-type inotify-event
    (fields wd mask name)
    (nongenerative inotify-event-type))

  ;; FFI
  (define c-inotify-init
    (foreign-procedure "jerboa_inotify_init" () int))
  (define c-inotify-add-watch
    (foreign-procedure "jerboa_inotify_add_watch" (int u8* size_t unsigned-32) int))
  (define c-inotify-rm-watch
    (foreign-procedure "jerboa_inotify_rm_watch" (int int) int))
  (define c-inotify-read
    (foreign-procedure "jerboa_inotify_read" (int u8* size_t u8*) int))
  (define c-inotify-close
    (foreign-procedure "jerboa_inotify_close" (int) int))

  ;; --- Public API ---

  (define (inotify-init)
    (let ([fd (c-inotify-init)])
      (when (< fd 0) (error 'inotify-init "inotify_init1 failed"))
      fd))

  (define (inotify-close fd)
    (c-inotify-close fd)
    (void))

  (define (inotify-add-watch fd path mask)
    (let ([bv (string->utf8 path)])
      (let ([wd (c-inotify-add-watch fd bv (bytevector-length bv) mask)])
        (when (< wd 0) (error 'inotify-add-watch "failed" path))
        wd)))

  (define (inotify-rm-watch fd wd)
    (let ([rc (c-inotify-rm-watch fd wd)])
      (when (< rc 0) (error 'inotify-rm-watch "failed" wd))
      (void)))

  ;; Returns list of inotify-event records, or '() if none ready
  (define (inotify-read-events fd)
    (let ([buf (make-bytevector 8192)]
          [count-box (make-bytevector 4 0)])
      (let ([rc (c-inotify-read fd buf 8192 count-box)])
        (when (< rc 0) (error 'inotify-read-events "read failed"))
        (let ([count (bytevector-s32-native-ref count-box 0)])
          (let loop ([i 0] [offset 0] [acc '()])
            (if (>= i count) (reverse acc)
              (let ([wd (bytevector-s32-native-ref buf offset)]
                    [mask (bytevector-u32-native-ref buf (+ offset 4))]
                    [name-len (bytevector-u32-native-ref buf (+ offset 8))])
                (let ([name (if (= name-len 0) ""
                              (utf8->string
                                (bv-sub buf (+ offset 12) name-len)))])
                  (loop (+ i 1) (+ offset 12 name-len)
                    (cons (make-inotify-event wd mask name) acc))))))))))

  ;; Helper
  (define (bv-sub bv start len)
    (let ([out (make-bytevector len)])
      (bytevector-copy! bv start out 0 len)
      out))

  ) ;; end library
