#!chezscheme
;;; (std service multilog) — Log multiplexer with TAI64N timestamps and rotation
;;;
;;; Reads lines from stdin, optionally prepends TAI64N timestamps,
;;; writes to rotating log files in a log directory. Inspired by
;;; DJB's multilog.

(library (std service multilog)
  (export multilog!)

  (import (chezscheme))

  ;; ========== TAI64N Timestamp ==========

  (define TAI-OFFSET 4611686018427387904)

  (define (tai64n-stamp)
    ;; Returns a TAI64N timestamp string: @hex-encoded-12-bytes
    (let* ([t (current-time 'time-utc)]
           [secs (+ (time-second t) TAI-OFFSET)]
           [nsecs (time-nanosecond t)]
           [bv (make-bytevector 12 0)])
      (bytevector-u64-set! bv 0 secs (endianness big))
      (bytevector-u32-set! bv 4 nsecs (endianness big))
      (string-append "@"
        (let loop ([i 0] [acc '()])
          (if (= i 12)
            (apply string-append (reverse acc))
            (loop (+ i 1)
                  (cons (let ([b (bytevector-u8-ref bv i)])
                          (string-append
                            (if (< b 16) "0" "")
                            (number->string b 16)))
                        acc)))))))

  ;; ========== Log Rotation ==========

  (define (rotate-log! log-dir max-files)
    ;; Rename current → @timestamp.s, prune excess files
    (let* ([current-path (string-append log-dir "/current")]
           [stamp (tai64n-stamp)]
           [archive-name (string-append stamp ".s")]
           [archive-path (string-append log-dir "/" archive-name)])
      ;; Rename current to archive
      (when (file-exists? current-path)
        (rename-file current-path archive-path))
      ;; Prune oldest archives beyond max-files
      (let* ([entries (directory-list log-dir)]
             [archives (filter (lambda (f) (and (> (string-length f) 2)
                                                (char=? (string-ref f 0) #\@)
                                                (string-suffix? ".s" f)))
                         entries)]
             [sorted (sort string>? archives)]  ;; newest first
             [excess (if (> (length sorted) max-files)
                       (list-tail sorted max-files)
                       '())])
        (for-each
          (lambda (f)
            (delete-file (string-append log-dir "/" f)))
          excess))))

  (define (string-suffix? suffix str)
    (let ([slen (string-length suffix)]
          [len (string-length str)])
      (and (>= len slen)
           (string=? (substring str (- len slen) len) suffix))))

  ;; ========== Main Loop ==========

  (define multilog!
    (case-lambda
      [(log-dir)
       (multilog! log-dir 99999 10 #t)]
      [(log-dir max-size)
       (multilog! log-dir max-size 10 #t)]
      [(log-dir max-size max-files)
       (multilog! log-dir max-size max-files #t)]
      [(log-dir max-size max-files timestamp?)
       ;; Ensure log directory exists
       (unless (file-exists? log-dir)
         (mkdir log-dir))

       (let ([current-path (string-append log-dir "/current")])
         (let outer-loop ()
           ;; Open current log file (append mode)
           (let ([out (open-file-output-port current-path
                        (file-options no-fail no-truncate)
                        (buffer-mode line)
                        (native-transcoder))])
             ;; Seek to end
             (set-port-position! out (port-length out))

             (let inner-loop ([bytes-written (port-position out)])
               (let ([line (get-line (current-input-port))])
                 (if (eof-object? line)
                   ;; EOF on stdin — done
                   (close-port out)
                   ;; Write line with optional timestamp
                   (let* ([prefix (if timestamp?
                                   (string-append (tai64n-stamp) " ")
                                   "")]
                          [output (string-append prefix line "\n")]
                          [len (string-length output)])
                     (put-string out output)
                     (flush-output-port out)
                     (let ([new-total (+ bytes-written len)])
                       (if (>= new-total max-size)
                         ;; Rotate
                         (begin
                           (close-port out)
                           (rotate-log! log-dir max-files)
                           (outer-loop))
                         (inner-loop new-total))))))))))]))

  ) ;; end library
