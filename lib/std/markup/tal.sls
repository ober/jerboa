#!chezscheme
;;; :std/markup/tal -- Template Attribute Language for SXML
;;; TAL processes SXML templates with special tal: attributes:
;;;   tal:content    -- replace element content with variable value
;;;   tal:replace    -- replace entire element with variable value
;;;   tal:condition  -- conditionally include element
;;;   tal:repeat     -- repeat element for each item in a list
;;;   tal:attributes -- set/override attributes from env
;;;   tal:omit-tag   -- omit surrounding tag, keep children
;;; Variables looked up in hashtable env; dotted paths (a/b) traverse nested envs.

(library (std markup tal)
  (export tal-expand tal-process make-tal-env tal-env-set! tal-env-ref)
  (import (chezscheme) (std markup sxml))

  ;; --- Environment: hashtable mapping string keys to values ---
  (define (make-tal-env) (make-hashtable string-hash string=?))
  (define (tal-env-set! env name value) (hashtable-set! env name value))

  (define (tal-env-ref env name)
    ;; Support paths: "a/b/c" traverses nested envs
    (let loop ((parts (string-split name #\/)) (cur env))
      (cond ((null? parts) cur)
            ((not (hashtable? cur)) #f)
            (else (let ((v (hashtable-ref cur (car parts) #f)))
                    (if (null? (cdr parts)) v (loop (cdr parts) v)))))))

  (define (string-split str delim)
    (let ((len (string-length str)))
      (let loop ((i 0) (start 0) (acc '()))
        (cond ((= i len) (reverse (cons (substring str start len) acc)))
              ((char=? (string-ref str i) delim)
               (loop (+ i 1) (+ i 1) (cons (substring str start i) acc)))
              (else (loop (+ i 1) start acc))))))

  (define (string-split-whitespace str)
    (let ((len (string-length str)))
      (let loop ((i 0) (start #f) (acc '()))
        (cond ((= i len)
               (reverse (if start (cons (substring str start len) acc) acc)))
              ((char-whitespace? (string-ref str i))
               (loop (+ i 1) #f (if start (cons (substring str start i) acc) acc)))
              (else (loop (+ i 1) (or start i) acc))))))

  (define (string-trim str)
    (let* ((len (string-length str))
           (s (let loop ((i 0))
                (if (and (< i len) (char-whitespace? (string-ref str i)))
                  (loop (+ i 1)) i)))
           (e (let loop ((i (- len 1)))
                (if (and (>= i s) (char-whitespace? (string-ref str i)))
                  (loop (- i 1)) (+ i 1)))))
      (if (>= s e) "" (substring str s e))))

  ;; --- TAL attribute helpers ---
  (define (tal-attr attrs name)
    (let ((sym (string->symbol (string-append "tal:" name))))
      (let loop ((a attrs))
        (cond ((null? a) #f)
              ((and (pair? (car a)) (eq? (caar a) sym))
               (if (pair? (cdar a)) (cadar a) #t))
              (else (loop (cdr a)))))))

  (define (strip-tal-attrs attrs)
    (filter (lambda (a)
              (and (pair? a)
                   (let ((n (symbol->string (car a))))
                     (not (and (>= (string-length n) 4)
                               (string=? (substring n 0 4) "tal:"))))))
            attrs))

  (define (strip-one-tal-attr elem attr-name)
    (let ((sym (string->symbol (string-append "tal:" attr-name))))
      (make-element (sxml:element-name elem)
                    (filter (lambda (a) (not (and (pair? a) (eq? (car a) sym))))
                            (sxml:attributes elem))
                    (sxml:children elem))))

  ;; --- Value conversion ---
  (define (value->children val)
    (cond ((not val) '()) ((string? val) (list val))
          ((number? val) (list (number->string val)))
          ((boolean? val) (if val (list "true") '()))
          ((and (pair? val) (symbol? (car val))) (list val))
          ((list? val) val)
          (else (list (format "~a" val)))))

  (define (truthy? val)
    (and val (not (and (string? val) (string=? val "")))
         (not (and (list? val) (null? val)))))

  (define (copy-env env)
    (let ((new (make-tal-env)))
      (let-values (((keys vals) (hashtable-entries env)))
        (vector-for-each (lambda (k v) (tal-env-set! new k v)) keys vals))
      new))

  ;; --- TAL processing engine ---
  (define (process-node node env)
    (cond ((string? node) (list node))
          ((not (sxml:element? node)) (list node))
          (else (process-element node env))))

  (define (process-children children env)
    (apply append (map (lambda (c) (process-node c env)) children)))

  ;; Process element with TAL directives (priority order):
  ;;   condition -> repeat -> replace -> attributes -> content -> omit-tag
  (define (process-element elem env)
    (let* ((attrs (sxml:attributes elem))
           (children (sxml:children elem))
           (tc (tal-attr attrs "condition"))
           (tr (tal-attr attrs "repeat"))
           (trp (tal-attr attrs "replace"))
           (ta (tal-attr attrs "attributes"))
           (tco (tal-attr attrs "content"))
           (to (tal-attr attrs "omit-tag")))
      (cond
        ;; 1. tal:condition
        ((and tc (not (truthy? (tal-env-ref env tc)))) '())
        ;; 2. tal:repeat
        (tr (process-repeat elem env tr))
        ;; 3. tal:replace
        (trp (value->children (tal-env-ref env trp)))
        ;; 4-6. Build element with remaining directives
        (else
         (let* ((clean (strip-tal-attrs attrs))
                (final-attrs (if ta (apply-tal-attributes clean ta env) clean))
                (final-children (if tco (value->children (tal-env-ref env tco))
                                    (process-children children env)))
                (result (make-element (sxml:element-name elem)
                                      final-attrs final-children)))
           (if (and to (truthy? (eval-omit-tag to env)))
             final-children
             (list result)))))))

  ;; tal:repeat "var collection" -- repeat element for each item
  (define (process-repeat elem env spec)
    (let* ((parts (string-split-whitespace spec))
           (_ (when (< (length parts) 2)
                (error 'tal-process "tal:repeat requires 'var collection'" spec)))
           (var (car parts)) (coll-name (cadr parts))
           (collection (tal-env-ref env coll-name)))
      (if (and collection (list? collection))
        (let loop ((items collection) (idx 0) (acc '()))
          (if (null? items) (apply append (reverse acc))
              (let* ((child-env (copy-env env))
                     (_ (tal-env-set! child-env var (car items)))
                     (rmeta (make-tal-env))
                     (_ (begin
                          (tal-env-set! rmeta "index" idx)
                          (tal-env-set! rmeta "number" (+ idx 1))
                          (tal-env-set! rmeta "even" (even? idx))
                          (tal-env-set! rmeta "odd" (odd? idx))
                          (tal-env-set! rmeta "start" (= idx 0))
                          (tal-env-set! rmeta "end" (null? (cdr items)))
                          (tal-env-set! rmeta "length" (length collection))
                          (tal-env-set! child-env "repeat" rmeta)))
                     (stripped (strip-one-tal-attr elem "repeat")))
                (loop (cdr items) (+ idx 1)
                      (cons (process-element stripped child-env) acc)))))
        '())))

  ;; tal:attributes "attr1 var1; attr2 var2"
  (define (apply-tal-attributes attrs spec env)
    (let ((pairs (parse-attr-spec spec)))
      (let loop ((p pairs) (cur attrs))
        (if (null? p) cur
            (let* ((attr-name (string->symbol (caar p)))
                   (var-name (cadar p))
                   (val (tal-env-ref env var-name)))
              (if val
                (let ((s (cond ((string? val) val) ((number? val) (number->string val))
                               ((boolean? val) (if val "true" "false"))
                               (else (format "~a" val)))))
                  (loop (cdr p) (set-attr-in-list cur attr-name s)))
                (loop (cdr p)
                      (filter (lambda (a) (not (and (pair? a) (eq? (car a) attr-name))))
                              cur))))))))

  (define (parse-attr-spec spec)
    (filter pair?
            (map (lambda (seg)
                   (let ((parts (string-split-whitespace (string-trim seg))))
                     (if (>= (length parts) 2) (list (car parts) (cadr parts)) #f)))
                 (string-split spec #\;))))

  (define (set-attr-in-list attrs name value)
    (let loop ((a attrs) (acc '()) (found? #f))
      (cond ((null? a) (if found? (reverse acc)
                            (reverse (cons (list name value) acc))))
            ((and (pair? (car a)) (eq? (caar a) name))
             (loop (cdr a) (cons (list name value) acc) #t))
            (else (loop (cdr a) (cons (car a) acc) found?)))))

  (define (eval-omit-tag spec env)
    (cond ((boolean? spec) spec)
          ((or (string=? spec "") (string-ci=? spec "true") (string=? spec "1")) #t)
          ((or (string-ci=? spec "false") (string=? spec "0")) #f)
          (else (tal-env-ref env spec))))

  ;; --- Public API ---
  (define (tal-process template env)
    (cond ((string? template) template)
          ((not (sxml:element? template)) template)
          ((eq? (sxml:element-name template) '*TOP*)
           (cons '*TOP* (process-children (sxml:children template) env)))
          (else (let ((r (process-element template env)))
                  (cond ((null? r) '())
                        ((= (length r) 1) (car r))
                        (else r))))))

  (define (tal-expand template env) (tal-process template env))

  ) ;; end library
