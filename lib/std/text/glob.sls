#!chezscheme
;;; (std text glob) -- Glob/Fnmatch Pattern Matching
;;;
;;; Supports:
;;;   *      — match any sequence of non-/ chars
;;;   **     — match any sequence including /
;;;   ?      — match any single char
;;;   [abc]  — match any char in set
;;;   [!abc] — match any char not in set
;;;   [a-z]  — match char range
;;;
;;; Usage:
;;;   (import (std text glob))
;;;   (glob-match? "*.ss" "hello.ss")        ; => #t
;;;   (glob-match? "src/**/*.ss" "src/a/b.ss") ; => #t
;;;   (glob-filter "*.ss" '("a.ss" "b.txt"))  ; => ("a.ss")
;;;   (glob-expand "*.ss")                     ; => list of matching files

(library (std text glob)
  (export
    glob-match?
    glob-filter
    glob-expand
    glob->regex-string)

  (import (chezscheme))

  ;; ========== Pattern Matching ==========
  (define (glob-match? pattern str)
    ;; Match a glob pattern against a string
    (match-glob (string->list pattern) (string->list str)))

  (define (match-glob pat str)
    (cond
      ;; Both empty — match
      [(and (null? pat) (null? str)) #t]
      ;; Pattern empty, string not — no match
      [(null? pat) #f]
      ;; ** — match any sequence including empty
      [(and (eqv? (car pat) #\*)
            (pair? (cdr pat))
            (eqv? (cadr pat) #\*))
       (let ([rest-pat (cddr pat)])
         ;; Skip optional / after **
         (let ([rest-pat (if (and (pair? rest-pat) (eqv? (car rest-pat) #\/))
                           (cdr rest-pat) rest-pat)])
           ;; Try matching rest-pat at every position
           (let loop ([s str])
             (cond
               [(match-glob rest-pat s) #t]
               [(null? s) #f]
               [else (loop (cdr s))]))))]
      ;; * — match any non-/ sequence
      [(eqv? (car pat) #\*)
       (let ([rest-pat (cdr pat)])
         (let loop ([s str])
           (cond
             [(match-glob rest-pat s) #t]
             [(null? s) #f]
             [(eqv? (car s) #\/) #f]  ;; * doesn't cross /
             [else (loop (cdr s))])))]
      ;; ? — match any single non-/ char
      [(eqv? (car pat) #\?)
       (and (pair? str)
            (not (eqv? (car str) #\/))
            (match-glob (cdr pat) (cdr str)))]
      ;; [chars] — character class
      [(eqv? (car pat) #\[)
       (let-values ([(negate? chars rest-pat) (parse-char-class (cdr pat))])
         (and (pair? str)
              (let ([match-class? (char-in-class? (car str) chars)])
                (if negate? (not match-class?) match-class?))
              (match-glob rest-pat (cdr str))))]
      ;; Literal char
      [(null? str) #f]
      [(eqv? (car pat) (car str))
       (match-glob (cdr pat) (cdr str))]
      [else #f]))

  (define (parse-char-class chars)
    ;; Parse [!abc] or [a-z] etc, return (values negate? char-specs rest-pat)
    (let* ([negate? (and (pair? chars) (eqv? (car chars) #\!))]
           [chars (if negate? (cdr chars) chars)])
      (let loop ([cs chars] [specs '()])
        (cond
          [(null? cs) (values negate? (reverse specs) '())]  ;; unclosed
          [(eqv? (car cs) #\])
           (values negate? (reverse specs) (cdr cs))]
          ;; Range: a-z
          [(and (pair? (cdr cs)) (pair? (cddr cs))
                (eqv? (cadr cs) #\-) (not (eqv? (caddr cs) #\])))
           (loop (cdddr cs) (cons (cons (car cs) (caddr cs)) specs))]
          [else
           (loop (cdr cs) (cons (car cs) specs))]))))

  (define (char-in-class? c specs)
    (let loop ([specs specs])
      (cond
        [(null? specs) #f]
        [(char? (car specs))
         (or (eqv? c (car specs)) (loop (cdr specs)))]
        [(pair? (car specs))
         ;; Range
         (or (and (char>=? c (caar specs))
                  (char<=? c (cdar specs)))
             (loop (cdr specs)))]
        [else (loop (cdr specs))])))

  ;; ========== Filter ==========
  (define (glob-filter pattern strings)
    (filter (lambda (s) (glob-match? pattern s)) strings))

  ;; ========== Expand (filesystem) ==========
  (define (glob-expand pattern)
    ;; Expand a glob pattern against the filesystem
    ;; For simple patterns without /, just list current directory
    (if (string-contains-char? pattern #\/)
      (glob-expand-path (split-path pattern) "")
      (glob-expand-simple pattern ".")))

  (define (glob-expand-simple pattern dir)
    ;; Match files in a single directory
    (guard (exn [#t '()])
      (let ([entries (directory-list dir)])
        (filter (lambda (f) (glob-match? pattern f))
                (map symbol->string entries)))))

  (define (glob-expand-path parts prefix)
    ;; Recursively match path components
    (cond
      [(null? parts) (list prefix)]
      [(string=? (car parts) "**")
       ;; Recursive descent
       (let ([rest (cdr parts)])
         (let loop ([dirs (list (if (string=? prefix "") "." prefix))]
                    [results '()])
           (if (null? dirs)
             results
             (let* ([dir (car dirs)]
                    [matches (if (null? rest)
                               (all-files-recursive dir)
                               (glob-expand-path rest dir))]
                    [subdirs (guard (exn [#t '()])
                               (filter
                                 (lambda (d)
                                   (file-directory?
                                     (if (string=? dir ".") d
                                       (string-append dir "/" d))))
                                 (map (lambda (e) (if (symbol? e) (symbol->string e) e)) (directory-list dir))))])
               (loop (append (cdr dirs)
                            (map (lambda (d)
                                   (if (string=? dir ".") d
                                     (string-append dir "/" d)))
                                 subdirs))
                     (append results matches))))))]
      [else
       ;; Normal component
       (let* ([dir (if (string=? prefix "") "." prefix)]
              [entries (guard (exn [#t '()])
                         (map (lambda (e) (if (symbol? e) (symbol->string e) e)) (directory-list dir)))]
              [matches (filter (lambda (e) (glob-match? (car parts) e)) entries)])
         (let loop ([ms matches] [results '()])
           (if (null? ms)
             results
             (let ([full (if (string=? prefix "")
                           (car ms)
                           (string-append prefix "/" (car ms)))])
               (loop (cdr ms)
                     (append results
                       (if (null? (cdr parts))
                         (list full)
                         (if (file-directory? full)
                           (glob-expand-path (cdr parts) full)
                           '()))))))))]))

  (define (all-files-recursive dir)
    (guard (exn [#t '()])
      (let loop ([dirs (list dir)] [files '()])
        (if (null? dirs) files
          (let* ([d (car dirs)]
                 [entries (map (lambda (e)
                                (let ([path (string-append d "/" (symbol->string e))])
                                  path))
                              (directory-list d))]
                 [subdirs (filter file-directory? entries)])
            (loop (append (cdr dirs) subdirs)
                  (append files entries)))))))

  ;; ========== Regex Conversion ==========
  (define (glob->regex-string pattern)
    ;; Convert glob to a regex string
    (let ([out (open-output-string)])
      (display "^" out)
      (let loop ([cs (string->list pattern)])
        (cond
          [(null? cs) (void)]
          [(and (eqv? (car cs) #\*) (pair? (cdr cs)) (eqv? (cadr cs) #\*))
           (display ".*" out)
           (loop (cddr cs))]
          [(eqv? (car cs) #\*)
           (display "[^/]*" out)
           (loop (cdr cs))]
          [(eqv? (car cs) #\?)
           (display "[^/]" out)
           (loop (cdr cs))]
          [(eqv? (car cs) #\[)
           (display "[" out)
           (loop (cdr cs))]
          [(eqv? (car cs) #\])
           (display "]" out)
           (loop (cdr cs))]
          [(memv (car cs) '(#\. #\^ #\$ #\+ #\{ #\} #\| #\( #\) #\\))
           (display "\\" out)
           (display (car cs) out)
           (loop (cdr cs))]
          [else
           (display (car cs) out)
           (loop (cdr cs))]))
      (display "$" out)
      (get-output-string out)))

  ;; ========== Helpers ==========
  (define (string-contains-char? s c)
    (let ([n (string-length s)])
      (let loop ([i 0])
        (cond
          [(= i n) #f]
          [(char=? (string-ref s i) c) #t]
          [else (loop (+ i 1))]))))

  (define (split-path s)
    ;; Split "a/b/c" into ("a" "b" "c")
    (let ([n (string-length s)])
      (let loop ([i 0] [start 0] [acc '()])
        (cond
          [(= i n) (reverse (cons (substring s start n) acc))]
          [(char=? (string-ref s i) #\/)
           (loop (+ i 1) (+ i 1) (cons (substring s start i) acc))]
          [else (loop (+ i 1) start acc)]))))


) ;; end library
