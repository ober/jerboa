#!chezscheme
;;; (std odb) -- Persistent Object Database
;;;
;;; A ManarDB-inspired persistent object store built on CLOS and mmap.
;;; Each persistent class gets its own mmap'd file. Objects are fixed-size
;;; records stored sequentially. Slot access goes through mmap for zero-copy
;;; persistence.
;;;
;;; Architecture:
;;;   - Each persistent class has a "type tag" (small integer) and a backing file
;;;   - An mptr (managed pointer) = (type-tag . byte-offset) identifies an object
;;;   - Slots are 8-byte aligned: s64, f64, or mptr (tagged pointer to another object)
;;;   - The persistent metaclass intercepts slot-ref/slot-set! to read/write mmap
;;;   - doclass iterates all live objects of a class
;;;   - Transactions are optional (single-writer model via flock)
;;;
;;; Usage:
;;;   (odb-open "/tmp/mydb")
;;;   (define-persistent-class <point> ()
;;;     ((x :type :s64 :initform 0)
;;;      (y :type :s64 :initform 0)))
;;;   (with-odb-transaction
;;;     (define p (make <point> :x 10 :y 20)))
;;;   (doclass (obj <point>) (display (slot-ref obj 'x)))
;;;   (odb-close)

(library (std odb)
  (export
    ;; Store lifecycle
    odb-open odb-close odb-sync
    odb-root odb-root-set!

    ;; Persistent class definition
    define-persistent-class

    ;; Slot types
    :s64 :f64 :mptr :string

    ;; Object operations
    odb-make odb-slot-ref odb-slot-set!
    odb-delete odb-proxy?
    mptr? mptr-null? mptr->object

    ;; Iteration & query
    doclass odb-count odb-find odb-filter

    ;; Transactions
    with-odb-transaction

    ;; Schema
    odb-class-info odb-migrate

    ;; Internals for MOP integration
    *odb* odb?
    register-persistent-class!
    persistent-class-tag persistent-class-region
    persistent-class-record-size persistent-class-slot-layout)

  (import (chezscheme)
          (std clos)
          (std os mmap)
          (std os flock))

  ;; Ensure libc is loaded for FFI (mmap, ftruncate, etc.)
  (define _libc (load-shared-object "libc.so.6"))

  ;; =========================================================================
  ;; Constants
  ;; =========================================================================

  (define *endian* 'little)      ;; Native endianness for mmap access
  (define *slot-size* 8)         ;; All slots are 8 bytes (s64/f64/mptr)
  (define *header-size* 64)      ;; Per-file header: magic, version, count, record-size
  (define *magic* #x4F444231)    ;; "ODB1" as u32
  (define *version* 1)
  (define *initial-capacity* 256) ;; Initial objects per region file
  (define *deleted-marker* #xDEAD) ;; Mark deleted objects in status field

  ;; =========================================================================
  ;; Slot type tags
  ;; =========================================================================

  (define :s64    's64)
  (define :f64    'f64)
  (define :mptr   'mptr)
  (define :string 'string)

  ;; =========================================================================
  ;; ODB store record
  ;; =========================================================================

  (define-record-type (%odb make-odb odb?)
    (fields
      (immutable path %odb-path)
      (mutable classes %odb-classes %odb-classes-set!)
      (mutable next-tag %odb-next-tag %odb-next-tag-set!)
      (mutable open? %odb-open? %odb-open?-set!)
      (mutable lock-fd %odb-lock-fd %odb-lock-fd-set!)
      (mutable root-mptr %odb-root %odb-root-set!)
      (mutable dirty? %odb-dirty? %odb-dirty?-set!))
    (protocol
      (lambda (new)
        (lambda (path)
          (new path (make-eq-hashtable) 1 #f #f 0 #f)))))

  ;; Global current store
  (define *odb* (make-parameter #f))

  ;; =========================================================================
  ;; Persistent class info
  ;; =========================================================================
  ;; Tracks per-class metadata for the mmap storage layer.

  (define-record-type persistent-class-info
    (fields
      (immutable tag)                ;; Integer type tag (1, 2, 3, ...)
      (immutable name)               ;; Symbol: class name
      (mutable slot-names)            ;; List of slot name symbols
      (mutable slot-types)            ;; List of slot type symbols (s64, f64, mptr)
      (mutable slot-offsets)          ;; Hashtable: slot-name -> byte offset within record
      (mutable record-size)           ;; Bytes per object record (including status word)
      (mutable region)               ;; mmap-region or #f
      (mutable count)                ;; Number of live objects
      (mutable capacity)             ;; Max objects before grow
      (mutable file-path)            ;; Backing file path
      (mutable clos-class)))         ;; The CLOS class object

  ;; =========================================================================
  ;; Tagged pointer (mptr)
  ;; =========================================================================
  ;; An mptr is a 64-bit integer: high 16 bits = type tag, low 48 bits = byte offset.
  ;; mptr 0 = null.

  (define *mptr-tag-bits* 16)
  (define *mptr-offset-mask* (- (expt 2 48) 1))

  (define (make-mptr tag offset)
    (bitwise-ior (bitwise-arithmetic-shift tag 48) offset))

  (define (mptr-tag ptr)
    (bitwise-arithmetic-shift-right ptr 48))

  (define (mptr-offset ptr)
    (bitwise-and ptr *mptr-offset-mask*))

  (define (mptr? v) (and (integer? v) (exact? v) (> v 0)))
  (define (mptr-null? v) (eqv? v 0))

  ;; =========================================================================
  ;; File header layout (64 bytes)
  ;; =========================================================================
  ;; Offset 0:  u32 magic ("ODB1")
  ;; Offset 4:  u32 version
  ;; Offset 8:  u64 object count
  ;; Offset 16: u32 record size
  ;; Offset 20: u32 type tag
  ;; Offset 24: u64 root mptr (only in tag-1 file)
  ;; Offset 32-63: reserved

  (define (write-header! region count record-size tag root-mptr)
    (mmap-u32-set! region 0  *magic* *endian*)
    (mmap-u32-set! region 4  *version* *endian*)
    (mmap-u64-set! region 8  count *endian*)
    (mmap-u32-set! region 16 record-size *endian*)
    (mmap-u32-set! region 20 tag *endian*)
    (mmap-u64-set! region 24 (or root-mptr 0) *endian*))

  (define (read-header region)
    (let ([magic   (mmap-u32-ref region 0 *endian*)]
          [version (mmap-u32-ref region 4 *endian*)]
          [count   (mmap-u64-ref region 8 *endian*)]
          [rec-sz  (mmap-u32-ref region 16 *endian*)]
          [tag     (mmap-u32-ref region 20 *endian*)]
          [root    (mmap-u64-ref region 24 *endian*)])
      (unless (= magic *magic*)
        (error 'read-header "bad magic number — not an ODB file"))
      (values version count rec-sz tag root)))

  ;; =========================================================================
  ;; Store lifecycle
  ;; =========================================================================

  ;; open(2) and ftruncate(2) FFI for creating/growing backing files
  (define %c-open
    (foreign-procedure "open" (string int int) int))
  (define %c-close
    (foreign-procedure "close" (int) int))
  (define %c-ftruncate
    (foreign-procedure "ftruncate" (int long) int))
  (define %c-mkdir
    (foreign-procedure "mkdir" (string int) int))
  (define %c-access
    (foreign-procedure "access" (string int) int))

  (define (ensure-directory path)
    (when (< (%c-access path 0) 0)
      (let ([rc (%c-mkdir path #o755)])
        (when (< rc 0)
          (error 'odb-open "cannot create directory" path)))))

  (define (odb-open path)
    (ensure-directory path)
    (let ([store (make-odb path)])
      ;; Lock the directory
      (let* ([lock-path (string-append path "/odb.lock")]
             [fd (%c-open lock-path
                          (bitwise-ior #x40 #x2) ;; O_CREAT | O_RDWR
                          #o644)])
        (when (< fd 0)
          (error 'odb-open "cannot create lock file" lock-path))
        (flock-exclusive fd)
        (%odb-lock-fd-set! store fd))
      (%odb-open?-set! store #t)
      ;; Scan for existing class files
      (scan-existing-files! store)
      (*odb* store)
      store))

  (define (odb-close . opts)
    (let ([store (or (and (pair? opts) (car opts)) (*odb*))])
      (unless store (error 'odb-close "no open store"))
      (when (%odb-dirty? store) (odb-sync store))
      ;; Unmap all regions
      (let-values ([(keys vals) (hashtable-entries (%odb-classes store))])
        (vector-for-each
          (lambda (info)
            (when (persistent-class-info-region info)
              (munmap (persistent-class-info-region info))
              (persistent-class-info-region-set! info #f)))
          vals))
      ;; Release lock
      (when (%odb-lock-fd store)
        (flock-unlock (%odb-lock-fd store))
        (%c-close (%odb-lock-fd store))
        (%odb-lock-fd-set! store #f))
      (%odb-open?-set! store #f)
      (when (eq? (*odb*) store) (*odb* #f))))

  (define (odb-sync . opts)
    (let ([store (or (and (pair? opts) (car opts)) (*odb*))])
      (unless store (error 'odb-sync "no open store"))
      (let-values ([(keys vals) (hashtable-entries (%odb-classes store))])
        (vector-for-each
          (lambda (info)
            (when (persistent-class-info-region info)
              ;; Update header count
              (mmap-u64-set! (persistent-class-info-region info) 8
                             (persistent-class-info-count info) *endian*)
              ;; Write root mptr to tag-1 file
              (when (= (persistent-class-info-tag info) 1)
                (mmap-u64-set! (persistent-class-info-region info) 24
                               (or (%odb-root store) 0) *endian*))
              (msync (persistent-class-info-region info))))
          vals))
      (%odb-dirty?-set! store #f)))

  (define (odb-root . opts)
    (let ([store (or (and (pair? opts) (car opts)) (*odb*))])
      (and store (%odb-root store))))

  (define (odb-root-set! mptr . opts)
    (let ([store (or (and (pair? opts) (car opts)) (*odb*))])
      (unless store (error 'odb-root-set! "no open store"))
      (%odb-root-set! store mptr)
      (%odb-dirty?-set! store #t)))

  ;; =========================================================================
  ;; Scan existing backing files on open
  ;; =========================================================================

  (define (scan-existing-files! store)
    (let ([path (%odb-path store)])
      (guard (e [#t (void)])  ;; If directory listing fails, just start fresh
        (let ([entries (directory-list path)])
          (for-each
            (lambda (entry)
              (when (and (> (string-length entry) 4)
                         (string=? (substring entry (- (string-length entry) 4)
                                              (string-length entry))
                                   ".odb"))
                ;; Found a .odb file — open and read header
                (let* ([file-path (string-append path "/" entry)]
                       [region (mmap file-path '#:mode 'read-write)])
                  (guard (e [#t (munmap region)])
                    (let-values ([(ver count rec-sz tag root) (read-header region)])
                      ;; Extract class name from filename (strip .odb)
                      (let ([name (string->symbol
                                    (substring entry 0
                                              (- (string-length entry) 4)))])
                        ;; Reconstruct class info (slot layout unknown until class is defined)
                        (let ([info (make-persistent-class-info
                                      tag name '() '()
                                      (make-eq-hashtable) rec-sz
                                      region count
                                      (quotient (- (mmap-region-size region)
                                                   *header-size*)
                                                rec-sz)
                                      file-path #f)])
                          (hashtable-set! (%odb-classes store) name info)
                          (when (> tag (%odb-next-tag store))
                            (%odb-next-tag-set! store (+ tag 1)))
                          (when (and root (> root 0))
                            (%odb-root-set! store root)))))))))
            entries)))))

  ;; =========================================================================
  ;; Persistent class registration
  ;; =========================================================================

  (define (compute-slot-layout slot-specs)
    ;; slot-specs: list of (name :type <type> ...) or (name) -> default s64
    ;; Returns: (values slot-names slot-types slot-offsets record-size)
    ;; Record layout: [status:8] [slot0:8] [slot1:8] ...
    (let ([offsets (make-eq-hashtable)])
      (let loop ([specs slot-specs] [names '()] [types '()] [off 8])
        (if (null? specs)
            (values (reverse names) (reverse types) offsets off)
            (let* ([spec (car specs)]
                   [name (if (pair? spec) (car spec) spec)]
                   [type (if (pair? spec)
                             (slot-opt-raw (cdr spec) ':type :s64)
                             :s64)])
              (hashtable-set! offsets name off)
              (loop (cdr specs)
                    (cons name names)
                    (cons (normalize-type type) types)
                    (+ off *slot-size*)))))))

  (define (sym-name=? a b)
    (and (symbol? a) (symbol? b)
         (string=? (symbol->string a) (symbol->string b))))

  (define (slot-opt-raw opts key default)
    (let loop ([o opts])
      (cond
        [(null? o) default]
        [(and (pair? o) (pair? (cdr o)) (sym-name=? (car o) key))
         (cadr o)]
        [else (loop (if (pair? (cdr o)) (cddr o) '()))])))

  ;; Normalize a slot type symbol: :s64 -> s64, :f64 -> f64, etc.
  ;; Handles both keyword-prefixed (:s64) and plain (s64) forms.
  (define (normalize-type t)
    (let ([s (symbol->string t)])
      (if (and (> (string-length s) 1) (char=? (string-ref s 0) #\:))
          (string->symbol (substring s 1 (string-length s)))
          t)))

  (define (register-persistent-class! name slot-specs clos-class)
    (let ([store (*odb*)])
      (unless store (error 'register-persistent-class! "no open store"))
      (let-values ([(slot-names slot-types slot-offsets record-size)
                    (compute-slot-layout slot-specs)])
        ;; Check if already registered (reopen case)
        (let ([existing (hashtable-ref (%odb-classes store) name #f)])
          (if existing
              ;; Update existing info with CLOS class and slot metadata
              (begin
                (persistent-class-info-clos-class-set! existing clos-class)
                (persistent-class-info-slot-names-set! existing slot-names)
                (persistent-class-info-slot-types-set! existing slot-types)
                (persistent-class-info-slot-offsets-set! existing slot-offsets)
                (persistent-class-info-record-size-set! existing record-size)
                existing)
              ;; Create new
              (let* ([tag (%odb-next-tag store)]
                     [_ (%odb-next-tag-set! store (+ tag 1))]
                     [file-path (string-append (%odb-path store) "/"
                                               (symbol->string name) ".odb")]
                     [file-size (+ *header-size*
                                   (* *initial-capacity* record-size))]
                     [info (make-persistent-class-info
                             tag name slot-names slot-types
                             slot-offsets record-size
                             #f 0 *initial-capacity* file-path
                             clos-class)])
                ;; Create backing file
                (create-backing-file! file-path file-size)
                ;; Memory-map it
                (let ([region (mmap file-path '#:mode 'read-write)])
                  (persistent-class-info-region-set! info region)
                  ;; Write header
                  (write-header! region 0 record-size tag 0))
                (hashtable-set! (%odb-classes store) name info)
                (void)))))))

  (define (create-backing-file! path size)
    (let ([fd (%c-open path
                       (bitwise-ior #x42 #x200)  ;; O_CREAT | O_RDWR | O_TRUNC
                       #o644)])
      (when (< fd 0)
        (error 'create-backing-file! "cannot create file" path))
      (let ([rc (%c-ftruncate fd size)])
        (%c-close fd)
        (when (< rc 0)
          (error 'create-backing-file! "ftruncate failed" path)))))

  ;; =========================================================================
  ;; Region growing
  ;; =========================================================================

  (define (grow-region! info)
    (let* ([old-region (persistent-class-info-region info)]
           [old-cap (persistent-class-info-capacity info)]
           [new-cap (* old-cap 2)]
           [rec-sz (persistent-class-info-record-size info)]
           [new-size (+ *header-size* (* new-cap rec-sz))]
           [path (persistent-class-info-file-path info)])
      ;; Sync and unmap old region
      (msync old-region)
      (munmap old-region)
      ;; Grow file
      (let ([fd (%c-open path #x2 #o644)])  ;; O_RDWR
        (when (< fd 0)
          (error 'grow-region! "cannot open file" path))
        (%c-ftruncate fd new-size)
        (%c-close fd))
      ;; Remap
      (let ([new-region (mmap path '#:mode 'read-write)])
        (persistent-class-info-region-set! info new-region)
        (persistent-class-info-capacity-set! info new-cap))))

  ;; =========================================================================
  ;; Object allocation
  ;; =========================================================================

  (define (odb-allocate info)
    ;; Returns byte offset of the new record within the region
    (when (>= (persistent-class-info-count info)
              (persistent-class-info-capacity info))
      (grow-region! info))
    (let* ([idx (persistent-class-info-count info)]
           [rec-sz (persistent-class-info-record-size info)]
           [offset (+ *header-size* (* idx rec-sz))])
      (persistent-class-info-count-set! info (+ idx 1))
      ;; Write status word = 1 (live)
      (mmap-u64-set! (persistent-class-info-region info)
                     offset 1 *endian*)
      offset))

  ;; =========================================================================
  ;; Slot access: read/write 8-byte values from mmap
  ;; =========================================================================

  (define (odb-slot-ref-raw region offset slot-offset type)
    (let ([addr (+ offset slot-offset)])
      (case type
        [(s64)    (mmap-s64-ref region addr *endian*)]
        [(f64)    (let ([bits (mmap-u64-ref region addr *endian*)])
                    (bytevector-ieee-double-ref
                      (let ([bv (make-bytevector 8)])
                        (bytevector-u64-set! bv 0 bits (endianness little))
                        bv)
                      0 (endianness little)))]
        [(mptr)   (mmap-u64-ref region addr *endian*)]
        [(string) ;; String stored as length-prefixed UTF-8 at a separate offset
                  ;; For now: store as s64 index into a string table, or inline
                  ;; Simplified: store string hash/id — real impl would need string region
                  (mmap-s64-ref region addr *endian*)]
        [else (error 'odb-slot-ref-raw "unknown slot type" type)])))

  (define (odb-slot-set!-raw region offset slot-offset type value)
    (let ([addr (+ offset slot-offset)])
      (case type
        [(s64)    (mmap-u64-set! region addr value *endian*)]
        [(f64)    (let ([bv (make-bytevector 8)])
                    (bytevector-ieee-double-set! bv 0 value (endianness little))
                    (mmap-u64-set! region addr
                                   (bytevector-u64-ref bv 0 (endianness little))
                                   *endian*))]
        [(mptr)   (mmap-u64-set! region addr (or value 0) *endian*)]
        [(string) (mmap-u64-set! region addr (or value 0) *endian*)]
        [else (error 'odb-slot-set!-raw "unknown slot type" type)])))

  ;; =========================================================================
  ;; Persistent object proxy
  ;; =========================================================================
  ;; A persistent object in Scheme is a lightweight proxy: (tag . offset).
  ;; It references data in the mmap region, not heap memory.

  ;; Persistent objects are CLOS instances with hidden %odb-tag, %odb-offset, %odb-store slots.
  ;; These accessors extract the proxy info from any persistent CLOS object.

  (define (odb-proxy? obj)
    (and (instance? obj)
         (slot-exists? obj '%odb-tag)
         (slot-bound? obj '%odb-tag)
         (not (not (slot-ref obj '%odb-tag)))))

  (define (odb-proxy-tag obj)    (slot-ref obj '%odb-tag))
  (define (odb-proxy-offset obj) (slot-ref obj '%odb-offset))
  (define (odb-proxy-store obj)  (slot-ref obj '%odb-store))

  ;; Create a CLOS persistent object wrapper from raw mmap data
  (define (make-persistent-proxy tag offset store)
    (let* ([info (tag->info store tag)]
           [clos-class (and info (persistent-class-info-clos-class info))])
      (if clos-class
          (let ([obj (allocate-instance clos-class)])
            (slot-set! obj '%odb-tag tag)
            (slot-set! obj '%odb-offset offset)
            (slot-set! obj '%odb-store store)
            obj)
          ;; Fallback: class not yet defined (pre-registration scan)
          ;; Use a simple vector as placeholder
          (vector 'odb-proxy tag offset store))))

  (define (proxy->info proxy)
    (let ([store (odb-proxy-store proxy)])
      (let-values ([(keys vals) (hashtable-entries (%odb-classes store))])
        (let loop ([i 0])
          (if (>= i (vector-length vals))
              (error 'proxy->info "unknown type tag" (odb-proxy-tag proxy))
              (if (= (persistent-class-info-tag (vector-ref vals i))
                     (odb-proxy-tag proxy))
                  (vector-ref vals i)
                  (loop (+ i 1))))))))

  ;; Fast tag->info lookup cache
  (define *tag->info* (make-eqv-hashtable))

  (define (tag->info store tag)
    (or (hashtable-ref *tag->info* tag #f)
        (let-values ([(keys vals) (hashtable-entries (%odb-classes store))])
          (let loop ([i 0])
            (if (>= i (vector-length vals)) #f
                (let ([info (vector-ref vals i)])
                  (if (= (persistent-class-info-tag info) tag)
                      (begin (hashtable-set! *tag->info* tag info) info)
                      (loop (+ i 1)))))))))

  ;; =========================================================================
  ;; High-level slot access
  ;; =========================================================================

  (define (odb-slot-ref proxy slot-name)
    (let* ([info (proxy->info proxy)]
           [region (persistent-class-info-region info)]
           [offset (odb-proxy-offset proxy)]
           [slot-off (hashtable-ref (persistent-class-info-slot-offsets info)
                                    slot-name #f)]
           [slot-idx (list-index slot-name (persistent-class-info-slot-names info))]
           [type (and slot-idx (list-ref (persistent-class-info-slot-types info)
                                         slot-idx))])
      (unless slot-off
        (error 'odb-slot-ref "no such slot" slot-name
               (persistent-class-info-name info)))
      (let ([raw (odb-slot-ref-raw region offset slot-off type)])
        ;; For mptr types, return a proxy
        (if (and (eq? type 'mptr) (> raw 0))
            (make-persistent-proxy (mptr-tag raw) (mptr-offset raw)
                            (odb-proxy-store proxy))
            raw))))

  (define (odb-slot-set! proxy slot-name value)
    (let* ([info (proxy->info proxy)]
           [region (persistent-class-info-region info)]
           [offset (odb-proxy-offset proxy)]
           [slot-off (hashtable-ref (persistent-class-info-slot-offsets info)
                                    slot-name #f)]
           [slot-idx (list-index slot-name (persistent-class-info-slot-names info))]
           [type (and slot-idx (list-ref (persistent-class-info-slot-types info)
                                         slot-idx))])
      (unless slot-off
        (error 'odb-slot-set! "no such slot" slot-name
               (persistent-class-info-name info)))
      ;; Convert proxy values to mptrs
      (let ([raw (if (and (eq? type 'mptr) (odb-proxy? value))
                     (make-mptr (odb-proxy-tag value) (odb-proxy-offset value))
                     value)])
        (odb-slot-set!-raw region offset slot-off type raw)
        (let ([store (odb-proxy-store proxy)])
          (%odb-dirty?-set! store #t)))))

  (define (list-index item lst)
    (let loop ([l lst] [i 0])
      (cond [(null? l) #f]
            [(eq? (car l) item) i]
            [else (loop (cdr l) (+ i 1))])))

  ;; =========================================================================
  ;; Object creation
  ;; =========================================================================

  (define (%odb-make-proc class-or-name . initargs)
    (let* ([store (*odb*)]
           [_ (unless store (error 'odb-make "no open store"))]
           [clos-class (if (symbol? class-or-name)
                           (let ([info (hashtable-ref (%odb-classes store)
                                                      class-or-name #f)])
                             (and info (persistent-class-info-clos-class info)))
                           class-or-name)]
           [cname (if (symbol? class-or-name)
                      class-or-name
                      (class-name class-or-name))]
           [info (hashtable-ref (%odb-classes store) cname #f)]
           [_ (unless info (error 'odb-make "unknown persistent class" cname))]
           [offset (odb-allocate info)]
           ;; Create a CLOS instance with hidden proxy slots
           [obj (allocate-instance clos-class)])
      ;; Set hidden proxy slots
      (slot-set! obj '%odb-tag (persistent-class-info-tag info))
      (slot-set! obj '%odb-offset offset)
      (slot-set! obj '%odb-store store)
      ;; Apply initargs to persistent slots
      (let loop ([args initargs])
        (when (and (pair? args) (pair? (cdr args)))
          (let* ([key (car args)]
                 [val (cadr args)]
                 [slot-name (keyword->slot-name key)])
            (when slot-name
              (odb-slot-set! obj slot-name val)))
          (loop (cddr args))))
      (%odb-dirty?-set! store #t)
      obj))

  (define (keyword->slot-name key)
    ;; :x -> x, ':x -> x
    (cond
      [(symbol? key)
       (let ([s (symbol->string key)])
         (if (and (> (string-length s) 1)
                  (char=? (string-ref s 0) #\:))
             (string->symbol (substring s 1 (string-length s)))
             key))]
      [else #f]))

  ;; odb-make macro: auto-quotes keyword symbols like :x
  (define-syntax odb-make
    (lambda (stx)
      (define (keyword-symbol? s)
        (and (symbol? s)
             (let ([str (symbol->string s)])
               (and (fx> (string-length str) 1)
                    (char=? (string-ref str 0) #\:)))))
      (syntax-case stx ()
        [(_ class-name arg ...)
         (with-syntax ([(qarg ...)
                        (map (lambda (a)
                               (let ([d (syntax->datum a)])
                                 (if (keyword-symbol? d)
                                     (datum->syntax a `',d)
                                     a)))
                             #'(arg ...))])
           #'(%odb-make-proc class-name qarg ...))])))

  ;; =========================================================================
  ;; Object deletion
  ;; =========================================================================

  (define (odb-delete proxy)
    (let* ([info (proxy->info proxy)]
           [region (persistent-class-info-region info)]
           [offset (odb-proxy-offset proxy)])
      ;; Set status word to deleted marker
      (mmap-u64-set! region offset *deleted-marker* *endian*)
      (%odb-dirty?-set!(odb-proxy-store proxy) #t)))

  (define (odb-object-live? region offset)
    (= (mmap-u64-ref region offset *endian*) 1))

  ;; =========================================================================
  ;; mptr conversion
  ;; =========================================================================

  (define (mptr->object mptr-val . opts)
    (let ([store (or (and (pair? opts) (car opts)) (*odb*))])
      (if (or (not mptr-val) (= mptr-val 0))
          #f
          (make-persistent-proxy (mptr-tag mptr-val) (mptr-offset mptr-val) store))))

  ;; =========================================================================
  ;; Iteration: doclass
  ;; =========================================================================

  (define-syntax doclass
    (syntax-rules ()
      [(_ (var class-name) body ...)
       (doclass-proc 'class-name
         (lambda (var) body ...))]
      [(_ (var class-name result) body ...)
       (let ([acc result])
         (doclass-proc 'class-name
           (lambda (var) body ...))
         acc)]))

  (define (doclass-proc class-name proc)
    (let* ([store (*odb*)]
           [_ (unless store (error 'doclass "no open store"))]
           [info (hashtable-ref (%odb-classes store) class-name #f)]
           [_ (unless info (error 'doclass "unknown persistent class" class-name))])
      (let ([region (persistent-class-info-region info)]
            [count (persistent-class-info-count info)]
            [rec-sz (persistent-class-info-record-size info)]
            [tag (persistent-class-info-tag info)])
        (let loop ([i 0])
          (when (< i count)
            (let ([offset (+ *header-size* (* i rec-sz))])
              (when (odb-object-live? region offset)
                (proc (make-persistent-proxy tag offset store))))
            (loop (+ i 1)))))))

  ;; =========================================================================
  ;; Query helpers
  ;; =========================================================================

  (define (odb-count class-name)
    (let* ([store (*odb*)]
           [info (hashtable-ref (%odb-classes store) class-name #f)])
      (if info
          (let ([region (persistent-class-info-region info)]
                [count (persistent-class-info-count info)]
                [rec-sz (persistent-class-info-record-size info)])
            (let loop ([i 0] [n 0])
              (if (>= i count) n
                  (let ([offset (+ *header-size* (* i rec-sz))])
                    (loop (+ i 1)
                          (if (odb-object-live? region offset) (+ n 1) n))))))
          0)))

  (define (odb-find class-name pred)
    ;; Returns first matching proxy or #f
    (let* ([store (*odb*)]
           [info (hashtable-ref (%odb-classes store) class-name #f)])
      (and info
           (let ([region (persistent-class-info-region info)]
                 [count (persistent-class-info-count info)]
                 [rec-sz (persistent-class-info-record-size info)]
                 [tag (persistent-class-info-tag info)])
             (let loop ([i 0])
               (if (>= i count) #f
                   (let ([offset (+ *header-size* (* i rec-sz))])
                     (if (odb-object-live? region offset)
                         (let ([proxy (make-persistent-proxy tag offset store)])
                           (if (pred proxy) proxy (loop (+ i 1))))
                         (loop (+ i 1))))))))))

  (define (odb-filter class-name pred)
    ;; Returns list of all matching proxies
    (let ([result '()])
      (doclass-proc class-name
        (lambda (proxy)
          (when (pred proxy)
            (set! result (cons proxy result)))))
      (reverse result)))

  ;; =========================================================================
  ;; Transactions (simplified: flock-based single-writer)
  ;; =========================================================================

  (define *in-transaction* (make-parameter #f))

  (define-syntax with-odb-transaction
    (syntax-rules ()
      [(_ body ...)
       (let ([store (*odb*)])
         (unless store (error 'with-odb-transaction "no open store"))
         (dynamic-wind
           (lambda ()
             (unless (*in-transaction*)
               (*in-transaction* #t)))
           (lambda ()
             body ...
             (odb-sync store))
           (lambda ()
             (*in-transaction* #f))))]))

  ;; =========================================================================
  ;; Schema info & migration
  ;; =========================================================================

  (define (odb-class-info class-name)
    (let ([store (*odb*)])
      (and store
           (let ([info (hashtable-ref (%odb-classes store) class-name #f)])
             (and info
                  `((tag . ,(persistent-class-info-tag info))
                    (slots . ,(persistent-class-info-slot-names info))
                    (types . ,(persistent-class-info-slot-types info))
                    (record-size . ,(persistent-class-info-record-size info))
                    (count . ,(persistent-class-info-count info))
                    (capacity . ,(persistent-class-info-capacity info))))))))

  (define (odb-migrate old-proxy new-class-name slot-mapper)
    ;; Migrate a single object to a new class.
    ;; slot-mapper: (lambda (slot-name old-proxy) -> value) for each slot in new class.
    (let* ([store (*odb*)]
           [new-info (hashtable-ref (%odb-classes store) new-class-name #f)])
      (unless new-info
        (error 'odb-migrate "target class not found" new-class-name))
      (let* ([new-proxy (%odb-make-proc new-class-name)]
             [new-slots (persistent-class-info-slot-names new-info)])
        ;; Set each slot in the new object using the mapper
        (for-each
          (lambda (slot-name)
            (let ([val (slot-mapper slot-name old-proxy)])
              (odb-slot-set! new-proxy slot-name val)))
          new-slots)
        ;; Delete old object
        (odb-delete old-proxy)
        new-proxy)))

  ;; =========================================================================
  ;; CLOS-integrated persistent class macro
  ;; =========================================================================

  (define (persistent-class-tag class-name)
    (let ([info (and (*odb*) (hashtable-ref (%odb-classes(*odb*)) class-name #f))])
      (and info (persistent-class-info-tag info))))

  (define (persistent-class-region class-name)
    (let ([info (and (*odb*) (hashtable-ref (%odb-classes(*odb*)) class-name #f))])
      (and info (persistent-class-info-region info))))

  (define (persistent-class-record-size class-name)
    (let ([info (and (*odb*) (hashtable-ref (%odb-classes(*odb*)) class-name #f))])
      (and info (persistent-class-info-record-size info))))

  (define (persistent-class-slot-layout class-name)
    (let ([info (and (*odb*) (hashtable-ref (%odb-classes(*odb*)) class-name #f))])
      (and info (list (persistent-class-info-slot-names info)
                      (persistent-class-info-slot-types info)))))

  ;; =========================================================================
  ;; define-persistent-class
  ;; =========================================================================
  ;; Creates a CLOS class with :virtual allocation that routes slot access
  ;; through the ODB mmap layer. Also registers the class with the store.
  ;;
  ;; Usage:
  ;;   (define-persistent-class <point> ()
  ;;     ((x :type :s64 :initform 0)
  ;;      (y :type :s64 :initform 0)))

  (define-syntax define-persistent-class
    (lambda (stx)
      ;; Inline plist lookup — needed at expansion time (can't call runtime fns)
      (define (plist-get opts key default)
        (let loop ([o opts])
          (cond
            [(null? o) default]
            [(and (pair? o) (pair? (cdr o))
                  (symbol? (car o)) (symbol? key)
                  (string=? (symbol->string (car o)) (symbol->string key)))
             (cadr o)]
            [else (loop (if (pair? (cdr o)) (cddr o) '()))])))

      (define (parse-slot-spec spec-stx)
        ;; Returns: (name type initform-or-#f)
        (syntax-case spec-stx ()
          [(name opts ...)
           (let* ([opts-datum (map syntax->datum (syntax->list #'(opts ...)))]
                  [type (plist-get opts-datum ':type 's64)]
                  [initform (plist-get opts-datum ':initform #f)])
             (values (syntax->datum #'name) type initform))]
          [name
           (identifier? #'name)
           (values (syntax->datum #'name) 's64 #f)]))

      (syntax-case stx ()
        [(_ class-name (super ...) (slot-spec ...))
         (let* ([cname (syntax->datum #'class-name)]
                [slot-data
                 (map (lambda (s)
                        (let-values ([(name type initform) (parse-slot-spec s)])
                          (list name type initform)))
                      (syntax->list #'(slot-spec ...)))]
                [slot-names (map car slot-data)]
                [slot-types (map cadr slot-data)])
           (with-syntax
             ([(sname ...) (map (lambda (s) (datum->syntax #'class-name (car s)))
                                slot-data)]
              [(stype ...) (map (lambda (s) (datum->syntax #'class-name (cadr s)))
                                slot-data)]
              [raw-slot-specs
               (datum->syntax #'class-name
                 (map (lambda (s)
                        (let ([spec (syntax->datum s)])
                          (if (pair? spec) spec (list spec))))
                      (syntax->list #'(slot-spec ...))))]
              ;; Build CLOS slot specs: hidden proxy slots + virtual user slots
              [(clos-slot ...)
               (append
                 ;; Hidden slots for proxy data (regular instance allocation)
                 (map (lambda (n)
                        (datum->syntax #'class-name n))
                      '((%odb-tag :initform #f)
                        (%odb-offset :initform #f)
                        (%odb-store :initform #f)))
                 ;; User-defined slots with virtual allocation
                 (map (lambda (sd)
                        (let ([name (car sd)]
                              [initform (caddr sd)])
                          (datum->syntax #'class-name
                            (append
                              (list name
                                    ':allocation ':virtual
                                    ':slot-ref
                                    `(lambda (obj)
                                       (odb-slot-ref obj ',name))
                                    ':slot-set!
                                    `(lambda (obj val)
                                       (odb-slot-set! obj ',name val)))
                              (if initform
                                  (list ':initform initform)
                                  '())))))
                      slot-data))])
             #'(begin
                 ;; Define the CLOS class
                 (define-class class-name (super ...)
                   (clos-slot ...))
                 ;; Register with ODB store (if open)
                 (when (*odb*)
                   (register-persistent-class!
                     'class-name
                     'raw-slot-specs
                     class-name)))))])))

  ;; =========================================================================
  ;; Root mptr helpers (re-export to avoid name collision)
  ;; =========================================================================
  ;; The odb record already has root/root-set! fields.
  ;; The exported odb-root/odb-root-set! access those.
  ;; (Already defined above via the record)

) ;; end library
