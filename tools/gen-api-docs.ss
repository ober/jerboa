#!/usr/bin/env -S scheme --libdirs lib --script
;;; gen-api-docs.ss — Generate API reference documentation from source
;;;
;;; Scans lib/ for .sls files, extracts library exports, and generates
;;; a markdown API reference.
;;;
;;; Run: bin/jerboa run tools/gen-api-docs.ss > docs/api-reference.md

(import (chezscheme))

;; --- File scanning ---

(define (find-sls-files dir)
  "Recursively find all .sls files under dir."
  (let ([result '()])
    (define (walk path)
      (for-each
        (lambda (entry)
          (let ([full (string-append path "/" entry)])
            (cond
              [(and (file-exists? full)
                    (not (file-directory? full))
                    (string-suffix? ".sls" full))
               (set! result (cons full result))]
              [(and (file-directory? full)
                    (not (string=? entry "."))
                    (not (string=? entry ".."))
                    (not (string=? entry ".git")))
               (walk full)])))
        (directory-list path)))
    (walk dir)
    (sort (lambda (a b) (string<? a b)) result)))

(define (string-suffix? suffix str)
  (let ([slen (string-length suffix)]
        [len (string-length str)])
    (and (>= len slen)
         (string=? suffix (substring str (- len slen) len)))))

;; --- Library parsing ---

(define (extract-library-info filepath)
  "Read a .sls file and extract library name and exports."
  (guard (e [#t #f])  ;; skip files that fail to read
    (let ([port (open-input-file filepath)])
      (let loop ()
        (let ([form (read port)])
          (cond
            [(eof-object? form)
             (close-port port)
             #f]
            [(and (pair? form) (eq? (car form) 'library))
             (close-port port)
             (let* ([name (cadr form)]
                    [clauses (cddr form)]
                    [exports (extract-exports clauses)])
               (list name exports))]
            [else (loop)]))))))

(define (extract-exports clauses)
  "Extract export symbols from library clauses."
  (let loop ([clauses clauses])
    (cond
      [(null? clauses) '()]
      [(and (pair? (car clauses))
            (eq? (caar clauses) 'export))
       (let ([exports (cdar clauses)])
         (apply append
           (map (lambda (e)
                  (cond
                    [(symbol? e) (list e)]
                    [(and (pair? e) (eq? (car e) 'rename))
                     (map cadr (cdr e))]  ;; exported name
                    [else '()]))
                exports)))]
      [else (loop (cdr clauses))])))

;; --- Library name formatting ---

(define (library-name->string name)
  (string-append "("
    (let loop ([parts name])
      (if (null? parts) ""
        (string-append
          (symbol->string (car parts))
          (if (null? (cdr parts)) ""
            (string-append " " (loop (cdr parts)))))))
    ")"))

(define (library-name->path name)
  "Convert library name to a relative path for linking."
  (let loop ([parts name])
    (if (null? parts) ""
      (string-append
        (symbol->string (car parts))
        (if (null? (cdr parts)) ""
          (string-append "/" (loop (cdr parts))))))))

;; --- Markdown generation ---

(define (categorize-libraries libs)
  "Group libraries by their top-level module."
  (let ([categories (make-hashtable string-hash string=?)])
    (for-each
      (lambda (lib)
        (let* ([name (car lib)]
               [category (if (and (pair? name) (>= (length name) 1))
                           (symbol->string (car name))
                           "other")]
               [existing (or (hashtable-ref categories category #f) '())])
          (hashtable-set! categories category (cons lib existing))))
      libs)
    categories))

(define (generate-markdown libs)
  (printf "# Jerboa API Reference\n\n")
  (printf "Auto-generated from source. ~a modules documented.\n\n" (length libs))
  (printf "---\n\n")

  ;; Table of contents
  (printf "## Table of Contents\n\n")
  (let ([categories (categorize-libraries libs)])
    (let-values ([(keys vals) (hashtable-entries categories)])
      (let ([sorted-keys (sort string<? (vector->list keys))])
        (for-each
          (lambda (cat)
            (printf "- [~a](#~a)\n" cat cat))
          sorted-keys)
        (printf "\n---\n\n")

        ;; Each category
        (for-each
          (lambda (cat)
            (printf "## ~a\n\n" cat)
            (let ([cat-libs (sort
                              (lambda (a b)
                                (string<? (library-name->string (car a))
                                          (library-name->string (car b))))
                              (hashtable-ref categories cat '()))])
              (for-each
                (lambda (lib)
                  (let ([name (car lib)]
                        [exports (cadr lib)])
                    (printf "### `~a`\n\n" (library-name->string name))
                    (if (null? exports)
                      (printf "_No exports_\n\n")
                      (begin
                        (printf "**Exports:** ")
                        (printf "~a\n\n"
                          (let loop ([exps exports] [first? #t])
                            (if (null? exps) ""
                              (string-append
                                (if first? "" ", ")
                                "`" (symbol->string (car exps)) "`"
                                (loop (cdr exps) #f)))))))))
                cat-libs))
            (printf "\n"))
          sorted-keys)))))

;; --- Main ---

(let* ([dir "lib"]
       [files (find-sls-files dir)]
       [libs (filter (lambda (x) x)
               (map extract-library-info files))])
  (generate-markdown libs))
