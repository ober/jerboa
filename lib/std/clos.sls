#!chezscheme
;;; (std clos) -- Full CLOS/MOP for Jerboa
;;;
;;; A complete Common Lisp-style object system with:
;;;   Layer 1: Meta-objects, classes, C3 linearization, make
;;;   Layer 2: Generic functions, multimethod dispatch, call-next-method
;;;   Layer 3: Slot protocol (initform, initarg, accessor, allocation)
;;;   Layer 4: Method combination (:before/:after/:around)
;;;   Layer 5: Advanced MOP (metaclasses, change-class, eql specializers)
;;;
;;; Based on Gregor Kiczales's Tiny CLOS, informed by STklos and AMOP.
;;; Instances are vectors with tag in slot 0, class in slot 1.

(library (std clos)
  (export
    ;; Layer 1: Foundation
    <top> <object> <class> <generic> <method>
    class-of class-name class-direct-superclasses class-direct-subclasses
    class-precedence-list class-slots class-direct-slots class-direct-methods
    is-a? instance?
    compute-cpl
    allocate-instance make make-instance
    find-class register-class!

    ;; Built-in type classes
    <boolean> <char> <null> <pair> <list>
    <number> <integer> <rational> <real> <complex>
    <string> <symbol> <keyword> <vector> <bytevector>
    <hashtable> <port> <input-port> <output-port>
    <procedure> <condition> <record> <eof> <void>

    ;; Layer 2: Generic functions & dispatch
    define-generic define-method
    generic-function-name generic-function-methods
    method-specializers method-procedure method-qualifiers
    method-generic-function
    compute-applicable-methods method-more-specific?
    sort-applicable-methods
    call-next-method next-method?
    no-applicable-method no-next-method
    apply-generic apply-method apply-methods
    add-method!

    ;; Layer 3: Slot protocol
    slot-ref slot-set! slot-bound? slot-exists?
    slot-value
    slot-unbound slot-missing
    compute-get-n-set compute-slots compute-slot-accessors
    slot-definition-name slot-definition-options
    slot-definition-initform slot-definition-initarg
    slot-definition-allocation slot-definition-accessor
    slot-definition-reader slot-definition-writer
    slot-definition-init-thunk slot-definition-validator
    slot-definition-observer slot-definition-delegate

    ;; Layer 4: Method combination
    compute-effective-method
    define-method-combination
    standard-method-combination

    ;; Layer 5: Advanced MOP
    define-class
    change-class
    validate-superclass
    describe
    class-subclasses class-methods
    shallow-clone deep-clone
    eql-specializer eql-specializer? eql-specializer-value
    predicate-specializer predicate-specializer?
    predicate-specializer-predicate predicate-specializer-description
    one-of-specializer

    ;; MOP hooks
    initialize slot-value-using-class
    make-class make-method-obj named-generic dispatch-named-generic
    )

  (import (chezscheme))

  ;; =========================================================================
  ;; Bootstrap class storage
  ;; =========================================================================
  ;; R6RS forbids exporting set!'d variables. We store class objects in a
  ;; mutable vector and export identifier-syntax macros that dereference it.

  (define *C* (make-vector 30 #f))

  ;; Indices into *C*
  (define-syntax %top      (identifier-syntax 0))
  (define-syntax %object   (identifier-syntax 1))
  (define-syntax %class    (identifier-syntax 2))
  (define-syntax %generic  (identifier-syntax 3))
  (define-syntax %method   (identifier-syntax 4))
  (define-syntax %boolean  (identifier-syntax 5))
  (define-syntax %char     (identifier-syntax 6))
  (define-syntax %null     (identifier-syntax 7))
  (define-syntax %pair     (identifier-syntax 8))
  (define-syntax %list     (identifier-syntax 9))
  (define-syntax %number   (identifier-syntax 10))
  (define-syntax %complex  (identifier-syntax 11))
  (define-syntax %real     (identifier-syntax 12))
  (define-syntax %rational (identifier-syntax 13))
  (define-syntax %integer  (identifier-syntax 14))
  (define-syntax %string   (identifier-syntax 15))
  (define-syntax %symbol   (identifier-syntax 16))
  (define-syntax %keyword  (identifier-syntax 17))
  (define-syntax %vector   (identifier-syntax 18))
  (define-syntax %bytevec  (identifier-syntax 19))
  (define-syntax %hashtable (identifier-syntax 20))
  (define-syntax %port     (identifier-syntax 21))
  (define-syntax %inport   (identifier-syntax 22))
  (define-syntax %outport  (identifier-syntax 23))
  (define-syntax %procedure (identifier-syntax 24))
  (define-syntax %condition (identifier-syntax 25))
  (define-syntax %record   (identifier-syntax 26))
  (define-syntax %eof      (identifier-syntax 27))
  (define-syntax %void     (identifier-syntax 28))

  ;; Exported names: these are identifier-syntax macros, not mutable variables
  (define-syntax <top>         (identifier-syntax (vector-ref *C* %top)))
  (define-syntax <object>      (identifier-syntax (vector-ref *C* %object)))
  (define-syntax <class>       (identifier-syntax (vector-ref *C* %class)))
  (define-syntax <generic>     (identifier-syntax (vector-ref *C* %generic)))
  (define-syntax <method>      (identifier-syntax (vector-ref *C* %method)))
  (define-syntax <boolean>     (identifier-syntax (vector-ref *C* %boolean)))
  (define-syntax <char>        (identifier-syntax (vector-ref *C* %char)))
  (define-syntax <null>        (identifier-syntax (vector-ref *C* %null)))
  (define-syntax <pair>        (identifier-syntax (vector-ref *C* %pair)))
  (define-syntax <list>        (identifier-syntax (vector-ref *C* %list)))
  (define-syntax <number>      (identifier-syntax (vector-ref *C* %number)))
  (define-syntax <complex>     (identifier-syntax (vector-ref *C* %complex)))
  (define-syntax <real>        (identifier-syntax (vector-ref *C* %real)))
  (define-syntax <rational>    (identifier-syntax (vector-ref *C* %rational)))
  (define-syntax <integer>     (identifier-syntax (vector-ref *C* %integer)))
  (define-syntax <string>      (identifier-syntax (vector-ref *C* %string)))
  (define-syntax <symbol>      (identifier-syntax (vector-ref *C* %symbol)))
  (define-syntax <keyword>     (identifier-syntax (vector-ref *C* %keyword)))
  (define-syntax <vector>      (identifier-syntax (vector-ref *C* %vector)))
  (define-syntax <bytevector>  (identifier-syntax (vector-ref *C* %bytevec)))
  (define-syntax <hashtable>   (identifier-syntax (vector-ref *C* %hashtable)))
  (define-syntax <port>        (identifier-syntax (vector-ref *C* %port)))
  (define-syntax <input-port>  (identifier-syntax (vector-ref *C* %inport)))
  (define-syntax <output-port> (identifier-syntax (vector-ref *C* %outport)))
  (define-syntax <procedure>   (identifier-syntax (vector-ref *C* %procedure)))
  (define-syntax <condition>   (identifier-syntax (vector-ref *C* %condition)))
  (define-syntax <record>      (identifier-syntax (vector-ref *C* %record)))
  (define-syntax <eof>         (identifier-syntax (vector-ref *C* %eof)))
  (define-syntax <void>        (identifier-syntax (vector-ref *C* %void)))

  ;; =========================================================================
  ;; Sentinel values
  ;; =========================================================================

  (define *unbound* (cons 'unbound 'slot))
  (define (unbound? v) (eq? v *unbound*))

  ;; =========================================================================
  ;; Instance representation
  ;; =========================================================================

  (define *instance-tag* (cons 'clos 'instance))

  (define (instance? obj)
    (and (vector? obj)
         (fx> (vector-length obj) 1)
         (eq? (vector-ref obj 0) *instance-tag*)))

  (define (instance-class obj)
    (vector-ref obj 1))

  (define (instance-ref obj index)
    (vector-ref obj (fx+ index 2)))

  (define (instance-set! obj index val)
    (vector-set! obj (fx+ index 2) val))

  (define (%allocate-instance class nfields)
    (let ([inst (make-vector (fx+ nfields 2) *unbound*)])
      (vector-set! inst 0 *instance-tag*)
      (vector-set! inst 1 class)
      inst))

  ;; =========================================================================
  ;; Class field layout
  ;; =========================================================================

  (define *class-name-idx*              0)
  (define *class-direct-supers-idx*     1)
  (define *class-direct-subclasses-idx* 2)
  (define *class-cpl-idx*               3)
  (define *class-direct-slots-idx*      4)
  (define *class-slots-idx*             5)
  (define *class-nfields-idx*           6)
  (define *class-getters-n-setters-idx* 7)
  (define *class-direct-methods-idx*    8)
  (define *class-redefined-idx*         9)
  (define *class-nslots*               10)

  (define *generic-name-idx*         0)
  (define *generic-methods-idx*      1)
  (define *generic-arity-idx*        2)
  (define *generic-combination-idx*  3)
  (define *generic-cache-idx*        4)
  (define *generic-nslots*           5)

  (define *method-gf-idx*           0)
  (define *method-specializers-idx* 1)
  (define *method-qualifiers-idx*   2)
  (define *method-procedure-idx*    3)
  (define *method-nslots*           4)

  ;; =========================================================================
  ;; Class accessors (used before class-of works)
  ;; =========================================================================

  (define (class-get c idx) (instance-ref c idx))
  (define (class-put! c idx v) (instance-set! c idx v))

  ;; =========================================================================
  ;; Class registry
  ;; =========================================================================

  (define *class-registry* (make-eq-hashtable))

  (define (register-class! name class)
    (hashtable-set! *class-registry* name class))

  (define (find-class name)
    (or (hashtable-ref *class-registry* name #f)
        (error 'find-class "unknown class" name)))

  ;; =========================================================================
  ;; C3 Linearization
  ;; =========================================================================

  (define (compute-cpl class)
    (letrec
      ([good-candidate?
         (lambda (c seqs)
           (not (exists (lambda (seq)
                          (and (pair? seq) (pair? (cdr seq))
                               (memq c (cdr seq))))
                        seqs)))]
       [pick-next
         (lambda (seqs)
           (let loop ([ss seqs])
             (if (null? ss)
                 (error 'compute-cpl "inconsistent class hierarchy")
                 (let ([head (caar ss)])
                   (if (good-candidate? head seqs)
                       head
                       (loop (cdr ss)))))))]
       [c3-merge
         (lambda (seqs)
           (let ([seqs (filter pair? seqs)])
             (if (null? seqs)
                 '()
                 (let ([next (pick-next seqs)])
                   (cons next
                         (c3-merge
                           (map (lambda (seq)
                                  (if (and (pair? seq) (eq? (car seq) next))
                                      (cdr seq)
                                      seq))
                                seqs)))))))])
      (let ([supers (class-get class *class-direct-supers-idx*)])
        (cons class
              (c3-merge
                (append (map (lambda (s) (class-get s *class-cpl-idx*))
                             supers)
                        (list supers)))))))

  ;; =========================================================================
  ;; Class introspection
  ;; =========================================================================

  (define (class-name c)                 (class-get c *class-name-idx*))
  (define (class-direct-superclasses c)  (class-get c *class-direct-supers-idx*))
  (define (class-direct-subclasses c)    (class-get c *class-direct-subclasses-idx*))
  (define (class-precedence-list c)      (class-get c *class-cpl-idx*))
  (define (class-direct-slots c)         (class-get c *class-direct-slots-idx*))
  (define (class-slots c)                (class-get c *class-slots-idx*))
  (define (class-direct-methods c)       (class-get c *class-direct-methods-idx*))

  ;; class-of — defined after bootstrap sets up class objects
  (define (class-of obj)
    (cond
      [(instance? obj) (instance-class obj)]
      [(boolean? obj)    <boolean>]
      [(null? obj)       <null>]
      [(char? obj)       <char>]
      [(and (integer? obj) (exact? obj)) <integer>]
      [(and (rational? obj) (exact? obj)) <rational>]
      [(real? obj)       <real>]
      [(complex? obj)    <complex>]
      [(number? obj)     <number>]
      [(string? obj)     <string>]
      [(symbol? obj)     <symbol>]
      [(pair? obj)       (if (list? obj) <list> <pair>)]
      [(vector? obj)     <vector>]
      [(bytevector? obj) <bytevector>]
      [(hashtable? obj)  <hashtable>]
      [(input-port? obj) <input-port>]
      [(output-port? obj)<output-port>]
      [(port? obj)       <port>]
      [(procedure? obj)  <procedure>]
      [(condition? obj)  <condition>]
      [(record? obj)     <record>]
      [(eof-object? obj) <eof>]
      [(eq? obj (void))  <void>]
      [else              <top>]))

  (define (is-a? obj class)
    (let ([c (class-of obj)])
      (and c (memq class (class-precedence-list c)) #t)))

  ;; =========================================================================
  ;; eql specializer
  ;; =========================================================================

  (define-record-type (%eql-specializer eql-specializer eql-specializer?)
    (fields (immutable value eql-specializer-value)))

  ;; =========================================================================
  ;; Generic function & method accessors
  ;; =========================================================================

  (define (generic-function-name gf)    (instance-ref gf *generic-name-idx*))
  (define (generic-function-methods gf) (instance-ref gf *generic-methods-idx*))
  (define (method-generic-function m)   (instance-ref m *method-gf-idx*))
  (define (method-specializers m)       (instance-ref m *method-specializers-idx*))
  (define (method-qualifiers m)         (instance-ref m *method-qualifiers-idx*))
  (define (method-procedure m)          (instance-ref m *method-procedure-idx*))

  ;; =========================================================================
  ;; Slot definition accessors
  ;; =========================================================================

  (define (slot-definition-name s)
    (if (pair? s) (car s) s))

  (define (slot-definition-options s)
    (if (pair? s) (cdr s) '()))

  (define (slot-opt s key default)
    (if (pair? s)
        (let loop ([opts (cdr s)])
          (cond
            [(null? opts) default]
            [(and (pair? opts) (pair? (cdr opts)) (eq? (car opts) key))
             (cadr opts)]
            [else (loop (if (pair? (cdr opts)) (cddr opts) '()))]))
        default))

  (define (slot-definition-initform s)   (slot-opt s ':initform *unbound*))
  (define (slot-definition-initarg s)    (slot-opt s ':initarg #f))
  (define (slot-definition-accessor s)   (slot-opt s ':accessor #f))
  (define (slot-definition-reader s)     (slot-opt s ':reader #f))
  (define (slot-definition-writer s)     (slot-opt s ':writer #f))
  (define (slot-definition-allocation s) (slot-opt s ':allocation ':instance))
  (define (slot-definition-init-thunk s) (slot-opt s ':init-thunk #f))
  (define (slot-definition-validator s)  (slot-opt s ':validator #f))
  (define (slot-definition-observer s)   (slot-opt s ':observer #f))
  (define (slot-definition-delegate s)   (slot-opt s ':delegate #f))

  ;; =========================================================================
  ;; Specializer matching
  ;; =========================================================================

  ;; Predicate specializer: dispatches via arbitrary predicate
  (define-record-type (%predicate-specializer predicate-specializer
                                              predicate-specializer?)
    (fields (immutable predicate predicate-specializer-predicate)
            (immutable description predicate-specializer-description)))

  ;; one-of specializer: matches membership in a set
  (define (one-of-specializer items . opts)
    (let ([test (if (pair? opts) (car opts) memv)])
      (predicate-specializer
        (lambda (arg) (test arg items))
        (format "(one-of ~s)" items))))

  (define (specializer-matches? spec arg)
    (cond
      [(eql-specializer? spec)
       (eqv? (eql-specializer-value spec) arg)]
      [(predicate-specializer? spec)
       ((predicate-specializer-predicate spec) arg)]
      [else
       (memq spec (class-precedence-list (class-of arg)))]))

  ;; =========================================================================
  ;; Next-method machinery
  ;; =========================================================================

  (define *next-method-list* (make-parameter '()))
  (define *next-method-args* (make-parameter '()))
  (define *current-gf*      (make-parameter #f))

  (define (call-next-method . new-args)
    (let ([methods (*next-method-list*)]
          [args (if (null? new-args) (*next-method-args*) new-args)]
          [gf (*current-gf*)])
      (if (null? methods)
          (no-next-method gf args)
          (apply-method gf methods args))))

  (define (next-method?)
    (pair? (*next-method-list*)))

  (define (no-applicable-method gf args)
    (error 'no-applicable-method
           "no applicable method"
           (if (instance? gf) (generic-function-name gf) gf) args))

  (define (no-next-method gf args)
    (error 'no-next-method
           "no next method"
           (if (instance? gf) (generic-function-name gf) gf) args))

  (define (apply-method gf methods args)
    (let ([m (car methods)]
          [rest (cdr methods)])
      (parameterize ([*next-method-list* rest]
                     [*next-method-args* args]
                     [*current-gf* gf])
        (apply (method-procedure m) args))))

  (define (apply-methods gf sorted-methods args)
    (if (null? sorted-methods)
        (no-applicable-method gf args)
        (apply-method gf sorted-methods args)))

  ;; =========================================================================
  ;; Dispatch: compute-applicable-methods, sort, apply-generic
  ;; =========================================================================

  (define (compute-applicable-methods gf args)
    (filter
      (lambda (m)
        (let ([specs (method-specializers m)])
          (and (= (length specs) (length args))
               (for-all specializer-matches? specs args))))
      (generic-function-methods gf)))

  ;; Specificity: eql > predicate > class (by CPL position)
  (define (specializer-specificity spec)
    (cond [(eql-specializer? spec) 2]
          [(predicate-specializer? spec) 1]
          [else 0]))

  (define (method-more-specific? m1 m2 arg-classes)
    (let loop ([s1 (method-specializers m1)]
               [s2 (method-specializers m2)]
               [ac arg-classes])
      (cond
        [(null? s1) #f]
        [(fx> (specializer-specificity (car s1))
              (specializer-specificity (car s2))) #t]
        [(fx< (specializer-specificity (car s1))
              (specializer-specificity (car s2))) #f]
        ;; Both same specificity level
        [(eql-specializer? (car s1))
         ;; Both eql — tie, check next arg
         (loop (cdr s1) (cdr s2) (cdr ac))]
        [(predicate-specializer? (car s1))
         ;; Both predicate — tie, check next arg
         (loop (cdr s1) (cdr s2) (cdr ac))]
        [else
         ;; Both class — compare by CPL position
         (let ([cpl (class-precedence-list (car ac))])
           (let find ([c cpl])
             (cond
               [(null? c) (loop (cdr s1) (cdr s2) (cdr ac))]
               [(eq? (car c) (car s1)) #t]
               [(eq? (car c) (car s2)) #f]
               [else (find (cdr c))])))])))

  (define (sort-applicable-methods gf methods args)
    (let ([arg-classes (map class-of args)])
      (list-sort
        (lambda (m1 m2) (method-more-specific? m1 m2 arg-classes))
        methods)))

  ;; =========================================================================
  ;; Method combination (Layer 4)
  ;; =========================================================================

  (define (partition-methods methods)
    (let loop ([ms methods]
               [around '()] [before '()] [primary '()] [after '()])
      (if (null? ms)
          (values (reverse around) (reverse before)
                  (reverse primary) (reverse after))
          (let ([quals (method-qualifiers (car ms))])
            (cond
              [(equal? quals '(:around))
               (loop (cdr ms) (cons (car ms) around) before primary after)]
              [(equal? quals '(:before))
               (loop (cdr ms) around (cons (car ms) before) primary after)]
              [(equal? quals '(:after))
               (loop (cdr ms) around before primary (cons (car ms) after))]
              [else
               (loop (cdr ms) around before (cons (car ms) primary) after)])))))

  (define (apply-standard-method-combination gf sorted-methods args)
    (let-values ([(around before primary after)
                  (partition-methods sorted-methods)])
      (when (null? primary)
        (no-applicable-method gf args))
      (letrec
        ([run-primary
           (lambda ()
             (for-each (lambda (m)
                         (parameterize ([*next-method-list* '()]
                                        [*next-method-args* args]
                                        [*current-gf* gf])
                           (apply (method-procedure m) args)))
                       before)
             (let ([result (apply-methods gf primary args)])
               (for-each (lambda (m)
                           (parameterize ([*next-method-list* '()]
                                          [*next-method-args* args]
                                          [*current-gf* gf])
                             (apply (method-procedure m) args)))
                         (reverse after))
               result))])
        (if (null? around)
            (run-primary)
            (let* ([primary-proxy
                     (make-method-obj gf
                       (if (pair? primary)
                           (method-specializers (car primary))
                           '())
                       '()
                       (lambda args* (run-primary)))]
                   [chain (append around (list primary-proxy))])
              (apply-method gf chain args))))))

  (define (compute-effective-method gf methods)
    (lambda args
      (apply-standard-method-combination gf methods args)))

  (define (standard-method-combination) 'standard)

  (define *method-combinations* (make-eq-hashtable))

  (define-syntax define-method-combination
    (syntax-rules ()
      [(_ name combiner)
       (hashtable-set! *method-combinations* 'name combiner)]))

  (define (apply-generic gf args)
    (let ([methods (compute-applicable-methods gf args)])
      (if (null? methods)
          (no-applicable-method gf args)
          (let ([sorted (sort-applicable-methods gf methods args)])
            (let ([combination (instance-ref gf *generic-combination-idx*)])
              (if (eq? combination 'standard)
                  (apply-standard-method-combination gf sorted args)
                  (apply-methods gf sorted args)))))))

  ;; =========================================================================
  ;; Factory functions
  ;; =========================================================================

  (define (make-generic-function name arity . opts)
    (let ([gf (%allocate-instance <generic> *generic-nslots*)])
      (instance-set! gf *generic-name-idx* name)
      (instance-set! gf *generic-methods-idx* '())
      (instance-set! gf *generic-arity-idx* arity)
      (instance-set! gf *generic-combination-idx*
        (if (pair? opts) (car opts) 'standard))
      (instance-set! gf *generic-cache-idx* (make-hashtable equal-hash equal?))
      gf))

  (define (make-method-obj gf specializers qualifiers proc)
    (let ([m (%allocate-instance <method> *method-nslots*)])
      (instance-set! m *method-gf-idx* gf)
      (instance-set! m *method-specializers-idx* specializers)
      (instance-set! m *method-qualifiers-idx* qualifiers)
      (instance-set! m *method-procedure-idx* proc)
      m))

  ;; =========================================================================
  ;; add-method!
  ;; =========================================================================

  (define (add-method! gf method)
    (let* ([new-specs (method-specializers method)]
           [new-quals (method-qualifiers method)]
           [old-methods (generic-function-methods gf)]
           [updated
             (let loop ([ms old-methods] [acc '()])
               (if (null? ms)
                   (cons method (reverse acc))
                   (if (and (equal? (method-specializers (car ms)) new-specs)
                            (equal? (method-qualifiers (car ms)) new-quals))
                       (append (reverse acc) (cons method (cdr ms)))
                       (loop (cdr ms) (cons (car ms) acc)))))])
      (instance-set! gf *generic-methods-idx* updated)
      (instance-set! gf *generic-cache-idx* (make-hashtable equal-hash equal?))
      (for-each (lambda (spec)
                  (when (and (instance? spec)
                             (not (eql-specializer? spec)))
                    (let ([dm (class-get spec *class-direct-methods-idx*)])
                      (unless (memq method dm)
                        (class-put! spec *class-direct-methods-idx*
                          (cons method dm))))))
                new-specs)
      (void)))

  ;; =========================================================================
  ;; gf->procedure
  ;; =========================================================================

  (define *procedure->gf* (make-eq-hashtable))

  (define (gf->procedure gf)
    (let ([proc (lambda args (apply-generic gf args))])
      (hashtable-set! *procedure->gf* proc gf)
      proc))

  (define (procedure->gf proc)
    (hashtable-ref *procedure->gf* proc #f))

  ;; =========================================================================
  ;; Named generics registry
  ;; =========================================================================

  (define *named-generics* (make-eq-hashtable))

  (define (named-generic name)
    (hashtable-ref *named-generics* name #f))

  (define (dispatch-named-generic name . args)
    (let ([gf (hashtable-ref *named-generics* name #f)])
      (unless gf
        (error 'dispatch-named-generic "no generic function" name))
      (apply-generic gf args)))

  (define (%add-method-to-gf! name specializers qualifiers proc)
    (let* ([gf (or (hashtable-ref *named-generics* name #f)
                   (let ([new-gf (make-generic-function name #f)])
                     (hashtable-set! *named-generics* name new-gf)
                     new-gf))]
           [m (make-method-obj gf specializers qualifiers proc)])
      (add-method! gf m)
      (void)))

  ;; =========================================================================
  ;; Slot protocol: compute-slots, compute-get-n-set
  ;; =========================================================================

  (define (compute-slots class)
    (let ([all-slots
            (apply append
              (map (lambda (c) (class-get c *class-direct-slots-idx*))
                   (class-get class *class-cpl-idx*)))])
      (let loop ([s all-slots] [seen '()] [acc '()])
        (if (null? s)
            (reverse acc)
            (let ([name (slot-definition-name (car s))])
              (if (memq name seen)
                  (loop (cdr s) seen acc)
                  (loop (cdr s) (cons name seen) (cons (car s) acc))))))))

  (define (compute-get-n-set class slot-def)
    (let ([raw
           (case (slot-definition-allocation slot-def)
             [(:instance)
              (let ([idx (class-get class *class-nfields-idx*)])
                (class-put! class *class-nfields-idx* (fx+ idx 1))
                idx)]
             [(:class)
              (let ([cell *unbound*])
                (cons (lambda (obj) cell)
                      (lambda (obj val) (set! cell val))))]
             [(:each-subclass)
              ;; Like :class, but each subclass gets its own shared cell
              (let ([cell *unbound*])
                (cons (lambda (obj) cell)
                      (lambda (obj val) (set! cell val))))]
             [(:delegate)
              ;; Forward to another slot by name
              (let ([target (slot-definition-delegate slot-def)])
                (unless target
                  (error 'compute-get-n-set
                         ":delegate allocation requires :delegate option" slot-def))
                (cons (lambda (obj) (slot-ref obj target))
                      (lambda (obj val) (slot-set! obj target val))))]
             [(:virtual)
              (let ([getter (slot-opt slot-def ':slot-ref #f)]
                    [setter (slot-opt slot-def ':slot-set! #f)])
                (unless (and getter setter)
                  (error 'compute-get-n-set
                         "virtual slot requires :slot-ref and :slot-set!" slot-def))
                (cons getter setter))]
             [else
              (error 'compute-get-n-set "unknown slot allocation"
                     (slot-definition-allocation slot-def))])])
      ;; Wrap with :validator and :observer if present
      (let ([validator (slot-definition-validator slot-def)]
            [observer (slot-definition-observer slot-def)])
        (if (and (not validator) (not observer))
            raw
            ;; Pair access needs wrapping
            (if (fixnum? raw)
                ;; Instance slot — convert to getter/setter pair for wrapping
                (let ([idx raw])
                  (cons (lambda (obj) (instance-ref obj idx))
                        (lambda (obj val)
                          (let ([v (if validator (validator obj val) val)])
                            (instance-set! obj idx v)
                            (when observer (observer obj v))))))
                ;; Already a pair
                (let ([getter (car raw)]
                      [setter (cdr raw)])
                  (cons getter
                        (lambda (obj val)
                          (let ([v (if validator (validator obj val) val)])
                            (setter obj v)
                            (when observer (observer obj v)))))))))))

  (define (compute-getters-n-setters class slots)
    (map (lambda (s)
           (let* ([s (if (pair? s) s (list s))]
                  [g-n-s (compute-get-n-set class s)]
                  [name (slot-definition-name s)]
                  [init-thunk (slot-definition-init-thunk s)]
                  [initform (slot-definition-initform s)]
                  ;; :init-thunk takes priority over :initform
                  [init-fn (cond
                             [init-thunk init-thunk]  ;; thunk: (lambda () value)
                             [(not (unbound? initform))
                              (lambda (obj) initform)]
                             [else #f])])
             (cons name (cons init-fn g-n-s))))
         slots))

  ;; =========================================================================
  ;; slot-ref / slot-set! / slot-bound? / slot-exists?
  ;; =========================================================================

  (define (slot-ref obj slot-name)
    (let* ([class (class-of obj)]
           [g-n-s (class-get class *class-getters-n-setters-idx*)]
           [entry (assq slot-name g-n-s)])
      (unless entry
        (slot-missing class obj slot-name))
      (let ([access (cddr entry)])
        (let ([val (if (fixnum? access)
                       (instance-ref obj access)
                       ((car access) obj))])
          (if (unbound? val)
              (slot-unbound class obj slot-name)
              val)))))

  (define (slot-set! obj slot-name val)
    (let* ([class (class-of obj)]
           [g-n-s (class-get class *class-getters-n-setters-idx*)]
           [entry (assq slot-name g-n-s)])
      (unless entry
        (slot-missing class obj slot-name))
      (let ([access (cddr entry)])
        (if (fixnum? access)
            (instance-set! obj access val)
            ((cdr access) obj val)))))

  (define (slot-bound? obj slot-name)
    (let* ([class (class-of obj)]
           [g-n-s (class-get class *class-getters-n-setters-idx*)]
           [entry (assq slot-name g-n-s)])
      (if (not entry) #f
          (let ([access (cddr entry)])
            (not (unbound?
                   (if (fixnum? access)
                       (instance-ref obj access)
                       ((car access) obj))))))))

  (define (slot-exists? obj slot-name)
    (and (assq slot-name
               (class-get (class-of obj) *class-getters-n-setters-idx*))
         #t))

  (define (slot-value obj slot-name) (slot-ref obj slot-name))
  (define (slot-value-using-class class obj slot-name) (slot-ref obj slot-name))

  (define (slot-unbound class obj slot-name)
    (error 'slot-unbound "slot is unbound" slot-name (class-name class)))

  (define (slot-missing class obj slot-name)
    (error 'slot-missing "no such slot" slot-name (class-name class)))

  ;; =========================================================================
  ;; Slot accessor generation
  ;; =========================================================================

  (define *accessor-generics* (make-eq-hashtable))

  (define (ensure-accessor-generic name)
    (or (hashtable-ref *accessor-generics* name #f)
        (let ([gf (make-generic-function name 1)])
          (hashtable-set! *accessor-generics* name gf)
          gf)))

  (define (ensure-writer-generic name)
    (let ([wname (string->symbol
                   (string-append "set-" (symbol->string name) "!"))])
      (or (hashtable-ref *accessor-generics* wname #f)
          (let ([gf (make-generic-function wname 2)])
            (hashtable-set! *accessor-generics* wname gf)
            gf))))

  (define (compute-slot-accessors class slots)
    (for-each
      (lambda (s)
        (let ([name (slot-definition-name s)]
              [reader (slot-definition-reader s)]
              [writer (slot-definition-writer s)]
              [accessor (slot-definition-accessor s)])
          (when reader
            (let ([gf (ensure-accessor-generic reader)])
              (add-method! gf
                (make-method-obj gf (list class) '()
                  (lambda (obj) (slot-ref obj name))))))
          (when writer
            (let ([gf (ensure-writer-generic writer)])
              (add-method! gf
                (make-method-obj gf (list class <top>) '()
                  (lambda (obj val) (slot-set! obj name val))))))
          (when accessor
            (let ([gf-r (ensure-accessor-generic accessor)]
                  [gf-w (ensure-writer-generic accessor)])
              (add-method! gf-r
                (make-method-obj gf-r (list class) '()
                  (lambda (obj) (slot-ref obj name))))
              (add-method! gf-w
                (make-method-obj gf-w (list class <top>) '()
                  (lambda (obj val) (slot-set! obj name val))))))))
      slots))

  ;; =========================================================================
  ;; keyword-get, initialize
  ;; =========================================================================

  (define (keyword-get plist key default)
    (let loop ([p plist])
      (cond
        [(null? p) default]
        [(and (pair? p) (pair? (cdr p)) (eq? (car p) key))
         (cadr p)]
        [else (loop (if (pair? (cdr p)) (cddr p) '()))])))

  (define (initialize instance initargs)
    (let* ([class (class-of instance)]
           [g-n-s (class-get class *class-getters-n-setters-idx*)]
           [slots (class-get class *class-slots-idx*)])
      (for-each
        (lambda (slot-def)
          (let* ([name (slot-definition-name slot-def)]
                 [entry (assq name g-n-s)]
                 [initarg (slot-definition-initarg slot-def)]
                 [init-fn (and entry (cadr entry))]
                 [access (and entry (cddr entry))])
            (when access
              (let ([val (if initarg
                             (keyword-get initargs initarg *unbound*)
                             *unbound*)])
                (if (not (unbound? val))
                    (if (fixnum? access)
                        (instance-set! instance access val)
                        ((cdr access) instance val))
                    (when init-fn
                      (let ([default (init-fn instance)])
                        (if (fixnum? access)
                            (instance-set! instance access default)
                            ((cdr access) instance default)))))))))
        slots)))

  ;; =========================================================================
  ;; allocate-instance, make, make-instance
  ;; =========================================================================

  (define (allocate-instance class . initargs)
    (%allocate-instance class (class-get class *class-nfields-idx*)))

  (define (make-instance class . initargs)
    (let ([instance (allocate-instance class)])
      (initialize instance initargs)
      instance))

  ;; make as a macro: auto-quotes keyword symbols (e.g., :x becomes ':x)
  ;; so users can write (make <point> :x 10) in natural CLOS style.
  ;; Use make-instance for programmatic calls with runtime keyword lists.
  (define-syntax make
    (lambda (stx)
      (define (keyword-symbol? s)
        (and (symbol? s)
             (let ([str (symbol->string s)])
               (and (fx> (string-length str) 1)
                    (char=? (string-ref str 0) #\:)))))
      (syntax-case stx ()
        [(_ class arg ...)
         (with-syntax ([(qarg ...)
                        (map (lambda (a)
                               (let ([d (syntax->datum a)])
                                 (if (keyword-symbol? d)
                                     (datum->syntax a `',d)
                                     a)))
                             #'(arg ...))])
           #'(make-instance class qarg ...))])))

  ;; =========================================================================
  ;; make-class: programmatic class creation
  ;; =========================================================================

  (define (make-class name direct-supers direct-slots . opts)
    (let* ([supers (if (null? direct-supers) (list <object>) direct-supers)]
           [metaclass (keyword-get opts ':metaclass <class>)]
           [c (%allocate-instance metaclass *class-nslots*)])
      (class-put! c *class-name-idx* name)
      (class-put! c *class-direct-supers-idx* supers)
      (class-put! c *class-direct-subclasses-idx* '())
      (class-put! c *class-direct-slots-idx* direct-slots)
      (class-put! c *class-direct-methods-idx* '())
      (class-put! c *class-redefined-idx* #f)
      (class-put! c *class-cpl-idx* (compute-cpl c))
      (let ([all-slots (compute-slots c)])
        (class-put! c *class-slots-idx* all-slots)
        (class-put! c *class-nfields-idx* 0)
        (class-put! c *class-getters-n-setters-idx*
          (compute-getters-n-setters c all-slots)))
      (for-each
        (lambda (s)
          (class-put! s *class-direct-subclasses-idx*
            (cons c (class-get s *class-direct-subclasses-idx*))))
        supers)
      (compute-slot-accessors c direct-slots)
      (register-class! name c)
      c))

  (define (validate-superclass class superclass) #t)

  ;; =========================================================================
  ;; Layer 5: change-class, describe, clone
  ;; =========================================================================

  (define (slot-exists?-internal class obj name)
    (and (assq name (class-get class *class-getters-n-setters-idx*)) #t))

  (define (slot-bound?-internal class obj name)
    (let ([entry (assq name (class-get class *class-getters-n-setters-idx*))])
      (and entry
           (let ([access (cddr entry)])
             (not (unbound?
                    (if (fixnum? access)
                        (instance-ref obj access)
                        ((car access) obj))))))))

  (define (slot-ref-internal class obj name)
    (let* ([entry (assq name (class-get class *class-getters-n-setters-idx*))]
           [access (cddr entry)])
      (if (fixnum? access)
          (instance-ref obj access)
          ((car access) obj))))

  (define (slot-set!-internal class obj name val)
    (let* ([entry (assq name (class-get class *class-getters-n-setters-idx*))]
           [access (cddr entry)])
      (if (fixnum? access)
          (instance-set! obj access val)
          ((cdr access) obj val))))

  (define (change-class instance new-class)
    (let* ([old-class (class-of instance)]
           [new-instance (allocate-instance new-class)]
           [new-slots (class-get new-class *class-slots-idx*)])
      (for-each
        (lambda (slot-def)
          (let ([name (slot-definition-name slot-def)])
            (if (slot-exists?-internal old-class instance name)
                (when (slot-bound?-internal old-class instance name)
                  (slot-set!-internal new-class new-instance name
                    (slot-ref-internal old-class instance name)))
                (let* ([g-n-s (class-get new-class *class-getters-n-setters-idx*)]
                       [entry (assq name g-n-s)]
                       [init-fn (and entry (cadr entry))])
                  (when init-fn
                    (slot-set!-internal new-class new-instance name
                      (init-fn new-instance)))))))
        new-slots)
      new-instance))

  (define (describe obj)
    (let* ([class (class-of obj)]
           [name (class-name class)])
      (display (format "#<~a" name))
      (when (instance? obj)
        (for-each
          (lambda (slot-def)
            (let ([sname (slot-definition-name slot-def)])
              (display (format " ~a:" sname))
              (if (slot-bound? obj sname)
                  (display (format "~s" (slot-ref obj sname)))
                  (display "#<unbound>"))))
          (class-get class *class-slots-idx*)))
      (display ">")
      (newline)))

  (define (class-subclasses class)
    (let loop ([queue (class-direct-subclasses class)]
               [seen '()] [result '()])
      (if (null? queue)
          result
          (let ([c (car queue)])
            (if (memq c seen)
                (loop (cdr queue) seen result)
                (loop (append (cdr queue) (class-direct-subclasses c))
                      (cons c seen)
                      (cons c result)))))))

  (define (class-methods class)
    (apply append
      (map class-direct-methods
           (cons class (class-subclasses class)))))

  (define (shallow-clone obj)
    (let* ([class (class-of obj)]
           [clone (allocate-instance class)])
      (for-each
        (lambda (slot-def)
          (let ([name (slot-definition-name slot-def)])
            (when (slot-bound? obj name)
              (slot-set! clone name (slot-ref obj name)))))
        (class-get class *class-slots-idx*))
      clone))

  (define (deep-clone obj)
    (let* ([class (class-of obj)]
           [clone (allocate-instance class)])
      (for-each
        (lambda (slot-def)
          (let ([name (slot-definition-name slot-def)])
            (when (slot-bound? obj name)
              (let ([val (slot-ref obj name)])
                (slot-set! clone name
                  (if (instance? val) (deep-clone val) val))))))
        (class-get class *class-slots-idx*))
      clone))

  ;; =========================================================================
  ;; define-class, define-generic, define-method macros
  ;; =========================================================================

  ;; Options whose values are procedures and must be evaluated, not quoted.
  (define-syntax %eval-option?
    (syntax-rules ()
      [(_ k) (memq 'k '(:init-thunk :validator :observer :slot-ref :slot-set!))]))

  (define-syntax define-class
    (lambda (stx)
      ;; Transform a slot spec: quote data options, evaluate proc options.
      ;; (x :initarg :x :validator (lambda ...))
      ;;   => (list 'x ':initarg ':x ':validator (lambda ...))
      (define (transform-slot slot-stx)
        (syntax-case slot-stx ()
          [name
           (identifier? #'name)
           #''name]
          [(name opt ...)
           (with-syntax ([(transformed ...)
                          (transform-opts #'(opt ...))])
             #'(list 'name transformed ...))]))

      (define (transform-opts opts-stx)
        (syntax-case opts-stx ()
          [() '()]
          [(key val rest ...)
           (let* ([k (syntax->datum #'key)]
                  [proc-opt? (and (symbol? k)
                                  (memq k '(:init-thunk :validator :observer
                                            :slot-ref :slot-set!)))])
             (cons (datum->syntax #'key `',k)
                   (cons (if proc-opt? #'val #`'val)
                         (transform-opts #'(rest ...)))))]
          [(lone)
           (list #`'lone)]))

      (syntax-case stx ()
        [(_ name (super ...) (slot ...) option ...)
         (with-syntax ([(xslot ...) (map transform-slot #'(slot ...))])
           #'(define name
               (make-class 'name (list super ...) (list xslot ...) option ...)))]
        [(_ name (super ...) (slot ...))
         (with-syntax ([(xslot ...) (map transform-slot #'(slot ...))])
           #'(define name
               (make-class 'name (list super ...) (list xslot ...))))])))

  (define-syntax define-generic
    (lambda (stx)
      (syntax-case stx ()
        [(_ name)
         #'(define name
             (let ([gf (make-generic-function 'name #f)])
               (hashtable-set! *named-generics* 'name gf)
               (gf->procedure gf)))])))

  (define-syntax define-method
    (lambda (stx)
      (define (extract-formals params)
        (map (lambda (p)
               (syntax-case p ()
                 [(arg cls) #'arg]
                 [arg #'arg]))
             params))

      (define (extract-specializers params)
        (map (lambda (p)
               (syntax-case p ()
                 [(arg cls) #'cls]
                 [arg #'<top>]))
             params))

      ;; Use syntax->datum for qualifier matching — free-identifier=? fails
      ;; across lexical contexts for unbound keyword symbols like :before.
      (define (qualifier-keyword? x)
        (memq (syntax->datum x) '(:before :after :around)))

      (syntax-case stx ()
        [(_ (name qualifier param ...) body ...)
         (qualifier-keyword? #'qualifier)
         (with-syntax ([(formal ...) (extract-formals #'(param ...))]
                       [(spec ...) (extract-specializers #'(param ...))]
                       [qual-list (datum->syntax #'name
                                    (list (syntax->datum #'qualifier)))])
           #'(%add-method-to-gf! 'name (list spec ...) 'qual-list
               (lambda (formal ...) body ...)))]
        [(_ (name param ...) body ...)
         (with-syntax ([(formal ...) (extract-formals #'(param ...))]
                       [(spec ...) (extract-specializers #'(param ...))])
           #'(%add-method-to-gf! 'name (list spec ...) '()
               (lambda (formal ...) body ...)))])))

  ;; =========================================================================
  ;; BOOTSTRAP: Initialize the class hierarchy
  ;; =========================================================================
  ;; This runs once when the library is loaded. All define forms are above;
  ;; this section is purely expressions at the end of the library body.

  ;; Helper for primitive (built-in) classes
  (define (make-primitive-class! name supers)
    (let ([c (%allocate-instance (vector-ref *C* %class) *class-nslots*)])
      (class-put! c *class-name-idx* name)
      (class-put! c *class-direct-supers-idx* supers)
      (class-put! c *class-direct-subclasses-idx* '())
      (class-put! c *class-direct-slots-idx* '())
      (class-put! c *class-slots-idx* '())
      (class-put! c *class-nfields-idx* 0)
      (class-put! c *class-getters-n-setters-idx* '())
      (class-put! c *class-direct-methods-idx* '())
      (class-put! c *class-redefined-idx* #f)
      (class-put! c *class-cpl-idx*
        (cons c (apply append
                  (map (lambda (s) (class-get s *class-cpl-idx*)) supers))))
      (for-each (lambda (s)
                  (class-put! s *class-direct-subclasses-idx*
                    (cons c (class-get s *class-direct-subclasses-idx*))))
                supers)
      (register-class! name c)
      c))

  ;; --- Build core classes ---

  ;; <top>
  (let ([c (%allocate-instance #f *class-nslots*)])
    (class-put! c *class-name-idx* '<top>)
    (class-put! c *class-direct-supers-idx* '())
    (class-put! c *class-direct-subclasses-idx* '())
    (class-put! c *class-direct-slots-idx* '())
    (class-put! c *class-slots-idx* '())
    (class-put! c *class-nfields-idx* 0)
    (class-put! c *class-getters-n-setters-idx* '())
    (class-put! c *class-direct-methods-idx* '())
    (class-put! c *class-redefined-idx* #f)
    (class-put! c *class-cpl-idx* (list c))
    (vector-set! *C* %top c))

  ;; <object>
  (let ([c (%allocate-instance #f *class-nslots*)])
    (class-put! c *class-name-idx* '<object>)
    (class-put! c *class-direct-supers-idx* (list <top>))
    (class-put! c *class-direct-subclasses-idx* '())
    (class-put! c *class-direct-slots-idx* '())
    (class-put! c *class-slots-idx* '())
    (class-put! c *class-nfields-idx* 0)
    (class-put! c *class-getters-n-setters-idx* '())
    (class-put! c *class-direct-methods-idx* '())
    (class-put! c *class-redefined-idx* #f)
    (class-put! c *class-cpl-idx* (list c <top>))
    (vector-set! *C* %object c))

  ;; <class> (metaclass — its own class)
  (let ([c (%allocate-instance #f *class-nslots*)])
    (vector-set! c 1 c) ;; class-of <class> = <class>
    (class-put! c *class-name-idx* '<class>)
    (class-put! c *class-direct-supers-idx* (list <object>))
    (class-put! c *class-direct-subclasses-idx* '())
    (class-put! c *class-direct-slots-idx*
      '((name) (direct-superclasses) (direct-subclasses)
        (precedence-list) (direct-slots) (slots) (nfields)
        (getters-n-setters) (direct-methods) (redefined)))
    (class-put! c *class-slots-idx*
      '((name) (direct-superclasses) (direct-subclasses)
        (precedence-list) (direct-slots) (slots) (nfields)
        (getters-n-setters) (direct-methods) (redefined)))
    (class-put! c *class-nfields-idx* *class-nslots*)
    (class-put! c *class-getters-n-setters-idx*
      `((name               #f . ,*class-name-idx*)
        (direct-superclasses #f . ,*class-direct-supers-idx*)
        (direct-subclasses  #f . ,*class-direct-subclasses-idx*)
        (precedence-list    #f . ,*class-cpl-idx*)
        (direct-slots       #f . ,*class-direct-slots-idx*)
        (slots              #f . ,*class-slots-idx*)
        (nfields            #f . ,*class-nfields-idx*)
        (getters-n-setters  #f . ,*class-getters-n-setters-idx*)
        (direct-methods     #f . ,*class-direct-methods-idx*)
        (redefined          #f . ,*class-redefined-idx*)))
    (class-put! c *class-direct-methods-idx* '())
    (class-put! c *class-redefined-idx* #f)
    (class-put! c *class-cpl-idx* (list c <object> <top>))
    (vector-set! *C* %class c))

  ;; Fix parent-child links and class pointers
  (class-put! <top> *class-direct-subclasses-idx* (list <object>))
  (class-put! <object> *class-direct-subclasses-idx* (list <class>))
  (vector-set! <top> 1 <class>)
  (vector-set! <object> 1 <class>)
  (register-class! '<top> <top>)
  (register-class! '<object> <object>)
  (register-class! '<class> <class>)

  ;; <generic>
  (let ([c (%allocate-instance <class> *class-nslots*)])
    (class-put! c *class-name-idx* '<generic>)
    (class-put! c *class-direct-supers-idx* (list <object>))
    (class-put! c *class-direct-subclasses-idx* '())
    (class-put! c *class-direct-slots-idx*
      '((name) (methods) (arity) (method-combination) (cache)))
    (class-put! c *class-slots-idx*
      '((name) (methods) (arity) (method-combination) (cache)))
    (class-put! c *class-nfields-idx* *generic-nslots*)
    (class-put! c *class-getters-n-setters-idx*
      `((name               #f . ,*generic-name-idx*)
        (methods            #f . ,*generic-methods-idx*)
        (arity              #f . ,*generic-arity-idx*)
        (method-combination #f . ,*generic-combination-idx*)
        (cache              #f . ,*generic-cache-idx*)))
    (class-put! c *class-direct-methods-idx* '())
    (class-put! c *class-redefined-idx* #f)
    (class-put! c *class-cpl-idx* (list c <object> <top>))
    (class-put! <object> *class-direct-subclasses-idx*
      (cons c (class-get <object> *class-direct-subclasses-idx*)))
    (register-class! '<generic> c)
    (vector-set! *C* %generic c))

  ;; <method>
  (let ([c (%allocate-instance <class> *class-nslots*)])
    (class-put! c *class-name-idx* '<method>)
    (class-put! c *class-direct-supers-idx* (list <object>))
    (class-put! c *class-direct-subclasses-idx* '())
    (class-put! c *class-direct-slots-idx*
      '((generic-function) (specializers) (qualifiers) (procedure)))
    (class-put! c *class-slots-idx*
      '((generic-function) (specializers) (qualifiers) (procedure)))
    (class-put! c *class-nfields-idx* *method-nslots*)
    (class-put! c *class-getters-n-setters-idx*
      `((generic-function #f . ,*method-gf-idx*)
        (specializers     #f . ,*method-specializers-idx*)
        (qualifiers       #f . ,*method-qualifiers-idx*)
        (procedure        #f . ,*method-procedure-idx*)))
    (class-put! c *class-direct-methods-idx* '())
    (class-put! c *class-redefined-idx* #f)
    (class-put! c *class-cpl-idx* (list c <object> <top>))
    (class-put! <object> *class-direct-subclasses-idx*
      (cons c (class-get <object> *class-direct-subclasses-idx*)))
    (register-class! '<method> c)
    (vector-set! *C* %method c))

  ;; Built-in type classes
  (vector-set! *C* %boolean   (make-primitive-class! '<boolean>    (list <top>)))
  (vector-set! *C* %char      (make-primitive-class! '<char>       (list <top>)))
  (vector-set! *C* %null      (make-primitive-class! '<null>       (list <top>)))
  (vector-set! *C* %symbol    (make-primitive-class! '<symbol>     (list <top>)))
  (vector-set! *C* %keyword   (make-primitive-class! '<keyword>    (list <symbol>)))
  (vector-set! *C* %number    (make-primitive-class! '<number>     (list <top>)))
  (vector-set! *C* %complex   (make-primitive-class! '<complex>    (list <number>)))
  (vector-set! *C* %real      (make-primitive-class! '<real>       (list <complex>)))
  (vector-set! *C* %rational  (make-primitive-class! '<rational>   (list <real>)))
  (vector-set! *C* %integer   (make-primitive-class! '<integer>    (list <rational>)))
  (vector-set! *C* %string    (make-primitive-class! '<string>     (list <top>)))
  (vector-set! *C* %pair      (make-primitive-class! '<pair>       (list <top>)))
  (vector-set! *C* %list      (make-primitive-class! '<list>       (list <pair>)))
  (vector-set! *C* %vector    (make-primitive-class! '<vector>     (list <top>)))
  (vector-set! *C* %bytevec   (make-primitive-class! '<bytevector> (list <top>)))
  (vector-set! *C* %hashtable (make-primitive-class! '<hashtable>  (list <top>)))
  (vector-set! *C* %port      (make-primitive-class! '<port>       (list <top>)))
  (vector-set! *C* %inport    (make-primitive-class! '<input-port> (list <port>)))
  (vector-set! *C* %outport   (make-primitive-class! '<output-port>(list <port>)))
  (vector-set! *C* %procedure (make-primitive-class! '<procedure>  (list <top>)))
  (vector-set! *C* %condition (make-primitive-class! '<condition>  (list <top>)))
  (vector-set! *C* %record    (make-primitive-class! '<record>     (list <top>)))
  (vector-set! *C* %eof       (make-primitive-class! '<eof>        (list <top>)))
  (vector-set! *C* %void      (make-primitive-class! '<void>       (list <top>)))

) ;; end library
