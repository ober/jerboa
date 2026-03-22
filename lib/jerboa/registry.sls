#!chezscheme
;;; (jerboa registry) — GitHub-based package registry (no central server).
;;; Packages identified by github.com/user/repo, installed via git clone.

(library (jerboa registry)
  (export registry-search registry-lookup
          package-install! package-uninstall! package-update!
          installed-packages package-installed?
          *registry-file* *package-dir*)
  (import (except (chezscheme) make-hash-table hash-table? iota 1+ 1-)
          (jerboa runtime)
          (std text json))

  (define (home-dir)
    (or (getenv "HOME") (error 'registry "HOME not set")))

  (define *registry-file*
    (make-parameter (string-append (home-dir) "/.jerboa/registry.json")))

  (define *package-dir*
    (make-parameter (string-append (home-dir) "/.jerboa/packages/")))

  (define (ensure-directory path)
    (unless (file-exists? path)
      (system (string-append "mkdir -p " (shell-quote path)))))

  (define (shell-quote s)
    (string-append "'" (let loop ([i 0] [acc ""])
      (if (= i (string-length s))
        acc
        (let ([ch (string-ref s i)])
          (if (char=? ch #\')
            (loop (+ i 1) (string-append acc "'\\''"))
            (loop (+ i 1) (string-append acc (string ch))))))) "'"))

  (define (run-command cmd)
    (let ([rc (system cmd)])
      (unless (= rc 0)
        (error 'registry "command failed" cmd rc))))

  (define (url-from-github-path gh-path)
    (string-append "https://" gh-path ".git"))

  (define (name-from-github-path gh-path)
    (let loop ([i (- (string-length gh-path) 1)])
      (cond
        [(< i 0) gh-path]
        [(char=? (string-ref gh-path i) #\/)
         (substring gh-path (+ i 1) (string-length gh-path))]
        [else (loop (- i 1))])))

  (define (current-date-string)
    (let ([t (current-date)])
      (format "~a-~2,'0d-~2,'0d"
              (date-year t) (date-month t) (date-day t))))

  (define (load-registry)
    (let ([file (*registry-file*)])
      (if (file-exists? file)
        (let ([data (call-with-input-file file
                      (lambda (p) (read-json p)))])
          (if (list? data) data '()))
        '())))

  (define (save-registry! entries)
    (ensure-directory (path-parent (*registry-file*)))
    (call-with-output-file (*registry-file*)
      (lambda (p) (write-json entries p) (newline p))
      'replace))

  (define (path-parent path)
    (let loop ([i (- (string-length path) 1)])
      (cond
        [(< i 0) "."]
        [(char=? (string-ref path i) #\/) (substring path 0 i)]
        [else (loop (- i 1))])))

  ;; Entry accessors — each entry is a hashtable with string keys
  (define (entry-name e)    (hash-ref e "name" ""))
  (define (entry-version e) (hash-ref e "version" "0.0.0"))
  (define (entry-path e)    (hash-ref e "path" ""))
  (define (entry-url e)     (hash-ref e "url" ""))
  (define (entry-date e)    (hash-ref e "installed-date" ""))

  (define (make-entry name version path url date)
    (let ([ht (make-hash-table)])
      (hash-put! ht "name" name)
      (hash-put! ht "version" version)
      (hash-put! ht "path" path)
      (hash-put! ht "url" url)
      (hash-put! ht "installed-date" date)
      ht))

  (define (read-pkg-version pkg-dir)
    (let ([pkg-file (string-append pkg-dir "/jerboa.pkg")])
      (if (file-exists? pkg-file)
        (guard (e [#t "0.0.0"])
          (let ([data (call-with-input-file pkg-file read)])
            (if (list? data)
              (let loop ([lst data])
                (cond
                  [(null? lst) "0.0.0"]
                  [(and (pair? (car lst))
                        (eq? (caar lst) 'version))
                   (let ([v (cdar lst)])
                     (if (pair? v) (car v) (cdr (car lst))))]
                  [else (loop (cdr lst))]))
              "0.0.0")))
        "0.0.0")))

  (define (registry-search query)
    (let ([entries (load-registry)]
          [q (string-downcase query)])
      (filter (lambda (e)
                (string-contains (string-downcase (entry-name e)) q))
              entries)))

  (define (string-contains haystack needle)
    (let ([hlen (string-length haystack)]
          [nlen (string-length needle)])
      (let loop ([i 0])
        (cond
          [(> (+ i nlen) hlen) #f]
          [(string=? (substring haystack i (+ i nlen)) needle) #t]
          [else (loop (+ i 1))]))))

  (define (registry-lookup name)
    (let ([entries (load-registry)])
      (find (lambda (e) (string=? (entry-name e) name)) entries)))

  (define (package-install! gh-path)
    (let* ([name (name-from-github-path gh-path)]
           [url  (url-from-github-path gh-path)]
           [dest (string-append (*package-dir*) name)])
      (when (package-installed? name)
        (error 'package-install! "package already installed" name))
      (ensure-directory (*package-dir*))
      (run-command (string-append "git clone " (shell-quote url)
                                  " " (shell-quote dest)))
      (let* ([version (read-pkg-version dest)]
             [entry   (make-entry name version dest gh-path
                                  (current-date-string))]
             [entries (load-registry)])
        (save-registry! (cons entry entries))
        entry)))

  (define (package-uninstall! name)
    (let ([entry (registry-lookup name)])
      (unless entry
        (error 'package-uninstall! "package not installed" name))
      (let ([path (entry-path entry)])
        (when (file-exists? path)
          (run-command (string-append "rm -rf " (shell-quote path)))))
      (save-registry!
        (filter (lambda (e) (not (string=? (entry-name e) name)))
                (load-registry)))))

  (define (package-update! name)
    (let ([entry (registry-lookup name)])
      (unless entry
        (error 'package-update! "package not installed" name))
      (let ([path (entry-path entry)])
        (run-command (string-append "git -C " (shell-quote path) " pull")))))

  (define (installed-packages) (load-registry))

  (define (package-installed? name) (and (registry-lookup name) #t))

)
