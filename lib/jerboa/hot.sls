#!chezscheme
;;; (jerboa hot) — Hot Code Reload
;;;
;;; Watch files for modification using mtime polling and reload them.

(library (jerboa hot)
  (export
    make-reloader reloader? reloader-watch! reloader-unwatch!
    reloader-check! reloader-reload! reloader-watched
    file-modified? file-mtimes
    with-reloader reloader-on-reload! reloader-on-error!
    reload-result? reload-result-file reload-result-success? reload-result-error
    ;; Testing helper: mark a watched file as stale (mtime=unknown)
    reloader-force-stale!)

  (import (chezscheme))

  ;; ========== Reload Result ==========

  (define-record-type (%reload-result make-reload-result reload-result?)
    (fields (immutable file    reload-result-file)
            (immutable success reload-result-success?)
            (immutable error   reload-result-error)))   ;; #f or condition

  ;; ========== Reloader ==========

  ;; mtimes: hashtable path -> mtime (integer seconds)
  ;; on-reload: procedure called with (path) on success; or #f
  ;; on-error:  procedure called with (path exn) on error; or #f

  (define-record-type (%reloader make-reloader-raw reloader?)
    (fields (mutable mtimes    reloader-mtimes    reloader-mtimes-set!)
            (mutable on-reload reloader-on-reload-cb reloader-on-reload-cb-set!)
            (mutable on-error  reloader-on-error-cb  reloader-on-error-cb-set!)))

  (define (make-reloader)
    (make-reloader-raw (make-hashtable equal-hash equal?) #f #f))

  (define (reloader-on-reload! r cb)
    (reloader-on-reload-cb-set! r cb))

  (define (reloader-on-error! r cb)
    (reloader-on-error-cb-set! r cb))

  (define (get-mtime path)
    (guard (exn [#t #f])
      (if (file-exists? path)
        (file-modification-time path)
        #f)))

  (define (mtime-equal? t1 t2)
    (cond
      [(and (not t1) (not t2)) #t]
      [(or  (not t1) (not t2)) #f]
      [else (time=? t1 t2)]))

  (define (reloader-watch! r path)
    ;; Add path to watch list, storing current mtime.
    (let ([mtime (get-mtime path)])
      (hashtable-set! (reloader-mtimes r) path mtime)))

  (define (reloader-unwatch! r path)
    (hashtable-delete! (reloader-mtimes r) path))

  (define (reloader-watched r)
    ;; Returns list of watched file paths.
    (let-values ([(keys _) (hashtable-entries (reloader-mtimes r))])
      (vector->list keys)))

  (define (file-modified? r path)
    ;; Returns #t if mtime differs from stored mtime.
    (let ([stored  (hashtable-ref (reloader-mtimes r) path #f)]
          [current (get-mtime path)])
      (not (mtime-equal? stored current))))

  (define (file-mtimes r)
    ;; Returns alist of (path . mtime) for all watched files.
    (let-values ([(keys vals) (hashtable-entries (reloader-mtimes r))])
      (let loop ([i 0] [acc '()])
        (if (= i (vector-length keys))
          acc
          (loop (+ i 1)
                (cons (cons (vector-ref keys i) (vector-ref vals i))
                      acc))))))

  (define (reloader-force-stale! r path)
    ;; Mark a watched file as stale (for testing). Sets stored mtime to #f.
    (hashtable-set! (reloader-mtimes r) path #f))

  (define (reloader-check! r)
    ;; Check all watched files; return list of changed file paths.
    (filter (lambda (path) (file-modified? r path))
            (reloader-watched r)))

  (define (reloader-reload! r)
    ;; For each changed file, reload it; return list of reload-results.
    (let ([changed (reloader-check! r)])
      (map (lambda (path)
             (let ([result
                    (guard (exn [#t (make-reload-result path #f exn)])
                      (load path)
                      ;; Update stored mtime on success
                      (hashtable-set! (reloader-mtimes r) path (get-mtime path))
                      (make-reload-result path #t #f))])
               ;; Fire callbacks
               (if (reload-result-success? result)
                 (let ([cb (reloader-on-reload-cb r)])
                   (when cb (cb path)))
                 (let ([cb (reloader-on-error-cb r)])
                   (when cb (cb path (reload-result-error result)))))
               result))
           changed)))

  (define-syntax with-reloader
    (syntax-rules ()
      [(_ r body ...)
       (let ([r (make-reloader)])
         body ...)]))

) ;; end library
