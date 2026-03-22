#!/usr/bin/env -S scheme --libdirs lib --script
;;; data-pipeline.ss — CSV to JSON data transformation pipeline
;;;
;;; Demonstrates: iterators, JSON, CSV, file I/O, hash tables, sorting
;;;
;;; Run: bin/jerboa run examples/data-pipeline.ss
;;;
;;; Creates sample CSV data, parses it, transforms it, and outputs JSON.

(import (except (chezscheme)
          make-hash-table hash-table?
          sort sort! format printf fprintf
          iota 1+ 1-
          path-extension path-absolute?
          with-input-from-string with-output-to-string)
        (jerboa prelude)
        (std iter)
        (std text json)
        (std text csv)
        (std os temporaries))

;; --- Sample data ---

(define sample-csv
  "name,department,salary,years
Alice,Engineering,120000,5
Bob,Engineering,115000,3
Carol,Marketing,95000,7
Dave,Engineering,130000,8
Eve,Marketing,105000,4
Frank,Sales,90000,2
Grace,Engineering,125000,6
Hank,Sales,88000,1
Ivy,Marketing,110000,9
Jack,Sales,92000,3")

;; --- Pipeline stages ---

(def (parse-employees csv-text)
  "Parse CSV text into a list of hash tables."
  (let* ([rows (read-csv (open-input-string csv-text))]
         [headers (car rows)]
         [data (cdr rows)])
    (map (lambda (row)
           (let ([ht (make-hash-table)])
             (for-each
               (lambda (header value)
                 (hash-put! ht header
                   (if (or (string=? header "salary")
                           (string=? header "years"))
                     (string->number value)
                     value)))
               headers row)
             ht))
         data)))

(def (group-by-department employees)
  "Group employees by department."
  (let ([groups (make-hash-table)])
    (for-each
      (lambda (emp)
        (let* ([dept (hash-ref emp "department")]
               [existing (or (hash-get groups dept) '())])
          (hash-put! groups dept (cons emp existing))))
      employees)
    groups))

(def (department-stats groups)
  "Compute per-department statistics."
  (let ([stats '()])
    (hash-for-each
      (lambda (dept employees)
        (let* ([salaries (map (lambda (e) (hash-ref e "salary")) employees)]
               [count (length salaries)]
               [total (apply + salaries)]
               [avg (quotient total count)]
               [max-sal (apply max salaries)]
               [min-sal (apply min salaries)]
               [total-years (apply + (map (lambda (e) (hash-ref e "years"))
                                          employees))])
          (set! stats
            (cons (list->hash-table
                    `(("department" . ,dept)
                      ("headcount" . ,count)
                      ("avg_salary" . ,avg)
                      ("max_salary" . ,max-sal)
                      ("min_salary" . ,min-sal)
                      ("total_experience_years" . ,total-years)
                      ("members" . ,(map (lambda (e) (hash-ref e "name"))
                                         employees))))
                  stats))))
      groups)
    (sort stats
      (lambda (a b)
        (string<? (hash-ref a "department")
                  (hash-ref b "department"))))))

(def (top-earners employees (n 3))
  "Find the top N earners across all departments."
  (let ([sorted (sort employees
                  (lambda (a b)
                    (> (hash-ref a "salary") (hash-ref b "salary"))))])
    (if (> (length sorted) n)
      (list-head sorted n)
      sorted)))

;; --- Run the pipeline ---

(printf "=== Jerboa Data Pipeline ===\n\n")

;; Stage 1: Parse
(printf "Stage 1: Parsing CSV data...\n")
(define employees (parse-employees sample-csv))
(printf "  Parsed ~a employee records\n\n" (length employees))

;; Stage 2: Group
(printf "Stage 2: Grouping by department...\n")
(define groups (group-by-department employees))
(printf "  Found ~a departments\n\n" (hash-length groups))

;; Stage 3: Compute stats
(printf "Stage 3: Computing department statistics...\n")
(define stats (department-stats groups))

;; Stage 4: Output
(printf "\n--- Department Summary (JSON) ---\n\n")
(for-each
  (lambda (dept-stat)
    (printf "~a:\n" (hash-ref dept-stat "department"))
    (printf "  Headcount: ~a\n" (hash-ref dept-stat "headcount"))
    (printf "  Avg Salary: $~a\n" (hash-ref dept-stat "avg_salary"))
    (printf "  Salary Range: $~a - $~a\n"
            (hash-ref dept-stat "min_salary")
            (hash-ref dept-stat "max_salary"))
    (printf "  Total Experience: ~a years\n"
            (hash-ref dept-stat "total_experience_years"))
    (printf "  Members: ~a\n\n"
            (string-join (hash-ref dept-stat "members") ", ")))
  stats)

;; Top earners
(printf "--- Top 3 Earners ---\n\n")
(for-each
  (lambda (emp)
    (printf "  ~a (~a): $~a (~a years)\n"
            (hash-ref emp "name")
            (hash-ref emp "department")
            (hash-ref emp "salary")
            (hash-ref emp "years")))
  (top-earners employees))

;; Full JSON output
(printf "\n--- Full JSON Output ---\n\n")
(let ([report (list->hash-table
                `(("generated" . ,(format "~a" (current-time)))
                  ("total_employees" . ,(length employees))
                  ("departments" . ,stats)
                  ("top_earners" . ,(map (lambda (e)
                                           (list->hash-table
                                             `(("name" . ,(hash-ref e "name"))
                                               ("salary" . ,(hash-ref e "salary")))))
                                         (top-earners employees)))))])
  (displayln (json-object->string report)))
