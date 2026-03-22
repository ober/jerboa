# Protocol Libraries

Binary protocol encoding/decoding libraries for network and data interchange formats.

## Table of Contents

- [9P2000 Filesystem Protocol](#9p2000-filesystem-protocol-std-net-9p)
  - [Overview](#9p-overview)
  - [Import](#9p-import)
  - [Wire Format](#9p-wire-format)
  - [Message Type Constants](#message-type-constants)
  - [Qid Records](#qid-records)
  - [Stat Records](#stat-records)
  - [Message Constructors](#message-constructors)
  - [Message Accessors](#message-accessors)
  - [Encoding and Decoding](#encoding-and-decoding)
  - [Usage Examples](#9p-usage-examples)
- [MessagePack Serialization](#messagepack-serialization-std-text-msgpack)
  - [Overview](#msgpack-overview)
  - [Import](#msgpack-import)
  - [Type Mappings](#type-mappings)
  - [API Reference](#msgpack-api-reference)
  - [Usage Examples](#msgpack-usage-examples)

---

## 9P2000 Filesystem Protocol `(std net 9p)`

### 9P Overview

Pure encoding/decoding of 9P2000 wire-format messages as defined by the Plan 9 operating system. This library works entirely with bytevectors and performs no network I/O. You construct typed message records, encode them to bytevectors for transmission, and decode received bytevectors back into message records.

**Source:** `lib/std/net/9p.sls`

### 9P Import

```scheme
(import (std net 9p))
```

### 9P Wire Format

Every 9P2000 message on the wire has this layout:

```
[4-byte LE size][1-byte type][2-byte LE tag][fields...]
```

- **size** includes itself (the entire message length including the 4 size bytes).
- **tag** is a 16-bit identifier that pairs requests with responses.
- Strings within fields are encoded as `[2-byte LE length][UTF-8 bytes]`.

### Message Type Constants

Each constant is an exact integer matching the 9P2000 specification.

| Constant | Value | Description |
|---|---|---|
| `p9-type-tversion` | 100 | Client version negotiation |
| `p9-type-rversion` | 101 | Server version reply |
| `p9-type-tauth` | 102 | Client authentication request |
| `p9-type-rauth` | 103 | Server authentication reply |
| `p9-type-tattach` | 104 | Client attach to filesystem |
| `p9-type-rattach` | 105 | Server attach reply |
| `p9-type-rerror` | 107 | Server error reply |
| `p9-type-twalk` | 110 | Client walk path elements |
| `p9-type-rwalk` | 111 | Server walk reply |
| `p9-type-topen` | 112 | Client open file |
| `p9-type-ropen` | 113 | Server open reply |
| `p9-type-tcreate` | 114 | Client create file |
| `p9-type-rcreate` | 115 | Server create reply |
| `p9-type-tread` | 116 | Client read data |
| `p9-type-rread` | 117 | Server read reply |
| `p9-type-twrite` | 118 | Client write data |
| `p9-type-rwrite` | 119 | Server write reply |
| `p9-type-tclunk` | 120 | Client close fid |
| `p9-type-rclunk` | 121 | Server close reply |
| `p9-type-tstat` | 124 | Client stat request |
| `p9-type-rstat` | 125 | Server stat reply |

### Qid Records

A qid is a 13-byte server-unique file identifier containing a type byte, a version number, and a unique path.

| Procedure | Signature | Description |
|---|---|---|
| `make-p9-qid` | `(type version path) -> qid` | Create a qid. `type` is a byte (e.g., `#x80` for directory), `version` is a 32-bit integer, `path` is a 64-bit integer. |
| `p9-qid?` | `(x) -> boolean` | Test if `x` is a qid record. |
| `p9-qid-type` | `(qid) -> integer` | Qid type byte. |
| `p9-qid-version` | `(qid) -> integer` | Qid version (32-bit). |
| `p9-qid-path` | `(qid) -> integer` | Qid unique path (64-bit). |

### Stat Records

A stat record describes file metadata.

| Procedure | Signature | Description |
|---|---|---|
| `make-p9-stat` | `(type dev qid mode atime mtime length name uid gid muid) -> stat` | Create a stat record with all fields. |
| `p9-stat?` | `(x) -> boolean` | Test if `x` is a stat record. |
| `p9-stat-type` | `(stat) -> integer` | Kernel server type (16-bit). |
| `p9-stat-dev` | `(stat) -> integer` | Kernel server subtype (32-bit). |
| `p9-stat-qid` | `(stat) -> qid` | Unique file identifier. |
| `p9-stat-mode` | `(stat) -> integer` | Permissions and flags (32-bit). |
| `p9-stat-atime` | `(stat) -> integer` | Last access time (Unix epoch, 32-bit). |
| `p9-stat-mtime` | `(stat) -> integer` | Last modification time (Unix epoch, 32-bit). |
| `p9-stat-length` | `(stat) -> integer` | File length in bytes (64-bit). |
| `p9-stat-name` | `(stat) -> string` | File name (final path element). |
| `p9-stat-uid` | `(stat) -> string` | Owner name. |
| `p9-stat-gid` | `(stat) -> string` | Group name. |
| `p9-stat-muid` | `(stat) -> string` | Name of user who last modified the file. |

### Message Constructors

Every constructor takes `tag` as the first argument (a 16-bit integer pairing requests with responses).

| Constructor | Arguments | Description |
|---|---|---|
| `make-p9-tversion` | `tag msize version` | Version negotiation. `msize` is max message size (u32), `version` is a string (e.g., `"9P2000"`). |
| `make-p9-rversion` | `tag msize version` | Server version reply. |
| `make-p9-tauth` | `tag afid uname aname` | Authentication request. `afid` (u32) is the auth fid, `uname`/`aname` are strings. |
| `make-p9-rauth` | `tag aqid` | Auth reply with the authentication qid. |
| `make-p9-tattach` | `tag fid afid uname aname` | Attach to root. `fid` (u32) is the new root fid, `afid` is auth fid (`#xFFFFFFFF` for no auth). |
| `make-p9-rattach` | `tag qid` | Attach reply with the root qid. |
| `make-p9-rerror` | `tag ename` | Error reply. `ename` is an error message string. |
| `make-p9-twalk` | `tag fid newfid wnames` | Walk path. `fid` is starting fid, `newfid` is the cloned fid, `wnames` is a list of path element strings. |
| `make-p9-rwalk` | `tag qids` | Walk reply. `qids` is a list of qid records, one per successfully walked element. |
| `make-p9-topen` | `tag fid mode` | Open a fid. `mode` is a byte (0=read, 1=write, 2=rdwr, 16=trunc). |
| `make-p9-ropen` | `tag qid iounit` | Open reply. `iounit` (u32) is the max atomic I/O size (0 means use msize). |
| `make-p9-tcreate` | `tag fid name perm mode` | Create a file in directory `fid`. `name` is the file name, `perm` (u32) is permissions, `mode` is open mode. |
| `make-p9-rcreate` | `tag qid iounit` | Create reply. |
| `make-p9-tread` | `tag fid offset count` | Read `count` (u32) bytes at `offset` (u64) from `fid`. |
| `make-p9-rread` | `tag data` | Read reply. `data` is a bytevector. |
| `make-p9-twrite` | `tag fid offset data` | Write `data` (bytevector) at `offset` (u64) to `fid`. |
| `make-p9-rwrite` | `tag count` | Write reply. `count` (u32) is bytes actually written. |
| `make-p9-tclunk` | `tag fid` | Close a fid. |
| `make-p9-rclunk` | `tag` | Clunk reply (no fields beyond tag). |
| `make-p9-tstat` | `tag fid` | Request file metadata. |
| `make-p9-rstat` | `tag stat` | Stat reply. `stat` is a `p9-stat` record. |

### Message Accessors

All message records carry a tag. Use these generic accessors on any message:

| Procedure | Signature | Description |
|---|---|---|
| `p9-message-type` | `(msg) -> integer` | Returns the type constant for any message record. |
| `p9-message-tag` | `(msg) -> integer` | Returns the tag for any message record. |

Per-message field accessors follow the naming pattern `p9-<type>-rec-<field>`:

| Accessor | Returns |
|---|---|
| `p9-tversion-rec-msize`, `p9-tversion-rec-version` | integer, string |
| `p9-rversion-rec-msize`, `p9-rversion-rec-version` | integer, string |
| `p9-tauth-rec-afid`, `p9-tauth-rec-uname`, `p9-tauth-rec-aname` | integer, string, string |
| `p9-rauth-rec-aqid` | qid |
| `p9-tattach-rec-fid`, `p9-tattach-rec-afid`, `p9-tattach-rec-uname`, `p9-tattach-rec-aname` | integer, integer, string, string |
| `p9-rattach-rec-qid` | qid |
| `p9-rerror-rec-ename` | string |
| `p9-twalk-rec-fid`, `p9-twalk-rec-newfid`, `p9-twalk-rec-wnames` | integer, integer, list of strings |
| `p9-rwalk-rec-qids` | list of qids |
| `p9-topen-rec-fid`, `p9-topen-rec-mode` | integer, integer |
| `p9-ropen-rec-qid`, `p9-ropen-rec-iounit` | qid, integer |
| `p9-tcreate-rec-fid`, `p9-tcreate-rec-name`, `p9-tcreate-rec-perm`, `p9-tcreate-rec-mode` | integer, string, integer, integer |
| `p9-rcreate-rec-qid`, `p9-rcreate-rec-iounit` | qid, integer |
| `p9-tread-rec-fid`, `p9-tread-rec-offset`, `p9-tread-rec-count` | integer, integer, integer |
| `p9-rread-rec-data` | bytevector |
| `p9-twrite-rec-fid`, `p9-twrite-rec-offset`, `p9-twrite-rec-data` | integer, integer, bytevector |
| `p9-rwrite-rec-count` | integer |
| `p9-tclunk-rec-fid` | integer |
| `p9-tstat-rec-fid` | integer |
| `p9-rstat-rec-stat` | stat |

### Encoding and Decoding

| Procedure | Signature | Description |
|---|---|---|
| `p9-encode` | `(msg) -> bytevector` | Encode a message record to a complete 9P2000 wire-format bytevector (including the 4-byte size header). |
| `p9-decode` | `(bv) -> msg` | Decode a bytevector into a typed message record. Raises an error if the bytevector is shorter than 7 bytes or contains an unknown message type. |

### 9P Usage Examples

#### Version negotiation (client side)

```scheme
(import (std net 9p))

;; Build a Tversion message: tag=0, max message size 8192, version "9P2000"
(define tv (make-p9-tversion 0 8192 "9P2000"))

;; Encode to wire format for sending
(define wire (p9-encode tv))
;; wire is a bytevector ready to write to a socket

;; Suppose we receive an Rversion bytevector from the server:
(define reply (p9-decode wire))
(p9-message-type reply)          ;=> 100 (p9-type-tversion)
(p9-tversion-rec-msize reply)    ;=> 8192
(p9-tversion-rec-version reply)  ;=> "9P2000"
```

#### Attach to a filesystem

```scheme
(import (std net 9p))

;; Attach with fid=1, no auth (afid=#xFFFFFFFF), user "glenda", aname ""
(define attach-msg (make-p9-tattach 1 1 #xFFFFFFFF "glenda" ""))
(define attach-wire (p9-encode attach-msg))

;; After receiving the server reply:
;; (define reply (p9-decode received-bv))
;; (p9-rattach-rec-qid reply)  ; root directory qid
```

#### Walk, open, and read a file

```scheme
(import (std net 9p))

;; Walk from root fid=1 to newfid=2 through path elements
(define walk (make-p9-twalk 2 1 2 '("usr" "glenda" "profile")))
(define walk-wire (p9-encode walk))

;; Open the walked fid for reading (mode=0)
(define open-msg (make-p9-topen 3 2 0))
(define open-wire (p9-encode open-msg))

;; Read 4096 bytes at offset 0
(define read-msg (make-p9-tread 4 2 0 4096))
(define read-wire (p9-encode read-msg))

;; Close the fid when done
(define clunk-msg (make-p9-tclunk 5 2))
(define clunk-wire (p9-encode clunk-msg))
```

#### Building a stat reply (server side)

```scheme
(import (std net 9p))

(define qid (make-p9-qid #x80 0 42))  ; directory, version 0, path 42
(define st (make-p9-stat
             0        ; type
             0        ; dev
             qid      ; qid
             #o755    ; mode (directory + rwxr-xr-x)
             1700000000  ; atime
             1700000000  ; mtime
             0        ; length (directories have length 0)
             "mydir"  ; name
             "glenda" ; uid
             "glenda" ; gid
             "glenda" ; muid
             ))

(define rstat-msg (make-p9-rstat 6 st))
(define rstat-wire (p9-encode rstat-msg))
```

#### Round-trip encode/decode

```scheme
(import (std net 9p))

(define msg (make-p9-rerror 99 "file not found"))
(define decoded (p9-decode (p9-encode msg)))
(p9-rerror-rec-ename decoded)  ;=> "file not found"
(p9-message-tag decoded)       ;=> 99
```

---

## MessagePack Serialization `(std text msgpack)`

### Msgpack Overview

Encode and decode values using the [MessagePack](https://msgpack.org) binary serialization format. Supports the full msgpack type system: nil, booleans, integers (arbitrary precision within 64-bit signed/unsigned range), IEEE 754 doubles, UTF-8 strings, binary data, arrays, and maps. Integer encoding automatically selects the most compact representation.

**Source:** `lib/std/text/msgpack.sls`

### Msgpack Import

```scheme
(import (std text msgpack))
```

### Type Mappings

| MessagePack Type | Scheme Type | Notes |
|---|---|---|
| nil | `(void)` or `'()` | Both `(void)` and the empty list encode as nil. |
| boolean | `#t` / `#f` | |
| integer | exact integer | Signed range: -2^63 to 2^63-1. Unsigned range: 0 to 2^64-1. Auto-compact encoding. |
| float 64 | flonum | Always encodes as 64-bit double. |
| str | string | UTF-8 encoded on the wire. |
| bin | bytevector | |
| array | vector | |
| map | alist | List of `(key . value)` pairs. A list is treated as a map only if its car is a pair (alist detection). |
| ext | bytevector | Extension types are decoded as raw bytevectors (type byte is discarded). |
| float 32 | flonum | Decoded to a Scheme flonum (only encountered when decoding; encoding always uses float 64). |

### Msgpack API Reference

| Procedure | Signature | Description |
|---|---|---|
| `msgpack-pack` | `(val) -> bytevector` | Encode a Scheme value to a MessagePack bytevector. Raises an error for unsupported types. |
| `msgpack-unpack` | `(bv) -> value` | Decode a MessagePack bytevector to a Scheme value. Raises an error on unexpected EOF or unknown format bytes. |
| `msgpack-pack-port` | `(val port) -> void` | Encode a value and write directly to a binary output port. Useful for streaming or writing multiple values to the same port. |
| `msgpack-unpack-port` | `(port) -> value` | Read and decode one MessagePack value from a binary input port. Call repeatedly to decode a stream of concatenated values. |

### Msgpack Usage Examples

#### Basic round-trip

```scheme
(import (std text msgpack))

;; Integers
(msgpack-unpack (msgpack-pack 42))      ;=> 42
(msgpack-unpack (msgpack-pack -1))      ;=> -1
(msgpack-unpack (msgpack-pack 100000))  ;=> 100000

;; Strings
(msgpack-unpack (msgpack-pack "hello"))  ;=> "hello"

;; Booleans
(msgpack-unpack (msgpack-pack #t))  ;=> #t
(msgpack-unpack (msgpack-pack #f))  ;=> #f

;; Nil
(msgpack-unpack (msgpack-pack (void)))  ;=> (void)

;; Floats
(msgpack-unpack (msgpack-pack 3.14))  ;=> 3.14
```

#### Arrays (vectors)

```scheme
(import (std text msgpack))

(define v (vector 1 "two" 3.0 #t))
(define packed (msgpack-pack v))
(msgpack-unpack packed)  ;=> #(1 "two" 3.0 #t)

;; Nested arrays
(msgpack-unpack (msgpack-pack (vector (vector 1 2) (vector 3 4))))
;=> #(#(1 2) #(3 4))
```

#### Maps (alists)

```scheme
(import (std text msgpack))

(define data '(("name" . "alice") ("age" . 30) ("active" . #t)))
(define packed (msgpack-pack data))
(define decoded (msgpack-unpack packed))
decoded  ;=> (("name" . "alice") ("age" . 30) ("active" . #t))

;; Nested maps
(define nested '(("user" . (("name" . "bob") ("id" . 7)))))
(msgpack-unpack (msgpack-pack nested))
;=> (("user" . (("name" . "bob") ("id" . 7))))
```

#### Binary data

```scheme
(import (std text msgpack))

(define blob (bytevector 0 1 2 255 254 253))
(define packed (msgpack-pack blob))
(msgpack-unpack packed)  ;=> #vu8(0 1 2 255 254 253)
```

#### Streaming with ports

```scheme
(import (std text msgpack))

;; Write multiple values to a port
(let-values ([(port extract) (open-bytevector-output-port)])
  (msgpack-pack-port 1 port)
  (msgpack-pack-port "hello" port)
  (msgpack-pack-port (vector 10 20) port)
  (let* ([bv (extract)]
         [in (open-bytevector-input-port bv)])
    (list
      (msgpack-unpack-port in)    ;=> 1
      (msgpack-unpack-port in)    ;=> "hello"
      (msgpack-unpack-port in)))) ;=> #(10 20)
;=> (1 "hello" #(10 20))
```

#### Integer encoding compactness

The encoder automatically picks the smallest representation:

```scheme
(import (std text msgpack))

;; Positive fixint (1 byte for 0-127)
(bytevector-length (msgpack-pack 0))    ;=> 1
(bytevector-length (msgpack-pack 127))  ;=> 1

;; Negative fixint (1 byte for -32 to -1)
(bytevector-length (msgpack-pack -1))   ;=> 1
(bytevector-length (msgpack-pack -32))  ;=> 1

;; uint8 (2 bytes for 128-255)
(bytevector-length (msgpack-pack 200))  ;=> 2

;; uint16 (3 bytes for 256-65535)
(bytevector-length (msgpack-pack 1000)) ;=> 3
```

#### Interoperability

MessagePack is a cross-language format. Bytevectors produced by `msgpack-pack` are compatible with any MessagePack implementation (Python, Go, Rust, JavaScript, etc.) and vice versa.

```scheme
(import (std text msgpack))

;; Encode a structure for sending over the network
(define request
  (msgpack-pack
    '(("method" . "getUser")
      ("params" . #(42))
      ("id" . 1))))

;; request is a compact bytevector ready for transmission
(bytevector-length request)  ; much smaller than equivalent JSON
```
