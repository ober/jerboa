#!chezscheme
;;; (std dev pgo) -- Profile-Guided Optimization
;;;
;;; Records type feedback from production runs and feeds it back to the
;;; compiler to specialize hot call sites.
;;;
;;; Workflow:
;;;   1. Instrument: add (profile-call ...) around hot call sites
;;;   2. Run with production workload: types are recorded in *pgo-profiles*
;;;   3. Save: (save-profile! "myapp.prof")
;;;   4. Optimize: use (with-pgo "myapp.prof" ...) to specialize code
;;;
;;; Example:
;;;   ;; Instrumented version (slow):
;;;   (define (sum lst)
;;;     (let loop ([l lst] [acc 0])
;;;       (if (null? l) acc
;;;         (loop (cdr l) (profile-call + acc (car l))))))
;;;
;;;   ;; Optimized version (after collecting profile):
;;;   (define (sum lst)
;;;     (let loop ([l lst] [acc 0])
;;;       (if (null? l) acc
;;;         (loop (cdr l)
;;;           (pgo-specialize add-site acc (car l)
;;;             [(fixnum fixnum) (fx+ acc (car l))]
;;;             [else (+ acc (car l))]))))))

(library (std dev pgo)
  (export
    ;; Instrumentation
    profile-call
    profile-val

    ;; Profile data access
    *pgo-profiles*
    profile-site-counts
    profile-dominant-type
    profile-summary

    ;; Persistence
    save-profile!
    load-profile!
    merge-profile!

    ;; Optimization macros
    pgo-specialize
    with-pgo-file)

  (import (chezscheme))

  ;;; ========== Type classification ==========

  (define (classify-type val)
    (cond
      [(fixnum? val)      'fixnum]
      [(flonum? val)      'flonum]
      [(bignum? val)      'bignum]
      [(rational? val)    'rational]
      [(complex? val)     'complex]
      [(boolean? val)     'boolean]
      [(char? val)        'char]
      [(string? val)      'string]
      [(symbol? val)      'symbol]
      [(null? val)        'null]
      [(pair? val)        'pair]
      [(vector? val)      'vector]
      [(bytevector? val)  'bytevector]
      [(procedure? val)   'procedure]
      [(port? val)        'port]
      [else               'other]))

  ;;; ========== Profile storage ==========
  ;; eq-hashtable: site-id (symbol) -> eq-hashtable of type->count

  (define *pgo-profiles* (make-eq-hashtable))

  (define (ensure-site! site-id)
    (or (hashtable-ref *pgo-profiles* site-id #f)
        (let ([t (make-eq-hashtable)])
          (hashtable-set! *pgo-profiles* site-id t)
          t)))

  (define (record-type! site-id val)
    (let* ([counts (ensure-site! site-id)]
           [type   (classify-type val)])
      (hashtable-set! counts type
        (+ 1 (hashtable-ref counts type 0)))))

  ;;; ========== profile-call ==========
  ;; (profile-call site-id proc arg ...)
  ;; Calls (proc arg ...), records types of result and each arg at site-id.
  ;; Returns result unchanged.
  (define-syntax profile-call
    (syntax-rules ()
      [(_ site-id proc arg ...)
       ;; Evaluate all args, call proc, record result type at site-id
       (let ([result (proc arg ...)])
         (record-type! 'site-id result)
         result)]))

  ;;; ========== profile-val ==========
  ;; (profile-val site-id expr)
  ;; Records the type of expr's result without wrapping a call.
  (define-syntax profile-val
    (syntax-rules ()
      [(_ site-id expr)
       (let ([v expr])
         (record-type! 'site-id v)
         v)]))

  ;;; ========== Profile queries ==========

  ;; Returns alist of (type . count) for a site, sorted by count descending.
  (define (profile-site-counts site-id)
    (let ([counts (hashtable-ref *pgo-profiles* site-id #f)])
      (if (not counts)
        '()
        (let-values ([(keys vals) (hashtable-entries counts)])
          (let ([pairs (map cons (vector->list keys) (vector->list vals))])
            (sort (lambda (a b) (> (cdr a) (cdr b))) pairs))))))

  ;; Returns the most common type at site-id, or #f if no data.
  (define (profile-dominant-type site-id)
    (let ([counts (profile-site-counts site-id)])
      (and (not (null? counts)) (caar counts))))

  ;; Print a human-readable summary of all profile data.
  (define (profile-summary . port-opt)
    (let ([port (if (pair? port-opt) (car port-opt) (current-output-port))])
      (let-values ([(sites _) (hashtable-entries *pgo-profiles*)])
        (vector-for-each
          (lambda (site)
            (display (format "site ~a:\n" site) port)
            (for-each
              (lambda (pair)
                (display (format "  ~a: ~a\n" (car pair) (cdr pair)) port))
              (profile-site-counts site)))
          sites))))

  ;;; ========== Persistence ==========

  ;; Save profile data as an S-expression file.
  (define (save-profile! path)
    (call-with-output-file path
      (lambda (port)
        (write '(jerboa-pgo-profile 1) port) (newline port)
        (let-values ([(sites _) (hashtable-entries *pgo-profiles*)])
          (vector-for-each
            (lambda (site)
              (let ([counts (profile-site-counts site)])
                (write (list site counts) port)
                (newline port)))
            sites)))
      'replace))

  ;; Load profile data, merging into *pgo-profiles*.
  (define (load-profile! path)
    (guard (exn [#t (void)])
      (call-with-input-file path
        (lambda (port)
          (let ([header (read port)])
            (unless (and (pair? header) (eq? (car header) 'jerboa-pgo-profile))
              (error 'load-profile! "not a PGO profile file" path))
            (let loop ()
              (let ([entry (read port)])
                (unless (eof-object? entry)
                  (let* ([site   (car entry)]
                         [counts (cadr entry)]
                         [ht     (ensure-site! site)])
                    (for-each
                      (lambda (pair)
                        (let ([type  (car pair)]
                              [count (cdr pair)])
                          (hashtable-set! ht type
                            (+ count (hashtable-ref ht type 0)))))
                      counts))
                  (loop)))))))))

  ;; Merge a profile file into the current profiles without replacing.
  (define (merge-profile! path)
    (load-profile! path))

  ;;; ========== Compile-time profile store ==========
  ;; Separate from the runtime *pgo-profiles* — this is accessible at expand time.
  ;; with-pgo-file populates this; pgo-specialize reads from it.
  (meta define *ct-pgo-profiles* (make-eq-hashtable))

  ;; CT-level helpers (phase 1)
  (meta define (ct-profile-lookup ht site-id)
    (hashtable-ref ht site-id #f))

  (meta define (ct-dominant-type ht site-id)
    (let ([counts (ct-profile-lookup ht site-id)])
      (if (not counts)
        #f
        (let-values ([(keys vals) (hashtable-entries counts)])
          (let ([pairs (map cons (vector->list keys) (vector->list vals))])
            (if (null? pairs) #f
                (car (car (sort (lambda (a b) (> (cdr a) (cdr b))) pairs)))))))))

  (meta define (ct-load-profile! ht path)
    (guard (exn [#t (void)])
      (call-with-input-file path
        (lambda (port)
          (let ([header (read port)])
            (let loop ()
              (let ([entry (read port)])
                (unless (eof-object? entry)
                  (let* ([site   (car entry)]
                         [counts (cadr entry)]
                         [cur    (or (hashtable-ref ht site #f)
                                     (let ([t (make-eq-hashtable)])
                                       (hashtable-set! ht site t)
                                       t))])
                    (for-each
                      (lambda (p)
                        (hashtable-set! cur (car p)
                          (+ (cdr p) (hashtable-ref cur (car p) 0))))
                      counts))
                  (loop)))))))))

  ;;; ========== pgo-specialize ==========
  ;; (pgo-specialize site-id (arg ...) [(type ...) spec-expr] ... [else fallback-expr])
  ;;
  ;; Generates a runtime type dispatch for the args.
  ;; When a profile file has been loaded via with-pgo-file, annotates the
  ;; dominant type (for documentation/future use).
  (define-syntax pgo-specialize
    (lambda (stx)
      (syntax-case stx (else)
        [(_ site-id (arg ...) [(type ...) spec-expr] ... [else fallback-expr])
         (let* ([arg-list (syntax->list #'(arg ...))]
                [clauses  (map list
                            (syntax->list #'((type ...) ...))
                            (syntax->list #'(spec-expr ...)))])
           (with-syntax
             ([(check ...)
               (map (lambda (clause)
                      (let* ([types    (syntax->list (car clause))]
                             [spec     (cadr clause)]
                             [preds
                              (map (lambda (ty-stx arg-stx)
                                     (case (syntax->datum ty-stx)
                                       [(fixnum)  #`(fixnum?  #,arg-stx)]
                                       [(flonum)  #`(flonum?  #,arg-stx)]
                                       [(string)  #`(string?  #,arg-stx)]
                                       [(pair)    #`(pair?    #,arg-stx)]
                                       [(null)    #`(null?    #,arg-stx)]
                                       [(boolean) #`(boolean? #,arg-stx)]
                                       [(vector)  #`(vector?  #,arg-stx)]
                                       [else      #`#t]))
                                   types arg-list)]
                             [guard-expr
                              (if (= 1 (length preds)) (car preds)
                                  #`(and #,@preds))])
                        #`(#,guard-expr #,spec)))
                    clauses)])
             #'(cond check ... [else fallback-expr])))])))

  ;; (with-pgo-file "path.prof" body ...)
  ;; At compile time: loads profile data into *ct-pgo-profiles*.
  ;; Subsequent pgo-specialize calls in the same module can use the data.
  (define-syntax with-pgo-file
    (lambda (stx)
      (syntax-case stx ()
        [(_ path-str body ...)
         (let ([path (syntax->datum #'path-str)])
           (when (string? path)
             (ct-load-profile! *ct-pgo-profiles* path))
           #'(begin body ...))])))

) ;; end library
