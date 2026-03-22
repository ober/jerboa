#!/usr/bin/env -S scheme --libdirs lib --script
;;; cli-tool.ss — A file statistics CLI tool
;;;
;;; Demonstrates: getopt, process, format, error handling, JSON output
;;;
;;; Run: bin/jerboa run examples/cli-tool.ss count --ext .ss lib/
;;;      bin/jerboa run examples/cli-tool.ss stats lib/std/
;;;      bin/jerboa run examples/cli-tool.ss find --pattern "defstruct" lib/

(import (except (chezscheme)
          make-hash-table hash-table?
          sort sort! format printf fprintf
          iota 1+ 1-
          path-extension path-absolute?
          with-input-from-string with-output-to-string)
        (jerboa prelude)
        (std cli getopt)
        (std misc process)
        (std text json))

;; --- File utilities ---

(def (directory-files-recursive dir (ext #f))
  (let ([result '()])
    (def (walk path)
      (for-each
        (lambda (entry)
          (let ([full (path-join path entry)])
            (cond
              [(and (file-exists? full)
                    (not (file-directory? full)))
               (when (or (not ext)
                         (string-suffix? ext full))
                 (set! result (cons full result)))]
              [(and (file-directory? full)
                    (not (string=? entry "."))
                    (not (string=? entry "..")))
               (walk full)])))
        (directory-list path)))
    (walk dir)
    (reverse result)))

(def (file-line-count path)
  (let ([lines 0])
    (call-with-input-file path
      (lambda (port)
        (let loop ()
          (unless (eof-object? (get-line port))
            (set! lines (+ lines 1))
            (loop)))))
    lines))

(def (file-contains? path pattern)
  (call-with-input-file path
    (lambda (port)
      (let loop ()
        (let ([line (get-line port)])
          (cond
            [(eof-object? line) #f]
            [(string-contains line pattern) #t]
            [else (loop)]))))))

;; --- Commands ---

(def (cmd-count args)
  (let ([ext (or (agetv 'ext args) #f)]
        [dir (or (agetv 'dir args) ".")])
    (unless (file-directory? dir)
      (eprintf "Error: ~a is not a directory\n" dir)
      (exit 1))
    (let* ([files (directory-files-recursive dir ext)]
           [count (length files)])
      (printf "~a files" count)
      (when ext (printf " matching *~a" ext))
      (printf " in ~a\n" dir))))

(def (cmd-stats args)
  (let* ([dir (or (agetv 'dir args) ".")]
         [files (directory-files-recursive dir ".ss")])
    (unless (file-directory? dir)
      (eprintf "Error: ~a is not a directory\n" dir)
      (exit 1))
    (let* ([line-counts (map (lambda (f)
                               (cons f (file-line-count f)))
                             files)]
           [total-lines (apply + (map cdr line-counts))]
           [total-files (length files)]
           [sorted (sort line-counts (lambda (a b) (> (cdr a) (cdr b))))]
           [top-5 (if (> (length sorted) 5)
                    (list-head sorted 5)
                    sorted)])
      (printf "Directory: ~a\n" dir)
      (printf "Scheme files: ~a\n" total-files)
      (printf "Total lines: ~a\n" total-lines)
      (when (> total-files 0)
        (printf "Average: ~a lines/file\n" (quotient total-lines total-files)))
      (printf "\nLargest files:\n")
      (for-each
        (lambda (entry)
          (printf "  ~5d  ~a\n" (cdr entry) (car entry)))
        top-5))))

(def (cmd-find args)
  (let ([pattern (or (agetv 'pattern args) #f)]
        [dir (or (agetv 'dir args) ".")])
    (unless pattern
      (eprintf "Error: --pattern is required\n")
      (exit 1))
    (unless (file-directory? dir)
      (eprintf "Error: ~a is not a directory\n" dir)
      (exit 1))
    (let ([files (directory-files-recursive dir ".ss")])
      (for-each
        (lambda (f)
          (when (file-contains? f pattern)
            (printf "~a\n" f)))
        files))))

;; --- Main ---

(def (usage)
  (printf "Usage: cli-tool <command> [options] [directory]\n\n")
  (printf "Commands:\n")
  (printf "  count [--ext .ss] <dir>       Count files\n")
  (printf "  stats <dir>                   Line count statistics for .ss files\n")
  (printf "  find --pattern <str> <dir>    Find files containing pattern\n")
  (printf "\nExamples:\n")
  (printf "  cli-tool count --ext .sls lib/\n")
  (printf "  cli-tool stats lib/std/\n")
  (printf "  cli-tool find --pattern defstruct lib/\n"))

(def (parse-args argv)
  (let loop ([args (cdr argv)] ;; skip script name
             [result '()])
    (cond
      [(null? args) result]
      [(string=? (car args) "--ext")
       (if (null? (cdr args))
         (begin (eprintf "Error: --ext requires a value\n") (exit 1))
         (loop (cddr args) (cons (cons 'ext (cadr args)) result)))]
      [(string=? (car args) "--pattern")
       (if (null? (cdr args))
         (begin (eprintf "Error: --pattern requires a value\n") (exit 1))
         (loop (cddr args) (cons (cons 'pattern (cadr args)) result)))]
      [(string-prefix? "--" (car args))
       (eprintf "Unknown option: ~a\n" (car args))
       (exit 1)]
      [else
       (loop (cdr args) (cons (cons 'dir (car args)) result))])))

(let ([argv (command-line)])
  (when (< (length argv) 2)
    (usage)
    (exit 0))
  (let ([cmd (cadr argv)]
        [args (parse-args (cdr argv))])
    (cond
      [(string=? cmd "count") (cmd-count args)]
      [(string=? cmd "stats") (cmd-stats args)]
      [(string=? cmd "find")  (cmd-find args)]
      [(string=? cmd "help")  (usage)]
      [else
       (eprintf "Unknown command: ~a\n" cmd)
       (usage)
       (exit 1)])))
