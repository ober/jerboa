#!chezscheme
;;; (std os mmap) -- Memory-Mapped I/O
;;;
;;; Direct access to file contents as byte-addressable memory without copying.
;;; Wraps POSIX mmap(2)/munmap(2)/msync(2)/madvise(2).
;;;
;;; Usage:
;;;   (define mapping (mmap "large-file.dat" #:mode 'read-only))
;;;   (mmap-u64-ref mapping 0 'little)   ; read 8 bytes little-endian
;;;   (munmap mapping)                   ; release mapping
;;;
;;; The returned mmap region exposes byte-level access via foreign-ref/foreign-set!.
;;; mmap-bytevector returns a fresh bytevector copy of the mapped data.

(library (std os mmap)
  (export
    ;; Mapping creation
    mmap munmap msync madvise

    ;; Type predicate
    mmap-region? mmap-region-addr mmap-region-size mmap-region-mode

    ;; Byte-level access (O(1), no copying)
    mmap-u8-ref  mmap-u8-set!
    mmap-u16-ref mmap-u16-set!
    mmap-u32-ref mmap-u32-set!
    mmap-u64-ref mmap-u64-set!
    mmap-s8-ref  mmap-s16-ref mmap-s32-ref mmap-s64-ref

    ;; Copy to/from bytevector
    mmap->bytevector mmap-copy-in!

    ;; Constants
    PROT_READ PROT_WRITE PROT_EXEC
    MAP_SHARED MAP_PRIVATE MAP_ANONYMOUS
    MADV_SEQUENTIAL MADV_RANDOM MADV_WILLNEED MADV_DONTNEED
    MS_SYNC MS_ASYNC MS_INVALIDATE)

  (import (chezscheme))

  ;;; ========== POSIX constants ==========
  ;; Values for Linux x86-64. Adjust for other platforms.

  (define PROT_READ   1)
  (define PROT_WRITE  2)
  (define PROT_EXEC   4)
  (define PROT_NONE   0)

  (define MAP_SHARED    1)
  (define MAP_PRIVATE   2)
  (define MAP_ANONYMOUS #x20)
  (define MAP_FAILED    -1)   ; mmap returns (void*)-1 on failure

  (define MADV_SEQUENTIAL  2)
  (define MADV_RANDOM      1)
  (define MADV_WILLNEED    3)
  (define MADV_DONTNEED    4)

  (define MS_ASYNC      1)
  (define MS_SYNC       4)
  (define MS_INVALIDATE 2)

  ;;; ========== FFI declarations ==========

  ;; mmap(addr, length, prot, flags, fd, offset) -> void*
  ;; Returns -1 (as unsigned long) on failure, mapped address otherwise
  (define %mmap
    (foreign-procedure "mmap"
      (void* size_t int int int long)
      void*))

  ;; munmap(addr, length) -> int
  (define %munmap
    (foreign-procedure "munmap"
      (void* size_t)
      int))

  ;; msync(addr, length, flags) -> int
  (define %msync
    (foreign-procedure "msync"
      (void* size_t int)
      int))

  ;; madvise(addr, length, advice) -> int
  (define %madvise
    (foreign-procedure "madvise"
      (void* size_t int)
      int))

  ;; open(path, flags, mode) -> fd
  (define %open
    (foreign-procedure "open"
      (string int int)
      int))

  ;; close(fd) -> int
  (define %close
    (foreign-procedure "close"
      (int)
      int))

  ;; stat: just get file size via lseek
  (define %lseek
    (foreign-procedure "lseek"
      (int long int)
      long))

  (define O_RDONLY  0)
  (define O_RDWR    2)
  (define O_CREAT   #x40)
  (define O_TRUNC   #x200)
  (define SEEK_END  2)

  ;;; ========== mmap region record ==========
  (define-record-type mmap-region
    (fields addr    ; integer: the mapped address
            size    ; fixnum: mapping size in bytes
            mode    ; symbol: 'read-only or 'read-write
            fd))    ; integer: backing fd (-1 for anon)

  ;;; ========== Map a file ==========
  (define (mmap path . opts)
    (let* ([mode      (get-opt opts '#:mode 'read-only)]
           [size-opt  (get-opt opts '#:size #f)]
           [flags     (case mode
                        [(read-only)  (bitwise-ior O_RDONLY)]
                        [(read-write) (bitwise-ior O_RDWR)]
                        [else (error 'mmap "unknown mode" mode)])]
           [fd        (if (string? path)
                        (%open path flags #o644)
                        path)])  ; allow passing an fd
      (when (< fd 0)
        (error 'mmap "cannot open file" path))
      (let ([size (or size-opt
                      ;; Get file size via lseek
                      (let ([sz (%lseek fd 0 SEEK_END)])
                        (%lseek fd 0 0)  ; seek back to start
                        sz))])
        (when (<= size 0)
          (when (string? path) (%close fd))
          (error 'mmap "file is empty or size is zero" path))
        (let* ([prot  (case mode
                        [(read-only)  PROT_READ]
                        [(read-write) (bitwise-ior PROT_READ PROT_WRITE)])]
               [mflags MAP_SHARED]
               [addr  (%mmap 0 size prot mflags fd 0)])
          ;; mmap returns (void*)-1 on failure; as a Chez integer this is large
          (when (= addr (- (expt 2 64) 1))  ; MAP_FAILED = (void*)-1
            (when (string? path) (%close fd))
            (error 'mmap "mmap failed" path))
          (let ([region (make-mmap-region addr size mode
                          (if (string? path) fd -1))])
            ;; Register guardian for GC-based cleanup
            (register-mmap-guardian! region)
            region)))))

  ;; Anonymous mapping (not backed by a file)
  (define (mmap-anon size . opts)
    (let* ([mode   (get-opt opts '#:mode 'read-write)]
           [prot   (bitwise-ior PROT_READ PROT_WRITE)]
           [mflags (bitwise-ior MAP_PRIVATE MAP_ANONYMOUS)]
           [addr   (%mmap 0 size prot mflags -1 0)])
      (when (= addr (- (expt 2 64) 1))
        (error 'mmap-anon "anonymous mmap failed" size))
      (let ([region (make-mmap-region addr size mode -1)])
        (register-mmap-guardian! region)
        region)))

  ;;; ========== Unmap ==========
  (define (munmap region)
    (let* ([addr (mmap-region-addr region)]
           [size (mmap-region-size region)]
           [fd   (mmap-region-fd region)]
           [rc   (%munmap addr size)])
      (when (>= fd 0)
        (%close fd))
      (when (< rc 0)
        (error 'munmap "munmap failed"))))

  ;;; ========== Sync ==========
  (define (msync region . flags-opt)
    (let ([flags (if (pair? flags-opt) (car flags-opt) MS_SYNC)])
      (let ([rc (%msync (mmap-region-addr region)
                        (mmap-region-size region)
                        flags)])
        (when (< rc 0)
          (error 'msync "msync failed")))))

  ;;; ========== Advise kernel ==========
  (define (madvise region advice)
    (let ([advice-const
           (case advice
             [(sequential)  MADV_SEQUENTIAL]
             [(random)      MADV_RANDOM]
             [(willneed)    MADV_WILLNEED]
             [(dontneed)    MADV_DONTNEED]
             [else (if (fixnum? advice) advice
                       (error 'madvise "unknown advice" advice))])])
      (%madvise (mmap-region-addr region)
                (mmap-region-size region)
                advice-const)))

  ;;; ========== Byte-level access ==========

  (define (mmap-check-bounds region offset size who)
    (when (or (< offset 0)
              (> (+ offset size) (mmap-region-size region)))
      (error who "offset out of bounds" offset)))

  (define (mmap-u8-ref region offset)
    (mmap-check-bounds region offset 1 'mmap-u8-ref)
    (foreign-ref 'unsigned-8 (mmap-region-addr region) offset))

  (define (mmap-u8-set! region offset val)
    (mmap-check-bounds region offset 1 'mmap-u8-set!)
    (foreign-set! 'unsigned-8 (mmap-region-addr region) offset val))

  (define (mmap-s8-ref region offset)
    (mmap-check-bounds region offset 1 'mmap-s8-ref)
    (foreign-ref 'integer-8 (mmap-region-addr region) offset))

  (define (mmap-u16-ref region offset endianness)
    (mmap-check-bounds region offset 2 'mmap-u16-ref)
    (let* ([addr (+ (mmap-region-addr region) offset)]
           [b0   (foreign-ref 'unsigned-8 addr 0)]
           [b1   (foreign-ref 'unsigned-8 addr 1)])
      (case endianness
        [(little) (bitwise-ior b0 (bitwise-arithmetic-shift b1 8))]
        [(big)    (bitwise-ior (bitwise-arithmetic-shift b0 8) b1)]
        [else (error 'mmap-u16-ref "bad endianness" endianness)])))

  (define (mmap-u16-set! region offset val endianness)
    (mmap-check-bounds region offset 2 'mmap-u16-set!)
    (let ([addr (+ (mmap-region-addr region) offset)])
      (case endianness
        [(little)
         (foreign-set! 'unsigned-8 addr 0 (bitwise-and val #xff))
         (foreign-set! 'unsigned-8 addr 1 (bitwise-and (bitwise-arithmetic-shift val -8) #xff))]
        [(big)
         (foreign-set! 'unsigned-8 addr 0 (bitwise-and (bitwise-arithmetic-shift val -8) #xff))
         (foreign-set! 'unsigned-8 addr 1 (bitwise-and val #xff))])))

  (define (mmap-s16-ref region offset endianness)
    (let ([u (mmap-u16-ref region offset endianness)])
      (if (>= u #x8000) (- u #x10000) u)))

  ;; Native endianness detection (for fast-path direct loads)
  (define *native-endian*
    (if (eq? (native-endianness) (endianness little)) 'little 'big))

  (define (mmap-u32-ref region offset endianness)
    (mmap-check-bounds region offset 4 'mmap-u32-ref)
    (let ([addr (+ (mmap-region-addr region) offset)])
      (if (eq? endianness *native-endian*)
          ;; Fast path: single 32-bit load
          (foreign-ref 'unsigned-32 addr 0)
          ;; Slow path: byte-swap
          (let ([b0 (foreign-ref 'unsigned-8 addr 0)]
                [b1 (foreign-ref 'unsigned-8 addr 1)]
                [b2 (foreign-ref 'unsigned-8 addr 2)]
                [b3 (foreign-ref 'unsigned-8 addr 3)])
            (case endianness
              [(little)
               (bitwise-ior b0
                 (bitwise-arithmetic-shift b1 8)
                 (bitwise-arithmetic-shift b2 16)
                 (bitwise-arithmetic-shift b3 24))]
              [(big)
               (bitwise-ior (bitwise-arithmetic-shift b0 24)
                 (bitwise-arithmetic-shift b1 16)
                 (bitwise-arithmetic-shift b2 8)
                 b3)])))))

  (define (mmap-u32-set! region offset val endianness)
    (mmap-check-bounds region offset 4 'mmap-u32-set!)
    (let ([addr (+ (mmap-region-addr region) offset)])
      (if (eq? endianness *native-endian*)
          ;; Fast path: single 32-bit store
          (foreign-set! 'unsigned-32 addr 0 val)
          ;; Slow path: byte-swap
          (case endianness
            [(little)
             (foreign-set! 'unsigned-8 addr 0 (bitwise-and val #xff))
             (foreign-set! 'unsigned-8 addr 1 (bitwise-and (bitwise-arithmetic-shift val -8) #xff))
             (foreign-set! 'unsigned-8 addr 2 (bitwise-and (bitwise-arithmetic-shift val -16) #xff))
             (foreign-set! 'unsigned-8 addr 3 (bitwise-and (bitwise-arithmetic-shift val -24) #xff))]
            [(big)
             (foreign-set! 'unsigned-8 addr 0 (bitwise-and (bitwise-arithmetic-shift val -24) #xff))
             (foreign-set! 'unsigned-8 addr 1 (bitwise-and (bitwise-arithmetic-shift val -16) #xff))
             (foreign-set! 'unsigned-8 addr 2 (bitwise-and (bitwise-arithmetic-shift val -8) #xff))
             (foreign-set! 'unsigned-8 addr 3 (bitwise-and val #xff))]))))

  (define (mmap-s32-ref region offset endianness)
    (mmap-check-bounds region offset 4 'mmap-s32-ref)
    (let ([addr (+ (mmap-region-addr region) offset)])
      (if (eq? endianness *native-endian*)
          (foreign-ref 'integer-32 addr 0)
          (let ([u (mmap-u32-ref region offset endianness)])
            (if (>= u #x80000000) (- u #x100000000) u)))))

  (define (mmap-u64-ref region offset endianness)
    (mmap-check-bounds region offset 8 'mmap-u64-ref)
    (let ([addr (+ (mmap-region-addr region) offset)])
      (if (eq? endianness *native-endian*)
          ;; Fast path: single 64-bit load
          (foreign-ref 'unsigned-64 addr 0)
          ;; Slow path: assemble from two 32-bit reads
          (let* ([lo (mmap-u32-ref region offset endianness)]
                 [hi (mmap-u32-ref region (+ offset 4) endianness)])
            (case endianness
              [(little) (bitwise-ior lo (bitwise-arithmetic-shift hi 32))]
              [(big)    (bitwise-ior (bitwise-arithmetic-shift lo 32) hi)])))))

  (define (mmap-u64-set! region offset val endianness)
    (mmap-check-bounds region offset 8 'mmap-u64-set!)
    (let ([addr (+ (mmap-region-addr region) offset)])
      (if (eq? endianness *native-endian*)
          ;; Fast path: single 64-bit store
          (foreign-set! 'unsigned-64 addr 0 val)
          ;; Slow path: split into two 32-bit writes
          (case endianness
            [(little)
             (mmap-u32-set! region offset (bitwise-and val #xffffffff) 'little)
             (mmap-u32-set! region (+ offset 4) (bitwise-arithmetic-shift val -32) 'little)]
            [(big)
             (mmap-u32-set! region offset (bitwise-arithmetic-shift val -32) 'big)
             (mmap-u32-set! region (+ offset 4) (bitwise-and val #xffffffff) 'big)]))))

  (define (mmap-s64-ref region offset endianness)
    (mmap-check-bounds region offset 8 'mmap-s64-ref)
    (let ([addr (+ (mmap-region-addr region) offset)])
      (if (eq? endianness *native-endian*)
          (foreign-ref 'integer-64 addr 0)
          (let ([u (mmap-u64-ref region offset endianness)])
            (if (>= u (expt 2 63)) (- u (expt 2 64)) u)))))

  ;;; ========== Copy to/from bytevector ==========

  (define (mmap->bytevector region . range-opt)
    (let* ([start (if (pair? range-opt) (car range-opt) 0)]
           [end   (if (and (pair? range-opt) (pair? (cdr range-opt)))
                    (cadr range-opt)
                    (mmap-region-size region))]
           [len   (- end start)]
           [bv    (make-bytevector len)])
      (do ([i 0 (+ i 1)])
          ((= i len) bv)
        (bytevector-u8-set! bv i (mmap-u8-ref region (+ start i))))))

  (define (mmap-copy-in! region bv . offset-opt)
    (let ([offset (if (pair? offset-opt) (car offset-opt) 0)]
          [len    (bytevector-length bv)])
      (do ([i 0 (+ i 1)])
          ((= i len))
        (mmap-u8-set! region (+ offset i) (bytevector-u8-ref bv i)))))

  ;;; ========== GC-based cleanup ==========
  (define *mmap-guardian* (make-guardian))

  (define (register-mmap-guardian! region)
    (*mmap-guardian* region))

  ;; Poll the guardian periodically (call from REPL or background thread)
  (define (collect-dead-mmaps!)
    (let loop ([region (*mmap-guardian*)])
      (when region
        (let* ([addr (mmap-region-addr region)]
               [size (mmap-region-size region)]
               [fd   (mmap-region-fd region)])
          (%munmap addr size)
          (when (>= fd 0) (%close fd)))
        (loop (*mmap-guardian*)))))

  ;;; ========== Helpers ==========
  ;; Match keyword args by symbol name (not identity) to work across libraries.
  ;; #:mode creates gensyms; we compare the underlying name string.
  (define (sym-name=? a b)
    (and (symbol? a) (symbol? b)
         (string=? (symbol->string a) (symbol->string b))))

  (define (get-opt opts key default)
    (let loop ([opts opts])
      (cond
        [(null? opts) default]
        [(and (pair? opts) (pair? (cdr opts)) (sym-name=? (car opts) key))
         (cadr opts)]
        [else (loop (if (pair? opts) (cdr opts) '()))])))

) ;; end library
