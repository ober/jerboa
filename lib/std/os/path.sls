#!chezscheme
;;; :std/os/path -- Path utilities

(library (std os path)
  (export path-expand path-normalize path-directory path-strip-directory
          path-extension path-strip-extension path-strip-trailing-directory-separator
          path-join path-absolute?)
  (import (except (chezscheme) path-extension path-absolute?))

  (define (path-expand path . args)
    ;; Gerbil: (path-expand path) or (path-expand path dir)
    (let ([base (if (pair? args) (car args) (current-directory))])
      (if (path-absolute? path)
        path
        ;; Strip trailing slash from base to prevent double-slash
        (let ([clean-base (path-strip-trailing-directory-separator base)])
          (string-append clean-base "/" path)))))

  (define (path-normalize path . args)
    (apply path-expand path args))

  (define (path-directory path)
    (let ([idx (string-last-index path #\/)])
      (cond
        [(not idx) "."]
        [(= idx 0) "/"]  ;; root path: (path-directory "/foo") → "/"
        [else (substring path 0 idx)])))

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
    ;; Operate on the basename to avoid stripping dots in directory components
    ;; and to handle dotfiles (e.g., .bashrc has no extension).
    (let* ([dir-idx (string-last-index path #\/)]
           [base-start (if dir-idx (+ dir-idx 1) 0)]
           [base (substring path base-start (string-length path))]
           [dot-idx (string-last-index base #\.)])
      (if (and dot-idx (> dot-idx 0))  ;; dot-idx > 0 excludes dotfiles like .bashrc
        (substring path 0 (+ base-start dot-idx))
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

  (define (path-strip-trailing-directory-separator path)
    (let ((len (string-length path)))
      (if (and (> len 1) (char=? (string-ref path (- len 1)) #\/))
        (substring path 0 (- len 1))
        path)))

  ) ;; end library
