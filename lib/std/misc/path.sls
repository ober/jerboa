#!chezscheme
(library (std misc path)
  (export
    path-default-extension
    path-normalize
    path-relative?
    path-split
    subpath)
  (import (chezscheme))

  ;; Add extension to path only if it doesn't already have one.
  ;; ext should include the leading dot, e.g. ".scm"
  (define (path-default-extension path ext)
    (let ([current (path-extension path)])
      (if (and current (not (string=? current "")))
          path
          (let ([ext* (if (and (> (string-length ext) 0)
                               (not (char=? (string-ref ext 0) #\.)))
                        (string-append "." ext)
                        ext)])
            (string-append path ext*)))))

  ;; Resolve . and .. components in a path string.
  (define (path-normalize path)
    (let* ([absolute? (and (> (string-length path) 0)
                           (char=? (string-ref path 0) #\/))]
           [parts (path-split path)]
           [resolved
            (let loop ([parts parts] [acc '()])
              (cond
                [(null? parts) (reverse acc)]
                [(string=? (car parts) ".")
                 (loop (cdr parts) acc)]
                [(string=? (car parts) "..")
                 (if (null? acc)
                     (loop (cdr parts) (if absolute? '() (list "..")))
                     (loop (cdr parts) (cdr acc)))]
                [else
                 (loop (cdr parts) (cons (car parts) acc))]))])
      (cond
        [(null? resolved)
         (if absolute? "/" ".")]
        [absolute?
         (string-append "/" (apply string-append
                                   (let loop ([parts resolved])
                                     (if (null? (cdr parts))
                                         (list (car parts))
                                         (cons (car parts)
                                               (cons "/" (loop (cdr parts))))))))]
        [else
         (apply string-append
                (let loop ([parts resolved])
                  (if (null? (cdr parts))
                      (list (car parts))
                      (cons (car parts)
                            (cons "/" (loop (cdr parts)))))))])))

  ;; #t if path does not start with /
  (define (path-relative? path)
    (or (string=? path "")
        (not (char=? (string-ref path 0) #\/))))

  ;; Split a path string into a list of non-empty components.
  ;; Leading / is dropped (use path-relative? to detect absolute paths).
  (define (path-split path)
    (let loop ([chars (string->list path)] [current '()] [acc '()])
      (cond
        [(null? chars)
         (let ([parts (reverse
                       (if (null? current)
                           acc
                           (cons (list->string (reverse current)) acc)))])
           (filter (lambda (s) (not (string=? s ""))) parts))]
        [(char=? (car chars) #\/)
         (if (null? current)
             (loop (cdr chars) '() acc)
             (loop (cdr chars) '() (cons (list->string (reverse current)) acc)))]
        [else
         (loop (cdr chars) (cons (car chars) current) acc)])))

  ;; Join base path with additional parts using "/" separators.
  ;; Trims trailing slashes from base and leading slashes from each part.
  (define (subpath base . parts)
    (define (trim-trailing-slash s)
      (let ([len (string-length s)])
        (if (and (> len 0) (char=? (string-ref s (- len 1)) #\/))
            (substring s 0 (- len 1))
            s)))
    (define (trim-leading-slash s)
      (if (and (> (string-length s) 0) (char=? (string-ref s 0) #\/))
          (substring s 1 (string-length s))
          s))
    (let loop ([parts parts] [result (trim-trailing-slash base)])
      (if (null? parts)
          result
          (loop (cdr parts)
                (string-append result "/" (trim-leading-slash (trim-trailing-slash (car parts))))))))

) ; end library
