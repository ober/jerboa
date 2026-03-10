#!chezscheme
;;; :std/os/path -- Path utilities

(library (std os path)
  (export path-expand path-normalize path-directory path-strip-directory
          path-extension path-strip-extension
          path-join path-absolute?)
  (import (except (chezscheme) path-extension path-absolute?))

  (define (path-expand path)
    (if (path-absolute? path)
      path
      (string-append (current-directory) "/" path)))

  (define (path-normalize path)
    (path-expand path))

  (define (path-directory path)
    (let ([idx (string-last-index path #\/)])
      (if idx
        (substring path 0 idx)
        ".")))

  (define (path-strip-directory path)
    (let ([idx (string-last-index path #\/)])
      (if idx
        (substring path (+ idx 1) (string-length path))
        path)))

  (define (path-extension path)
    (let ([base (path-strip-directory path)])
      (let ([idx (string-last-index base #\.)])
        (if idx
          (substring base idx (string-length base))
          ""))))

  (define (path-strip-extension path)
    (let ([idx (string-last-index path #\.)])
      (if idx
        (substring path 0 idx)
        path)))

  (define (path-join . parts)
    (let loop ([rest parts] [acc ""])
      (if (null? rest) acc
        (let ([part (car rest)])
          (loop (cdr rest)
                (if (string=? acc "")
                  part
                  (string-append acc "/" part)))))))

  (define (path-absolute? path)
    (and (> (string-length path) 0)
         (char=? (string-ref path 0) #\/)))

  ;; Helper: find last index of char in string
  (define (string-last-index str ch)
    (let loop ([i (- (string-length str) 1)])
      (cond
        [(< i 0) #f]
        [(char=? (string-ref str i) ch) i]
        [else (loop (- i 1))])))

  ) ;; end library
