# Jerboa API Index

_Auto-generated from `jerboa-mcp/api-signatures.json` (2026-04-22). 626 modules, 12393 unique symbols, 18925 total exports._

> **Authoritative.** If a symbol does not appear in the index below, it is not exported by any Jerboa library and any reference is a hallucination. This index is parsed directly from `.sls` source files on every regeneration.

## Contents

- [1. Prelude exports](#1-prelude-exports)
- [2. Where is X? (symbol → modules)](#2-where-is-x-symbol--modules)
- [3. Module catalog](#3-module-catalog)

## 1. Prelude exports

Importing `(jerboa prelude)` gives you 438 bindings. Everything listed here is available with no further import.

<details><summary>Full list</summary>

```
*method-tables*          *struct-types*           ->
->>                      ->>?                     ->?
1+                       1-                       :
<...>                    <>                       ContractViolation
Error                    acons                    add-watch!
aget                     agetq                    agetv
aif                      alist                    alist->hash-table
alist->plist*            alist?                   alists->csv
and-then                 any                      append-map
append1                  arem                     arem!
aremq                    aremq!                   aremv
aremv!                   as->                     aset
aset!                    asetq                    asetq!
asetv                    asetv!                   assert!
assoc-in                 assoc-in!                atom
atom-deref               atom-reset!              atom-swap!
atom-update!             atom?                    awhen
begin-ffi                bind-method!             butlast
c-declare                c-lambda                 call-method
call-with-list-builder   capture                  catch
chain                    chain-and                comp
compare-and-set!         complement               compose
compose1                 cond->                   cond->>
conjoin                  constantly               cpu-count
csv->alists              csv-port->rows           curry
curryn                   cut                      cute
date->string             datetime->alist          datetime->epoch
datetime->iso8601        datetime->julian         datetime->string
datetime-add             datetime-clamp           datetime-day
datetime-diff            datetime-floor-day       datetime-floor-hour
datetime-floor-month     datetime-hour            datetime-max
datetime-min             datetime-minute          datetime-month
datetime-nanosecond      datetime-now             datetime-offset
datetime-second          datetime-subtract        datetime-truncate
datetime-utc-now         datetime-year            datetime<=?
datetime<?               datetime=?               datetime>=?
datetime>?               datetime?                day-of-week
day-of-year              days-in-month            def
def*                     defclass                 define-active-pattern
define-c-lambda          define-enum              define-match-type
define-rx                define-sealed-hierarchy  define-values
defmethod                defn                     defrecord
defrule                  defrules                 defstruct
delete-duplicates/hash   deref                    directory-exists?
disjoin                  displayln                distinct
dotimes                  drop                     drop-last
drop-until               drop-while               duplicates
duration                 duration-nanoseconds     duration-seconds
duration?                epoch->datetime          eprintf
eql?                     err                      err->list
err?                     error-irritants          error-message
error-trace              every                    every-consecutive?
every-pred               filter-err               filter-map
filter-ok                finally                  first-and-only
flatten                  flatten-result           flatten1
flip                     fnil                     for
for-each!                for/and                  for/collect
for/fold                 for/or                   force-output
format                   fprintf                  frequencies
get-in                   group-by                 group-consecutive
group-n-consecutive      group-same               hash->list
hash->plist              hash-clear!              hash-copy
hash-eq-literal          hash-find                hash-fold
hash-for-each            hash-get                 hash-has-key?
hash-key?                hash-keys                hash-length
hash-literal             hash-map                 hash-merge
hash-merge!              hash-put!                hash-ref
hash-remove!             hash-set                 hash-table-set!
hash-table?              hash-update!             hash-values
identity                 if-let                   in-bytes
in-chars                 in-hash-keys             in-hash-pairs
in-hash-values           in-indexed               in-lines
in-list                  in-naturals              in-port
in-producer              in-range                 in-string
in-vector                interleave               interpose
iota                     iterate-n                json-object->string
julian->datetime         juxt                     keep
keyword->string          keyword?                 last-pair
leap-year?               length<=?                length<=n?
length<?                 length<n?                length=?
length=n?                length>=?                length>=n?
length>?                 length>n?                let-alist
let-hash                 list->hash-table         list-of?
make-date                make-datetime            make-duration
make-hash-table          make-hash-table-eq       make-keyword
make-shared              make-time                map-err
map-ok                   map-results              map/car
mapcat                   match                    match/strict
maybe                    memo-proc                meta
meta-wrapped?            negate                   nested-empty-like
nested-get               ok                       ok->list
ok?                      or-else                  parse-date
parse-datetime           parse-time               partial
partition                partition-all            partition-by
path-absolute?           path-directory           path-expand
path-extension           path-join                path-normalize
path-strip-directory     path-strip-extension     pget
pgetq                    pgetv                    plist->alist*
plist->hash-table        pop!                     pp
pp-to-string             ppd                      ppd-to-string
pprint                   prem                     prem!
premq                    premq!                   premv
premv!                   printf                   processor-count
pset                     pset!                    psetq
psetq!                   psetv                    psetv!
push!                    random-integer           rassoc
re                       re-find-all              re-fold
re-groups                re-match-end             re-match-full
re-match-group           re-match-groups          re-match-named
re-match-start           re-match?                re-replace
re-replace-all           re-search                re-split
re?                      read-all-as-lines        read-all-as-string
read-csv                 read-csv-file            read-file-lines
read-file-string         read-json                read-line
reductions               regex-match              regex-replace
regex-replace-all        regex-search             register-struct-type!
remove-watch!            reset!                   result->option
result->values           result?                  results-partition
rows->csv-string         rx                       sequence-results
shared-cas!              shared-ref               shared-set!
shared-swap!             shared-update!           shared?
slice                    snoc                     some
some->                   some->>                  some-fn
sort                     sort!                    split
split-at                 split-with               stable-sort
stable-sort!             str                      string->json-object
string->keyword          string-contains          string-empty?
string-find              string-find-all          string-index
string-join              string-map               string-match?
string-prefix?           string-split             string-suffix?
string-trim              strip-meta               struct-field-ref
struct-field-set!        struct-predicate         struct-type-info
swap!                    take                     take-last
take-until               take-while               time->string
try                      try-result               try-result*
unique                   until                    unwind-protect
unwrap                   unwrap-err               unwrap-or
unwrap-or-else           update-in                update-in!
using                    vary-meta                vderef
volatile!                volatile?                vreset!
vswap!                   when-let                 when/list
while                    with-catch               with-id
with-input-from-string   with-list-builder        with-lock
with-meta                with-output-to-string    with-resource
write-csv                write-csv-file           write-file-string
write-json               zip                      ~
```

</details>

## 2. Where is X? (symbol → modules)

Every exported symbol, mapped to the modules that export it. If a symbol has multiple providers, any of them will give you that binding.

| [1](#idx-1) | [a](#idx-a) | [b](#idx-b) | [c](#idx-c) | [d](#idx-d) | [e](#idx-e) | [f](#idx-f) | [g](#idx-g) | [h](#idx-h) | [i](#idx-i) | [j](#idx-j) | [k](#idx-k) | [l](#idx-l) | [m](#idx-m) | [n](#idx-n) | [o](#idx-o) | [p](#idx-p) | [q](#idx-q) | [r](#idx-r) | [s](#idx-s) | [sym](#idx-sym) | [t](#idx-t) | [u](#idx-u) | [v](#idx-v) | [w](#idx-w) | [x](#idx-x) | [y](#idx-y) | [z](#idx-z) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

### <a name="idx-1"></a>1

| Symbol | Modules |
| --- | --- |
| `1+` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+3) |
| `1-` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+3) |

### <a name="idx-a"></a>a

| Symbol | Modules |
| --- | --- |
| `AF_SP` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `AF_SP_RAW` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `ALL` | `(std specter)` |
| `Applicative` | `(std typed hkt)` |
| `Async` | `(std async)` |
| `Async::descriptor` | `(std async)` |
| `abi-name` | `(jerboa cross)` |
| `abort` | `(std control delimited)` |
| `abort-to-prompt` | `(std misc delimited)` |
| `absento` | `(jerboa clojure)`, `(std logic)` |
| `acons` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `acquire` | `(std effect resource)` |
| `acquire-port` | `(std effect resource)` |
| `activate-cloj-reader!` | `(jerboa cloj)`, `(jerboa clojure)` |
| `active-pattern-proc` | `(std match2)` |
| `active-pattern?` | `(std match2)` |
| `actor-alive?` | `(std actor core)`, `(std actor)` |
| `actor-dead?` | `(std error conditions)` |
| `actor-error-actor-id` | `(std error conditions)` |
| `actor-error?` | `(std error conditions)` |
| `actor-id` | `(std actor core)`, `(std actor)` |
| `actor-kill!` | `(std actor core)`, `(std actor)` |
| `actor-ref-id` | `(std actor core)`, `(std actor)` |
| `actor-ref-links` | `(std actor core)`, `(std actor)` |
| `actor-ref-links-set!` | `(std actor core)`, `(std actor)` |
| `actor-ref-mailbox` | `(std actor core)` |
| `actor-ref-monitors` | `(std actor core)`, `(std actor)` |
| `actor-ref-monitors-set!` | `(std actor core)`, `(std actor)` |
| `actor-ref-name` | `(std actor core)`, `(std actor)` |
| `actor-ref-node` | `(std actor core)`, `(std actor)` |
| `actor-ref?` | `(std actor core)`, `(std actor)` |
| `actor-timeout-seconds` | `(std error conditions)` |
| `actor-timeout?` | `(std error conditions)` |
| `actor-wait!` | `(std actor core)`, `(std actor)` |
| `add-command!` | `(std cli multicall)` |
| `add-duration` | `(std srfi srfi-19)` |
| `add-method!` | `(std clos)` |
| `add-rule!` | `(std lint)` |
| `add-signal-handler!` | `(std os signal)` |
| `add-sink!` | `(std log)` |
| `add-watch!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc atom)` |
| `address->string` | `(std net address)` |
| `address-host` | `(std net address)` |
| `address-port` | `(std net address)` |
| `address?` | `(std net address)` |
| `admix` | `(std csp clj)` |
| `admix!` | `(std csp mix)`, `(std csp ops)` |
| `advise-after` | `(std misc advice)` |
| `advise-around` | `(std misc advice)` |
| `advise-before` | `(std misc advice)` |
| `advise-error` | `(std error-advice)` |
| `advised?` | `(std misc advice)` |
| `aead-decrypt` | `(std crypto aead)` |
| `aead-encrypt` | `(std crypto aead)` |
| `aead-key-generate` | `(std crypto aead)` |
| `affine-consumed?` | `(std typed affine)` |
| `affine-drop!` | `(std typed affine)` |
| `affine-peek` | `(std typed affine)` |
| `affine-use` | `(std typed affine)` |
| `affine?` | `(std typed affine)` |
| `after` | `(std select)` |
| `agent` | `(std agent)` |
| `agent-error` | `(std agent)` |
| `agent-value` | `(std agent)` |
| `agent?` | `(std agent)` |
| `aget` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `agetq` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `agetv` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `agg-collect` | `(std table)` |
| `agg-count` | `(std table)` |
| `agg-max` | `(std table)` |
| `agg-mean` | `(std table)` |
| `agg-min` | `(std table)` |
| `agg-sum` | `(std table)` |
| `aif` | `(jerboa clojure)`, `(jerboa prelude)`, `(std gambit-compat)`, `(std prelude)`, ... (+1) |
| `alias` | `(std srfi srfi-212)` |
| `alist` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std sugar)` |
| `alist->btree` | `(std mmap-btree)` |
| `alist->hamt` | `(std misc persistent)` |
| `alist->hash` | `(std misc alist-more)` |
| `alist->hash-table` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+3) |
| `alist->headers` | `(std net request)` |
| `alist->mapping` | `(std srfi srfi-146)` |
| `alist->plist` | `(std misc plist)` |
| `alist->plist*` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `alist->pmap` | `(std data pmap)` |
| `alist->protobuf` | `(std protobuf)` |
| `alist->query-string` | `(std net uri)` |
| `alist->record` | `(std debug record-inspect)` |
| `alist->sorted-map` | `(std ds sorted-map)` |
| `alist-copy` | `(std srfi srfi-1)` |
| `alist-delete` | `(std srfi srfi-1)` |
| `alist-delete!` | `(std srfi srfi-1)` |
| `alist-filter` | `(std misc alist-more)` |
| `alist-keys` | `(std misc alist-more)` |
| `alist-list->relation` | `(std misc relation)` |
| `alist-map` | `(std misc alist-more)` |
| `alist-merge` | `(std misc alist-more)` |
| `alist-ref/default` | `(std misc alist-more)` |
| `alist-update` | `(std misc alist-more)` |
| `alist-values` | `(std misc alist-more)` |
| `alist?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `alists->csv` | `(jerboa clojure)`, `(jerboa prelude)`, `(std csv)`, `(std prelude)` |
| `all-sealed-methods` | `(std dev devirt)` |
| `all-solutions` | `(std effect multishot)` |
| `alloc-profile-start!` | `(std dev profile)` |
| `alloc-profile-stop!` | `(std dev profile)` |
| `alloc-results` | `(std dev profile)` |
| `allocate-instance` | `(std clos)` |
| `allocation-count` | `(std profile)` |
| `alt!` | `(std csp clj)`, `(std csp select)` |
| `alt!!` | `(std csp clj)`, `(std csp select)` |
| `alter` | `(std stm)` |
| `alts!` | `(std csp clj)`, `(std csp select)` |
| `alts!!` | `(std csp clj)`, `(std csp select)` |
| `always-event` | `(std misc event)` |
| `always-evt` | `(std event)` |
| `amb` | `(std amb)`, `(std effect multishot)`, `(std misc amb)` |
| `amb-all` | `(std effect multishot)` |
| `amb-assert` | `(std amb)`, `(std misc amb)` |
| `amb-collect` | `(std amb)`, `(std misc amb)` |
| `amb-fail` | `(std amb)`, `(std misc amb)` |
| `amb-find` | `(std amb)` |
| `analyze-document` | `(std lsp)` |
| `and-then` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `annotate-code` | `(std quasiquote-types)` |
| `annotated-datum` | `(jerboa reader)` |
| `annotated-datum-source` | `(jerboa reader)` |
| `annotated-datum-value` | `(jerboa reader)` |
| `annotated-datum?` | `(jerboa reader)` |
| `antidebug-breakpoint?` | `(std os antidebug)` |
| `antidebug-check-all` | `(std os antidebug)` |
| `antidebug-error-reason` | `(std os antidebug)` |
| `antidebug-error?` | `(std os antidebug)` |
| `antidebug-ld-preload?` | `(std os antidebug)` |
| `antidebug-ptrace!` | `(std os antidebug)` |
| `antidebug-timing-anomaly?` | `(std os antidebug)` |
| `antidebug-traced?` | `(std os antidebug)` |
| `any` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+5) |
| `any-bit-set?` | `(std srfi srfi-151)` |
| `any?-ec` | `(std srfi srfi-42)` |
| `api-key-register!` | `(std security auth)` |
| `api-key-revoke!` | `(std security auth)` |
| `api-key-store?` | `(std security auth)` |
| `api-key-validate` | `(std security auth)` |
| `app-arguments` | `(std app)` |
| `app-init-proc` | `(std app)` |
| `app-main-proc` | `(std app)` |
| `app-name` | `(std app)` |
| `app-run!` | `(std app)` |
| `app?` | `(std app)` |
| `append-map` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)`, `(std srfi srfi-1)` |
| `append-map!` | `(std srfi srfi-1)` |
| `append-reverse` | `(std srfi srfi-1)` |
| `append-reverse!` | `(std srfi srfi-1)` |
| `append1` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `appendo` | `(jerboa clojure)`, `(std logic)` |
| `apply-dynamic-bindings` | `(jerboa clojure)`, `(std clojure)` |
| `apply-generic` | `(std clos)` |
| `apply-input-transformers` | `(std repl middleware)` |
| `apply-method` | `(std clos)` |
| `apply-methods` | `(std clos)` |
| `apply-optimization-passes` | `(std compiler passes)` |
| `apply-security-headers` | `(std net security-headers)` |
| `apply-xf` | `(std transducer)` |
| `arbitrary-boolean` | `(std test framework)` |
| `arbitrary-integer` | `(std test framework)` |
| `arbitrary-list` | `(std test framework)` |
| `arbitrary-string` | `(std test framework)` |
| `arem` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `arem!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `aremq` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `aremq!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `aremv` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `aremv!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `arena-alloc` | `(std arena)` |
| `arena-alloc-bytes` | `(std arena)` |
| `arena-alloc-string` | `(std arena)` |
| `arena-capacity` | `(std arena)` |
| `arena-checkpoint` | `(std arena)` |
| `arena-destroy!` | `(std arena)` |
| `arena-intern!` | `(std arena)` |
| `arena-intern-lookup` | `(std arena)` |
| `arena-remaining` | `(std arena)` |
| `arena-reset!` | `(std arena)` |
| `arena-rollback!` | `(std arena)` |
| `arena-stats` | `(std arena)` |
| `arena-used` | `(std arena)` |
| `arena?` | `(std arena)` |
| `argon2id-available?` | `(std crypto password)` |
| `argument` | `(std cli getopt)` |
| `arithmetic-seq` | `(std compiler partial-eval)` |
| `arithmetic-shift` | `(jerboa core)`, `(std gambit-compat)`, `(std srfi srfi-151)` |
| `arity-error` | `(std errors)` |
| `arity-error-definition` | `(std errors)` |
| `arity-error-expected` | `(std errors)` |
| `arity-error-got` | `(std errors)` |
| `arity-error-who` | `(std errors)` |
| `arity-error?` | `(std errors)` |
| `artifact-store-get` | `(std build reproducible)` |
| `artifact-store-has?` | `(std build reproducible)` |
| `artifact-store-path` | `(std build reproducible)` |
| `artifact-store-put!` | `(std build reproducible)` |
| `artifact-store?` | `(std build reproducible)` |
| `as->` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std sugar)` |
| `aset` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `aset!` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `asetq` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `asetq!` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `asetv` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `asetv!` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `ask` | `(std actor protocol)`, `(std actor)` |
| `ask-sync` | `(std actor protocol)`, `(std actor)` |
| `assert!` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+5) |
| `assert-contract` | `(std contract)` |
| `assert-equal!` | `(std assert)` |
| `assert-exception` | `(std assert)` |
| `assert-flow` | `(std security flow)` |
| `assert-pred` | `(std assert)` |
| `assert-refined` | `(std typed advanced)`, `(std typed refine)` |
| `assert-type` | `(std macro-types)`, `(std typed)` |
| `assert-untainted` | `(std security taint)` |
| `assoc` | `(jerboa clojure)`, `(std clojure)` |
| `assoc!` | `(jerboa clojure)`, `(std clojure)` |
| `assoc-in` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc nested)` |
| `assoc-in!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc nested)` |
| `assume` | `(std srfi srfi-145)` |
| `ast->nfa` | `(std regex-ct-impl)` |
| `async` | `(std concur async-await)` |
| `async-channel-get` | `(std async)` |
| `async-channel-put` | `(std async)` |
| `async-promise-resolve!` | `(std async)` |
| `async-promise-resolved?` | `(std async)` |
| `async-promise-value` | `(std async)` |
| `async-promise?` | `(std async)` |
| `async-reduce` | `(std csp clj)` |
| `async-sleep` | `(std async)` |
| `async-stream->list` | `(std stream async)` |
| `async-stream-empty?` | `(std stream async)` |
| `async-stream-filter` | `(std stream async)` |
| `async-stream-fold` | `(std stream async)` |
| `async-stream-for-each` | `(std stream async)` |
| `async-stream-map` | `(std stream async)` |
| `async-stream-next!` | `(std stream async)` |
| `async-stream-take` | `(std stream async)` |
| `async-task` | `(std async)` |
| `async-task?` | `(std async)` |
| `at-compile-time` | `(std staging)` |
| `atom` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc atom)` |
| `atom-deref` | `(jerboa prelude)`, `(std misc atom)` |
| `atom-reset!` | `(jerboa prelude)`, `(std misc atom)` |
| `atom-swap!` | `(jerboa prelude)`, `(std misc atom)` |
| `atom-update!` | `(jerboa prelude)`, `(std misc atom)` |
| `atom?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc atom)` |
| `atomically` | `(std concur stm)`, `(std stm)` |
| `attenuate-capability` | `(std security capability)` |
| `attenuate-eval` | `(std capability)` |
| `attenuate-fs` | `(std capability)` |
| `attenuate-net` | `(std capability)` |
| `audit-event-types` | `(std security audit)` |
| `audit-imports-directory` | `(std security import-audit)` |
| `audit-imports-file` | `(std security import-audit)` |
| `audit-log!` | `(std security audit)` |
| `audit-logger-close!` | `(std security audit)` |
| `audit-logger?` | `(std security audit)` |
| `auth-result-authenticated?` | `(std security auth)` |
| `auth-result-identity` | `(std security auth)` |
| `auth-result-roles` | `(std security auth)` |
| `auth-result?` | `(std security auth)` |
| `authenticated-message-hmac` | `(std actor cluster-security)` |
| `authenticated-message-payload` | `(std actor cluster-security)` |
| `authenticated-message-sender` | `(std actor cluster-security)` |
| `authenticated-message-sequence` | `(std actor cluster-security)` |
| `authenticated-message-timestamp` | `(std actor cluster-security)` |
| `authenticated-message?` | `(std actor cluster-security)` |
| `auto-clone` | `(std derive2)` |
| `auto-compare` | `(std derive2)` |
| `auto-display` | `(std derive2)` |
| `auto-equal` | `(std derive2)` |
| `auto-hash` | `(std derive2)` |
| `auto-json` | `(std derive2)` |
| `auto-serialize` | `(std derive2)` |
| `auto-specialization-enabled?` | `(std compiler partial-eval)` |
| `await` | `(std agent)`, `(std concur async-await)` |
| `await-all` | `(std concur async-await)` |
| `await-any` | `(std concur async-await)` |
| `awhen` | `(jerboa clojure)`, `(jerboa prelude)`, `(std gambit-compat)`, `(std prelude)`, ... (+1) |
| `aws-sigv4-sign` | `(std net s3)` |

### <a name="idx-b"></a>b

| Symbol | Modules |
| --- | --- |
| `BYTEVECTOR-HEADER-PAYLOAD` | `(jerboa wasm values)` |
| `Bounded` | `(std typed refine)` |
| `bag` | `(std srfi srfi-113)` |
| `bag->list` | `(std srfi srfi-113)` |
| `bag-adjoin` | `(std srfi srfi-113)` |
| `bag-count` | `(std srfi srfi-113)` |
| `bag-delete` | `(std srfi srfi-113)` |
| `bag?` | `(std srfi srfi-113)` |
| `balanced-quotient` | `(std srfi srfi-141)` |
| `balanced-remainder` | `(std srfi srfi-141)` |
| `balanced/` | `(std srfi srfi-141)` |
| `barrier-parties` | `(std misc barrier)` |
| `barrier-reset!` | `(std concur util)`, `(std misc barrier)` |
| `barrier-wait!` | `(std concur util)`, `(std misc barrier)` |
| `barrier-waiting` | `(std misc barrier)` |
| `barrier?` | `(std concur util)`, `(std misc barrier)` |
| `base58-decode` | `(std text base58)` |
| `base58-encode` | `(std text base58)` |
| `base58check-decode` | `(std text base58)` |
| `base58check-encode` | `(std text base58)` |
| `base64-decode` | `(std text base64)` |
| `base64-encode` | `(std text base64)` |
| `base64-string->u8vector` | `(std text base64)` |
| `batch-call` | `(std net json-rpc)` |
| `begin-ffi` | `(jerboa clojure)`, `(jerboa ffi)`, `(jerboa prelude clean)`, `(jerboa prelude)`, ... (+1) |
| `benchmark->alist` | `(std dev benchmark)` |
| `benchmark-compare` | `(std dev benchmark)` |
| `benchmark-faster?` | `(std dev benchmark)` |
| `benchmark-name` | `(std dev benchmark)` |
| `benchmark-report` | `(std dev benchmark)` |
| `benchmark-result-max-ns` | `(std dev benchmark)` |
| `benchmark-result-mean-ns` | `(std dev benchmark)` |
| `benchmark-result-median-ns` | `(std dev benchmark)` |
| `benchmark-result-min-ns` | `(std dev benchmark)` |
| `benchmark-result-name` | `(std dev benchmark)` |
| `benchmark-result-samples` | `(std dev benchmark)` |
| `benchmark-result-stddev-ns` | `(std dev benchmark)` |
| `benchmark-result?` | `(std dev benchmark)` |
| `benchmark-run` | `(std dev benchmark)` |
| `benchmark-setup` | `(std dev benchmark)` |
| `benchmark-teardown` | `(std dev benchmark)` |
| `benchmark?` | `(std dev benchmark)` |
| `bg-color` | `(std misc terminal)` |
| `binary-pack` | `(std binary)` |
| `binary-read` | `(std binary)`, `(std misc binary-type)` |
| `binary-struct-fields` | `(std binary)` |
| `binary-struct-name` | `(std binary)` |
| `binary-struct-size` | `(std binary)` |
| `binary-struct?` | `(std binary)` |
| `binary-unpack` | `(std binary)` |
| `binary-write` | `(std misc binary-type)` |
| `binary-write!` | `(std binary)` |
| `bind-method!` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `binding` | `(jerboa clojure)`, `(std clojure)` |
| `bio-close` | `(std net bio)` |
| `bio-flush` | `(std net bio)` |
| `bio-peek-byte` | `(std net bio)` |
| `bio-read-byte` | `(std net bio)` |
| `bio-read-bytes` | `(std net bio)` |
| `bio-read-line` | `(std net bio)` |
| `bio-unread-byte` | `(std net bio)` |
| `bio-write-byte` | `(std net bio)` |
| `bio-write-bytes` | `(std net bio)` |
| `bio-write-string` | `(std net bio)` |
| `bit-count` | `(std srfi srfi-151)` |
| `bit-field` | `(std srfi srfi-151)` |
| `bit-field-any?` | `(std srfi srfi-151)` |
| `bit-field-clear` | `(std srfi srfi-151)` |
| `bit-field-every?` | `(std srfi srfi-151)` |
| `bit-field-replace` | `(std srfi srfi-151)` |
| `bit-field-rotate` | `(std srfi srfi-151)` |
| `bit-field-set` | `(std srfi srfi-151)` |
| `bit-set?` | `(std srfi srfi-151)` |
| `bit-swap` | `(std srfi srfi-151)` |
| `bitwise-and` | `(std srfi srfi-151)` |
| `bitwise-if` | `(std srfi srfi-151)` |
| `bitwise-ior` | `(std srfi srfi-151)` |
| `bitwise-not` | `(std srfi srfi-151)` |
| `bitwise-xor` | `(std srfi srfi-151)` |
| `black` | `(std cli style)` |
| `blank?` | `(std clojure string)` |
| `blink` | `(std misc terminal)` |
| `blue` | `(std cli style)` |
| `bn*` | `(std crypto bn)` |
| `bn+` | `(std crypto bn)` |
| `bn-` | `(std crypto bn)` |
| `bn->bytevector` | `(std crypto bn)` |
| `bn->hex` | `(std crypto bn)` |
| `bn-bit-length` | `(std crypto bn)` |
| `bn-compare` | `(std crypto bn)` |
| `bn-expt-mod` | `(std crypto bn)` |
| `bn-gcd` | `(std crypto bn)` |
| `bn-mod` | `(std crypto bn)` |
| `bn-modinv` | `(std crypto bn)` |
| `bn-negative?` | `(std crypto bn)` |
| `bn-zero?` | `(std crypto bn)` |
| `bn/` | `(std crypto bn)` |
| `bold` | `(std cli style)`, `(std misc terminal)` |
| `boolean-comparator` | `(std srfi srfi-128)` |
| `borrow` | `(std borrow)` |
| `borrow-count` | `(std borrow)` |
| `borrow-mut` | `(std borrow)` |
| `bound-fn` | `(jerboa clojure)`, `(std clojure)` |
| `bounded-deque-capacity` | `(std misc deque)` |
| `bounded-deque?` | `(std misc deque)` |
| `bounded-send` | `(std actor bounded)` |
| `box` | `(std gambit-compat)` |
| `box?` | `(std gambit-compat)` |
| `break-never!` | `(std dev debug)` |
| `break-when!` | `(std dev debug)` |
| `btree->alist` | `(std mmap-btree)` |
| `btree-commit!` | `(std mmap-btree)` |
| `btree-delete!` | `(std mmap-btree)` |
| `btree-fold` | `(std mmap-btree)` |
| `btree-get` | `(std mmap-btree)` |
| `btree-has?` | `(std mmap-btree)` |
| `btree-keys` | `(std mmap-btree)` |
| `btree-order` | `(std mmap-btree)` |
| `btree-path` | `(std mmap-btree)` |
| `btree-put!` | `(std mmap-btree)` |
| `btree-range` | `(std mmap-btree)` |
| `btree-rollback!` | `(std mmap-btree)` |
| `btree-size` | `(std mmap-btree)` |
| `btree-values` | `(std mmap-btree)` |
| `btree?` | `(std mmap-btree)` |
| `buffer-pool-stats` | `(std net zero-copy)` |
| `buffer-pool?` | `(std net zero-copy)` |
| `buffer-slice?` | `(std net zero-copy)` |
| `buffer-spec?` | `(std csp clj)` |
| `buffered-close` | `(std io bio)` |
| `buffered-flush` | `(std io bio)` |
| `buffered-input?` | `(std io bio)` |
| `buffered-output?` | `(std io bio)` |
| `buffered-peek-byte` | `(std io bio)` |
| `buffered-peek-char` | `(std io bio)` |
| `buffered-read-byte` | `(std io bio)` |
| `buffered-read-bytes` | `(std io bio)` |
| `buffered-read-char` | `(std io bio)` |
| `buffered-read-line` | `(std io bio)` |
| `buffered-unread-byte` | `(std io bio)` |
| `buffered-write-byte` | `(std io bio)` |
| `buffered-write-bytes` | `(std io bio)` |
| `buffered-write-line` | `(std io bio)` |
| `buffered-write-string` | `(std io bio)` |
| `build-app` | `(std match-syntax)` |
| `build-begin` | `(std match-syntax)` |
| `build-binary` | `(jerboa build)` |
| `build-boot-file` | `(jerboa build)` |
| `build-cache-load` | `(std build)` |
| `build-cache-lookup` | `(std build reproducible)` |
| `build-cache-save` | `(std build)` |
| `build-cache-stats` | `(std build reproducible)` |
| `build-cache-store!` | `(std build reproducible)` |
| `build-cache?` | `(std build reproducible)` |
| `build-dag` | `(std build)` |
| `build-dep-graph-from-dir` | `(std build watch)` |
| `build-if` | `(std match-syntax)` |
| `build-instance-dict` | `(std misc typeclass)` |
| `build-lambda` | `(std match-syntax)` |
| `build-let` | `(std match-syntax)` |
| `build-matrix-results` | `(std build cross)` |
| `build-musl-binary` | `(jerboa build musl)` |
| `build-nfa` | `(std text regex-compile)` |
| `build-project` | `(jerboa build)`, `(std build)` |
| `build-query-string` | `(std net request)` |
| `build-record-deps-hash` | `(std build reproducible)` |
| `build-record-hash` | `(std build reproducible)` |
| `build-record-source-hash` | `(std build reproducible)` |
| `build-record-timestamp` | `(std build reproducible)` |
| `build-record?` | `(std build reproducible)` |
| `build-release` | `(jerboa build)` |
| `build-static-binary` | `(jerboa build)` |
| `build-system-add-rule!` | `(std build watch)` |
| `build-system-build!` | `(std build watch)` |
| `build-system-build-all!` | `(std build watch)` |
| `build-system-clean!` | `(std build watch)` |
| `build-system?` | `(std build watch)` |
| `butlast` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list-more)`, `(std misc list)` |
| `bv-f32-ref` | `(std binary)` |
| `bv-f32-set!` | `(std binary)` |
| `bv-f64-ref` | `(std binary)` |
| `bv-f64-set!` | `(std binary)` |
| `bv-s16-ref` | `(std binary)` |
| `bv-s16-set!` | `(std binary)` |
| `bv-s32-ref` | `(std binary)` |
| `bv-s32-set!` | `(std binary)` |
| `bv-s64-ref` | `(std binary)` |
| `bv-s64-set!` | `(std binary)` |
| `bv-s8-ref` | `(std binary)` |
| `bv-s8-set!` | `(std binary)` |
| `bv-u16-ref` | `(std binary)` |
| `bv-u16-set!` | `(std binary)` |
| `bv-u32-ref` | `(std binary)` |
| `bv-u32-set!` | `(std binary)` |
| `bv-u64-ref` | `(std binary)` |
| `bv-u64-set!` | `(std binary)` |
| `bv-u8-ref` | `(std binary)` |
| `bv-u8-set!` | `(std binary)` |
| `bwp-object?` | `(std ephemeron)` |
| `bytes->message` | `(std actor transport)` |
| `bytes->string` | `(jerboa core)`, `(std gambit-compat)` |
| `bytevector->bn` | `(std crypto bn)` |
| `bytevector->fasl` | `(std fasl)` |
| `bytevector->generator` | `(std srfi srfi-158)` |
| `bytevector->integer` | `(std misc numeric)` |
| `bytevector-builder-append-bv!` | `(jerboa wasm format)` |
| `bytevector-builder-append-u8!` | `(jerboa wasm format)` |
| `bytevector-builder-build` | `(jerboa wasm format)` |
| `bytevector-builder-length` | `(jerboa wasm format)` |
| `bytevector-concat` | `(std io raw)` |
| `bytevector-copy*` | `(thunderchez thunder-utils)` |

### <a name="idx-c"></a>c

| Symbol | Modules |
| --- | --- |
| `CLOSURE-HEADER-PAYLOAD` | `(jerboa wasm values)` |
| `CONNECTION_BAD` | `(std db postgresql)` |
| `CONNECTION_OK` | `(std db postgresql)` |
| `CURLFTP_CREATE_DIR` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLFTP_CREATE_DIR_NONE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLFTP_CREATE_DIR_RETRY` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_ACCEPTTIMEOUT_MS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_ACCEPT_ENCODING` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_ADDRESS_SCOPE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_APPEND` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_AUTOREFERER` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_BUFFERSIZE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_CAINFO` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_CAPATH` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_CERTINFO` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_CHUNK_BGN_FUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_CHUNK_DATA` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_CHUNK_END_FUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_CLOSESOCKETDATA` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_CLOSESOCKETFUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_CONNECTTIMEOUT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_CONNECTTIMEOUT_MS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_CONNECT_ONLY` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_CONNECT_TO` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_CONV_FROM_NETWORK_FUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_CONV_FROM_UTF8_FUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_CONV_TO_NETWORK_FUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_COOKIE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_COOKIEFILE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_COOKIEJAR` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_COOKIELIST` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_COOKIESESSION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_COPYPOSTFIELDS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_CRLF` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_CRLFILE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_CUSTOMREQUEST` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_DEBUGDATA` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_DEBUGFUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_DEFAULT_PROTOCOL` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_DIRLISTONLY` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_DNS_CACHE_TIMEOUT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_DNS_INTERFACE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_DNS_LOCAL_IP4` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_DNS_LOCAL_IP6` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_DNS_SERVERS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_DNS_USE_GLOBAL_CACHE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_EGDSOCKET` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_ERRORBUFFER` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_EXPECT_100_TIMEOUT_MS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FAILONERROR` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FILETIME` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FNMATCH_DATA` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FNMATCH_FUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FOLLOWLOCATION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FORBID_REUSE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FRESH_CONNECT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FTPPORT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FTPSSLAUTH` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FTP_ACCOUNT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FTP_ALTERNATIVE_TO_USER` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FTP_CREATE_MISSING_DIRS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FTP_FILEMETHOD` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FTP_RESPONSE_TIMEOUT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FTP_SKIP_PASV_IP` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FTP_SSL_CCC` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FTP_USE_EPRT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FTP_USE_EPSV` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_FTP_USE_PRET` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_GSSAPI_DELEGATION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_HEADER` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_HEADERDATA` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_HEADERFUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_HEADEROPT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_HTTP200ALIASES` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_HTTPAUTH` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_HTTPGET` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_HTTPHEADER` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_HTTPPOST` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_HTTPPROXYTUNNEL` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_HTTP_CONTENT_DECODING` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_HTTP_TRANSFER_DECODING` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_HTTP_VERSION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_IGNORE_CONTENT_LENGTH` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_INFILESIZE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_INFILESIZE_LARGE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_INTERFACE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_INTERLEAVEDATA` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_INTERLEAVEFUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_IOCTLDATA` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_IOCTLFUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_IPRESOLVE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_ISSUERCERT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_KEYPASSWD` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_KRBLEVEL` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_LOCALPORT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_LOCALPORTRANGE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_LOGIN_OPTIONS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_LOW_SPEED_LIMIT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_LOW_SPEED_TIME` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_MAIL_AUTH` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_MAIL_FROM` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_MAIL_RCPT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_MAXCONNECTS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_MAXFILESIZE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_MAXFILESIZE_LARGE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_MAXREDIRS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_MAX_RECV_SPEED_LARGE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_MAX_SEND_SPEED_LARGE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_NETRC` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_NETRC_FILE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_NEW_DIRECTORY_PERMS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_NEW_FILE_PERMS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_NOBODY` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_NOPROGRESS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_NOPROXY` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_NOSIGNAL` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_OBSOLETE40` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_OBSOLETE72` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_OPENSOCKETDATA` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_OPENSOCKETFUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PASSWORD` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PATH_AS_IS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PINNEDPUBLICKEY` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PIPEWAIT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PORT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_POST` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_POSTFIELDS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_POSTFIELDSIZE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_POSTFIELDSIZE_LARGE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_POSTQUOTE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_POSTREDIR` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PREQUOTE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PRIVATE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PROGRESSDATA` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PROGRESSFUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PROTOCOLS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PROXY` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PROXYAUTH` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PROXYHEADER` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PROXYPASSWORD` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PROXYPORT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PROXYTYPE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PROXYUSERNAME` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PROXYUSERPWD` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PROXY_SERVICE_NAME` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PROXY_TRANSFER_MODE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_PUT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_QUOTE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_RANDOM_FILE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_RANGE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_READDATA` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_READFUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_REDIR_PROTOCOLS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_REFERER` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_RESOLVE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_RESUME_FROM` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_RESUME_FROM_LARGE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_RTSP_CLIENT_CSEQ` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_RTSP_REQUEST` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_RTSP_SERVER_CSEQ` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_RTSP_SESSION_ID` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_RTSP_STREAM_URI` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_RTSP_TRANSPORT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SASL_IR` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SEEKDATA` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SEEKFUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SERVICE_NAME` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SHARE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SOCKOPTDATA` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SOCKOPTFUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SOCKS5_GSSAPI_NEC` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SOCKS5_GSSAPI_SERVICE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSH_AUTH_TYPES` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSH_HOST_PUBLIC_KEY_MD5` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSH_KEYDATA` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSH_KEYFUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSH_KNOWNHOSTS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSH_PRIVATE_KEYFILE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSH_PUBLIC_KEYFILE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSLCERT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSLCERTTYPE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSLENGINE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSLENGINE_DEFAULT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSLKEY` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSLKEYTYPE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSLVERSION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSL_CIPHER_LIST` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSL_CTX_DATA` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSL_CTX_FUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSL_ENABLE_ALPN` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSL_ENABLE_NPN` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSL_FALSESTART` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSL_OPTIONS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSL_SESSIONID_CACHE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSL_VERIFYHOST` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSL_VERIFYPEER` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_SSL_VERIFYSTATUS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_STDERR` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_STREAM_DEPENDS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_STREAM_DEPENDS_E` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_STREAM_WEIGHT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_TCP_FASTOPEN` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_TCP_KEEPALIVE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_TCP_KEEPIDLE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_TCP_KEEPINTVL` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_TCP_NODELAY` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_TELNETOPTIONS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_TFTP_BLKSIZE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_TFTP_NO_OPTIONS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_TIMECONDITION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_TIMEOUT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_TIMEOUT_MS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_TIMEVALUE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_TLSAUTH_PASSWORD` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_TLSAUTH_TYPE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_TLSAUTH_USERNAME` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_TRANSFERTEXT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_TRANSFER_ENCODING` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_UNIX_SOCKET_PATH` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_UNRESTRICTED_AUTH` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_UPLOAD` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_URL` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_USERAGENT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_USERNAME` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_USERPWD` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_USE_SSL` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_VERBOSE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_WILDCARDMATCH` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_WRITEDATA` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_WRITEFUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_XFERINFOFUNCTION` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLOPT_XOAUTH2_BEARER` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLPROTO_DICT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLPROTO_FILE` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLPROTO_FTP` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLPROTO_FTPS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLPROTO_HTTP` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLPROTO_HTTPS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLPROTO_IMAP` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLPROTO_IMAPS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLPROTO_LDAP` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLPROTO_LDAPS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLPROTO_POP3` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLPROTO_POP3S` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLPROTO_SCP` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLPROTO_SFTP` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLPROTO_SMTP` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLPROTO_SMTPS` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLPROTO_TELNET` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLPROTO_TFTP` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLUSESSL` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURL_GLOBAL_ACK_EINTR` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURL_GLOBAL_ALL` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURL_GLOBAL_DEFAULT` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURL_GLOBAL_NOTHING` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURL_GLOBAL_SSL` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURL_GLOBAL_WIN32` | `(std ffi curl)`, `(thunderchez curl)` |
| `CURLcode` | `(std ffi curl)`, `(thunderchez curl)` |
| `ContractViolation` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `c-append` | `(std misc ck-macros)` |
| `c-car` | `(std misc ck-macros)` |
| `c-cdr` | `(std misc ck-macros)` |
| `c-cons` | `(std misc ck-macros)` |
| `c-declare` | `(jerboa clojure)`, `(jerboa ffi)`, `(jerboa prelude clean)`, `(jerboa prelude)`, ... (+1) |
| `c-filter` | `(std misc ck-macros)` |
| `c-foldr` | `(std misc ck-macros)` |
| `c-if` | `(std misc ck-macros)` |
| `c-lambda` | `(jerboa clojure)`, `(jerboa ffi)`, `(jerboa prelude clean)`, `(jerboa prelude)`, ... (+1) |
| `c-length` | `(std misc ck-macros)` |
| `c-map` | `(std misc ck-macros)` |
| `c-null?` | `(std misc ck-macros)` |
| `c-quote` | `(std misc ck-macros)` |
| `c-reverse` | `(std misc ck-macros)` |
| `c-type->ffi-type` | `(std foreign bind)` |
| `c-usb-device` | `(std ffi usb)`, `(thunderchez usb)` |
| `c-usb-device-descriptor` | `(std ffi usb)`, `(thunderchez usb)` |
| `cache-clear!` | `(jerboa cache)` |
| `cache-directory` | `(jerboa cache)` |
| `cache-key` | `(jerboa cache)` |
| `cache-lookup` | `(jerboa cache)` |
| `cache-stats` | `(jerboa cache)` |
| `cache-store!` | `(jerboa cache)` |
| `cafe-eval` | `(std cafe)` |
| `cage!` | `(std security cage)` |
| `cage-active?` | `(std security cage)` |
| `cage-allowed-paths` | `(std security cage)` |
| `cage-config-execute` | `(std security cage)` |
| `cage-config-network` | `(std security cage)` |
| `cage-config-read-only` | `(std security cage)` |
| `cage-config-read-write` | `(std security cage)` |
| `cage-config-root` | `(std security cage)` |
| `cage-config-system-paths` | `(std security cage)` |
| `cage-config-temp-dir` | `(std security cage)` |
| `cage-config?` | `(std security cage)` |
| `cage-error-detail` | `(std security cage)` |
| `cage-error-phase` | `(std security cage)` |
| `cage-error?` | `(std security cage)` |
| `cage-root` | `(std security cage)` |
| `cairo-antialias` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-antialias-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-append-path` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-arc` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-arc-negative` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-bool-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-clip` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-clip-extents` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-clip-preserve` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-close-path` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-content-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-copy-clip-rectangle-list` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-copy-page` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-copy-path` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-copy-path-flat` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-curve-to` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-debug-reset-static-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-destroy-func-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-acquire` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-finish` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-flush` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-get-type` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-get-user-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-observer-elapsed` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-observer-fill-elapsed` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-observer-glyphs-elapsed` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-observer-mask-elapsed` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-observer-paint-elapsed` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-observer-print` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-observer-stroke-elapsed` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-release` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-set-user-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-status` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-to-user` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-to-user-distance` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-type` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-device-type-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-extend` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-extend-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-fill` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-fill-extents` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-fill-preserve` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-fill-rule` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-fill-rule-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-filter` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-filter-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-extents` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-extents-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-extents-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-face-get-type` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-face-get-user-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-face-set-user-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-face-status` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-face-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-options-copy` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-options-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-options-equal` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-options-get-antialias` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-options-get-hint-metrics` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-options-get-hint-style` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-options-get-subpixel-order` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-options-hash` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-options-merge` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-options-set-antialias` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-options-set-hint-metrics` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-options-set-hint-style` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-options-set-subpixel-order` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-options-status` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-options-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-slant` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-slant-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-type` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-type-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-weight` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-font-weight-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-format` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-format-stride-for-width` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-format-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-free-garbage` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-antialias` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-current-point` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-dash` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-dash-count` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-fill-rule` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-font-face` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-font-matrix` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-font-options` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-group-target` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-line-cap` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-line-join` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-line-width` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-matrix` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-miter-limit` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-operator` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-scaled-font` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-source` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-target` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-tolerance` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-get-user-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-glyph*-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-glyph-allocate` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-glyph-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-glyph-extents` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-glyph-free` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-glyph-path` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-glyph-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-glyph-t*` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-guard-pointer` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-guardian` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-has-current-point` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-hint-metrics` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-hint-metrics-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-hint-style` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-hint-style-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-identity-matrix` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-image-surface-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-image-surface-create-for-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-image-surface-create-from-png` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-image-surface-create-from-png-stream` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-image-surface-get-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-image-surface-get-format` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-image-surface-get-height` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-image-surface-get-stride` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-image-surface-get-width` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-in-clip` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-in-fill` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-in-stroke` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-int-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-library-init` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-line-cap` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-line-cap-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-line-join` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-line-join-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-line-to` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-mask` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-mask-surface` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-matrix-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-matrix-init` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-matrix-init-identity` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-matrix-init-rotate` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-matrix-init-scale` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-matrix-init-translate` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-matrix-invert` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-matrix-multiply` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-matrix-rotate` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-matrix-scale` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-matrix-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-matrix-transform-distance` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-matrix-transform-point` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-matrix-translate` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-mesh-pattern-begin-patch` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-mesh-pattern-curve-to` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-mesh-pattern-end-patch` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-mesh-pattern-get-control-point` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-mesh-pattern-get-corner-color-rgba` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-mesh-pattern-get-patch-count` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-mesh-pattern-get-path` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-mesh-pattern-line-to` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-mesh-pattern-move-to` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-mesh-pattern-set-control-point` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-mesh-pattern-set-corner-color-rgb` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-mesh-pattern-set-corner-color-rgba` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-move-to` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-new-path` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-new-sub-path` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-operator` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-operator-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-paint` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-paint-with-alpha` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-path-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-path-data-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-path-data-type` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-path-data-type-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-path-extents` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-path-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-add-color-stop-rgb` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-add-color-stop-rgba` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-create-for-surface` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-create-linear` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-create-mesh` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-create-radial` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-create-raster-source` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-create-rgb` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-create-rgba` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-get-color-stop-count` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-get-color-stop-rgba` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-get-extend` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-get-filter` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-get-linear-points` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-get-matrix` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-get-radial-circles` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-get-rgba` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-get-surface` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-get-type` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-get-user-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-set-extend` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-set-filter` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-set-matrix` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-set-user-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-status` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-type` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pattern-type-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pdf-get-versions` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pdf-surface-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pdf-surface-create-for-stream` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pdf-surface-restrict-to-version` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pdf-surface-set-size` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pdf-version-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pdf-version-t*` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pdf-version-to-string` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pop-group` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-pop-group-to-source` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-push-group` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-push-group-with-content` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-raster-source-acquire-func-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-raster-source-acquire-func-t*` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-raster-source-copy-func-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-raster-source-finish-func-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-raster-source-pattern-get-acquire` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-raster-source-pattern-get-callback-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-raster-source-pattern-get-copy` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-raster-source-pattern-get-finish` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-raster-source-pattern-get-snapshot` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-raster-source-pattern-set-acquire` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-raster-source-pattern-set-callback-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-raster-source-pattern-set-copy` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-raster-source-pattern-set-finish` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-raster-source-pattern-set-snapshot` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-raster-source-release-func-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-raster-source-release-func-t*` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-raster-source-snapshot-func-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-read-func-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-recording-surface-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-recording-surface-get-extents` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-recording-surface-ink-extents` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-rectangle` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-rectangle-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-rectangle-int-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-rectangle-list-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-rectangle-list-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-rectangle-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-contains-point` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-contains-rectangle` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-copy` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-create-rectangle` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-create-rectangles` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-equal` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-get-extents` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-get-rectangle` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-intersect` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-intersect-rectangle` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-is-empty` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-num-rectangles` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-overlap` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-overlap-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-status` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-subtract` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-subtract-rectangle` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-translate` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-union` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-union-rectangle` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-xor` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-region-xor-rectangle` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-rel-curve-to` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-rel-line-to` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-rel-move-to` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-reset-clip` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-restore` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-rotate` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-save` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-scale` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-scaled-font-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-scaled-font-extents` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-scaled-font-get-ctm` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-scaled-font-get-font-face` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-scaled-font-get-font-matrix` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-scaled-font-get-font-options` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-scaled-font-get-scale-matrix` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-scaled-font-get-type` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-scaled-font-get-user-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-scaled-font-glyph-extents` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-scaled-font-set-user-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-scaled-font-status` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-scaled-font-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-scaled-font-text-extents` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-scaled-font-text-to-glyphs` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-select-font-face` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-antialias` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-dash` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-fill-rule` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-font-face` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-font-matrix` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-font-options` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-font-size` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-line-cap` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-line-join` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-line-width` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-matrix` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-miter-limit` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-operator` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-scaled-font` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-source` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-source-color` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-source-rgb` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-source-rgba` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-source-surface` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-tolerance` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-set-user-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-show-glyphs` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-show-page` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-show-text` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-show-text-glyphs` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-status` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-status-enum` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-status-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-status-to-string` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-stroke` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-stroke-extents` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-stroke-preserve` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-subpixel-order` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-subpixel-order-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-copy-page` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-create-for-rectangle` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-create-observer` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-create-similar` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-create-similar-image` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-finish` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-flush` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-get-content` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-get-device` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-get-device-offset` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-get-device-scale` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-get-fallback-resolution` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-get-font-options` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-get-mime-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-get-type` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-get-user-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-has-show-text-glyphs` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-map-to-image` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-mark-dirty` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-mark-dirty-rectangle` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-observer-add-fill-callback` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-observer-add-finish-callback` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-observer-add-flush-callback` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-observer-add-glyphs-callback` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-observer-add-mask-callback` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-observer-add-paint-callback` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-observer-add-stroke-callback` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-observer-callback-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-observer-elapsed` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-observer-mode` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-observer-mode-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-observer-print` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-set-device-offset` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-set-device-scale` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-set-fallback-resolution` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-set-mime-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-set-user-data` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-show-page` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-status` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-supports-mime-type` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-t*` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-type` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-type-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-unmap-image` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-write-to-png` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-surface-write-to-png-stream` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-text-cluster*-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-text-cluster-allocate` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-text-cluster-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-text-cluster-flag` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-text-cluster-flags-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-text-cluster-flags-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-text-cluster-free` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-text-cluster-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-text-cluster-t*` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-text-extents` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-text-extents-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-text-extents-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-text-path` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-toy-font-face-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-toy-font-face-get-family` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-toy-font-face-get-slant` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-toy-font-face-get-weight` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-transform` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-translate` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-user-data-key-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-user-font-face-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-user-font-face-get-init-func` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-user-font-face-get-render-glyph-func` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-user-font-face-get-text-to-glyphs-func` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-user-font-face-get-unicode-to-glyph-func` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-user-font-face-set-init-func` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-user-font-face-set-render-glyph-func` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-user-font-face-set-text-to-glyphs-func` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-user-font-face-set-unicode-to-glyph-func` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-user-scaled-font-init-func-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-user-scaled-font-render-glyph-func-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-user-scaled-font-text-to-glyphs-func-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-user-scaled-font-unicode-to-glyph-func-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-user-to-device` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-user-to-device-distance` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-version` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-version-string` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-void*-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `cairo-write-func-t` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `call-method` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `call-next-method` | `(std clos)` |
| `call-with-current-continuation-marks` | `(std control marks)` |
| `call-with-getopt` | `(std cli getopt)` |
| `call-with-immediate-continuation-mark` | `(std misc cont-marks)` |
| `call-with-input-string` | `(jerboa core)`, `(std gambit-compat)`, `(std misc port-utils)` |
| `call-with-inspector` | `(std debug inspector)` |
| `call-with-list-builder` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `call-with-output` | `(std srfi srfi-159)` |
| `call-with-output-string` | `(jerboa core)`, `(std gambit-compat)`, `(std misc port-utils)` |
| `call-with-prompt` | `(std misc delimited)` |
| `call-with-recording` | `(std dev debug)` |
| `call-with-resource` | `(jerboa prelude safe)`, `(std resource)` |
| `call-with-safe-input-file` | `(jerboa prelude safe)` |
| `call-with-safe-output-file` | `(jerboa prelude safe)` |
| `call-with-temporary-directory` | `(std os temp)` |
| `call-with-temporary-file` | `(std os temp)` |
| `call-with-timeout` | `(std misc timeout)` |
| `callable?` | `(std macro-types)` |
| `can-prove?` | `(std typed solver)` |
| `can-refute?` | `(std typed solver)` |
| `cancel!` | `(std task)` |
| `cancel-token?` | `(std task)` |
| `cancellation-token?` | `(std concur async-await)` |
| `cancelled-fiber-id` | `(std fiber)` |
| `cancelled?` | `(std task)` |
| `cap-connect` | `(std capability)` |
| `cap-file-open` | `(std capability)` |
| `cap-file-read` | `(std capability)` |
| `cap-file-write` | `(std capability)` |
| `capability-permissions` | `(std security capability)` |
| `capability-requirements` | `(std security capability-typed)` |
| `capability-type` | `(std capability)`, `(std security capability)` |
| `capability-valid?` | `(std capability)` |
| `capability-violation-detail` | `(std security capability)` |
| `capability-violation-type` | `(std security capability)` |
| `capability-violation?` | `(std security capability)` |
| `capability?` | `(std capability)`, `(std security capability)` |
| `capitalize` | `(std clojure string)` |
| `capsicum-apply-preset!` | `(std security capsicum)` |
| `capsicum-available?` | `(std security capsicum)` |
| `capsicum-compute-only-preset` | `(std security capsicum)` |
| `capsicum-enter!` | `(std security capsicum)` |
| `capsicum-in-capability-mode?` | `(std security capsicum)` |
| `capsicum-io-only-preset` | `(std security capsicum)` |
| `capsicum-limit-fd!` | `(std security capsicum)` |
| `capsicum-open-path` | `(std security capsicum)` |
| `capsicum-right-event` | `(std security capsicum)` |
| `capsicum-right-fstat` | `(std security capsicum)` |
| `capsicum-right-ftruncate` | `(std security capsicum)` |
| `capsicum-right-lookup` | `(std security capsicum)` |
| `capsicum-right-mmap` | `(std security capsicum)` |
| `capsicum-right-read` | `(std security capsicum)` |
| `capsicum-right-seek` | `(std security capsicum)` |
| `capsicum-right-write` | `(std security capsicum)` |
| `capture` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std sugar)` |
| `capture-dynamic-bindings` | `(jerboa clojure)`, `(std clojure)` |
| `car+cdr` | `(std srfi srfi-1)` |
| `car-lens` | `(std lens)` |
| `caro` | `(jerboa clojure)`, `(std logic)` |
| `cas-count` | `(std content-address)` |
| `cas-get` | `(std content-address)` |
| `cas-has?` | `(std content-address)` |
| `cas-keys` | `(std content-address)` |
| `cas-put!` | `(std content-address)` |
| `cas-store` | `(std content-address)` |
| `cast` | `(thunderchez ffi-utils)` |
| `cat` | `(std transducer)` |
| `catch` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `cbor-decode` | `(std text cbor)` |
| `cbor-encode` | `(std text cbor)` |
| `cbor-read` | `(std text cbor)` |
| `cbor-write` | `(std text cbor)` |
| `cc-flags-for-target` | `(jerboa cross)` |
| `cdr-lens` | `(std lens)` |
| `cdro` | `(jerboa clojure)`, `(std logic)` |
| `ceiling-quotient` | `(std srfi srfi-141)` |
| `ceiling-remainder` | `(std srfi srfi-141)` |
| `ceiling/` | `(std srfi srfi-141)` |
| `cell-content` | `(std repl notebook)` |
| `cell-output` | `(std repl notebook)` |
| `cell-type` | `(std repl notebook)` |
| `cell?` | `(std repl notebook)` |
| `cert-fingerprint` | `(std crypto x509)` |
| `chain` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+3) |
| `chain-and` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+3) |
| `chan` | `(std csp clj)` |
| `chan->list` | `(std csp)` |
| `chan-classify-by` | `(std csp ops)` |
| `chan-close!` | `(std csp)` |
| `chan-closed?` | `(std csp)` |
| `chan-empty?` | `(std csp)` |
| `chan-filter` | `(std csp)` |
| `chan-get!` | `(std csp)` |
| `chan-into` | `(std csp ops)` |
| `chan-kind` | `(std csp)` |
| `chan-map` | `(std csp)` |
| `chan-merge` | `(std csp ops)` |
| `chan-pipe` | `(std csp)` |
| `chan-pipe-to` | `(std csp ops)` |
| `chan-pipeline` | `(std csp ops)` |
| `chan-pipeline-async` | `(std csp ops)` |
| `chan-put!` | `(std csp)` |
| `chan-recv-evt` | `(std csp select)` |
| `chan-reduce` | `(std csp ops)` |
| `chan-reduce-async` | `(std csp ops)` |
| `chan-send-evt` | `(std csp select)` |
| `chan-split` | `(std csp ops)` |
| `chan-try-get` | `(std csp)` |
| `chan-try-put!` | `(std csp)` |
| `change-class` | `(std clos)` |
| `channel-close` | `(std misc channel)` |
| `channel-close!` | `(std security privsep)` |
| `channel-closed?` | `(std misc channel)` |
| `channel-empty?` | `(std misc channel)` |
| `channel-get` | `(std misc channel)` |
| `channel-length` | `(std misc channel)` |
| `channel-put` | `(std misc channel)` |
| `channel-receive` | `(std security privsep)` |
| `channel-recv` | `(std misc event)` |
| `channel-recv-event` | `(std misc event)` |
| `channel-select` | `(std misc channel)` |
| `channel-send` | `(std misc event)` |
| `channel-send!` | `(std security privsep)` |
| `channel-send-event` | `(std misc event)` |
| `channel-table-alloc-id` | `(std net ssh channel)` |
| `channel-table-get` | `(std net ssh channel)` |
| `channel-table-next-id` | `(std net ssh channel)` |
| `channel-table-put!` | `(std net ssh channel)` |
| `channel-table-remove!` | `(std net ssh channel)` |
| `channel-try-get` | `(std misc channel)` |
| `channel-try-put` | `(std misc channel)` |
| `channel-try-send` | `(std select)` |
| `channel-xform-done-fn` | `(std csp)` |
| `channel-xform-done-fn-set!` | `(std csp)` |
| `channel-xform-fn` | `(std csp)` |
| `channel-xform-fn-set!` | `(std csp)` |
| `channel?` | `(std csp)`, `(std misc channel)` |
| `chaperone-hashtable` | `(std misc chaperone)` |
| `chaperone-hashtable-delete!` | `(std misc chaperone)` |
| `chaperone-hashtable-ref` | `(std misc chaperone)` |
| `chaperone-hashtable-set!` | `(std misc chaperone)` |
| `chaperone-of?` | `(std misc chaperone)` |
| `chaperone-procedure` | `(std misc chaperone)` |
| `chaperone-unwrap` | `(std misc chaperone)` |
| `chaperone-vector` | `(std misc chaperone)` |
| `chaperone-vector-ref` | `(std misc chaperone)` |
| `chaperone-vector-set!` | `(std misc chaperone)` |
| `chaperone?` | `(std misc chaperone)` |
| `char*->bytevector` | `(thunderchez ffi-utils)` |
| `char*-array->string` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `char-array` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `char-comparator` | `(std srfi srfi-128)` |
| `char-matches-class?` | `(std regex-ct-impl)` |
| `char-matches?` | `(std text regex-compile)` |
| `char-set` | `(std srfi srfi-14)`, `(std text char-set)` |
| `char-set->list` | `(std srfi srfi-14)`, `(std text char-set)` |
| `char-set->string` | `(std srfi srfi-14)`, `(std text char-set)` |
| `char-set-adjoin` | `(std srfi srfi-14)` |
| `char-set-any` | `(std srfi srfi-14)` |
| `char-set-complement` | `(std srfi srfi-14)`, `(std text char-set)` |
| `char-set-contains?` | `(std srfi srfi-14)`, `(std text char-set)` |
| `char-set-copy` | `(std srfi srfi-14)` |
| `char-set-count` | `(std srfi srfi-14)` |
| `char-set-cursor` | `(std srfi srfi-14)` |
| `char-set-cursor-next` | `(std srfi srfi-14)` |
| `char-set-delete` | `(std srfi srfi-14)` |
| `char-set-difference` | `(std srfi srfi-14)`, `(std text char-set)` |
| `char-set-every` | `(std srfi srfi-14)` |
| `char-set-filter` | `(std srfi srfi-14)` |
| `char-set-fold` | `(std srfi srfi-14)` |
| `char-set-for-each` | `(std srfi srfi-14)` |
| `char-set-hash` | `(std srfi srfi-14)` |
| `char-set-intersection` | `(std srfi srfi-14)`, `(std text char-set)` |
| `char-set-map` | `(std srfi srfi-14)` |
| `char-set-ref` | `(std srfi srfi-14)` |
| `char-set-size` | `(std srfi srfi-14)`, `(std text char-set)` |
| `char-set-union` | `(std srfi srfi-14)`, `(std text char-set)` |
| `char-set-xor` | `(std srfi srfi-14)` |
| `char-set:alphanumeric` | `(std text char-set)` |
| `char-set:ascii` | `(std srfi srfi-14)` |
| `char-set:blank` | `(std srfi srfi-14)` |
| `char-set:digit` | `(std srfi srfi-14)`, `(std text char-set)` |
| `char-set:empty` | `(std srfi srfi-14)` |
| `char-set:full` | `(std srfi srfi-14)` |
| `char-set:graphic` | `(std srfi srfi-14)` |
| `char-set:hex-digit` | `(std srfi srfi-14)`, `(std text char-set)` |
| `char-set:iso-control` | `(std srfi srfi-14)` |
| `char-set:letter` | `(std srfi srfi-14)`, `(std text char-set)` |
| `char-set:letter+digit` | `(std srfi srfi-14)` |
| `char-set:lower` | `(std text char-set)` |
| `char-set:lower-case` | `(std srfi srfi-14)` |
| `char-set:printing` | `(std srfi srfi-14)` |
| `char-set:punctuation` | `(std srfi srfi-14)`, `(std text char-set)` |
| `char-set:symbol` | `(std srfi srfi-14)` |
| `char-set:title-case` | `(std srfi srfi-14)` |
| `char-set:upper` | `(std text char-set)` |
| `char-set:upper-case` | `(std srfi srfi-14)` |
| `char-set:whitespace` | `(std srfi srfi-14)`, `(std text char-set)` |
| `char-set<=` | `(std srfi srfi-14)` |
| `char-set=` | `(std srfi srfi-14)` |
| `char-set?` | `(std srfi srfi-14)`, `(std text char-set)` |
| `chash` | `(std concur hash)` |
| `chash->list` | `(std concur hash)` |
| `chash-clear!` | `(std concur hash)` |
| `chash-for-each` | `(std concur hash)` |
| `chash-get` | `(std concur hash)` |
| `chash-key?` | `(std concur hash)` |
| `chash-keys` | `(std concur hash)` |
| `chash-merge!` | `(std concur hash)` |
| `chash-put!` | `(std concur hash)` |
| `chash-ref` | `(std concur hash)` |
| `chash-remove!` | `(std concur hash)` |
| `chash-size` | `(std concur hash)` |
| `chash-snapshot` | `(std concur hash)` |
| `chash-swap!` | `(std concur hash)` |
| `chash-update!` | `(std concur hash)` |
| `chash-values` | `(std concur hash)` |
| `chash?` | `(std concur hash)` |
| `check` | `(std test)` |
| `check-alerts!` | `(std security metrics)` |
| `check-argument` | `(std contract)` |
| `check-body-limits` | `(std net timeout)` |
| `check-breakpoints!` | `(std dev debug)` |
| `check-cancellation!` | `(std concur async-await)` |
| `check-capability!` | `(std security capability)` |
| `check-capability!/audit` | `(std security audit)` |
| `check-effect-signature` | `(std typed effect-typing)` |
| `check-effects!` | `(std typed effects)` |
| `check-eq?` | `(std test)` |
| `check-equal?` | `(std test)` |
| `check-eqv?` | `(std test)` |
| `check-error` | `(std test framework)` |
| `check-exception` | `(std test)` |
| `check-false` | `(std test framework)` |
| `check-flow!` | `(std security flow)` |
| `check-header-limits` | `(std net timeout)` |
| `check-not-eq?` | `(std test)` |
| `check-not-equal?` | `(std test)` |
| `check-not-eqv?` | `(std test)` |
| `check-not-tainted!` | `(std taint)` |
| `check-output` | `(std test)` |
| `check-posix` | `(std os posix)` |
| `check-posix/ptr` | `(std os posix)` |
| `check-pred` | `(std test framework)` |
| `check-predicate` | `(std test)` |
| `check-program-types` | `(std typed check)` |
| `check-property` | `(std proptest)`, `(std test check)`, `(std test framework)`, `(std test quickcheck)` |
| `check-property/test` | `(std proptest)` |
| `check-refinement!` | `(std typed advanced)`, `(std typed refine)` |
| `check-resource-leaks!` | `(std concur)` |
| `check-result` | `(std contract)`, `(std health)` |
| `check-result-duration` | `(std health)` |
| `check-result-message` | `(std health)` |
| `check-result-name` | `(std health)` |
| `check-result-status` | `(std health)` |
| `check-return-type!` | `(std typed)` |
| `check-row-type!` | `(std typed row2)` |
| `check-taint-label!` | `(std taint)` |
| `check-true` | `(std test framework)` |
| `check-type` | `(std typed infer)` |
| `check-type!` | `(std typed)` |
| `check-untainted!` | `(std security taint)` |
| `check-uri-limits` | `(std net timeout)` |
| `check=` | `(std test framework)` |
| `checkpoint-actor-mailbox` | `(std actor checkpoint)` |
| `checkpoint-age` | `(std actor checkpoint)` |
| `checkpoint-computation` | `(std persist closure)` |
| `checkpoint-manager-path` | `(std actor checkpoint)` |
| `checkpoint-manager-register!` | `(std actor checkpoint)` |
| `checkpoint-manager-restore` | `(std actor checkpoint)` |
| `checkpoint-manager-start!` | `(std actor checkpoint)` |
| `checkpoint-manager-stop!` | `(std actor checkpoint)` |
| `checkpoint-manager?` | `(std actor checkpoint)` |
| `checkpoint-serializable?` | `(std actor checkpoint)` |
| `checkpoint-value` | `(std actor checkpoint)` |
| `child-spec` | `(std proc supervisor)` |
| `child-spec-id` | `(std actor supervisor)`, `(std actor)`, `(std proc supervisor)` |
| `child-spec-max-restarts` | `(std proc supervisor)` |
| `child-spec-restart` | `(std actor supervisor)`, `(std actor)` |
| `child-spec-restart-type` | `(std proc supervisor)` |
| `child-spec-restart-window` | `(std proc supervisor)` |
| `child-spec-shutdown` | `(std actor supervisor)`, `(std actor)` |
| `child-spec-start-thunk` | `(std actor supervisor)`, `(std actor)` |
| `child-spec-thunk` | `(std proc supervisor)` |
| `child-spec-type` | `(std actor supervisor)`, `(std actor)` |
| `child-spec?` | `(std actor supervisor)`, `(std actor)`, `(std proc supervisor)` |
| `choice` | `(std event)`, `(std misc event)` |
| `choose` | `(std effect multishot)` |
| `chop` | `(thunderchez thunder-utils)` |
| `chunk` | `(std misc list-more)` |
| `cipher-block-size` | `(std crypto cipher)` |
| `cipher-iv-length` | `(std crypto cipher)` |
| `cipher-key-length` | `(std crypto cipher)` |
| `cipher-state-ctx` | `(std net ssh transport)` |
| `cipher-state-iv` | `(std net ssh transport)` |
| `cipher-state-key` | `(std net ssh transport)` |
| `cipher-state-mac-key` | `(std net ssh transport)` |
| `cipher-state-name` | `(std net ssh transport)` |
| `cipher-state?` | `(std net ssh transport)` |
| `circuit-breaker-call` | `(std misc retry)` |
| `circuit-breaker-reset!` | `(std misc retry)` |
| `circuit-breaker-state` | `(std misc retry)` |
| `circuit-breaker-stats` | `(std misc retry)` |
| `circuit-breaker?` | `(std circuit)`, `(std misc retry)` |
| `circuit-call` | `(std circuit)` |
| `circuit-closed?` | `(std circuit)` |
| `circuit-half-open?` | `(std circuit)` |
| `circuit-open?` | `(std circuit)` |
| `circuit-reset!` | `(std circuit)` |
| `circuit-state` | `(std circuit)` |
| `circuit-stats` | `(std circuit)` |
| `circular-generator` | `(std srfi srfi-121)`, `(std srfi srfi-158)` |
| `circular-list?` | `(std srfi srfi-1)` |
| `ck` | `(std misc ck-macros)` |
| `clamp` | `(std misc number)`, `(std misc numeric)` |
| `class-direct-methods` | `(std clos)` |
| `class-direct-slots` | `(std clos)` |
| `class-direct-subclasses` | `(std clos)` |
| `class-direct-superclasses` | `(std clos)` |
| `class-method` | `(std typed typeclass)` |
| `class-methods` | `(std clos)` |
| `class-name` | `(std clos)` |
| `class-of` | `(std clos)` |
| `class-precedence-list` | `(std clos)` |
| `class-slots` | `(std clos)` |
| `class-subclasses` | `(std clos)` |
| `classified-level` | `(std security flow)` |
| `classified-value` | `(std security flow)` |
| `classified?` | `(std security flow)` |
| `classify` | `(std security flow)` |
| `clear-agent-errors` | `(std agent)` |
| `clear-line` | `(std misc terminal)` |
| `clear-profile!` | `(std specialize)` |
| `clear-screen` | `(std misc terminal)` |
| `clear-specialization-cache!` | `(std compiler partial-eval)` |
| `clear-to-beginning` | `(std misc terminal)` |
| `clear-to-end` | `(std misc terminal)` |
| `clear-world!` | `(std image)` |
| `cli-cmd-description` | `(std cli multicall)` |
| `cli-cmd-name` | `(std cli multicall)` |
| `cli-commands` | `(std cli multicall)` |
| `cli-name` | `(std cli multicall)` |
| `cli-version` | `(std cli multicall)` |
| `client-error-classes` | `(std security errors)` |
| `client-error?` | `(std security errors)` |
| `clj-delay` | `(jerboa clojure)`, `(std clojure)` |
| `clj-force` | `(jerboa clojure)`, `(std clojure)` |
| `clj-future` | `(jerboa clojure)`, `(std clojure)` |
| `clj-index-of` | `(std clojure string)` |
| `clj-promise` | `(jerboa clojure)`, `(std clojure)` |
| `clj-thread` | `(std csp clj)` |
| `close!` | `(std csp clj)` |
| `close-btree` | `(std mmap-btree)` |
| `close-resource!` | `(std concur)` |
| `closure-arity` | `(std debug closure-inspect)` |
| `closure-free-variables` | `(std debug closure-inspect)` |
| `closure-load` | `(std persist closure)` |
| `closure-max-arity` | `(std debug closure-inspect)` |
| `closure-min-arity` | `(std debug closure-inspect)` |
| `closure-save` | `(std persist closure)` |
| `closure-set-free-variable!` | `(std debug closure-inspect)` |
| `closure-with` | `(std debug closure-inspect)` |
| `cluster-join!` | `(std actor cluster)` |
| `cluster-leave!` | `(std actor cluster)` |
| `cluster-node-by-name` | `(std actor cluster)` |
| `cluster-nodes` | `(std actor cluster)` |
| `cluster-policy-allowed-connections` | `(std actor cluster-security)` |
| `cluster-policy-auth-method` | `(std actor cluster-security)` |
| `cluster-policy-max-message-rate` | `(std actor cluster-security)` |
| `cluster-policy-max-message-size` | `(std actor cluster-security)` |
| `cluster-policy-node-roles` | `(std actor cluster-security)` |
| `cluster-policy-role-permissions` | `(std actor cluster-security)` |
| `cluster-policy?` | `(std actor cluster-security)` |
| `cluster-register!` | `(std actor distributed)` |
| `cluster-registered-names` | `(std actor distributed)` |
| `cluster-size` | `(std distributed)` |
| `cluster-whereis` | `(std actor distributed)` |
| `cluster?` | `(std distributed)` |
| `code-expr` | `(std quasiquote-types)` |
| `code-type` | `(std quasiquote-types)` |
| `code?` | `(std quasiquote-types)` |
| `col-max` | `(std dataframe)` |
| `col-mean` | `(std dataframe)` |
| `col-median` | `(std dataframe)` |
| `col-min` | `(std dataframe)` |
| `col-std` | `(std dataframe)` |
| `col-sum` | `(std dataframe)` |
| `collect` | `(std specter)` |
| `collect-one` | `(std specter)` |
| `collection->list` | `(std misc collection)` |
| `collection-any` | `(std misc collection)` |
| `collection-every` | `(std misc collection)` |
| `collection-filter` | `(std misc collection)` |
| `collection-find` | `(std misc collection)` |
| `collection-fold` | `(std misc collection)` |
| `collection-for-each` | `(std misc collection)` |
| `collection-length` | `(std misc collection)` |
| `collection-map` | `(std misc collection)` |
| `color-a` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `color-b` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `color-enabled?` | `(std cli style)` |
| `color-g` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `color-r` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `color?` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `command` | `(std cli getopt)` |
| `common-error-fixes` | `(std error-advice)` |
| `common-mime-types` | `(std mime types)` |
| `commute` | `(std stm)` |
| `comp` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc func)`, `(std prelude)` |
| `comp-navs` | `(std specter)` |
| `comparator-check-type` | `(std srfi srfi-128)` |
| `comparator-equality-predicate` | `(std srfi srfi-128)` |
| `comparator-hash` | `(std srfi srfi-128)` |
| `comparator-hash-function` | `(std srfi srfi-128)` |
| `comparator-hashable?` | `(std srfi srfi-128)` |
| `comparator-ordered?` | `(std srfi srfi-128)` |
| `comparator-ordering-predicate` | `(std srfi srfi-128)` |
| `comparator-test-type` | `(std srfi srfi-128)` |
| `comparator-type-test-predicate` | `(std srfi srfi-128)` |
| `comparator?` | `(std srfi srfi-128)` |
| `compare-and-set!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc atom)` |
| `compile-expr` | `(jerboa wasm codegen)` |
| `compile-file` | `(std compile)` |
| `compile-for-target` | `(jerboa build)`, `(std build cross)` |
| `compile-format` | `(std misc fmt)` |
| `compile-imported-libraries` | `(std compile)` |
| `compile-library` | `(std compile)` |
| `compile-modules-parallel` | `(jerboa build)` |
| `compile-program` | `(jerboa wasm codegen)`, `(std compile)` |
| `compile-query` | `(std db query-compile)` |
| `compile-regex` | `(std text regex-compile)` |
| `compile-regex-to-dfa` | `(std regex-ct)` |
| `compile-time-eval` | `(std compiler partial-eval)` |
| `compile-to-port` | `(std compile)` |
| `compile-whole-program` | `(std compile)` |
| `complement` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc func)`, `(std prelude)` |
| `completion-error!` | `(std misc completion)` |
| `completion-post!` | `(std misc completion)` |
| `completion-ready?` | `(std misc completion)` |
| `completion-wait!` | `(std misc completion)` |
| `completion?` | `(std misc completion)` |
| `component` | `(std component fiber)`, `(std component)` |
| `component-config` | `(std component fiber)`, `(std component)` |
| `component-deps` | `(std component fiber)`, `(std component)` |
| `component-hash` | `(std build sbom)` |
| `component-license` | `(std build sbom)` |
| `component-name` | `(std build sbom)`, `(std component fiber)`, `(std component)` |
| `component-started?` | `(std component fiber)`, `(std component)` |
| `component-state` | `(std component fiber)`, `(std component)` |
| `component-type` | `(std build sbom)` |
| `component-version` | `(std build sbom)` |
| `component?` | `(std build sbom)`, `(std component fiber)`, `(std component)` |
| `compose` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc func)`, `(std prelude)` |
| `compose-lens` | `(std lens)` |
| `compose-middleware` | `(std web rack)` |
| `compose-passes` | `(std compiler passes)` |
| `compose-transducers` | `(std transducer)` |
| `compose-xf` | `(std seq)` |
| `compose1` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc func)`, `(std prelude)` |
| `comptime` | `(std comptime)` |
| `comptime-cond` | `(std comptime)` |
| `comptime-define` | `(std comptime)` |
| `comptime-if` | `(std comptime)` |
| `comptime-table` | `(std comptime)` |
| `compute-applicable-methods` | `(std clos)` |
| `compute-cpl` | `(std clos)` |
| `compute-custom-prompt` | `(std repl middleware)` |
| `compute-effective-method` | `(std clos)` |
| `compute-file-hash` | `(jerboa build)` |
| `compute-get-n-set` | `(std clos)` |
| `compute-only-filter` | `(std security seccomp)` |
| `compute-slot-accessors` | `(std clos)` |
| `compute-slots` | `(std clos)` |
| `concatenate` | `(std srfi srfi-1)` |
| `concatenate!` | `(std srfi srfi-1)` |
| `concurrent-hash` | `(std concur hash)` |
| `concurrent-hash->list` | `(std concur hash)` |
| `concurrent-hash-clear!` | `(std concur hash)` |
| `concurrent-hash-for-each` | `(std concur hash)` |
| `concurrent-hash-get` | `(std concur hash)` |
| `concurrent-hash-key?` | `(std concur hash)` |
| `concurrent-hash-keys` | `(std concur hash)` |
| `concurrent-hash-merge!` | `(std concur hash)` |
| `concurrent-hash-put!` | `(std concur hash)` |
| `concurrent-hash-ref` | `(std concur hash)` |
| `concurrent-hash-remove!` | `(std concur hash)` |
| `concurrent-hash-size` | `(std concur hash)` |
| `concurrent-hash-snapshot` | `(std concur hash)` |
| `concurrent-hash-swap!` | `(std concur hash)` |
| `concurrent-hash-update!` | `(std concur hash)` |
| `concurrent-hash-values` | `(std concur hash)` |
| `concurrent-hash?` | `(std concur hash)` |
| `cond->` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std sugar)` |
| `cond->>` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std sugar)` |
| `cond-path` | `(std specter)` |
| `cond/t` | `(std typed advanced)` |
| `conda` | `(jerboa clojure)`, `(std logic)` |
| `conde` | `(jerboa clojure)`, `(std logic)` |
| `condition-variable-broadcast!` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `condition-variable-signal!` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `condition-variable-specific` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `condition-variable-specific-set!` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `condition-variable?` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `condu` | `(jerboa clojure)`, `(std logic)` |
| `config->alist` | `(std misc config)` |
| `config-from-file` | `(std misc config)` |
| `config-get` | `(std config)` |
| `config-keys` | `(std misc config)` |
| `config-merge` | `(std misc config)` |
| `config-merge!` | `(std config)` |
| `config-ref` | `(std config)`, `(std misc config)` |
| `config-ref*` | `(std config)` |
| `config-ref/default` | `(std misc config)` |
| `config-schema` | `(std config)` |
| `config-set` | `(std misc config)` |
| `config-set!` | `(std config)` |
| `config-subsection` | `(std misc config)` |
| `config-valid?` | `(std config)` |
| `config-verify` | `(std misc config)` |
| `config?` | `(std config)`, `(std misc config)` |
| `conj` | `(jerboa clojure)`, `(std clojure)` |
| `conj!` | `(jerboa clojure)`, `(std clojure)` |
| `conjoin` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc func)`, `(std prelude)` |
| `conn-pool-acquire!` | `(std net connpool)` |
| `conn-pool-close!` | `(std net connpool)` |
| `conn-pool-discard!` | `(std net connpool)` |
| `conn-pool-release!` | `(std net connpool)` |
| `conn-pool-size` | `(std net connpool)` |
| `conn-pool?` | `(std net connpool)` |
| `conn-read` | `(std net ssl)` |
| `conn-wrap` | `(std net ssl)` |
| `conn-write` | `(std net ssl)` |
| `conn-write-string` | `(std net ssl)` |
| `connection-allowed?` | `(std actor cluster-security)` |
| `connection-pool?` | `(std net pool)` |
| `connection-refused?` | `(jerboa prelude safe)`, `(std error conditions)` |
| `connection-timeout-seconds` | `(std error conditions)` |
| `connection-timeout?` | `(jerboa prelude safe)`, `(std error conditions)` |
| `cons*` | `(jerboa clojure)`, `(jerboa runtime)`, `(std clojure)` |
| `conso` | `(jerboa clojure)`, `(std logic)` |
| `constant-fold` | `(std staging2)` |
| `constantly` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc func)`, `(std prelude)` |
| `constraint-args` | `(std typed solver)` |
| `constraint-pred` | `(std typed solver)` |
| `constraint-satisfied?` | `(jerboa pkg)` |
| `constraint?` | `(std typed solver)` |
| `consume` | `(std borrow)` |
| `contains?` | `(jerboa clojure)`, `(std clojure)` |
| `content-hash` | `(std build reproducible)`, `(std build)`, `(std content-address)` |
| `content-hash-string` | `(std build reproducible)` |
| `context->list` | `(std error context)` |
| `context->string` | `(std error context)` |
| `context-add-func!` | `(jerboa wasm codegen)` |
| `context-add-local!` | `(jerboa wasm codegen)` |
| `context-block-depth` | `(jerboa wasm codegen)` |
| `context-condition-chain` | `(std error context)` |
| `context-condition?` | `(std error context)` |
| `context-func-index` | `(jerboa wasm codegen)` |
| `context-local-index` | `(jerboa wasm codegen)` |
| `context-pop-block!` | `(jerboa wasm codegen)` |
| `context-push-block!` | `(jerboa wasm codegen)` |
| `continuation->frames` | `(std error diagnostics)` |
| `continuation-mark-set->list` | `(std misc cont-marks)` |
| `continuation-mark-set-first` | `(std misc cont-marks)` |
| `continuation-marks->list` | `(std control marks)` |
| `continuation-marks?` | `(std misc cont-marks)` |
| `contract-violation-message` | `(std contract)` |
| `contract-violation-who` | `(std contract)` |
| `contract-violation?` | `(std contract)` |
| `control` | `(std control delimited)` |
| `control-at` | `(std control delimited)` |
| `coprime?` | `(std misc prime)` |
| `copy-bit` | `(std srfi srfi-151)` |
| `copy-file` | `(jerboa core)`, `(std gambit-compat)`, `(std os path-util)` |
| `coroutine-done?` | `(std control coroutine)` |
| `coroutine-state` | `(std control coroutine)` |
| `coroutine-transfer` | `(std control coroutine)` |
| `coroutine?` | `(std control coroutine)` |
| `count` | `(jerboa clojure)`, `(std clojure)`, `(std srfi srfi-1)` |
| `count-accumulator` | `(std srfi srfi-158)` |
| `count-resumes` | `(std dev cont-mark-opt)` |
| `count-window-add!` | `(std stream window)` |
| `counter-add!` | `(std metrics)` |
| `counter-inc!` | `(std metrics)` |
| `counter-value` | `(std metrics)` |
| `counter?` | `(std metrics)` |
| `cp0-pass-description` | `(std compiler passes)` |
| `cp0-pass-description-set!` | `(std compiler passes)` |
| `cp0-pass-enabled` | `(std compiler passes)` |
| `cp0-pass-enabled-set!` | `(std compiler passes)` |
| `cp0-pass-name` | `(std compiler passes)` |
| `cp0-pass-name-set!` | `(std compiler passes)` |
| `cp0-pass-priority` | `(std compiler passes)` |
| `cp0-pass-priority-set!` | `(std compiler passes)` |
| `cp0-pass-transformer` | `(std compiler passes)` |
| `cp0-pass-transformer-set!` | `(std compiler passes)` |
| `cp0-pass?` | `(std compiler passes)` |
| `cprintf` | `(std text printf)` |
| `cpu-count` | `(jerboa prelude)`, `(std actor scheduler)`, `(std actor)`, `(std gambit-compat)` |
| `create-directory` | `(jerboa core)`, `(std gambit-compat)` |
| `create-directory*` | `(jerboa core)`, `(std gambit-compat)` |
| `create-temporary-file` | `(std os temporaries)` |
| `cross-compiler-available?` | `(std build cross)` |
| `cross-config-cc` | `(jerboa cross)`, `(std build cross)` |
| `cross-config-cflags` | `(jerboa cross)` |
| `cross-config-extra-flags` | `(std build cross)` |
| `cross-config-host` | `(std build cross)` |
| `cross-config-sysroot` | `(jerboa cross)`, `(std build cross)` |
| `cross-config-target` | `(std build cross)` |
| `cross-config-target-arch` | `(jerboa cross)` |
| `cross-config-target-os` | `(jerboa cross)` |
| `cross-config-valid?` | `(jerboa cross)` |
| `cross-config?` | `(jerboa cross)`, `(std build cross)` |
| `cross-target-ar` | `(jerboa build)` |
| `cross-target-arch` | `(jerboa build)` |
| `cross-target-cc` | `(jerboa build)` |
| `cross-target-os` | `(jerboa build)` |
| `cross-target?` | `(jerboa build)` |
| `crypto-error-string` | `(std crypto etc)` |
| `csp-header` | `(std net security-headers)` |
| `csp-run` | `(std csp)` |
| `csv->alists` | `(jerboa clojure)`, `(jerboa prelude)`, `(std csv)`, `(std prelude)` |
| `csv-port->rows` | `(jerboa clojure)`, `(jerboa prelude)`, `(std csv)`, `(std prelude)` |
| `csv-read` | `(std text csv)` |
| `csv-write` | `(std text csv)` |
| `ct` | `(std dev partial-eval)` |
| `ct-constant-expr?` | `(std dev partial-eval)` |
| `ct-env-reset!` | `(std dev partial-eval)` |
| `ct-literal?` | `(std dev partial-eval)` |
| `ct/try` | `(std dev partial-eval)` |
| `cts-cancel!` | `(std concur async-await)` |
| `cts-token` | `(std concur async-await)` |
| `curl-easy-cleanup` | `(std ffi curl)`, `(thunderchez curl)` |
| `curl-easy-init` | `(std ffi curl)`, `(thunderchez curl)` |
| `curl-easy-perform` | `(std ffi curl)`, `(thunderchez curl)` |
| `curl-easy-setopt/function` | `(std ffi curl)`, `(thunderchez curl)` |
| `curl-easy-setopt/long` | `(std ffi curl)`, `(thunderchez curl)` |
| `curl-easy-setopt/object` | `(std ffi curl)`, `(thunderchez curl)` |
| `curl-easy-setopt/offset` | `(std ffi curl)`, `(thunderchez curl)` |
| `curl-easy-setopt/scheme-object` | `(std ffi curl)`, `(thunderchez curl)` |
| `curl-easy-setopt/string` | `(std ffi curl)`, `(thunderchez curl)` |
| `curl-global-init` | `(std ffi curl)`, `(thunderchez curl)` |
| `curl-read-callback` | `(std ffi curl)`, `(thunderchez curl)` |
| `curl-slist-append` | `(std ffi curl)`, `(thunderchez curl)` |
| `curl-slist-free-all` | `(std ffi curl)`, `(thunderchez curl)` |
| `curl-write-callback` | `(std ffi curl)`, `(thunderchez curl)` |
| `curl_slist` | `(std ffi curl)`, `(thunderchez curl)` |
| `current-app-name` | `(std app)` |
| `current-capabilities` | `(std security capability)` |
| `current-config` | `(std misc config)` |
| `current-context` | `(std error context)` |
| `current-continuation-marks` | `(std control marks)`, `(std misc cont-marks)` |
| `current-custodian` | `(std misc custodian)` |
| `current-date` | `(std srfi srfi-19)` |
| `current-declassify-handler` | `(std security flow)` |
| `current-diagnostic-handler` | `(std error diagnostics)` |
| `current-fiber` | `(std fiber)` |
| `current-fiber-runtime` | `(std fiber)` |
| `current-log-directory` | `(std logger)` |
| `current-logger` | `(std log)`, `(std logger)` |
| `current-logger-options` | `(std logger)` |
| `current-node` | `(std actor cluster)` |
| `current-node-id` | `(std actor transport)` |
| `current-platform` | `(std build cross)` |
| `current-recording` | `(std dev debug)` |
| `current-representation-options` | `(std misc repr)` |
| `current-route-params` | `(std net fiber-httpd)` |
| `current-scheduler` | `(std actor scheduler)`, `(std actor)`, `(std sched)` |
| `current-second` | `(std gambit-compat)` |
| `current-span` | `(std span)` |
| `current-stack-frames` | `(std debug inspector)` |
| `current-thread` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `current-time` | `(std srfi srfi-19)` |
| `current-timestamp` | `(std time)` |
| `current-unix-time` | `(std time)` |
| `curry` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc func)`, `(std prelude)` |
| `curryn` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc func)`, `(std prelude)` |
| `cursor-back` | `(std misc terminal)` |
| `cursor-down` | `(std misc terminal)` |
| `cursor-forward` | `(std misc terminal)` |
| `cursor-hide` | `(std misc terminal)` |
| `cursor-position` | `(std misc terminal)` |
| `cursor-restore` | `(std misc terminal)` |
| `cursor-save` | `(std misc terminal)` |
| `cursor-show` | `(std misc terminal)` |
| `cursor-up` | `(std misc terminal)` |
| `custodian-managed-list` | `(std misc custodian)` |
| `custodian-open-input-file` | `(std misc custodian)` |
| `custodian-open-output-file` | `(std misc custodian)` |
| `custodian-register!` | `(std misc custodian)` |
| `custodian-shutdown-all` | `(std misc custodian)` |
| `custodian?` | `(std misc custodian)` |
| `cut` | `(jerboa clojure)`, `(jerboa prelude)`, `(std gambit-compat)`, `(std prelude)`, ... (+1) |
| `cute` | `(jerboa clojure)`, `(jerboa prelude)`, `(std gambit-compat)`, `(std prelude)`, ... (+1) |
| `cyan` | `(std cli style)` |
| `cycle` | `(jerboa clojure)`, `(std clojure)` |

### <a name="idx-d"></a>d

| Symbol | Modules |
| --- | --- |
| `DUCKDB_BLOB` | `(std db duckdb-native)`, `(std db duckdb)` |
| `DUCKDB_BOOLEAN` | `(std db duckdb-native)`, `(std db duckdb)` |
| `DUCKDB_FLOAT` | `(std db duckdb-native)`, `(std db duckdb)` |
| `DUCKDB_INTEGER` | `(std db duckdb-native)`, `(std db duckdb)` |
| `DUCKDB_NULL` | `(std db duckdb-native)`, `(std db duckdb)` |
| `DUCKDB_TEXT` | `(std db duckdb-native)`, `(std db duckdb)` |
| `Datafiable` | `(jerboa clojure)`, `(std datafy)` |
| `dag-add-edge!` | `(std misc dag)` |
| `dag-add-node!` | `(std misc dag)` |
| `dag-edges` | `(std misc dag)` |
| `dag-has-cycle?` | `(std misc dag)` |
| `dag-neighbors` | `(std misc dag)` |
| `dag-nodes` | `(std misc dag)` |
| `dag-predecessors` | `(std misc dag)` |
| `dag-reachable` | `(std misc dag)` |
| `dag-sinks` | `(std misc dag)` |
| `dag-sources` | `(std misc dag)` |
| `dag?` | `(std misc dag)` |
| `dataframe->alists` | `(std dataframe)` |
| `dataframe->csv-string` | `(std dataframe)` |
| `dataframe->vectors` | `(std dataframe)` |
| `dataframe-append` | `(std dataframe)` |
| `dataframe-column` | `(std dataframe)` |
| `dataframe-columns` | `(std dataframe)` |
| `dataframe-count` | `(std dataframe)` |
| `dataframe-describe` | `(std dataframe)` |
| `dataframe-display` | `(std dataframe)` |
| `dataframe-drop` | `(std dataframe)` |
| `dataframe-filter` | `(std dataframe)` |
| `dataframe-from-alists` | `(std dataframe)` |
| `dataframe-from-csv-string` | `(std dataframe)` |
| `dataframe-from-vectors` | `(std dataframe)` |
| `dataframe-group-by` | `(std dataframe)` |
| `dataframe-head` | `(std dataframe)` |
| `dataframe-join` | `(std dataframe)` |
| `dataframe-left-join` | `(std dataframe)` |
| `dataframe-map` | `(std dataframe)` |
| `dataframe-mutate` | `(std dataframe)` |
| `dataframe-ncol` | `(std dataframe)` |
| `dataframe-nrow` | `(std dataframe)` |
| `dataframe-ref` | `(std dataframe)` |
| `dataframe-rename` | `(std dataframe)` |
| `dataframe-row` | `(std dataframe)` |
| `dataframe-select` | `(std dataframe)` |
| `dataframe-sort` | `(std dataframe)` |
| `dataframe-summarize` | `(std dataframe)` |
| `dataframe-tail` | `(std dataframe)` |
| `dataframe?` | `(std dataframe)` |
| `datafy` | `(jerboa clojure)`, `(std datafy)` |
| `datalog-assert!` | `(std datalog)` |
| `datalog-clear!` | `(std datalog)` |
| `datalog-facts` | `(std datalog)` |
| `datalog-query` | `(std datalog)` |
| `datalog-retract!` | `(std datalog)` |
| `datalog-rule!` | `(std datalog)` |
| `datalog-rules` | `(std datalog)` |
| `datasource-data` | `(std query)` |
| `datasource?` | `(std query)` |
| `date->string` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)`, ... (+1) |
| `date->string*` | `(std gambit-compat)` |
| `date->time-utc` | `(std srfi srfi-19)` |
| `date-day` | `(std srfi srfi-19)` |
| `date-hour` | `(std srfi srfi-19)` |
| `date-minute` | `(std srfi srfi-19)` |
| `date-month` | `(std srfi srfi-19)` |
| `date-nanosecond` | `(std srfi srfi-19)` |
| `date-second` | `(std srfi srfi-19)` |
| `date-week-day` | `(std srfi srfi-19)` |
| `date-year` | `(std srfi srfi-19)` |
| `date-zone-offset` | `(std srfi srfi-19)` |
| `date?` | `(std srfi srfi-19)` |
| `datetime->alist` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime->epoch` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime->iso8601` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime->julian` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime->string` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-add` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-clamp` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-day` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-diff` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-floor-day` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-floor-hour` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-floor-month` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-hour` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-max` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-min` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-minute` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-month` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-nanosecond` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-now` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-offset` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-second` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-subtract` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-truncate` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-utc-now` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime-year` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime<=?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime<?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime=?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime>=?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime>?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datetime?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `datum->stx` | `(std stxutil)` |
| `day-of-week` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `day-of-year` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `days-in-month` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `db-connection-error?` | `(jerboa prelude safe)`, `(std error conditions)` |
| `db-constraint-violation-constraint` | `(std error conditions)` |
| `db-constraint-violation?` | `(jerboa prelude safe)`, `(std error conditions)` |
| `db-error-backend` | `(std error conditions)` |
| `db-error?` | `(jerboa prelude safe)`, `(std error conditions)`, `(std safe)` |
| `db-query-error-sql` | `(std error conditions)` |
| `db-query-error?` | `(jerboa prelude safe)`, `(std error conditions)` |
| `db-timeout-seconds` | `(std error conditions)` |
| `db-timeout?` | `(std error conditions)` |
| `dbi-bind` | `(std db dbi)` |
| `dbi-close` | `(std db dbi)` |
| `dbi-columns` | `(std db dbi)` |
| `dbi-connect` | `(std db dbi)` |
| `dbi-connection?` | `(std db dbi)` |
| `dbi-driver-register!` | `(std db dbi)` |
| `dbi-drivers` | `(std db dbi)` |
| `dbi-exec` | `(std db dbi)` |
| `dbi-prepare` | `(std db dbi)` |
| `dbi-query` | `(std db dbi)` |
| `dbi-step` | `(std db dbi)` |
| `dbi-with-transaction` | `(std db dbi)` |
| `dead-code-elim` | `(std staging2)` |
| `deadlock-check!` | `(std concur)` |
| `deadlock-checked-channel-get` | `(std concur deadlock)` |
| `deadlock-checked-mutex-lock!` | `(std concur deadlock)` |
| `deadlock-checked-mutex-unlock!` | `(std concur deadlock)` |
| `deadlock-condition-cycle` | `(std concur deadlock)` |
| `deadlock-condition?` | `(std concur deadlock)` |
| `deadlock-detection-report` | `(std concur deadlock)` |
| `deadlock?` | `(std concur deadlock)` |
| `debug-current-frame` | `(std dev debug)` |
| `debug-forward` | `(std dev debug)` |
| `debug-frame-count` | `(std dev debug)` |
| `debug-goto` | `(std dev debug)` |
| `debug-history` | `(std dev debug)` |
| `debug-inspect` | `(std dev debug)` |
| `debug-locals` | `(std dev debug)` |
| `debug-print-frame` | `(std dev debug)` |
| `debug-rewind` | `(std dev debug)` |
| `debug-step` | `(std dev debug)` |
| `debug-summary` | `(std dev debug)` |
| `debugf` | `(std logger)` |
| `dec` | `(jerboa clojure)`, `(std clojure)` |
| `decimal*` | `(std misc decimal)` |
| `decimal+` | `(std misc decimal)` |
| `decimal-` | `(std misc decimal)` |
| `decimal->inexact` | `(std misc decimal)` |
| `decimal->string` | `(std misc decimal)` |
| `decimal-abs` | `(std misc decimal)` |
| `decimal-negative?` | `(std misc decimal)` |
| `decimal-round` | `(std misc decimal)` |
| `decimal-truncate` | `(std misc decimal)` |
| `decimal-zero?` | `(std misc decimal)` |
| `decimal/` | `(std misc decimal)` |
| `decimal<` | `(std misc decimal)` |
| `decimal<=` | `(std misc decimal)` |
| `decimal=` | `(std misc decimal)` |
| `decimal>` | `(std misc decimal)` |
| `decimal>=` | `(std misc decimal)` |
| `decimal?` | `(std misc decimal)` |
| `declassify` | `(std security flow)` |
| `decode-f32` | `(jerboa wasm format)` |
| `decode-f64` | `(jerboa wasm format)` |
| `decode-i32-leb128` | `(jerboa wasm format)` |
| `decode-i64-leb128` | `(jerboa wasm format)` |
| `decode-keys` | `(thunderchez thunder-utils)` |
| `decode-string` | `(jerboa wasm format)` |
| `decode-u32-leb128` | `(jerboa wasm format)` |
| `decrypt` | `(std crypto cipher)` |
| `decrypt-final!` | `(std crypto cipher)` |
| `decrypt-init!` | `(std crypto cipher)` |
| `decrypt-update!` | `(std crypto cipher)` |
| `dedupe-xf` | `(std seq)` |
| `deduplicate` | `(std transducer)` |
| `deep-clone` | `(std clos)` |
| `def` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+3) |
| `def*` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+3) |
| `def-dynamic` | `(jerboa clojure)`, `(std clojure)` |
| `default` | `(std csp clj)`, `(std csp select)`, `(std select)` |
| `default-fuel` | `(std actor engine)` |
| `default-hash` | `(std srfi srfi-128)` |
| `default-http-limits` | `(std net timeout)` |
| `default-linter` | `(std lint)` |
| `default-mailbox-config` | `(std actor bounded)` |
| `default-registry` | `(std metrics)` |
| `default-representation-options` | `(std misc repr)` |
| `default-scheduler` | `(std actor scheduler)`, `(std actor)` |
| `default-security-headers` | `(std net security-headers)` |
| `default-service-config` | `(std service config)` |
| `default-theme` | `(std misc highlight)` |
| `default-timeout-config` | `(std net timeout)` |
| `default-tls-config` | `(std net tls)` |
| `default-transforms` | `(jerboa translator)` |
| `defclass` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+3) |
| `defeffect` | `(std effect)` |
| `defeffect-nondet` | `(std effect multishot)` |
| `defgeneric` | `(std generic)` |
| `define-active-pattern` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude)`, `(std match2)`, ... (+1) |
| `define-advisable` | `(std misc advice)` |
| `define-application` | `(std app)` |
| `define-async` | `(std concur async-await)` |
| `define-benchmark` | `(std dev benchmark)` |
| `define-binary-array` | `(std misc binary-type)` |
| `define-binary-record` | `(std misc binary-type)` |
| `define-binary-struct` | `(std binary)` |
| `define-binary-type` | `(std misc binary-type)` |
| `define-c-lambda` | `(jerboa clojure)`, `(jerboa ffi)`, `(jerboa prelude clean)`, `(jerboa prelude)`, ... (+1) |
| `define-c-library` | `(std foreign bind)` |
| `define-callback` | `(std foreign)` |
| `define-class` | `(std clos)`, `(std typed typeclass)` |
| `define-cli` | `(std cli multicall)` |
| `define-collection` | `(std misc collection)` |
| `define-comptime` | `(std comptime)` |
| `define-const` | `(std foreign)` |
| `define-cp0-pass` | `(std compiler passes)` |
| `define-ct` | `(std dev partial-eval)` |
| `define-deprecated` | `(std deprecation)` |
| `define-derivation` | `(std derive)` |
| `define-devirt-dispatch` | `(std dev devirt)` |
| `define-effect-signature` | `(std typed effect-typing)` |
| `define-enum` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std sugar)` |
| `define-enumeration*` | `(thunderchez ffi-utils)` |
| `define-error-advice` | `(std error-advice)` |
| `define-error-class` | `(std security errors)` |
| `define-ffi-library` | `(std foreign)` |
| `define-flags` | `(thunderchez ffi-utils)` |
| `define-foreign` | `(std foreign)` |
| `define-foreign-struct` | `(std foreign)` |
| `define-foreign-type` | `(std foreign)` |
| `define-foreign/async` | `(std foreign bind)` |
| `define-foreign/check` | `(std foreign)` |
| `define-ftype` | `(std ftype)` |
| `define-ftype-allocator` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `define-function` | `(thunderchez ffi-utils)` |
| `define-gadt` | `(std typed gadt)` |
| `define-generic` | `(std clos)` |
| `define-grammar` | `(std peg)` |
| `define-instance` | `(std misc typeclass)`, `(std typed typeclass)` |
| `define-json-schema` | `(std text json-schema)` |
| `define-linear` | `(std typed linear)` |
| `define-match-type` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude)`, `(std match2)`, ... (+1) |
| `define-memoized` | `(std misc memoize)` |
| `define-method` | `(std clos)` |
| `define-method-combination` | `(std clos)` |
| `define-model-test` | `(std proptest)` |
| `define-persistent-class` | `(std odb)` |
| `define-pgo-module` | `(std compiler pgo)` |
| `define-phantom-protocol` | `(std typed phantom)` |
| `define-phantom-type` | `(std typed phantom)` |
| `define-posix` | `(std os posix)` |
| `define-profiled` | `(std misc profile)` |
| `define-protocol` | `(std derive2)` |
| `define-protocol/tc` | `(std contract2)` |
| `define-query` | `(std db query-compile)` |
| `define-record-type` | `(std srfi srfi-9)` |
| `define-regex` | `(std regex-ct)`, `(std text regex-compile)` |
| `define-rpc` | `(std net grpc)` |
| `define-rule` | `(std parser defparser)` |
| `define-rx` | `(jerboa clojure)`, `(jerboa prelude)`, `(std rx)` |
| `define-sanitizer` | `(std taint)` |
| `define-sdl-func` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `define-sealed-hierarchy` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude)`, `(std match2)`, ... (+1) |
| `define-service` | `(std net grpc)` |
| `define-sink` | `(std taint)` |
| `define-specialized` | `(std compiler partial-eval)` |
| `define-staged` | `(std staging2)` |
| `define-staging-type` | `(std staging)` |
| `define-test-suite` | `(std test framework)` |
| `define-type-alias` | `(std macro-types)` |
| `define-typeclass` | `(std misc typeclass)` |
| `define-typed-macro` | `(std macro-types)` |
| `define-values` | `(jerboa clojure)`, `(jerboa prelude)`, `(std sugar)` |
| `define/cap` | `(std security capability-typed)` |
| `define/cas` | `(std content-address)` |
| `define/contract` | `(std contract)` |
| `define/ct` | `(std staging)`, `(std typed check)` |
| `define/doc` | `(std doc)` |
| `define/keys` | `(thunderchez thunder-utils)` |
| `define/optional` | `(thunderchez thunder-utils)` |
| `define/pe` | `(std compiler partial-eval)` |
| `define/profile` | `(std compiler pgo)` |
| `define/profiled` | `(std dev profile)` |
| `define/r` | `(std typed refine)` |
| `define/row` | `(std typed row2)` |
| `define/t` | `(std typed)` |
| `define/tc` | `(std typed advanced)` |
| `define/te` | `(std typed effects)`, `(std typed)` |
| `definterface` | `(std interface)` |
| `deflate-bytevector` | `(std compress zlib)` |
| `deflexer` | `(std parser deflexer)` |
| `deflogger` | `(std logger)` |
| `defmemo` | `(std misc memo)` |
| `defmessage` | `(std protobuf macros)` |
| `defmethod` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `defmethod/tracked` | `(std dev devirt)` |
| `defmulti` | `(std multi)` |
| `defn` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std sugar)` |
| `defparser` | `(std parser defparser)` |
| `defproperty` | `(std proptest)` |
| `defprotocol` | `(std actor protocol)`, `(std actor)`, `(std protocol)` |
| `defprotocol-hkt` | `(std typed hkt)` |
| `defrecord` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std sugar)` |
| `defrow` | `(std typed advanced)` |
| `defrule` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+3) |
| `defrule/guard` | `(std staging)` |
| `defrule/rec` | `(std staging)` |
| `defrules` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+3) |
| `defspecific` | `(std generic)` |
| `defstruct` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+3) |
| `defstruct/d` | `(std derive)` |
| `defstruct/foreign` | `(std foreign bind)` |
| `defstruct/immutable` | `(std concur)` |
| `defstruct/thread-local` | `(std concur)` |
| `defstruct/thread-safe` | `(std concur)` |
| `defvariant` | `(std variant)` |
| `delay` | `(std lazy)` |
| `delay?` | `(jerboa clojure)`, `(std clojure)` |
| `delegation-token-capability-type` | `(std actor cluster-security)` |
| `delegation-token-expiry` | `(std actor cluster-security)` |
| `delegation-token-permissions` | `(std actor cluster-security)` |
| `delegation-token-target-node` | `(std actor cluster-security)` |
| `delegation-token?` | `(std actor cluster-security)` |
| `delete` | `(jerboa core)`, `(std gambit-compat)`, `(std srfi srfi-1)` |
| `delete!` | `(std srfi srfi-1)` |
| `delete-duplicates` | `(std srfi srfi-1)` |
| `delete-duplicates!` | `(std srfi srfi-1)` |
| `delete-duplicates/hash` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `delete-old-checkpoints` | `(std actor checkpoint)` |
| `deliver` | `(jerboa clojure)`, `(std clojure)` |
| `demonitor-node` | `(std actor distributed)` |
| `dep-graph-add!` | `(std build watch)` |
| `dep-graph-clean!` | `(std build watch)` |
| `dep-graph-dependencies` | `(std build watch)` |
| `dep-graph-dependents` | `(std build watch)` |
| `dep-graph-dirty!` | `(std build watch)` |
| `dep-graph-dirty-set` | `(std build watch)` |
| `dep-graph-dirty?` | `(std build watch)` |
| `dep-graph-topo-sort` | `(std build watch)` |
| `dep-graph?` | `(std build watch)` |
| `dep-name` | `(jerboa pkg)` |
| `dep-version-constraint` | `(jerboa pkg)` |
| `dep?` | `(jerboa pkg)` |
| `dependency-order` | `(jerboa pkg)` |
| `deprecated` | `(std deprecation)` |
| `deprecation-warning-handler` | `(std deprecation)` |
| `deque->list` | `(std misc deque)` |
| `deque-clear!` | `(std misc deque)` |
| `deque-empty?` | `(std actor deque)`, `(std misc deque)` |
| `deque-filter` | `(std misc deque)` |
| `deque-for-each` | `(std misc deque)` |
| `deque-map` | `(std misc deque)` |
| `deque-peek-back` | `(std misc deque)` |
| `deque-peek-front` | `(std misc deque)` |
| `deque-pop-back!` | `(std misc deque)` |
| `deque-pop-bottom!` | `(std actor deque)` |
| `deque-pop-front!` | `(std misc deque)` |
| `deque-push-back!` | `(std misc deque)` |
| `deque-push-bottom!` | `(std actor deque)` |
| `deque-push-front!` | `(std misc deque)` |
| `deque-size` | `(std actor deque)`, `(std misc deque)` |
| `deque-steal-top!` | `(std actor deque)` |
| `deque?` | `(std misc deque)` |
| `dequeue!` | `(std misc queue)` |
| `deref` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc atom)` |
| `derive!` | `(std derive)` |
| `derive-all` | `(std derive2)` |
| `derive-printer` | `(std staging)` |
| `derive-serializer` | `(std staging)` |
| `describe` | `(std clos)` |
| `describe-value` | `(std repl)` |
| `deserialize-message` | `(std actor distributed)` |
| `deserialize-value` | `(std actor checkpoint)` |
| `detect-all-deps` | `(std build sbom)` |
| `detect-c-deps` | `(std build sbom)` |
| `detect-deadlock` | `(std concur deadlock)` |
| `detect-host-config` | `(jerboa cross)` |
| `detect-platform` | `(std build cross)` |
| `detect-rust-deps` | `(std build sbom)` |
| `detect-scheme-deps` | `(std build sbom)` |
| `devirt-call` | `(std dev devirt)` |
| `dfa->scheme` | `(std regex-ct-impl)` |
| `dfa-dot` | `(std regex-ct)` |
| `dfa-state-count` | `(std regex-ct)` |
| `dfn` | `(jerboa clojure)`, `(std clojure)` |
| `dh-2048-modp` | `(std crypto dh)` |
| `dh-compute-shared` | `(std crypto dh)` |
| `dh-generate-key` | `(std crypto dh)` |
| `dh-generate-parameters` | `(std crypto dh)` |
| `dh-key-private` | `(std crypto dh)` |
| `dh-key-public` | `(std crypto dh)` |
| `dh-key?` | `(std crypto dh)` |
| `dh-params-g` | `(std crypto dh)` |
| `dh-params-p` | `(std crypto dh)` |
| `dh-params?` | `(std crypto dh)` |
| `diagnostic-context` | `(std error diagnostics)` |
| `diagnostic-frames` | `(std error diagnostics)` |
| `diagnostic?` | `(std error diagnostics)` |
| `die` | `(std cli print-exit)` |
| `diff` | `(std misc diff)` |
| `diff->string` | `(std misc diff)` |
| `diff-apply` | `(std text diff)` |
| `diff-lines` | `(std text diff)` |
| `diff-report` | `(std misc diff)` |
| `diff-strings` | `(std misc diff)`, `(std text diff)` |
| `diff-summary` | `(std text diff)` |
| `diff-unified` | `(std text diff)` |
| `difference` | `(jerboa clojure)`, `(std clojure)` |
| `digest->hex-string` | `(std crypto digest)` |
| `digest->u8vector` | `(std crypto digest)` |
| `dim` | `(std cli style)`, `(std misc terminal)` |
| `directory-exists?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std os path-util)` |
| `directory-files` | `(jerboa core)`, `(std gambit-compat)`, `(std os path-util)` |
| `directory-files*` | `(std gambit-compat)` |
| `directory-files-recursive` | `(std os path-util)` |
| `directory-hash` | `(std build verify)` |
| `disable-auto-specialization!` | `(std compiler partial-eval)` |
| `disable-colors!` | `(std cli style)` |
| `disable-pass-debug!` | `(std compiler passes)` |
| `discharge-effect` | `(std typed effects)` |
| `discover-modules` | `(std build)` |
| `disj` | `(jerboa clojure)`, `(std clojure)` |
| `disjoin` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc func)`, `(std prelude)` |
| `dispatch-custom-command` | `(std repl middleware)` |
| `dispatch-named-generic` | `(std clos)` |
| `display-continuation-backtrace` | `(jerboa core)`, `(std gambit-compat)` |
| `display-diagnostic` | `(std error diagnostics)` |
| `display-exception` | `(jerboa core)`, `(std gambit-compat)` |
| `display-profile` | `(std debug flamegraph)` |
| `display-separated` | `(std misc repr)` |
| `displayed` | `(std srfi srfi-159)` |
| `displayln` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `dissoc` | `(jerboa clojure)`, `(std clojure)` |
| `dissoc!` | `(jerboa clojure)`, `(std clojure)` |
| `dist-supervisor-children` | `(std actor distributed)` |
| `dist-supervisor-start-child!` | `(std actor distributed)` |
| `distinct` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)`, `(std prelude)` |
| `distributed-eval` | `(std distributed)` |
| `distributed-map` | `(std distributed)` |
| `distributed-supervisor?` | `(std actor cluster)` |
| `divmod` | `(std misc number)`, `(std misc numeric)` |
| `dlet` | `(jerboa clojure)`, `(std clojure)` |
| `dns-answer` | `(std net dns)` |
| `dns-answer-data` | `(std net dns)` |
| `dns-answer-name` | `(std net dns)` |
| `dns-answer-ttl` | `(std net dns)` |
| `dns-answer-type` | `(std net dns)` |
| `dns-answers` | `(std net dns)` |
| `dns-decode-name` | `(std net dns)` |
| `dns-decode-response` | `(std net dns)` |
| `dns-encode-name` | `(std net dns)` |
| `dns-encode-query` | `(std net dns)` |
| `dns-failure-hostname` | `(std error conditions)` |
| `dns-failure?` | `(std error conditions)` |
| `dns-host-import-forms` | `(std secure wasm-target)` |
| `dns-make-query` | `(std net dns)` |
| `dns-question` | `(std net dns)` |
| `dns-questions` | `(std net dns)` |
| `dns-resolver-start!` | `(std net resolve)` |
| `dns-resolver-stop!` | `(std net resolve)` |
| `dns-resolver?` | `(std net resolve)` |
| `dns-response?` | `(std net dns)` |
| `dns-rr-type-a` | `(std net dns)` |
| `dns-rr-type-aaaa` | `(std net dns)` |
| `dns-rr-type-cname` | `(std net dns)` |
| `dns-rr-type-mx` | `(std net dns)` |
| `dns-rr-type-ns` | `(std net dns)` |
| `dns-rr-type-txt` | `(std net dns)` |
| `dns-transaction-id` | `(std net dns)` |
| `do-ec` | `(std srfi srfi-42)` |
| `do/m` | `(std typed hkt)` |
| `doall` | `(jerboa clojure)`, `(std clojure)` |
| `doc-entry-doc` | `(std doc generator)` |
| `doc-entry-examples` | `(std doc generator)` |
| `doc-entry-name` | `(std doc generator)` |
| `doc-entry-type` | `(std doc generator)` |
| `doc-module` | `(std doc generator)` |
| `doc-procedure` | `(std doc generator)` |
| `doc-syntax` | `(std doc generator)` |
| `doc-value` | `(std doc generator)` |
| `doclass` | `(std odb)` |
| `doctest-summary` | `(std doc)` |
| `document-store-close!` | `(std lsp)` |
| `document-store-get` | `(std lsp)` |
| `document-store-open!` | `(std lsp)` |
| `document-store-update!` | `(std lsp)` |
| `dorun` | `(jerboa clojure)`, `(std clojure)` |
| `dosync` | `(std stm)` |
| `dotimes` | `(jerboa clojure)`, `(jerboa prelude)`, `(std gambit-compat)`, `(std prelude)`, ... (+1) |
| `doto` | `(jerboa clojure)`, `(std clojure)` |
| `dotted-list?` | `(std srfi srfi-1)` |
| `double-array` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `double-array-create` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `double-array-create-from-vector` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `drop` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+5) |
| `drop-connection!` | `(std actor transport)` |
| `drop-last` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)`, `(std prelude)` |
| `drop-right` | `(std srfi srfi-1)` |
| `drop-right!` | `(std srfi srfi-1)` |
| `drop-until` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `drop-while` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)`, `(std srfi srfi-1)` |
| `drop-while-xf` | `(std seq)` |
| `drop-xf` | `(std seq)` |
| `dropping` | `(std transducer)` |
| `dropping-buffer` | `(std csp clj)` |
| `dropping-while` | `(std transducer)` |
| `dsend` | `(std actor distributed)` |
| `dsend/ask` | `(std actor distributed)` |
| `dsupervisor-handle-node-failure!` | `(std actor cluster)` |
| `dsupervisor-start-child!` | `(std actor cluster)` |
| `dsupervisor-stop-child!` | `(std actor cluster)` |
| `dsupervisor-which-children` | `(std actor cluster)` |
| `duckdb-bind!` | `(std db duckdb)` |
| `duckdb-bind-blob` | `(std db duckdb-native)` |
| `duckdb-bind-bool` | `(std db duckdb-native)` |
| `duckdb-bind-double` | `(std db duckdb-native)` |
| `duckdb-bind-int` | `(std db duckdb-native)` |
| `duckdb-bind-null` | `(std db duckdb-native)` |
| `duckdb-bind-text` | `(std db duckdb-native)` |
| `duckdb-close` | `(std db duckdb-native)`, `(std db duckdb)` |
| `duckdb-column-name` | `(std db duckdb-native)`, `(std db duckdb)` |
| `duckdb-column-type` | `(std db duckdb-native)`, `(std db duckdb)` |
| `duckdb-eval` | `(std db duckdb-native)`, `(std db duckdb)` |
| `duckdb-exec` | `(std db duckdb-native)`, `(std db duckdb)` |
| `duckdb-execute` | `(std db duckdb-native)`, `(std db duckdb)` |
| `duckdb-finalize` | `(std db duckdb-native)`, `(std db duckdb)` |
| `duckdb-free-result` | `(std db duckdb-native)`, `(std db duckdb)` |
| `duckdb-ncols` | `(std db duckdb-native)`, `(std db duckdb)` |
| `duckdb-nrows` | `(std db duckdb-native)`, `(std db duckdb)` |
| `duckdb-open` | `(std db duckdb-native)`, `(std db duckdb)` |
| `duckdb-prepare` | `(std db duckdb-native)`, `(std db duckdb)` |
| `duckdb-query` | `(std db duckdb-native)`, `(std db duckdb)` |
| `duckdb-read-csv` | `(std db duckdb)` |
| `duckdb-read-parquet` | `(std db duckdb)` |
| `duckdb-reset` | `(std db duckdb-native)`, `(std db duckdb)` |
| `duckdb-value` | `(std db duckdb)` |
| `duckdb-value-blob` | `(std db duckdb-native)` |
| `duckdb-value-bool` | `(std db duckdb-native)` |
| `duckdb-value-double` | `(std db duckdb-native)` |
| `duckdb-value-int` | `(std db duckdb-native)` |
| `duckdb-value-is-null?` | `(std db duckdb-native)`, `(std db duckdb)` |
| `duckdb-value-text` | `(std db duckdb-native)` |
| `duckdb-version` | `(std db duckdb-native)`, `(std db duckdb)` |
| `duckdb-write-csv` | `(std db duckdb)` |
| `duckdb-write-parquet` | `(std db duckdb)` |
| `dump-ir-between-passes!` | `(std compiler passes)` |
| `dump-specialization-stats` | `(std compiler partial-eval)` |
| `duplicates` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `duration` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `duration->string` | `(std time)` |
| `duration-nanoseconds` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `duration-seconds` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `duration?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `dynamic-value?` | `(std compiler partial-eval)` |

### <a name="idx-e"></a>e

| Symbol | Modules |
| --- | --- |
| `EACCES` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `EADDRINUSE` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `EADDRNOTAVAIL` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `EAFNOSUPPORT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `EAGAIN` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `EBADF` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `ECONNABORTED` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `ECONNREFUSED` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `ECONNRESET` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `EFAULT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `EFSM` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `EHOSTUNREACH` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `EINPROGRESS` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `EINTR` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `EINVAL` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `EMFILE` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `EMSGSIZE` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `ENAMETOOLONG` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `END` | `(std specter)` |
| `ENETDOWN` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `ENETRESET` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `ENETUNREACH` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `ENOBUFS` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `ENODEV` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `ENOMEM` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `ENOPROTOOPT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `ENOTCONN` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `ENOTSOCK` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `ENOTSUP` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `EPOLLERR` | `(std os epoll-native)`, `(std os epoll)` |
| `EPOLLET` | `(std os epoll-native)`, `(std os epoll)` |
| `EPOLLHUP` | `(std os epoll-native)`, `(std os epoll)` |
| `EPOLLIN` | `(std os epoll-native)`, `(std os epoll)` |
| `EPOLLONESHOT` | `(std os epoll-native)`, `(std os epoll)` |
| `EPOLLOUT` | `(std os epoll-native)`, `(std os epoll)` |
| `EPOLLPRI` | `(std os epoll-native)`, `(std os epoll)` |
| `EPOLLRDHUP` | `(std os epoll-native)`, `(std os epoll)` |
| `EPOLL_CTL_ADD` | `(std os epoll-native)` |
| `EPOLL_CTL_DEL` | `(std os epoll-native)` |
| `EPOLL_CTL_MOD` | `(std os epoll-native)` |
| `EPROTO` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `EPROTONOSUPPORT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `ETERM` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `ETIMEDOUT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `EVFILT_READ` | `(std os kqueue)` |
| `EVFILT_SIGNAL` | `(std os kqueue)` |
| `EVFILT_TIMER` | `(std os kqueue)` |
| `EVFILT_WRITE` | `(std os kqueue)` |
| `EV_ADD` | `(std os kqueue)` |
| `EV_DELETE` | `(std os kqueue)` |
| `EV_DISABLE` | `(std os kqueue)` |
| `EV_ENABLE` | `(std os kqueue)` |
| `Eff` | `(std typed effects)` |
| `Err-val` | `(std typed hkt)` |
| `Err?` | `(std typed hkt)` |
| `Error` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `Error-irritants` | `(std error)` |
| `Error-message` | `(std error)` |
| `Error?` | `(std error)` |
| `each` | `(std srfi srfi-159)` |
| `each-in-list` | `(std srfi srfi-159)` |
| `each-traversal` | `(std lens)` |
| `ed25519-keygen` | `(std crypto pkey)` |
| `ed25519-sign` | `(std crypto pkey)` |
| `ed25519-verify` | `(std crypto pkey)` |
| `edit-distance` | `(std misc diff)`, `(std text diff)` |
| `edn->string` | `(std text edn)` |
| `edn-default-tag-reader` | `(std text edn)` |
| `edn-set-elements` | `(std text edn)` |
| `edn-set?` | `(std text edn)` |
| `edn-tag-readers` | `(std text edn)` |
| `eduction` | `(std transducer)` |
| `eff-type-effects` | `(std typed effects)` |
| `eff-type-return` | `(std typed effects)` |
| `eff-type?` | `(std typed effects)` |
| `effect-not-handled?` | `(std effect)` |
| `effect-perform` | `(std effect)` |
| `effect-set-difference` | `(std typed effects)` |
| `effect-set-intersect` | `(std typed effects)` |
| `effect-set-member?` | `(std typed effects)` |
| `effect-set-union` | `(std typed effects)` |
| `effect-sig-handles` | `(std typed effect-typing)` |
| `effect-sig-returns` | `(std typed effect-typing)` |
| `effect-sig?` | `(std typed effect-typing)` |
| `effect-type-effect` | `(std typed)` |
| `effect-type-result` | `(std typed)` |
| `effect-type?` | `(std typed)` |
| `eighth` | `(std srfi srfi-1)` |
| `elapsed` | `(std time)` |
| `elapsed/values` | `(std time)` |
| `email-body` | `(std net smtp)` |
| `email-from` | `(std net smtp)` |
| `email-subject` | `(std net smtp)` |
| `email-to` | `(std net smtp)` |
| `email?` | `(std net smtp)` |
| `emit` | `(std misc event-emitter)` |
| `emit!` | `(std event-source)` |
| `empty-effect-set` | `(std typed effects)` |
| `empty-type-env` | `(std typed env)` |
| `empty?` | `(jerboa clojure)`, `(std clojure)` |
| `enable-auto-specialization!` | `(std compiler partial-eval)` |
| `enable-colors!` | `(std cli style)` |
| `enable-pass-debug!` | `(std compiler passes)` |
| `encode-f32` | `(jerboa wasm format)` |
| `encode-f64` | `(jerboa wasm format)` |
| `encode-i32-leb128` | `(jerboa wasm format)` |
| `encode-i64-leb128` | `(jerboa wasm format)` |
| `encode-string` | `(jerboa wasm format)` |
| `encode-u32-leb128` | `(jerboa wasm format)` |
| `encrypt` | `(std crypto cipher)` |
| `encrypt-final!` | `(std crypto cipher)` |
| `encrypt-init!` | `(std crypto cipher)` |
| `encrypt-update!` | `(std crypto cipher)` |
| `end-of-char-set?` | `(std srfi srfi-14)` |
| `endianness-for-target` | `(jerboa cross)` |
| `ends-with?` | `(std clojure string)` |
| `engine-expired?` | `(std engine)` |
| `engine-map` | `(std engine)` |
| `engine-pool-stop!` | `(std actor engine)` |
| `engine-pool-submit!` | `(std actor engine)` |
| `engine-pool-worker-count` | `(std actor engine)` |
| `engine-pool?` | `(std actor engine)` |
| `engine-result` | `(std engine)` |
| `engine-run` | `(std engine)` |
| `enqueue!` | `(std misc queue)` |
| `ensure` | `(std stm)` |
| `ensure-directory` | `(std os path-util)` |
| `enumerating` | `(std transducer)` |
| `env-override!` | `(std config)` |
| `env-read?` | `(std security capability)` |
| `env-write?` | `(std security capability)` |
| `ephemeron-broken?` | `(std srfi srfi-124)` |
| `ephemeron-datum` | `(std srfi srfi-124)` |
| `ephemeron-key` | `(std ephemeron)`, `(std srfi srfi-124)` |
| `ephemeron-pair` | `(std ephemeron)` |
| `ephemeron-pair?` | `(std ephemeron)` |
| `ephemeron-value` | `(std ephemeron)` |
| `ephemeron?` | `(std srfi srfi-124)` |
| `epoch->datetime` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `epoll-add!` | `(std os epoll-native)`, `(std os epoll)` |
| `epoll-close` | `(std os epoll-native)`, `(std os epoll)` |
| `epoll-create` | `(std os epoll-native)`, `(std os epoll)` |
| `epoll-event-events` | `(std os epoll)` |
| `epoll-event-fd` | `(std os epoll)` |
| `epoll-modify!` | `(std os epoll-native)`, `(std os epoll)` |
| `epoll-remove!` | `(std os epoll-native)`, `(std os epoll)` |
| `epoll-wait` | `(std os epoll-native)`, `(std os epoll)` |
| `eprintf` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `epsilon-closure` | `(std regex-ct-impl)`, `(std text regex-compile)` |
| `eql-specializer` | `(std clos)` |
| `eql-specializer-value` | `(std clos)` |
| `eql-specializer?` | `(std clos)` |
| `eql?` | `(jerboa clojure)`, `(jerboa prelude)` |
| `equiv-hash` | `(std misc equiv)` |
| `equiv?` | `(std misc equiv)` |
| `err` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc result)`, `(std prelude)`, ... (+1) |
| `err->list` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `err-value` | `(std misc result)` |
| `err?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc result)`, `(std prelude)`, ... (+1) |
| `errdefer` | `(std errdefer)` |
| `errdefer*` | `(std errdefer)` |
| `error-class` | `(std security errors)` |
| `error-irritants` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+5) |
| `error-message` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+5) |
| `error-prefix` | `(std cli style)` |
| `error-trace` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+5) |
| `error-with-advice` | `(std error-advice)` |
| `error?` | `(std error)` |
| `errorf` | `(std logger)` |
| `escape` | `(std clojure string)` |
| `euclidean-quotient` | `(std srfi srfi-141)` |
| `euclidean-remainder` | `(std srfi srfi-141)` |
| `euclidean/` | `(std srfi srfi-141)` |
| `euler-totient` | `(std misc prime)` |
| `eval-cap-allowed-modules` | `(std capability)` |
| `eval-capability?` | `(std capability)` |
| `eval-state` | `(std typed monad)` |
| `evector->list` | `(std misc evector)` |
| `evector->vector` | `(std misc evector)` |
| `evector-capacity` | `(std misc evector)` |
| `evector-length` | `(std misc evector)` |
| `evector-pop!` | `(std misc evector)` |
| `evector-push!` | `(std misc evector)` |
| `evector-ref` | `(std misc evector)` |
| `evector-set!` | `(std misc evector)` |
| `evector?` | `(std misc evector)` |
| `event-count` | `(std event-source)` |
| `event-data` | `(std debug timetravel)` |
| `event-diff` | `(std debug timetravel)` |
| `event-emitter?` | `(std misc event-emitter)` |
| `event-log` | `(std event-source)` |
| `event-log-since` | `(std event-source)` |
| `event-names` | `(std misc event-emitter)` |
| `event-ready?` | `(std misc event)` |
| `event-step` | `(std debug timetravel)` |
| `event-store?` | `(std event-source)` |
| `event-tag` | `(std debug timetravel)` |
| `event-timestamp` | `(std debug timetravel)` |
| `event-value` | `(std misc event)` |
| `event?` | `(std debug timetravel)`, `(std event)` |
| `eventfd-create` | `(std os epoll-native)` |
| `eventfd-drain` | `(std os epoll-native)` |
| `eventfd-signal` | `(std os epoll-native)` |
| `events-between` | `(std debug timetravel)` |
| `events-by-tag` | `(std debug timetravel)` |
| `every` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+5) |
| `every-bit-set?` | `(std srfi srfi-151)` |
| `every-consecutive?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `every-pred` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc func)`, ... (+1) |
| `every?-ec` | `(std srfi srfi-42)` |
| `ex-cause` | `(jerboa clojure)`, `(std clojure)` |
| `ex-data` | `(jerboa clojure)`, `(std clojure)` |
| `ex-info` | `(jerboa clojure)`, `(std clojure)` |
| `ex-info?` | `(jerboa clojure)`, `(std clojure)` |
| `ex-message` | `(jerboa clojure)`, `(std clojure)` |
| `exec-state` | `(std typed monad)` |
| `exit/failure` | `(std cli print-exit)` |
| `exit/success` | `(std cli print-exit)` |
| `export-all` | `(std compat gerbil-import)` |
| `expr->hash` | `(std content-address)` |
| `extend-protocol` | `(std protocol)` |
| `extend-type` | `(std protocol)` |
| `extension->mime-type` | `(std mime types)` |
| `extract-context` | `(std span)` |
| `extract-docs` | `(std doc generator)` |

### <a name="idx-f"></a>f

| Symbol | Modules |
| --- | --- |
| `FD_CLOEXEC` | `(std os fcntl)` |
| `FIRST` | `(std specter)` |
| `FIXNUM-MASK` | `(jerboa wasm values)` |
| `FIXNUM-MAX` | `(jerboa wasm values)` |
| `FIXNUM-MIN` | `(jerboa wasm values)` |
| `FIXNUM-TAG` | `(jerboa wasm values)` |
| `FLONUM-PAYLOAD-SIZE` | `(jerboa wasm values)` |
| `F_GETFD` | `(std os fcntl)` |
| `F_GETFL` | `(std os fcntl)` |
| `F_OK` | `(std os posix)` |
| `F_SETFD` | `(std os fcntl)` |
| `F_SETFL` | `(std os fcntl)` |
| `FileIO` | `(std security io-intercept)` |
| `Foldable` | `(std typed hkt)` |
| `Functor` | `(std typed hkt)` |
| `f32` | `(std binary)` |
| `f32vector` | `(std srfi srfi-160)` |
| `f32vector->list` | `(std srfi srfi-160)` |
| `f32vector-append` | `(std srfi srfi-160)` |
| `f32vector-copy` | `(std srfi srfi-160)` |
| `f32vector-length` | `(std srfi srfi-160)` |
| `f32vector-ref` | `(std srfi srfi-160)` |
| `f32vector-set!` | `(std srfi srfi-160)` |
| `f32vector?` | `(std srfi srfi-160)` |
| `f64` | `(std binary)` |
| `f64vector` | `(std srfi srfi-160)` |
| `f64vector->list` | `(std gambit-compat)`, `(std srfi srfi-160)` |
| `f64vector-append` | `(std srfi srfi-160)` |
| `f64vector-copy` | `(std srfi srfi-160)` |
| `f64vector-length` | `(jerboa core)`, `(std gambit-compat)`, `(std srfi srfi-160)` |
| `f64vector-ref` | `(jerboa core)`, `(std gambit-compat)`, `(std srfi srfi-160)` |
| `f64vector-set!` | `(jerboa core)`, `(std gambit-compat)`, `(std srfi srfi-160)` |
| `f64vector?` | `(std srfi srfi-160)` |
| `factorize` | `(std misc prime)` |
| `fail` | `(jerboa clojure)`, `(std effect multishot)`, `(std logic)` |
| `false?` | `(jerboa clojure)`, `(std clojure)` |
| `fasl->bytevector` | `(std fasl)` |
| `fasl-deserialize` | `(std persist closure)` |
| `fasl-file-read` | `(std fasl)` |
| `fasl-file-write` | `(std fasl)` |
| `fasl-read-datum` | `(std fasl)` |
| `fasl-serialize` | `(std persist closure)` |
| `fasl-write-datum` | `(std fasl)` |
| `fastcgi-accept` | `(std web fastcgi)` |
| `fastcgi-close` | `(std web fastcgi)` |
| `fastcgi-listen` | `(std web fastcgi)` |
| `fastcgi-request-params` | `(std web fastcgi)` |
| `fastcgi-request-stdin` | `(std web fastcgi)` |
| `fastcgi-respond` | `(std web fastcgi)` |
| `fcntl-getfd` | `(std os fcntl)` |
| `fcntl-getfl` | `(std os fcntl)` |
| `fcntl-setfd` | `(std os fcntl)` |
| `fcntl-setfl` | `(std os fcntl)` |
| `fd->binary-input-port` | `(std io raw)` |
| `fd->binary-input/output-port` | `(std io raw)` |
| `fd->binary-output-port` | `(std io raw)` |
| `fd->textual-input-port` | `(std io raw)` |
| `fd->textual-output-port` | `(std io raw)` |
| `fd-close` | `(std os epoll)` |
| `fd-close!` | `(std os fd)` |
| `fd-dup` | `(std os fd)` |
| `fd-dup2` | `(std os fd)` |
| `fd-flags` | `(std os fcntl)` |
| `fd-num` | `(std os fd)` |
| `fd-open?` | `(std os fd)` |
| `fd-pipe` | `(std os epoll)`, `(std os fd)` |
| `fd-read` | `(std os epoll)`, `(std os fd)` |
| `fd-read-all` | `(std io raw)` |
| `fd-read-bytes` | `(std io raw)` |
| `fd-redirect!` | `(std os fd)` |
| `fd-set-cloexec!` | `(std os fcntl)` |
| `fd-set-nonblock!` | `(std os fcntl)` |
| `fd-write` | `(std os epoll)`, `(std os fd)` |
| `fd-write-bytes` | `(std io raw)` |
| `fd?` | `(std os fd)` |
| `fdclose` | `(std os fdio)` |
| `fdopen-input-port` | `(std os fdio)` |
| `fdopen-output-port` | `(std os fdio)` |
| `fdread` | `(std os fdio)` |
| `fdwrite` | `(std os fdio)` |
| `ffi-thread-pool-call` | `(std foreign bind)` |
| `ffi-thread-pool-shutdown!` | `(std foreign bind)` |
| `ffi-type-map` | `(jerboa ffi)` |
| `fg-color` | `(std misc terminal)` |
| `fiber-append-file` | `(std io filepool)` |
| `fiber-cancel!` | `(std fiber)` |
| `fiber-cancelled-condition?` | `(std fiber)` |
| `fiber-cancelled?` | `(std fiber)` |
| `fiber-channel-close` | `(std fiber)` |
| `fiber-channel-closed?` | `(std fiber)` |
| `fiber-channel-recv` | `(std fiber)` |
| `fiber-channel-send` | `(std fiber)` |
| `fiber-channel-try-recv` | `(std fiber)` |
| `fiber-channel-try-send` | `(std fiber)` |
| `fiber-channel?` | `(std fiber)` |
| `fiber-check-cancelled!` | `(std fiber)` |
| `fiber-csp-chan` | `(std csp fiber-chan)` |
| `fiber-csp-chan-inner` | `(std csp fiber-chan)` |
| `fiber-csp-chan-kind` | `(std csp fiber-chan)` |
| `fiber-csp-chan?` | `(std csp fiber-chan)` |
| `fiber-done?` | `(std fiber)` |
| `fiber-file-exists?` | `(std io filepool)` |
| `fiber-gate-set!` | `(std fiber)` |
| `fiber-group-spawn` | `(std fiber)` |
| `fiber-httpd-listen-port` | `(std net fiber-httpd)` |
| `fiber-httpd-metrics` | `(std net fiber-httpd)` |
| `fiber-httpd-start` | `(std net fiber-httpd)` |
| `fiber-httpd-start*` | `(std net fiber-httpd)` |
| `fiber-httpd-stop!` | `(std net fiber-httpd)` |
| `fiber-httpd?` | `(std net fiber-httpd)` |
| `fiber-id` | `(std fiber)` |
| `fiber-join` | `(std fiber)` |
| `fiber-link!` | `(std fiber)` |
| `fiber-linked-crash?` | `(std fiber)` |
| `fiber-name` | `(std fiber)` |
| `fiber-parameterize` | `(std fiber)` |
| `fiber-read-file` | `(std io filepool)` |
| `fiber-read-file-bytes` | `(std io filepool)` |
| `fiber-resolve` | `(std net resolve)` |
| `fiber-runtime-active?` | `(std csp fiber-chan)` |
| `fiber-runtime-component` | `(std component fiber)` |
| `fiber-runtime-fiber-count` | `(std fiber)` |
| `fiber-runtime-run!` | `(std fiber)` |
| `fiber-runtime-stop!` | `(std fiber)` |
| `fiber-runtime?` | `(std fiber)` |
| `fiber-select` | `(std fiber)` |
| `fiber-self` | `(std fiber)` |
| `fiber-semaphore-acquire!` | `(std fiber)` |
| `fiber-semaphore-release!` | `(std fiber)` |
| `fiber-semaphore-try-acquire!` | `(std fiber)` |
| `fiber-semaphore?` | `(std fiber)` |
| `fiber-sendfile` | `(std net sendfile)` |
| `fiber-sendfile*` | `(std net sendfile)` |
| `fiber-sleep` | `(std fiber)` |
| `fiber-spawn` | `(std fiber)` |
| `fiber-spawn*` | `(std fiber)` |
| `fiber-state` | `(std fiber)` |
| `fiber-tcp-accept` | `(std net io)` |
| `fiber-tcp-close` | `(std net io)` |
| `fiber-tcp-connect` | `(std net io)` |
| `fiber-tcp-listen` | `(std net io)` |
| `fiber-tcp-read` | `(std net io)` |
| `fiber-tcp-write` | `(std net io)` |
| `fiber-tcp-writev2` | `(std net io)` |
| `fiber-timeout` | `(std fiber)` |
| `fiber-timeout-condition?` | `(std fiber)` |
| `fiber-unlink!` | `(std fiber)` |
| `fiber-wait-readable` | `(std net io)` |
| `fiber-wait-writable` | `(std net io)` |
| `fiber-write-file` | `(std io filepool)` |
| `fiber-write-file-bytes` | `(std io filepool)` |
| `fiber-ws-close` | `(std net fiber-ws)` |
| `fiber-ws-open?` | `(std net fiber-ws)` |
| `fiber-ws-ping` | `(std net fiber-ws)` |
| `fiber-ws-recv` | `(std net fiber-ws)` |
| `fiber-ws-send` | `(std net fiber-ws)` |
| `fiber-ws-send-binary` | `(std net fiber-ws)` |
| `fiber-ws-upgrade` | `(std net fiber-ws)` |
| `fiber-ws?` | `(std net fiber-ws)` |
| `fiber-yield` | `(std fiber)` |
| `fiber?` | `(std fiber)` |
| `field-number` | `(std protobuf)` |
| `field-type` | `(std protobuf)` |
| `field-value` | `(std protobuf)` |
| `field?` | `(std protobuf)` |
| `fifth` | `(std srfi srfi-1)` |
| `file` | `(std clojure io)`, `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `file->c-array` | `(jerboa build)` |
| `file-changed?` | `(std build watch)` |
| `file-executable?` | `(std os file-info)` |
| `file-exists-safe?` | `(std os path-util)` |
| `file-info` | `(jerboa core)`, `(std gambit-compat)` |
| `file-info-device` | `(jerboa core)`, `(std gambit-compat)` |
| `file-info-gid` | `(std os file-info)` |
| `file-info-group` | `(jerboa core)`, `(std gambit-compat)` |
| `file-info-inode` | `(jerboa core)`, `(std gambit-compat)` |
| `file-info-last-access-time` | `(jerboa core)`, `(std gambit-compat)` |
| `file-info-last-modification-time` | `(jerboa core)`, `(std gambit-compat)` |
| `file-info-mode` | `(jerboa core)`, `(std gambit-compat)`, `(std os file-info)` |
| `file-info-mtime` | `(std os file-info)` |
| `file-info-owner` | `(jerboa core)`, `(std gambit-compat)` |
| `file-info-size` | `(jerboa core)`, `(std gambit-compat)`, `(std os file-info)` |
| `file-info-type` | `(jerboa core)`, `(std gambit-compat)`, `(std os file-info)` |
| `file-info-uid` | `(std os file-info)` |
| `file-info?` | `(std os file-info)` |
| `file-mode` | `(std os file-info)` |
| `file-modified?` | `(jerboa hot)` |
| `file-mtime` | `(std build watch)`, `(std os file-info)` |
| `file-mtimes` | `(jerboa hot)` |
| `file-path-label` | `(std taint)` |
| `file-pool-start!` | `(std io filepool)` |
| `file-pool-stop!` | `(std io filepool)` |
| `file-pool?` | `(std io filepool)` |
| `file-port-length` | `(std port-position)` |
| `file-readable?` | `(std os file-info)` |
| `file-sha256-hex` | `(std build verify)` |
| `file-size` | `(std os file-info)`, `(std os path-util)` |
| `file-type` | `(std os file-info)` |
| `file-writable?` | `(std os file-info)` |
| `filter!` | `(std srfi srfi-1)` |
| `filter-err` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `filter-map` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+6) |
| `filter-ok` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `filter-with-process` | `(std misc process)` |
| `filter-xf` | `(std seq)` |
| `filterer` | `(std specter)` |
| `filtering` | `(std transducer)` |
| `finally` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `find-class` | `(std clos)` |
| `find-completions` | `(std lsp)` |
| `find-cross-compiler` | `(std build cross)` |
| `find-definition` | `(std lsp)` |
| `find-scheme-files` | `(std build watch)` |
| `find-snapshot` | `(std debug timetravel)` |
| `find-suggestions` | `(std errors)` |
| `find-tail` | `(std srfi srfi-1)` |
| `finish-span!` | `(std span)` |
| `first` | `(jerboa clojure)`, `(std clojure)`, `(std srfi srfi-1)` |
| `first-and-only` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `first-ec` | `(std srfi srfi-42)` |
| `first-set-bit` | `(std srfi srfi-151)` |
| `fitted` | `(std srfi srfi-159)` |
| `fitted/both` | `(std srfi srfi-159)` |
| `fitted/right` | `(std srfi srfi-159)` |
| `fixed-window-count` | `(std net rate)` |
| `fixed-window-try!` | `(std net rate)` |
| `fixed-window?` | `(std net rate)` |
| `fixnum->flonum` | `(std misc number)` |
| `fixnum-width` | `(std fixnum)` |
| `fixnum?` | `(std srfi srfi-143)` |
| `fl` | `(std srfi srfi-159)` |
| `fl*` | `(std srfi srfi-144)` |
| `fl+` | `(std srfi srfi-144)` |
| `fl-` | `(std srfi srfi-144)` |
| `fl-e` | `(std srfi srfi-144)` |
| `fl-epsilon` | `(std srfi srfi-144)` |
| `fl-greatest` | `(std srfi srfi-144)` |
| `fl-least` | `(std srfi srfi-144)` |
| `fl-pi` | `(std srfi srfi-144)` |
| `fl/` | `(std srfi srfi-144)` |
| `fl<` | `(std srfi srfi-144)` |
| `fl<=` | `(std srfi srfi-144)` |
| `fl=` | `(std srfi srfi-144)` |
| `fl>` | `(std srfi srfi-144)` |
| `fl>=` | `(std srfi srfi-144)` |
| `flabs` | `(std srfi srfi-144)` |
| `flacos` | `(std srfi srfi-144)` |
| `flag` | `(std cli getopt)` |
| `flags` | `(thunderchez ffi-utils)` |
| `flags-alist` | `(thunderchez ffi-utils)` |
| `flags-decode-maker` | `(thunderchez ffi-utils)` |
| `flags-indexer` | `(thunderchez ffi-utils)` |
| `flags-name` | `(thunderchez ffi-utils)` |
| `flags-ref-maker` | `(thunderchez ffi-utils)` |
| `flasin` | `(std srfi srfi-144)` |
| `flat-map` | `(std srfi srfi-1)` |
| `flat-map-xf` | `(std seq)` |
| `flat-mapping` | `(std transducer)` |
| `flatan` | `(std srfi srfi-144)` |
| `flatten` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+3) |
| `flatten-request-headers` | `(std net request)` |
| `flatten-result` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `flatten1` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `flceiling` | `(std srfi srfi-144)` |
| `flcos` | `(std srfi srfi-144)` |
| `flexp` | `(std srfi srfi-144)` |
| `flfinite?` | `(std srfi srfi-144)` |
| `flfloor` | `(std srfi srfi-144)` |
| `flinfinite?` | `(std srfi srfi-144)` |
| `flinteger?` | `(std srfi srfi-144)` |
| `flip` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc func)`, `(std prelude)` |
| `fllog` | `(std srfi srfi-144)` |
| `flmax` | `(std srfi srfi-144)` |
| `flmin` | `(std srfi srfi-144)` |
| `flnan?` | `(std srfi srfi-144)` |
| `flnegative?` | `(std srfi srfi-144)` |
| `float32-be` | `(std misc binary-type)` |
| `float64-be` | `(std misc binary-type)` |
| `flock-exclusive` | `(std os flock)` |
| `flock-shared` | `(std os flock)` |
| `flock-try-exclusive` | `(std os flock)` |
| `flock-try-shared` | `(std os flock)` |
| `flock-unlock` | `(std os flock)` |
| `floor-quotient` | `(std srfi srfi-141)` |
| `floor-remainder` | `(std srfi srfi-141)` |
| `floor/` | `(std srfi srfi-141)` |
| `flow-violation-from` | `(std security flow)` |
| `flow-violation-to` | `(std security flow)` |
| `flow-violation?` | `(std security flow)` |
| `flpositive?` | `(std srfi srfi-144)` |
| `flround` | `(std srfi srfi-144)` |
| `flsin` | `(std srfi srfi-144)` |
| `flsqrt` | `(std srfi srfi-144)` |
| `fltan` | `(std srfi srfi-144)` |
| `fltruncate` | `(std srfi srfi-144)` |
| `flzero?` | `(std srfi srfi-144)` |
| `fmt` | `(std misc fmt)` |
| `fmt/port` | `(std misc fmt)` |
| `fn-literal` | `(jerboa cloj)`, `(jerboa clojure)` |
| `fnil` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc func)`, ... (+1) |
| `fold` | `(std srfi srfi-1)` |
| `fold-ec` | `(std srfi srfi-42)` |
| `fold-syntax` | `(std match-syntax)` |
| `for` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `for-all` | `(std test check)`, `(std test framework)`, `(std test quickcheck)` |
| `for-each!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `for/and` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `for/collect` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `for/fold` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `for/or` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `force` | `(std lazy)` |
| `force-output` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude)`, `(std gambit-compat)` |
| `foreign-alloc` | `(std foreign)`, `(std ftype)` |
| `foreign-free` | `(std foreign)`, `(std ftype)` |
| `foreign-ptr-free!` | `(std foreign bind)` |
| `foreign-ptr-valid?` | `(std foreign bind)` |
| `foreign-ptr-value` | `(std foreign bind)` |
| `foreign-ptr?` | `(std foreign bind)` |
| `foreign-ref` | `(std foreign)`, `(std ftype)` |
| `foreign-set!` | `(std foreign)`, `(std ftype)` |
| `foreign-sizeof` | `(std foreign)`, `(std ftype)` |
| `forked` | `(std srfi srfi-159)` |
| `format` | `(jerboa clojure)`, `(jerboa prelude safe)`, `(jerboa prelude)`, `(std format)`, ... (+1) |
| `format-build-result` | `(std build watch)` |
| `format-condition` | `(std errors)` |
| `format-diagnostic` | `(std error diagnostics)` |
| `format-error-message` | `(std errors)` |
| `format-error-with-fix` | `(std error-advice)` |
| `format-id` | `(std staging)` |
| `format-lsp-error` | `(std lsp)` |
| `format-lsp-notification` | `(std lsp)` |
| `format-lsp-response` | `(std lsp)` |
| `format-one` | `(std text printf)` |
| `format-signature` | `(std doc generator)` |
| `forward-listener-local-port` | `(std net ssh forward)`, `(std net ssh)` |
| `forward-listener-remote-host` | `(std net ssh forward)`, `(std net ssh)` |
| `forward-listener-remote-port` | `(std net ssh forward)`, `(std net ssh)` |
| `forward-listener?` | `(std net ssh forward)`, `(std net ssh)` |
| `fourth` | `(std srfi srfi-1)` |
| `fprintf` | `(jerboa clojure)`, `(jerboa prelude safe)`, `(jerboa prelude)`, `(std format)`, ... (+1) |
| `fprintf*` | `(std text printf)` |
| `frame-locals` | `(std debug inspector)` |
| `frame-name` | `(std debug inspector)` |
| `frame?` | `(std debug inspector)` |
| `free-cipher-ctx` | `(std crypto cipher)` |
| `free-epoll-events` | `(std os epoll)` |
| `free-identifiers` | `(std match-syntax)` |
| `free-stat` | `(std os posix)` |
| `free-variables` | `(jerboa wasm closure)` |
| `frequencies` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list-more)`, `(std misc list)`, ... (+1) |
| `fresh` | `(jerboa clojure)`, `(std logic)` |
| `from` | `(std db query-compile)`, `(std query)` |
| `from-maybe` | `(std typed monad)` |
| `fs-allowed-path?` | `(std security capability)` |
| `fs-cap-paths` | `(std capability)` |
| `fs-cap-readable?` | `(std capability)` |
| `fs-cap-writable?` | `(std capability)` |
| `fs-capability?` | `(std capability)` |
| `fs-execute?` | `(std security capability)` |
| `fs-policy` | `(std capability sandbox)` |
| `fs-read?` | `(std security capability)` |
| `fs-write?` | `(std security capability)` |
| `ftype-pointer-address` | `(std ftype)` |
| `ftype-pointer-null?` | `(std ftype)` |
| `ftype-pointer=?` | `(std ftype)` |
| `ftype-pointer?` | `(std ftype)` |
| `ftype-ref` | `(std ftype)` |
| `ftype-set!` | `(std ftype)` |
| `ftype-sizeof` | `(std ftype)` |
| `fuel-eval` | `(std engine)` |
| `fuse-handlers` | `(std effect fusion)` |
| `fusion-stats-reset!` | `(std effect fusion)` |
| `future-cancel` | `(jerboa clojure)`, `(std clojure)` |
| `future-cancelled?` | `(jerboa clojure)`, `(std clojure)` |
| `future-complete!` | `(std task)` |
| `future-done?` | `(jerboa clojure)`, `(std clojure)`, `(std task)` |
| `future-fail!` | `(std task)` |
| `future-force` | `(std concur util)` |
| `future-get` | `(std task)` |
| `future-map` | `(std concur util)` |
| `future-ready?` | `(std concur util)` |
| `future?` | `(jerboa clojure)`, `(std clojure)`, `(std concur util)`, `(std task)` |
| `fuzz-fuel` | `(std test fuzz)` |
| `fuzz-iterations` | `(std test fuzz)` |
| `fuzz-max-size` | `(std test fuzz)` |
| `fuzz-one` | `(std test fuzz)` |
| `fuzz-report` | `(std test fuzz)` |
| `fuzz-roundtrip-check` | `(std test fuzz)` |
| `fuzz-run` | `(std test fuzz)` |
| `fuzz-stats-crashes` | `(std test fuzz)` |
| `fuzz-stats-exceptions` | `(std test fuzz)` |
| `fuzz-stats-iterations` | `(std test fuzz)` |
| `fuzz-stats-name` | `(std test fuzz)` |
| `fuzz-stats-timeouts` | `(std test fuzz)` |
| `fuzz-with-timeout` | `(std test fuzz)` |
| `fx*` | `(std fixnum)`, `(std srfi srfi-143)` |
| `fx+` | `(std fixnum)`, `(std srfi srfi-143)` |
| `fx-` | `(std fixnum)`, `(std srfi srfi-143)` |
| `fx-greatest` | `(std srfi srfi-143)` |
| `fx-least` | `(std srfi srfi-143)` |
| `fx-width` | `(std srfi srfi-143)` |
| `fx<` | `(std fixnum)`, `(std srfi srfi-143)` |
| `fx<=` | `(std fixnum)`, `(std srfi srfi-143)` |
| `fx=` | `(std fixnum)`, `(std srfi srfi-143)` |
| `fx>` | `(std fixnum)`, `(std srfi srfi-143)` |
| `fx>=` | `(std fixnum)`, `(std srfi srfi-143)` |
| `fxabs` | `(std fixnum)`, `(std srfi srfi-143)` |
| `fxand` | `(std srfi srfi-143)` |
| `fxarithmetic-shift-left` | `(std fixnum)`, `(std srfi srfi-143)` |
| `fxarithmetic-shift-right` | `(std fixnum)`, `(std srfi srfi-143)` |
| `fxbit-count` | `(std fixnum)` |
| `fxdiv` | `(std fixnum)` |
| `fxdiv0` | `(std fixnum)` |
| `fxeven?` | `(std fixnum)`, `(std srfi srfi-143)` |
| `fxfirst-bit-set` | `(std fixnum)` |
| `fxior` | `(std srfi srfi-143)` |
| `fxlength` | `(std fixnum)` |
| `fxlogand` | `(std fixnum)` |
| `fxlogbit?` | `(std fixnum)` |
| `fxlognot` | `(std fixnum)` |
| `fxlogor` | `(std fixnum)` |
| `fxlogxor` | `(std fixnum)` |
| `fxmax` | `(std fixnum)`, `(std srfi srfi-143)` |
| `fxmin` | `(std fixnum)`, `(std srfi srfi-143)` |
| `fxmod` | `(std fixnum)` |
| `fxmod0` | `(std fixnum)` |
| `fxnegative?` | `(std fixnum)`, `(std srfi srfi-143)` |
| `fxnot` | `(std srfi srfi-143)` |
| `fxodd?` | `(std fixnum)`, `(std srfi srfi-143)` |
| `fxpositive?` | `(std fixnum)`, `(std srfi srfi-143)` |
| `fxquotient` | `(std srfi srfi-143)` |
| `fxremainder` | `(std srfi srfi-143)` |
| `fxsll` | `(std fixnum)` |
| `fxsra` | `(std fixnum)` |
| `fxsrl` | `(std fixnum)` |
| `fxxor` | `(std srfi srfi-143)` |
| `fxzero?` | `(std fixnum)`, `(std srfi srfi-143)` |

### <a name="idx-g"></a>g

| Symbol | Modules |
| --- | --- |
| `GLOBAL-ARENA-BASE` | `(jerboa wasm values)` |
| `GLOBAL-HEAP-END` | `(jerboa wasm values)` |
| `GLOBAL-HEAP-PTR` | `(jerboa wasm values)` |
| `GLOBAL-ROOT-SP` | `(jerboa wasm values)` |
| `GLOBAL-SYMBOL-TABLE` | `(jerboa wasm values)` |
| `GLUT_ACCUM` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_ALPHA` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_BLUE` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_DEPTH` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_DOUBLE` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_DOWN` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_ENTERED` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_FULLY_COVERED` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_FULLY_RETAINED` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_GREEN` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_HIDDEN` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_INDEX` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_DOWN` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_END` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_F1` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_F10` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_F11` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_F12` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_F2` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_F3` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_F4` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_F5` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_F6` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_F7` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_F8` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_F9` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_HOME` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_INSERT` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_LEFT` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_PAGE_DOWN` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_PAGE_UP` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_RIGHT` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_KEY_UP` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_LEFT` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_LEFT_BUTTON` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_LUMINANCE` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_MENU_IN_USE` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_MENU_NOT_IN_USE` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_MIDDLE_BUTTON` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_MULTISAMPLE` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_NORMAL` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_NOT_VISIBLE` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_NO_RECOVERY` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_OVERLAY` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_PARTIALLY_RETAINED` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_RED` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_RGB` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_RGBA` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_RIGHT_BUTTON` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_SINGLE` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_STENCIL` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_STEREO` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_UP` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLUT_VISIBLE` | `(std ffi glut)`, `(thunderchez glut)` |
| `GLU_AUTO_LOAD_MATRIX` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_BEGIN` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_CCW` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_CULLING` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_CW` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_DISPLAY_MODE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_DOMAIN_DISTANCE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_EDGE_FLAG` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_END` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_ERROR` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_EXTENSIONS` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_EXTERIOR` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_EXT_nurbs_tessellator` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_EXT_object_space_tess` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_FALSE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_FILL` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_FLAT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_INCOMPATIBLE_GL_VERSION` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_INSIDE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_INTERIOR` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_INVALID_ENUM` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_INVALID_OPERATION` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_INVALID_VALUE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_LINE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_MAP1_TRIM_2` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_MAP1_TRIM_3` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NONE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_BEGIN` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_BEGIN_DATA` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_BEGIN_DATA_EXT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_BEGIN_EXT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_COLOR` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_COLOR_DATA` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_COLOR_DATA_EXT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_COLOR_EXT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_END` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_END_DATA` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_END_DATA_EXT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_END_EXT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR1` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR10` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR11` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR12` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR13` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR14` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR15` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR16` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR17` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR18` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR19` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR2` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR20` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR21` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR22` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR23` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR24` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR25` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR26` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR27` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR28` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR29` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR3` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR30` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR31` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR32` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR33` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR34` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR35` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR36` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR37` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR4` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR5` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR6` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR7` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR8` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_ERROR9` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_MODE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_MODE_EXT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_NORMAL` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_NORMAL_DATA` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_NORMAL_DATA_EXT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_NORMAL_EXT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_RENDERER` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_RENDERER_EXT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_TESSELLATOR` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_TESSELLATOR_EXT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_TEXTURE_COORD` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_TEXTURE_COORD_DATA` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_TEX_COORD_DATA_EXT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_TEX_COORD_EXT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_VERTEX` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_VERTEX_DATA` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_VERTEX_DATA_EXT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_NURBS_VERTEX_EXT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_OBJECT_PARAMETRIC_ERROR` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_OBJECT_PARAMETRIC_ERROR_EXT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_OBJECT_PATH_LENGTH` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_OBJECT_PATH_LENGTH_EXT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_OUTLINE_PATCH` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_OUTLINE_POLYGON` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_OUTSIDE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_OUT_OF_MEMORY` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_PARAMETRIC_ERROR` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_PARAMETRIC_TOLERANCE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_PATH_LENGTH` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_POINT` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_SAMPLING_METHOD` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_SAMPLING_TOLERANCE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_SILHOUETTE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_SMOOTH` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_BEGIN` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_BEGIN_DATA` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_BOUNDARY_ONLY` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_COMBINE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_COMBINE_DATA` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_COORD_TOO_LARGE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_EDGE_FLAG` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_EDGE_FLAG_DATA` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_END` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_END_DATA` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_ERROR` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_ERROR1` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_ERROR2` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_ERROR3` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_ERROR4` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_ERROR5` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_ERROR6` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_ERROR7` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_ERROR8` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_ERROR_DATA` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_MAX_COORD` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_MISSING_BEGIN_CONTOUR` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_MISSING_BEGIN_POLYGON` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_MISSING_END_CONTOUR` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_MISSING_END_POLYGON` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_NEED_COMBINE_CALLBACK` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_TOLERANCE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_VERTEX` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_VERTEX_DATA` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_WINDING_ABS_GEQ_TWO` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_WINDING_NEGATIVE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_WINDING_NONZERO` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_WINDING_ODD` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_WINDING_POSITIVE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TESS_WINDING_RULE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_TRUE` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_UNKNOWN` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_U_STEP` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_VERSION` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_VERSION_1_1` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_VERSION_1_2` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_VERSION_1_3` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_VERTEX` | `(std ffi glu)`, `(thunderchez glu)` |
| `GLU_V_STEP` | `(std ffi glu)`, `(thunderchez glu)` |
| `GL_2D` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_2_BYTES` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_3D` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_3D_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_3D_COLOR_TEXTURE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_3_BYTES` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_4D_COLOR_TEXTURE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_4_BYTES` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ACCUM` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ACCUM_ALPHA_BITS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ACCUM_BLUE_BITS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ACCUM_BUFFER_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ACCUM_CLEAR_VALUE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ACCUM_GREEN_BITS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ACCUM_RED_BITS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ACTIVE_TEXTURE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ACTIVE_TEXTURE_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ADD` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ADD_SIGNED` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ALIASED_LINE_WIDTH_RANGE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ALIASED_POINT_SIZE_RANGE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ALL_ATTRIB_BITS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ALL_CLIENT_ATTRIB_BITS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ALPHA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ALPHA12` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ALPHA16` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ALPHA4` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ALPHA8` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ALPHA_BIAS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ALPHA_BITS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ALPHA_SCALE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ALPHA_TEST` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ALPHA_TEST_FUNC` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ALPHA_TEST_REF` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ALWAYS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_AMBIENT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_AMBIENT_AND_DIFFUSE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_AND` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_AND_INVERTED` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_AND_REVERSE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ATTRIB_STACK_DEPTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_AUTO_NORMAL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_AUX0` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_AUX1` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_AUX2` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_AUX3` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_AUX_BUFFERS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_BACK` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_BACK_LEFT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_BACK_RIGHT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_BGR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_BGRA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_BITMAP` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_BITMAP_TOKEN` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_BLEND` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_BLEND_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_BLEND_DST` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_BLEND_EQUATION` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_BLEND_SRC` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_BLUE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_BLUE_BIAS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_BLUE_BITS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_BLUE_SCALE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_BYTE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_C3F_V3F` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_C4F_N3F_V3F` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_C4UB_V2F` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_C4UB_V3F` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CCW` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CLAMP` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CLAMP_TO_BORDER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CLAMP_TO_EDGE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CLEAR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CLIENT_ACTIVE_TEXTURE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CLIENT_ACTIVE_TEXTURE_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CLIENT_ALL_ATTRIB_BITS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CLIENT_ATTRIB_STACK_DEPTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CLIENT_PIXEL_STORE_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CLIENT_VERTEX_ARRAY_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CLIP_PLANE0` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CLIP_PLANE1` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CLIP_PLANE2` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CLIP_PLANE3` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CLIP_PLANE4` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CLIP_PLANE5` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COEFF` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_ARRAY` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_ARRAY_POINTER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_ARRAY_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_ARRAY_STRIDE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_ARRAY_TYPE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_BUFFER_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_CLEAR_VALUE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_INDEX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_INDEXES` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_LOGIC_OP` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_MATERIAL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_MATERIAL_FACE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_MATERIAL_PARAMETER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_MATRIX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_MATRIX_STACK_DEPTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_TABLE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_TABLE_ALPHA_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_TABLE_BIAS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_TABLE_BLUE_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_TABLE_FORMAT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_TABLE_GREEN_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_TABLE_INTENSITY_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_TABLE_LUMINANCE_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_TABLE_RED_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_TABLE_SCALE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_TABLE_WIDTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COLOR_WRITEMASK` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COMBINE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COMBINE_ALPHA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COMBINE_RGB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COMPILE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COMPILE_AND_EXECUTE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COMPRESSED_ALPHA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COMPRESSED_INTENSITY` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COMPRESSED_LUMINANCE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COMPRESSED_LUMINANCE_ALPHA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COMPRESSED_RGB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COMPRESSED_RGBA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COMPRESSED_TEXTURE_FORMATS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CONSTANT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CONSTANT_ALPHA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CONSTANT_ATTENUATION` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CONSTANT_BORDER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CONSTANT_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CONVOLUTION_1D` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CONVOLUTION_2D` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CONVOLUTION_BORDER_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CONVOLUTION_BORDER_MODE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CONVOLUTION_FILTER_BIAS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CONVOLUTION_FILTER_SCALE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CONVOLUTION_FORMAT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CONVOLUTION_HEIGHT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CONVOLUTION_WIDTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COPY` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COPY_INVERTED` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_COPY_PIXEL_TOKEN` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CULL_FACE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CULL_FACE_MODE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CURRENT_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CURRENT_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CURRENT_INDEX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CURRENT_NORMAL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CURRENT_RASTER_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CURRENT_RASTER_DISTANCE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CURRENT_RASTER_INDEX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CURRENT_RASTER_POSITION` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CURRENT_RASTER_POSITION_VALID` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CURRENT_RASTER_TEXTURE_COORDS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CURRENT_TEXTURE_COORDS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_CW` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DECAL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DECR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DEPTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DEPTH_BIAS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DEPTH_BITS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DEPTH_BUFFER_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DEPTH_CLEAR_VALUE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DEPTH_COMPONENT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DEPTH_FUNC` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DEPTH_RANGE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DEPTH_SCALE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DEPTH_TEST` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DEPTH_WRITEMASK` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DIFFUSE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DITHER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DOMAIN` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DONT_CARE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DOT3_RGB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DOT3_RGBA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DOUBLE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DOUBLEBUFFER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DRAW_BUFFER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DRAW_PIXEL_TOKEN` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DST_ALPHA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_DST_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_EDGE_FLAG` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_EDGE_FLAG_ARRAY` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_EDGE_FLAG_ARRAY_POINTER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_EDGE_FLAG_ARRAY_STRIDE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_EMISSION` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ENABLE_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_EQUAL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_EQUIV` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_EVAL_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_EXP` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_EXP2` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_EXTENSIONS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_EYE_LINEAR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_EYE_PLANE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FALSE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FASTEST` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FEEDBACK` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FEEDBACK_BUFFER_POINTER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FEEDBACK_BUFFER_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FEEDBACK_BUFFER_TYPE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FILL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FLAT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FLOAT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FOG` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FOG_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FOG_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FOG_DENSITY` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FOG_END` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FOG_HINT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FOG_INDEX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FOG_MODE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FOG_START` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FRONT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FRONT_AND_BACK` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FRONT_FACE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FRONT_LEFT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FRONT_RIGHT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FUNC_ADD` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FUNC_REVERSE_SUBTRACT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_FUNC_SUBTRACT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_GEQUAL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_GREATER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_GREEN` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_GREEN_BIAS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_GREEN_BITS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_GREEN_SCALE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_HINT_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_HISTOGRAM` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_HISTOGRAM_ALPHA_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_HISTOGRAM_BLUE_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_HISTOGRAM_FORMAT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_HISTOGRAM_GREEN_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_HISTOGRAM_LUMINANCE_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_HISTOGRAM_RED_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_HISTOGRAM_SINK` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_HISTOGRAM_WIDTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INCR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INDEX_ARRAY` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INDEX_ARRAY_POINTER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INDEX_ARRAY_STRIDE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INDEX_ARRAY_TYPE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INDEX_BITS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INDEX_CLEAR_VALUE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INDEX_LOGIC_OP` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INDEX_MODE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INDEX_OFFSET` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INDEX_SHIFT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INDEX_WRITEMASK` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INTENSITY` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INTENSITY12` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INTENSITY16` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INTENSITY4` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INTENSITY8` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INTERPOLATE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INVALID_ENUM` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INVALID_OPERATION` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INVALID_VALUE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_INVERT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_KEEP` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LEFT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LEQUAL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LESS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LIGHT0` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LIGHT1` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LIGHT2` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LIGHT3` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LIGHT4` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LIGHT5` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LIGHT6` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LIGHT7` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LIGHTING` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LIGHTING_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LIGHT_MODEL_AMBIENT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LIGHT_MODEL_COLOR_CONTROL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LIGHT_MODEL_LOCAL_VIEWER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LIGHT_MODEL_TWO_SIDE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINEAR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINEAR_ATTENUATION` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINEAR_MIPMAP_LINEAR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINEAR_MIPMAP_NEAREST` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINES` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINE_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINE_LOOP` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINE_RESET_TOKEN` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINE_SMOOTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINE_SMOOTH_HINT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINE_STIPPLE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINE_STIPPLE_PATTERN` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINE_STIPPLE_REPEAT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINE_STRIP` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINE_TOKEN` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINE_WIDTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINE_WIDTH_GRANULARITY` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LINE_WIDTH_RANGE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LIST_BASE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LIST_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LIST_INDEX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LIST_MODE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LOAD` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LOGIC_OP` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LOGIC_OP_MODE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LUMINANCE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LUMINANCE12` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LUMINANCE12_ALPHA12` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LUMINANCE12_ALPHA4` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LUMINANCE16` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LUMINANCE16_ALPHA16` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LUMINANCE4` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LUMINANCE4_ALPHA4` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LUMINANCE6_ALPHA2` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LUMINANCE8` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LUMINANCE8_ALPHA8` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_LUMINANCE_ALPHA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP1_COLOR_4` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP1_GRID_DOMAIN` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP1_GRID_SEGMENTS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP1_INDEX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP1_NORMAL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP1_TEXTURE_COORD_1` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP1_TEXTURE_COORD_2` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP1_TEXTURE_COORD_3` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP1_TEXTURE_COORD_4` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP1_VERTEX_3` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP1_VERTEX_4` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP2_COLOR_4` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP2_GRID_DOMAIN` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP2_GRID_SEGMENTS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP2_INDEX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP2_NORMAL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP2_TEXTURE_COORD_1` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP2_TEXTURE_COORD_2` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP2_TEXTURE_COORD_3` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP2_TEXTURE_COORD_4` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP2_VERTEX_3` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP2_VERTEX_4` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAP_STENCIL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MATRIX_MODE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_3D_TEXTURE_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_ATTRIB_STACK_DEPTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_CLIENT_ATTRIB_STACK_DEPTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_CLIP_PLANES` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_COLOR_MATRIX_STACK_DEPTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_CONVOLUTION_HEIGHT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_CONVOLUTION_WIDTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_CUBE_MAP_TEXTURE_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_ELEMENTS_INDICES` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_ELEMENTS_VERTICES` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_EVAL_ORDER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_LIGHTS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_LIST_NESTING` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_MODELVIEW_STACK_DEPTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_NAME_STACK_DEPTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_PIXEL_MAP_TABLE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_PROJECTION_STACK_DEPTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_TEXTURE_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_TEXTURE_STACK_DEPTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_TEXTURE_UNITS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_TEXTURE_UNITS_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MAX_VIEWPORT_DIMS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MIN` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MINMAX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MINMAX_FORMAT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MINMAX_SINK` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MODELVIEW` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MODELVIEW_MATRIX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MODELVIEW_STACK_DEPTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MODULATE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MULT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MULTISAMPLE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_MULTISAMPLE_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_N3F_V3F` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NAME_STACK_DEPTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NAND` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NEAREST` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NEAREST_MIPMAP_LINEAR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NEAREST_MIPMAP_NEAREST` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NEVER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NICEST` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NONE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NOOP` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NORMALIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NORMAL_ARRAY` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NORMAL_ARRAY_POINTER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NORMAL_ARRAY_STRIDE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NORMAL_ARRAY_TYPE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NORMAL_MAP` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NOTEQUAL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NO_ERROR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_NUM_COMPRESSED_TEXTURE_FORMATS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_OBJECT_LINEAR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_OBJECT_PLANE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ONE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ONE_MINUS_CONSTANT_ALPHA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ONE_MINUS_CONSTANT_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ONE_MINUS_DST_ALPHA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ONE_MINUS_DST_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ONE_MINUS_SRC_ALPHA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ONE_MINUS_SRC_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_OPERAND0_ALPHA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_OPERAND0_RGB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_OPERAND1_ALPHA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_OPERAND1_RGB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_OPERAND2_ALPHA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_OPERAND2_RGB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_OR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ORDER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_OR_INVERTED` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_OR_REVERSE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_OUT_OF_MEMORY` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PACK_ALIGNMENT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PACK_IMAGE_HEIGHT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PACK_LSB_FIRST` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PACK_ROW_LENGTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PACK_SKIP_IMAGES` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PACK_SKIP_PIXELS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PACK_SKIP_ROWS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PACK_SWAP_BYTES` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PASS_THROUGH_TOKEN` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PERSPECTIVE_CORRECTION_HINT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_A_TO_A` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_A_TO_A_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_B_TO_B` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_B_TO_B_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_G_TO_G` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_G_TO_G_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_I_TO_A` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_I_TO_A_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_I_TO_B` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_I_TO_B_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_I_TO_G` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_I_TO_G_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_I_TO_I` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_I_TO_I_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_I_TO_R` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_I_TO_R_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_R_TO_R` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_R_TO_R_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_S_TO_S` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MAP_S_TO_S_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PIXEL_MODE_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POINT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POINTS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POINT_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POINT_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POINT_SIZE_GRANULARITY` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POINT_SIZE_RANGE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POINT_SMOOTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POINT_SMOOTH_HINT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POINT_TOKEN` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POLYGON` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POLYGON_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POLYGON_MODE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POLYGON_OFFSET_FACTOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POLYGON_OFFSET_FILL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POLYGON_OFFSET_LINE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POLYGON_OFFSET_POINT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POLYGON_OFFSET_UNITS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POLYGON_SMOOTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POLYGON_SMOOTH_HINT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POLYGON_STIPPLE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POLYGON_STIPPLE_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POLYGON_TOKEN` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POSITION` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POST_COLOR_MATRIX_ALPHA_BIAS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POST_COLOR_MATRIX_ALPHA_SCALE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POST_COLOR_MATRIX_BLUE_BIAS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POST_COLOR_MATRIX_BLUE_SCALE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POST_COLOR_MATRIX_COLOR_TABLE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POST_COLOR_MATRIX_GREEN_BIAS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POST_COLOR_MATRIX_GREEN_SCALE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POST_COLOR_MATRIX_RED_BIAS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POST_COLOR_MATRIX_RED_SCALE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POST_CONVOLUTION_ALPHA_BIAS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POST_CONVOLUTION_ALPHA_SCALE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POST_CONVOLUTION_BLUE_BIAS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POST_CONVOLUTION_BLUE_SCALE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POST_CONVOLUTION_COLOR_TABLE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POST_CONVOLUTION_GREEN_BIAS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POST_CONVOLUTION_GREEN_SCALE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POST_CONVOLUTION_RED_BIAS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_POST_CONVOLUTION_RED_SCALE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PREVIOUS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PRIMARY_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PROJECTION` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PROJECTION_MATRIX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PROJECTION_STACK_DEPTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PROXY_COLOR_TABLE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PROXY_HISTOGRAM` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PROXY_POST_COLOR_MATRIX_COLOR_TABLE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PROXY_POST_CONVOLUTION_COLOR_TABLE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PROXY_TEXTURE_1D` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PROXY_TEXTURE_2D` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PROXY_TEXTURE_3D` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_PROXY_TEXTURE_CUBE_MAP` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_Q` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_QUADRATIC_ATTENUATION` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_QUADS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_QUAD_STRIP` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_R` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_R3_G3_B2` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_READ_BUFFER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RED` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_REDUCE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RED_BIAS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RED_BITS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RED_SCALE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_REFLECTION_MAP` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RENDER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RENDERER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RENDER_MODE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_REPEAT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_REPLACE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_REPLICATE_BORDER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RESCALE_NORMAL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RETURN` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RGB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RGB10` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RGB10_A2` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RGB12` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RGB16` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RGB4` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RGB5` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RGB5_A1` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RGB8` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RGBA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RGBA12` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RGBA16` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RGBA2` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RGBA4` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RGBA8` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RGBA_MODE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RGB_SCALE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_RIGHT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_S` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SAMPLES` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SAMPLE_ALPHA_TO_COVERAGE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SAMPLE_ALPHA_TO_ONE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SAMPLE_BUFFERS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SAMPLE_COVERAGE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SAMPLE_COVERAGE_INVERT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SAMPLE_COVERAGE_VALUE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SCISSOR_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SCISSOR_BOX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SCISSOR_TEST` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SELECT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SELECTION_BUFFER_POINTER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SELECTION_BUFFER_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SEPARABLE_2D` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SEPARATE_SPECULAR_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SET` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SHADE_MODEL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SHININESS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SHORT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SINGLE_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SMOOTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SMOOTH_LINE_WIDTH_GRANULARITY` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SMOOTH_LINE_WIDTH_RANGE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SMOOTH_POINT_SIZE_GRANULARITY` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SMOOTH_POINT_SIZE_RANGE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SOURCE0_ALPHA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SOURCE0_RGB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SOURCE1_ALPHA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SOURCE1_RGB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SOURCE2_ALPHA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SOURCE2_RGB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SPECULAR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SPHERE_MAP` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SPOT_CUTOFF` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SPOT_DIRECTION` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SPOT_EXPONENT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SRC_ALPHA` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SRC_ALPHA_SATURATE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SRC_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_STACK_OVERFLOW` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_STACK_UNDERFLOW` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_STENCIL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_STENCIL_BITS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_STENCIL_BUFFER_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_STENCIL_CLEAR_VALUE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_STENCIL_FAIL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_STENCIL_FUNC` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_STENCIL_INDEX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_STENCIL_PASS_DEPTH_FAIL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_STENCIL_PASS_DEPTH_PASS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_STENCIL_REF` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_STENCIL_TEST` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_STENCIL_VALUE_MASK` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_STENCIL_WRITEMASK` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_STEREO` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SUBPIXEL_BITS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_SUBTRACT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_T` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_T2F_C3F_V3F` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_T2F_C4F_N3F_V3F` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_T2F_C4UB_V3F` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_T2F_N3F_V3F` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_T2F_V3F` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_T4F_C4F_N3F_V4F` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_T4F_V4F` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TABLE_TOO_LARGE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE0` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE0_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE1` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE10` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE10_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE11` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE11_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE12` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE12_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE13` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE13_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE14` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE14_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE15` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE15_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE16` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE16_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE17` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE17_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE18` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE18_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE19` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE19_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE1_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE2` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE20` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE20_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE21` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE21_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE22` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE22_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE23` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE23_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE24` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE24_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE25` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE25_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE26` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE26_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE27` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE27_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE28` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE28_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE29` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE29_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE2_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE3` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE30` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE30_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE31` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE31_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE3_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE4` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE4_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE5` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE5_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE6` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE6_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE7` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE7_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE8` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE8_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE9` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE9_ARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_1D` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_2D` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_3D` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_ALPHA_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_BASE_LEVEL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_BINDING_1D` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_BINDING_2D` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_BINDING_3D` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_BINDING_CUBE_MAP` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_BLUE_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_BORDER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_BORDER_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_COMPONENTS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_COMPRESSED` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_COMPRESSED_IMAGE_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_COMPRESSION_HINT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_COORD_ARRAY` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_COORD_ARRAY_POINTER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_COORD_ARRAY_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_COORD_ARRAY_STRIDE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_COORD_ARRAY_TYPE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_CUBE_MAP` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_CUBE_MAP_NEGATIVE_X` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_CUBE_MAP_NEGATIVE_Y` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_CUBE_MAP_NEGATIVE_Z` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_CUBE_MAP_POSITIVE_X` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_CUBE_MAP_POSITIVE_Y` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_CUBE_MAP_POSITIVE_Z` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_DEPTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_ENV` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_ENV_COLOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_ENV_MODE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_GEN_MODE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_GEN_Q` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_GEN_R` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_GEN_S` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_GEN_T` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_GREEN_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_HEIGHT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_INTENSITY_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_INTERNAL_FORMAT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_LUMINANCE_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_MAG_FILTER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_MATRIX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_MAX_LEVEL` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_MAX_LOD` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_MIN_FILTER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_MIN_LOD` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_PRIORITY` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_RED_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_RESIDENT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_STACK_DEPTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_WIDTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_WRAP_R` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_WRAP_S` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TEXTURE_WRAP_T` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TRANSFORM_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TRANSPOSE_COLOR_MATRIX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TRANSPOSE_MODELVIEW_MATRIX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TRANSPOSE_PROJECTION_MATRIX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TRANSPOSE_TEXTURE_MATRIX` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TRIANGLES` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TRIANGLE_FAN` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TRIANGLE_STRIP` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_TRUE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNPACK_ALIGNMENT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNPACK_IMAGE_HEIGHT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNPACK_LSB_FIRST` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNPACK_ROW_LENGTH` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNPACK_SKIP_IMAGES` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNPACK_SKIP_PIXELS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNPACK_SKIP_ROWS` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNPACK_SWAP_BYTES` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNSIGNED_BYTE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNSIGNED_BYTE_2_3_3_REV` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNSIGNED_BYTE_3_3_2` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNSIGNED_INT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNSIGNED_INT_10_10_10_2` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNSIGNED_INT_2_10_10_10_REV` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNSIGNED_INT_8_8_8_8` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNSIGNED_INT_8_8_8_8_REV` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNSIGNED_SHORT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNSIGNED_SHORT_1_5_5_5_REV` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNSIGNED_SHORT_4_4_4_4` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNSIGNED_SHORT_4_4_4_4_REV` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNSIGNED_SHORT_5_5_5_1` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNSIGNED_SHORT_5_6_5` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_UNSIGNED_SHORT_5_6_5_REV` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_V2F` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_V3F` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_VENDOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_VERSION` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_VERTEX_ARRAY` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_VERTEX_ARRAY_POINTER` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_VERTEX_ARRAY_SIZE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_VERTEX_ARRAY_STRIDE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_VERTEX_ARRAY_TYPE` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_VIEWPORT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_VIEWPORT_BIT` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_XOR` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ZERO` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ZOOM_X` | `(std ffi gl)`, `(thunderchez gl)` |
| `GL_ZOOM_Y` | `(std ffi gl)`, `(thunderchez gl)` |
| `gadt-constructor` | `(std typed gadt)` |
| `gadt-fields` | `(std typed gadt)` |
| `gadt-match` | `(std typed gadt)` |
| `gadt-tag` | `(std typed gadt)` |
| `gadt?` | `(std typed gadt)` |
| `gambit-cpu-count` | `(std compat gambit)` |
| `gambit-current-time-milliseconds` | `(std compat gambit)` |
| `gambit-heap-size` | `(std compat gambit)` |
| `gambit-object->string` | `(std compat gambit)` |
| `gappend` | `(std srfi srfi-121)`, `(std srfi srfi-158)` |
| `gauge-dec!` | `(std metrics)` |
| `gauge-inc!` | `(std metrics)` |
| `gauge-set!` | `(std metrics)` |
| `gauge-value` | `(std metrics)` |
| `gauge?` | `(std metrics)` |
| `gc-all-forms` | `(jerboa wasm gc)` |
| `gc-allocator-forms` | `(jerboa wasm gc)` |
| `gc-collect-and-report` | `(std debug heap)` |
| `gc-count` | `(std debug heap)` |
| `gc-memory-grow-forms` | `(jerboa wasm gc)` |
| `gc-root-stack-forms` | `(jerboa wasm gc)` |
| `gc-time-ms` | `(std debug heap)` |
| `gcombine` | `(std srfi srfi-121)`, `(std srfi srfi-158)` |
| `gcons*` | `(std srfi srfi-158)` |
| `gcounter-increment!` | `(std actor crdt)` |
| `gcounter-merge!` | `(std actor crdt)` |
| `gcounter-state` | `(std actor crdt)` |
| `gcounter-value` | `(std actor crdt)` |
| `gcounter?` | `(std actor crdt)` |
| `gdelete-neighbor-dups` | `(std srfi srfi-158)` |
| `gdrop` | `(std srfi srfi-158)` |
| `gen-bind` | `(std proptest)`, `(std test quickcheck)` |
| `gen-bool` | `(std test quickcheck)` |
| `gen-boolean` | `(std proptest)` |
| `gen-char` | `(std proptest)`, `(std test quickcheck)` |
| `gen-choose` | `(std test quickcheck)` |
| `gen-filter` | `(std test quickcheck)` |
| `gen-frequency` | `(std proptest)` |
| `gen-int` | `(std test quickcheck)` |
| `gen-integer` | `(std proptest)` |
| `gen-list` | `(std proptest)`, `(std test quickcheck)` |
| `gen-map` | `(std proptest)`, `(std test quickcheck)` |
| `gen-nat` | `(std proptest)`, `(std test quickcheck)` |
| `gen-one-of` | `(std proptest)`, `(std test quickcheck)` |
| `gen-pair` | `(std test quickcheck)` |
| `gen-real` | `(std proptest)` |
| `gen-sample` | `(std proptest)` |
| `gen-sized` | `(std test quickcheck)` |
| `gen-string` | `(std proptest)`, `(std test quickcheck)` |
| `gen-such-that` | `(std proptest)` |
| `gen-symbol` | `(std proptest)` |
| `gen-tuple` | `(std proptest)` |
| `gen-vector` | `(std proptest)`, `(std test quickcheck)` |
| `gen:bind` | `(std test check)` |
| `gen:boolean` | `(std test check)` |
| `gen:char` | `(std test check)` |
| `gen:choose` | `(std test check)` |
| `gen:elements` | `(std test check)` |
| `gen:fmap` | `(std test check)` |
| `gen:frequency` | `(std test check)` |
| `gen:generate` | `(std test check)` |
| `gen:hash-table` | `(std test check)` |
| `gen:integer` | `(std test check)` |
| `gen:list` | `(std test check)` |
| `gen:nat` | `(std test check)` |
| `gen:no-shrink` | `(std test check)` |
| `gen:one-of` | `(std test check)` |
| `gen:pair` | `(std test check)` |
| `gen:real` | `(std test check)` |
| `gen:return` | `(std test check)` |
| `gen:sample` | `(std test check)` |
| `gen:sized` | `(std test check)` |
| `gen:string` | `(std test check)` |
| `gen:such-that` | `(std test check)` |
| `gen:symbol` | `(std test check)` |
| `gen:tuple` | `(std test check)` |
| `gen:vector` | `(std test check)` |
| `generate` | `(std quasiquote-types)` |
| `generate-bash-completion` | `(std cli completion)` |
| `generate-html` | `(std doc generator)` |
| `generate-main-c` | `(jerboa build)` |
| `generate-markdown` | `(std doc generator)` |
| `generate-matcher-code` | `(std text regex-compile)` |
| `generate-self-signed-cert!` | `(std crypto x509)` |
| `generate-wpo-files` | `(std compile)` |
| `generate-zsh-completion` | `(std cli completion)` |
| `generator` | `(std srfi srfi-121)`, `(std srfi srfi-158)` |
| `generator->list` | `(std srfi srfi-121)`, `(std srfi srfi-158)` |
| `generator->lseq` | `(std srfi srfi-127)` |
| `generator->string` | `(std srfi srfi-158)` |
| `generator->vector` | `(std srfi srfi-121)`, `(std srfi srfi-158)` |
| `generator-any` | `(std srfi srfi-158)` |
| `generator-count` | `(std srfi srfi-158)` |
| `generator-drop` | `(std srfi srfi-121)` |
| `generator-every` | `(std srfi srfi-158)` |
| `generator-filter` | `(std srfi srfi-121)` |
| `generator-find` | `(std srfi srfi-158)` |
| `generator-fold` | `(std srfi srfi-121)`, `(std srfi srfi-158)` |
| `generator-for-each` | `(std srfi srfi-121)`, `(std srfi srfi-158)` |
| `generator-map` | `(std srfi srfi-121)` |
| `generator-map->list` | `(std srfi srfi-158)` |
| `generator-take` | `(std srfi srfi-121)` |
| `generator?` | `(std proptest)` |
| `generic-dispatch` | `(std generic)` |
| `generic-function-methods` | `(std clos)` |
| `generic-function-name` | `(std clos)` |
| `genident` | `(std stxutil)` |
| `gensym-stage` | `(std staging2)` |
| `gerbil-import` | `(std compat gerbil-import)` |
| `gerbil-parameterize` | `(std gambit-compat)` |
| `get` | `(jerboa clojure)`, `(std clojure)` |
| `get-doc` | `(std doc)` |
| `get-environment-variables` | `(std gambit-compat)` |
| `get-file-info` | `(std os file-info)` |
| `get-in` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc nested)` |
| `get-method` | `(std multi)` |
| `get-output-u8vector` | `(std gambit-compat)` |
| `get-test-output` | `(std effect io)` |
| `getenv` | `(jerboa core)`, `(std gambit-compat)`, `(std os env)` |
| `getenv*` | `(std gambit-compat)` |
| `getenv-int` | `(std test fuzz)` |
| `getopt` | `(std cli getopt)` |
| `getopt-display-help` | `(std cli getopt)` |
| `getopt-display-help-topic` | `(std cli getopt)` |
| `getopt-error?` | `(std cli getopt)` |
| `getopt-object?` | `(std cli getopt)` |
| `getopt-parse` | `(std cli getopt)` |
| `getopt?` | `(std cli getopt)` |
| `getpid` | `(jerboa core)`, `(std gambit-compat)` |
| `getprop` | `(std symbol-property)` |
| `gfilter` | `(std srfi srfi-158)` |
| `gflatten` | `(std srfi srfi-158)` |
| `glAccum` | `(std ffi gl)`, `(thunderchez gl)` |
| `glActiveTexture` | `(std ffi gl)`, `(thunderchez gl)` |
| `glActiveTextureARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glAlphaFunc` | `(std ffi gl)`, `(thunderchez gl)` |
| `glAreTexturesResident` | `(std ffi gl)`, `(thunderchez gl)` |
| `glArrayElement` | `(std ffi gl)`, `(thunderchez gl)` |
| `glBegin` | `(std ffi gl)`, `(thunderchez gl)` |
| `glBindTexture` | `(std ffi gl)`, `(thunderchez gl)` |
| `glBitmap` | `(std ffi gl)`, `(thunderchez gl)` |
| `glBlendColor` | `(std ffi gl)`, `(thunderchez gl)` |
| `glBlendEquation` | `(std ffi gl)`, `(thunderchez gl)` |
| `glBlendFunc` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCallList` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCallLists` | `(std ffi gl)`, `(thunderchez gl)` |
| `glClear` | `(std ffi gl)`, `(thunderchez gl)` |
| `glClearAccum` | `(std ffi gl)`, `(thunderchez gl)` |
| `glClearColor` | `(std ffi gl)`, `(thunderchez gl)` |
| `glClearDepth` | `(std ffi gl)`, `(thunderchez gl)` |
| `glClearIndex` | `(std ffi gl)`, `(thunderchez gl)` |
| `glClearStencil` | `(std ffi gl)`, `(thunderchez gl)` |
| `glClientActiveTexture` | `(std ffi gl)`, `(thunderchez gl)` |
| `glClientActiveTextureARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glClipPlane` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor3b` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor3bv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor3d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor3dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor3f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor3fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor3i` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor3iv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor3s` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor3sv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor3ub` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor3ubv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor3ui` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor3uiv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor3us` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor3usv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor4b` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor4bv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor4d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor4dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor4f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor4fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor4i` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor4iv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor4s` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor4sv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor4ub` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor4ubv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor4ui` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor4uiv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor4us` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColor4usv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColorMask` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColorMaterial` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColorPointer` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColorSubTable` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColorTable` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColorTableParameterfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glColorTableParameteriv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCompressedTexImage1D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCompressedTexImage2D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCompressedTexImage3D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCompressedTexSubImage1D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCompressedTexSubImage2D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCompressedTexSubImage3D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glConvolutionFilter1D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glConvolutionFilter2D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glConvolutionParameterf` | `(std ffi gl)`, `(thunderchez gl)` |
| `glConvolutionParameterfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glConvolutionParameteri` | `(std ffi gl)`, `(thunderchez gl)` |
| `glConvolutionParameteriv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCopyColorSubTable` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCopyColorTable` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCopyConvolutionFilter1D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCopyConvolutionFilter2D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCopyPixels` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCopyTexImage1D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCopyTexImage2D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCopyTexSubImage1D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCopyTexSubImage2D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCopyTexSubImage3D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glCullFace` | `(std ffi gl)`, `(thunderchez gl)` |
| `glDeleteLists` | `(std ffi gl)`, `(thunderchez gl)` |
| `glDeleteTextures` | `(std ffi gl)`, `(thunderchez gl)` |
| `glDepthFunc` | `(std ffi gl)`, `(thunderchez gl)` |
| `glDepthMask` | `(std ffi gl)`, `(thunderchez gl)` |
| `glDepthRange` | `(std ffi gl)`, `(thunderchez gl)` |
| `glDisable` | `(std ffi gl)`, `(thunderchez gl)` |
| `glDisableClientState` | `(std ffi gl)`, `(thunderchez gl)` |
| `glDrawArrays` | `(std ffi gl)`, `(thunderchez gl)` |
| `glDrawBuffer` | `(std ffi gl)`, `(thunderchez gl)` |
| `glDrawElements` | `(std ffi gl)`, `(thunderchez gl)` |
| `glDrawPixels` | `(std ffi gl)`, `(thunderchez gl)` |
| `glDrawRangeElements` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEdgeFlag` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEdgeFlagPointer` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEdgeFlagv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEnable` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEnableClientState` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEnd` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEndList` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEvalCoord1d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEvalCoord1dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEvalCoord1f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEvalCoord1fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEvalCoord2d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEvalCoord2dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEvalCoord2f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEvalCoord2fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEvalMesh1` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEvalMesh2` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEvalPoint1` | `(std ffi gl)`, `(thunderchez gl)` |
| `glEvalPoint2` | `(std ffi gl)`, `(thunderchez gl)` |
| `glFeedbackBuffer` | `(std ffi gl)`, `(thunderchez gl)` |
| `glFinish` | `(std ffi gl)`, `(thunderchez gl)` |
| `glFlush` | `(std ffi gl)`, `(thunderchez gl)` |
| `glFogf` | `(std ffi gl)`, `(thunderchez gl)` |
| `glFogfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glFogi` | `(std ffi gl)`, `(thunderchez gl)` |
| `glFogiv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glFrontFace` | `(std ffi gl)`, `(thunderchez gl)` |
| `glFrustum` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGenLists` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGenTextures` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetBooleanv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetClipPlane` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetColorTable` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetColorTableParameterfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetColorTableParameteriv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetCompressedTexImage` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetConvolutionFilter` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetConvolutionParameterfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetConvolutionParameteriv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetDoublev` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetError` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetFloatv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetHistogram` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetHistogramParameterfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetHistogramParameteriv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetIntegerv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetLightfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetLightiv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetMapdv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetMapfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetMapiv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetMaterialfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetMaterialiv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetMinmax` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetMinmaxParameterfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetMinmaxParameteriv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetPixelMapfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetPixelMapuiv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetPixelMapusv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetPointerv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetPolygonStipple` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetSeparableFilter` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetString` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetTexEnvfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetTexEnviv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetTexGendv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetTexGenfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetTexGeniv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetTexImage` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetTexLevelParameterfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetTexLevelParameteriv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetTexParameterfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glGetTexParameteriv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glHint` | `(std ffi gl)`, `(thunderchez gl)` |
| `glHistogram` | `(std ffi gl)`, `(thunderchez gl)` |
| `glIndexMask` | `(std ffi gl)`, `(thunderchez gl)` |
| `glIndexPointer` | `(std ffi gl)`, `(thunderchez gl)` |
| `glIndexd` | `(std ffi gl)`, `(thunderchez gl)` |
| `glIndexdv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glIndexf` | `(std ffi gl)`, `(thunderchez gl)` |
| `glIndexfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glIndexi` | `(std ffi gl)`, `(thunderchez gl)` |
| `glIndexiv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glIndexs` | `(std ffi gl)`, `(thunderchez gl)` |
| `glIndexsv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glIndexub` | `(std ffi gl)`, `(thunderchez gl)` |
| `glIndexubv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glInitNames` | `(std ffi gl)`, `(thunderchez gl)` |
| `glInterleavedArrays` | `(std ffi gl)`, `(thunderchez gl)` |
| `glIsEnabled` | `(std ffi gl)`, `(thunderchez gl)` |
| `glIsList` | `(std ffi gl)`, `(thunderchez gl)` |
| `glIsTexture` | `(std ffi gl)`, `(thunderchez gl)` |
| `glLightModelf` | `(std ffi gl)`, `(thunderchez gl)` |
| `glLightModelfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glLightModeli` | `(std ffi gl)`, `(thunderchez gl)` |
| `glLightModeliv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glLightf` | `(std ffi gl)`, `(thunderchez gl)` |
| `glLightfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glLighti` | `(std ffi gl)`, `(thunderchez gl)` |
| `glLightiv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glLineStipple` | `(std ffi gl)`, `(thunderchez gl)` |
| `glLineWidth` | `(std ffi gl)`, `(thunderchez gl)` |
| `glListBase` | `(std ffi gl)`, `(thunderchez gl)` |
| `glLoadIdentity` | `(std ffi gl)`, `(thunderchez gl)` |
| `glLoadMatrixd` | `(std ffi gl)`, `(thunderchez gl)` |
| `glLoadMatrixf` | `(std ffi gl)`, `(thunderchez gl)` |
| `glLoadName` | `(std ffi gl)`, `(thunderchez gl)` |
| `glLoadTransposeMatrixd` | `(std ffi gl)`, `(thunderchez gl)` |
| `glLoadTransposeMatrixf` | `(std ffi gl)`, `(thunderchez gl)` |
| `glLogicOp` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMap1d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMap1f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMap2d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMap2f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMapGrid1d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMapGrid1f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMapGrid2d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMapGrid2f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMaterialf` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMaterialfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMateriali` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMaterialiv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMatrixMode` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMinmax` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultMatrixd` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultMatrixf` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultTransposeMatrixd` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultTransposeMatrixf` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord1d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord1dARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord1dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord1dvARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord1f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord1fARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord1fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord1fvARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord1i` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord1iARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord1iv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord1ivARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord1s` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord1sARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord1sv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord1svARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord2d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord2dARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord2dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord2dvARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord2f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord2fARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord2fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord2fvARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord2i` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord2iARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord2iv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord2ivARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord2s` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord2sARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord2sv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord2svARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord3d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord3dARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord3dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord3dvARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord3f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord3fARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord3fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord3fvARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord3i` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord3iARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord3iv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord3ivARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord3s` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord3sARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord3sv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord3svARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord4d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord4dARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord4dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord4dvARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord4f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord4fARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord4fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord4fvARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord4i` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord4iARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord4iv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord4ivARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord4s` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord4sARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord4sv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glMultiTexCoord4svARB` | `(std ffi gl)`, `(thunderchez gl)` |
| `glNewList` | `(std ffi gl)`, `(thunderchez gl)` |
| `glNormal3b` | `(std ffi gl)`, `(thunderchez gl)` |
| `glNormal3bv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glNormal3d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glNormal3dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glNormal3f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glNormal3fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glNormal3i` | `(std ffi gl)`, `(thunderchez gl)` |
| `glNormal3iv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glNormal3s` | `(std ffi gl)`, `(thunderchez gl)` |
| `glNormal3sv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glNormalPointer` | `(std ffi gl)`, `(thunderchez gl)` |
| `glOrtho` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPassThrough` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPixelMapfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPixelMapuiv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPixelMapusv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPixelStoref` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPixelStorei` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPixelTransferf` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPixelTransferi` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPixelZoom` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPointSize` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPolygonMode` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPolygonOffset` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPolygonStipple` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPopAttrib` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPopClientAttrib` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPopMatrix` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPopName` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPrioritizeTextures` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPushAttrib` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPushClientAttrib` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPushMatrix` | `(std ffi gl)`, `(thunderchez gl)` |
| `glPushName` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos2d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos2dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos2f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos2fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos2i` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos2iv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos2s` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos2sv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos3d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos3dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos3f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos3fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos3i` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos3iv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos3s` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos3sv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos4d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos4dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos4f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos4fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos4i` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos4iv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos4s` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRasterPos4sv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glReadBuffer` | `(std ffi gl)`, `(thunderchez gl)` |
| `glReadPixels` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRectd` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRectdv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRectf` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRectfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRecti` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRectiv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRects` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRectsv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRenderMode` | `(std ffi gl)`, `(thunderchez gl)` |
| `glResetHistogram` | `(std ffi gl)`, `(thunderchez gl)` |
| `glResetMinmax` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRotated` | `(std ffi gl)`, `(thunderchez gl)` |
| `glRotatef` | `(std ffi gl)`, `(thunderchez gl)` |
| `glSampleCoverage` | `(std ffi gl)`, `(thunderchez gl)` |
| `glScaled` | `(std ffi gl)`, `(thunderchez gl)` |
| `glScalef` | `(std ffi gl)`, `(thunderchez gl)` |
| `glScissor` | `(std ffi gl)`, `(thunderchez gl)` |
| `glSelectBuffer` | `(std ffi gl)`, `(thunderchez gl)` |
| `glSeparableFilter2D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glShadeModel` | `(std ffi gl)`, `(thunderchez gl)` |
| `glStencilFunc` | `(std ffi gl)`, `(thunderchez gl)` |
| `glStencilMask` | `(std ffi gl)`, `(thunderchez gl)` |
| `glStencilOp` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord1d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord1dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord1f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord1fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord1i` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord1iv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord1s` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord1sv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord2d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord2dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord2f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord2fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord2i` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord2iv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord2s` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord2sv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord3d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord3dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord3f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord3fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord3i` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord3iv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord3s` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord3sv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord4d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord4dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord4f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord4fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord4i` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord4iv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord4s` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoord4sv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexCoordPointer` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexEnvf` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexEnvfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexEnvi` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexEnviv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexGend` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexGendv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexGenf` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexGenfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexGeni` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexGeniv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexImage1D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexImage2D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexImage3D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexParameterf` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexParameterfv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexParameteri` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexParameteriv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexSubImage1D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexSubImage2D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTexSubImage3D` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTranslated` | `(std ffi gl)`, `(thunderchez gl)` |
| `glTranslatef` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex2d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex2dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex2f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex2fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex2i` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex2iv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex2s` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex2sv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex3d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex3dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex3f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex3fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex3i` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex3iv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex3s` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex3sv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex4d` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex4dv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex4f` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex4fv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex4i` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex4iv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex4s` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertex4sv` | `(std ffi gl)`, `(thunderchez gl)` |
| `glVertexPointer` | `(std ffi gl)`, `(thunderchez gl)` |
| `glViewport` | `(std ffi gl)`, `(thunderchez gl)` |
| `glob->regex-string` | `(std text glob)` |
| `glob-expand` | `(std text glob)` |
| `glob-filter` | `(std text glob)` |
| `glob-match?` | `(std text glob)` |
| `gluBeginCurve` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluBeginPolygon` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluBeginSurface` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluBeginTrim` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluBuild1DMipmapLevels` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluBuild1DMipmaps` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluBuild2DMipmapLevels` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluBuild2DMipmaps` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluBuild3DMipmapLevels` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluBuild3DMipmaps` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluCheckExtension` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluCylinder` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluDeleteNurbsRenderer` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluDeleteQuadric` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluDeleteTess` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluDisk` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluEndCurve` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluEndPolygon` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluEndSurface` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluEndTrim` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluErrorString` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluGetNurbsProperty` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluGetString` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluGetTessProperty` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluLoadSamplingMatrices` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluLookAt` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluNewNurbsRenderer` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluNewQuadric` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluNewTess` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluNextContour` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluNurbsCallbackData` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluNurbsCallbackDataEXT` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluNurbsCurve` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluNurbsProperty` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluNurbsSurface` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluOrtho2D` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluPartialDisk` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluPerspective` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluPickMatrix` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluProject` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluPwlCurve` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluQuadricDrawStyle` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluQuadricNormals` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluQuadricOrientation` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluQuadricTexture` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluScaleImage` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluSphere` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluTessBeginContour` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluTessBeginPolygon` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluTessEndContour` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluTessEndPolygon` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluTessNormal` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluTessProperty` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluTessVertex` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluUnProject` | `(std ffi glu)`, `(thunderchez glu)` |
| `gluUnProject4` | `(std ffi glu)`, `(thunderchez glu)` |
| `glutAddMenuEntry` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutAddSubMenu` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutAttachMenu` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutBitmapCharacter` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutBitmapLength` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutBitmapWidth` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutButtonBoxFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutChangeToMenuEntry` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutChangeToSubMenu` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutCopyColormap` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutCreateMenu` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutCreateSubWindow` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutCreateWindow` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutDestroyMenu` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutDestroyWindow` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutDetachMenu` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutDeviceGet` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutDialsFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutDisplayFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutEnterGameMode` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutEntryFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutEstablishOverlay` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutExtensionSupported` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutForceJoystickFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutFullScreen` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutGameModeGet` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutGameModeString` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutGet` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutGetColor` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutGetMenu` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutGetModifiers` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutGetProcAddress` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutGetWindow` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutHideOverlay` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutHideWindow` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutIconifyWindow` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutIdleFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutIgnoreKeyRepeat` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutInit` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutInitDisplayMode` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutInitDisplayString` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutInitWindowPosition` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutInitWindowSize` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutJoystickFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutKeyboardFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutKeyboardUpFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutLayerGet` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutLeaveGameMode` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutMainLoop` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutMenuStateFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutMenuStatusFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutMotionFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutMouseFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutOverlayDisplayFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutPassiveMotionFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutPopWindow` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutPositionWindow` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutPostOverlayRedisplay` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutPostRedisplay` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutPostWindowOverlayRedisplay` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutPostWindowRedisplay` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutPushWindow` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutRemoveMenuItem` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutRemoveOverlay` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutReportErrors` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutReshapeFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutReshapeWindow` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSetColor` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSetCursor` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSetIconTitle` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSetKeyRepeat` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSetMenu` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSetWindow` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSetWindowTitle` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSetupVideoResizing` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutShowOverlay` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutShowWindow` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSolidCone` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSolidCube` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSolidDodecahedron` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSolidIcosahedron` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSolidOctahedron` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSolidSphere` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSolidTeapot` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSolidTetrahedron` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSolidTorus` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSpaceballButtonFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSpaceballMotionFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSpaceballRotateFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSpecialFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSpecialUpFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutStopVideoResizing` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutStrokeCharacter` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutStrokeLength` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutStrokeWidth` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutSwapBuffers` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutTabletButtonFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutTabletMotionFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutTimerFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutUseLayer` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutVideoPan` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutVideoResize` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutVideoResizeGet` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutVisibilityFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutWarpPointer` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutWindowStatusFunc` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutWireCone` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutWireCube` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutWireDodecahedron` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutWireIcosahedron` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutWireOctahedron` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutWireSphere` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutWireTeapot` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutWireTetrahedron` | `(std ffi glut)`, `(thunderchez glut)` |
| `glutWireTorus` | `(std ffi glut)`, `(thunderchez glut)` |
| `go` | `(std csp clj)`, `(std csp)` |
| `go-loop` | `(std csp clj)` |
| `go-named` | `(std csp)` |
| `graceful-shutdown!` | `(std component fiber)` |
| `greatest-fixnum` | `(std fixnum)` |
| `green` | `(std cli style)` |
| `gremove` | `(std srfi srfi-158)` |
| `group-by` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+4) |
| `group-consecutive` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `group-n-consecutive` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `group-same` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `grpc-call` | `(std net grpc)` |
| `grpc-call-async` | `(std net grpc)` |
| `grpc-error?` | `(std net grpc)` |
| `grpc-ok?` | `(std net grpc)` |
| `grpc-server-port` | `(std net grpc)` |
| `grpc-server-start!` | `(std net grpc)` |
| `grpc-server-stop!` | `(std net grpc)` |
| `grpc-status` | `(std net grpc)` |
| `gset-add!` | `(std actor crdt)` |
| `gset-member?` | `(std actor crdt)` |
| `gset-merge!` | `(std actor crdt)` |
| `gset-value` | `(std actor crdt)` |
| `gset?` | `(std actor crdt)` |
| `gtake` | `(std srfi srfi-158)` |
| `guard-evt` | `(std event)` |
| `guardian-drain!` | `(std guardian)` |
| `guardian-pool-collect!` | `(std misc guardian-pool)` |
| `guardian-pool-drain!` | `(std misc guardian-pool)` |
| `guardian-pool-register` | `(std misc guardian-pool)` |
| `guardian-pool?` | `(std misc guardian-pool)` |
| `guardian-register!` | `(std guardian)` |
| `gunzip-bytevector` | `(std compress zlib)` |
| `gzip-bytevector` | `(std compress zlib)` |
| `gzip-data?` | `(std compress zlib)` |

### <a name="idx-h"></a>h

| Symbol | Modules |
| --- | --- |
| `HASHTABLE-HEADER-PAYLOAD` | `(jerboa wasm values)` |
| `HEADER-GC-BIT` | `(jerboa wasm values)` |
| `HEADER-SIZE-MASK` | `(jerboa wasm values)` |
| `HEADER-TYPE-MASK` | `(jerboa wasm values)` |
| `HEADER-TYPE-SHIFT` | `(jerboa wasm values)` |
| `HEAP-ALIGN` | `(jerboa wasm values)` |
| `HEAP-BASE` | `(jerboa wasm values)` |
| `hamt->alist` | `(std misc persistent)` |
| `hamt-contains?` | `(std misc persistent)` |
| `hamt-delete` | `(std misc persistent)` |
| `hamt-empty` | `(std misc persistent)` |
| `hamt-fold` | `(std misc persistent)` |
| `hamt-keys` | `(std misc persistent)` |
| `hamt-map` | `(std misc persistent)` |
| `hamt-ref` | `(std misc persistent)` |
| `hamt-set` | `(std misc persistent)` |
| `hamt-size` | `(std misc persistent)` |
| `hamt-values` | `(std misc persistent)` |
| `hamt?` | `(std misc persistent)` |
| `handle` | `(std event)`, `(std misc event)` |
| `handle-initialize` | `(std lsp)` |
| `handle-request` | `(std lsp server)` |
| `handle-shutdown` | `(std lsp)` |
| `handle-text-document-completion` | `(std lsp)` |
| `handle-text-document-definition` | `(std lsp)` |
| `handle-text-document-diagnostic` | `(std lsp)` |
| `handle-text-document-document-symbol` | `(std lsp)` |
| `handle-text-document-hover` | `(std lsp)` |
| `handle-text-document-references` | `(std lsp)` |
| `handle-workspace-symbol` | `(std lsp)` |
| `handler-clause-linear?` | `(std dev cont-mark-opt)` |
| `handler-fusion-stats` | `(std effect fusion)` |
| `hash` | `(jerboa clojure)`, `(jerboa core)`, `(std clojure)`, `(std gambit-compat)` |
| `hash->alist` | `(std misc hash-more)` |
| `hash->list` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `hash->plist` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `hash-any` | `(std misc hash-more)` |
| `hash-clear!` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+5) |
| `hash-constructor` | `(std gambit-compat)` |
| `hash-copy` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+5) |
| `hash-count` | `(std misc hash-more)` |
| `hash-eq` | `(jerboa core)`, `(jerboa runtime)`, `(std gambit-compat)` |
| `hash-eq-literal` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+3) |
| `hash-eq?` | `(jerboa runtime)` |
| `hash-every` | `(std misc hash-more)` |
| `hash-filter` | `(std misc hash-more)` |
| `hash-find` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+5) |
| `hash-fold` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+5) |
| `hash-for-each` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `hash-get` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `hash-has-key?` | `(jerboa clojure)`, `(jerboa prelude)` |
| `hash-intersect` | `(std misc hash-more)` |
| `hash-key?` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `hash-keys` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `hash-keys/list` | `(std misc hash-more)` |
| `hash-length` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `hash-literal` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+3) |
| `hash-map` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+5) |
| `hash-map/values` | `(std misc hash-more)` |
| `hash-merge` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+5) |
| `hash-merge!` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `hash-put!` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `hash-ref` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `hash-ref-lens` | `(std lens)` |
| `hash-ref/default` | `(std misc hash-more)` |
| `hash-remove!` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `hash-set` | `(jerboa clojure)`, `(jerboa prelude)`, `(jerboa runtime)`, `(std clojure)` |
| `hash-table` | `(std srfi srfi-125)` |
| `hash-table->alist` | `(std srfi srfi-125)` |
| `hash-table-contains?` | `(std srfi srfi-125)` |
| `hash-table-copy` | `(std srfi srfi-125)` |
| `hash-table-delete!` | `(std srfi srfi-125)` |
| `hash-table-entries` | `(std srfi srfi-125)` |
| `hash-table-fold` | `(std srfi srfi-125)` |
| `hash-table-for-each` | `(std srfi srfi-125)` |
| `hash-table-keys` | `(std srfi srfi-125)` |
| `hash-table-map` | `(std srfi srfi-125)` |
| `hash-table-map->list` | `(std srfi srfi-125)` |
| `hash-table-ref` | `(std srfi srfi-125)` |
| `hash-table-ref/default` | `(std srfi srfi-125)` |
| `hash-table-set!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std srfi srfi-125)` |
| `hash-table-size` | `(std srfi srfi-125)` |
| `hash-table-update!` | `(std srfi srfi-125)` |
| `hash-table-update!/default` | `(std srfi srfi-125)` |
| `hash-table-values` | `(std srfi srfi-125)` |
| `hash-table?` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+4) |
| `hash-union` | `(std misc hash-more)` |
| `hash-update!` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `hash-value-set!` | `(std misc hash-more)` |
| `hash-values` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `hash-values/list` | `(std misc hash-more)` |
| `hashtable->imap` | `(std immutable)` |
| `header-injection?` | `(std security sanitize)` |
| `headers->alist` | `(std net request)` |
| `health-registry?` | `(std health)` |
| `health-status` | `(std health)` |
| `healthy?` | `(std health)` |
| `heap->list` | `(std misc heap)` |
| `heap->sorted-list` | `(std misc heap)` |
| `heap-clear!` | `(std misc heap)` |
| `heap-empty?` | `(std misc heap)` |
| `heap-extract!` | `(std misc heap)` |
| `heap-insert!` | `(std misc heap)` |
| `heap-peek` | `(std misc heap)` |
| `heap-report` | `(std debug heap)` |
| `heap-size` | `(std debug heap)`, `(std misc heap)` |
| `heap?` | `(std misc heap)` |
| `hex->bn` | `(std crypto bn)` |
| `hex-decode` | `(std text hex)` |
| `hex-encode` | `(std text hex)` |
| `hex-string->u8vector` | `(std text hex)` |
| `highlight-scheme` | `(std misc highlight)` |
| `highlight-scheme/sxml` | `(std misc highlight)` |
| `highlight-to-port` | `(std misc highlight)` |
| `histogram-buckets` | `(std metrics)` |
| `histogram-count` | `(std metrics)` |
| `histogram-observe!` | `(std metrics)` |
| `histogram-sum` | `(std metrics)` |
| `histogram?` | `(std metrics)` |
| `hkt-dispatch` | `(std typed hkt)` |
| `hkt-instance` | `(std typed hkt)` |
| `hkt-instance?` | `(std typed hkt)` |
| `hmac` | `(std crypto hmac)` |
| `hmac-md5` | `(std crypto hmac)` |
| `hmac-sha1` | `(std crypto hmac)` |
| `hmac-sha256` | `(std crypto hmac)` |
| `hmac-sha384` | `(std crypto hmac)` |
| `hmac-sha512` | `(std crypto hmac)` |
| `holding-resource!` | `(std concur deadlock)` |
| `hostname?` | `(std net address)` |
| `hpack-context?` | `(std net http2)` |
| `hpack-decode` | `(std net http2)` |
| `hpack-encode` | `(std net http2)` |
| `hsts-header` | `(std net security-headers)` |
| `html->sxml` | `(std markup html-parser)` |
| `html-attribute-escape` | `(std text html)` |
| `html-escape` | `(std taint)`, `(std text html)` |
| `html-label` | `(std taint)` |
| `html-parse-port` | `(std markup html-parser)` |
| `html-parse-string` | `(std markup html-parser)` |
| `html-strip-tags` | `(std text html)` |
| `html-unescape` | `(std text html)` |
| `http-delete` | `(std net request)` |
| `http-get` | `(std net request)` |
| `http-head` | `(std net request)` |
| `http-limits-max-body-size` | `(std net timeout)` |
| `http-limits-max-header-count` | `(std net timeout)` |
| `http-limits-max-header-size` | `(std net timeout)` |
| `http-limits-max-uri-length` | `(std net timeout)` |
| `http-limits-request-timeout` | `(std net timeout)` |
| `http-limits?` | `(std net timeout)` |
| `http-post` | `(std net request)` |
| `http-post-stream` | `(std net request)` |
| `http-put` | `(std net request)` |
| `http-req-body` | `(std net httpd)` |
| `http-req-client-addr` | `(std net httpd)` |
| `http-req-header` | `(std net httpd)` |
| `http-req-headers` | `(std net httpd)` |
| `http-req-method` | `(std net httpd)` |
| `http-req-path` | `(std net httpd)` |
| `http-req-query` | `(std net httpd)` |
| `http-req-version` | `(std net httpd)` |
| `http-respond` | `(std net httpd)` |
| `http-respond-chunk` | `(std net httpd)` |
| `http-respond-chunk-begin` | `(std net httpd)` |
| `http-respond-chunk-end` | `(std net httpd)` |
| `http-respond-error` | `(std net httpd)` |
| `http-respond-file` | `(std net httpd)` |
| `http-respond-html` | `(std net httpd)` |
| `http-respond-json` | `(std net httpd)` |
| `http-respond-redirect` | `(std net httpd)` |
| `http2-frame-decode` | `(std net http2)` |
| `http2-frame-encode` | `(std net http2)` |
| `http2-frame-flags` | `(std net http2)` |
| `http2-frame-payload` | `(std net http2)` |
| `http2-frame-stream-id` | `(std net http2)` |
| `http2-frame-type` | `(std net http2)` |
| `http2-frame-type-continuation` | `(std net http2)` |
| `http2-frame-type-data` | `(std net http2)` |
| `http2-frame-type-goaway` | `(std net http2)` |
| `http2-frame-type-headers` | `(std net http2)` |
| `http2-frame-type-ping` | `(std net http2)` |
| `http2-frame-type-priority` | `(std net http2)` |
| `http2-frame-type-push-promise` | `(std net http2)` |
| `http2-frame-type-rst-stream` | `(std net http2)` |
| `http2-frame-type-settings` | `(std net http2)` |
| `http2-frame-type-window-update` | `(std net http2)` |
| `httpd-component` | `(std component fiber)` |
| `httpd-config` | `(std net httpd)` |
| `httpd-metrics-connections-active` | `(std net fiber-httpd)` |
| `httpd-metrics-connections-total` | `(std net fiber-httpd)` |
| `httpd-metrics-errors-total` | `(std net fiber-httpd)` |
| `httpd-metrics-requests-total` | `(std net fiber-httpd)` |
| `httpd-metrics-start-time` | `(std net fiber-httpd)` |
| `httpd-metrics?` | `(std net fiber-httpd)` |
| `httpd-route` | `(std net httpd)` |
| `httpd-route-prefix` | `(std net httpd)` |
| `httpd-route-static` | `(std net httpd)` |
| `httpd-start` | `(std net httpd)` |
| `httpd-start-https` | `(std net httpd)` |
| `httpd-stop` | `(std net httpd)` |

### <a name="idx-i"></a>i

| Symbol | Modules |
| --- | --- |
| `IMM-EOF` | `(jerboa wasm values)` |
| `IMM-FALSE` | `(jerboa wasm values)` |
| `IMM-NIL` | `(jerboa wasm values)` |
| `IMM-TRUE` | `(jerboa wasm values)` |
| `IMM-VOID` | `(jerboa wasm values)` |
| `INADDR_ANY` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `INADDR_BROADCAST` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `INADDR_LOOPBACK` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `INADDR_NONE` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `INDEXED-VALS` | `(std specter)` |
| `IN_ACCESS` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_ALL_EVENTS` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_ATTRIB` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_CLOSE` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_CLOSE_NOWRITE` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_CLOSE_WRITE` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_CREATE` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_DELETE` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_DELETE_SELF` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_DONT_FOLLOW` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_EXCL_UNLINK` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_IGNORED` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_ISDIR` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_MASK_ADD` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_MODIFY` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_MOVE` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_MOVED_FROM` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_MOVED_TO` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_MOVE_SELF` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_ONESHOT` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_ONLYDIR` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_OPEN` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_Q_OVERFLOW` | `(std os inotify-native)`, `(std os inotify)` |
| `IN_UNMOUNT` | `(std os inotify-native)`, `(std os inotify)` |
| `Intersection` | `(std typed advanced)` |
| `iappend` | `(std srfi srfi-116)` |
| `icar` | `(std srfi srfi-116)` |
| `icdr` | `(std srfi srfi-116)` |
| `identity` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc func)`, `(std prelude)` |
| `identity-lens` | `(std lens)` |
| `ideque` | `(std srfi srfi-134)` |
| `ideque->list` | `(std srfi srfi-134)` |
| `ideque-add-back` | `(std srfi srfi-134)` |
| `ideque-add-front` | `(std srfi srfi-134)` |
| `ideque-any` | `(std srfi srfi-134)` |
| `ideque-append` | `(std srfi srfi-134)` |
| `ideque-back` | `(std srfi srfi-134)` |
| `ideque-empty?` | `(std srfi srfi-134)` |
| `ideque-every` | `(std srfi srfi-134)` |
| `ideque-filter` | `(std srfi srfi-134)` |
| `ideque-fold` | `(std srfi srfi-134)` |
| `ideque-fold-right` | `(std srfi srfi-134)` |
| `ideque-for-each` | `(std srfi srfi-134)` |
| `ideque-front` | `(std srfi srfi-134)` |
| `ideque-length` | `(std srfi srfi-134)` |
| `ideque-map` | `(std srfi srfi-134)` |
| `ideque-remove-back` | `(std srfi srfi-134)` |
| `ideque-remove-front` | `(std srfi srfi-134)` |
| `ideque?` | `(std srfi srfi-134)` |
| `idrop` | `(std srfi srfi-116)` |
| `if-let` | `(jerboa clojure)`, `(jerboa prelude)`, `(std gambit-compat)`, `(std prelude)`, ... (+1) |
| `if-path` | `(std specter)` |
| `if/t` | `(std typed advanced)` |
| `ifilter` | `(std srfi srfi-116)` |
| `ifold` | `(std srfi srfi-116)` |
| `ifor-each` | `(std srfi srfi-116)` |
| `ilength` | `(std srfi srfi-116)` |
| `ilist` | `(std srfi srfi-116)` |
| `ilist->list` | `(std srfi srfi-116)` |
| `ilist-ref` | `(std srfi srfi-116)` |
| `ilist?` | `(std srfi srfi-116)` |
| `image-clear!` | `(std persist image)` |
| `image-keys` | `(std persist image)` |
| `image-ref` | `(std persist image)` |
| `image-set!` | `(std persist image)` |
| `imap` | `(jerboa clojure)`, `(std clojure)`, `(std immutable)`, `(std srfi srfi-116)` |
| `imap->alist` | `(std immutable)` |
| `imap-delete` | `(std immutable)` |
| `imap-empty` | `(std immutable)` |
| `imap-filter` | `(std immutable)` |
| `imap-fold` | `(std immutable)` |
| `imap-for-each` | `(std immutable)` |
| `imap-has?` | `(jerboa clojure)`, `(std clojure)`, `(std immutable)` |
| `imap-hash` | `(jerboa clojure)`, `(std clojure)`, `(std immutable)` |
| `imap-keys` | `(std immutable)` |
| `imap-map` | `(std immutable)` |
| `imap-merge` | `(std immutable)` |
| `imap-persistent!` | `(std immutable)` |
| `imap-ref` | `(jerboa clojure)`, `(std clojure)`, `(std immutable)` |
| `imap-set` | `(jerboa clojure)`, `(std clojure)`, `(std immutable)` |
| `imap-size` | `(std immutable)` |
| `imap-t-delete!` | `(std immutable)` |
| `imap-t-has?` | `(std immutable)` |
| `imap-t-ref` | `(std immutable)` |
| `imap-t-set!` | `(std immutable)` |
| `imap-t-size` | `(std immutable)` |
| `imap-transient` | `(std immutable)` |
| `imap-transient?` | `(std immutable)` |
| `imap-values` | `(std immutable)` |
| `imap=?` | `(jerboa clojure)`, `(std clojure)`, `(std immutable)` |
| `imap?` | `(jerboa clojure)`, `(std clojure)`, `(std immutable)` |
| `img-init` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-is-bmp` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-is-cur` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-is-gif` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-is-ico` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-is-jpg` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-is-lbm` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-is-pcx` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-is-png` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-is-tif` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-is-webp` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-is-xcf` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-is-xpm` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-is-xv` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-linked-version` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-bmp-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-cur-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-gif-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-ico-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-jpg-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-lbm-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-pcx-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-png-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-pnm-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-texture` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-texture-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-texture-typed-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-tga-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-tif-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-typed-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-webp-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-xcf-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-xpm-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-load-xv-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-quit` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-read-xpm-from-array` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-save-png` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `img-save-png-rw` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `immutable?` | `(std concur)` |
| `impersonate-procedure` | `(std misc chaperone)` |
| `implement-hkt` | `(std typed hkt)` |
| `import-violation-file` | `(std security import-audit)` |
| `import-violation-import-spec` | `(std security import-audit)` |
| `import-violation-line` | `(std security import-audit)` |
| `import-violation?` | `(std security import-audit)` |
| `in-bytes` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `in-chars` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `in-hash-keys` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `in-hash-pairs` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `in-hash-values` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `in-imap` | `(jerboa clojure)`, `(std clojure)`, `(std immutable)` |
| `in-imap-keys` | `(jerboa clojure)`, `(std clojure)`, `(std immutable)` |
| `in-imap-pairs` | `(jerboa clojure)`, `(std clojure)`, `(std immutable)` |
| `in-imap-values` | `(jerboa clojure)`, `(std clojure)`, `(std immutable)` |
| `in-indexed` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `in-lines` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `in-list` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `in-naturals` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `in-pmap` | `(std pmap)` |
| `in-pmap-keys` | `(std pmap)` |
| `in-pmap-pairs` | `(std pmap)` |
| `in-pmap-values` | `(std pmap)` |
| `in-port` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `in-producer` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `in-pset` | `(jerboa clojure)`, `(std clojure)`, `(std pset)` |
| `in-range` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `in-range?` | `(std misc numeric)` |
| `in-string` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `in-vector` | `(jerboa clojure)`, `(jerboa prelude)`, `(std iter)`, `(std prelude)` |
| `inc` | `(jerboa clojure)`, `(std clojure)` |
| `includes?` | `(std clojure string)` |
| `indexing` | `(std transducer)` |
| `infer-effects` | `(std typed effects)` |
| `infer-handler-effects` | `(std typed effect-typing)` |
| `infer-type` | `(std typed infer)` |
| `inflate-bytevector` | `(std compress zlib)` |
| `info-prefix` | `(std cli style)` |
| `infof` | `(std logger)` |
| `ini-read` | `(std text ini)` |
| `ini-ref` | `(std text ini)` |
| `ini-set` | `(std text ini)` |
| `ini-write` | `(std text ini)` |
| `initialize` | `(std clos)` |
| `inject-context` | `(std span)` |
| `inline-calls` | `(std staging2)` |
| `inotify-add-watch` | `(std os inotify-native)`, `(std os inotify)` |
| `inotify-close` | `(std os inotify-native)`, `(std os inotify)` |
| `inotify-event-cookie` | `(std os inotify)` |
| `inotify-event-mask` | `(std os inotify-native)`, `(std os inotify)` |
| `inotify-event-name` | `(std os inotify-native)`, `(std os inotify)` |
| `inotify-event-wd` | `(std os inotify-native)`, `(std os inotify)` |
| `inotify-event?` | `(std os inotify-native)`, `(std os inotify)` |
| `inotify-init` | `(std os inotify-native)`, `(std os inotify)` |
| `inotify-poll` | `(std os inotify)` |
| `inotify-read-events` | `(std os inotify-native)`, `(std os inotify)` |
| `inotify-rm-watch` | `(std os inotify-native)`, `(std os inotify)` |
| `input-port-timeout-set!` | `(jerboa core)`, `(std gambit-compat)` |
| `input-stream` | `(std clojure io)` |
| `inspect-condition` | `(std inspect)` |
| `inspect-object` | `(std inspect)` |
| `inspect-procedure` | `(std inspect)` |
| `inspect-record` | `(std inspect)` |
| `install-error-advisor!` | `(std error-advice)` |
| `install-error-handler!` | `(std errors)` |
| `installed-packages` | `(jerboa registry)` |
| `instance-of` | `(std typed typeclass)` |
| `instance?` | `(std clos)` |
| `instrument` | `(std dev debug)` |
| `int%` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `int16-be` | `(std misc binary-type)` |
| `int16-le` | `(std misc binary-type)` |
| `int32-be` | `(std misc binary-type)` |
| `int32-le` | `(std misc binary-type)` |
| `int8` | `(std misc binary-type)` |
| `integer->bytevector` | `(std misc numeric)` |
| `integer-length` | `(std srfi srfi-151)` |
| `integer-length*` | `(std misc number)` |
| `integrity-error-reason` | `(std os integrity)` |
| `integrity-error?` | `(std os integrity)` |
| `integrity-hash-file` | `(std os integrity)` |
| `integrity-hash-region` | `(std os integrity)` |
| `integrity-hash-self` | `(std os integrity)` |
| `integrity-verify-hash` | `(std os integrity)` |
| `integrity-verify-signature` | `(std os integrity)` |
| `interface-has-method?` | `(std interface)` |
| `interface-method-names` | `(std interface)` |
| `interface-name` | `(std interface)` |
| `interface-register-method!` | `(std interface)` |
| `interface-satisfies?` | `(std interface)` |
| `interleave` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list-more)`, `(std misc list)`, ... (+1) |
| `internal-error-classes` | `(std security errors)` |
| `internal-error?` | `(std security errors)` |
| `interned-symbol?` | `(std misc symbol)` |
| `interpolate` | `(std interpolate)` |
| `interpose` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)`, `(std prelude)` |
| `intersection` | `(jerboa clojure)`, `(std clojure)` |
| `into` | `(jerboa clojure)`, `(std clojure)`, `(std seq)`, `(std transducer)` |
| `inull?` | `(std srfi srfi-116)` |
| `io-copy` | `(std clojure io)` |
| `io-delete-file` | `(std clojure io)`, `(std effect io)` |
| `io-display` | `(std effect io)` |
| `io-file-exists?` | `(std clojure io)`, `(std effect io)` |
| `io-only-filter` | `(std security seccomp)` |
| `io-poller-start!` | `(std net io)` |
| `io-poller-stop!` | `(std net io)` |
| `io-poller?` | `(std net io)` |
| `io-read-file` | `(std effect io)` |
| `io-read-line` | `(std effect io)` |
| `io-write-file` | `(std effect io)` |
| `io/delete-file` | `(std security io-intercept)` |
| `io/net-connect` | `(std security io-intercept)` |
| `io/net-listen` | `(std security io-intercept)` |
| `io/process-exec` | `(std security io-intercept)` |
| `io/read-file` | `(std security io-intercept)` |
| `io/write-file` | `(std security io-intercept)` |
| `iota` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+4) |
| `iouring-accept!` | `(std os iouring)` |
| `iouring-available?` | `(std os iouring)` |
| `iouring-close!` | `(std os iouring)` |
| `iouring-nop!` | `(std os iouring)` |
| `iouring-pending` | `(std os iouring)` |
| `iouring-read!` | `(std os iouring)` |
| `iouring-ring-addr` | `(std os iouring)` |
| `iouring-submit!` | `(std os iouring)` |
| `iouring-wait!` | `(std os iouring)` |
| `iouring-write!` | `(std os iouring)` |
| `iouring?` | `(std os iouring)` |
| `ip-address` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `ipair` | `(std srfi srfi-116)` |
| `ipair?` | `(std srfi srfi-116)` |
| `ipv4?` | `(std net address)` |
| `ipv6?` | `(std net address)` |
| `iremove` | `(std srfi srfi-116)` |
| `ireverse` | `(std srfi srfi-116)` |
| `is-a?` | `(std clos)` |
| `is-literal-null?` | `(std typed solver)` |
| `is-literal-positive?` | `(std typed solver)` |
| `is-literal-zero?` | `(std typed solver)` |
| `itake` | `(std srfi srfi-116)` |
| `italic` | `(std cli style)`, `(std misc terminal)` |
| `iterate` | `(jerboa clojure)`, `(std clojure)` |
| `iterate-n` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)`, `(std prelude)` |
| `iunfold` | `(std srfi srfi-116)` |
| `ivec` | `(jerboa clojure)`, `(std clojure)`, `(std immutable)` |
| `ivec->list` | `(std immutable)` |
| `ivec-append` | `(std immutable)` |
| `ivec-concat` | `(std immutable)` |
| `ivec-empty` | `(std immutable)` |
| `ivec-filter` | `(std immutable)` |
| `ivec-fold` | `(std immutable)` |
| `ivec-for-each` | `(std immutable)` |
| `ivec-length` | `(jerboa clojure)`, `(std clojure)`, `(std immutable)` |
| `ivec-map` | `(std immutable)` |
| `ivec-ref` | `(jerboa clojure)`, `(std clojure)`, `(std immutable)` |
| `ivec-set` | `(jerboa clojure)`, `(std clojure)`, `(std immutable)` |
| `ivec-slice` | `(std immutable)` |
| `ivec?` | `(std immutable)` |

### <a name="idx-j"></a>j

| Symbol | Modules |
| --- | --- |
| `jerboa-condition-subsystem` | `(jerboa prelude safe)`, `(std error conditions)` |
| `jerboa-condition?` | `(jerboa prelude safe)`, `(std error conditions)` |
| `jerboa-native-available?` | `(std native)` |
| `jerboa-native-load!` | `(std native)` |
| `jerboa-read` | `(jerboa reader)` |
| `jerboa-read-all` | `(jerboa reader)` |
| `jerboa-read-file` | `(jerboa reader)` |
| `jerboa-read-string` | `(jerboa reader)` |
| `jerboa-repl` | `(std repl)` |
| `join` | `(std clojure string)`, `(std query)` |
| `joined` | `(std srfi srfi-159)` |
| `joined/dot` | `(std srfi srfi-159)` |
| `joined/last` | `(std srfi srfi-159)` |
| `joined/prefix` | `(std srfi srfi-159)` |
| `joined/range` | `(std srfi srfi-159)` |
| `joined/suffix` | `(std srfi srfi-159)` |
| `json-object->string` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `json-rpc-call` | `(std net json-rpc)` |
| `json-rpc-error-response` | `(std net json-rpc)` |
| `json-rpc-error?` | `(std net json-rpc)` |
| `json-rpc-notification` | `(std net json-rpc)` |
| `json-rpc-parse` | `(std net json-rpc)` |
| `json-rpc-request` | `(std net json-rpc)` |
| `json-rpc-response` | `(std net json-rpc)` |
| `json-schema?` | `(std text json-schema)` |
| `julian->datetime` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `juxt` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc func)`, `(std prelude)` |

### <a name="idx-k"></a>k

| Symbol | Modules |
| --- | --- |
| `keep` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)`, `(std prelude)` |
| `keypath` | `(std specter)` |
| `keys` | `(jerboa clojure)`, `(std clojure)` |
| `keyword->string` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `keyword->symbol` | `(std misc symbol)` |
| `keyword-arg-ref` | `(jerboa core)`, `(jerboa runtime)`, `(std gambit-compat)` |
| `keyword?` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `kill` | `(std os signal)` |
| `kqueue-add-read` | `(std os kqueue)` |
| `kqueue-add-signal` | `(std os kqueue)` |
| `kqueue-add-timer` | `(std os kqueue)` |
| `kqueue-add-write` | `(std os kqueue)` |
| `kqueue-close` | `(std os kqueue)` |
| `kqueue-create` | `(std os kqueue)` |
| `kqueue-event-data` | `(std os kqueue)` |
| `kqueue-event-fd` | `(std os kqueue)` |
| `kqueue-event-filter` | `(std os kqueue)` |
| `kqueue-event?` | `(std os kqueue)` |
| `kqueue-remove` | `(std os kqueue)` |
| `kqueue-wait` | `(std os kqueue)` |

### <a name="idx-l"></a>l

| Symbol | Modules |
| --- | --- |
| `LANDLOCK_ACCESS_FS_EXECUTE` | `(std os landlock-native)` |
| `LANDLOCK_ACCESS_FS_MAKE_BLOCK` | `(std os landlock-native)` |
| `LANDLOCK_ACCESS_FS_MAKE_CHAR` | `(std os landlock-native)` |
| `LANDLOCK_ACCESS_FS_MAKE_DIR` | `(std os landlock-native)` |
| `LANDLOCK_ACCESS_FS_MAKE_FIFO` | `(std os landlock-native)` |
| `LANDLOCK_ACCESS_FS_MAKE_REG` | `(std os landlock-native)` |
| `LANDLOCK_ACCESS_FS_MAKE_SOCK` | `(std os landlock-native)` |
| `LANDLOCK_ACCESS_FS_MAKE_SYM` | `(std os landlock-native)` |
| `LANDLOCK_ACCESS_FS_READ_DIR` | `(std os landlock-native)` |
| `LANDLOCK_ACCESS_FS_READ_FILE` | `(std os landlock-native)` |
| `LANDLOCK_ACCESS_FS_REFER` | `(std os landlock-native)` |
| `LANDLOCK_ACCESS_FS_REMOVE_DIR` | `(std os landlock-native)` |
| `LANDLOCK_ACCESS_FS_REMOVE_FILE` | `(std os landlock-native)` |
| `LANDLOCK_ACCESS_FS_TRUNCATE` | `(std os landlock-native)` |
| `LANDLOCK_ACCESS_FS_WRITE_FILE` | `(std os landlock-native)` |
| `LANDLOCK_ACCESS_NET_BIND_TCP` | `(std os landlock-native)` |
| `LANDLOCK_ACCESS_NET_CONNECT_TCP` | `(std os landlock-native)` |
| `LAST` | `(std specter)` |
| `LOCK_EX` | `(std os flock)` |
| `LOCK_NB` | `(std os flock)` |
| `LOCK_SH` | `(std os flock)` |
| `LOCK_UN` | `(std os flock)` |
| `label->pred-datum` | `(std regex-ct-impl)` |
| `lambda-lift` | `(jerboa wasm closure)` |
| `lambda-params` | `(jerboa wasm closure)` |
| `lambda-staged` | `(std staging2)` |
| `lambda/cap` | `(std security capability-typed)` |
| `lambda/ct` | `(std typed check)` |
| `lambda/keys` | `(thunderchez thunder-utils)` |
| `lambda/optional` | `(thunderchez thunder-utils)` |
| `lambda/r` | `(std typed refine)` |
| `lambda/t` | `(std typed)` |
| `lambda/tc` | `(std typed advanced)` |
| `lambda/te` | `(std typed effects)`, `(std typed)` |
| `landlock-abi-version` | `(std os landlock-native)`, `(std os landlock)` |
| `landlock-add-execute!` | `(std security landlock)` |
| `landlock-add-net-rule` | `(std os landlock-native)` |
| `landlock-add-path-rule` | `(std os landlock-native)` |
| `landlock-add-read-only!` | `(std security landlock)` |
| `landlock-add-read-write!` | `(std security landlock)` |
| `landlock-available?` | `(std os landlock-native)`, `(std os landlock)`, `(std security landlock)` |
| `landlock-create-ruleset` | `(std os landlock-native)` |
| `landlock-enforce!` | `(std os landlock-native)`, `(std os landlock)` |
| `landlock-error-reason` | `(std os landlock-native)`, `(std os landlock)` |
| `landlock-error?` | `(std os landlock-native)`, `(std os landlock)` |
| `landlock-install!` | `(std security landlock)` |
| `landlock-restrict-self!` | `(std os landlock-native)` |
| `landlock-ruleset?` | `(std security landlock)` |
| `lappend` | `(std lazy)` |
| `last` | `(jerboa clojure)`, `(jerboa core)`, `(std clojure)`, `(std gambit-compat)` |
| `last-ec` | `(std srfi srfi-42)` |
| `last-pair` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `latch-await` | `(std concur util)` |
| `latch-count-down!` | `(std concur util)` |
| `lazy` | `(std lazy)` |
| `lazy->list` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-all?` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-any?` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-append` | `(jerboa clojure)`, `(std clojure)`, `(std misc lazy-seq)`, `(std seq)` |
| `lazy-car` | `(std misc lazy-seq)` |
| `lazy-cdr` | `(std misc lazy-seq)` |
| `lazy-chunk` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-concat` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-cons` | `(jerboa clojure)`, `(std clojure)`, `(std misc lazy-seq)`, `(std seq)` |
| `lazy-count` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-cycle` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-drop` | `(jerboa clojure)`, `(std clojure)`, `(std misc lazy-seq)`, `(std seq)` |
| `lazy-drop-while` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-filter` | `(jerboa clojure)`, `(std clojure)`, `(std misc lazy-seq)`, `(std seq)` |
| `lazy-first` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-flatten` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-fold` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-for-each` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-force` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-interleave` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-interpose` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-iterate` | `(jerboa clojure)`, `(std clojure)`, `(std misc lazy-seq)`, `(std seq)` |
| `lazy-map` | `(jerboa clojure)`, `(std clojure)`, `(std misc lazy-seq)`, `(std seq)` |
| `lazy-mapcat` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-nil` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-nil?` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-nth` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-null` | `(std misc lazy-seq)` |
| `lazy-null?` | `(std misc lazy-seq)` |
| `lazy-partition` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-range` | `(jerboa clojure)`, `(std clojure)`, `(std misc lazy-seq)`, `(std seq)` |
| `lazy-realize` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-realized?` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-repeat` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-rest` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-seq` | `(std misc lazy-seq)` |
| `lazy-seq->list` | `(std misc lazy-seq)` |
| `lazy-seq?` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-take` | `(jerboa clojure)`, `(std clojure)`, `(std misc lazy-seq)`, `(std seq)` |
| `lazy-take-while` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `lazy-zip` | `(jerboa clojure)`, `(std clojure)`, `(std misc lazy-seq)`, `(std seq)` |
| `lcar` | `(std lazy)` |
| `lcdr` | `(std lazy)` |
| `lcons` | `(std lazy)` |
| `lcs` | `(std misc diff)` |
| `ldrop` | `(std lazy)` |
| `leak-tracker-count` | `(std debug memleak)` |
| `leak-tracker-reset!` | `(std debug memleak)` |
| `leap-year?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `least-fixnum` | `(std fixnum)` |
| `length<=?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `length<=n?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `length<?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `length<n?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `length=?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `length=n?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `length>=?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `length>=n?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `length>?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `length>n?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `lens?` | `(std lens)` |
| `lerp` | `(std misc numeric)` |
| `let-alist` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std sugar)` |
| `let-hash` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+3) |
| `let-struct` | `(std ffi cairo)`, `(thunderchez cairo)`, `(thunderchez ffi-utils)` |
| `let/cc` | `(std gambit-compat)` |
| `level-internal` | `(std security flow)` |
| `level-public` | `(std security flow)` |
| `level-secret` | `(std security flow)` |
| `level-top-secret` | `(std security flow)` |
| `leveldb-approximate-size` | `(std db leveldb)` |
| `leveldb-close` | `(std db leveldb)` |
| `leveldb-compact-range` | `(std db leveldb)` |
| `leveldb-default-options` | `(std db leveldb)` |
| `leveldb-default-read-options` | `(std db leveldb)` |
| `leveldb-default-write-options` | `(std db leveldb)` |
| `leveldb-delete` | `(std db leveldb)` |
| `leveldb-destroy-db` | `(std db leveldb)` |
| `leveldb-error?` | `(std db leveldb)` |
| `leveldb-fold` | `(std db leveldb)` |
| `leveldb-fold-keys` | `(std db leveldb)` |
| `leveldb-for-each` | `(std db leveldb)` |
| `leveldb-for-each-keys` | `(std db leveldb)` |
| `leveldb-get` | `(std db leveldb)` |
| `leveldb-iterator` | `(std db leveldb)` |
| `leveldb-iterator-close` | `(std db leveldb)` |
| `leveldb-iterator-error` | `(std db leveldb)` |
| `leveldb-iterator-key` | `(std db leveldb)` |
| `leveldb-iterator-next` | `(std db leveldb)` |
| `leveldb-iterator-prev` | `(std db leveldb)` |
| `leveldb-iterator-seek` | `(std db leveldb)` |
| `leveldb-iterator-seek-first` | `(std db leveldb)` |
| `leveldb-iterator-seek-last` | `(std db leveldb)` |
| `leveldb-iterator-valid?` | `(std db leveldb)` |
| `leveldb-iterator-value` | `(std db leveldb)` |
| `leveldb-key?` | `(std db leveldb)` |
| `leveldb-open` | `(std db leveldb)` |
| `leveldb-options` | `(std db leveldb)` |
| `leveldb-property` | `(std db leveldb)` |
| `leveldb-put` | `(std db leveldb)` |
| `leveldb-read-options` | `(std db leveldb)` |
| `leveldb-repair-db` | `(std db leveldb)` |
| `leveldb-snapshot` | `(std db leveldb)` |
| `leveldb-snapshot-release` | `(std db leveldb)` |
| `leveldb-version` | `(std db leveldb)` |
| `leveldb-write` | `(std db leveldb)` |
| `leveldb-write-options` | `(std db leveldb)` |
| `leveldb-writebatch` | `(std db leveldb)` |
| `leveldb-writebatch-append` | `(std db leveldb)` |
| `leveldb-writebatch-clear` | `(std db leveldb)` |
| `leveldb-writebatch-delete` | `(std db leveldb)` |
| `leveldb-writebatch-destroy` | `(std db leveldb)` |
| `leveldb-writebatch-put` | `(std db leveldb)` |
| `leveldb?` | `(std db leveldb)` |
| `levenshtein-distance` | `(std errors)` |
| `lex-port` | `(std parser deflexer)` |
| `lex-string` | `(std parser deflexer)` |
| `lexer-next` | `(std parser deflexer)` |
| `lfilter` | `(std lazy)` |
| `lfold` | `(std lazy)` |
| `lift` | `(std typed monad)` |
| `limit` | `(std db query-compile)`, `(std query)` |
| `limit-exceeded-actual` | `(std net timeout)` |
| `limit-exceeded-max` | `(std net timeout)` |
| `limit-exceeded-what` | `(std net timeout)` |
| `limit-exceeded?` | `(std net timeout)` |
| `line-seq` | `(std clojure io)` |
| `linear-consumed?` | `(std typed linear)` |
| `linear-handler-info-name` | `(std dev cont-mark-opt)` |
| `linear-handler-info-ops` | `(std dev cont-mark-opt)` |
| `linear-handler-info?` | `(std dev cont-mark-opt)` |
| `linear-handler-optimization-count` | `(std dev cont-mark-opt)` |
| `linear-split` | `(std typed linear)` |
| `linear-use` | `(std typed linear)` |
| `linear-value` | `(std typed linear)` |
| `linear?` | `(std typed linear)` |
| `link-for-target` | `(std build cross)` |
| `link-static-archives` | `(jerboa build)` |
| `linked-crash-condition` | `(std fiber)` |
| `linked-crash-source` | `(std fiber)` |
| `lint-file` | `(std lint)` |
| `lint-form` | `(std lint)` |
| `lint-result-col` | `(std lint)` |
| `lint-result-file` | `(std lint)` |
| `lint-result-line` | `(std lint)` |
| `lint-result-message` | `(std lint)` |
| `lint-result-rule` | `(std lint)` |
| `lint-result-severity` | `(std lint)` |
| `lint-result?` | `(std lint)` |
| `lint-rule-names` | `(std lint)` |
| `lint-string` | `(std lint)` |
| `lint-summary` | `(std lint)` |
| `linter?` | `(std lint)` |
| `list*` | `(jerboa clojure)`, `(std clojure)` |
| `list->async-stream` | `(std stream async)` |
| `list->bag` | `(std srfi srfi-113)` |
| `list->char-set` | `(std srfi srfi-14)` |
| `list->deque` | `(std misc deque)` |
| `list->f32vector` | `(std srfi srfi-160)` |
| `list->f64vector` | `(std srfi srfi-160)` |
| `list->generator` | `(std srfi srfi-121)`, `(std srfi srfi-158)` |
| `list->hash-table` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `list->heap` | `(std misc heap)` |
| `list->ideque` | `(std srfi srfi-134)` |
| `list->ilist` | `(std srfi srfi-116)` |
| `list->ivec` | `(std immutable)` |
| `list->lazy` | `(jerboa clojure)`, `(std clojure)`, `(std seq)` |
| `list->lazy-seq` | `(std misc lazy-seq)` |
| `list->llist` | `(std lazy)` |
| `list->persistent-vector` | `(std pvec)` |
| `list->pqueue` | `(jerboa clojure)`, `(std clojure)`, `(std pqueue)` |
| `list->s16vector` | `(std srfi srfi-160)` |
| `list->s32vector` | `(std srfi srfi-160)` |
| `list->s64vector` | `(std srfi srfi-160)` |
| `list->s8vector` | `(std srfi srfi-160)` |
| `list->set` | `(std srfi srfi-113)` |
| `list->stream` | `(std srfi srfi-41)` |
| `list->text` | `(std srfi srfi-135)` |
| `list->trie` | `(std misc trie)` |
| `list->u16vector` | `(std srfi srfi-160)` |
| `list->u32vector` | `(std srfi srfi-160)` |
| `list->u64vector` | `(std srfi srfi-160)` |
| `list->u8vector` | `(jerboa core)`, `(std gambit-compat)`, `(std srfi srfi-160)` |
| `list->weak-list` | `(std misc weak)` |
| `list-accumulator` | `(std srfi srfi-158)` |
| `list-checkpoints` | `(std actor checkpoint)` |
| `list-documented` | `(std doc)` |
| `list-ec` | `(std srfi srfi-42)` |
| `list-index` | `(std misc list-more)`, `(std srfi srfi-1)` |
| `list-like?` | `(std macro-types)` |
| `list-merge` | `(std srfi srfi-132)` |
| `list-merge!` | `(std srfi srfi-132)` |
| `list-of?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std ergo)` |
| `list-optimization-passes` | `(std compiler passes)` |
| `list-queue` | `(std srfi srfi-117)` |
| `list-queue-add-back!` | `(std srfi srfi-117)` |
| `list-queue-add-front!` | `(std srfi srfi-117)` |
| `list-queue-append!` | `(std srfi srfi-117)` |
| `list-queue-back` | `(std srfi srfi-117)` |
| `list-queue-empty?` | `(std srfi srfi-117)` |
| `list-queue-for-each` | `(std srfi srfi-117)` |
| `list-queue-front` | `(std srfi srfi-117)` |
| `list-queue-length` | `(std srfi srfi-117)` |
| `list-queue-list` | `(std srfi srfi-117)` |
| `list-queue-map` | `(std srfi srfi-117)` |
| `list-queue-remove-back!` | `(std srfi srfi-117)` |
| `list-queue-remove-front!` | `(std srfi srfi-117)` |
| `list-queue?` | `(std srfi srfi-117)` |
| `list-ref-lens` | `(std lens)` |
| `list-repl-commands` | `(std repl middleware)` |
| `list-sort` | `(std srfi srfi-132)` |
| `list-sort!` | `(std srfi srfi-132)` |
| `list-sorted?` | `(std srfi srfi-132)` |
| `list-split-at` | `(std misc list-more)` |
| `list-stable-sort` | `(std srfi srfi-132)` |
| `list-zipper` | `(std zipper)` |
| `list=` | `(std srfi srfi-1)` |
| `listener-count` | `(std misc event-emitter)` |
| `listeners` | `(std misc event-emitter)` |
| `literate` | `(std lazy)` |
| `live-object-counts` | `(std inspect)` |
| `llist->list` | `(std lazy)` |
| `lmap` | `(std lazy)` |
| `lnull` | `(std lazy)` |
| `lnull?` | `(std lazy)` |
| `load-bytevector` | `(thunderchez thunder-utils)` |
| `load-c-header` | `(std foreign bind)` |
| `load-config` | `(std config)` |
| `load-image` | `(std persist image)` |
| `load-profile!` | `(std dev pgo)` |
| `load-service-config` | `(std service config)` |
| `load-shared-object` | `(std foreign)` |
| `load-shared-object*` | `(jerboa ffi)` |
| `load-world` | `(std image)` |
| `load-world-sexp` | `(std image)` |
| `local-cluster` | `(std distributed)` |
| `location-range` | `(std lsp)` |
| `location-uri` | `(std lsp)` |
| `lock-entry-deps` | `(jerboa lock)` |
| `lock-entry-hash` | `(jerboa lock)` |
| `lock-entry-name` | `(jerboa lock)` |
| `lock-entry-version` | `(jerboa lock)` |
| `lock-entry?` | `(jerboa lock)` |
| `lock-object` | `(std ftype)` |
| `lock-order-violations` | `(std concur)` |
| `lockfile->sexp` | `(jerboa lock)` |
| `lockfile-add!` | `(jerboa lock)` |
| `lockfile-diff` | `(jerboa lock)` |
| `lockfile-entries` | `(jerboa lock)` |
| `lockfile-has?` | `(jerboa lock)` |
| `lockfile-lookup` | `(jerboa lock)` |
| `lockfile-merge` | `(jerboa lock)` |
| `lockfile-read` | `(jerboa lock)` |
| `lockfile-remove!` | `(jerboa lock)` |
| `lockfile-verify-report` | `(std build verify)` |
| `lockfile-write` | `(jerboa lock)` |
| `lockfile?` | `(jerboa lock)` |
| `log-debug` | `(std log)` |
| `log-error` | `(std log)` |
| `log-fatal` | `(std log)` |
| `log-info` | `(std log)` |
| `log-level?` | `(std log)` |
| `log-warn` | `(std log)` |
| `logger-fields` | `(std log)` |
| `logger-level` | `(std log)` |
| `logger-options?` | `(std logger)` |
| `logger?` | `(std log)` |
| `lookup-derivation` | `(std derive)` |
| `lookup-error-class` | `(std security errors)` |
| `lookup-instance` | `(std misc typeclass)` |
| `lookup-local-actor` | `(std actor core)`, `(std actor)` |
| `lookup-typeclass` | `(std misc typeclass)` |
| `loop` | `(jerboa clojure)`, `(std clojure)` |
| `lower-case` | `(std clojure string)` |
| `lrange` | `(std lazy)` |
| `lru-cache-capacity` | `(std misc lru-cache)` |
| `lru-cache-clear!` | `(std misc lru-cache)` |
| `lru-cache-contains?` | `(std misc lru-cache)` |
| `lru-cache-delete!` | `(std misc lru-cache)` |
| `lru-cache-for-each` | `(std misc lru-cache)` |
| `lru-cache-get` | `(std misc lru-cache)` |
| `lru-cache-keys` | `(std misc lru-cache)` |
| `lru-cache-put!` | `(std misc lru-cache)` |
| `lru-cache-size` | `(std misc lru-cache)` |
| `lru-cache-stats` | `(std misc lru-cache)` |
| `lru-cache-values` | `(std misc lru-cache)` |
| `lru-cache?` | `(std misc lru-cache)` |
| `lseq->generator` | `(std srfi srfi-127)` |
| `lseq->list` | `(std srfi srfi-127)` |
| `lseq-any` | `(std srfi srfi-127)` |
| `lseq-append` | `(std srfi srfi-127)` |
| `lseq-car` | `(std srfi srfi-127)` |
| `lseq-cdr` | `(std srfi srfi-127)` |
| `lseq-drop` | `(std srfi srfi-127)` |
| `lseq-every` | `(std srfi srfi-127)` |
| `lseq-filter` | `(std srfi srfi-127)` |
| `lseq-first` | `(std srfi srfi-127)` |
| `lseq-fold` | `(std srfi srfi-127)` |
| `lseq-for-each` | `(std srfi srfi-127)` |
| `lseq-length` | `(std srfi srfi-127)` |
| `lseq-map` | `(std srfi srfi-127)` |
| `lseq-null?` | `(std srfi srfi-127)` |
| `lseq-pair?` | `(std srfi srfi-127)` |
| `lseq-ref` | `(std srfi srfi-127)` |
| `lseq-rest` | `(std srfi srfi-127)` |
| `lseq-take` | `(std srfi srfi-127)` |
| `lseq?` | `(std srfi srfi-127)` |
| `lset-diff+intersection` | `(std srfi srfi-1)` |
| `lset-diff+intersection!` | `(std srfi srfi-1)` |
| `lset-difference` | `(std srfi srfi-1)` |
| `lset-difference!` | `(std srfi srfi-1)` |
| `lset-intersection` | `(std srfi srfi-1)` |
| `lset-intersection!` | `(std srfi srfi-1)` |
| `lset-union` | `(std srfi srfi-1)` |
| `lset-union!` | `(std srfi srfi-1)` |
| `lset-xor` | `(std srfi srfi-1)` |
| `lset-xor!` | `(std srfi srfi-1)` |
| `lsp-capabilities` | `(std lsp)` |
| `lsp-handle-message` | `(std lsp)` |
| `lsp-notify` | `(std lsp server)` |
| `lsp-respond` | `(std lsp server)` |
| `lsp-send-notification` | `(std lsp)` |
| `lsp-server-running?` | `(std lsp)` |
| `lsp-server-start!` | `(std lsp)` |
| `lsp-server-stop!` | `(std lsp)` |
| `lsp-server?` | `(std lsp)` |
| `lsp-state?` | `(std lsp server)` |
| `ltake` | `(std lazy)` |
| `lvar` | `(jerboa clojure)`, `(std logic)` |
| `lvar?` | `(jerboa clojure)`, `(std logic)` |
| `lww-register-merge!` | `(std actor crdt)` |
| `lww-register-set!` | `(std actor crdt)` |
| `lww-register-timestamp` | `(std actor crdt)` |
| `lww-register-value` | `(std actor crdt)` |
| `lww-register?` | `(std actor crdt)` |
| `lz4-compress` | `(std compress lz4)` |
| `lz4-compress-port` | `(std compress lz4)` |
| `lz4-decompress` | `(std compress lz4)` |
| `lz4-decompress-port` | `(std compress lz4)` |

### <a name="idx-m"></a>m

| Symbol | Modules |
| --- | --- |
| `MADV_DONTNEED` | `(std os mmap)` |
| `MADV_RANDOM` | `(std os mmap)` |
| `MADV_SEQUENTIAL` | `(std os mmap)` |
| `MADV_WILLNEED` | `(std os mmap)` |
| `MAP-ENTRIES` | `(std specter)` |
| `MAP-KEYS` | `(std specter)` |
| `MAP-VALS` | `(std specter)` |
| `MAP_ANONYMOUS` | `(std os mmap)` |
| `MAP_PRIVATE` | `(std os mmap)` |
| `MAP_SHARED` | `(std os mmap)` |
| `MDB_APPEND` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_APPENDDUP` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_BAD_DBI` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_BAD_RSLOT` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_BAD_TXN` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_BAD_VALSIZE` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_CORRUPTED` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_CP_COMPACT` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_CREATE` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_CURRENT` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_CURSOR_FULL` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_DBS_FULL` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_DUPFIXED` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_DUPSORT` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_FIXEDMAP` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_INCOMPATIBLE` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_INTEGERDUP` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_INTEGERKEY` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_INVALID` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_KEYEXIST` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_LAST_ERRCODE` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_MAPASYNC` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_MAP_FULL` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_MAP_RESIZED` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_MULTIPLE` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_NODUPDATA` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_NOLOCK` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_NOMEMINIT` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_NOMETASYNC` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_NOOVERWRITE` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_NORDAHEAD` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_NOSUBDIR` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_NOSYNC` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_NOTFOUND` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_NOTLS` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_PAGE_FULL` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_PAGE_NOTFOUND` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_PANIC` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_PROBLEM` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_RDONLY` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_READERS_FULL` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_RESERVE` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_REVERSEDUP` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_REVERSEKEY` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_SUCCESS` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_TLS_FULL` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_TXN_FULL` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_VERSION_MAJOR` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_VERSION_MINOR` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_VERSION_MISMATCH` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_VERSION_PATCH` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MDB_WRITEMAP` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `MEM-HEAP-START` | `(jerboa wasm values)` |
| `MEM-IO-BASE` | `(jerboa wasm values)` |
| `MEM-IO-SIZE` | `(jerboa wasm values)` |
| `MEM-ROOT-STACK-BASE` | `(jerboa wasm values)` |
| `MEM-ROOT-STACK-SIZE` | `(jerboa wasm values)` |
| `MEM-STATIC-BASE` | `(jerboa wasm values)` |
| `MEM-STATIC-SIZE` | `(jerboa wasm values)` |
| `MS_ASYNC` | `(std os mmap)` |
| `MS_INVALIDATE` | `(std os mmap)` |
| `MS_SYNC` | `(std os mmap)` |
| `Monad` | `(std typed hkt)` |
| `madvise` | `(std os mmap)` |
| `magenta` | `(std cli style)` |
| `mailbox-config-capacity` | `(std actor bounded)` |
| `mailbox-config-strategy` | `(std actor bounded)` |
| `mailbox-config?` | `(std actor bounded)` |
| `mailbox-full-actor-id` | `(std actor bounded)` |
| `mailbox-full-capacity` | `(std error conditions)` |
| `mailbox-full-condition?` | `(std actor bounded)` |
| `mailbox-full?` | `(std actor bounded)`, `(std error conditions)` |
| `mailbox-size` | `(std actor bounded)` |
| `make` | `(std clos)` |
| `make-Err` | `(std typed hkt)` |
| `make-None` | `(std typed hkt)` |
| `make-Ok` | `(std typed hkt)` |
| `make-Some` | `(std typed hkt)` |
| `make-accumulator` | `(std srfi srfi-158)` |
| `make-actor-dead` | `(std error conditions)` |
| `make-actor-error` | `(std error conditions)` |
| `make-actor-timeout` | `(std error conditions)` |
| `make-address` | `(std net address)` |
| `make-advisable` | `(std misc advice)` |
| `make-affine` | `(std typed affine)` |
| `make-affine/cleanup` | `(std typed affine)` |
| `make-allow-io-handler` | `(std security io-intercept)` |
| `make-annotated-datum` | `(jerboa reader)` |
| `make-antidebug-error` | `(std os antidebug)` |
| `make-api-key-store` | `(std security auth)` |
| `make-app` | `(std app)`, `(std web rack)` |
| `make-arena` | `(std arena)` |
| `make-arena-interner` | `(std arena)` |
| `make-artifact-store` | `(std build reproducible)` |
| `make-async-promise` | `(std async)` |
| `make-async-stream` | `(std stream async)` |
| `make-audit-io-handler` | `(std security io-intercept)` |
| `make-audit-logger` | `(std security audit)` |
| `make-auth-middleware` | `(std security auth)` |
| `make-auth-result` | `(std security auth)` |
| `make-authenticated-message` | `(std actor cluster-security)` |
| `make-barrier` | `(std concur util)`, `(std misc barrier)` |
| `make-benchmark` | `(std dev benchmark)` |
| `make-bio-input` | `(std net bio)` |
| `make-bio-output` | `(std net bio)` |
| `make-bounded-deque` | `(std misc deque)` |
| `make-buffer-pool` | `(std net zero-copy)` |
| `make-buffer-slice` | `(std net zero-copy)` |
| `make-buffered-input` | `(std io bio)` |
| `make-buffered-output` | `(std io bio)` |
| `make-build-cache` | `(std build reproducible)` |
| `make-build-matrix` | `(std build cross)` |
| `make-build-record` | `(std build reproducible)` |
| `make-build-system` | `(std build watch)` |
| `make-bytevector-builder` | `(jerboa wasm format)` |
| `make-cage-config` | `(std security cage)` |
| `make-cage-error` | `(std security cage)` |
| `make-cancel-token` | `(std task)` |
| `make-cancellation-token-source` | `(std concur async-await)` |
| `make-capability-violation` | `(std security capability)` |
| `make-cas` | `(std content-address)` |
| `make-cell` | `(std repl notebook)` |
| `make-channel` | `(std csp)`, `(std misc channel)`, `(std misc event)` |
| `make-channel-table` | `(std net ssh channel)` |
| `make-channel/buf` | `(std csp)` |
| `make-channel/dropping` | `(std csp)` |
| `make-channel/sliding` | `(std csp)` |
| `make-char-set` | `(std text char-set)` |
| `make-chash` | `(std concur hash)` |
| `make-check` | `(std health)` |
| `make-checked-mutex` | `(std concur deadlock)` |
| `make-checkpoint-manager` | `(std actor checkpoint)` |
| `make-child-spec` | `(std actor supervisor)`, `(std actor)` |
| `make-cipher-ctx` | `(std crypto cipher)` |
| `make-cipher-state` | `(std net ssh transport)` |
| `make-circuit-breaker` | `(std circuit)`, `(std misc retry)` |
| `make-circuit-config` | `(std circuit)` |
| `make-class` | `(std clos)` |
| `make-cluster` | `(std distributed)` |
| `make-cluster-policy` | `(std actor cluster-security)` |
| `make-code` | `(std quasiquote-types)` |
| `make-color` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `make-comparator` | `(std srfi srfi-128)` |
| `make-compile-context` | `(jerboa wasm codegen)` |
| `make-completion` | `(std misc completion)` |
| `make-component` | `(std build sbom)` |
| `make-concurrent-hash` | `(std concur hash)` |
| `make-condition-variable` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `make-config` | `(std config)`, `(std misc config)` |
| `make-conn-pool` | `(std net connpool)` |
| `make-connection-pool` | `(std db conpool)`, `(std net pool)` |
| `make-connection-refused` | `(std error conditions)` |
| `make-connection-timeout` | `(std error conditions)` |
| `make-console-sink` | `(std log)` |
| `make-constraint` | `(std typed solver)` |
| `make-context-condition` | `(std error context)` |
| `make-contract-monitor` | `(std debug contract-monitor)` |
| `make-coroutine` | `(std control coroutine)` |
| `make-coroutine-generator` | `(std srfi srfi-121)`, `(std srfi srfi-158)` |
| `make-count-window` | `(std stream window)` |
| `make-counter` | `(std metrics)` |
| `make-cp0-pass` | `(std compiler passes)` |
| `make-cross-config` | `(jerboa cross)`, `(std build cross)` |
| `make-cross-target` | `(jerboa build)` |
| `make-custodian` | `(std misc custodian)` |
| `make-dag` | `(std misc dag)` |
| `make-dataframe` | `(std dataframe)` |
| `make-datalog` | `(std datalog)` |
| `make-datasource` | `(std query)` |
| `make-date` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)`, ... (+1) |
| `make-datetime` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `make-db-connection-error` | `(std error conditions)` |
| `make-db-constraint-violation` | `(std error conditions)` |
| `make-db-error` | `(std error conditions)` |
| `make-db-query-error` | `(std error conditions)` |
| `make-db-timeout` | `(std error conditions)` |
| `make-dbi-connection` | `(std db dbi)` |
| `make-deadlock-condition` | `(std concur deadlock)` |
| `make-debounce` | `(std time)` |
| `make-decimal` | `(std misc decimal)` |
| `make-default-comparator` | `(std srfi srfi-128)` |
| `make-delegation-token` | `(std actor cluster-security)` |
| `make-deny-all-io-handler` | `(std security io-intercept)` |
| `make-dep` | `(jerboa pkg)` |
| `make-dep-graph` | `(std build watch)` |
| `make-deque` | `(std misc deque)` |
| `make-dh-key` | `(std crypto dh)` |
| `make-dh-params` | `(std crypto dh)` |
| `make-diagnostic` | `(std error diagnostics)` |
| `make-dist-supervisor` | `(std actor distributed)` |
| `make-distributed-supervisor` | `(std actor cluster)` |
| `make-dns-failure` | `(std error conditions)` |
| `make-dns-resolver` | `(std net resolve)` |
| `make-doc-entry` | `(std doc generator)` |
| `make-document-store` | `(std lsp)` |
| `make-duration` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `make-edn-set` | `(std text edn)` |
| `make-eff-type` | `(std typed effects)` |
| `make-effect-type` | `(std typed)` |
| `make-element` | `(std markup sxml)` |
| `make-email` | `(std net smtp)` |
| `make-engine-pool` | `(std actor engine)` |
| `make-env-capability` | `(std security capability)` |
| `make-ephemeron` | `(std srfi srfi-124)` |
| `make-ephemeron-eq-hashtable` | `(std ephemeron)` |
| `make-epoll-events` | `(std os epoll)` |
| `make-eval-capability` | `(std capability)` |
| `make-eval-engine` | `(std engine)` |
| `make-evector` | `(std misc evector)` |
| `make-event` | `(std debug timetravel)`, `(std event)`, `(std misc event)` |
| `make-event-emitter` | `(std misc event-emitter)` |
| `make-event-store` | `(std event-source)` |
| `make-f32vector` | `(std srfi srfi-160)` |
| `make-f64vector` | `(jerboa core)`, `(std gambit-compat)`, `(std srfi srfi-160)` |
| `make-fastcgi-server` | `(std web fastcgi)` |
| `make-fd` | `(std os fd)` |
| `make-ffi-thread-pool` | `(std foreign bind)` |
| `make-fiber-cancelled` | `(std fiber)` |
| `make-fiber-channel` | `(std fiber)` |
| `make-fiber-csp-channel` | `(std csp fiber-chan)` |
| `make-fiber-csp-channel/dropping` | `(std csp fiber-chan)` |
| `make-fiber-csp-channel/sliding` | `(std csp fiber-chan)` |
| `make-fiber-linked-crash` | `(std fiber)` |
| `make-fiber-parameter` | `(std fiber)` |
| `make-fiber-runtime` | `(std fiber)` |
| `make-fiber-semaphore` | `(std fiber)` |
| `make-fiber-timeout` | `(std fiber)` |
| `make-fiber-ws` | `(std net fiber-ws)` |
| `make-field` | `(std protobuf)` |
| `make-file-pool` | `(std io filepool)` |
| `make-file-sink` | `(std log)` |
| `make-fixed-window` | `(std net rate)` |
| `make-fixnum-const` | `(jerboa wasm values)` |
| `make-flags` | `(thunderchez ffi-utils)` |
| `make-flow-violation` | `(std security flow)` |
| `make-forward-listener` | `(std net ssh forward)` |
| `make-frame` | `(std debug inspector)` |
| `make-fs-capability` | `(std capability)`, `(std security capability)` |
| `make-ftype-pointer` | `(std ftype)` |
| `make-future` | `(std concur util)`, `(std task)` |
| `make-fuzz-stats` | `(std test fuzz)` |
| `make-gauge` | `(std metrics)` |
| `make-gcounter` | `(std actor crdt)` |
| `make-gen` | `(std test quickcheck)` |
| `make-grpc-client` | `(std net grpc)` |
| `make-grpc-server` | `(std net grpc)` |
| `make-gset` | `(std actor crdt)` |
| `make-guardian` | `(std guardian)` |
| `make-guardian-pool` | `(std misc guardian-pool)` |
| `make-hash-set` | `(jerboa clojure)`, `(std clojure)` |
| `make-hash-table` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+4) |
| `make-hash-table-eq` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `make-header-injection` | `(std security sanitize)` |
| `make-health-registry` | `(std health)` |
| `make-heap` | `(std misc heap)` |
| `make-histogram` | `(std metrics)` |
| `make-hpack-context` | `(std net http2)` |
| `make-http-limits` | `(std net timeout)` |
| `make-http2-data-frame` | `(std net http2)` |
| `make-http2-goaway-frame` | `(std net http2)` |
| `make-http2-headers-frame` | `(std net http2)` |
| `make-http2-ping-frame` | `(std net http2)` |
| `make-http2-rst-stream-frame` | `(std net http2)` |
| `make-http2-settings-frame` | `(std net http2)` |
| `make-http2-window-update-frame` | `(std net http2)` |
| `make-imm-const` | `(jerboa wasm values)` |
| `make-inotify-event` | `(std os inotify-native)`, `(std os inotify)` |
| `make-instance` | `(std clos)` |
| `make-integrity-error` | `(std os integrity)` |
| `make-interface` | `(std interface)` |
| `make-io-poller` | `(std net io)` |
| `make-iota-generator` | `(std srfi srfi-158)` |
| `make-iouring` | `(std os iouring)` |
| `make-iterator` | `(std misc collection)` |
| `make-jerboa-condition` | `(std error conditions)` |
| `make-json-rpc-error` | `(std net json-rpc)` |
| `make-json-sink` | `(std log)` |
| `make-keyword` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `make-landlock-error` | `(std os landlock-native)`, `(std os landlock)` |
| `make-landlock-ruleset` | `(std security landlock)` |
| `make-latch` | `(std concur util)` |
| `make-lens` | `(std lens)` |
| `make-lexer` | `(std parser deflexer)` |
| `make-limit-exceeded` | `(std net timeout)` |
| `make-linear` | `(std typed linear)` |
| `make-linear-handler-info` | `(std dev cont-mark-opt)` |
| `make-linter` | `(std lint)` |
| `make-list` | `(jerboa runtime)` |
| `make-list-queue` | `(std srfi srfi-117)` |
| `make-location` | `(std lsp)` |
| `make-lock-entry` | `(jerboa lock)` |
| `make-lockfile` | `(jerboa lock)` |
| `make-logger` | `(std log)` |
| `make-logger-options` | `(std logger)` |
| `make-lru-cache` | `(std misc lru-cache)` |
| `make-lsp-server` | `(std lsp)` |
| `make-lsp-state` | `(std lsp server)` |
| `make-lww-register` | `(std actor crdt)` |
| `make-mailbox-config` | `(std actor bounded)` |
| `make-mailbox-full` | `(std actor bounded)`, `(std error conditions)` |
| `make-managed-ptr` | `(std foreign bind)` |
| `make-manifest` | `(jerboa pkg)`, `(std build reproducible)` |
| `make-mdb-cond` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `make-mdb-val` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `make-method-obj` | `(std clos)` |
| `make-mime-message` | `(std mime struct)` |
| `make-mime-part` | `(std mime struct)` |
| `make-mix` | `(std csp mix)`, `(std csp ops)` |
| `make-movable` | `(std move)` |
| `make-mpsc-queue` | `(std actor mpsc)` |
| `make-mult` | `(std csp ops)` |
| `make-musl-cross-target` | `(jerboa build musl)` |
| `make-mutex` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `make-mutex-gambit` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `make-mv-register` | `(std actor crdt)` |
| `make-mvcc-store` | `(std mvcc)` |
| `make-negotiated-algorithms` | `(std net ssh transport)` |
| `make-net-capability` | `(std capability)`, `(std security capability)` |
| `make-network-error` | `(std error conditions)` |
| `make-network-read-error` | `(std error conditions)` |
| `make-network-write-error` | `(std error conditions)` |
| `make-nfa-builder` | `(std regex-ct-impl)` |
| `make-nfa-state` | `(std text regex-compile)` |
| `make-node-tls-config` | `(std actor cluster-security)` |
| `make-noop-tracer` | `(std span)` |
| `make-notebook` | `(std notebook)`, `(std repl notebook)` |
| `make-open-record` | `(std typed row2)` |
| `make-operation-timeout` | `(std safe-timeout)` |
| `make-orset` | `(std actor crdt)` |
| `make-owned` | `(std borrow)` |
| `make-p9-qid` | `(std net 9p)` |
| `make-p9-rattach` | `(std net 9p)` |
| `make-p9-rauth` | `(std net 9p)` |
| `make-p9-rclunk` | `(std net 9p)` |
| `make-p9-rcreate` | `(std net 9p)` |
| `make-p9-rerror` | `(std net 9p)` |
| `make-p9-ropen` | `(std net 9p)` |
| `make-p9-rread` | `(std net 9p)` |
| `make-p9-rstat` | `(std net 9p)` |
| `make-p9-rversion` | `(std net 9p)` |
| `make-p9-rwalk` | `(std net 9p)` |
| `make-p9-rwrite` | `(std net 9p)` |
| `make-p9-stat` | `(std net 9p)` |
| `make-p9-tattach` | `(std net 9p)` |
| `make-p9-tauth` | `(std net 9p)` |
| `make-p9-tclunk` | `(std net 9p)` |
| `make-p9-tcreate` | `(std net 9p)` |
| `make-p9-topen` | `(std net 9p)` |
| `make-p9-tread` | `(std net 9p)` |
| `make-p9-tstat` | `(std net 9p)` |
| `make-p9-tversion` | `(std net 9p)` |
| `make-p9-twalk` | `(std net 9p)` |
| `make-p9-twrite` | `(std net 9p)` |
| `make-package` | `(jerboa pkg)` |
| `make-parents` | `(std clojure io)` |
| `make-parse-depth-exceeded` | `(std error conditions)` |
| `make-parse-error` | `(std error conditions)` |
| `make-parse-failure` | `(std parser)` |
| `make-parse-invalid-input` | `(std error conditions)` |
| `make-parse-result` | `(std parser)` |
| `make-parse-size-exceeded` | `(std error conditions)` |
| `make-parse-state` | `(std regex-ct-impl)` |
| `make-password-salt` | `(std crypto password)` |
| `make-path-traversal` | `(std security sanitize)` |
| `make-pattern-var` | `(std compiler pattern)` |
| `make-persistent-map` | `(std pmap)` |
| `make-persistent-set` | `(std pset)` |
| `make-phantom` | `(std typed phantom)` |
| `make-pin-set` | `(std net tls)` |
| `make-pipeline` | `(std pipeline)` |
| `make-pmap-cell` | `(std data pmap)` |
| `make-pncounter` | `(std actor crdt)` |
| `make-pointerlike` | `(std misc guardian-pool)` |
| `make-pool` | `(std misc pool)` |
| `make-position` | `(std lsp)` |
| `make-posix-error` | `(std os posix)` |
| `make-pqueue` | `(std misc pqueue)` |
| `make-prism` | `(std lens)` |
| `make-privsep` | `(std security privsep)` |
| `make-privsep-channel` | `(std security privsep)` |
| `make-process-capability` | `(std security capability)` |
| `make-process-group` | `(std actor distributed)` |
| `make-profiler` | `(std debug flamegraph)` |
| `make-projection` | `(std event-source)` |
| `make-promise` | `(std concur async-await)` |
| `make-promise-channel` | `(std csp ops)` |
| `make-prompt-tag` | `(std control delimited)`, `(std misc delimited)` |
| `make-provenance` | `(std build reproducible)` |
| `make-pub` | `(std csp ops)` |
| `make-query` | `(std db query-compile)` |
| `make-queue` | `(std misc queue)` |
| `make-raft-cluster` | `(std raft)` |
| `make-raft-node` | `(std raft)` |
| `make-range` | `(std lsp)` |
| `make-range-generator` | `(std srfi srfi-158)` |
| `make-rate-limiter` | `(std misc rate-limiter)`, `(std net rate)`, `(std security auth)` |
| `make-rbtree` | `(std misc rbtree)` |
| `make-reader-monad` | `(std typed monad)` |
| `make-readonly-ruleset` | `(std security landlock)` |
| `make-recorder` | `(std debug timetravel)` |
| `make-recording` | `(std debug replay)` |
| `make-ref` | `(std stm)` |
| `make-refinement` | `(std typed refine)` |
| `make-refinement-type` | `(std typed advanced)` |
| `make-regex-char-class` | `(std text regex-compile)` |
| `make-regex-literal` | `(std text regex-compile)` |
| `make-regex-optional` | `(std text regex-compile)` |
| `make-regex-or` | `(std text regex-compile)` |
| `make-regex-plus` | `(std text regex-compile)` |
| `make-regex-repeat` | `(std text regex-compile)` |
| `make-regex-sequence` | `(std text regex-compile)` |
| `make-regex-star` | `(std text regex-compile)` |
| `make-region` | `(std region)` |
| `make-registry` | `(std metrics)` |
| `make-relation` | `(std misc relation)` |
| `make-reloader` | `(jerboa hot)` |
| `make-remote-actor-ref` | `(std actor core)`, `(std actor transport)`, `(std actor)` |
| `make-remote-ref` | `(std actor distributed)` |
| `make-repl-config` | `(std repl)` |
| `make-replay-window` | `(std actor cluster-security)` |
| `make-reply-channel` | `(std actor protocol)` |
| `make-request` | `(std net fiber-httpd)` |
| `make-resource-already-closed` | `(std error conditions)` |
| `make-resource-error` | `(std error conditions)` |
| `make-resource-exhausted` | `(std error conditions)` |
| `make-resource-leak` | `(std error conditions)` |
| `make-restricted-environment` | `(std security restrict)` |
| `make-retry-policy` | `(std misc retry)` |
| `make-ringbuf` | `(std misc ringbuf)` |
| `make-rng` | `(std proptest)` |
| `make-root-capability` | `(std capability)` |
| `make-round-robin-scheduler` | `(std control coroutine)` |
| `make-route` | `(std net router)` |
| `make-router` | `(std net fiber-httpd)`, `(std net httpd)`, `(std net router)` |
| `make-row-type` | `(std typed row2)` |
| `make-rule` | `(std rewrite)` |
| `make-rule-config` | `(std lint)` |
| `make-ruleset` | `(std rewrite)` |
| `make-rwlock` | `(std concur util)`, `(std misc rwlock)` |
| `make-s16vector` | `(std srfi srfi-160)` |
| `make-s3-client` | `(std net s3)` |
| `make-s32vector` | `(std srfi srfi-160)` |
| `make-s64vector` | `(std srfi srfi-160)` |
| `make-s8vector` | `(std srfi srfi-160)` |
| `make-safe-error-handler` | `(std security errors)` |
| `make-sandbox` | `(jerboa embed)`, `(std capability sandbox)` |
| `make-sandbox-config` | `(jerboa embed)`, `(jerboa prelude safe)`, `(std security sandbox)` |
| `make-sandbox-error` | `(std security sandbox)` |
| `make-sandbox-policy` | `(std capability sandbox)` |
| `make-sandbox-violation` | `(std capability sandbox)` |
| `make-sasl-context` | `(std net sasl)` |
| `make-sbom` | `(std build sbom)` |
| `make-scheduler` | `(std actor scheduler)`, `(std actor)`, `(std sched)` |
| `make-schema` | `(std schema)`, `(std text json-schema)` |
| `make-seccomp-error` | `(std os seccomp)` |
| `make-seccomp-filter` | `(std security seccomp)` |
| `make-secret` | `(std security secret)` |
| `make-security-headers` | `(std net security-headers)` |
| `make-security-level` | `(std security flow)` |
| `make-security-metrics` | `(std security metrics)` |
| `make-semaphore` | `(std concur util)` |
| `make-serialization-error` | `(std error conditions)` |
| `make-serialize-size-exceeded` | `(std error conditions)` |
| `make-service-config` | `(std service config)` |
| `make-session-store` | `(std security auth)` |
| `make-session-window` | `(std stream window)` |
| `make-sftp-attrs` | `(std net ssh sftp)`, `(std net ssh)` |
| `make-shared` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc shared)` |
| `make-signal` | `(std frp)` |
| `make-signal-channel` | `(std os signal-channel)` |
| `make-signalfd` | `(std os signalfd)` |
| `make-slang-build-config` | `(std secure link)` |
| `make-slang-config` | `(std secure compiler)` |
| `make-sliding-window` | `(std net rate)`, `(std stream window)` |
| `make-smtp-config` | `(std net smtp)` |
| `make-solver-context` | `(std typed solver)` |
| `make-sorted-map` | `(std ds sorted-map)` |
| `make-source-location` | `(jerboa reader)`, `(std errors)` |
| `make-specializable` | `(std specialize)` |
| `make-spinlock` | `(std misc spinlock)` |
| `make-ssh-auth-error` | `(std net ssh conditions)` |
| `make-ssh-channel` | `(std net ssh channel)` |
| `make-ssh-channel-error` | `(std net ssh conditions)` |
| `make-ssh-connection-error` | `(std net ssh conditions)` |
| `make-ssh-error` | `(std net ssh conditions)` |
| `make-ssh-host-key-error` | `(std net ssh conditions)` |
| `make-ssh-kex-error` | `(std net ssh conditions)` |
| `make-ssh-pool` | `(std net ssh client)`, `(std net ssh)` |
| `make-ssh-protocol-error` | `(std net ssh conditions)` |
| `make-ssh-sftp-error` | `(std net ssh conditions)` |
| `make-ssh-timeout-error` | `(std net ssh conditions)` |
| `make-stage` | `(std pipeline)` |
| `make-state-machine` | `(std misc state-machine)` |
| `make-state-monad` | `(std typed monad)` |
| `make-stopwatch` | `(std time)` |
| `make-string-reader` | `(std io strio)` |
| `make-string-writer` | `(std io strio)` |
| `make-struct-info` | `(std derive)` |
| `make-supervision-failure` | `(std error conditions)` |
| `make-supervisor` | `(std proc supervisor)` |
| `make-svstat-info` | `(std service control)` |
| `make-symbol` | `(std misc symbol)` |
| `make-table` | `(std table)` |
| `make-tagged-value` | `(std text edn)` |
| `make-taint-label` | `(std taint)` |
| `make-taint-violation` | `(std security taint)` |
| `make-tal-env` | `(std markup tal)` |
| `make-target-platform` | `(std build cross)` |
| `make-template-env` | `(std text template)` |
| `make-temporal-contract` | `(std contract2)` |
| `make-temporary-directory` | `(std os temp)` |
| `make-temporary-file` | `(std os temp)` |
| `make-temporary-file-name` | `(std os temporaries)` |
| `make-term` | `(std rewrite)` |
| `make-theme` | `(std misc highlight)` |
| `make-thread` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `make-thread-pool` | `(std concur util)` |
| `make-throttle` | `(std time)` |
| `make-time` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)`, ... (+1) |
| `make-time-window` | `(std stream window)` |
| `make-timeout-config` | `(std net timeout)` |
| `make-timeout-error` | `(std error conditions)` |
| `make-timeout-value` | `(std misc timeout)` |
| `make-tls-config` | `(std net tls)` |
| `make-tls-error` | `(std error conditions)` |
| `make-tmpdir-ruleset` | `(std security landlock)` |
| `make-token` | `(std parser deflexer)` |
| `make-token-bucket` | `(std net rate)` |
| `make-tracer` | `(std span)` |
| `make-tracked-closure` | `(std debug closure-inspect)` |
| `make-tracked-mutex` | `(std concur)` |
| `make-translator` | `(jerboa translator)` |
| `make-transport-state` | `(std net ssh transport)` |
| `make-traversal` | `(std lens)` |
| `make-trie` | `(std misc trie)` |
| `make-tumbling-window` | `(std stream window)` |
| `make-tvar` | `(std concur stm)`, `(std stm)` |
| `make-type-env` | `(std typed env)` |
| `make-type-error` | `(std typed infer)` |
| `make-u16vector` | `(std srfi srfi-160)` |
| `make-u32vector` | `(std srfi srfi-160)` |
| `make-u64vector` | `(std srfi srfi-160)` |
| `make-u8vector` | `(std gambit-compat)`, `(std srfi srfi-160)` |
| `make-unsafe-deserialize` | `(std error conditions)` |
| `make-url-scheme-violation` | `(std security sanitize)` |
| `make-uuid` | `(std misc uuid)` |
| `make-vclock` | `(std actor crdt)` |
| `make-walist` | `(std misc walist)` |
| `make-wasi-env` | `(std wasm wasi)` |
| `make-wasi-imports` | `(std wasm wasi)` |
| `make-wasm-array` | `(jerboa wasm runtime)` |
| `make-wasm-export` | `(jerboa wasm codegen)` |
| `make-wasm-func` | `(jerboa wasm codegen)` |
| `make-wasm-i31` | `(jerboa wasm runtime)` |
| `make-wasm-import` | `(jerboa wasm codegen)` |
| `make-wasm-module` | `(jerboa wasm codegen)` |
| `make-wasm-runtime` | `(jerboa wasm runtime)` |
| `make-wasm-store` | `(jerboa wasm runtime)` |
| `make-wasm-struct` | `(jerboa wasm runtime)` |
| `make-wasm-tag` | `(jerboa wasm runtime)` |
| `make-wasm-trap` | `(jerboa wasm runtime)` |
| `make-wasm-type` | `(jerboa wasm codegen)` |
| `make-watcher` | `(std build watch)` |
| `make-weak-eq-hashtable` | `(std ephemeron)` |
| `make-weak-hashtable` | `(std misc weak)` |
| `make-weak-pair` | `(std ephemeron)`, `(std misc weak)` |
| `make-websocket-response` | `(std net fiber-httpd)` |
| `make-wg` | `(std misc wg)` |
| `make-windowed-stream` | `(std stream window)` |
| `make-work-deque` | `(std actor deque)` |
| `make-work-pool` | `(std net workpool)` |
| `make-worker` | `(std distributed)` |
| `make-writer-monad` | `(std typed monad)` |
| `make-ws-frame` | `(std net websocket)` |
| `make-yaml-alias` | `(std text yaml nodes)`, `(std text yaml)` |
| `make-yaml-document` | `(std text yaml nodes)`, `(std text yaml)` |
| `make-yaml-mapping` | `(std text yaml nodes)`, `(std text yaml)` |
| `make-yaml-scalar` | `(std text yaml nodes)`, `(std text yaml)` |
| `make-yaml-sequence` | `(std text yaml nodes)`, `(std text yaml)` |
| `manifest->alist` | `(std build reproducible)` |
| `manifest->string` | `(std build reproducible)` |
| `manifest-add` | `(jerboa pkg)` |
| `manifest-add!` | `(std build reproducible)` |
| `manifest-from-string` | `(std build reproducible)` |
| `manifest-get` | `(std build reproducible)` |
| `manifest-hash` | `(std build reproducible)` |
| `manifest-lookup` | `(jerboa pkg)` |
| `manifest-packages` | `(jerboa pkg)` |
| `manifest-remove` | `(jerboa pkg)` |
| `manifest?` | `(jerboa pkg)`, `(std build reproducible)` |
| `map!` | `(std srfi srfi-1)` |
| `map-const` | `(std compiler partial-eval)` |
| `map-err` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `map-invert` | `(jerboa clojure)`, `(std clojure)` |
| `map-ok` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `map-results` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `map-xf` | `(std seq)` |
| `map/car` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `mapcat` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)`, `(std prelude)` |
| `mapping` | `(std srfi srfi-146)`, `(std transducer)` |
| `mapping->alist` | `(std srfi srfi-146)` |
| `mapping-comparator` | `(std srfi srfi-146)` |
| `mapping-contains?` | `(std srfi srfi-146)` |
| `mapping-default-comparator` | `(std srfi srfi-146)` |
| `mapping-delete` | `(std srfi srfi-146)` |
| `mapping-delete-all` | `(std srfi srfi-146)` |
| `mapping-difference` | `(std srfi srfi-146)` |
| `mapping-empty?` | `(std srfi srfi-146)` |
| `mapping-entries` | `(std srfi srfi-146)` |
| `mapping-filter` | `(std srfi srfi-146)` |
| `mapping-fold` | `(std srfi srfi-146)` |
| `mapping-for-each` | `(std srfi srfi-146)` |
| `mapping-intersection` | `(std srfi srfi-146)` |
| `mapping-keys` | `(std srfi srfi-146)` |
| `mapping-map` | `(std srfi srfi-146)` |
| `mapping-ref` | `(std srfi srfi-146)` |
| `mapping-ref/default` | `(std srfi srfi-146)` |
| `mapping-remove` | `(std srfi srfi-146)` |
| `mapping-set` | `(std srfi srfi-146)` |
| `mapping-size` | `(std srfi srfi-146)` |
| `mapping-union` | `(std srfi srfi-146)` |
| `mapping-update` | `(std srfi srfi-146)` |
| `mapping-values` | `(std srfi srfi-146)` |
| `mapping?` | `(std srfi srfi-146)` |
| `match` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `match-pattern` | `(std match-syntax)` |
| `match-regex` | `(std regex-ct)` |
| `match-variant` | `(std variant)` |
| `match/strict` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude)`, `(std match2)`, ... (+1) |
| `matrix-scale` | `(std compiler partial-eval)` |
| `max-ec` | `(std srfi srfi-42)` |
| `max-key` | `(jerboa clojure)`, `(std clojure)` |
| `maybe` | `(jerboa clojure)`, `(jerboa prelude)`, `(std ergo)` |
| `maybe-bind` | `(std typed monad)` |
| `maybe-return` | `(std typed monad)` |
| `md5` | `(std crypto digest)` |
| `mdb-alloc-dbi` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-alloc-env*` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-alloc-txn*` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-alloc-val` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-cmb-func` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-cmp` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-cond-errno` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-cond-str` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-cond?` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-cursor` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-cursor-close` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-cursor-count` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-cursor-dbi` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-cursor-del` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-cursor-get` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-cursor-op` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-cursor-op-ref` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-cursor-op-t` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-cursor-open` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-cursor-put` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-cursor-renew` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-cursor-txn` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-dbi` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-dbi-close` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-dbi-flags` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-dbi-open` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-dcmp` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-del` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-drop` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-close` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-copy` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-copy2` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-copyfd` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-copyfd2` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-create` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-get-fd` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-get-flags` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-get-maxkeysize` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-get-maxreaders` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-get-path` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-get-userctx` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-info` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-open` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-set-assert` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-set-flags` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-set-mapsize` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-set-maxdbs` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-set-maxreaders` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-set-userctx` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-stat` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-env-sync` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-envinfo-t` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-free-garbage` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-get` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-guard-pointer` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-guardian` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-library-init` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-null-txn` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-null-val` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-put` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-reader-check` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-reader-list` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-rel-func` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-set-compare` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-set-dupsort` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-set-relctx` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-set-relfunc` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-stat` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-stat-t` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-strerror` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-txn` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-txn-abort` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-txn-begin` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-txn-commit` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-txn-env` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-txn-id` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-txn-renew` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-txn-reset` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-val` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-val->bytevector` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-val-data` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-val-data-set!` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-val-size` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-val-size-set!` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `mdb-version` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `membero` | `(jerboa clojure)`, `(std logic)` |
| `memo` | `(std misc memo)` |
| `memo-cache` | `(std misc memo)` |
| `memo-clear!` | `(std misc memo)`, `(std misc memoize)` |
| `memo-proc` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc func)`, `(std prelude)` |
| `memo-size` | `(std misc memo)` |
| `memo-stats` | `(std misc memo)` |
| `memo/lru` | `(std misc memo)` |
| `memo/lru+ttl` | `(std misc memo)` |
| `memo/ttl` | `(std misc memo)` |
| `memoize` | `(jerboa clojure)`, `(std clojure)`, `(std misc memoize)` |
| `memoize/lru` | `(std misc memoize)` |
| `merge` | `(jerboa clojure)`, `(std clojure)`, `(std csp clj)`, `(std srfi srfi-95)` |
| `merge!` | `(std srfi srfi-95)` |
| `merge-profile!` | `(std dev pgo)` |
| `merge-with` | `(jerboa clojure)`, `(std clojure)` |
| `message->bytes` | `(std actor transport)` |
| `message->protobuf` | `(std protobuf macros)` |
| `meta` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc meta)` |
| `meta-wrapped?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc meta)` |
| `method-closed?` | `(std dev devirt)` |
| `method-generic-function` | `(std clos)` |
| `method-implementations` | `(std dev devirt)` |
| `method-more-specific?` | `(std clos)` |
| `method-procedure` | `(std clos)` |
| `method-qualifiers` | `(std clos)` |
| `method-specializers` | `(std clos)` |
| `methods` | `(std multi)` |
| `metric-alert!` | `(std security metrics)` |
| `metric-get` | `(std security metrics)` |
| `metric-increment!` | `(std security metrics)` |
| `metric-observe!` | `(std security metrics)` |
| `metric-set!` | `(std security metrics)` |
| `metrics-reset-counters!` | `(std security metrics)` |
| `metrics-snapshot` | `(std security metrics)` |
| `mime-body` | `(std mime struct)` |
| `mime-boundary` | `(std mime struct)` |
| `mime-content-type` | `(std mime struct)` |
| `mime-headers` | `(std mime struct)` |
| `mime-message?` | `(std mime struct)` |
| `mime-part-body` | `(std mime struct)` |
| `mime-part-headers` | `(std mime struct)` |
| `mime-part?` | `(std mime struct)` |
| `mime-type->extensions` | `(std mime types)` |
| `mime-type-category` | `(std mime types)` |
| `mime-type?` | `(std mime types)` |
| `min-ec` | `(std srfi srfi-42)` |
| `min-key` | `(jerboa clojure)`, `(std clojure)` |
| `minimal-policy` | `(std capability sandbox)` |
| `minimize-dfa` | `(std text regex-compile)` |
| `mix` | `(std csp clj)` |
| `mix-allocate-channels` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-channel-finished` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-close-audio` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-each-sound-font` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-expire-channel` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-fade-in-channel-timed` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-fade-in-music` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-fade-in-music-pos` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-fade-out-channel` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-fade-out-group` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-fade-out-music` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-fading-channel` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-fading-music` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-free-chunk` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-free-music` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-get-chunk` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-get-chunk-decoder` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-get-music-decoder` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-get-music-hook-data` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-get-music-type` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-get-num-chunk-decoders` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-get-num-music-decoders` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-get-sound-fonts` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-get-synchro-value` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-group-available` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-group-channel` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-group-channels` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-group-count` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-group-newer` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-group-oldest` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-halt-channel` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-halt-group` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-halt-music` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-has-chunk-decoder` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-has-music-decoder` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-hook-music` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-hook-music-finished` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-init` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-linked-version` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-load-mus` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-load-mus-rw` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-load-mus-type-rw` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-load-wav-rw` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-open-audio` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-open-audio-device` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-out` | `(std csp mix)`, `(std csp ops)` |
| `mix-pause` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-pause-music` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-paused` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-paused-music` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-play-channel-timed` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-play-music` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-playing` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-playing-music` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-query-spec` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-quick-load-raw` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-quick-load-wav` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-quit` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-register-effect` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-reserve-channels` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-resume` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-resume-music` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-rewind-music` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-set-distance` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-set-music-cmd` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-set-music-position` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-set-panning` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-set-position` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-set-post-mix` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-set-reverse-stereo` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-set-sound-fonts` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-set-synchro-value` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-solo-mode` | `(std csp mix)`, `(std csp ops)` |
| `mix-unregister-all-effects` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-unregister-effect` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-volume` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-volume-chunk` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix-volume-music` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `mix?` | `(std csp mix)`, `(std csp ops)` |
| `mmap` | `(std os mmap)` |
| `mmap->bytevector` | `(std os mmap)` |
| `mmap-copy-in!` | `(std os mmap)` |
| `mmap-region-addr` | `(std os mmap)` |
| `mmap-region-mode` | `(std os mmap)` |
| `mmap-region-size` | `(std os mmap)` |
| `mmap-region?` | `(std os mmap)` |
| `mmap-s16-ref` | `(std os mmap)` |
| `mmap-s32-ref` | `(std os mmap)` |
| `mmap-s64-ref` | `(std os mmap)` |
| `mmap-s8-ref` | `(std os mmap)` |
| `mmap-u16-ref` | `(std os mmap)` |
| `mmap-u16-set!` | `(std os mmap)` |
| `mmap-u32-ref` | `(std os mmap)` |
| `mmap-u32-set!` | `(std os mmap)` |
| `mmap-u64-ref` | `(std os mmap)` |
| `mmap-u64-set!` | `(std os mmap)` |
| `mmap-u8-ref` | `(std os mmap)` |
| `mmap-u8-set!` | `(std os mmap)` |
| `module-changed?` | `(jerboa build)`, `(std build)` |
| `module-dependencies` | `(std build)` |
| `module-dependents` | `(std dev reload)` |
| `module-file` | `(std dev reload)` |
| `module-mtime` | `(std dev reload)` |
| `module-registered?` | `(std dev reload)` |
| `monad-guard` | `(std typed monad)` |
| `monad-join` | `(std typed monad)` |
| `monad-map` | `(std typed monad)` |
| `monad-mapM` | `(std typed monad)` |
| `monad-sequence` | `(std typed monad)` |
| `monad-unless` | `(std typed monad)` |
| `monad-void` | `(std typed monad)` |
| `monad-when` | `(std typed monad)` |
| `monitor-check!` | `(std debug contract-monitor)` |
| `monitor-check-count` | `(std debug contract-monitor)` |
| `monitor-clear!` | `(std debug contract-monitor)` |
| `monitor-node` | `(std actor distributed)` |
| `monitor-report` | `(std debug contract-monitor)` |
| `monitor-stats` | `(std debug contract-monitor)` |
| `monitor-violation-count` | `(std debug contract-monitor)` |
| `monitor-violations` | `(std debug contract-monitor)` |
| `movable?` | `(std move)` |
| `move` | `(std regex-ct-impl)` |
| `move!` | `(std move)` |
| `move-into` | `(std move)` |
| `move-value` | `(std move)` |
| `moved?` | `(std move)` |
| `mpsc-close!` | `(std actor mpsc)` |
| `mpsc-closed?` | `(std actor mpsc)` |
| `mpsc-dequeue!` | `(std actor mpsc)` |
| `mpsc-empty?` | `(std actor mpsc)` |
| `mpsc-enqueue!` | `(std actor mpsc)` |
| `mpsc-length` | `(std actor mpsc)` |
| `mpsc-queue?` | `(std actor mpsc)` |
| `mpsc-try-dequeue!` | `(std actor mpsc)` |
| `mptr->object` | `(std odb)` |
| `mptr-null?` | `(std odb)` |
| `mptr?` | `(std odb)` |
| `msgpack-pack` | `(std text msgpack)` |
| `msgpack-pack-port` | `(std text msgpack)` |
| `msgpack-unpack` | `(std text msgpack)` |
| `msgpack-unpack-port` | `(std text msgpack)` |
| `msync` | `(std os mmap)` |
| `mult` | `(std csp clj)` |
| `mult-policy` | `(std csp ops)` |
| `mult-source` | `(std csp ops)` |
| `mult?` | `(std csp ops)` |
| `multi-path` | `(std specter)` |
| `multilog!` | `(std service multilog)` |
| `multimethod-name` | `(std multi)` |
| `multimethod?` | `(std multi)` |
| `multipart-decode` | `(std mime struct)` |
| `multipart-encode` | `(std mime struct)` |
| `multishot-continuation?` | `(std effect multishot)` |
| `multishot-handler?` | `(std effect multishot)` |
| `munmap` | `(std os mmap)` |
| `musl-available?` | `(jerboa build musl)` |
| `musl-boot-files` | `(jerboa build musl)` |
| `musl-chez-lib-dir` | `(jerboa build musl)` |
| `musl-chez-prefix` | `(jerboa build musl)` |
| `musl-chez-prefix-set!` | `(jerboa build musl)` |
| `musl-cross-available?` | `(jerboa build musl)` |
| `musl-crt-objects` | `(jerboa build musl)` |
| `musl-gcc-path` | `(jerboa build musl)` |
| `musl-libkernel-path` | `(jerboa build musl)` |
| `musl-link-command` | `(jerboa build musl)` |
| `musl-link-flags` | `(jerboa build)` |
| `musl-sysroot` | `(jerboa build musl)` |
| `must` | `(std specter)` |
| `mutate-bytevector` | `(std test fuzz)` |
| `mutate-string` | `(std test fuzz)` |
| `mutex-lock!` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `mutex-name` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `mutex-specific` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `mutex-specific-set!` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `mutex-unlock!` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `mutex?` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `mv-register-merge!` | `(std actor crdt)` |
| `mv-register-set!` | `(std actor crdt)` |
| `mv-register-values` | `(std actor crdt)` |
| `mv-register?` | `(std actor crdt)` |
| `mvcc-as-of` | `(std mvcc)` |
| `mvcc-get` | `(std mvcc)` |
| `mvcc-history` | `(std mvcc)` |
| `mvcc-keys` | `(std mvcc)` |
| `mvcc-transact!` | `(std mvcc)` |
| `mvcc-version` | `(std mvcc)` |

### <a name="idx-n"></a>n

| Symbol | Modules |
| --- | --- |
| `NIL->VAL` | `(std specter)` |
| `NN_BUS` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_DOMAIN` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_DONTWAIT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_EACCES` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_EACCESS` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_EADDRINUSE` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_EADDRNOTAVAIL` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_EAFNOSUPPORT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_EAGAIN` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_EBADF` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_ECONNABORTED` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_ECONNREFUSED` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_ECONNRESET` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_EFAULT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_EFSM` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_EHOSTUNREACH` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_EINPROGRESS` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_EINVAL` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_EISCONN` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_EMFILE` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_EMSGSIZE` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_ENETDOWN` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_ENETRESET` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_ENETUNREACH` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_ENOBUFS` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_ENOPROTOOPT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_ENOTCONN` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_ENOTSOCK` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_EPROTO` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_EPROTONOSUPPORT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_ESOCKTNOSUPPORT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_ETERM` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_ETIMEDOUT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_INPROC` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_IPC` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_IPV4ONLY` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_LINGER` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_MAXTTL` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_MSG` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_NOTSUP` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_NS_DOMAIN` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_NS_ERROR` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_NS_EVENT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_NS_FLAG` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_NS_LIMIT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_NS_NAMESPACE` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_NS_OPTION_LEVEL` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_NS_OPTION_TYPE` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_NS_OPTION_UNIT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_NS_PROTOCOL` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_NS_SOCKET_OPTION` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_NS_STATISTIC` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_NS_TRANSPORT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_NS_TRANSPORT_OPTION` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_NS_VERSION` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_PAIR` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_POLLIN` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_POLLOUT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_PROTOCOL` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_PUB` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_PULL` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_PUSH` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_RCVBUF` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_RCVFD` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_RCVMAXSIZE` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_RCVPRIO` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_RCVTIMEO` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_RECONNECT_IVL` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_RECONNECT_IVL_MAX` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_REP` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_REQ` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_REQ_RESEND_IVL` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_RESPONDENT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_SNDBUF` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_SNDFD` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_SNDPRIO` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_SNDTIMEO` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_SOCKADDR_MAX` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_SOCKET_NAME` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_SOL_SOCKET` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_STAT_ACCEPTED_CONNECTIONS` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_STAT_ACCEPT_ERRORS` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_STAT_BIND_ERRORS` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_STAT_BROKEN_CONNECTIONS` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_STAT_BYTES_RECEIVED` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_STAT_BYTES_SENT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_STAT_CONNECT_ERRORS` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_STAT_CURRENT_CONNECTIONS` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_STAT_CURRENT_EP_ERRORS` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_STAT_CURRENT_SND_PRIORITY` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_STAT_DROPPED_CONNECTIONS` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_STAT_ESTABLISHED_CONNECTIONS` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_STAT_INPROGRESS_CONNECTIONS` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_STAT_MESSAGES_RECEIVED` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_STAT_MESSAGES_SENT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_SUB` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_SUB_SUBSCRIBE` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_SUB_UNSUBSCRIBE` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_SURVEYOR` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_SURVEYOR_DEADLINE` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_TCP` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_TCP_NODELAY` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_TYPE_INT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_TYPE_NONE` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_TYPE_STR` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_UNIT_BOOLEAN` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_UNIT_BYTES` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_UNIT_COUNTER` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_UNIT_MESSAGES` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_UNIT_MILLISECONDS` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_UNIT_NONE` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_UNIT_PRIORITY` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_VERSION_AGE` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_VERSION_CURRENT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_VERSION_REVISION` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_WS` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_WS_MSG_TYPE` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_WS_MSG_TYPE_BINARY` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `NN_WS_MSG_TYPE_TEXT` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `Natural` | `(std typed refine)` |
| `Navigable` | `(jerboa clojure)`, `(std datafy)` |
| `NetIO` | `(std security io-intercept)` |
| `NonEmpty` | `(std typed refine)` |
| `NonNeg` | `(std typed refine)` |
| `NonNull` | `(std typed refine)` |
| `NonZero` | `(std typed refine)` |
| `None?` | `(std typed hkt)` |
| `named-generic` | `(std clos)` |
| `nanomsg-library-init` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `native-crypto-memcmp` | `(std crypto native)` |
| `native-digest` | `(std crypto native)` |
| `native-hmac-sha256` | `(std crypto native)` |
| `native-md5` | `(std crypto native)` |
| `native-platform?` | `(std build cross)` |
| `native-random-bytes` | `(std crypto native)` |
| `native-random-bytes!` | `(std crypto native)` |
| `native-sha1` | `(std crypto native)` |
| `native-sha256` | `(std crypto native)` |
| `native-sha384` | `(std crypto native)` |
| `native-sha512` | `(std crypto native)` |
| `natural?` | `(std misc number)` |
| `nav` | `(jerboa clojure)`, `(std datafy)` |
| `nb-cell!` | `(std notebook)` |
| `nb-cell-names` | `(std notebook)` |
| `nb-dirty?` | `(std notebook)` |
| `nb-eval!` | `(std notebook)` |
| `nb-eval-cell!` | `(std notebook)` |
| `nb-ref` | `(std notebook)` |
| `nb-remove!` | `(std notebook)` |
| `nb-reset!` | `(std notebook)` |
| `negate` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc func)`, `(std prelude)` |
| `negative?` | `(std misc number)` |
| `negotiated-algorithms-cipher-c2s` | `(std net ssh transport)` |
| `negotiated-algorithms-cipher-s2c` | `(std net ssh transport)` |
| `negotiated-algorithms-compress-c2s` | `(std net ssh transport)` |
| `negotiated-algorithms-compress-s2c` | `(std net ssh transport)` |
| `negotiated-algorithms-host-key` | `(std net ssh transport)` |
| `negotiated-algorithms-kex` | `(std net ssh transport)` |
| `negotiated-algorithms-mac-c2s` | `(std net ssh transport)` |
| `negotiated-algorithms-mac-s2c` | `(std net ssh transport)` |
| `negotiated-algorithms?` | `(std net ssh transport)` |
| `nested-empty-like` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc nested)` |
| `nested-get` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc nested)` |
| `net-allowed-host?` | `(std security capability)` |
| `net-cap-allowed-hosts` | `(std capability)` |
| `net-cap-deny-others?` | `(std capability)` |
| `net-capability?` | `(std capability)` |
| `net-connect?` | `(std security capability)` |
| `net-listen?` | `(std security capability)` |
| `network-error-address` | `(std error conditions)` |
| `network-error-port-number` | `(std error conditions)` |
| `network-error?` | `(jerboa prelude safe)`, `(std error conditions)`, `(std safe)` |
| `network-policy` | `(std capability sandbox)` |
| `network-read-error?` | `(std error conditions)` |
| `network-server-filter` | `(std security seccomp)` |
| `network-write-error?` | `(std error conditions)` |
| `never-event` | `(std misc event)` |
| `never-evt` | `(std event)` |
| `new-cafe` | `(std cafe)` |
| `new-struct` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `next` | `(jerboa clojure)`, `(std clojure)` |
| `next-method?` | `(std clos)` |
| `next-prime` | `(std misc prime)` |
| `nfa->dfa` | `(std regex-ct-impl)`, `(std text regex-compile)` |
| `nfa-alphabet` | `(std regex-ct-impl)` |
| `nfa-state-final?` | `(std text regex-compile)` |
| `nfa-state-id` | `(std text regex-compile)` |
| `nfa-state?` | `(std text regex-compile)` |
| `nil?` | `(jerboa clojure)`, `(std clojure)` |
| `ninth` | `(std srfi srfi-1)` |
| `nl` | `(std srfi srfi-159)` |
| `nn-assert` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-bind` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-close` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-connect` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-device` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-errno` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-freemsg` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-get-statistic` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-getsockopt` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-poll` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-recv` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-recvmsg` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-send` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-sendmsg` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-setsockopt` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-setsockopt/int` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-shutdown` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-socket` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-strerror` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `nn-symbol` | `(std ffi nanomsg)`, `(thunderchez nanomsg)` |
| `no-applicable-method` | `(std clos)` |
| `no-next-method` | `(std clos)` |
| `node-alive?` | `(std actor cluster)`, `(std actor distributed)` |
| `node-closure` | `(std markup sxml-path)` |
| `node-has-permission?` | `(std actor cluster-security)` |
| `node-id` | `(std actor cluster)` |
| `node-join` | `(std markup sxml-path)` |
| `node-name` | `(std actor cluster)` |
| `node-tls-config-ca-certificate` | `(std actor cluster-security)` |
| `node-tls-config-certificate` | `(std actor cluster-security)` |
| `node-tls-config-private-key` | `(std actor cluster-security)` |
| `node-tls-config-verify-peer?` | `(std actor cluster-security)` |
| `node-tls-config?` | `(std actor cluster-security)` |
| `node-typeof?` | `(std markup sxml-path)` |
| `node?` | `(std actor cluster)` |
| `normalize` | `(std rewrite)` |
| `normalize-artifact` | `(std build reproducible)` |
| `normalize-path-sep` | `(jerboa cross)` |
| `not-pair?` | `(std srfi srfi-1)` |
| `notebook-add-cell!` | `(std repl notebook)` |
| `notebook-cells` | `(std repl notebook)` |
| `notebook-export-html` | `(std repl notebook)` |
| `notebook-export-markdown` | `(std repl notebook)` |
| `notebook-load` | `(std repl notebook)` |
| `notebook-name` | `(std notebook)` |
| `notebook-recording?` | `(std repl notebook)` |
| `notebook-run` | `(std repl notebook)` |
| `notebook-save` | `(std repl notebook)` |
| `notebook-start!` | `(std repl notebook)` |
| `notebook-stop!` | `(std repl notebook)` |
| `notebook-title` | `(std repl notebook)` |
| `notebook?` | `(std notebook)`, `(std repl notebook)` |
| `nothing` | `(std srfi srfi-159)` |
| `notify-change!` | `(std dev reload)` |
| `nrepl-running?` | `(std nrepl)` |
| `nrepl-server-port` | `(std nrepl)` |
| `nrepl-start!` | `(std nrepl)` |
| `nrepl-stop!` | `(std nrepl)` |
| `nth-prime` | `(std misc prime)` |
| `nthpath` | `(std specter)` |
| `null-list?` | `(std srfi srfi-1)` |
| `nullo` | `(jerboa clojure)`, `(std logic)` |
| `number->human-readable` | `(std misc number)` |
| `number->padded-string` | `(std misc number)`, `(std misc numeric)` |
| `number-comparator` | `(std srfi srfi-128)` |
| `numeric` | `(std srfi srfi-159)` |
| `numeric/comma` | `(std srfi srfi-159)` |
| `numeric/si` | `(std srfi srfi-159)` |
| `numeric?` | `(std macro-types)` |

### <a name="idx-o"></a>o

| Symbol | Modules |
| --- | --- |
| `O_APPEND` | `(std os fcntl)`, `(std os posix)` |
| `O_CLOEXEC` | `(std os fcntl)`, `(std os posix)` |
| `O_CREAT` | `(std os posix)` |
| `O_EXCL` | `(std os posix)` |
| `O_NOCTTY` | `(std os posix)` |
| `O_NONBLOCK` | `(std os fcntl)`, `(std os posix)` |
| `O_RDONLY` | `(std os posix)` |
| `O_RDWR` | `(std os posix)` |
| `O_TRUNC` | `(std os posix)` |
| `O_WRONLY` | `(std os posix)` |
| `Ok-val` | `(std typed hkt)` |
| `Ok?` | `(std typed hkt)` |
| `object->string` | `(jerboa core)`, `(std gambit-compat)` |
| `object-counts` | `(std debug heap)` |
| `object-size` | `(std inspect)` |
| `object-type-name` | `(std inspect)` |
| `odb-class-info` | `(std odb)` |
| `odb-close` | `(std odb)` |
| `odb-count` | `(std odb)` |
| `odb-delete` | `(std odb)` |
| `odb-filter` | `(std odb)` |
| `odb-find` | `(std odb)` |
| `odb-make` | `(std odb)` |
| `odb-migrate` | `(std odb)` |
| `odb-open` | `(std odb)` |
| `odb-proxy?` | `(std odb)` |
| `odb-root` | `(std odb)` |
| `odb-root-set!` | `(std odb)` |
| `odb-slot-ref` | `(std odb)` |
| `odb-slot-set!` | `(std odb)` |
| `odb-sync` | `(std odb)` |
| `odb?` | `(std odb)` |
| `off` | `(std misc event-emitter)` |
| `off-all` | `(std misc event-emitter)` |
| `off-module-change` | `(std dev reload)` |
| `offer!` | `(std csp clj)` |
| `offset` | `(std db query-compile)`, `(std query)` |
| `ok` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc result)`, `(std prelude)`, ... (+1) |
| `ok->list` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `ok-value` | `(std misc result)` |
| `ok?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc result)`, `(std prelude)`, ... (+1) |
| `on` | `(std misc event-emitter)` |
| `on-module-change` | `(std dev reload)` |
| `on-node-join` | `(std actor cluster)` |
| `on-node-leave` | `(std actor cluster)` |
| `once` | `(std misc event-emitter)` |
| `one-for-all` | `(std proc supervisor)` |
| `one-for-one` | `(std proc supervisor)` |
| `one-of-specializer` | `(std clos)` |
| `one-solution` | `(std effect multishot)` |
| `onto-chan` | `(std csp clj)`, `(std csp ops)` |
| `onto-chan!` | `(std csp clj)`, `(std csp ops)` |
| `onto-chan!!` | `(std csp clj)`, `(std csp ops)` |
| `open-btree` | `(std mmap-btree)` |
| `open-input-process` | `(jerboa core)`, `(std gambit-compat)`, `(std misc process)` |
| `open-input-u8vector` | `(std gambit-compat)` |
| `open-output-process` | `(std misc process)` |
| `open-output-u8vector` | `(std gambit-compat)` |
| `open-pipe` | `(std os pipe)` |
| `open-process` | `(jerboa core)`, `(std gambit-compat)`, `(std misc process)` |
| `open-record-alist` | `(std typed row2)` |
| `open-record-fields` | `(std typed row2)` |
| `open-record-get` | `(std typed row2)` |
| `open-record-has?` | `(std typed row2)` |
| `open-record-set` | `(std typed row2)` |
| `open-record?` | `(std typed row2)` |
| `open-resource-count` | `(std concur)` |
| `open-safe-input-file` | `(jerboa prelude safe)` |
| `open-safe-output-file` | `(jerboa prelude safe)` |
| `operation-timeout?` | `(std safe-timeout)` |
| `optimize-level` | `(std compile)` |
| `option` | `(std cli getopt)` |
| `option-bind` | `(std typed hkt)` |
| `option-fmap` | `(std typed hkt)` |
| `option-return` | `(std typed hkt)` |
| `optional-argument` | `(std cli getopt)` |
| `or-else` | `(jerboa clojure)`, `(jerboa prelude)`, `(std concur stm)`, `(std prelude)`, ... (+2) |
| `order-by` | `(std db query-compile)`, `(std query)` |
| `orset-add!` | `(std actor crdt)` |
| `orset-member?` | `(std actor crdt)` |
| `orset-merge!` | `(std actor crdt)` |
| `orset-remove!` | `(std actor crdt)` |
| `orset-value` | `(std actor crdt)` |
| `orset?` | `(std actor crdt)` |
| `output-port-timeout-set!` | `(jerboa core)`, `(std gambit-compat)` |
| `output-stream` | `(std clojure io)` |
| `over` | `(std lens)` |
| `owned-consumed?` | `(std borrow)` |
| `owned-ref` | `(std borrow)` |
| `owned-set!` | `(std borrow)` |
| `owned?` | `(std borrow)` |

### <a name="idx-p"></a>p

| Symbol | Modules |
| --- | --- |
| `PAIR-PAYLOAD-SIZE` | `(jerboa wasm values)` |
| `PCRE2_ANCHORED` | `(std pcre2)` |
| `PCRE2_CASELESS` | `(std pcre2)` |
| `PCRE2_DOTALL` | `(std pcre2)` |
| `PCRE2_EXTENDED` | `(std pcre2)` |
| `PCRE2_LITERAL` | `(std pcre2)` |
| `PCRE2_MULTILINE` | `(std pcre2)` |
| `PCRE2_UCP` | `(std pcre2)` |
| `PCRE2_UNGREEDY` | `(std pcre2)` |
| `PCRE2_UTF` | `(std pcre2)` |
| `PGRES_COMMAND_OK` | `(std db postgresql)` |
| `PGRES_EMPTY_QUERY` | `(std db postgresql)` |
| `PGRES_FATAL_ERROR` | `(std db postgresql)` |
| `PGRES_TUPLES_OK` | `(std db postgresql)` |
| `PROT_EXEC` | `(std os mmap)` |
| `PROT_READ` | `(std os mmap)` |
| `PROT_WRITE` | `(std os mmap)` |
| `Positive` | `(std typed refine)` |
| `ProcessIO` | `(std security io-intercept)` |
| `Pure` | `(std typed effects)` |
| `p9-decode` | `(std net 9p)` |
| `p9-encode` | `(std net 9p)` |
| `p9-message-tag` | `(std net 9p)` |
| `p9-message-type` | `(std net 9p)` |
| `p9-qid-path` | `(std net 9p)` |
| `p9-qid-type` | `(std net 9p)` |
| `p9-qid-version` | `(std net 9p)` |
| `p9-qid?` | `(std net 9p)` |
| `p9-rattach-rec-qid` | `(std net 9p)` |
| `p9-rauth-rec-aqid` | `(std net 9p)` |
| `p9-rcreate-rec-iounit` | `(std net 9p)` |
| `p9-rcreate-rec-qid` | `(std net 9p)` |
| `p9-rerror-rec-ename` | `(std net 9p)` |
| `p9-ropen-rec-iounit` | `(std net 9p)` |
| `p9-ropen-rec-qid` | `(std net 9p)` |
| `p9-rread-rec-data` | `(std net 9p)` |
| `p9-rstat-rec-stat` | `(std net 9p)` |
| `p9-rversion-rec-msize` | `(std net 9p)` |
| `p9-rversion-rec-version` | `(std net 9p)` |
| `p9-rwalk-rec-qids` | `(std net 9p)` |
| `p9-rwrite-rec-count` | `(std net 9p)` |
| `p9-stat-atime` | `(std net 9p)` |
| `p9-stat-dev` | `(std net 9p)` |
| `p9-stat-gid` | `(std net 9p)` |
| `p9-stat-length` | `(std net 9p)` |
| `p9-stat-mode` | `(std net 9p)` |
| `p9-stat-mtime` | `(std net 9p)` |
| `p9-stat-muid` | `(std net 9p)` |
| `p9-stat-name` | `(std net 9p)` |
| `p9-stat-qid` | `(std net 9p)` |
| `p9-stat-type` | `(std net 9p)` |
| `p9-stat-uid` | `(std net 9p)` |
| `p9-stat?` | `(std net 9p)` |
| `p9-tattach-rec-afid` | `(std net 9p)` |
| `p9-tattach-rec-aname` | `(std net 9p)` |
| `p9-tattach-rec-fid` | `(std net 9p)` |
| `p9-tattach-rec-uname` | `(std net 9p)` |
| `p9-tauth-rec-afid` | `(std net 9p)` |
| `p9-tauth-rec-aname` | `(std net 9p)` |
| `p9-tauth-rec-uname` | `(std net 9p)` |
| `p9-tclunk-rec-fid` | `(std net 9p)` |
| `p9-tcreate-rec-fid` | `(std net 9p)` |
| `p9-tcreate-rec-mode` | `(std net 9p)` |
| `p9-tcreate-rec-name` | `(std net 9p)` |
| `p9-tcreate-rec-perm` | `(std net 9p)` |
| `p9-topen-rec-fid` | `(std net 9p)` |
| `p9-topen-rec-mode` | `(std net 9p)` |
| `p9-tread-rec-count` | `(std net 9p)` |
| `p9-tread-rec-fid` | `(std net 9p)` |
| `p9-tread-rec-offset` | `(std net 9p)` |
| `p9-tstat-rec-fid` | `(std net 9p)` |
| `p9-tversion-rec-msize` | `(std net 9p)` |
| `p9-tversion-rec-version` | `(std net 9p)` |
| `p9-twalk-rec-fid` | `(std net 9p)` |
| `p9-twalk-rec-newfid` | `(std net 9p)` |
| `p9-twalk-rec-wnames` | `(std net 9p)` |
| `p9-twrite-rec-data` | `(std net 9p)` |
| `p9-twrite-rec-fid` | `(std net 9p)` |
| `p9-twrite-rec-offset` | `(std net 9p)` |
| `p9-type-rattach` | `(std net 9p)` |
| `p9-type-rauth` | `(std net 9p)` |
| `p9-type-rclunk` | `(std net 9p)` |
| `p9-type-rcreate` | `(std net 9p)` |
| `p9-type-rerror` | `(std net 9p)` |
| `p9-type-ropen` | `(std net 9p)` |
| `p9-type-rread` | `(std net 9p)` |
| `p9-type-rstat` | `(std net 9p)` |
| `p9-type-rversion` | `(std net 9p)` |
| `p9-type-rwalk` | `(std net 9p)` |
| `p9-type-rwrite` | `(std net 9p)` |
| `p9-type-tattach` | `(std net 9p)` |
| `p9-type-tauth` | `(std net 9p)` |
| `p9-type-tclunk` | `(std net 9p)` |
| `p9-type-tcreate` | `(std net 9p)` |
| `p9-type-topen` | `(std net 9p)` |
| `p9-type-tread` | `(std net 9p)` |
| `p9-type-tstat` | `(std net 9p)` |
| `p9-type-tversion` | `(std net 9p)` |
| `p9-type-twalk` | `(std net 9p)` |
| `p9-type-twrite` | `(std net 9p)` |
| `package-author` | `(jerboa pkg)` |
| `package-deps` | `(jerboa pkg)` |
| `package-description` | `(jerboa pkg)` |
| `package-install!` | `(jerboa registry)` |
| `package-installed?` | `(jerboa registry)` |
| `package-name` | `(jerboa pkg)` |
| `package-uninstall!` | `(jerboa registry)` |
| `package-update!` | `(jerboa registry)` |
| `package-version` | `(jerboa pkg)` |
| `package?` | `(jerboa pkg)` |
| `pad-left` | `(std misc fmt)` |
| `pad-right` | `(std misc fmt)` |
| `padded` | `(std srfi srfi-159)` |
| `padded/both` | `(std srfi srfi-159)` |
| `padded/right` | `(std srfi srfi-159)` |
| `pair-fold` | `(std srfi srfi-1)` |
| `pair-fold-right` | `(std srfi srfi-1)` |
| `pair-reduce` | `(std srfi srfi-1)` |
| `pairo` | `(jerboa clojure)`, `(std logic)` |
| `par-filter` | `(std seq)` |
| `par-for-each` | `(std seq)` |
| `par-map` | `(std seq)` |
| `par-reduce` | `(std seq)` |
| `parallel` | `(jerboa prelude safe)`, `(std concur structured)` |
| `parse-address` | `(std net address)` |
| `parse-alt` | `(std parser)` |
| `parse-alternation` | `(std regex-ct-impl)` |
| `parse-any-char` | `(std parser)` |
| `parse-atom` | `(std regex-ct-impl)` |
| `parse-between` | `(std parser)` |
| `parse-c-signature` | `(std foreign bind)` |
| `parse-char` | `(std parser)` |
| `parse-char-class` | `(std regex-ct-impl)` |
| `parse-date` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `parse-datetime` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `parse-depth-exceeded-actual` | `(std error conditions)` |
| `parse-depth-exceeded-limit` | `(std error conditions)` |
| `parse-depth-exceeded?` | `(std error conditions)` |
| `parse-digits` | `(std regex-ct-impl)` |
| `parse-docstring` | `(std doc generator)` |
| `parse-eof` | `(std parser)` |
| `parse-error-format` | `(std error conditions)` |
| `parse-error-message` | `(std parser defparser)` |
| `parse-error-token` | `(std parser defparser)` |
| `parse-error?` | `(jerboa prelude safe)`, `(std error conditions)`, `(std parser defparser)`, `(std safe)` |
| `parse-escape` | `(std regex-ct-impl)` |
| `parse-failure-message` | `(std parser)` |
| `parse-failure-position` | `(std parser)` |
| `parse-failure?` | `(std parser)` |
| `parse-html-entities` | `(std text html)` |
| `parse-imports` | `(std build watch)` |
| `parse-invalid-input-position` | `(std error conditions)` |
| `parse-invalid-input?` | `(std error conditions)` |
| `parse-json-rpc-response` | `(std net json-rpc)` |
| `parse-literal` | `(std parser)` |
| `parse-lsp-message` | `(std lsp)` |
| `parse-many` | `(std parser)` |
| `parse-many1` | `(std parser)` |
| `parse-map` | `(std parser)` |
| `parse-optional` | `(std parser)` |
| `parse-quantified` | `(std regex-ct-impl)` |
| `parse-regex` | `(std regex-ct-impl)` |
| `parse-regex-string` | `(std text regex-compile)` |
| `parse-repetition` | `(std regex-ct-impl)` |
| `parse-result-rest` | `(std parser)` |
| `parse-result-value` | `(std parser)` |
| `parse-result?` | `(std parser)` |
| `parse-satisfy` | `(std parser)` |
| `parse-sep-by` | `(std parser)` |
| `parse-seq` | `(std parser)` |
| `parse-sequence` | `(std regex-ct-impl)` |
| `parse-size-exceeded-actual` | `(std error conditions)` |
| `parse-size-exceeded-limit` | `(std error conditions)` |
| `parse-size-exceeded?` | `(std error conditions)` |
| `parse-slang-module` | `(std secure compiler)` |
| `parse-string` | `(std parser)` |
| `parse-string*` | `(std parser)` |
| `parse-success?` | `(std parser)` |
| `parse-time` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `parse-tokens` | `(std parser defparser)` |
| `parse-url` | `(std net request)` |
| `partial` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc func)`, `(std prelude)` |
| `partial-eval` | `(std staging2)` |
| `partial-evaluate` | `(std compiler partial-eval)` |
| `partition` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)`, `(std prelude)` |
| `partition-all` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)`, `(std prelude)` |
| `partition-by` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)`, `(std prelude)` |
| `partitioning-by` | `(std transducer)` |
| `pass-debug-enabled?` | `(std compiler passes)` |
| `pass-priority` | `(std compiler passes)` |
| `pass:constant-fold` | `(std compiler passes)` |
| `pass:dead-code-eliminate` | `(std compiler passes)` |
| `pass:inline-small-functions` | `(std compiler passes)` |
| `pass:loop-unroll` | `(std compiler passes)` |
| `password-hash` | `(std crypto password)` |
| `password-hash-argon2id` | `(std crypto password)` |
| `password-verify` | `(std crypto password)` |
| `password-verify-argon2id` | `(std crypto password)` |
| `path-absolute?` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+3) |
| `path-common-prefix` | `(std os path-util)` |
| `path-default-extension` | `(std misc path)` |
| `path-directory` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `path-expand` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `path-extension` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+3) |
| `path-find` | `(std os path-util)` |
| `path-glob` | `(std os path-util)` |
| `path-join` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `path-normalize` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+5) |
| `path-relative` | `(std os path-util)` |
| `path-relative?` | `(std misc path)` |
| `path-split` | `(std misc path)` |
| `path-strip-directory` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `path-strip-extension` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `path-strip-trailing-directory-separator` | `(jerboa core)`, `(std gambit-compat)`, `(std os path)` |
| `path-traversal?` | `(std security sanitize)` |
| `path-walk` | `(std os path-util)` |
| `pattern-and` | `(std compiler pattern)` |
| `pattern-compile` | `(std compiler pattern)` |
| `pattern-ellipsis` | `(std compiler pattern)` |
| `pattern-guard*` | `(std compiler pattern)` |
| `pattern-match` | `(std rewrite)` |
| `pattern-match*` | `(std compiler pattern)` |
| `pattern-match-lambda` | `(std compiler pattern)` |
| `pattern-not` | `(std compiler pattern)` |
| `pattern-optional` | `(std compiler pattern)` |
| `pattern-or` | `(std compiler pattern)` |
| `pattern-repeat` | `(std compiler pattern)` |
| `pattern-type-guard` | `(std compiler pattern)` |
| `pattern-unless` | `(std compiler pattern)` |
| `pattern-var-constraint` | `(std compiler pattern)` |
| `pattern-var-name` | `(std compiler pattern)` |
| `pattern-vars` | `(std rewrite)` |
| `pattern-when` | `(std compiler pattern)` |
| `pb-bool` | `(std protobuf)` |
| `pb-bytes` | `(std protobuf)` |
| `pb-double` | `(std protobuf)` |
| `pb-embedded` | `(std protobuf)` |
| `pb-fixed32` | `(std protobuf)` |
| `pb-fixed64` | `(std protobuf)` |
| `pb-float` | `(std protobuf)` |
| `pb-int32` | `(std protobuf)` |
| `pb-int64` | `(std protobuf)` |
| `pb-repeated` | `(std protobuf)` |
| `pb-sint32` | `(std protobuf)` |
| `pb-sint64` | `(std protobuf)` |
| `pb-string` | `(std protobuf)` |
| `pb-uint32` | `(std protobuf)` |
| `pb-uint64` | `(std protobuf)` |
| `pb-varint` | `(std protobuf)` |
| `pcap-available?` | `(std pcap)` |
| `pcap-close` | `(std pcap)` |
| `pcap-interfaces` | `(std pcap)` |
| `pcap-next` | `(std pcap)` |
| `pcap-open` | `(std pcap)` |
| `pcre-match->alist` | `(std pcre2)` |
| `pcre-match->list` | `(std pcre2)` |
| `pcre-match-group` | `(std pcre2)` |
| `pcre-match-named` | `(std pcre2)` |
| `pcre-match-positions` | `(std pcre2)` |
| `pcre-match?` | `(std pcre2)` |
| `pcre-regex?` | `(std pcre2)` |
| `pcre2-compile` | `(std pcre2)` |
| `pcre2-extract` | `(std pcre2)` |
| `pcre2-find-all` | `(std pcre2)` |
| `pcre2-fold` | `(std pcre2)` |
| `pcre2-match` | `(std pcre2)` |
| `pcre2-matches?` | `(std pcre2)` |
| `pcre2-partition` | `(std pcre2)` |
| `pcre2-pregexp-match` | `(std pcre2)` |
| `pcre2-pregexp-match-positions` | `(std pcre2)` |
| `pcre2-pregexp-quote` | `(std pcre2)` |
| `pcre2-pregexp-replace` | `(std pcre2)` |
| `pcre2-pregexp-replace*` | `(std pcre2)` |
| `pcre2-quote` | `(std pcre2)` |
| `pcre2-regex` | `(std pcre2)` |
| `pcre2-release!` | `(std pcre2)` |
| `pcre2-replace` | `(std pcre2)` |
| `pcre2-replace-all` | `(std pcre2)` |
| `pcre2-search` | `(std pcre2)` |
| `pcre2-split` | `(std pcre2)` |
| `pdel` | `(std misc plist)` |
| `peek` | `(jerboa clojure)`, `(std clojure)` |
| `peg-error-input` | `(std peg)` |
| `peg-error-message` | `(std peg)` |
| `peg-error-position` | `(std peg)` |
| `peg-error?` | `(std peg)` |
| `peg-run` | `(std peg)` |
| `perform` | `(std effect)` |
| `persistent!` | `(jerboa clojure)`, `(std clojure)`, `(std pvec)` |
| `persistent-class-record-size` | `(std odb)` |
| `persistent-class-region` | `(std odb)` |
| `persistent-class-slot-layout` | `(std odb)` |
| `persistent-class-tag` | `(std odb)` |
| `persistent-map` | `(std pmap)` |
| `persistent-map!` | `(std pmap)` |
| `persistent-map->list` | `(std pmap)` |
| `persistent-map-delete` | `(std pmap)` |
| `persistent-map-diff` | `(std pmap)` |
| `persistent-map-filter` | `(std pmap)` |
| `persistent-map-fold` | `(std pmap)` |
| `persistent-map-for-each` | `(std pmap)` |
| `persistent-map-has?` | `(std pmap)` |
| `persistent-map-hash` | `(std pmap)` |
| `persistent-map-keys` | `(std pmap)` |
| `persistent-map-map` | `(std pmap)` |
| `persistent-map-merge` | `(std pmap)` |
| `persistent-map-ref` | `(std pmap)` |
| `persistent-map-set` | `(std pmap)` |
| `persistent-map-size` | `(std pmap)` |
| `persistent-map-values` | `(std pmap)` |
| `persistent-map=?` | `(std pmap)` |
| `persistent-map?` | `(jerboa clojure)`, `(std clojure)`, `(std immutable)`, `(std pmap)` |
| `persistent-queue` | `(jerboa clojure)`, `(std clojure)`, `(std pqueue)` |
| `persistent-set` | `(jerboa clojure)`, `(std clojure)`, `(std pset)` |
| `persistent-set!` | `(std pset)` |
| `persistent-set->list` | `(jerboa clojure)`, `(std clojure)`, `(std pset)` |
| `persistent-set-add` | `(std pset)` |
| `persistent-set-contains?` | `(jerboa clojure)`, `(std clojure)`, `(std pset)` |
| `persistent-set-difference` | `(std pset)` |
| `persistent-set-filter` | `(std pset)` |
| `persistent-set-fold` | `(std pset)` |
| `persistent-set-for-each` | `(std pset)` |
| `persistent-set-hash` | `(jerboa clojure)`, `(std clojure)`, `(std pset)` |
| `persistent-set-intersection` | `(std pset)` |
| `persistent-set-map` | `(std pset)` |
| `persistent-set-remove` | `(std pset)` |
| `persistent-set-size` | `(std pset)` |
| `persistent-set-subset?` | `(std pset)` |
| `persistent-set-union` | `(std pset)` |
| `persistent-set=?` | `(std pset)` |
| `persistent-set?` | `(jerboa clojure)`, `(std clojure)`, `(std pset)` |
| `persistent-vector` | `(std pvec)` |
| `persistent-vector->list` | `(std pvec)` |
| `persistent-vector-append` | `(std pvec)` |
| `persistent-vector-concat` | `(std pvec)` |
| `persistent-vector-filter` | `(std pvec)` |
| `persistent-vector-fold` | `(std pvec)` |
| `persistent-vector-for-each` | `(std pvec)` |
| `persistent-vector-length` | `(std pvec)` |
| `persistent-vector-map` | `(std pvec)` |
| `persistent-vector-prepend` | `(std pvec)` |
| `persistent-vector-ref` | `(std pvec)` |
| `persistent-vector-set` | `(std pvec)` |
| `persistent-vector-slice` | `(std pvec)` |
| `persistent-vector?` | `(std immutable)`, `(std pvec)` |
| `pg-clear` | `(std db postgresql)` |
| `pg-cmd-tuples` | `(std db postgresql)` |
| `pg-column-name` | `(std db postgresql-native)` |
| `pg-columns` | `(std db postgresql)` |
| `pg-connect` | `(std db postgresql-native)`, `(std db postgresql)` |
| `pg-disconnect` | `(std db postgresql-native)` |
| `pg-error-message` | `(std db postgresql)` |
| `pg-escape-identifier` | `(std db postgresql)` |
| `pg-escape-literal` | `(std db postgresql)` |
| `pg-eval` | `(std db postgresql)` |
| `pg-exec` | `(std db postgresql-native)`, `(std db postgresql)` |
| `pg-exec*` | `(std db postgresql)` |
| `pg-finish` | `(std db postgresql)` |
| `pg-fname` | `(std db postgresql)` |
| `pg-free-result` | `(std db postgresql-native)` |
| `pg-ftype` | `(std db postgresql)` |
| `pg-get-value` | `(std db postgresql-native)` |
| `pg-getisnull` | `(std db postgresql)` |
| `pg-getlength` | `(std db postgresql)` |
| `pg-getvalue` | `(std db postgresql)` |
| `pg-is-null?` | `(std db postgresql-native)` |
| `pg-ncols` | `(std db postgresql-native)` |
| `pg-nfields` | `(std db postgresql)` |
| `pg-nrows` | `(std db postgresql-native)` |
| `pg-ntuples` | `(std db postgresql)` |
| `pg-query` | `(std db postgresql-native)`, `(std db postgresql)` |
| `pg-result-error` | `(std db postgresql)` |
| `pg-result-status` | `(std db postgresql)` |
| `pg-server-version` | `(std db postgresql)` |
| `pg-socket` | `(std db postgresql)` |
| `pg-status` | `(std db postgresql)` |
| `pget` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+3) |
| `pgetq` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `pgetv` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `pgo-specialize` | `(std dev pgo)` |
| `phantom-check` | `(std typed phantom)` |
| `phantom-state` | `(std typed phantom)` |
| `phantom-transition` | `(std typed phantom)` |
| `phantom-type-name` | `(std typed phantom)` |
| `phantom-value` | `(std typed phantom)` |
| `phantom?` | `(std typed phantom)` |
| `pin-set-add!` | `(std net tls)` |
| `pin-set-check` | `(std net tls)` |
| `pin-set?` | `(std net tls)` |
| `ping-node` | `(std actor distributed)` |
| `pipe` | `(std csp clj)`, `(std pipeline)` |
| `pipe->ports` | `(std os pipe)` |
| `pipe-read` | `(std os fd)` |
| `pipe-write` | `(std os fd)` |
| `pipeline` | `(std csp clj)` |
| `pipeline-add-stage!` | `(std pipeline)` |
| `pipeline-async` | `(std csp clj)` |
| `pipeline-blocking` | `(std csp clj)` |
| `pipeline-catch` | `(std pipeline)` |
| `pipeline-compose` | `(std pipeline)` |
| `pipeline-filter` | `(std pipeline)` |
| `pipeline-map` | `(std pipeline)` |
| `pipeline-reduce` | `(std pipeline)` |
| `pipeline-result` | `(std pipeline)` |
| `pipeline-run` | `(std pipeline)` |
| `pipeline-run-parallel` | `(std pipeline)` |
| `pipeline-stats` | `(std pipeline)` |
| `pipeline-tap` | `(std pipeline)` |
| `pipeline-timeout` | `(std pipeline)` |
| `pipeline?` | `(std pipeline)` |
| `platform->string` | `(std build cross)` |
| `platform-abi` | `(std build cross)` |
| `platform-arch` | `(std build cross)` |
| `platform-bsd?` | `(std os platform)` |
| `platform-cpu-count` | `(std os platform)` |
| `platform-executable-path` | `(std os platform)` |
| `platform-linux?` | `(std os platform)` |
| `platform-load-libc` | `(std os platform)` |
| `platform-load-program` | `(std os platform)` |
| `platform-macos?` | `(std os platform)` |
| `platform-name` | `(std build cross)`, `(std os platform)` |
| `platform-os` | `(std build cross)` |
| `platform-page-size` | `(std os platform)` |
| `platform-string` | `(jerboa cross)` |
| `platform-tmpfile-path` | `(std os platform)` |
| `platform/arm64-linux` | `(std build cross)` |
| `platform/arm64-macos` | `(std build cross)` |
| `platform/riscv64-linux` | `(std build cross)` |
| `platform/x86_64-linux` | `(std build cross)` |
| `platform/x86_64-macos` | `(std build cross)` |
| `platform=?` | `(std build cross)` |
| `plist->alist` | `(std misc plist)` |
| `plist->alist*` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `plist->hash-table` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `plist-fold` | `(std misc plist)` |
| `plist-keys` | `(std misc plist)` |
| `plist-values` | `(std misc plist)` |
| `plist?` | `(std misc plist)` |
| `pmap->alist` | `(std data pmap)` |
| `pmap-cell-ref` | `(std data pmap)` |
| `pmap-cell-set!` | `(std data pmap)` |
| `pmap-cell-snapshot` | `(std data pmap)` |
| `pmap-cell-update!` | `(std data pmap)` |
| `pmap-cell?` | `(std data pmap)` |
| `pmap-contains?` | `(std data pmap)` |
| `pmap-delete` | `(std data pmap)` |
| `pmap-empty` | `(std data pmap)`, `(std pmap)` |
| `pmap-fold` | `(std data pmap)` |
| `pmap-for-each` | `(std data pmap)` |
| `pmap-keys` | `(std data pmap)` |
| `pmap-merge` | `(std data pmap)` |
| `pmap-ref` | `(std data pmap)` |
| `pmap-set` | `(std data pmap)` |
| `pmap-size` | `(std data pmap)` |
| `pmap-snapshot` | `(std data pmap)` |
| `pmap-values` | `(std data pmap)` |
| `pmap?` | `(std data pmap)` |
| `pncounter-decrement!` | `(std actor crdt)` |
| `pncounter-increment!` | `(std actor crdt)` |
| `pncounter-merge!` | `(std actor crdt)` |
| `pncounter-value` | `(std actor crdt)` |
| `pncounter?` | `(std actor crdt)` |
| `pointer-size-for-target` | `(jerboa cross)` |
| `pointerlike-free!` | `(std misc guardian-pool)` |
| `pointerlike-value` | `(std misc guardian-pool)` |
| `pointerlike?` | `(std misc guardian-pool)` |
| `policy-allow!` | `(std capability sandbox)` |
| `policy-allow-import!` | `(std capability sandbox)` |
| `policy-allowed` | `(std capability sandbox)` |
| `policy-allowed-imports` | `(std capability sandbox)` |
| `policy-allows?` | `(std capability sandbox)` |
| `policy-denied` | `(std capability sandbox)` |
| `policy-denied-imports` | `(std capability sandbox)` |
| `policy-deny!` | `(std capability sandbox)` |
| `policy-deny-import!` | `(std capability sandbox)` |
| `poll!` | `(std csp clj)` |
| `poll-resource-finalizers!` | `(std safe)` |
| `poller-register-fd!` | `(std net io)` |
| `poller-unregister-fd!` | `(std net io)` |
| `pool-acquire` | `(std db conpool)`, `(std misc pool)` |
| `pool-acquire!` | `(std net pool)`, `(std net zero-copy)` |
| `pool-available` | `(std db conpool)`, `(std net pool)` |
| `pool-close` | `(std db conpool)` |
| `pool-close!` | `(std net pool)` |
| `pool-drain` | `(std misc pool)` |
| `pool-health-check!` | `(std net pool)` |
| `pool-release` | `(std db conpool)`, `(std misc pool)` |
| `pool-release!` | `(std net pool)`, `(std net zero-copy)` |
| `pool-size` | `(std db conpool)`, `(std net pool)` |
| `pool-stats` | `(std db conpool)`, `(std misc pool)`, `(std net pool)` |
| `pool?` | `(std misc pool)` |
| `pop` | `(jerboa clojure)`, `(std clojure)` |
| `pop!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `port-has-port-position?` | `(std port-position)` |
| `port-has-set-port-position!?` | `(std port-position)` |
| `port-position` | `(std port-position)` |
| `position-character` | `(std lsp)` |
| `position-line` | `(std lsp)` |
| `positive-integer?` | `(std misc number)` |
| `posix-access` | `(std os posix)` |
| `posix-chdir` | `(std os posix)` |
| `posix-close` | `(std os posix)` |
| `posix-dup` | `(std os posix)` |
| `posix-dup2` | `(std os posix)` |
| `posix-errno` | `(std os posix)` |
| `posix-error-errno` | `(std os posix)` |
| `posix-error-message` | `(std os posix)` |
| `posix-error-syscall` | `(std os posix)` |
| `posix-error?` | `(std os posix)` |
| `posix-execve` | `(std os posix)` |
| `posix-exit` | `(std os posix)` |
| `posix-fcntl-getfl` | `(std os posix)` |
| `posix-fcntl-setfl` | `(std os posix)` |
| `posix-fork` | `(std os posix)` |
| `posix-fstat` | `(std os posix)` |
| `posix-get-terminal-size` | `(std os posix)` |
| `posix-getegid` | `(std os posix)` |
| `posix-geteuid` | `(std os posix)` |
| `posix-getgid` | `(std os posix)` |
| `posix-getpgid` | `(std os posix)` |
| `posix-getpid` | `(std os posix)` |
| `posix-getppid` | `(std os posix)` |
| `posix-getrlimit` | `(std os posix)` |
| `posix-getuid` | `(std os posix)` |
| `posix-isatty` | `(std os posix)` |
| `posix-kill` | `(std os posix)` |
| `posix-lseek` | `(std os posix)` |
| `posix-lstat` | `(std os posix)` |
| `posix-mkfifo` | `(std os posix)` |
| `posix-open` | `(std os posix)` |
| `posix-pipe` | `(std os posix)` |
| `posix-read` | `(std os posix)` |
| `posix-setenv` | `(std os posix)` |
| `posix-setgid` | `(std os posix)` |
| `posix-setpgid` | `(std os posix)` |
| `posix-setrlimit` | `(std os posix)` |
| `posix-setsid` | `(std os posix)` |
| `posix-setuid` | `(std os posix)` |
| `posix-sigprocmask` | `(std os posix)` |
| `posix-sigwait` | `(std os posix)` |
| `posix-stat` | `(std os posix)` |
| `posix-strerror` | `(std os posix)` |
| `posix-strftime` | `(std os posix)` |
| `posix-tcgetattr` | `(std os posix)` |
| `posix-tcgetpgrp` | `(std os posix)` |
| `posix-tcsetattr` | `(std os posix)` |
| `posix-tcsetpgrp` | `(std os posix)` |
| `posix-umask` | `(std os posix)` |
| `posix-unlink` | `(std os posix)` |
| `posix-unsetenv` | `(std os posix)` |
| `posix-waitpid` | `(std os posix)` |
| `posix-write` | `(std os posix)` |
| `post:` | `(std contract)` |
| `power` | `(std compiler partial-eval)` |
| `pp` | `(jerboa clojure)`, `(jerboa prelude)`, `(std debug pp)`, `(std gambit-compat)`, ... (+1) |
| `pp-to-string` | `(jerboa clojure)`, `(jerboa prelude)`, `(std debug pp)`, `(std prelude)` |
| `ppd` | `(jerboa clojure)`, `(jerboa prelude)`, `(std debug pp)`, `(std prelude)` |
| `ppd-to-string` | `(jerboa clojure)`, `(jerboa prelude)`, `(std debug pp)`, `(std prelude)` |
| `pprint` | `(jerboa clojure)`, `(jerboa prelude)`, `(std debug pp)`, `(std prelude)` |
| `pput` | `(std misc plist)` |
| `pqueue->list` | `(jerboa clojure)`, `(std clojure)`, `(std misc pqueue)`, `(std pqueue)` |
| `pqueue-clear!` | `(std misc pqueue)` |
| `pqueue-conj` | `(jerboa clojure)`, `(std clojure)`, `(std pqueue)` |
| `pqueue-count` | `(jerboa clojure)`, `(std clojure)`, `(std pqueue)` |
| `pqueue-empty` | `(jerboa clojure)`, `(std clojure)`, `(std pqueue)` |
| `pqueue-empty?` | `(jerboa clojure)`, `(std clojure)`, `(std misc pqueue)`, `(std pqueue)` |
| `pqueue-for-each` | `(std misc pqueue)` |
| `pqueue-length` | `(std misc pqueue)` |
| `pqueue-peek` | `(jerboa clojure)`, `(std clojure)`, `(std misc pqueue)`, `(std pqueue)` |
| `pqueue-pop` | `(jerboa clojure)`, `(std clojure)`, `(std pqueue)` |
| `pqueue-pop!` | `(std misc pqueue)` |
| `pqueue-push!` | `(std misc pqueue)` |
| `pqueue?` | `(jerboa clojure)`, `(std clojure)`, `(std misc pqueue)`, `(std pqueue)` |
| `pr` | `(jerboa clojure)`, `(std clojure)`, `(std misc repr)` |
| `pr-str` | `(jerboa clojure)`, `(std clojure)` |
| `pre:` | `(std contract)` |
| `pred-nav` | `(std specter)` |
| `predicate-specializer` | `(std clos)` |
| `predicate-specializer-description` | `(std clos)` |
| `predicate-specializer-predicate` | `(std clos)` |
| `predicate-specializer?` | `(std clos)` |
| `pregexp` | `(std pregexp)` |
| `pregexp-match` | `(std pregexp)` |
| `pregexp-match-positions` | `(std pregexp)` |
| `pregexp-quote` | `(std pregexp)` |
| `pregexp-replace` | `(std pregexp)` |
| `pregexp-replace*` | `(std pregexp)` |
| `pregexp-split` | `(std pregexp)` |
| `prem` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `prem!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `premq` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `premq!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `premv` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `premv!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `pretty-print-columns` | `(std debug pp)` |
| `prev-prime` | `(std misc prime)` |
| `preview` | `(std lens)` |
| `prime-factors` | `(std misc prime)` |
| `prime?` | `(std misc prime)` |
| `primes-up-to` | `(std misc prime)` |
| `print-error-exit` | `(std cli print-exit)` |
| `print-exit` | `(std cli print-exit)` |
| `print-representation` | `(std misc repr)` |
| `print-stack-trace` | `(thunderchez thunder-utils)` |
| `print-sxml->xml` | `(std markup xml)`, `(std text xml)` |
| `printf` | `(jerboa clojure)`, `(jerboa prelude safe)`, `(jerboa prelude)`, `(std format)`, ... (+1) |
| `println` | `(jerboa clojure)`, `(std clojure)` |
| `prism?` | `(std lens)` |
| `privsep-channel?` | `(std security privsep)` |
| `privsep-request` | `(std security privsep)` |
| `privsep-shutdown!` | `(std security privsep)` |
| `privsep?` | `(std security privsep)` |
| `prn` | `(jerboa clojure)`, `(std clojure)`, `(std misc repr)` |
| `prn-str` | `(jerboa clojure)`, `(std clojure)` |
| `procedure-arity` | `(std inspect)` |
| `process-exit-code` | `(std os fd)` |
| `process-exited?` | `(std os fd)` |
| `process-group-broadcast!` | `(std actor distributed)` |
| `process-group-join!` | `(std actor distributed)` |
| `process-group-leave!` | `(std actor distributed)` |
| `process-group-members` | `(std actor distributed)` |
| `process-kill` | `(std misc process)` |
| `process-pid` | `(std os fd)` |
| `process-port-pid` | `(std misc process)` |
| `process-port-rec-stderr-port` | `(std misc process)` |
| `process-port-rec-stdin-port` | `(std misc process)` |
| `process-port-rec-stdout-port` | `(std misc process)` |
| `process-port-status` | `(std misc process)` |
| `process-port?` | `(std misc process)` |
| `process-signal` | `(std os fd)` |
| `process-signal?` | `(std security capability)` |
| `process-signaled?` | `(std os fd)` |
| `process-spawn?` | `(std security capability)` |
| `process-status` | `(jerboa core)`, `(std gambit-compat)`, `(std os fd)` |
| `process-wait` | `(std os fd)` |
| `process?` | `(std os fd)` |
| `processor-count` | `(jerboa prelude)` |
| `product-ec` | `(std srfi srfi-42)` |
| `profile-call` | `(std dev pgo)` |
| `profile-call-count` | `(std compiler pgo)` |
| `profile-data` | `(std compiler pgo)`, `(std misc profile)` |
| `profile-dominant-type` | `(std dev pgo)` |
| `profile-fn` | `(std debug flamegraph)` |
| `profile-fn/timed` | `(std debug flamegraph)` |
| `profile-guided-inline?` | `(std compiler pgo)` |
| `profile-hot-functions` | `(std compiler pgo)` |
| `profile-load` | `(std compiler pgo)` |
| `profile-load!` | `(std compiler pgo)` |
| `profile-report` | `(std compiler pgo)`, `(std dev profile)`, `(std misc profile)` |
| `profile-reset!` | `(std compiler pgo)`, `(std dev profile)`, `(std misc profile)` |
| `profile-results` | `(std dev profile)` |
| `profile-running?` | `(std compiler pgo)` |
| `profile-save` | `(std compiler pgo)` |
| `profile-site-counts` | `(std dev pgo)` |
| `profile-start!` | `(std dev profile)` |
| `profile-stats` | `(std profile)` |
| `profile-stop!` | `(std dev profile)` |
| `profile-summary` | `(std dev pgo)` |
| `profile-thunk` | `(std debug flamegraph)` |
| `profile-val` | `(std dev pgo)` |
| `profiler->alist` | `(std debug flamegraph)` |
| `profiler->flamegraph-text` | `(std debug flamegraph)` |
| `profiler-enter!` | `(std debug flamegraph)` |
| `profiler-exit!` | `(std debug flamegraph)` |
| `profiler-flat-stats` | `(std debug flamegraph)` |
| `profiler-hotspots` | `(std debug flamegraph)` |
| `profiler-reset!` | `(std debug flamegraph)` |
| `profiler-running?` | `(std debug flamegraph)` |
| `profiler-samples` | `(std debug flamegraph)` |
| `profiler-start!` | `(std debug flamegraph)` |
| `profiler-stop!` | `(std debug flamegraph)` |
| `profiler-timing-enter!` | `(std debug flamegraph)` |
| `profiler-timing-exit!` | `(std debug flamegraph)` |
| `profiler-timing-stats` | `(std debug flamegraph)` |
| `profiler-total-samples` | `(std debug flamegraph)` |
| `profiler-tree` | `(std debug flamegraph)` |
| `profiler?` | `(std debug flamegraph)` |
| `profiling-active?` | `(std misc profile)` |
| `profiling-disable!` | `(std compiler pgo)` |
| `profiling-enable!` | `(std compiler pgo)` |
| `project` | `(std event-source)` |
| `project-since` | `(std event-source)` |
| `projection-current` | `(std event-source)` |
| `prometheus-format` | `(std metrics)` |
| `promise-await` | `(std concur async-await)` |
| `promise-chan` | `(std csp clj)` |
| `promise-channel-get!` | `(std csp ops)` |
| `promise-channel-put!` | `(std csp ops)` |
| `promise-channel?` | `(std csp ops)` |
| `promise-reject!` | `(std concur async-await)` |
| `promise-resolve!` | `(std concur async-await)` |
| `promise-resolved?` | `(std concur async-await)` |
| `promise?` | `(jerboa clojure)`, `(std clojure)`, `(std concur async-await)` |
| `prompt` | `(std control delimited)` |
| `prompt-at` | `(std control delimited)` |
| `prompt-tag-name` | `(std control delimited)` |
| `prompt-tag?` | `(std control delimited)` |
| `prop-for-all` | `(std test framework)` |
| `propagate-taint` | `(std taint)` |
| `proper-list?` | `(std srfi srfi-1)` |
| `property-counterexample` | `(std proptest)` |
| `property-failed?` | `(std proptest)` |
| `property-list` | `(std symbol-property)` |
| `property-num-trials` | `(std proptest)` |
| `property-passed?` | `(std proptest)` |
| `property-report` | `(std proptest)` |
| `property-result?` | `(std proptest)` |
| `proto-enum-name` | `(std protobuf grammar)` |
| `proto-enum-values` | `(std protobuf grammar)` |
| `proto-enum?` | `(std protobuf grammar)` |
| `proto-field-label` | `(std protobuf grammar)` |
| `proto-field-name` | `(std protobuf grammar)` |
| `proto-field-number` | `(std protobuf grammar)` |
| `proto-field-type` | `(std protobuf grammar)` |
| `proto-field?` | `(std protobuf grammar)` |
| `proto-file-enums` | `(std protobuf grammar)` |
| `proto-file-imports` | `(std protobuf grammar)` |
| `proto-file-messages` | `(std protobuf grammar)` |
| `proto-file-package` | `(std protobuf grammar)` |
| `proto-file-services` | `(std protobuf grammar)` |
| `proto-file-syntax` | `(std protobuf grammar)` |
| `proto-file?` | `(std protobuf grammar)` |
| `proto-message-fields` | `(std protobuf grammar)` |
| `proto-message-name` | `(std protobuf grammar)` |
| `proto-message?` | `(std protobuf grammar)` |
| `proto-service-methods` | `(std protobuf grammar)` |
| `proto-service-name` | `(std protobuf grammar)` |
| `proto-service?` | `(std protobuf grammar)` |
| `protobuf->alist` | `(std protobuf)` |
| `protobuf->message` | `(std protobuf macros)` |
| `protobuf-decode` | `(std protobuf)` |
| `protobuf-encode` | `(std protobuf)` |
| `protocol-methods` | `(std protocol)` |
| `protocol-name` | `(std protocol)` |
| `protocol-registry` | `(std derive2)` |
| `protocol?` | `(std protocol)` |
| `provenance->sexp` | `(std build reproducible)` |
| `provenance-build-timestamp` | `(std build reproducible)` |
| `provenance-builder-id` | `(std build reproducible)` |
| `provenance-output-hash` | `(std build reproducible)` |
| `provenance-read` | `(std build reproducible)` |
| `provenance-source-hash` | `(std build reproducible)` |
| `provenance-write` | `(std build reproducible)` |
| `provenance?` | `(std build reproducible)` |
| `ps-end?` | `(std regex-ct-impl)` |
| `ps-new-group!` | `(std regex-ct-impl)` |
| `ps-next!` | `(std regex-ct-impl)` |
| `ps-peek` | `(std regex-ct-impl)` |
| `ps-pos` | `(std regex-ct-impl)` |
| `ps-set-pos!` | `(std regex-ct-impl)` |
| `ps-str` | `(std regex-ct-impl)` |
| `pset` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `pset!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `pset->list` | `(std pset)` |
| `pset-add` | `(std pset)` |
| `pset-contains?` | `(std pset)` |
| `pset-difference` | `(std pset)` |
| `pset-empty` | `(std pset)` |
| `pset-filter` | `(std pset)` |
| `pset-fold` | `(std pset)` |
| `pset-for-each` | `(std pset)` |
| `pset-hash` | `(std pset)` |
| `pset-intersection` | `(std pset)` |
| `pset-map` | `(std pset)` |
| `pset-remove` | `(std pset)` |
| `pset-size` | `(std pset)` |
| `pset-subset?` | `(std pset)` |
| `pset-union` | `(std pset)` |
| `pset=?` | `(std pset)` |
| `pset?` | `(std pset)` |
| `psetq` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `psetq!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `psetv` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `psetv!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc alist)` |
| `pub` | `(std csp clj)` |
| `pub-source` | `(std csp ops)` |
| `pub?` | `(std csp ops)` |
| `pure?` | `(std typed effects)` |
| `push!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `put!` | `(std csp clj)`, `(std csp ops)` |
| `putprop` | `(std symbol-property)` |
| `putval` | `(std specter)` |
| `pvec-empty` | `(std pvec)` |
| `python->scheme` | `(std python)` |
| `python-call` | `(std python)` |
| `python-dict->scheme` | `(std python)` |
| `python-error-message` | `(std python)` |
| `python-error?` | `(std python)` |
| `python-eval` | `(std python)` |
| `python-exec` | `(std python)` |
| `python-import` | `(std python)` |
| `python-list->scheme` | `(std python)` |
| `python-numpy-array` | `(std python)` |
| `python-numpy-result` | `(std python)` |
| `python-proc?` | `(std python)` |
| `python-running?` | `(std python)` |
| `python-version` | `(std python)` |

### <a name="idx-q"></a>q

| Symbol | Modules |
| --- | --- |
| `QRcode` | `(std ffi qrencode)`, `(thunderchez qrencode)` |
| `q:<` | `(std query)` |
| `q:<=` | `(std query)` |
| `q:=` | `(std query)` |
| `q:>` | `(std query)` |
| `q:>=` | `(std query)` |
| `q:and` | `(std query)` |
| `q:between` | `(std query)` |
| `q:in` | `(std query)` |
| `q:like` | `(std query)` |
| `q:not` | `(std query)` |
| `q:or` | `(std query)` |
| `qr-ec-level` | `(std ffi qrencode)`, `(thunderchez qrencode)` |
| `qr-encode-init` | `(std ffi qrencode)`, `(thunderchez qrencode)` |
| `qr-encode-mode` | `(std ffi qrencode)`, `(thunderchez qrencode)` |
| `qr-encode-string-8bit` | `(std ffi qrencode)`, `(thunderchez qrencode)` |
| `qrcode-data` | `(std ffi qrencode)`, `(thunderchez qrencode)` |
| `qrcode-data-ref` | `(std ffi qrencode)`, `(thunderchez qrencode)` |
| `qrcode-version` | `(std ffi qrencode)`, `(thunderchez qrencode)` |
| `qrcode-width` | `(std ffi qrencode)`, `(thunderchez qrencode)` |
| `quasigen` | `(std staging)` |
| `query` | `(std query)` |
| `query->string` | `(std db query-compile)` |
| `query-execute` | `(std query)` |
| `query-param` | `(std db query-compile)` |
| `query-param-name` | `(std db query-compile)` |
| `query-param-value` | `(std db query-compile)` |
| `query-string->alist` | `(std net uri)` |
| `query?` | `(std db query-compile)` |
| `queue->list` | `(std misc queue)` |
| `queue-empty?` | `(std misc queue)` |
| `queue-length` | `(std misc queue)` |
| `queue-peek` | `(std misc queue)` |
| `queue?` | `(std misc queue)` |
| `quickcheck` | `(std test quickcheck)` |
| `quote-stage` | `(std staging2)` |

### <a name="idx-r"></a>r

| Symbol | Modules |
| --- | --- |
| `RLIMIT_AS` | `(std os posix)` |
| `RLIMIT_CORE` | `(std os posix)` |
| `RLIMIT_DATA` | `(std os posix)` |
| `RLIMIT_FSIZE` | `(std os posix)` |
| `RLIMIT_NOFILE` | `(std os posix)` |
| `RLIMIT_NPROC` | `(std os posix)` |
| `RLIMIT_STACK` | `(std os posix)` |
| `R_OK` | `(std os posix)` |
| `Refine` | `(std typed refine)` |
| `Row` | `(std typed row2)` |
| `r-drop` | `(jerboa clojure)`, `(std clojure reducers)` |
| `r-filter` | `(jerboa clojure)`, `(std clojure reducers)` |
| `r-flatten` | `(jerboa clojure)`, `(std clojure reducers)` |
| `r-fold` | `(jerboa clojure)`, `(std clojure reducers)` |
| `r-foldcat` | `(jerboa clojure)`, `(std clojure reducers)` |
| `r-map` | `(jerboa clojure)`, `(std clojure reducers)` |
| `r-mapcat` | `(jerboa clojure)`, `(std clojure reducers)` |
| `r-reduce` | `(jerboa clojure)`, `(std clojure reducers)` |
| `r-remove` | `(jerboa clojure)`, `(std clojure reducers)` |
| `r-take` | `(jerboa clojure)`, `(std clojure reducers)` |
| `r-take-while` | `(jerboa clojure)`, `(std clojure reducers)` |
| `ra-list->list` | `(std srfi srfi-101)` |
| `ra:append` | `(std srfi srfi-101)` |
| `ra:car` | `(std srfi srfi-101)` |
| `ra:cdr` | `(std srfi srfi-101)` |
| `ra:cons` | `(std srfi srfi-101)` |
| `ra:fold` | `(std srfi srfi-101)` |
| `ra:for-each` | `(std srfi srfi-101)` |
| `ra:length` | `(std srfi srfi-101)` |
| `ra:list` | `(std srfi srfi-101)` |
| `ra:list->ra-list` | `(std srfi srfi-101)` |
| `ra:list-ref` | `(std srfi srfi-101)` |
| `ra:list-ref/update` | `(std srfi srfi-101)` |
| `ra:list-set` | `(std srfi srfi-101)` |
| `ra:list?` | `(std srfi srfi-101)` |
| `ra:map` | `(std srfi srfi-101)` |
| `ra:null?` | `(std srfi srfi-101)` |
| `ra:pair?` | `(std srfi srfi-101)` |
| `race` | `(jerboa prelude safe)`, `(std concur structured)` |
| `rack-handler` | `(std web rack)` |
| `rack-request` | `(std web rack)` |
| `rack-response` | `(std web rack)` |
| `rack-run` | `(std web rack)` |
| `raft-cluster-leader` | `(std raft)` |
| `raft-cluster-nodes` | `(std raft)` |
| `raft-commit-index` | `(std raft)` |
| `raft-leader?` | `(std raft)` |
| `raft-log` | `(std raft)` |
| `raft-node-add-peer!` | `(std raft)` |
| `raft-node-inbox` | `(std raft)` |
| `raft-node-peers` | `(std raft)` |
| `raft-node-peers-set!` | `(std raft)` |
| `raft-propose!` | `(std raft)` |
| `raft-start!` | `(std raft)` |
| `raft-state` | `(std raft)` |
| `raft-stop!` | `(std raft)` |
| `raft-term` | `(std raft)` |
| `raise` | `(jerboa runtime)` |
| `raise-db-error` | `(std error conditions)` |
| `raise-error` | `(std error)` |
| `raise-in-context` | `(std error context)` |
| `raise-network-error` | `(std error conditions)` |
| `raise-parse-error` | `(std error conditions)` |
| `raise-ssh-auth-error` | `(std net ssh conditions)` |
| `raise-ssh-channel-error` | `(std net ssh conditions)` |
| `raise-ssh-connection-error` | `(std net ssh conditions)` |
| `raise-ssh-error` | `(std net ssh conditions)` |
| `raise-ssh-host-key-error` | `(std net ssh conditions)` |
| `raise-ssh-kex-error` | `(std net ssh conditions)` |
| `raise-ssh-protocol-error` | `(std net ssh conditions)` |
| `raise-ssh-sftp-error` | `(std net ssh conditions)` |
| `raise-ssh-timeout-error` | `(std net ssh conditions)` |
| `raise-timeout-error` | `(std error conditions)` |
| `random-ascii-string` | `(std test fuzz)` |
| `random-bytes` | `(jerboa core)`, `(std crypto etc)`, `(std crypto random)`, `(std gambit-compat)` |
| `random-bytes!` | `(std crypto etc)`, `(std crypto random)` |
| `random-bytevector` | `(std test fuzz)` |
| `random-choice` | `(std test fuzz)` |
| `random-element` | `(std test fuzz)` |
| `random-integer` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude)`, `(std gambit-compat)` |
| `random-token` | `(std crypto random)` |
| `random-u64` | `(std crypto random)` |
| `random-utf8-string` | `(std test fuzz)` |
| `random-uuid` | `(std crypto random)` |
| `range` | `(jerboa clojure)`, `(std clojure)` |
| `range->generator` | `(std srfi srfi-121)` |
| `range-end` | `(std lsp)` |
| `range-start` | `(std lsp)` |
| `rassoc` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `rate-limit-check!` | `(std security auth)` |
| `rate-limiter-acquire!` | `(std misc rate-limiter)` |
| `rate-limiter-available` | `(std misc rate-limiter)` |
| `rate-limiter-reset!` | `(std misc rate-limiter)` |
| `rate-limiter-try!` | `(std net rate)` |
| `rate-limiter-try-acquire` | `(std misc rate-limiter)` |
| `rate-limiter-wait!` | `(std net rate)` |
| `rate-limiter?` | `(std misc rate-limiter)`, `(std net rate)` |
| `rbtree->list` | `(std misc rbtree)` |
| `rbtree-contains?` | `(std misc rbtree)` |
| `rbtree-delete` | `(std misc rbtree)` |
| `rbtree-empty?` | `(std misc rbtree)` |
| `rbtree-fold` | `(std misc rbtree)` |
| `rbtree-insert` | `(std misc rbtree)` |
| `rbtree-lookup` | `(std misc rbtree)` |
| `rbtree-max` | `(std misc rbtree)` |
| `rbtree-min` | `(std misc rbtree)` |
| `rbtree-size` | `(std misc rbtree)` |
| `rbtree?` | `(std misc rbtree)` |
| `re` | `(jerboa clojure)`, `(jerboa prelude)`, `(std regex)` |
| `re-compile-uncached` | `(std regex)` |
| `re-find-all` | `(jerboa clojure)`, `(jerboa prelude)`, `(std regex)` |
| `re-fold` | `(jerboa clojure)`, `(jerboa prelude)`, `(std regex)` |
| `re-groups` | `(jerboa clojure)`, `(jerboa prelude)`, `(std regex)` |
| `re-match-end` | `(jerboa clojure)`, `(jerboa prelude)`, `(std regex)` |
| `re-match-full` | `(jerboa clojure)`, `(jerboa prelude)`, `(std regex)` |
| `re-match-group` | `(jerboa clojure)`, `(jerboa prelude)`, `(std regex)` |
| `re-match-groups` | `(jerboa clojure)`, `(jerboa prelude)`, `(std regex)` |
| `re-match-named` | `(jerboa clojure)`, `(jerboa prelude)`, `(std regex)` |
| `re-match-start` | `(jerboa clojure)`, `(jerboa prelude)`, `(std regex)` |
| `re-match?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std regex)` |
| `re-object-pat-string` | `(std regex)` |
| `re-quote-replacement` | `(std clojure string)` |
| `re-replace` | `(jerboa clojure)`, `(jerboa prelude)`, `(std regex)` |
| `re-replace-all` | `(jerboa clojure)`, `(jerboa prelude)`, `(std regex)` |
| `re-search` | `(jerboa clojure)`, `(jerboa prelude)`, `(std regex)` |
| `re-split` | `(jerboa clojure)`, `(jerboa prelude)`, `(std regex)` |
| `re?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std regex)` |
| `read-all` | `(std io)` |
| `read-all-as-bytes` | `(std misc port-utils)` |
| `read-all-as-lines` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `read-all-as-string` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+3) |
| `read-csv` | `(jerboa clojure)`, `(jerboa prelude)`, `(std csv)`, `(std prelude)`, ... (+1) |
| `read-csv-file` | `(jerboa clojure)`, `(jerboa prelude)`, `(std csv)`, `(std prelude)` |
| `read-csv-records` | `(std text csv)` |
| `read-delimited` | `(std io delimited)` |
| `read-edn` | `(std text edn)` |
| `read-edn-string` | `(std text edn)` |
| `read-fields` | `(std io delimited)` |
| `read-file-lines` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `read-file-string` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `read-json` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `read-line` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude)`, `(std gambit-compat)` |
| `read-line*` | `(std io delimited)` |
| `read-lock!` | `(std misc rwlock)` |
| `read-lsp-message` | `(std lsp)` |
| `read-netstring` | `(std ffi netstring)`, `(thunderchez netstring)` |
| `read-netstring/string` | `(std ffi netstring)`, `(thunderchez netstring)` |
| `read-paragraph` | `(std io delimited)` |
| `read-proto-file` | `(std protobuf grammar)` |
| `read-proto-string` | `(std protobuf grammar)` |
| `read-record` | `(std io delimited)` |
| `read-sexp-file` | `(std io)` |
| `read-sexp-port` | `(std io)` |
| `read-string` | `(jerboa core)`, `(std gambit-compat)`, `(thunderchez thunder-utils)` |
| `read-subu8vector` | `(std gambit-compat)` |
| `read-toml` | `(std text toml)` |
| `read-u8` | `(jerboa core)`, `(std gambit-compat)` |
| `read-unlock!` | `(std misc rwlock)` |
| `read-until` | `(std io delimited)` |
| `read-with-deadline` | `(std net timeout)` |
| `reader` | `(std clojure io)` |
| `reader-ask` | `(std typed monad)` |
| `reader-bind` | `(std typed monad)` |
| `reader-cloj-mode` | `(jerboa cloj)`, `(jerboa clojure)`, `(jerboa reader)` |
| `reader-column` | `(std io strio)` |
| `reader-eof?` | `(std io strio)` |
| `reader-line` | `(std io strio)` |
| `reader-local` | `(std typed monad)` |
| `reader-peek-char` | `(std io strio)` |
| `reader-position` | `(std io strio)` |
| `reader-read-char` | `(std io strio)` |
| `reader-read-line` | `(std io strio)` |
| `reader-read-until` | `(std io strio)` |
| `reader-read-while` | `(std io strio)` |
| `reader-return` | `(std typed monad)` |
| `realized?` | `(jerboa clojure)`, `(std clojure)` |
| `receive` | `(std srfi srfi-8)`, `(std values)` |
| `record->alist` | `(std debug record-inspect)` |
| `record-call!` | `(std debug timetravel)` |
| `record-constructor-descriptor` | `(std record-meta)` |
| `record-copy` | `(std debug record-inspect)` |
| `record-event!` | `(std debug timetravel)` |
| `record-execution` | `(std debug replay)` |
| `record-extend` | `(std typed row2)` |
| `record-field-count` | `(std debug record-inspect)` |
| `record-field-names-of` | `(std derive2)` |
| `record-field-values` | `(std derive2)` |
| `record-merge` | `(std typed row2)` |
| `record-ref` | `(std debug record-inspect)` |
| `record-restrict` | `(std typed row2)` |
| `record-return!` | `(std debug timetravel)` |
| `record-rtd` | `(std record-meta)` |
| `record-set!` | `(std debug record-inspect)` |
| `record-snapshot!` | `(std debug timetravel)` |
| `record-state!` | `(std debug timetravel)` |
| `record-type-call!` | `(std specialize)` |
| `record-type-descriptor` | `(std record-meta)` |
| `record-type-descriptor?` | `(std record-meta)` |
| `record-type-field-count` | `(std record-meta)` |
| `record-type-field-names` | `(std debug record-inspect)`, `(std record-meta)` |
| `record-type-generative?` | `(std record-meta)` |
| `record-type-name` | `(std debug record-inspect)`, `(std record-meta)` |
| `record-type-opaque?` | `(std record-meta)` |
| `record-type-parent` | `(std record-meta)` |
| `record-type-parent*` | `(std debug record-inspect)` |
| `record-type-sealed?` | `(std record-meta)` |
| `record-type-uid` | `(std record-meta)` |
| `record?` | `(std record-meta)` |
| `recorder-event-count` | `(std debug timetravel)` |
| `recorder-events` | `(std debug timetravel)` |
| `recorder-reset!` | `(std debug timetravel)` |
| `recorder-start!` | `(std debug timetravel)` |
| `recorder-stop!` | `(std debug timetravel)` |
| `recorder?` | `(std debug timetravel)` |
| `recording-add!` | `(std debug replay)` |
| `recording-count` | `(std debug replay)` |
| `recording-events` | `(std debug replay)` |
| `recording-result` | `(std debug replay)` |
| `recording?` | `(std debug replay)`, `(std dev debug)` |
| `recur` | `(jerboa clojure)`, `(std clojure)` |
| `recv` | `(std select)` |
| `red` | `(std cli style)` |
| `redis-init` | `(std ffi redis)`, `(thunderchez redis)` |
| `reduce` | `(jerboa clojure)`, `(std clojure)`, `(std srfi srfi-1)` |
| `reduce-kv` | `(jerboa clojure)`, `(std clojure)` |
| `reduce-right` | `(std srfi srfi-1)` |
| `reduced` | `(std transducer)` |
| `reduced?` | `(std transducer)` |
| `reductions` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)`, `(std prelude)` |
| `ref` | `(std ref)` |
| `ref-deref` | `(std stm)` |
| `ref-set` | `(std stm)` |
| `ref-set!` | `(std ref)` |
| `ref?` | `(std stm)` |
| `refine-branch` | `(std typed refine)` |
| `refinement-base` | `(std typed refine)` |
| `refinement-name` | `(std typed refine)` |
| `refinement-pred` | `(std typed refine)` |
| `refinement-type-base` | `(std typed advanced)` |
| `refinement-type-pred` | `(std typed advanced)` |
| `refinement-type?` | `(std typed advanced)` |
| `refinement?` | `(std typed refine)` |
| `regex-char-class-chars` | `(std text regex-compile)` |
| `regex-char-class-negated?` | `(std text regex-compile)` |
| `regex-char-class?` | `(std text regex-compile)` |
| `regex-compile` | `(std regex-native)` |
| `regex-dfa-compatible?` | `(std regex-ct)` |
| `regex-find` | `(std regex-native)`, `(std text regex-compile)` |
| `regex-free` | `(std regex-native)` |
| `regex-literal-char` | `(std text regex-compile)` |
| `regex-literal?` | `(std text regex-compile)` |
| `regex-match` | `(jerboa clojure)`, `(jerboa prelude)`, `(std text regex-compile)` |
| `regex-match?` | `(std regex-ct)`, `(std regex-native)`, `(std text regex-compile)` |
| `regex-optional-inner` | `(std text regex-compile)` |
| `regex-optional?` | `(std text regex-compile)` |
| `regex-or-alternatives` | `(std text regex-compile)` |
| `regex-or?` | `(std text regex-compile)` |
| `regex-pattern?` | `(std text regex-compile)` |
| `regex-plus-inner` | `(std text regex-compile)` |
| `regex-plus?` | `(std text regex-compile)` |
| `regex-quote` | `(std text regex-compile)` |
| `regex-repeat-inner` | `(std text regex-compile)` |
| `regex-repeat-max` | `(std text regex-compile)` |
| `regex-repeat-min` | `(std text regex-compile)` |
| `regex-repeat?` | `(std text regex-compile)` |
| `regex-replace` | `(jerboa clojure)`, `(jerboa prelude)` |
| `regex-replace-all` | `(jerboa clojure)`, `(jerboa prelude)`, `(std regex-native)` |
| `regex-search` | `(jerboa clojure)`, `(jerboa prelude)`, `(std regex-ct)` |
| `regex-sequence-parts` | `(std text regex-compile)` |
| `regex-sequence?` | `(std text regex-compile)` |
| `regex-split` | `(std text regex-compile)` |
| `regex-star-inner` | `(std text regex-compile)` |
| `regex-star?` | `(std text regex-compile)` |
| `regexp` | `(std srfi srfi-115)` |
| `regexp-extract` | `(std srfi srfi-115)` |
| `regexp-fold` | `(std srfi srfi-115)` |
| `regexp-match-count` | `(std srfi srfi-115)` |
| `regexp-match-submatch` | `(std srfi srfi-115)` |
| `regexp-match?` | `(std srfi srfi-115)` |
| `regexp-matches` | `(std srfi srfi-115)` |
| `regexp-matches?` | `(std srfi srfi-115)` |
| `regexp-replace` | `(std srfi srfi-115)` |
| `regexp-replace-all` | `(std srfi srfi-115)` |
| `regexp-search` | `(std srfi srfi-115)` |
| `regexp-split` | `(std srfi srfi-115)` |
| `regexp?` | `(std srfi srfi-115)` |
| `region-alive?` | `(std region)` |
| `region-alloc` | `(std region)` |
| `region-alloc-bytevector` | `(std region)` |
| `region-alloc-string` | `(std region)` |
| `region-free!` | `(std region)` |
| `region-ref` | `(std region)` |
| `region-set!` | `(std region)` |
| `register!` | `(std actor registry)`, `(std actor)` |
| `register-binary-type!` | `(std misc binary-type)` |
| `register-check!` | `(std health)` |
| `register-class!` | `(std clos)` |
| `register-derivation!` | `(std derive)` |
| `register-doc!` | `(std doc)`, `(std repl)` |
| `register-error-class!` | `(std security errors)` |
| `register-eval-hook!` | `(std repl middleware)` |
| `register-input-transformer!` | `(std repl middleware)` |
| `register-instance!` | `(std misc typeclass)` |
| `register-lifecycle!` | `(std component fiber)`, `(std component)` |
| `register-method-impl!` | `(std dev devirt)` |
| `register-mime-type!` | `(std mime types)` |
| `register-module!` | `(std dev reload)` |
| `register-optimization-pass!` | `(std compiler passes)` |
| `register-persistent-class!` | `(std odb)` |
| `register-prompt-fn!` | `(std repl middleware)` |
| `register-protocol!` | `(std derive2)` |
| `register-repl-command!` | `(std repl middleware)` |
| `register-repl-printer!` | `(std repl middleware)` |
| `register-resource!` | `(std concur)` |
| `register-resource-cleanup!` | `(jerboa prelude safe)`, `(std resource)` |
| `register-safe-record-type!` | `(jerboa prelude safe)`, `(std safe-fasl)` |
| `register-startup-hook!` | `(std repl middleware)` |
| `register-struct-type!` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+5) |
| `register-type-predicate!` | `(std typed)` |
| `register-typeclass!` | `(std misc typeclass)` |
| `register-waiting!` | `(std concur deadlock)` |
| `register-world!` | `(std image)` |
| `registered-modules` | `(std dev reload)` |
| `registered-names` | `(std actor registry)`, `(std actor)` |
| `registry-actor` | `(std actor registry)`, `(std actor)` |
| `registry-collect` | `(std metrics)` |
| `registry-lookup` | `(jerboa registry)` |
| `registry-search` | `(jerboa registry)` |
| `registry?` | `(std metrics)` |
| `reify` | `(jerboa clojure)`, `(std logic)` |
| `relation->alist-list` | `(std misc relation)` |
| `relation-aggregate` | `(std misc relation)` |
| `relation-columns` | `(std misc relation)` |
| `relation-count` | `(std misc relation)` |
| `relation-extend` | `(std misc relation)` |
| `relation-group-by` | `(std misc relation)` |
| `relation-join` | `(std misc relation)` |
| `relation-project` | `(std misc relation)` |
| `relation-ref` | `(std misc relation)` |
| `relation-rows` | `(std misc relation)` |
| `relation-select` | `(std misc relation)` |
| `relation-sort` | `(std misc relation)` |
| `relation?` | `(std misc relation)` |
| `releasing-resource!` | `(std concur deadlock)` |
| `reload!` | `(std dev reload)` |
| `reload-if-changed!` | `(std dev reload)` |
| `reload-result-error` | `(jerboa hot)` |
| `reload-result-file` | `(jerboa hot)` |
| `reload-result-success?` | `(jerboa hot)` |
| `reload-result?` | `(jerboa hot)` |
| `reloader-check!` | `(jerboa hot)` |
| `reloader-force-stale!` | `(jerboa hot)` |
| `reloader-on-error!` | `(jerboa hot)` |
| `reloader-on-reload!` | `(jerboa hot)` |
| `reloader-reload!` | `(jerboa hot)` |
| `reloader-unwatch!` | `(jerboa hot)` |
| `reloader-watch!` | `(jerboa hot)` |
| `reloader-watched` | `(jerboa hot)` |
| `reloader?` | `(jerboa hot)` |
| `remote-ref-id` | `(std actor distributed)` |
| `remote-ref-node` | `(std actor distributed)` |
| `remote-ref?` | `(std actor distributed)` |
| `remote-register!` | `(std actor cluster)` |
| `remote-unregister!` | `(std actor cluster)` |
| `remote-whereis` | `(std actor cluster)` |
| `remove-method` | `(std multi)` |
| `remove-rule!` | `(std lint)` |
| `remove-signal-handler!` | `(std os signal)` |
| `remove-watch!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc atom)` |
| `remprop` | `(std symbol-property)` |
| `repeat` | `(jerboa clojure)`, `(std clojure)` |
| `repeatedly` | `(jerboa clojure)`, `(std clojure)` |
| `repl-apropos` | `(std repl)` |
| `repl-command-registered?` | `(std repl middleware)` |
| `repl-complete` | `(std repl)` |
| `repl-config-color?` | `(std repl)` |
| `repl-config-history-size` | `(std repl)` |
| `repl-config-prompt` | `(std repl)` |
| `repl-config-show-time?` | `(std repl)` |
| `repl-config?` | `(std repl)` |
| `repl-doc` | `(std repl)` |
| `repl-expand` | `(std repl)` |
| `repl-history-ref` | `(std repl)` |
| `repl-load` | `(std repl)` |
| `repl-pp` | `(std repl)` |
| `repl-server-port` | `(std net repl)`, `(std repl server)` |
| `repl-server-running?` | `(std repl server)` |
| `repl-server-start` | `(std repl server)` |
| `repl-server-stop` | `(std repl server)` |
| `repl-server?` | `(std net repl)`, `(std repl server)` |
| `repl-time` | `(std repl)` |
| `repl-type` | `(std repl)` |
| `replace` | `(std clojure string)` |
| `replace-first` | `(std clojure string)` |
| `replay-events` | `(std debug timetravel)` |
| `replay-execution` | `(std debug replay)` |
| `replay-random` | `(std debug replay)` |
| `replay-time` | `(std debug replay)` |
| `replay-to-step` | `(std debug timetravel)` |
| `replay-window-check!` | `(std actor cluster-security)` |
| `replay-window?` | `(std actor cluster-security)` |
| `reply` | `(std actor protocol)`, `(std actor)` |
| `reply-channel-get` | `(std actor protocol)` |
| `reply-channel-put!` | `(std actor protocol)` |
| `reply-channel?` | `(std actor protocol)` |
| `reply-to` | `(std actor protocol)`, `(std actor)` |
| `report-leaks` | `(std debug memleak)` |
| `repr` | `(std misc repr)` |
| `request->ring` | `(std net ring)` |
| `request-body` | `(std net fiber-httpd)` |
| `request-close` | `(std net request)` |
| `request-content` | `(std net request)` |
| `request-header` | `(std net fiber-httpd)`, `(std net request)` |
| `request-headers` | `(std net fiber-httpd)`, `(std net request)` |
| `request-method` | `(std net fiber-httpd)` |
| `request-path` | `(std net fiber-httpd)` |
| `request-path-only` | `(std net fiber-httpd)` |
| `request-query-string` | `(std net fiber-httpd)` |
| `request-status` | `(std net request)` |
| `request-text` | `(std net request)` |
| `request-version` | `(std net fiber-httpd)` |
| `request?` | `(std net fiber-httpd)` |
| `require` | `(jerboa clojure)`, `(std clojure)` |
| `requires:` | `(std security capability-typed)` |
| `reset` | `(std control delimited)`, `(std misc delimited)` |
| `reset!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc atom)` |
| `reset-at` | `(std control delimited)` |
| `reset-handler` | `(std cafe)` |
| `reset-linear-stats!` | `(std dev cont-mark-opt)` |
| `reset-lock-tracking!` | `(std concur)` |
| `reset-style` | `(std misc terminal)` |
| `reset-taint-violations!` | `(std taint)` |
| `reset-type-errors!` | `(std typed infer)` |
| `reset/values` | `(std control delimited)` |
| `resolve-deps` | `(jerboa pkg)` |
| `resolve-hostname` | `(std net address)` |
| `resource-already-closed?` | `(jerboa prelude safe)`, `(std error conditions)` |
| `resource-error-resource-type` | `(std error conditions)` |
| `resource-error?` | `(jerboa prelude safe)`, `(std error conditions)`, `(std safe)` |
| `resource-exhausted-limit` | `(std error conditions)` |
| `resource-exhausted?` | `(jerboa prelude safe)`, `(std error conditions)` |
| `resource-leak?` | `(jerboa prelude safe)`, `(std error conditions)` |
| `respond` | `(std net fiber-httpd)` |
| `respond-html` | `(std net fiber-httpd)` |
| `respond-json` | `(std net fiber-httpd)` |
| `respond-text` | `(std net fiber-httpd)` |
| `response-body` | `(std net fiber-httpd)` |
| `response-headers` | `(std net fiber-httpd)` |
| `response-status` | `(std net fiber-httpd)` |
| `response?` | `(std net fiber-httpd)` |
| `rest` | `(jerboa clojure)`, `(std clojure)` |
| `rest-arguments` | `(std cli getopt)` |
| `rest-for-one` | `(std proc supervisor)` |
| `restart-agent` | `(std agent)` |
| `restore-actor-mailbox` | `(std actor checkpoint)` |
| `restore-value` | `(std actor checkpoint)` |
| `restricted-eval` | `(std security restrict)` |
| `restricted-eval-string` | `(std security restrict)` |
| `result->` | `(std misc result)` |
| `result->option` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `result->values` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `result-and-then` | `(std misc result)` |
| `result-bind` | `(std misc result)`, `(std typed hkt)` |
| `result-err?` | `(std misc result)` |
| `result-fmap` | `(std typed hkt)` |
| `result-fold` | `(std misc result)` |
| `result-guard` | `(std misc result)` |
| `result-map` | `(std misc result)` |
| `result-map-err` | `(std misc result)` |
| `result-ok?` | `(std misc result)` |
| `result-or-else` | `(std misc result)` |
| `result-return` | `(std typed hkt)` |
| `result-unwrap` | `(std misc result)` |
| `result-unwrap-or` | `(std misc result)` |
| `result?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc result)`, `(std prelude)`, ... (+1) |
| `results-collect` | `(std misc result)` |
| `results-partition` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `resume` | `(std effect)` |
| `resume-computation` | `(std persist closure)` |
| `resume-in-tail-position?` | `(std dev cont-mark-opt)` |
| `resume/deep` | `(std effect deep)` |
| `resume/multi` | `(std effect multishot)` |
| `retry` | `(std concur stm)`, `(std misc retry)`, `(std stm)` |
| `retry-on` | `(std error recovery)` |
| `retry-policy-base-delay` | `(std misc retry)` |
| `retry-policy-jitter?` | `(std misc retry)` |
| `retry-policy-max-attempts` | `(std misc retry)` |
| `retry-policy-max-delay` | `(std misc retry)` |
| `retry-policy?` | `(std misc retry)` |
| `retry/backoff` | `(std misc retry)` |
| `retry/predicate` | `(std misc retry)` |
| `return-redis-closure` | `(std ffi redis)`, `(thunderchez redis)` |
| `reverse` | `(std clojure string)` |
| `reverse-video` | `(std misc terminal)` |
| `review` | `(std lens)` |
| `rewrite` | `(std rewrite)` |
| `rewrite-all` | `(std rewrite)` |
| `rewrite-fixed-point` | `(std rewrite)` |
| `rewrite-once` | `(std rewrite)` |
| `rf-append!` | `(std transducer)` |
| `rf-cons` | `(std transducer)` |
| `rf-count` | `(std transducer)` |
| `rf-into-pmap` | `(std transducer)` |
| `rf-into-pset` | `(std transducer)` |
| `rf-into-pvec` | `(std transducer)` |
| `rf-into-vector` | `(std transducer)` |
| `rf-sum` | `(std transducer)` |
| `ring->response` | `(std net ring)` |
| `ring-app` | `(std net ring)` |
| `ring-not-found` | `(std net ring)` |
| `ring-redirect` | `(std net ring)` |
| `ring-response` | `(std net ring)` |
| `ringbuf->list` | `(std misc ringbuf)` |
| `ringbuf-capacity` | `(std misc ringbuf)` |
| `ringbuf-clear!` | `(std misc ringbuf)` |
| `ringbuf-empty?` | `(std misc ringbuf)` |
| `ringbuf-for-each` | `(std misc ringbuf)` |
| `ringbuf-full?` | `(std misc ringbuf)` |
| `ringbuf-peek` | `(std misc ringbuf)` |
| `ringbuf-peek-newest` | `(std misc ringbuf)` |
| `ringbuf-pop!` | `(std misc ringbuf)` |
| `ringbuf-push!` | `(std misc ringbuf)` |
| `ringbuf-ref` | `(std misc ringbuf)` |
| `ringbuf-size` | `(std misc ringbuf)` |
| `ringbuf?` | `(std misc ringbuf)` |
| `rng-next!` | `(std proptest)` |
| `rng-next-float!` | `(std proptest)` |
| `rng?` | `(std proptest)` |
| `root-capability?` | `(std capability)` |
| `round-quotient` | `(std srfi srfi-141)` |
| `round-remainder` | `(std srfi srfi-141)` |
| `round/` | `(std srfi srfi-141)` |
| `route-delete` | `(std net fiber-httpd)` |
| `route-get` | `(std net fiber-httpd)` |
| `route-handler` | `(std net router)` |
| `route-match?` | `(std net router)` |
| `route-middleware` | `(std net router)` |
| `route-not-found` | `(std net router)` |
| `route-param` | `(std net fiber-httpd)` |
| `route-params` | `(std net router)` |
| `route-post` | `(std net fiber-httpd)` |
| `route-put` | `(std net fiber-httpd)` |
| `router-add!` | `(std net fiber-httpd)`, `(std net httpd)`, `(std net router)` |
| `router-add-prefix!` | `(std net httpd)` |
| `router-any!` | `(std net router)` |
| `router-delete!` | `(std net router)` |
| `router-dispatch` | `(std net fiber-httpd)` |
| `router-get!` | `(std net router)` |
| `router-lookup` | `(std net httpd)` |
| `router-match` | `(std net router)` |
| `router-middleware!` | `(std net router)` |
| `router-patch!` | `(std net router)` |
| `router-post!` | `(std net router)` |
| `router-put!` | `(std net router)` |
| `router?` | `(std net router)` |
| `row-check` | `(std typed advanced)` |
| `row-filter` | `(std typed row2)` |
| `row-fold` | `(std typed row2)` |
| `row-keys` | `(std typed row2)` |
| `row-map` | `(std typed row2)` |
| `row-type-fields` | `(std typed row2)` |
| `row-type-rest` | `(std typed row2)` |
| `row-type?` | `(std typed advanced)`, `(std typed row2)` |
| `row-values` | `(std typed row2)` |
| `row?` | `(std typed advanced)` |
| `rows->csv-string` | `(jerboa clojure)`, `(jerboa prelude)`, `(std csv)`, `(std prelude)` |
| `rule-lhs` | `(std rewrite)` |
| `rule-name` | `(std rewrite)` |
| `rule-rhs` | `(std rewrite)` |
| `rule?` | `(std rewrite)` |
| `ruleset-add!` | `(std rewrite)` |
| `ruleset?` | `(std rewrite)` |
| `run` | `(jerboa clojure)`, `(std logic)` |
| `run*` | `(jerboa clojure)`, `(std logic)` |
| `run-all-doctests` | `(std doc)` |
| `run-all-suites` | `(std test framework)` |
| `run-async` | `(std async)` |
| `run-async/workers` | `(std async)` |
| `run-benchmark` | `(std dev benchmark)` |
| `run-benchmark-suite` | `(std dev benchmark)` |
| `run-build-matrix` | `(std build cross)` |
| `run-checks` | `(std health)` |
| `run-cli` | `(std cli multicall)` |
| `run-doctests` | `(std doc)` |
| `run-iouring-loop` | `(std os iouring)` |
| `run-model-test` | `(std proptest)` |
| `run-pipeline` | `(std os fd)` |
| `run-post-eval-hooks` | `(std repl middleware)` |
| `run-pre-eval-hooks` | `(std repl middleware)` |
| `run-process` | `(std misc process)` |
| `run-process/batch` | `(std misc process)` |
| `run-process/exec` | `(std misc process)` |
| `run-reader` | `(std typed monad)` |
| `run-safe` | `(jerboa prelude safe)`, `(std security sandbox)` |
| `run-safe-eval` | `(jerboa prelude safe)`, `(std security sandbox)` |
| `run-staged` | `(std quasiquote-types)` |
| `run-startup-hooks` | `(std repl middleware)` |
| `run-state` | `(std effect state)`, `(std typed monad)` |
| `run-suite` | `(std test framework)` |
| `run-test-suite!` | `(std test)` |
| `run-tests!` | `(std test)` |
| `run-with-handler` | `(std effect)` |
| `run-writer` | `(std typed monad)` |
| `runtime-all-forms` | `(jerboa wasm scheme-runtime)` |
| `runtime-arithmetic-forms` | `(jerboa wasm scheme-runtime)` |
| `runtime-bytevector-forms` | `(jerboa wasm scheme-runtime)` |
| `runtime-closure-forms` | `(jerboa wasm scheme-runtime)` |
| `runtime-closure-type-forms` | `(jerboa wasm scheme-runtime)` |
| `runtime-comparison-forms` | `(jerboa wasm scheme-runtime)` |
| `runtime-conversion-forms` | `(jerboa wasm scheme-runtime)` |
| `runtime-display-forms` | `(jerboa wasm scheme-runtime)` |
| `runtime-equality-forms` | `(jerboa wasm scheme-runtime)` |
| `runtime-io-forms` | `(jerboa wasm scheme-runtime)` |
| `runtime-list-forms` | `(jerboa wasm scheme-runtime)` |
| `runtime-result-forms` | `(jerboa wasm scheme-runtime)` |
| `runtime-string-forms` | `(jerboa wasm scheme-runtime)` |
| `runtime-vector-forms` | `(jerboa wasm scheme-runtime)` |
| `rust-aead-open` | `(std crypto native-rust)` |
| `rust-aead-seal` | `(std crypto native-rust)` |
| `rust-argon2id-hash` | `(std crypto native-rust)` |
| `rust-argon2id-verify` | `(std crypto native-rust)` |
| `rust-chacha20-open` | `(std crypto native-rust)` |
| `rust-chacha20-seal` | `(std crypto native-rust)` |
| `rust-deflate` | `(std compress native-rust)` |
| `rust-gunzip` | `(std compress native-rust)` |
| `rust-gzip` | `(std compress native-rust)` |
| `rust-hmac-sha256` | `(std crypto native-rust)` |
| `rust-hmac-sha256-verify` | `(std crypto native-rust)` |
| `rust-inflate` | `(std compress native-rust)` |
| `rust-last-error` | `(std crypto native-rust)`, `(std regex-native)` |
| `rust-pbkdf2-derive` | `(std crypto native-rust)` |
| `rust-pbkdf2-verify` | `(std crypto native-rust)` |
| `rust-random-bytes` | `(std crypto native-rust)` |
| `rust-scrypt` | `(std crypto native-rust)` |
| `rust-sha1` | `(std crypto native-rust)` |
| `rust-sha256` | `(std crypto native-rust)` |
| `rust-sha384` | `(std crypto native-rust)` |
| `rust-sha512` | `(std crypto native-rust)` |
| `rust-timing-safe-equal?` | `(std crypto native-rust)` |
| `rustls-accept` | `(std net tls-rustls)` |
| `rustls-close` | `(std net tls-rustls)` |
| `rustls-connect` | `(std net tls-rustls)` |
| `rustls-connect-mtls` | `(std net tls-rustls)` |
| `rustls-connect-pinned` | `(std net tls-rustls)` |
| `rustls-flush` | `(std net tls-rustls)` |
| `rustls-get-fd` | `(std net tls-rustls)` |
| `rustls-read` | `(std net tls-rustls)` |
| `rustls-server-ctx-free` | `(std net tls-rustls)` |
| `rustls-server-ctx-new` | `(std net tls-rustls)` |
| `rustls-server-ctx-new-mtls` | `(std net tls-rustls)` |
| `rustls-set-nonblock` | `(std net tls-rustls)` |
| `rustls-write` | `(std net tls-rustls)` |
| `rwlock-read-lock!` | `(std concur util)` |
| `rwlock-read-unlock!` | `(std concur util)` |
| `rwlock-write-lock!` | `(std concur util)` |
| `rwlock-write-unlock!` | `(std concur util)` |
| `rwlock?` | `(std concur util)`, `(std misc rwlock)` |
| `rx` | `(jerboa clojure)`, `(jerboa prelude)`, `(std rx)` |
| `rx:blank-line` | `(std rx patterns)` |
| `rx:camel-case` | `(std rx patterns)` |
| `rx:domain` | `(std rx patterns)` |
| `rx:email` | `(std rx patterns)` |
| `rx:email-domain` | `(std rx patterns)` |
| `rx:email-local` | `(std rx patterns)` |
| `rx:float` | `(std rx patterns)` |
| `rx:hex-byte` | `(std rx patterns)` |
| `rx:hex-color` | `(std rx patterns)` |
| `rx:hex-color-short` | `(std rx patterns)` |
| `rx:hostname` | `(std rx patterns)` |
| `rx:identifier` | `(std rx patterns)` |
| `rx:integer` | `(std rx patterns)` |
| `rx:ipv4` | `(std rx patterns)` |
| `rx:ipv4-octet` | `(std rx patterns)` |
| `rx:iso8601-date` | `(std rx patterns)` |
| `rx:iso8601-datetime` | `(std rx patterns)` |
| `rx:jwt` | `(std rx patterns)` |
| `rx:kebab-case` | `(std rx patterns)` |
| `rx:mac-address` | `(std rx patterns)` |
| `rx:quoted-string` | `(std rx patterns)` |
| `rx:scientific` | `(std rx patterns)` |
| `rx:semver` | `(std rx patterns)` |
| `rx:single-quoted-string` | `(std rx patterns)` |
| `rx:snake-case` | `(std rx patterns)` |
| `rx:time-hms` | `(std rx patterns)` |
| `rx:tld` | `(std rx patterns)` |
| `rx:unsigned-integer` | `(std rx patterns)` |
| `rx:url` | `(std rx patterns)` |
| `rx:url-http` | `(std rx patterns)` |
| `rx:url-https` | `(std rx patterns)` |
| `rx:uuid` | `(std rx patterns)` |
| `rx:word` | `(std rx patterns)` |

### <a name="idx-s"></a>s

| Symbol | Modules |
| --- | --- |
| `SEEK_CUR` | `(std os posix)` |
| `SEEK_END` | `(std os posix)` |
| `SEEK_SET` | `(std os posix)` |
| `SFD_CLOEXEC` | `(std os signalfd)` |
| `SFD_NONBLOCK` | `(std os signalfd)` |
| `SIGABRT` | `(std os posix)`, `(std os signal)` |
| `SIGALRM` | `(std os posix)`, `(std os signal)` |
| `SIGCHLD` | `(std os posix)`, `(std os signal)` |
| `SIGCONT` | `(std os posix)`, `(std os signal)` |
| `SIGFPE` | `(std os posix)`, `(std os signal)` |
| `SIGHUP` | `(std os posix)`, `(std os signal)` |
| `SIGILL` | `(std os posix)`, `(std os signal)` |
| `SIGINT` | `(std os posix)`, `(std os signal)` |
| `SIGIO` | `(std os posix)`, `(std os signal)` |
| `SIGKILL` | `(std os posix)`, `(std os signal)` |
| `SIGPIPE` | `(std os posix)`, `(std os signal)` |
| `SIGPROF` | `(std os posix)`, `(std os signal)` |
| `SIGQUIT` | `(std os posix)`, `(std os signal)` |
| `SIGSEGV` | `(std os posix)`, `(std os signal)` |
| `SIGSTOP` | `(std os posix)`, `(std os signal)` |
| `SIGSYS` | `(std os posix)`, `(std os signal)` |
| `SIGTERM` | `(std os posix)`, `(std os signal)` |
| `SIGTRAP` | `(std os posix)`, `(std os signal)` |
| `SIGTSTP` | `(std os posix)`, `(std os signal)` |
| `SIGTTIN` | `(std os posix)`, `(std os signal)` |
| `SIGTTOU` | `(std os posix)`, `(std os signal)` |
| `SIGURG` | `(std os posix)`, `(std os signal)` |
| `SIGUSR1` | `(std os posix)`, `(std os signal)` |
| `SIGUSR2` | `(std os posix)`, `(std os signal)` |
| `SIGVTALRM` | `(std os posix)`, `(std os signal)` |
| `SIGWINCH` | `(std os posix)`, `(std os signal)` |
| `SIGXCPU` | `(std os posix)`, `(std os signal)` |
| `SIGXFSZ` | `(std os posix)`, `(std os signal)` |
| `SIG_BLOCK` | `(std os posix)` |
| `SIG_SETMASK` | `(std os posix)` |
| `SIG_UNBLOCK` | `(std os posix)` |
| `SQLITE_BLOB` | `(std db sqlite-native)`, `(std db sqlite)` |
| `SQLITE_DONE` | `(std db sqlite-native)`, `(std db sqlite)` |
| `SQLITE_FLOAT` | `(std db sqlite-native)`, `(std db sqlite)` |
| `SQLITE_INTEGER` | `(std db sqlite-native)`, `(std db sqlite)` |
| `SQLITE_NULL` | `(std db sqlite-native)`, `(std db sqlite)` |
| `SQLITE_OK` | `(std db sqlite)` |
| `SQLITE_ROW` | `(std db sqlite-native)`, `(std db sqlite)` |
| `SQLITE_TEXT` | `(std db sqlite-native)`, `(std db sqlite)` |
| `SSH_DISCONNECT_AUTH_CANCELLED_BY_USER` | `(std net ssh wire)` |
| `SSH_DISCONNECT_BY_APPLICATION` | `(std net ssh wire)` |
| `SSH_DISCONNECT_COMPRESSION_ERROR` | `(std net ssh wire)` |
| `SSH_DISCONNECT_CONNECTION_LOST` | `(std net ssh wire)` |
| `SSH_DISCONNECT_HOST_AUTHENTICATION_FAILED` | `(std net ssh wire)` |
| `SSH_DISCONNECT_HOST_KEY_NOT_VERIFIABLE` | `(std net ssh wire)` |
| `SSH_DISCONNECT_HOST_NOT_ALLOWED_TO_CONNECT` | `(std net ssh wire)` |
| `SSH_DISCONNECT_ILLEGAL_USER_NAME` | `(std net ssh wire)` |
| `SSH_DISCONNECT_KEY_EXCHANGE_FAILED` | `(std net ssh wire)` |
| `SSH_DISCONNECT_MAC_ERROR` | `(std net ssh wire)` |
| `SSH_DISCONNECT_NO_MORE_AUTH_METHODS_AVAILABLE` | `(std net ssh wire)` |
| `SSH_DISCONNECT_PROTOCOL_ERROR` | `(std net ssh wire)` |
| `SSH_DISCONNECT_PROTOCOL_VERSION_NOT_SUPPORTED` | `(std net ssh wire)` |
| `SSH_DISCONNECT_SERVICE_NOT_AVAILABLE` | `(std net ssh wire)` |
| `SSH_DISCONNECT_TOO_MANY_CONNECTIONS` | `(std net ssh wire)` |
| `SSH_EXTENDED_DATA_STDERR` | `(std net ssh wire)` |
| `SSH_FXF_APPEND` | `(std net ssh sftp)`, `(std net ssh)` |
| `SSH_FXF_CREAT` | `(std net ssh sftp)`, `(std net ssh)` |
| `SSH_FXF_EXCL` | `(std net ssh sftp)`, `(std net ssh)` |
| `SSH_FXF_READ` | `(std net ssh sftp)`, `(std net ssh)` |
| `SSH_FXF_TRUNC` | `(std net ssh sftp)`, `(std net ssh)` |
| `SSH_FXF_WRITE` | `(std net ssh sftp)`, `(std net ssh)` |
| `SSH_MSG_CHANNEL_CLOSE` | `(std net ssh wire)` |
| `SSH_MSG_CHANNEL_DATA` | `(std net ssh wire)` |
| `SSH_MSG_CHANNEL_EOF` | `(std net ssh wire)` |
| `SSH_MSG_CHANNEL_EXTENDED_DATA` | `(std net ssh wire)` |
| `SSH_MSG_CHANNEL_FAILURE` | `(std net ssh wire)` |
| `SSH_MSG_CHANNEL_OPEN` | `(std net ssh wire)` |
| `SSH_MSG_CHANNEL_OPEN_CONFIRMATION` | `(std net ssh wire)` |
| `SSH_MSG_CHANNEL_OPEN_FAILURE` | `(std net ssh wire)` |
| `SSH_MSG_CHANNEL_REQUEST` | `(std net ssh wire)` |
| `SSH_MSG_CHANNEL_SUCCESS` | `(std net ssh wire)` |
| `SSH_MSG_CHANNEL_WINDOW_ADJUST` | `(std net ssh wire)` |
| `SSH_MSG_DEBUG` | `(std net ssh wire)` |
| `SSH_MSG_DISCONNECT` | `(std net ssh wire)` |
| `SSH_MSG_GLOBAL_REQUEST` | `(std net ssh wire)` |
| `SSH_MSG_IGNORE` | `(std net ssh wire)` |
| `SSH_MSG_KEXINIT` | `(std net ssh wire)` |
| `SSH_MSG_KEX_ECDH_INIT` | `(std net ssh wire)` |
| `SSH_MSG_KEX_ECDH_REPLY` | `(std net ssh wire)` |
| `SSH_MSG_NEWKEYS` | `(std net ssh wire)` |
| `SSH_MSG_REQUEST_FAILURE` | `(std net ssh wire)` |
| `SSH_MSG_REQUEST_SUCCESS` | `(std net ssh wire)` |
| `SSH_MSG_SERVICE_ACCEPT` | `(std net ssh wire)` |
| `SSH_MSG_SERVICE_REQUEST` | `(std net ssh wire)` |
| `SSH_MSG_UNIMPLEMENTED` | `(std net ssh wire)` |
| `SSH_MSG_USERAUTH_BANNER` | `(std net ssh wire)` |
| `SSH_MSG_USERAUTH_FAILURE` | `(std net ssh wire)` |
| `SSH_MSG_USERAUTH_INFO_REQUEST` | `(std net ssh wire)` |
| `SSH_MSG_USERAUTH_INFO_RESPONSE` | `(std net ssh wire)` |
| `SSH_MSG_USERAUTH_REQUEST` | `(std net ssh wire)` |
| `SSH_MSG_USERAUTH_SUCCESS` | `(std net ssh wire)` |
| `STDERR_FILENO` | `(std os fd)` |
| `STDIN_FILENO` | `(std os fd)` |
| `STDOUT_FILENO` | `(std os fd)` |
| `STRING-HEADER-PAYLOAD` | `(jerboa wasm values)` |
| `SYMBOL-HEADER-PAYLOAD` | `(jerboa wasm values)` |
| `Some-val` | `(std typed hkt)` |
| `Some?` | `(std typed hkt)` |
| `s-and` | `(jerboa clojure)`, `(std spec)` |
| `s-assert` | `(jerboa clojure)`, `(std spec)` |
| `s-cat` | `(jerboa clojure)`, `(std spec)` |
| `s-check-fn` | `(jerboa clojure)`, `(std spec)` |
| `s-coll-of` | `(jerboa clojure)`, `(std spec)` |
| `s-conform` | `(jerboa clojure)`, `(std spec)` |
| `s-def` | `(jerboa clojure)`, `(std spec)` |
| `s-double-in` | `(jerboa clojure)`, `(std spec)` |
| `s-enum` | `(jerboa clojure)`, `(std spec)` |
| `s-exercise` | `(jerboa clojure)`, `(std spec)` |
| `s-explain` | `(jerboa clojure)`, `(std spec)` |
| `s-explain-str` | `(jerboa clojure)`, `(std spec)` |
| `s-fdef` | `(jerboa clojure)`, `(std spec)` |
| `s-get-spec` | `(jerboa clojure)`, `(std spec)` |
| `s-int-in` | `(jerboa clojure)`, `(std spec)` |
| `s-keys` | `(jerboa clojure)`, `(std spec)` |
| `s-keys-opt` | `(jerboa clojure)`, `(std spec)` |
| `s-map-of` | `(jerboa clojure)`, `(std spec)` |
| `s-nilable` | `(jerboa clojure)`, `(std spec)` |
| `s-or` | `(jerboa clojure)`, `(std spec)` |
| `s-pred` | `(jerboa clojure)`, `(std spec)` |
| `s-tuple` | `(jerboa clojure)`, `(std spec)` |
| `s-valid?` | `(jerboa clojure)`, `(std spec)` |
| `s16` | `(std binary)` |
| `s16vector` | `(std srfi srfi-160)` |
| `s16vector->list` | `(std srfi srfi-160)` |
| `s16vector-append` | `(std srfi srfi-160)` |
| `s16vector-copy` | `(std srfi srfi-160)` |
| `s16vector-length` | `(std srfi srfi-160)` |
| `s16vector-ref` | `(std srfi srfi-160)` |
| `s16vector-set!` | `(std srfi srfi-160)` |
| `s16vector?` | `(std srfi srfi-160)` |
| `s3-delete-object` | `(std net s3)` |
| `s3-get-object` | `(std net s3)` |
| `s3-head-object` | `(std net s3)` |
| `s3-list-bucket` | `(std net s3)` |
| `s3-put-object` | `(std net s3)` |
| `s32` | `(std binary)` |
| `s32vector` | `(std srfi srfi-160)` |
| `s32vector->list` | `(std srfi srfi-160)` |
| `s32vector-append` | `(std srfi srfi-160)` |
| `s32vector-copy` | `(std srfi srfi-160)` |
| `s32vector-length` | `(std srfi srfi-160)` |
| `s32vector-ref` | `(std srfi srfi-160)` |
| `s32vector-set!` | `(std srfi srfi-160)` |
| `s32vector?` | `(std srfi srfi-160)` |
| `s64` | `(std binary)` |
| `s64vector` | `(std srfi srfi-160)` |
| `s64vector->list` | `(std srfi srfi-160)` |
| `s64vector-append` | `(std srfi srfi-160)` |
| `s64vector-copy` | `(std srfi srfi-160)` |
| `s64vector-length` | `(std srfi srfi-160)` |
| `s64vector-ref` | `(std srfi srfi-160)` |
| `s64vector-set!` | `(std srfi srfi-160)` |
| `s64vector?` | `(std srfi srfi-160)` |
| `s8` | `(std binary)` |
| `s8vector` | `(std srfi srfi-160)` |
| `s8vector->list` | `(std srfi srfi-160)` |
| `s8vector-append` | `(std srfi srfi-160)` |
| `s8vector-copy` | `(std srfi srfi-160)` |
| `s8vector-length` | `(std srfi srfi-160)` |
| `s8vector-ref` | `(std srfi srfi-160)` |
| `s8vector-set!` | `(std srfi srfi-160)` |
| `s8vector?` | `(std srfi srfi-160)` |
| `s:any` | `(std schema)` |
| `s:boolean` | `(std schema)` |
| `s:enum` | `(std schema)` |
| `s:hash` | `(std schema)` |
| `s:integer` | `(std schema)` |
| `s:keys` | `(std schema)` |
| `s:list` | `(std schema)` |
| `s:max` | `(std schema)` |
| `s:max-length` | `(std schema)` |
| `s:min` | `(std schema)` |
| `s:min-length` | `(std schema)` |
| `s:null` | `(std schema)` |
| `s:number` | `(std schema)` |
| `s:optional` | `(std schema)` |
| `s:pattern` | `(std schema)` |
| `s:required` | `(std schema)` |
| `s:string` | `(std schema)` |
| `s:union` | `(std schema)` |
| `safe-bindings` | `(std security restrict)` |
| `safe-call-with-input-file` | `(std safe)` |
| `safe-call-with-output-file` | `(std safe)` |
| `safe-delete-file` | `(std security taint)` |
| `safe-eprintf` | `(std format)` |
| `safe-error-response` | `(std security errors)` |
| `safe-error-response-message` | `(std security errors)` |
| `safe-error-response-reference` | `(std security errors)` |
| `safe-error-response-status` | `(std security errors)` |
| `safe-error-response?` | `(std security errors)` |
| `safe-fasl-read` | `(jerboa prelude safe)`, `(std safe-fasl)` |
| `safe-fasl-read-bytevector` | `(jerboa prelude safe)`, `(std safe-fasl)` |
| `safe-fasl-write` | `(jerboa prelude safe)`, `(std safe-fasl)` |
| `safe-fasl-write-bytevector` | `(jerboa prelude safe)`, `(std safe-fasl)` |
| `safe-fprintf` | `(std format)` |
| `safe-gunzip-bytevector` | `(std compress zlib)` |
| `safe-inflate-bytevector` | `(std compress zlib)` |
| `safe-open-input-file` | `(std safe)`, `(std security taint)` |
| `safe-open-output-file` | `(std safe)`, `(std security taint)` |
| `safe-path-join` | `(std security sanitize)` |
| `safe-printf` | `(std format)` |
| `safe-read-json` | `(std safe)` |
| `safe-record-type?` | `(std safe-fasl)` |
| `safe-sqlite-bind` | `(std safe)` |
| `safe-sqlite-close` | `(std safe)` |
| `safe-sqlite-exec` | `(std safe)` |
| `safe-sqlite-execute` | `(std safe)` |
| `safe-sqlite-finalize` | `(std safe)` |
| `safe-sqlite-open` | `(std safe)` |
| `safe-sqlite-prepare` | `(std safe)` |
| `safe-sqlite-query` | `(std safe)` |
| `safe-sqlite-step` | `(std safe)` |
| `safe-string->json` | `(std safe)` |
| `safe-system` | `(std security taint)` |
| `safe-tcp-accept` | `(std safe)` |
| `safe-tcp-close` | `(std safe)` |
| `safe-tcp-connect` | `(std safe)` |
| `safe-tcp-listen` | `(std safe)` |
| `safe-tcp-read` | `(std safe)` |
| `safe-tcp-write` | `(std safe)` |
| `safe-tcp-write-string` | `(std safe)` |
| `safe-yaml-load-string` | `(std text yaml)` |
| `sample` | `(std effect multishot)` |
| `sample-results` | `(std dev profile)` |
| `sample-start!` | `(std dev profile)` |
| `sample-stop!` | `(std dev profile)` |
| `sandbox-allowed?` | `(std capability sandbox)` |
| `sandbox-available?` | `(std os sandbox)` |
| `sandbox-call` | `(jerboa embed)` |
| `sandbox-config-capabilities` | `(jerboa prelude safe)`, `(std security sandbox)` |
| `sandbox-config-capsicum` | `(std security sandbox)` |
| `sandbox-config-landlock` | `(jerboa prelude safe)`, `(std security sandbox)` |
| `sandbox-config-max-output-size` | `(std security sandbox)` |
| `sandbox-config-seatbelt` | `(std security sandbox)` |
| `sandbox-config-seccomp` | `(jerboa prelude safe)`, `(std security sandbox)` |
| `sandbox-config-timeout` | `(jerboa prelude safe)`, `(std security sandbox)` |
| `sandbox-config?` | `(jerboa embed)`, `(jerboa prelude safe)`, `(std security sandbox)` |
| `sandbox-define!` | `(jerboa embed)` |
| `sandbox-environment` | `(jerboa embed)` |
| `sandbox-error-detail` | `(jerboa prelude safe)`, `(std security sandbox)` |
| `sandbox-error-irritants` | `(jerboa embed)` |
| `sandbox-error-message` | `(jerboa embed)` |
| `sandbox-error-phase` | `(jerboa prelude safe)`, `(std security sandbox)` |
| `sandbox-error-reason` | `(std capability)` |
| `sandbox-error?` | `(jerboa embed)`, `(jerboa prelude safe)`, `(std capability)`, `(std security sandbox)` |
| `sandbox-eval` | `(jerboa embed)`, `(std capability sandbox)` |
| `sandbox-eval-string` | `(jerboa embed)` |
| `sandbox-import!` | `(jerboa embed)` |
| `sandbox-load` | `(std capability sandbox)` |
| `sandbox-policy?` | `(std capability sandbox)` |
| `sandbox-ref` | `(jerboa embed)` |
| `sandbox-reset!` | `(jerboa embed)` |
| `sandbox-run` | `(std capability sandbox)`, `(std os sandbox)` |
| `sandbox-run/capsicum` | `(std os sandbox)` |
| `sandbox-run/command` | `(std os sandbox)` |
| `sandbox-run/pledge` | `(std os sandbox)` |
| `sandbox-run/profile` | `(std os sandbox)` |
| `sandbox-run/timeout` | `(std capability sandbox)` |
| `sandbox-violation-capability` | `(std capability sandbox)` |
| `sandbox-violation-context` | `(std capability sandbox)` |
| `sandbox-violation?` | `(std capability sandbox)` |
| `sandbox?` | `(jerboa embed)`, `(std capability sandbox)` |
| `sanitize-header-value` | `(std security sanitize)` |
| `sanitize-html` | `(std security sanitize)` |
| `sanitize-html-attribute` | `(std security sanitize)` |
| `sanitize-path` | `(std security sanitize)` |
| `sanitize-url` | `(std security sanitize)` |
| `sanitize-url-attribute` | `(std security sanitize)` |
| `sasl-complete?` | `(std net sasl)` |
| `sasl-plain` | `(std net sasl)` |
| `sasl-plain-encode` | `(std net sasl)` |
| `sasl-step` | `(std net sasl)` |
| `satisfies-refinement?` | `(std typed refine)` |
| `satisfies?` | `(std protocol)` |
| `save-bytevector` | `(thunderchez thunder-utils)` |
| `save-config` | `(std config)` |
| `save-image` | `(std persist image)` |
| `save-profile!` | `(std dev pgo)` |
| `save-world` | `(std image)` |
| `save-world-sexp` | `(std image)` |
| `sbom->sexp` | `(std build sbom)` |
| `sbom-add-build-info!` | `(std build sbom)` |
| `sbom-add-component!` | `(std build sbom)` |
| `sbom-build-info` | `(std build sbom)` |
| `sbom-components` | `(std build sbom)` |
| `sbom-find-component` | `(std build sbom)` |
| `sbom-project` | `(std build sbom)` |
| `sbom-read` | `(std build sbom)` |
| `sbom-timestamp` | `(std build sbom)` |
| `sbom-version` | `(std build sbom)` |
| `sbom-write` | `(std build sbom)` |
| `sbom?` | `(std build sbom)` |
| `scancode->keycode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `scheduler-add!` | `(std control coroutine)` |
| `scheduler-run!` | `(std control coroutine)`, `(std sched)` |
| `scheduler-running?` | `(std sched)` |
| `scheduler-spawn!` | `(std sched)` |
| `scheduler-start!` | `(std actor scheduler)`, `(std actor)` |
| `scheduler-stop!` | `(std actor scheduler)`, `(std actor)`, `(std sched)` |
| `scheduler-submit!` | `(std actor scheduler)`, `(std actor)` |
| `scheduler-task-count` | `(std sched)` |
| `scheduler-thread-count` | `(std sched)` |
| `scheduler-worker-count` | `(std actor scheduler)`, `(std actor)` |
| `scheduler-yield` | `(std sched)` |
| `scheduler?` | `(std actor scheduler)`, `(std actor)`, `(std sched)` |
| `schema-errors` | `(std schema)` |
| `schema-type` | `(std schema)` |
| `schema-type-array` | `(std text json-schema)` |
| `schema-type-boolean` | `(std text json-schema)` |
| `schema-type-null` | `(std text json-schema)` |
| `schema-type-number` | `(std text json-schema)` |
| `schema-type-object` | `(std text json-schema)` |
| `schema-type-string` | `(std text json-schema)` |
| `schema-valid?` | `(std schema)`, `(std text json-schema)` |
| `schema-validate` | `(std schema)` |
| `schema?` | `(std schema)` |
| `scheme->python` | `(std python)` |
| `scheme->wasm-type` | `(jerboa wasm codegen)` |
| `scheme->yaml` | `(std text yaml)` |
| `scheme-list->python` | `(std python)` |
| `scope-spawn` | `(jerboa prelude safe)`, `(std concur structured)` |
| `scope-spawn-named` | `(jerboa prelude safe)`, `(std concur structured)` |
| `scoped-amb` | `(std effect scoped)` |
| `scoped-collect` | `(std effect scoped)` |
| `scoped-perform` | `(std effect scoped)` |
| `scoped-reader` | `(std effect scoped)` |
| `scoped-state` | `(std effect scoped)` |
| `scrypt` | `(std crypto kdf)` |
| `sdl-add-event-watch` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-add-hint-callback` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-add-timer` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-alloc-format` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-alloc-palette` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-alloc-rw` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-alpha-opaque` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-alpha-transparent` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-arrayorder` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-atomic-add` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-atomic-cas` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-atomic-cas-ptr` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-atomic-get` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-atomic-get-ptr` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-atomic-lock` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-atomic-set` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-atomic-set-ptr` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-atomic-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-atomic-try-lock` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-atomic-unlock` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-audio-callback-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-audio-cvt-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-audio-device-id-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-audio-format-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-audio-init` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-audio-quit` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-audio-spec-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-audio-status` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-bitmaporder` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-bitsperpixel%` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-blend-mode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-blend-mode-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-blit-map-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-bool-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-build-audio-cvt` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-button` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-button-mask` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-button-ref` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-calculate-gamma-ramp` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-capture-mouse` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-clear-error` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-clear-hints` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-close-audio` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-close-audio-device` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-color-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-common-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-cond-broadcast` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-cond-signal` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-cond-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-cond-wait` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-cond-wait-timeout` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-controller-axis-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-controller-axis-invalid` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-controller-bind-type` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-controller-bind-type-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-controller-button-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-controller-device-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-convert-audio` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-convert-pixels` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-convert-surface` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-convert-surface-format` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-create-color-cursor` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-create-cond` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-create-cursor` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-create-mutex` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-create-renderer` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-create-rgb-surface` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-create-rgb-surface-from` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-create-rgb-surface-with-format` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-create-rgb-surface-with-format-from` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-create-semaphore` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-create-software-renderer` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-create-system-cursor` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-create-texture` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-create-texture-from-surface` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-create-thread` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-create-window` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-create-window-and-renderer` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-create-window-from` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-cursor-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-define-pixelformat` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-del-event-watch` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-del-hint-callback` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-delay` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-destroy-cond` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-destroy-mutex` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-destroy-renderer` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-destroy-semaphore` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-destroy-texture` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-destroy-window` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-detach-thread` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-disable-screen-saver` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-display-mode-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-dollar-gesture-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-drop-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-enable-screen-saver` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-enclose-points` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-error` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-errorcode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-errorcode-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-event-filter-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-event-keyboard-keysym-mod` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-event-keyboard-keysym-sym` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-event-mouse-button` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-event-state` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-event-type` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-event-type-ref` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-eventaction` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-fill-rect` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-fill-rects` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-filter-events` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-finger-id-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-finger-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-flush-event` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-flush-events` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-fourcc` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-fourcc/char` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-free-cursor` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-free-format` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-free-garbage` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-free-garbage-set-func` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-free-palette` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-free-rw` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-free-surface` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-free-wav` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-add-mapping` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-add-mappings-from-rw` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-axis-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-close` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-event-state` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-get-attached` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-get-axis` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-get-axis-from-string` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-get-bind-for-axis` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-get-bind-for-button` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-get-button` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-get-button-from-string` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-get-joystick` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-get-string-for-axis` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-get-string-for-button` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-mapping` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-name` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-name-for-index` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-open` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-game-controller-update` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gesture-id-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-assertion-handler` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-assertion-report` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-audio-device-name` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-audio-device-status` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-audio-driver` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-audio-status` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-base-path` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-clip-rect` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-clipboard-text` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-closest-display-mode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-color-key` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-cpu-cache-line-size` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-cpu-count` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-current-audio-driver` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-current-display-mode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-current-video-driver` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-cursor` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-default-assertion-handler` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-default-cursor` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-desktop-display-mode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-display-bounds` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-display-mode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-display-name` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-display-usable-bounds` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-error` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-event-filter` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-global-mouse-state` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-hint` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-hint-boolean` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-key-from-name` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-key-from-scancode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-key-name` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-keyboard-focus` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-keyboard-state` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-mod-state` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-mouse-focus` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-mouse-state` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-num-audio-devices` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-num-audio-drivers` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-num-display-modes` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-num-render-drivers` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-num-touch-devices` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-num-touch-fingers` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-num-video-displays` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-num-video-drivers` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-performance-counter` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-performance-frequency` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-pixel-format-name` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-pref-path` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-relative-mouse-mode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-relative-mouse-state` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-render-draw-blend-mode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-render-draw-color` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-render-driver-info` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-render-target` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-renderer` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-renderer-info` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-renderer-output-size` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-revision` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-revision-number` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-rgb` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-rgba` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-scancode-from-key` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-scancode-from-name` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-scancode-name` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-surface-alpha-mod` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-surface-blend-mode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-surface-color-mod` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-system-ram` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-texture-alpha-mod` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-texture-blend-mode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-texture-color-mod` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-thread-id` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-thread-name` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-ticks` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-touch-device` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-touch-finger` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-version` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-video-driver` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-window-borders-size` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-window-brightness` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-window-data` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-window-display-index` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-window-display-mode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-window-flags` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-window-from-id` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-window-gamma-ramp` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-window-grab` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-window-id` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-window-maximum-size` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-window-minimum-size` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-window-opacity` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-window-pixel-format` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-window-position` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-window-size` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-window-surface` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-get-window-title` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-attr` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-attr-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-bind-texture` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-context-flag` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-context-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-create-context` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-delete-context` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-extension-supported` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-get-attribute` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-get-current-context` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-get-current-window` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-get-drawable-size` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-get-proc-address` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-get-swap-interval` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-load-library` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-make-current` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-profile` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-reset-attributes` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-set-attribute` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-set-swap-interval` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-swap-window` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-unbind-texture` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-gl-unload-library` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-guard-pointer` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-guardian` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-has-alti-vec` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-has-avx` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-has-clipboard-text` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-has-event` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-has-events` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-has-intersection` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-has-mmx` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-has-rdtsc` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-has-screen-keyboard-support` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-has-ss-e2` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-has-ss-e3` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-has-ss-e41` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-has-ss-e42` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-has-sse` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-has3-d-now` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-hide-window` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-hint-priority` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-iconv-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-image-library-init` | `(std ffi sdl2 image)`, `(thunderchez sdl2 image)` |
| `sdl-init` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-init-sub-system` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-initialization` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-initialization-everything` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-intersect-rect` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-intersect-rect-and-line` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-is-game-controller` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-is-screen-keyboard-shown` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-is-screen-saver-enabled` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-is-text-input-active` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-ispixelformat-fourcc` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joy-axis-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joy-ball-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joy-button-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joy-device-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joy-hat-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-close` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-event-state` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-get-attached` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-get-axis` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-get-ball` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-get-button` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-get-device-guid` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-get-guid` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-get-guid-from-string` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-get-guid-string` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-get-hat` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-guid-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-id-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-instance-id` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-name` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-name-for-index` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-num-axes` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-num-balls` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-num-buttons` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-num-hats` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-open` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-joystick-update` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-keyboard-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-keycode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-keycode-decode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-keycode-ref` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-keycode-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-keymod-decode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-keymod-ref` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-keymod-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-keysym-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-let-ref-call` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-library-init` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-load-bmp` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-load-bmp-rw` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-load-dollar-templates` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-load-wav-rw` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-lock-audio` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-lock-audio-device` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-lock-mutex` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-lock-surface` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-lock-texture` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-lower-blit` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-lower-blit-scaled` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-main` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-map-rgb` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-map-rgba` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-masks-to-pixel-format-enum` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-maximize-window` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-message-box` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-message-box-button` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-message-box-button-data-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-message-box-color-scheme-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-message-box-color-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-message-box-color-type-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-message-box-data-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-minimize-window` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-mix-audio` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-mix-audio-format` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-mixer-library-init` | `(std ffi sdl2 mixer)`, `(thunderchez sdl2 mixer)` |
| `sdl-mouse-button-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-mouse-motion-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-mouse-wheel-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-multi-gesture-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-mutex-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-net-add-socket` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-alloc-packet` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-alloc-packetv` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-alloc-socket-set` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-check-sockets` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-del-socket` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-free-packet` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-free-packetv` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-free-socket-set` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-generic-socket` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-generic-socket-t` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-get-error` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-get-local-addresses` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-init` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-library-init` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-linked-version` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-quit` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-resize-packet` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-resolve-host` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-resolve-ip` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-set-error` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-socket-set-t` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-tcp-accept` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-tcp-add-socket` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-tcp-close` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-tcp-del-socket` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-tcp-get-peer-address` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-tcp-open` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-tcp-recv` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-tcp-send` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-udp-add-socket` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-udp-bind` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-udp-close` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-udp-del-socket` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-udp-get-peer-address` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-udp-open` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-udp-recv` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-udp-recvv` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-udp-send` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-udp-sendv` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-udp-set-packet-loss` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-udp-unbind` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-net-version-t` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `sdl-num-joysticks` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-open-audio` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-open-audio-device` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-packedlayout` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-packedorder` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-palette-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-pause-audio` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-pause-audio-device` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-peep-events` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-pixel-format-enum-to-masks` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-pixel-format-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-pixelflag%` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-pixelformat` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-pixellayout` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-pixelorder%` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-pixeltype` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-pixeltype%` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-point-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-poll-event` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-pump-events` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-push-event` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-query-texture` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-quit` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-quit-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-quit-sub-system` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-raise-window` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-read-b-e16` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-read-b-e32` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-read-b-e64` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-read-l-e16` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-read-l-e32` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-read-l-e64` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-read-u8` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-record-gesture` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-rect-empty` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-rect-equals` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-rect-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-register-events` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-remove-timer` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-clear` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-copy` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-copy-ex` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-draw-line` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-draw-lines` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-draw-point` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-draw-points` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-draw-rect` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-draw-rects` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-fill-rect` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-fill-rects` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-get-clip-rect` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-get-integer-scale` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-get-logical-size` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-get-scale` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-get-viewport` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-present` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-read-pixels` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-set-clip-rect` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-set-integer-scale` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-set-logical-size` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-set-scale` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-set-viewport` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-render-target-supported` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-renderer-flags` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-renderer-flip` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-renderer-info-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-renderer-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-report-assertion` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-reset-assertion-report` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-restore-window` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-rw-from-const-mem` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-rw-from-file` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-rw-from-fp` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-rw-from-mem` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-rw-ops-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-save-all-dollar-templates` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-save-bmp` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-save-bmp-rw` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-save-dollar-template` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-scancode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-scancode-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-sem-post` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-sem-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-sem-try-wait` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-sem-value` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-sem-wait` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-sem-wait-timeout` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-assertion-handler` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-clip-rect` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-clipboard-text` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-color-key` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-cursor` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-error` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-event-filter` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-hint` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-hint-with-priority` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-main-ready` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-mod-state` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-palette-colors` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-pixel-format-palette` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-relative-mouse-mode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-render-draw-blend-mode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-render-draw-color` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-render-target` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-surface-alpha-mod` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-surface-blend-mode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-surface-color-mod` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-surface-palette` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-surface-rle` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-text-input-rect` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-texture-alpha-mod` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-texture-blend-mode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-texture-color-mod` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-thread-priority` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-window-bordered` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-window-brightness` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-window-data` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-window-display-mode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-window-fullscreen` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-window-gamma-ramp` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-window-grab` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-window-icon` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-window-input-focus` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-window-maximum-size` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-window-minimum-size` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-window-modal-for` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-window-opacity` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-window-position` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-window-resizable` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-window-size` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-set-window-title` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-shim-ttf-init` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `sdl-show-cursor` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-show-message-box` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-show-simple-message-box` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-show-window` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-soft-stretch` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-spin-lock-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-start-text-input` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-stop-text-input` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-surface-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-swap-float` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-swap16` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-swap32` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-swap64` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-sys-wm-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-sys-wm-msg` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-system-cursor` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-text-input-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-texteditingevent-text-size` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-textinputevent-text-size` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-texture-access` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-texture-modulate` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-texture-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-thread-function-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-thread-id` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-thread-id-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-thread-priority` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-thread-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-timer-callback-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-timer-id-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-tls-create` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-tls-get` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-tls-set` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-tlsid-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-touch-finger-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-touch-id-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-try-lock-mutex` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-ttf-library-init` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `sdl-union-rect` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-unlock-audio` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-unlock-audio-device` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-unlock-mutex` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-unlock-surface` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-unlock-texture` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-update-texture` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-update-window-surface` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-update-window-surface-rects` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-update-yuv-texture` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-upper-blit` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-upper-blit-scaled` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-user-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-version-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-video-init` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-video-quit` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-wait-event` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-wait-event-timeout` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-wait-thread` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-warp-mouse-global` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-warp-mouse-in-window` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-was-init` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-window-event-enum` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-window-event-enum-ref` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-window-event-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-window-flags` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-window-flags-decode` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-window-flags-flags` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-window-flags-ref` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-window-flags-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-window-pos-centered` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-window-pos-centered?` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-window-pos-undefined` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-window-pos-undefined?` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sdl-window-t` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `seal-method!` | `(std dev devirt)` |
| `sealed-hierarchy-members` | `(std match2)` |
| `sealed-hierarchy?` | `(std match2)` |
| `seatbelt-available?` | `(std security seatbelt)` |
| `seatbelt-compute-only-profile` | `(std security seatbelt)` |
| `seatbelt-install!` | `(std security seatbelt)` |
| `seatbelt-install-profile!` | `(std security seatbelt)` |
| `seatbelt-no-network-profile` | `(std security seatbelt)` |
| `seatbelt-no-write-profile` | `(std security seatbelt)` |
| `seatbelt-read-only-profile` | `(std security seatbelt)` |
| `seccomp-available?` | `(std os seccomp)`, `(std security seccomp)` |
| `seccomp-errno` | `(std security seccomp)` |
| `seccomp-error-reason` | `(std os seccomp)` |
| `seccomp-error?` | `(std os seccomp)` |
| `seccomp-filter-allowed-syscalls` | `(std security seccomp)` |
| `seccomp-filter-default-action` | `(std security seccomp)` |
| `seccomp-filter?` | `(std security seccomp)` |
| `seccomp-install!` | `(std security seccomp)` |
| `seccomp-kill` | `(std security seccomp)` |
| `seccomp-lock!` | `(std os seccomp)` |
| `seccomp-lock-strict!` | `(std os seccomp)` |
| `seccomp-log` | `(std security seccomp)` |
| `seccomp-trap` | `(std security seccomp)` |
| `second` | `(std srfi srfi-1)` |
| `seconds->duration` | `(std time)` |
| `seconds->time` | `(std srfi srfi-19)` |
| `secret-consumed?` | `(std security secret)` |
| `secret-peek` | `(std security secret)` |
| `secret-use` | `(std security secret)` |
| `secret?` | `(std security secret)` |
| `secure-alloc` | `(std crypto secure-mem)` |
| `secure-free` | `(std crypto secure-mem)` |
| `secure-random-fill` | `(std crypto secure-mem)` |
| `secure-region-pointer` | `(std crypto secure-mem)` |
| `secure-region-size` | `(std crypto secure-mem)` |
| `secure-region?` | `(std crypto secure-mem)` |
| `secure-wipe` | `(std crypto secure-mem)` |
| `security-level-name` | `(std security flow)` |
| `security-level<=?` | `(std security flow)` |
| `security-level?` | `(std security flow)` |
| `security-metrics?` | `(std security metrics)` |
| `select` | `(std db query-compile)`, `(std event)`, `(std query)`, `(std select)`, ... (+1) |
| `select-first` | `(std specter)` |
| `select-keys` | `(jerboa clojure)`, `(std clojure)` |
| `select-one` | `(std specter)` |
| `self` | `(std actor core)`, `(std actor)` |
| `semaphore-acquire!` | `(std concur util)` |
| `semaphore-count` | `(std concur util)` |
| `semaphore-release!` | `(std concur util)` |
| `semaphore-try-acquire!` | `(std concur util)` |
| `semaphore?` | `(std concur util)` |
| `send` | `(std actor core)`, `(std actor)`, `(std agent)`, `(std select)` |
| `send-email` | `(std net smtp)` |
| `send-off` | `(std agent)` |
| `seq` | `(jerboa clojure)`, `(std clojure)` |
| `seq->list` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-butlast` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-concat` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-count` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-distinct` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-drop` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-drop-while` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-empty?` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-every?` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-filter` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-first` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-flatten` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-frequencies` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-group-by` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-interleave` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-interpose` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-into` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-keep` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-last` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-map` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-map-indexed` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-mapcat` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-nth` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-partition` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-partition-all` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-partition-by` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-reduce` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-remove` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-rest` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-reverse` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-second` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-some` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-sort` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-sort-by` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-take` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-take-while` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-zip` | `(jerboa clojure)`, `(std clojure seq)` |
| `seq-zipmap` | `(jerboa clojure)`, `(std clojure seq)` |
| `seqable?` | `(jerboa clojure)`, `(std clojure seq)` |
| `sequence` | `(std seq)`, `(std transducer)` |
| `sequence-results` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `serialization-error?` | `(std error conditions)` |
| `serialize-message` | `(std actor distributed)` |
| `serialize-size-exceeded-actual` | `(std error conditions)` |
| `serialize-size-exceeded-limit` | `(std error conditions)` |
| `serialize-size-exceeded?` | `(std error conditions)` |
| `serialize-value` | `(std actor checkpoint)` |
| `service-config-env-dir` | `(std service config)` |
| `service-config-file-limit` | `(std service config)` |
| `service-config-group` | `(std service config)` |
| `service-config-memory-limit` | `(std service config)` |
| `service-config-nofile-limit` | `(std service config)` |
| `service-config-nproc-limit` | `(std service config)` |
| `service-config-sandbox-exec` | `(std service config)` |
| `service-config-sandbox-read` | `(std service config)` |
| `service-config-sandbox-write` | `(std service config)` |
| `service-config-seccomp?` | `(std service config)` |
| `service-config-user` | `(std service config)` |
| `service-config?` | `(std service config)` |
| `session-cleanup!` | `(std security auth)` |
| `session-create!` | `(std security auth)` |
| `session-destroy!` | `(std security auth)` |
| `session-store?` | `(std security auth)` |
| `session-validate` | `(std security auth)` |
| `session-window-add!` | `(std stream window)` |
| `session-window-flush!` | `(std stream window)` |
| `session-window-gap` | `(std stream window)` |
| `session-window?` | `(std stream window)` |
| `set` | `(jerboa clojure)`, `(std clojure)`, `(std lens)`, `(std srfi srfi-113)` |
| `set->list` | `(std srfi srfi-113)` |
| `set-actor-scheduler!` | `(std actor core)`, `(std actor)` |
| `set-adjoin` | `(std srfi srfi-113)` |
| `set-any?` | `(std srfi srfi-113)` |
| `set-box!` | `(std gambit-compat)` |
| `set-dead-letter-handler!` | `(std actor core)`, `(std actor)` |
| `set-delete` | `(std srfi srfi-113)` |
| `set-difference` | `(std srfi srfi-113)` |
| `set-empty?` | `(std srfi srfi-113)` |
| `set-every?` | `(std srfi srfi-113)` |
| `set-filter` | `(std srfi srfi-113)` |
| `set-fold` | `(std srfi srfi-113)` |
| `set-for-each` | `(std srfi srfi-113)` |
| `set-index` | `(jerboa clojure)`, `(std clojure)` |
| `set-intersection` | `(std srfi srfi-113)` |
| `set-join` | `(jerboa clojure)`, `(std clojure)` |
| `set-map` | `(std srfi srfi-113)` |
| `set-member?` | `(std srfi srfi-113)` |
| `set-port-position!` | `(std port-position)` |
| `set-project` | `(jerboa clojure)`, `(std clojure)` |
| `set-remote-send-handler!` | `(std actor core)`, `(std actor)` |
| `set-rename` | `(jerboa clojure)`, `(std clojure)` |
| `set-select` | `(jerboa clojure)`, `(std clojure)` |
| `set-size` | `(std srfi srfi-113)` |
| `set-union` | `(std srfi srfi-113)` |
| `set-xor` | `(std srfi srfi-113)` |
| `set?` | `(jerboa clojure)`, `(std clojure)`, `(std srfi srfi-113)` |
| `setenv` | `(jerboa core)`, `(std gambit-compat)`, `(std os env)` |
| `setenv*` | `(std gambit-compat)` |
| `setval` | `(std specter)` |
| `seventh` | `(std srfi srfi-1)` |
| `severity-error` | `(std lint)` |
| `severity-info` | `(std lint)` |
| `severity-warn` | `(std lint)` |
| `sexp->lockfile` | `(jerboa lock)` |
| `sexp->provenance` | `(std build reproducible)` |
| `sexp->sbom` | `(std build sbom)` |
| `sftp-attrs-atime` | `(std net ssh sftp)`, `(std net ssh)` |
| `sftp-attrs-gid` | `(std net ssh sftp)`, `(std net ssh)` |
| `sftp-attrs-mtime` | `(std net ssh sftp)`, `(std net ssh)` |
| `sftp-attrs-permissions` | `(std net ssh sftp)`, `(std net ssh)` |
| `sftp-attrs-size` | `(std net ssh sftp)`, `(std net ssh)` |
| `sftp-attrs-uid` | `(std net ssh sftp)`, `(std net ssh)` |
| `sftp-attrs?` | `(std net ssh sftp)`, `(std net ssh)` |
| `sha1` | `(std crypto digest)` |
| `sha224` | `(std crypto digest)` |
| `sha256` | `(std crypto digest)` |
| `sha384` | `(std crypto digest)` |
| `sha512` | `(std crypto digest)` |
| `shallow-clone` | `(std clos)` |
| `shared-cas!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc shared)` |
| `shared-ref` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc shared)` |
| `shared-set!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc shared)` |
| `shared-swap!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc shared)` |
| `shared-update!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc shared)` |
| `shared?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc shared)` |
| `shell` | `(std os shell)` |
| `shell!` | `(std os shell)` |
| `shell-async` | `(std os shell)` |
| `shell-async-pid` | `(std os shell)` |
| `shell-async-stderr` | `(std os shell)` |
| `shell-async-stdout` | `(std os shell)` |
| `shell-async-wait` | `(std os shell)` |
| `shell-async?` | `(std os shell)` |
| `shell-capture` | `(std os shell)` |
| `shell-env` | `(std os shell)` |
| `shell-escape` | `(std taint)` |
| `shell-label` | `(std taint)` |
| `shell-pipe` | `(std os shell)` |
| `shell-quote` | `(std os shell)` |
| `shell/lines` | `(std os shell)` |
| `shell/status` | `(std os shell)` |
| `shift` | `(std control delimited)`, `(std misc delimited)` |
| `shift-at` | `(std control delimited)` |
| `show` | `(std srfi srfi-159)` |
| `shrink-boolean` | `(std proptest)` |
| `shrink-int` | `(std test quickcheck)` |
| `shrink-integer` | `(std proptest)`, `(std test check)` |
| `shrink-list` | `(std proptest)`, `(std test check)`, `(std test quickcheck)` |
| `shrink-string` | `(std proptest)`, `(std test check)`, `(std test quickcheck)` |
| `shrink-value` | `(std proptest)` |
| `shuffle` | `(std misc shuffle)` |
| `shuffle!` | `(std misc shuffle)` |
| `shutdown-agent!` | `(std agent)` |
| `signal-channel-close!` | `(std os signal-channel)` |
| `signal-channel-recv` | `(std os signal-channel)` |
| `signal-channel-signals` | `(std os signal-channel)` |
| `signal-channel-try-recv` | `(std os signal-channel)` |
| `signal-channel?` | `(std os signal-channel)` |
| `signal-filter` | `(std frp)` |
| `signal-fold` | `(std frp)` |
| `signal-freeze` | `(std frp)` |
| `signal-map` | `(std frp)` |
| `signal-merge` | `(std frp)` |
| `signal-names` | `(std os signal)` |
| `signal-number->name` | `(std os signal-channel)` |
| `signal-ref` | `(std frp)` |
| `signal-sample` | `(std frp)` |
| `signal-set!` | `(std frp)` |
| `signal-unwatch` | `(std frp)` |
| `signal-watch` | `(std frp)` |
| `signal-zip` | `(std frp)` |
| `signal?` | `(std frp)` |
| `signalfd-close` | `(std os signalfd)` |
| `signalfd-fd` | `(std os signalfd)` |
| `signalfd-read` | `(std os signalfd)` |
| `sint16` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sint32` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sint64` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `sixth` | `(std srfi srfi-1)` |
| `slang->wasm-forms` | `(std secure wasm-target)` |
| `slang-allowed-forms` | `(std secure compiler)` |
| `slang-anti-debug!` | `(std secure preamble)` |
| `slang-build` | `(std secure link)` |
| `slang-build-config-cc` | `(std secure link)` |
| `slang-build-config-extra-c-files` | `(std secure link)` |
| `slang-build-config-output` | `(std secure link)` |
| `slang-build-config-sign-key` | `(std secure link)` |
| `slang-build-config-static-libs` | `(std secure link)` |
| `slang-build-config-strip?` | `(std secure link)` |
| `slang-build-config-verbose?` | `(std secure link)` |
| `slang-build-config-verify?` | `(std secure link)` |
| `slang-build-config?` | `(std secure link)` |
| `slang-compile` | `(std secure compiler)` |
| `slang-compile-wasm` | `(std secure wasm-target)` |
| `slang-compile-wasm-file` | `(std secure wasm-target)` |
| `slang-config-debug?` | `(std secure compiler)` |
| `slang-config-max-iteration` | `(std secure compiler)` |
| `slang-config-max-recursion` | `(std secure compiler)` |
| `slang-config-platform` | `(std secure compiler)` |
| `slang-config?` | `(std secure compiler)` |
| `slang-detect-platform` | `(std secure preamble)` |
| `slang-drop-privileges!` | `(std secure preamble)` |
| `slang-enter-sandbox!` | `(std secure preamble)` |
| `slang-error-form` | `(std secure compiler)` |
| `slang-error-kind` | `(std secure compiler)` |
| `slang-error-message` | `(std secure compiler)` |
| `slang-error?` | `(std secure compiler)` |
| `slang-fd-ref` | `(std secure preamble)` |
| `slang-fds` | `(std secure preamble)` |
| `slang-forbidden-forms` | `(std secure compiler)` |
| `slang-link` | `(std secure link)` |
| `slang-lower-form` | `(std secure wasm-target)` |
| `slang-module-body` | `(std secure compiler)` |
| `slang-module-limits` | `(std secure compiler)` |
| `slang-module-name` | `(std secure compiler)` |
| `slang-module-requires` | `(std secure compiler)` |
| `slang-module?` | `(std secure compiler)` |
| `slang-platform` | `(std secure preamble)` |
| `slang-pre-open-resources` | `(std secure preamble)` |
| `slang-preamble-init!` | `(std secure preamble)` |
| `slang-sign!` | `(std secure link)` |
| `slang-validate` | `(std secure compiler)` |
| `slang-validate-file` | `(std secure compiler)` |
| `slang-verify-binary` | `(std secure link)` |
| `slang-verify-integrity!` | `(std secure preamble)` |
| `slice` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `slice->bytevector` | `(std net zero-copy)` |
| `slice-copy!` | `(std net zero-copy)` |
| `slice-data` | `(std net zero-copy)` |
| `slice-length` | `(std net zero-copy)` |
| `slice-offset` | `(std net zero-copy)` |
| `sliding-buffer` | `(std csp clj)` |
| `sliding-window-add!` | `(std stream window)` |
| `sliding-window-count` | `(std net rate)` |
| `sliding-window-size` | `(std stream window)` |
| `sliding-window-step` | `(std stream window)` |
| `sliding-window-try!` | `(std net rate)` |
| `sliding-window?` | `(std net rate)`, `(std stream window)` |
| `slot-bound?` | `(std clos)` |
| `slot-definition-accessor` | `(std clos)` |
| `slot-definition-allocation` | `(std clos)` |
| `slot-definition-delegate` | `(std clos)` |
| `slot-definition-init-thunk` | `(std clos)` |
| `slot-definition-initarg` | `(std clos)` |
| `slot-definition-initform` | `(std clos)` |
| `slot-definition-name` | `(std clos)` |
| `slot-definition-observer` | `(std clos)` |
| `slot-definition-options` | `(std clos)` |
| `slot-definition-reader` | `(std clos)` |
| `slot-definition-validator` | `(std clos)` |
| `slot-definition-writer` | `(std clos)` |
| `slot-exists?` | `(std clos)` |
| `slot-missing` | `(std clos)` |
| `slot-ref` | `(std clos)` |
| `slot-set!` | `(std clos)` |
| `slot-unbound` | `(std clos)` |
| `slot-value` | `(std clos)` |
| `slot-value-using-class` | `(std clos)` |
| `slurp` | `(std clojure io)` |
| `sm-can-send?` | `(std misc state-machine)` |
| `sm-history` | `(std misc state-machine)` |
| `sm-on-transition!` | `(std misc state-machine)` |
| `sm-reset!` | `(std misc state-machine)` |
| `sm-send!` | `(std misc state-machine)` |
| `sm-state` | `(std misc state-machine)` |
| `sm-transitions` | `(std misc state-machine)` |
| `smtp-config?` | `(std net smtp)` |
| `smtp-connect` | `(std net smtp)` |
| `smtp-disconnect` | `(std net smtp)` |
| `smtp-send` | `(std net smtp)` |
| `snapshot!` | `(std event-source)` |
| `snapshots-for` | `(std debug timetravel)` |
| `snoc` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+3) |
| `socks-connect` | `(std net socks)` |
| `socks4-connect` | `(std net socks)` |
| `socks5-connect` | `(std net socks)` |
| `socks5-port` | `(std net socks5-server)` |
| `socks5-set-proxy-env!` | `(std net socks5-server)` |
| `socks5-start` | `(std net socks5-server)` |
| `socks5-stats` | `(std net socks5-server)` |
| `socks5-stop` | `(std net socks5-server)` |
| `socks5-unset-proxy-env!` | `(std net socks5-server)` |
| `solo-mode` | `(std csp clj)` |
| `solo-mode!` | `(std csp mix)`, `(std csp ops)` |
| `solve-constraint` | `(std typed solver)` |
| `solver-context-add!` | `(std typed solver)` |
| `solver-context-lookup` | `(std typed solver)` |
| `some` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)`, `(std prelude)` |
| `some->` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std sugar)` |
| `some->>` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std sugar)` |
| `some-fn` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc func)`, ... (+1) |
| `some?` | `(jerboa clojure)`, `(std clojure)` |
| `sort` | `(jerboa clojure)`, `(jerboa prelude safe)`, `(jerboa prelude)`, `(std prelude)`, ... (+2) |
| `sort!` | `(jerboa clojure)`, `(jerboa prelude safe)`, `(jerboa prelude)`, `(std prelude)`, ... (+2) |
| `sort-applicable-methods` | `(std clos)` |
| `sorted-map->alist` | `(std ds sorted-map)` |
| `sorted-map-delete` | `(std ds sorted-map)` |
| `sorted-map-empty` | `(std ds sorted-map)` |
| `sorted-map-fold` | `(std ds sorted-map)` |
| `sorted-map-insert` | `(std ds sorted-map)` |
| `sorted-map-keys` | `(std ds sorted-map)` |
| `sorted-map-lookup` | `(std ds sorted-map)` |
| `sorted-map-max` | `(std ds sorted-map)` |
| `sorted-map-min` | `(std ds sorted-map)` |
| `sorted-map-range` | `(std ds sorted-map)` |
| `sorted-map-size` | `(std ds sorted-map)` |
| `sorted-map-values` | `(std ds sorted-map)` |
| `sorted-map?` | `(std ds sorted-map)` |
| `sorted-set` | `(jerboa clojure)`, `(std clojure)`, `(std sorted-set)` |
| `sorted-set->list` | `(jerboa clojure)`, `(std clojure)`, `(std sorted-set)` |
| `sorted-set-add` | `(jerboa clojure)`, `(std clojure)`, `(std sorted-set)` |
| `sorted-set-by` | `(jerboa clojure)`, `(std clojure)`, `(std sorted-set)` |
| `sorted-set-contains?` | `(jerboa clojure)`, `(std clojure)`, `(std sorted-set)` |
| `sorted-set-empty` | `(jerboa clojure)`, `(std clojure)`, `(std sorted-set)` |
| `sorted-set-fold` | `(jerboa clojure)`, `(std clojure)`, `(std sorted-set)` |
| `sorted-set-max` | `(jerboa clojure)`, `(std clojure)`, `(std sorted-set)` |
| `sorted-set-min` | `(jerboa clojure)`, `(std clojure)`, `(std sorted-set)` |
| `sorted-set-range` | `(jerboa clojure)`, `(std clojure)`, `(std sorted-set)` |
| `sorted-set-remove` | `(jerboa clojure)`, `(std clojure)`, `(std sorted-set)` |
| `sorted-set-size` | `(jerboa clojure)`, `(std clojure)`, `(std sorted-set)` |
| `sorted-set?` | `(jerboa clojure)`, `(std clojure)`, `(std sorted-set)` |
| `sorted?` | `(std srfi srfi-95)` |
| `source-location` | `(jerboa reader)` |
| `source-location-col` | `(std errors)` |
| `source-location-column` | `(jerboa reader)` |
| `source-location-file` | `(std errors)` |
| `source-location-line` | `(jerboa reader)`, `(std errors)` |
| `source-location-path` | `(jerboa reader)` |
| `source-location?` | `(jerboa reader)`, `(std errors)` |
| `space-to` | `(std srfi srfi-159)` |
| `span-context` | `(std span)` |
| `span-duration` | `(std span)` |
| `span-id` | `(std span)` |
| `span-log!` | `(std span)` |
| `span-set-tag!` | `(std span)` |
| `spawn` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `spawn-actor` | `(std actor core)`, `(std actor)` |
| `spawn-actor/linked` | `(std actor core)`, `(std actor)` |
| `spawn-bounded-actor` | `(std actor bounded)` |
| `spawn-bounded-actor/linked` | `(std actor bounded)` |
| `spawn-engine-actor` | `(std actor engine)` |
| `spawn-future` | `(std concur util)` |
| `spawn-process` | `(std os fd)` |
| `spawn/group` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `spawn/name` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `specialize` | `(std staging2)` |
| `specialize-fixnum` | `(std specialize)` |
| `specialize-fn` | `(std specialize)` |
| `specialize-function` | `(std compiler partial-eval)` |
| `specialize-numeric` | `(std specialize)` |
| `specialized?` | `(std specialize)` |
| `spin-lock!` | `(std misc spinlock)` |
| `spin-unlock!` | `(std misc spinlock)` |
| `spin-until-gate` | `(std fiber)` |
| `spinlock?` | `(std misc spinlock)` |
| `spit` | `(std clojure io)` |
| `splice` | `(std quasiquote-types)` |
| `split` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure string)`, `(std csp clj)`, ... (+1) |
| `split-at` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)`, `(std prelude)`, ... (+1) |
| `split-at!` | `(std srfi srfi-1)` |
| `split-by` | `(std csp clj)` |
| `split-lines` | `(std clojure string)` |
| `split-with` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)`, `(std prelude)` |
| `sprintf` | `(std text printf)` |
| `sql-and` | `(std ffi sql-null)`, `(thunderchez sql-null)` |
| `sql-coalesce` | `(std ffi sql-null)`, `(thunderchez sql-null)` |
| `sql-escape` | `(std security sanitize)`, `(std taint)` |
| `sql-label` | `(std taint)` |
| `sql-not` | `(std ffi sql-null)`, `(thunderchez sql-null)` |
| `sql-null` | `(std ffi sql-null)`, `(thunderchez sql-null)` |
| `sql-null?` | `(std ffi sql-null)`, `(thunderchez sql-null)` |
| `sql-or` | `(std ffi sql-null)`, `(thunderchez sql-null)` |
| `sqlite-bind` | `(jerboa prelude safe)` |
| `sqlite-bind!` | `(std db sqlite)` |
| `sqlite-bind-blob` | `(std db sqlite-native)` |
| `sqlite-bind-double` | `(std db sqlite-native)` |
| `sqlite-bind-int` | `(std db sqlite-native)` |
| `sqlite-bind-null` | `(std db sqlite-native)` |
| `sqlite-bind-null!` | `(std db sqlite)` |
| `sqlite-bind-text` | `(std db sqlite-native)` |
| `sqlite-changes` | `(std db sqlite-native)`, `(std db sqlite)` |
| `sqlite-clear-bindings` | `(std db sqlite)` |
| `sqlite-close` | `(jerboa prelude safe)`, `(std db sqlite-native)`, `(std db sqlite)` |
| `sqlite-column-blob` | `(std db sqlite-native)` |
| `sqlite-column-count` | `(std db sqlite-native)`, `(std db sqlite)` |
| `sqlite-column-double` | `(std db sqlite-native)` |
| `sqlite-column-int` | `(std db sqlite-native)` |
| `sqlite-column-name` | `(std db sqlite-native)`, `(std db sqlite)` |
| `sqlite-column-text` | `(std db sqlite-native)` |
| `sqlite-column-type` | `(std db sqlite-native)`, `(std db sqlite)` |
| `sqlite-column-value` | `(std db sqlite)` |
| `sqlite-columns` | `(std db sqlite)` |
| `sqlite-done?` | `(std db sqlite-native)` |
| `sqlite-errmsg` | `(std db sqlite-native)`, `(std db sqlite)` |
| `sqlite-eval` | `(std db sqlite)` |
| `sqlite-exec` | `(jerboa prelude safe)`, `(std db sqlite-native)`, `(std db sqlite)` |
| `sqlite-execute` | `(jerboa prelude safe)`, `(std db sqlite-native)` |
| `sqlite-finalize` | `(jerboa prelude safe)`, `(std db sqlite-native)`, `(std db sqlite)` |
| `sqlite-last-insert-rowid` | `(std db sqlite-native)`, `(std db sqlite)` |
| `sqlite-open` | `(jerboa prelude safe)`, `(std db sqlite-native)`, `(std db sqlite)` |
| `sqlite-prepare` | `(jerboa prelude safe)`, `(std db sqlite-native)`, `(std db sqlite)` |
| `sqlite-query` | `(jerboa prelude safe)`, `(std db sqlite-native)`, `(std db sqlite)` |
| `sqlite-reset` | `(std db sqlite-native)`, `(std db sqlite)` |
| `sqlite-row?` | `(std db sqlite-native)` |
| `sqlite-step` | `(jerboa prelude safe)`, `(std db sqlite-native)`, `(std db sqlite)` |
| `srange` | `(std specter)` |
| `sre->named-groups` | `(std srfi srfi-115)` |
| `sre->pattern-string` | `(std srfi srfi-115)` |
| `ssax:make-elem-parser` | `(std markup ssax)` |
| `ssax:make-parser` | `(std markup ssax)` |
| `ssax:make-pi-parser` | `(std markup ssax)` |
| `ssax:xml->sxml` | `(std markup ssax)` |
| `ssh-auth-error-available-methods` | `(std net ssh conditions)` |
| `ssh-auth-error-method` | `(std net ssh conditions)` |
| `ssh-auth-error?` | `(std net ssh conditions)`, `(std net ssh)` |
| `ssh-auth-interactive` | `(std net ssh auth)` |
| `ssh-auth-password` | `(std net ssh auth)` |
| `ssh-auth-publickey` | `(std net ssh auth)` |
| `ssh-capture` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-channel-close` | `(std net ssh channel)` |
| `ssh-channel-closed?` | `(std net ssh channel)` |
| `ssh-channel-closed?-set!` | `(std net ssh channel)` |
| `ssh-channel-data-event` | `(std net ssh channel)`, `(std net ssh)` |
| `ssh-channel-data-queue` | `(std net ssh channel)` |
| `ssh-channel-data-queue-set!` | `(std net ssh channel)` |
| `ssh-channel-dispatch` | `(std net ssh channel)` |
| `ssh-channel-dispatch-until` | `(std net ssh channel)` |
| `ssh-channel-eof?` | `(std net ssh channel)` |
| `ssh-channel-eof?-set!` | `(std net ssh channel)` |
| `ssh-channel-error-channel-id` | `(std net ssh conditions)` |
| `ssh-channel-error?` | `(std net ssh conditions)`, `(std net ssh)` |
| `ssh-channel-exit-signal` | `(std net ssh channel)` |
| `ssh-channel-exit-signal-set!` | `(std net ssh channel)` |
| `ssh-channel-exit-status` | `(std net ssh channel)` |
| `ssh-channel-exit-status-set!` | `(std net ssh channel)` |
| `ssh-channel-local-id` | `(std net ssh channel)` |
| `ssh-channel-local-window` | `(std net ssh channel)` |
| `ssh-channel-local-window-set!` | `(std net ssh channel)` |
| `ssh-channel-open-direct-tcpip` | `(std net ssh channel)` |
| `ssh-channel-open-session` | `(std net ssh channel)` |
| `ssh-channel-read` | `(std net ssh channel)` |
| `ssh-channel-read-stderr` | `(std net ssh channel)` |
| `ssh-channel-remote-id` | `(std net ssh channel)` |
| `ssh-channel-remote-id-set!` | `(std net ssh channel)` |
| `ssh-channel-remote-max-packet` | `(std net ssh channel)` |
| `ssh-channel-remote-max-packet-set!` | `(std net ssh channel)` |
| `ssh-channel-remote-window` | `(std net ssh channel)` |
| `ssh-channel-remote-window-set!` | `(std net ssh channel)` |
| `ssh-channel-send-data` | `(std net ssh channel)` |
| `ssh-channel-send-eof` | `(std net ssh channel)` |
| `ssh-channel-stderr-event` | `(std net ssh channel)`, `(std net ssh)` |
| `ssh-channel-stderr-queue` | `(std net ssh channel)` |
| `ssh-channel-stderr-queue-set!` | `(std net ssh channel)` |
| `ssh-channel?` | `(std net ssh channel)` |
| `ssh-connect` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-connection-channel-table` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-connection-custodian` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-connection-error-host` | `(std net ssh conditions)` |
| `ssh-connection-error-port` | `(std net ssh conditions)` |
| `ssh-connection-error?` | `(std net ssh conditions)`, `(std net ssh)` |
| `ssh-connection-state` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-connection-transport` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-connection?` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-disconnect` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-error-operation` | `(std net ssh conditions)`, `(std net ssh)` |
| `ssh-error?` | `(std net ssh conditions)`, `(std net ssh)` |
| `ssh-exec` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-forward-fd-pool` | `(std net ssh forward)` |
| `ssh-forward-local` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-forward-local-start` | `(std net ssh forward)` |
| `ssh-forward-local-stop` | `(std net ssh forward)`, `(std net ssh)` |
| `ssh-forward-remote` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-forward-remote-cancel` | `(std net ssh forward)` |
| `ssh-forward-remote-request` | `(std net ssh forward)` |
| `ssh-host-key-error-fingerprint` | `(std net ssh conditions)` |
| `ssh-host-key-error-reason` | `(std net ssh conditions)` |
| `ssh-host-key-error?` | `(std net ssh conditions)`, `(std net ssh)` |
| `ssh-host-key-fingerprint` | `(std net ssh known-hosts)`, `(std net ssh)` |
| `ssh-kex-activate-keys` | `(std net ssh kex)` |
| `ssh-kex-build-kexinit` | `(std net ssh kex)` |
| `ssh-kex-derive-keys` | `(std net ssh kex)` |
| `ssh-kex-error-phase` | `(std net ssh conditions)` |
| `ssh-kex-error?` | `(std net ssh conditions)`, `(std net ssh)` |
| `ssh-kex-negotiate` | `(std net ssh kex)` |
| `ssh-kex-parse-kexinit` | `(std net ssh kex)` |
| `ssh-kex-perform` | `(std net ssh kex)` |
| `ssh-known-hosts-add` | `(std net ssh known-hosts)`, `(std net ssh)` |
| `ssh-known-hosts-verifier` | `(std net ssh known-hosts)`, `(std net ssh)` |
| `ssh-known-hosts-verify` | `(std net ssh known-hosts)`, `(std net ssh)` |
| `ssh-make-payload` | `(std net ssh wire)` |
| `ssh-pool-drain` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-pool-stats` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-protocol-error-expected` | `(std net ssh conditions)` |
| `ssh-protocol-error-received` | `(std net ssh conditions)` |
| `ssh-protocol-error?` | `(std net ssh conditions)`, `(std net ssh)` |
| `ssh-read-boolean` | `(std net ssh wire)` |
| `ssh-read-byte` | `(std net ssh wire)` |
| `ssh-read-mpint` | `(std net ssh wire)` |
| `ssh-read-name-list` | `(std net ssh wire)` |
| `ssh-read-string` | `(std net ssh wire)` |
| `ssh-read-uint32` | `(std net ssh wire)` |
| `ssh-run` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-scp-get` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-scp-put` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-session-exec` | `(std net ssh session)` |
| `ssh-session-exec-simple` | `(std net ssh session)` |
| `ssh-session-request-pty` | `(std net ssh session)` |
| `ssh-session-shell` | `(std net ssh session)` |
| `ssh-session-subsystem` | `(std net ssh session)` |
| `ssh-sftp` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-sftp-close` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-sftp-close-handle` | `(std net ssh sftp)`, `(std net ssh)` |
| `ssh-sftp-close-session` | `(std net ssh sftp)` |
| `ssh-sftp-error-code` | `(std net ssh conditions)` |
| `ssh-sftp-error-path` | `(std net ssh conditions)` |
| `ssh-sftp-error?` | `(std net ssh conditions)`, `(std net ssh)` |
| `ssh-sftp-fstat` | `(std net ssh sftp)`, `(std net ssh)` |
| `ssh-sftp-get` | `(std net ssh sftp)`, `(std net ssh)` |
| `ssh-sftp-list-directory` | `(std net ssh sftp)`, `(std net ssh)` |
| `ssh-sftp-mkdir` | `(std net ssh sftp)`, `(std net ssh)` |
| `ssh-sftp-open` | `(std net ssh sftp)`, `(std net ssh)` |
| `ssh-sftp-open-session` | `(std net ssh sftp)` |
| `ssh-sftp-opendir` | `(std net ssh sftp)` |
| `ssh-sftp-put` | `(std net ssh sftp)`, `(std net ssh)` |
| `ssh-sftp-read` | `(std net ssh sftp)`, `(std net ssh)` |
| `ssh-sftp-readdir` | `(std net ssh sftp)` |
| `ssh-sftp-realpath` | `(std net ssh sftp)`, `(std net ssh)` |
| `ssh-sftp-remove` | `(std net ssh sftp)`, `(std net ssh)` |
| `ssh-sftp-rename` | `(std net ssh sftp)`, `(std net ssh)` |
| `ssh-sftp-rmdir` | `(std net ssh sftp)`, `(std net ssh)` |
| `ssh-sftp-setstat` | `(std net ssh sftp)`, `(std net ssh)` |
| `ssh-sftp-stat` | `(std net ssh sftp)`, `(std net ssh)` |
| `ssh-sftp-write` | `(std net ssh sftp)`, `(std net ssh)` |
| `ssh-shell` | `(std net ssh client)`, `(std net ssh)` |
| `ssh-tcp-read-exact` | `(std net ssh transport)` |
| `ssh-tcp-write-all` | `(std net ssh transport)` |
| `ssh-timeout-error-seconds` | `(std net ssh conditions)` |
| `ssh-timeout-error?` | `(std net ssh conditions)`, `(std net ssh)` |
| `ssh-transport-close` | `(std net ssh transport)` |
| `ssh-transport-connect` | `(std net ssh transport)` |
| `ssh-transport-fd-pool` | `(std net ssh transport)` |
| `ssh-transport-needs-rekey?` | `(std net ssh transport)` |
| `ssh-transport-recv-packet` | `(std net ssh transport)` |
| `ssh-transport-recv-version` | `(std net ssh transport)` |
| `ssh-transport-send-packet` | `(std net ssh transport)` |
| `ssh-transport-send-version` | `(std net ssh transport)` |
| `ssh-userauth-request` | `(std net ssh auth)` |
| `ssh-write-boolean` | `(std net ssh wire)` |
| `ssh-write-byte` | `(std net ssh wire)` |
| `ssh-write-mpint` | `(std net ssh wire)` |
| `ssh-write-name-list` | `(std net ssh wire)` |
| `ssh-write-string` | `(std net ssh wire)` |
| `ssh-write-uint32` | `(std net ssh wire)` |
| `ssl-cleanup!` | `(std net ssl)` |
| `ssl-close` | `(std net ssl)` |
| `ssl-connect` | `(std net ssl)` |
| `ssl-connection?` | `(std net ssl)` |
| `ssl-init!` | `(std net ssl)` |
| `ssl-read` | `(std net ssl)` |
| `ssl-read-all` | `(std net ssl)` |
| `ssl-server-accept` | `(std net ssl)` |
| `ssl-server-ctx` | `(std net ssl)` |
| `ssl-server-ctx-free` | `(std net ssl)` |
| `ssl-write` | `(std net ssl)` |
| `ssl-write-string` | `(std net ssl)` |
| `stable-sort` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `stable-sort!` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `stack-trace` | `(std debug inspector)` |
| `stage` | `(std quasiquote-types)` |
| `stage-apply` | `(std staging2)` |
| `stage-begin` | `(std staging2)` |
| `stage-fn` | `(std pipeline)` |
| `stage-if` | `(std staging2)` |
| `stage-let` | `(std staging2)` |
| `stage-name` | `(std pipeline)` |
| `stage-result` | `(std pipeline)` |
| `stage?` | `(std pipeline)` |
| `staged-code` | `(std staging2)` |
| `staged-eval` | `(std staging2)` |
| `staged-lambda` | `(std quasiquote-types)` |
| `staged?` | `(std staging2)` |
| `standard-method-combination` | `(std clos)` |
| `standard-policy` | `(std capability sandbox)` |
| `start` | `(std component fiber)`, `(std component)` |
| `start-component` | `(std component fiber)`, `(std component)` |
| `start-guardian-thread!` | `(std foreign)` |
| `start-logger!` | `(std logger)` |
| `start-lsp-server` | `(std lsp server)` |
| `start-node!` | `(std actor cluster)`, `(std actor transport)` |
| `start-node-server!` | `(std actor transport)` |
| `start-python` | `(std python)` |
| `start-registry!` | `(std actor registry)`, `(std actor)` |
| `start-repl-server` | `(std net repl)` |
| `start-signal-thread!` | `(std os signal-channel)` |
| `start-span` | `(std span)` |
| `start-supervisor` | `(std actor supervisor)`, `(std actor)` |
| `starts-with?` | `(std clojure string)` |
| `stat-atime` | `(std os posix)` |
| `stat-ctime` | `(std os posix)` |
| `stat-dev` | `(std os posix)` |
| `stat-gid` | `(std os posix)` |
| `stat-ino` | `(std os posix)` |
| `stat-is-block?` | `(std os posix)` |
| `stat-is-char?` | `(std os posix)` |
| `stat-is-directory?` | `(std os posix)` |
| `stat-is-fifo?` | `(std os posix)` |
| `stat-is-regular?` | `(std os posix)` |
| `stat-is-socket?` | `(std os posix)` |
| `stat-is-symlink?` | `(std os posix)` |
| `stat-mode` | `(std os posix)` |
| `stat-mtime` | `(std os posix)` |
| `stat-nlink` | `(std os posix)` |
| `stat-size` | `(std os posix)` |
| `stat-uid` | `(std os posix)` |
| `state-bind` | `(std typed monad)` |
| `state-get` | `(std effect state)`, `(std typed monad)` |
| `state-machine?` | `(std misc state-machine)` |
| `state-modify` | `(std effect state)`, `(std typed monad)` |
| `state-put` | `(std effect state)`, `(std typed monad)` |
| `state-return` | `(std typed monad)` |
| `static-link-flags` | `(jerboa build)` |
| `static-value?` | `(std compiler partial-eval)` |
| `stay-then-continue` | `(std specter)` |
| `stop` | `(std component fiber)`, `(std component)` |
| `stop-component` | `(std component fiber)`, `(std component)` |
| `stop-guardian-thread!` | `(std foreign)` |
| `stop-node!` | `(std actor cluster)` |
| `stop-python` | `(std python)` |
| `stop-repl-server` | `(std net repl)` |
| `stop-signal-thread!` | `(std os signal-channel)` |
| `stop-watching!` | `(std dev reload)` |
| `stopwatch-elapsed` | `(std time)` |
| `stopwatch-lap!` | `(std time)` |
| `stopwatch-laps` | `(std time)` |
| `stopwatch-report` | `(std time)` |
| `stopwatch-reset!` | `(std time)` |
| `stopwatch-start!` | `(std time)` |
| `stopwatch-stop!` | `(std time)` |
| `stopwatch?` | `(std time)` |
| `str` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std sugar)` |
| `str/blank?` | `(jerboa clojure)` |
| `str/capitalize` | `(jerboa clojure)` |
| `str/clj-index-of` | `(jerboa clojure)` |
| `str/ends-with?` | `(jerboa clojure)` |
| `str/escape` | `(jerboa clojure)` |
| `str/includes?` | `(jerboa clojure)` |
| `str/join` | `(jerboa clojure)` |
| `str/lower-case` | `(jerboa clojure)` |
| `str/re-quote-replacement` | `(jerboa clojure)` |
| `str/replace` | `(jerboa clojure)` |
| `str/replace-first` | `(jerboa clojure)` |
| `str/reverse` | `(jerboa clojure)` |
| `str/split` | `(jerboa clojure)` |
| `str/split-lines` | `(jerboa clojure)` |
| `str/starts-with?` | `(jerboa clojure)` |
| `str/trim` | `(jerboa clojure)` |
| `str/trim-newline` | `(jerboa clojure)` |
| `str/triml` | `(jerboa clojure)` |
| `str/trimr` | `(jerboa clojure)` |
| `str/upper-case` | `(jerboa clojure)` |
| `strategy/least-loaded` | `(std actor cluster)` |
| `strategy/local-first` | `(std actor cluster)` |
| `strategy/round-robin` | `(std actor cluster)` |
| `stream->list` | `(std srfi srfi-41)` |
| `stream-append` | `(std srfi srfi-41)` |
| `stream-car` | `(std srfi srfi-41)` |
| `stream-cdr` | `(std srfi srfi-41)` |
| `stream-cons` | `(std srfi srfi-41)` |
| `stream-constant` | `(std srfi srfi-41)` |
| `stream-drop` | `(std srfi srfi-41)` |
| `stream-filter` | `(std srfi srfi-41)` |
| `stream-fold` | `(std srfi srfi-41)` |
| `stream-for-each` | `(std srfi srfi-41)` |
| `stream-iterate` | `(std srfi srfi-41)` |
| `stream-map` | `(std srfi srfi-41)` |
| `stream-null` | `(std srfi srfi-41)` |
| `stream-null?` | `(std srfi srfi-41)` |
| `stream-pair?` | `(std srfi srfi-41)` |
| `stream-range` | `(std srfi srfi-41)` |
| `stream-ref` | `(std srfi srfi-41)` |
| `stream-take` | `(std srfi srfi-41)` |
| `stream-zip` | `(std srfi srfi-41)` |
| `stream?` | `(std srfi srfi-41)` |
| `string->bytes` | `(jerboa core)`, `(std gambit-compat)` |
| `string->char-set` | `(std srfi srfi-14)`, `(std text char-set)` |
| `string->date` | `(std srfi srfi-19)` |
| `string->decimal` | `(std misc decimal)` |
| `string->edn` | `(std text edn)` |
| `string->generator` | `(std srfi srfi-121)`, `(std srfi srfi-158)` |
| `string->json-object` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `string->keyword` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `string->platform` | `(std build cross)` |
| `string->text` | `(std srfi srfi-135)` |
| `string->toml` | `(std text toml)` |
| `string->transit` | `(jerboa clojure)`, `(std transit)` |
| `string->utf16` | `(std text utf16)` |
| `string->utf32` | `(std text utf32)` |
| `string->utf8` | `(std text utf8)` |
| `string-any` | `(std srfi srfi-13)`, `(std string)` |
| `string-comparator` | `(std srfi srfi-128)` |
| `string-concatenate` | `(std srfi srfi-13)`, `(std string)` |
| `string-contains` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+4) |
| `string-contains-ci` | `(std srfi srfi-13)` |
| `string-contains?` | `(std misc string-more)` |
| `string-count` | `(std misc string-more)`, `(std srfi srfi-13)`, `(std string)` |
| `string-cursor->index` | `(std srfi srfi-130)` |
| `string-cursor-back` | `(std srfi srfi-130)` |
| `string-cursor-diff` | `(std srfi srfi-130)` |
| `string-cursor-end` | `(std srfi srfi-130)` |
| `string-cursor-forward` | `(std srfi srfi-130)` |
| `string-cursor-next` | `(std srfi srfi-130)` |
| `string-cursor-prev` | `(std srfi srfi-130)` |
| `string-cursor-ref` | `(std srfi srfi-130)` |
| `string-cursor-start` | `(std srfi srfi-130)` |
| `string-cursor<=?` | `(std srfi srfi-130)` |
| `string-cursor<?` | `(std srfi srfi-130)` |
| `string-cursor=?` | `(std srfi srfi-130)` |
| `string-cursor>=?` | `(std srfi srfi-130)` |
| `string-cursor>?` | `(std srfi srfi-130)` |
| `string-delete` | `(std srfi srfi-13)`, `(std string)` |
| `string-drop` | `(std srfi srfi-13)`, `(std string)` |
| `string-drop-right` | `(std srfi srfi-13)`, `(std string)` |
| `string-drop-while` | `(std misc string-more)` |
| `string-ec` | `(std srfi srfi-42)` |
| `string-empty?` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+6) |
| `string-every` | `(std srfi srfi-13)`, `(std string)` |
| `string-filter` | `(std misc string-more)`, `(std srfi srfi-13)`, `(std string)` |
| `string-find` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc string)`, `(std prelude)` |
| `string-find-all` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc string)`, `(std prelude)` |
| `string-fold` | `(std srfi srfi-13)`, `(std string)` |
| `string-fold-right` | `(std srfi srfi-13)`, `(std string)` |
| `string-for-each-index` | `(std srfi srfi-13)`, `(std string)` |
| `string-index` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+5) |
| `string-index->cursor` | `(std srfi srfi-130)` |
| `string-index-right` | `(std misc string-more)`, `(std srfi srfi-13)`, `(std string)` |
| `string-join` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+5) |
| `string-like?` | `(std macro-types)` |
| `string-map` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude)`, `(std gambit-compat)` |
| `string-map!` | `(std srfi srfi-13)`, `(std string)` |
| `string-match?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc string)`, `(std prelude)` |
| `string-null?` | `(std srfi srfi-13)`, `(std string)` |
| `string-pad` | `(std srfi srfi-13)`, `(std string)` |
| `string-pad-left` | `(std misc string-more)` |
| `string-pad-right` | `(std misc string-more)`, `(std srfi srfi-13)`, `(std string)` |
| `string-prefix?` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+5) |
| `string-reader?` | `(std io strio)` |
| `string-repeat` | `(std misc string-more)` |
| `string-replace` | `(std misc string-more)`, `(std srfi srfi-13)`, `(std string)`, `(thunderchez thunder-utils)` |
| `string-reverse` | `(std misc string-more)`, `(std srfi srfi-13)`, `(std string)` |
| `string-split` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+7) |
| `string-subst` | `(jerboa core)`, `(std gambit-compat)` |
| `string-suffix?` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+6) |
| `string-take` | `(std srfi srfi-13)`, `(std string)` |
| `string-take-right` | `(std srfi srfi-13)`, `(std string)` |
| `string-take-while` | `(std misc string-more)` |
| `string-tokenize` | `(std srfi srfi-13)`, `(std string)` |
| `string-trim` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+4) |
| `string-trim-both` | `(std misc string-more)`, `(std srfi srfi-13)`, `(std string)` |
| `string-trim-eol` | `(std misc string)` |
| `string-trim-left` | `(std misc string-more)` |
| `string-trim-right` | `(std misc string-more)`, `(std srfi srfi-13)`, `(std string)` |
| `string-writer?` | `(std io strio)` |
| `strip-meta` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc meta)` |
| `struct-field-ref` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `struct-field-set!` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `struct-fields` | `(std staging)` |
| `struct-info-accessors` | `(std derive)` |
| `struct-info-fields` | `(std derive)` |
| `struct-info-make` | `(std derive)` |
| `struct-info-mutators` | `(std derive)` |
| `struct-info-name` | `(std derive)` |
| `struct-info-pred` | `(std derive)` |
| `struct-info-rtd` | `(std derive)` |
| `struct-info?` | `(std derive)` |
| `struct-out` | `(jerboa core)`, `(std gambit-compat)` |
| `struct-predicate` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `struct-type-info` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `sttf-render-glyph-blended` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `sttf-render-glyph-shaded` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `sttf-render-glyph-solid` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `sttf-render-text-blended` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `sttf-render-text-shaded` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `sttf-render-text-solid` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `sttf-render-unicode-blended` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `sttf-render-unicode-shaded` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `sttf-render-unicode-solid` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `sttf-render-ut-f8-blended` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `sttf-render-ut-f8-shaded` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `sttf-render-ut-f8-solid` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `stx->datum` | `(std stxutil)` |
| `stx-app-args` | `(std match-syntax)` |
| `stx-app-fn` | `(std match-syntax)` |
| `stx-application?` | `(std match-syntax)` |
| `stx-begin-exprs` | `(std match-syntax)` |
| `stx-begin?` | `(std match-syntax)` |
| `stx-car` | `(std stxutil)` |
| `stx-cdr` | `(std stxutil)` |
| `stx-define-name` | `(std match-syntax)` |
| `stx-define-value` | `(std match-syntax)` |
| `stx-define?` | `(std match-syntax)` |
| `stx-e` | `(std stxutil)` |
| `stx-for-each` | `(std stxutil)` |
| `stx-identifier-symbol` | `(std match-syntax)` |
| `stx-identifier?` | `(std match-syntax)`, `(std stxutil)` |
| `stx-if-else` | `(std match-syntax)` |
| `stx-if-test` | `(std match-syntax)` |
| `stx-if-then` | `(std match-syntax)` |
| `stx-if?` | `(std match-syntax)` |
| `stx-lambda-body` | `(std match-syntax)` |
| `stx-lambda-formals` | `(std match-syntax)` |
| `stx-lambda?` | `(std match-syntax)` |
| `stx-length` | `(std stxutil)` |
| `stx-let-bindings` | `(std match-syntax)` |
| `stx-let-body` | `(std match-syntax)` |
| `stx-let?` | `(std match-syntax)` |
| `stx-list?` | `(std match-syntax)`, `(std stxutil)` |
| `stx-literal?` | `(std match-syntax)` |
| `stx-map` | `(std stxutil)` |
| `stx-null?` | `(std match-syntax)`, `(std stxutil)` |
| `stx-pair?` | `(std match-syntax)`, `(std stxutil)` |
| `stx-quote?` | `(std match-syntax)` |
| `styled` | `(std cli style)` |
| `sub` | `(std csp clj)` |
| `sub!` | `(std csp ops)` |
| `sub-bytevector` | `(thunderchez thunder-utils)` |
| `sub-bytevector=?` | `(thunderchez thunder-utils)` |
| `submap` | `(std specter)` |
| `subpath` | `(std misc path)` |
| `subset?` | `(jerboa clojure)`, `(std clojure)` |
| `substitute` | `(std rewrite)` |
| `substring/cursors` | `(std srfi srfi-130)` |
| `subtext` | `(std srfi srfi-135)` |
| `subtype?` | `(std typed infer)` |
| `subu8vector` | `(jerboa core)`, `(std gambit-compat)` |
| `succeed` | `(jerboa clojure)`, `(std logic)` |
| `success-prefix` | `(std cli style)` |
| `suite-failed` | `(std test framework)` |
| `suite-name` | `(std test framework)` |
| `suite-passed` | `(std test framework)` |
| `suite-results` | `(std test framework)` |
| `sum-accumulator` | `(std srfi srfi-158)` |
| `sum-ec` | `(std srfi srfi-42)` |
| `superset?` | `(jerboa clojure)`, `(std clojure)` |
| `supervise!` | `(std service supervise)` |
| `supervision-failure-child-id` | `(std error conditions)` |
| `supervision-failure-reason` | `(std error conditions)` |
| `supervision-failure?` | `(std error conditions)` |
| `supervisor-children` | `(std proc supervisor)` |
| `supervisor-count-children` | `(std actor supervisor)`, `(std actor)` |
| `supervisor-delete-child!` | `(std actor supervisor)`, `(std actor)` |
| `supervisor-restart-child!` | `(std actor supervisor)`, `(std actor)`, `(std proc supervisor)` |
| `supervisor-run!` | `(std proc supervisor)` |
| `supervisor-running?` | `(std proc supervisor)` |
| `supervisor-start-child!` | `(std actor supervisor)`, `(std actor)`, `(std proc supervisor)` |
| `supervisor-stop!` | `(std proc supervisor)` |
| `supervisor-stop-child!` | `(std proc supervisor)` |
| `supervisor-terminate-child!` | `(std actor supervisor)`, `(std actor)` |
| `supervisor-which-children` | `(std actor supervisor)`, `(std actor)` |
| `supervisor?` | `(std proc supervisor)` |
| `suppress-deprecation-warnings` | `(std deprecation)` |
| `svc-alarm!` | `(std service control)` |
| `svc-continue!` | `(std service control)` |
| `svc-down!` | `(std service control)` |
| `svc-exit!` | `(std service control)` |
| `svc-hup!` | `(std service control)` |
| `svc-kill!` | `(std service control)` |
| `svc-once!` | `(std service control)` |
| `svc-pause!` | `(std service control)` |
| `svc-term!` | `(std service control)` |
| `svc-up!` | `(std service control)` |
| `svok?` | `(std service control)` |
| `svscan!` | `(std service svscan)` |
| `svstat` | `(std service control)` |
| `svstat-info-paused?` | `(std service control)` |
| `svstat-info-pid` | `(std service control)` |
| `svstat-info-seconds` | `(std service control)` |
| `svstat-info-up?` | `(std service control)` |
| `svstat-info-want` | `(std service control)` |
| `svstat-info?` | `(std service control)` |
| `svstat-string` | `(std service control)` |
| `swap!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc atom)` |
| `sxml->html` | `(std markup sxml-print)` |
| `sxml->string` | `(std markup sxml-print)` |
| `sxml->xml` | `(std markup sxml-print)` |
| `sxml-attribute-e` | `(std markup xml)`, `(std text xml)` |
| `sxml-attributes` | `(std markup xml)`, `(std text xml)` |
| `sxml-children` | `(std markup xml)`, `(std text xml)` |
| `sxml-e` | `(std markup xml)`, `(std text xml)` |
| `sxml:add-child` | `(std markup sxml)` |
| `sxml:attr` | `(std markup sxml)` |
| `sxml:attributes` | `(std markup sxml)` |
| `sxml:children` | `(std markup sxml)` |
| `sxml:content` | `(std markup sxml)` |
| `sxml:element-name` | `(std markup sxml)` |
| `sxml:element?` | `(std markup sxml)` |
| `sxml:filter` | `(std markup sxml-path)` |
| `sxml:remove-attr` | `(std markup sxml)` |
| `sxml:select` | `(std markup sxml-path)` |
| `sxml:select-first` | `(std markup sxml-path)` |
| `sxml:set-attr` | `(std markup sxml)` |
| `sxml:text?` | `(std markup sxml)` |
| `sxpath` | `(std markup sxml-path)` |
| `symbol->keyword` | `(std misc symbol)` |
| `symbol-append` | `(std misc symbol)` |
| `symbol-comparator` | `(std srfi srfi-128)` |
| `symbol-db-add-module!` | `(std lsp symbols)` |
| `symbol-db-complete` | `(std lsp symbols)` |
| `symbol-db-init!` | `(std lsp symbols)` |
| `symbol-db-lookup` | `(std lsp symbols)` |
| `sync` | `(std event)`, `(std misc event)` |
| `sync/timeout` | `(std misc event)` |
| `syntax-match` | `(std match-syntax)` |
| `syntax-match*` | `(std match-syntax)` |
| `syntax-walk` | `(std staging)` |
| `system-map` | `(std component fiber)`, `(std component)` |
| `system-started?` | `(std component fiber)`, `(std component)` |
| `system-using` | `(std component fiber)`, `(std component)` |

### <a name="idx-sym"></a>sym

| Symbol | Modules |
| --- | --- |
| `%chan-enqueue-raw!` | `(std csp)` |
| `&actor-dead` | `(std error conditions)` |
| `&actor-timeout` | `(std error conditions)` |
| `&antidebug-error` | `(std os antidebug)` |
| `&cage-error` | `(std security cage)` |
| `&capability-violation` | `(std security capability)` |
| `&connection-refused` | `(std error conditions)` |
| `&connection-timeout` | `(std error conditions)` |
| `&context-condition` | `(std error context)` |
| `&db-connection-error` | `(std error conditions)` |
| `&db-constraint-violation` | `(std error conditions)` |
| `&db-query-error` | `(std error conditions)` |
| `&db-timeout` | `(std error conditions)` |
| `&diagnostic` | `(std error diagnostics)` |
| `&dns-failure` | `(std error conditions)` |
| `&fiber-cancelled` | `(std fiber)` |
| `&fiber-linked-crash` | `(std fiber)` |
| `&fiber-timeout` | `(std fiber)` |
| `&flow-violation` | `(std security flow)` |
| `&header-injection` | `(std security sanitize)` |
| `&integrity-error` | `(std os integrity)` |
| `&jerboa` | `(jerboa prelude safe)`, `(std error conditions)` |
| `&jerboa-actor` | `(std error conditions)` |
| `&jerboa-db` | `(std error conditions)` |
| `&jerboa-network` | `(std error conditions)` |
| `&jerboa-parse` | `(std error conditions)` |
| `&jerboa-resource` | `(std error conditions)` |
| `&jerboa-serialization` | `(std error conditions)` |
| `&jerboa-timeout` | `(std error conditions)` |
| `&landlock-error` | `(std os landlock-native)`, `(std os landlock)` |
| `&limit-exceeded` | `(std net timeout)` |
| `&mailbox-full` | `(std actor bounded)`, `(std error conditions)` |
| `&network-read-error` | `(std error conditions)` |
| `&network-write-error` | `(std error conditions)` |
| `&operation-timeout` | `(std safe-timeout)` |
| `&parse-depth-exceeded` | `(std error conditions)` |
| `&parse-invalid-input` | `(std error conditions)` |
| `&parse-size-exceeded` | `(std error conditions)` |
| `&path-traversal` | `(std security sanitize)` |
| `&posix-error` | `(std os posix)` |
| `&resource-already-closed` | `(std error conditions)` |
| `&resource-exhausted` | `(std error conditions)` |
| `&resource-leak` | `(std error conditions)` |
| `&sandbox-error` | `(jerboa prelude safe)`, `(std security sandbox)` |
| `&seccomp-error` | `(std os seccomp)` |
| `&serialize-size-exceeded` | `(std error conditions)` |
| `&ssh-auth-error` | `(std net ssh conditions)`, `(std net ssh)` |
| `&ssh-channel-error` | `(std net ssh conditions)`, `(std net ssh)` |
| `&ssh-connection-error` | `(std net ssh conditions)`, `(std net ssh)` |
| `&ssh-error` | `(std net ssh conditions)`, `(std net ssh)` |
| `&ssh-host-key-error` | `(std net ssh conditions)`, `(std net ssh)` |
| `&ssh-kex-error` | `(std net ssh conditions)`, `(std net ssh)` |
| `&ssh-protocol-error` | `(std net ssh conditions)`, `(std net ssh)` |
| `&ssh-sftp-error` | `(std net ssh conditions)`, `(std net ssh)` |
| `&ssh-timeout-error` | `(std net ssh conditions)`, `(std net ssh)` |
| `&supervision-failure` | `(std error conditions)` |
| `&taint-violation` | `(std security taint)` |
| `&tls-error` | `(std error conditions)` |
| `&unsafe-deserialize` | `(std error conditions)` |
| `&url-scheme-violation` | `(std security sanitize)` |
| `*byte-order*` | `(std binary)` |
| `*cluster-name*` | `(std actor distributed)` |
| `*csv-max-field-length*` | `(std text csv)` |
| `*csv-strict-quotes*` | `(std text csv)` |
| `*current-notebook*` | `(std repl notebook)` |
| `*current-recording*` | `(std dev debug)` |
| `*deadlock-detection-enabled*` | `(std concur deadlock)` |
| `*default-python-cmd*` | `(std python)` |
| `*default-seed*` | `(std proptest)` |
| `*default-send-timeout*` | `(std actor distributed)` |
| `*default-timeout*` | `(jerboa prelude safe)`, `(std safe-timeout)` |
| `*default-trials*` | `(std proptest)` |
| `*doctest-env*` | `(std doc)` |
| `*effect-handlers*` | `(std effect)` |
| `*enable-type-checking*` | `(std typed check)` |
| `*error-advice-enabled*` | `(std error-advice)` |
| `*fasl-allow-procedures*` | `(jerboa prelude safe)`, `(std safe-fasl)` |
| `*fasl-max-byte-size*` | `(jerboa prelude safe)`, `(std safe-fasl)` |
| `*fasl-max-object-count*` | `(jerboa prelude safe)`, `(std safe-fasl)` |
| `*forbidden-imports*` | `(std security import-audit)` |
| `*http-max-body-size*` | `(std net request)` |
| `*http-max-header-count*` | `(std net request)` |
| `*http-max-header-size*` | `(std net request)` |
| `*http-max-line-length*` | `(std net request)` |
| `*json-max-depth*` | `(std text json)` |
| `*json-max-string-length*` | `(std text json)` |
| `*max-block-comment-depth*` | `(jerboa reader)` |
| `*max-list-length*` | `(jerboa reader)` |
| `*max-message-size*` | `(std actor distributed)` |
| `*max-privsep-children*` | `(std security privsep)` |
| `*max-read-depth*` | `(jerboa reader)` |
| `*max-string-length*` | `(jerboa reader)` |
| `*max-symbol-length*` | `(jerboa reader)` |
| `*method-registry*` | `(std dev devirt)` |
| `*method-tables*` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `*odb*` | `(std odb)` |
| `*package-dir*` | `(jerboa registry)` |
| `*pgo-profiles*` | `(std dev pgo)` |
| `*pregexp-max-steps*` | `(std pregexp)` |
| `*registry-file*` | `(jerboa registry)` |
| `*resource-finalizer-log*` | `(std safe)` |
| `*rust-max-decompressed-size*` | `(std compress native-rust)` |
| `*safe-mode*` | `(jerboa prelude safe)`, `(std safe)` |
| `*sandbox-capsicum*` | `(std security sandbox)` |
| `*sandbox-landlock*` | `(jerboa prelude safe)`, `(std security sandbox)` |
| `*sandbox-seatbelt*` | `(std security sandbox)` |
| `*sandbox-seccomp*` | `(jerboa prelude safe)`, `(std security sandbox)` |
| `*sandbox-timeout*` | `(jerboa prelude safe)`, `(std security sandbox)` |
| `*schema-max-depth*` | `(std schema)` |
| `*struct-types*` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `*sxml-max-depth*` | `(std text xml)` |
| `*sxml-max-output-size*` | `(std text xml)` |
| `*taint-violations*` | `(std taint)` |
| `*test-suites*` | `(std test framework)` |
| `*trusted-modules*` | `(std security import-audit)` |
| `*type-errors*` | `(std typed infer)` |
| `*type-errors-fatal*` | `(std typed check)` |
| `*typed-mode*` | `(std typed)` |
| `*variant-registry*` | `(std variant)` |
| `*warn-unhandled-effects*` | `(std typed effects)` |
| `*watch-interval-ms*` | `(std build watch)` |
| `*ws-max-payload-size*` | `(std net websocket)` |
| `*yaml-max-depth*` | `(std text yaml)` |
| `*yaml-max-input-size*` | `(std text yaml)` |
| `*zlib-max-decompressed-size*` | `(std compress zlib)` |
| `->` | `(jerboa clojure)`, `(jerboa prelude)`, `(std contract)`, `(std foreign)`, ... (+2) |
| `->>` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std sugar)` |
| `->>?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std sugar)` |
| `->?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std sugar)` |
| `/keys` | `(thunderchez thunder-utils)` |
| `/optional` | `(thunderchez thunder-utils)` |
| `:` | `(jerboa clojure)`, `(jerboa prelude)`, `(std ergo)` |
| `:do` | `(std srfi srfi-42)` |
| `:f64` | `(std odb)` |
| `:integers` | `(std srfi srfi-42)` |
| `:let` | `(std srfi srfi-42)` |
| `:list` | `(std srfi srfi-42)` |
| `:mptr` | `(std odb)` |
| `:parallel` | `(std srfi srfi-42)` |
| `:range` | `(std srfi srfi-42)` |
| `:s64` | `(std odb)` |
| `:string` | `(std odb)`, `(std srfi srfi-42)` |
| `:until` | `(std srfi srfi-42)` |
| `:vector` | `(std srfi srfi-42)` |
| `:while` | `(std srfi srfi-42)` |
| `<!` | `(std csp clj)` |
| `<!!` | `(std csp clj)` |
| `<...>` | `(jerboa clojure)`, `(jerboa prelude)`, `(std gambit-compat)`, `(std prelude)`, ... (+1) |
| `<=?` | `(std srfi srfi-128)` |
| `<>` | `(jerboa clojure)`, `(jerboa prelude)`, `(std gambit-compat)`, `(std prelude)`, ... (+1) |
| `<?` | `(std srfi srfi-128)` |
| `<boolean>` | `(std clos)` |
| `<bytevector>` | `(std clos)` |
| `<char>` | `(std clos)` |
| `<class>` | `(std clos)` |
| `<complex>` | `(std clos)` |
| `<condition>` | `(std clos)` |
| `<eof>` | `(std clos)` |
| `<generic>` | `(std clos)` |
| `<hashtable>` | `(std clos)` |
| `<input-port>` | `(std clos)` |
| `<integer>` | `(std clos)` |
| `<keyword>` | `(std clos)` |
| `<list>` | `(std clos)` |
| `<method>` | `(std clos)` |
| `<null>` | `(std clos)` |
| `<number>` | `(std clos)` |
| `<object>` | `(std clos)` |
| `<output-port>` | `(std clos)` |
| `<pair>` | `(std clos)` |
| `<port>` | `(std clos)` |
| `<procedure>` | `(std clos)` |
| `<rational>` | `(std clos)` |
| `<real>` | `(std clos)` |
| `<record>` | `(std clos)` |
| `<string>` | `(std clos)` |
| `<symbol>` | `(std clos)` |
| `<top>` | `(std clos)` |
| `<vector>` | `(std clos)` |
| `<void>` | `(std clos)` |
| `==` | `(jerboa clojure)`, `(std logic)` |
| `=>` | `(std injest)` |
| `=?` | `(jerboa clojure)`, `(std clojure)`, `(std srfi srfi-128)` |
| `>!` | `(std csp clj)` |
| `>!!` | `(std csp clj)` |
| `>=?` | `(std srfi srfi-128)` |
| `>?` | `(std srfi srfi-128)` |
| `\x7C;\x3E;` | `(std pipeline)` |
| `~` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+5) |

### <a name="idx-t"></a>t

| Symbol | Modules |
| --- | --- |
| `TCSADRAIN` | `(std os posix)` |
| `TCSAFLUSH` | `(std os posix)` |
| `TCSANOW` | `(std os posix)` |
| `TYPE-BYTEVECTOR` | `(jerboa wasm values)` |
| `TYPE-CLOSURE` | `(jerboa wasm values)` |
| `TYPE-FLONUM` | `(jerboa wasm values)` |
| `TYPE-HASHTABLE` | `(jerboa wasm values)` |
| `TYPE-PAIR` | `(jerboa wasm values)` |
| `TYPE-RECORD` | `(jerboa wasm values)` |
| `TYPE-STRING` | `(jerboa wasm values)` |
| `TYPE-SYMBOL` | `(jerboa wasm values)` |
| `TYPE-VECTOR` | `(jerboa wasm values)` |
| `Traversable` | `(std typed hkt)` |
| `tab-to` | `(std srfi srfi-159)` |
| `table->list` | `(std table)` |
| `table-add-row!` | `(std table)` |
| `table-aggregate` | `(std table)` |
| `table-column` | `(std table)` |
| `table-column-names` | `(std table)` |
| `table-columns` | `(std table)` |
| `table-drop` | `(std table)` |
| `table-from-alist` | `(std table)` |
| `table-from-rows` | `(std table)` |
| `table-group-by` | `(std table)` |
| `table-join` | `(std table)` |
| `table-print` | `(std table)` |
| `table-ref` | `(std table)` |
| `table-row` | `(std table)` |
| `table-row-count` | `(std table)` |
| `table-rows` | `(std table)` |
| `table-select` | `(std table)` |
| `table-sort-by` | `(std table)` |
| `table-take` | `(std table)` |
| `table-where` | `(std table)` |
| `table?` | `(std table)` |
| `tagged-fixnum` | `(jerboa wasm values)` |
| `tagged-value-tag` | `(std text edn)` |
| `tagged-value-value` | `(std text edn)` |
| `tagged-value?` | `(std text edn)` |
| `taint` | `(std security taint)`, `(std taint)` |
| `taint-class` | `(std security taint)` |
| `taint-deser` | `(std security taint)` |
| `taint-env` | `(std security taint)` |
| `taint-file` | `(std security taint)` |
| `taint-flow-report` | `(std taint)` |
| `taint-http` | `(std security taint)` |
| `taint-label-name` | `(std taint)` |
| `taint-label-severity` | `(std taint)` |
| `taint-label?` | `(std taint)` |
| `taint-labels` | `(std taint)` |
| `taint-net` | `(std security taint)` |
| `taint-value` | `(std security taint)` |
| `taint-violation-class` | `(std security taint)` |
| `taint-violation-sink` | `(std security taint)` |
| `taint-violation?` | `(std security taint)` |
| `tainted-string-append` | `(std security taint)` |
| `tainted-string-length` | `(std security taint)` |
| `tainted-string-ref` | `(std security taint)` |
| `tainted-substring` | `(std security taint)` |
| `tainted?` | `(std security taint)`, `(std taint)` |
| `take` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+5) |
| `take!` | `(std csp clj)`, `(std csp ops)`, `(std srfi srfi-1)` |
| `take-last` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)`, `(std prelude)` |
| `take-until` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `take-while` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)`, `(std srfi srfi-1)` |
| `take-while-xf` | `(std seq)` |
| `take-xf` | `(std seq)` |
| `taking` | `(std transducer)` |
| `taking-while` | `(std transducer)` |
| `tal-env-ref` | `(std markup tal)` |
| `tal-env-set!` | `(std markup tal)` |
| `tal-expand` | `(std markup tal)` |
| `tal-process` | `(std markup tal)` |
| `tap` | `(std csp clj)` |
| `tap!` | `(std csp ops)` |
| `target-arch-aarch64?` | `(jerboa cross)` |
| `target-arch-riscv64?` | `(jerboa cross)` |
| `target-arch-x86-64?` | `(jerboa cross)` |
| `target-linux-aarch64` | `(jerboa build)` |
| `target-linux-x64` | `(jerboa build)` |
| `target-macos-aarch64` | `(jerboa build)` |
| `target-macos-x64` | `(jerboa build)` |
| `target-os-linux?` | `(jerboa cross)` |
| `target-os-macos?` | `(jerboa cross)` |
| `target-os-windows?` | `(jerboa cross)` |
| `target-platform?` | `(std build cross)` |
| `task-await` | `(jerboa prelude safe)`, `(std concur structured)` |
| `task-cancel` | `(jerboa prelude safe)`, `(std concur structured)` |
| `task-done?` | `(jerboa prelude safe)`, `(std concur structured)` |
| `task-group-async` | `(std task)` |
| `task-group-cancel!` | `(std task)` |
| `task-group-cancel-tok` | `(std task)` |
| `task-group-spawn` | `(std task)` |
| `task-group?` | `(std task)` |
| `task-name` | `(jerboa prelude safe)`, `(std concur structured)` |
| `task-resources` | `(std concur)` |
| `task-result` | `(jerboa prelude safe)`, `(std concur structured)` |
| `task?` | `(jerboa prelude safe)`, `(std concur structured)` |
| `tc-apply` | `(std misc typeclass)` |
| `tc-check!` | `(std contract2)` |
| `tc-history` | `(std contract2)` |
| `tc-name` | `(std contract2)` |
| `tc-ref` | `(std misc typeclass)` |
| `tc-reset!` | `(std contract2)` |
| `tc-state` | `(std contract2)` |
| `tc-valid-operations` | `(std contract2)` |
| `tc-violated?` | `(std contract2)` |
| `tcp-accept` | `(jerboa prelude safe)`, `(std net ssl)`, `(std net tcp-raw)`, `(std net tcp)` |
| `tcp-accept-binary` | `(std net tcp)` |
| `tcp-close` | `(jerboa prelude safe)`, `(std net ssl)`, `(std net tcp-raw)`, `(std net tcp)` |
| `tcp-connect` | `(jerboa prelude safe)`, `(std net ssl)`, `(std net tcp-raw)`, `(std net tcp)` |
| `tcp-connect-binary` | `(std net tcp)` |
| `tcp-listen` | `(jerboa prelude safe)`, `(std net ssl)`, `(std net tcp-raw)`, `(std net tcp)` |
| `tcp-read` | `(jerboa prelude safe)`, `(std net ssl)`, `(std net tcp-raw)` |
| `tcp-read-all` | `(std net ssl)`, `(std net tcp-raw)` |
| `tcp-server-port` | `(std net tcp)` |
| `tcp-server?` | `(std net tcp)` |
| `tcp-set-timeout` | `(std net ssl)`, `(std net tcp-raw)` |
| `tcp-socket` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `tcp-write` | `(jerboa prelude safe)`, `(std net ssl)`, `(std net tcp-raw)` |
| `tcp-write-string` | `(jerboa prelude safe)`, `(std net ssl)`, `(std net tcp-raw)` |
| `tell` | `(std actor protocol)`, `(std actor)` |
| `template-compile` | `(std compiler pattern)`, `(std text template)` |
| `template-env-ref` | `(std text template)` |
| `template-env-set!` | `(std text template)` |
| `template-escape-html` | `(std text template)` |
| `template-render` | `(std text template)` |
| `template-render-file` | `(std text template)` |
| `template-substitute*` | `(std compiler pattern)` |
| `temporary-file-directory` | `(std os temporaries)` |
| `tenth` | `(std srfi srfi-1)` |
| `term-args` | `(std rewrite)` |
| `term-head` | `(std rewrite)` |
| `term?` | `(std rewrite)` |
| `terminal-height` | `(std misc terminal)` |
| `terminal-width` | `(std misc terminal)` |
| `test-begin!` | `(std test)` |
| `test-case` | `(std test framework)`, `(std test)` |
| `test-equal` | `(std test framework)` |
| `test-error` | `(std test framework)` |
| `test-false` | `(std test framework)` |
| `test-not-equal` | `(std test framework)` |
| `test-report-summary!` | `(std test)` |
| `test-result` | `(std test)` |
| `test-suite` | `(std test)` |
| `test-true` | `(std test framework)` |
| `text` | `(std srfi srfi-135)` |
| `text->list` | `(std srfi srfi-135)` |
| `text->string` | `(std srfi srfi-135)` |
| `text-append` | `(std srfi srfi-135)` |
| `text-concatenate` | `(std srfi srfi-135)` |
| `text-contains` | `(std srfi srfi-135)` |
| `text-count` | `(std srfi srfi-135)` |
| `text-drop` | `(std srfi srfi-135)` |
| `text-filter` | `(std srfi srfi-135)` |
| `text-fold` | `(std srfi srfi-135)` |
| `text-fold-right` | `(std srfi srfi-135)` |
| `text-for-each` | `(std srfi srfi-135)` |
| `text-index` | `(std srfi srfi-135)` |
| `text-length` | `(std srfi srfi-135)` |
| `text-map` | `(std srfi srfi-135)` |
| `text-ref` | `(std srfi srfi-135)` |
| `text-remove` | `(std srfi srfi-135)` |
| `text-tabulate` | `(std srfi srfi-135)` |
| `text-take` | `(std srfi srfi-135)` |
| `text?` | `(std srfi srfi-135)` |
| `textual-null?` | `(std srfi srfi-135)` |
| `textual?` | `(std srfi srfi-135)` |
| `third` | `(std srfi srfi-1)` |
| `this-source-directory` | `(std source)` |
| `this-source-file` | `(std source)` |
| `this-source-location` | `(std source)` |
| `thread-count` | `(std debug threads)` |
| `thread-done?` | `(jerboa core)`, `(std misc thread)` |
| `thread-interrupt!` | `(jerboa core)`, `(std gambit-compat)` |
| `thread-join!` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `thread-list` | `(std debug threads)` |
| `thread-local-marker?` | `(std concur)` |
| `thread-mailbox-next` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `thread-name` | `(jerboa core)`, `(std debug threads)`, `(std gambit-compat)`, `(std misc thread)` |
| `thread-pool-stop!` | `(std concur util)` |
| `thread-pool-submit!` | `(std concur util)` |
| `thread-pool-worker-count` | `(std concur util)` |
| `thread-pool?` | `(std concur util)` |
| `thread-receive` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `thread-report` | `(std debug threads)` |
| `thread-safety-of` | `(std concur)` |
| `thread-send` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `thread-sleep!` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `thread-specific` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `thread-specific-set!` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `thread-start!` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `thread-state` | `(std debug threads)` |
| `thread-terminate!` | `(jerboa core)`, `(std gambit-compat)` |
| `thread-yield!` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `thread?` | `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)` |
| `time->seconds` | `(jerboa core)`, `(std gambit-compat)`, `(std srfi srfi-19)` |
| `time->string` | `(jerboa clojure)`, `(jerboa prelude)`, `(std datetime)`, `(std prelude)` |
| `time-call` | `(std dev profile)` |
| `time-difference` | `(std srfi srfi-19)` |
| `time-duration` | `(std srfi srfi-19)` |
| `time-it` | `(std misc profile)`, `(std profile)`, `(std time)` |
| `time-monotonic` | `(std srfi srfi-19)` |
| `time-nanosecond` | `(std srfi srfi-19)` |
| `time-second` | `(std srfi srfi-19)` |
| `time-thunk` | `(std dev profile)` |
| `time-type` | `(std srfi srfi-19)` |
| `time-utc` | `(std srfi srfi-19)` |
| `time-utc->date` | `(std srfi srfi-19)` |
| `time-window-add!` | `(std stream window)` |
| `time-window-flush!` | `(std stream window)` |
| `time?` | `(std srfi srfi-19)` |
| `timed-eval` | `(std engine)` |
| `timeout` | `(std csp clj)`, `(std csp select)` |
| `timeout-channel` | `(std csp select)` |
| `timeout-config-connect` | `(std net timeout)` |
| `timeout-config-idle` | `(std net timeout)` |
| `timeout-config-read` | `(std net timeout)` |
| `timeout-config-write` | `(std net timeout)` |
| `timeout-config?` | `(std net timeout)` |
| `timeout-error-operation` | `(std error conditions)` |
| `timeout-error-seconds` | `(std error conditions)` |
| `timeout-error?` | `(jerboa prelude safe)`, `(std error conditions)`, `(std safe)` |
| `timeout-evt` | `(std event)` |
| `timeout-fiber-id` | `(std fiber)` |
| `timeout-value` | `(std misc timeout)` |
| `timeout-value-message` | `(std misc timeout)` |
| `timeout-value?` | `(std misc timeout)` |
| `timer-event` | `(std misc event)` |
| `timing-safe-equal?` | `(std crypto compare)` |
| `timing-safe-string=?` | `(std crypto compare)` |
| `tls-accept` | `(std net tls)` |
| `tls-close` | `(std net tls)` |
| `tls-config-ca-file` | `(std net tls)` |
| `tls-config-cert-file` | `(std net tls)` |
| `tls-config-cipher-suites` | `(std net tls)` |
| `tls-config-key-file` | `(std net tls)` |
| `tls-config-min-version` | `(std net tls)` |
| `tls-config-verify-hostname?` | `(std net tls)` |
| `tls-config-verify-peer?` | `(std net tls)` |
| `tls-config-with` | `(std net tls)` |
| `tls-config?` | `(std net tls)` |
| `tls-connect` | `(std net tls)` |
| `tls-error-reason` | `(std error conditions)` |
| `tls-error?` | `(std error conditions)` |
| `tls-listen` | `(std net tls)` |
| `tls-read` | `(std net tls)` |
| `tls-write` | `(std net tls)` |
| `tmap-delete!` | `(std pmap)` |
| `tmap-has?` | `(std pmap)` |
| `tmap-ref` | `(std pmap)` |
| `tmap-set!` | `(std pmap)` |
| `tmap-size` | `(std pmap)` |
| `to-chan` | `(std csp clj)`, `(std csp ops)` |
| `toggle` | `(std csp clj)` |
| `toggle!` | `(std csp mix)`, `(std csp ops)` |
| `token-bucket-consume!` | `(std net rate)` |
| `token-bucket-tokens` | `(std net rate)` |
| `token-bucket-try!` | `(std net rate)` |
| `token-bucket?` | `(std net rate)` |
| `token-categories` | `(std misc highlight)` |
| `token-column` | `(std parser deflexer)` |
| `token-line` | `(std parser deflexer)` |
| `token-type` | `(std parser deflexer)` |
| `token-value` | `(std parser deflexer)` |
| `token?` | `(std parser deflexer)` |
| `toml->hash-table` | `(std text toml)` |
| `top-k-hotspots` | `(std debug flamegraph)` |
| `topological-sort` | `(std build)`, `(std misc dag)` |
| `trace-call!` | `(std dev debug)` |
| `trace-calls` | `(std trace)` |
| `trace-define` | `(std trace)` |
| `trace-error!` | `(std dev debug)` |
| `trace-event!` | `(std dev debug)` |
| `trace-fn` | `(std debug timetravel)` |
| `trace-id` | `(std span)` |
| `trace-imports` | `(jerboa build)` |
| `trace-lambda` | `(std trace)` |
| `trace-let` | `(std trace)` |
| `trace-output-port` | `(std trace)` |
| `trace-return!` | `(std dev debug)` |
| `tracer?` | `(std span)` |
| `track-allocation` | `(std debug memleak)` |
| `tracked-closure?` | `(std debug closure-inspect)` |
| `tracked-lock!` | `(std concur)` |
| `tracked-mutex?` | `(std concur)` |
| `tracked-unlock!` | `(std concur)` |
| `transduce` | `(std seq)`, `(std transducer)` |
| `transducer?` | `(std transducer)` |
| `transform` | `(std specter)` |
| `transient` | `(jerboa clojure)`, `(std clojure)`, `(std pvec)` |
| `transient-append!` | `(std pvec)` |
| `transient-map` | `(std pmap)` |
| `transient-map?` | `(std pmap)` |
| `transient-ref` | `(std pvec)` |
| `transient-set` | `(std pset)` |
| `transient-set!` | `(std pvec)` |
| `transient-set?` | `(std pset)` |
| `transient?` | `(jerboa clojure)`, `(std clojure)`, `(std pvec)` |
| `transit->string` | `(jerboa clojure)`, `(std transit)` |
| `transit-decode` | `(jerboa clojure)`, `(std transit)` |
| `transit-encode` | `(jerboa clojure)`, `(std transit)` |
| `transit-instant` | `(jerboa clojure)`, `(std transit)` |
| `transit-instant?` | `(jerboa clojure)`, `(std transit)` |
| `transit-keyword` | `(jerboa clojure)`, `(std transit)` |
| `transit-keyword?` | `(jerboa clojure)`, `(std transit)` |
| `transit-read` | `(jerboa clojure)`, `(std transit)` |
| `transit-symbol` | `(jerboa clojure)`, `(std transit)` |
| `transit-symbol?` | `(jerboa clojure)`, `(std transit)` |
| `transit-uri` | `(jerboa clojure)`, `(std transit)` |
| `transit-uri?` | `(jerboa clojure)`, `(std transit)` |
| `transit-uuid` | `(jerboa clojure)`, `(std transit)` |
| `transit-uuid?` | `(jerboa clojure)`, `(std transit)` |
| `transit-write` | `(jerboa clojure)`, `(std transit)` |
| `translate-brackets` | `(jerboa translator)` |
| `translate-define-values` | `(jerboa translator)` |
| `translate-defrules` | `(jerboa translator)` |
| `translate-defstruct` | `(jerboa translator)` |
| `translate-export` | `(jerboa translator)` |
| `translate-file` | `(jerboa translator)` |
| `translate-for-loops` | `(jerboa translator)` |
| `translate-gerbil-void` | `(jerboa translator)` |
| `translate-hash-bang` | `(jerboa translator)` |
| `translate-hash-operations` | `(jerboa translator)` |
| `translate-imports` | `(jerboa translator)` |
| `translate-keywords` | `(jerboa translator)` |
| `translate-let-hash` | `(jerboa translator)` |
| `translate-match-patterns` | `(jerboa translator)` |
| `translate-method-dispatch` | `(jerboa translator)` |
| `translate-package-to-library` | `(jerboa translator)` |
| `translate-parameterize` | `(jerboa translator)` |
| `translate-spawn-forms` | `(jerboa translator)` |
| `translate-try-catch` | `(jerboa translator)` |
| `translate-using` | `(jerboa translator)` |
| `transport-remote-send!` | `(std actor transport)` |
| `transport-shutdown!` | `(std actor transport)` |
| `transport-state-algorithms` | `(std net ssh transport)` |
| `transport-state-algorithms-set!` | `(std net ssh transport)` |
| `transport-state-bytes-received` | `(std net ssh transport)` |
| `transport-state-bytes-received-set!` | `(std net ssh transport)` |
| `transport-state-bytes-sent` | `(std net ssh transport)` |
| `transport-state-bytes-sent-set!` | `(std net ssh transport)` |
| `transport-state-client-kexinit` | `(std net ssh transport)` |
| `transport-state-client-kexinit-set!` | `(std net ssh transport)` |
| `transport-state-client-version` | `(std net ssh transport)` |
| `transport-state-fd` | `(std net ssh transport)` |
| `transport-state-packets-received` | `(std net ssh transport)` |
| `transport-state-packets-received-set!` | `(std net ssh transport)` |
| `transport-state-packets-sent` | `(std net ssh transport)` |
| `transport-state-packets-sent-set!` | `(std net ssh transport)` |
| `transport-state-recv-cipher` | `(std net ssh transport)` |
| `transport-state-recv-cipher-set!` | `(std net ssh transport)` |
| `transport-state-recv-mac-key` | `(std net ssh transport)` |
| `transport-state-recv-mac-key-set!` | `(std net ssh transport)` |
| `transport-state-recv-seqno` | `(std net ssh transport)` |
| `transport-state-recv-seqno-set!` | `(std net ssh transport)` |
| `transport-state-send-cipher` | `(std net ssh transport)` |
| `transport-state-send-cipher-set!` | `(std net ssh transport)` |
| `transport-state-send-mac-key` | `(std net ssh transport)` |
| `transport-state-send-mac-key-set!` | `(std net ssh transport)` |
| `transport-state-send-seqno` | `(std net ssh transport)` |
| `transport-state-send-seqno-set!` | `(std net ssh transport)` |
| `transport-state-server-kexinit` | `(std net ssh transport)` |
| `transport-state-server-kexinit-set!` | `(std net ssh transport)` |
| `transport-state-server-version` | `(std net ssh transport)` |
| `transport-state-session-id` | `(std net ssh transport)` |
| `transport-state-session-id-set!` | `(std net ssh transport)` |
| `transport-state?` | `(std net ssh transport)` |
| `traversal?` | `(std lens)` |
| `traverse-over` | `(std lens)` |
| `traverse-view` | `(std lens)` |
| `tree-shake-imports` | `(jerboa build)` |
| `trie-autocomplete` | `(std misc trie)` |
| `trie-delete!` | `(std misc trie)` |
| `trie-insert!` | `(std misc trie)` |
| `trie-prefix-search` | `(std misc trie)` |
| `trie-search` | `(std misc trie)` |
| `trie-size` | `(std misc trie)` |
| `trie-starts-with?` | `(std misc trie)` |
| `trie-words` | `(std misc trie)` |
| `trie?` | `(std misc trie)` |
| `trim` | `(std clojure string)` |
| `trim-newline` | `(std clojure string)` |
| `triml` | `(std clojure string)` |
| `trimmed` | `(std srfi srfi-159)` |
| `trimmed/both` | `(std srfi srfi-159)` |
| `trimmed/lazy` | `(std srfi srfi-159)` |
| `trimmed/right` | `(std srfi srfi-159)` |
| `trimr` | `(std clojure string)` |
| `true?` | `(jerboa clojure)`, `(std clojure)` |
| `truncate-quotient` | `(std gambit-compat)`, `(std srfi srfi-141)` |
| `truncate-remainder` | `(std gambit-compat)`, `(std srfi srfi-141)` |
| `truncate/` | `(std srfi srfi-141)` |
| `try` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+4) |
| `try->result` | `(std misc result)` |
| `try-custom-printers` | `(std repl middleware)` |
| `try-result` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `try-result*` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `tset-add!` | `(std pset)` |
| `tset-contains?` | `(std pset)` |
| `tset-remove!` | `(std pset)` |
| `tset-size` | `(std pset)` |
| `ttf-byte-swapped-unicode` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-close-font` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-font-ascent` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-font-descent` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-font-face-family-name` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-font-face-is-fixed-width` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-font-face-style-name` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-font-faces` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-font-height` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-font-line-skip` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-get-font-hinting` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-get-font-kerning` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-get-font-outline` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-get-font-style` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-glyph-is-provided` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-glyph-metrics` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-init` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-linked-version` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-open-font` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-open-font-index` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-open-font-index-rw` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-open-font-rw` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-quit` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-set-font-hinting` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-set-font-kerning` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-set-font-outline` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-set-font-style` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-size-text` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-size-unicode` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-size-ut-f8` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `ttf-was-init` | `(std ffi sdl2 ttf)`, `(thunderchez sdl2 ttf)` |
| `tty-size` | `(std os tty)` |
| `tty?` | `(std misc process)`, `(std os tty)` |
| `tumbling-window?` | `(std stream window)` |
| `tvar-get` | `(std concur stm)` |
| `tvar-read` | `(std stm)` |
| `tvar-ref` | `(std stm)` |
| `tvar-set!` | `(std concur stm)` |
| `tvar-write!` | `(std stm)` |
| `tvar?` | `(std concur stm)`, `(std stm)` |
| `tx-delete!` | `(std mvcc)` |
| `tx-get` | `(std mvcc)` |
| `tx-put!` | `(std mvcc)` |
| `type-aliases` | `(std macro-types)` |
| `type-check-file` | `(std typed check)` |
| `type-env->list` | `(std typed env)` |
| `type-env-bind!` | `(std typed env)` |
| `type-env-extend` | `(std typed env)` |
| `type-env-lookup` | `(std typed env)` |
| `type-env?` | `(std typed env)` |
| `type-error` | `(std errors)` |
| `type-error-actual` | `(std typed infer)` |
| `type-error-expected` | `(std errors)`, `(std typed infer)` |
| `type-error-got` | `(std errors)` |
| `type-error-got-type` | `(std errors)` |
| `type-error-location` | `(std typed infer)` |
| `type-error-message` | `(std typed infer)` |
| `type-error-who` | `(std errors)` |
| `type-error?` | `(std errors)`, `(std typed infer)` |
| `type-of` | `(std macro-types)` |
| `type-predicate` | `(std typed)` |
| `type-profile` | `(std specialize)` |
| `typeclass-dispatch` | `(std misc typeclass)` |
| `typeclass-instance-of?` | `(std misc typeclass)` |
| `typeclass-instance?` | `(std misc typeclass)` |
| `typed-with-handler` | `(std typed effect-typing)` |

### <a name="idx-u"></a>u

| Symbol | Modules |
| --- | --- |
| `Union` | `(std typed advanced)` |
| `u16` | `(std binary)` |
| `u16vector` | `(std srfi srfi-160)` |
| `u16vector->list` | `(std srfi srfi-160)` |
| `u16vector-append` | `(std srfi srfi-160)` |
| `u16vector-copy` | `(std srfi srfi-160)` |
| `u16vector-length` | `(std srfi srfi-160)` |
| `u16vector-ref` | `(std srfi srfi-160)` |
| `u16vector-set!` | `(std srfi srfi-160)` |
| `u16vector?` | `(std srfi srfi-160)` |
| `u32` | `(std binary)` |
| `u32vector` | `(std srfi srfi-160)` |
| `u32vector->list` | `(std srfi srfi-160)` |
| `u32vector-append` | `(std srfi srfi-160)` |
| `u32vector-copy` | `(std srfi srfi-160)` |
| `u32vector-length` | `(std srfi srfi-160)` |
| `u32vector-ref` | `(std srfi srfi-160)` |
| `u32vector-set!` | `(std srfi srfi-160)` |
| `u32vector?` | `(std srfi srfi-160)` |
| `u64` | `(std binary)` |
| `u64vector` | `(std srfi srfi-160)` |
| `u64vector->list` | `(std srfi srfi-160)` |
| `u64vector-append` | `(std srfi srfi-160)` |
| `u64vector-copy` | `(std srfi srfi-160)` |
| `u64vector-length` | `(std srfi srfi-160)` |
| `u64vector-ref` | `(std srfi srfi-160)` |
| `u64vector-set!` | `(std srfi srfi-160)` |
| `u64vector?` | `(std srfi srfi-160)` |
| `u8` | `(std binary)` |
| `u8vector` | `(jerboa core)`, `(std gambit-compat)`, `(std srfi srfi-160)` |
| `u8vector->base64-string` | `(std text base64)` |
| `u8vector->hex-string` | `(std text hex)` |
| `u8vector->list` | `(jerboa core)`, `(std gambit-compat)`, `(std srfi srfi-160)` |
| `u8vector->uint` | `(std misc bytes)` |
| `u8vector-and` | `(std misc bytes)` |
| `u8vector-append` | `(std gambit-compat)`, `(std srfi srfi-160)` |
| `u8vector-copy` | `(std gambit-compat)`, `(std srfi srfi-160)` |
| `u8vector-copy!` | `(std gambit-compat)` |
| `u8vector-ior` | `(std misc bytes)` |
| `u8vector-length` | `(jerboa core)`, `(std gambit-compat)`, `(std srfi srfi-160)` |
| `u8vector-ref` | `(jerboa core)`, `(std gambit-compat)`, `(std srfi srfi-160)` |
| `u8vector-set!` | `(jerboa core)`, `(std gambit-compat)`, `(std srfi srfi-160)` |
| `u8vector-xor` | `(std misc bytes)` |
| `u8vector-xor!` | `(std misc bytes)` |
| `u8vector-zero!` | `(std misc bytes)` |
| `u8vector?` | `(std gambit-compat)`, `(std srfi srfi-160)` |
| `ucs-range->char-set` | `(std srfi srfi-14)` |
| `udp-bind` | `(std net udp)` |
| `udp-close-socket` | `(std net udp)` |
| `udp-open-socket` | `(std net udp)` |
| `udp-packet` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `udp-receive-from` | `(std net udp)` |
| `udp-send-to` | `(std net udp)` |
| `udp-set-broadcast!` | `(std net udp)` |
| `udp-set-timeout!` | `(std net udp)` |
| `udp-socket` | `(std ffi sdl2 net)`, `(thunderchez sdl2 net)` |
| `uint->u8vector` | `(std misc bytes)` |
| `uint16` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `uint16-be` | `(std misc binary-type)` |
| `uint16-le` | `(std misc binary-type)` |
| `uint32` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `uint32-be` | `(std misc binary-type)` |
| `uint32-le` | `(std misc binary-type)` |
| `uint64` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `uint8` | `(std ffi sdl2)`, `(std misc binary-type)`, `(thunderchez sdl2)` |
| `unadvise` | `(std misc advice)` |
| `unbound-error` | `(std errors)` |
| `unbound-error-name` | `(std errors)` |
| `unbound-error-suggestions` | `(std errors)` |
| `unbound-error?` | `(std errors)` |
| `unbox` | `(std gambit-compat)` |
| `underline` | `(std cli style)`, `(std misc terminal)` |
| `unified-alts!` | `(std csp fiber-chan)` |
| `unified-chan-close!` | `(std csp fiber-chan)` |
| `unified-chan-closed?` | `(std csp fiber-chan)` |
| `unified-chan-get!` | `(std csp fiber-chan)` |
| `unified-chan-put!` | `(std csp fiber-chan)` |
| `unified-chan-try-get` | `(std csp fiber-chan)` |
| `unified-chan-try-put!` | `(std csp fiber-chan)` |
| `unified-timeout` | `(std csp fiber-chan)` |
| `unify-types` | `(std typed infer)` |
| `union` | `(jerboa clojure)`, `(std clojure)` |
| `unique` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+3) |
| `unless/t` | `(std typed advanced)` |
| `unlock-object` | `(std ftype)` |
| `unmix` | `(std csp clj)` |
| `unmix!` | `(std csp mix)`, `(std csp ops)` |
| `unmix-all` | `(std csp clj)` |
| `unmix-all!` | `(std csp mix)`, `(std csp ops)` |
| `unquote-stage` | `(std staging2)` |
| `unreduced` | `(std transducer)` |
| `unregister!` | `(std actor registry)`, `(std actor)` |
| `unregister-module!` | `(std dev reload)` |
| `unregister-optimization-pass!` | `(std compiler passes)` |
| `unregister-repl-command!` | `(std repl middleware)` |
| `unregister-safe-record-type!` | `(jerboa prelude safe)`, `(std safe-fasl)` |
| `unregister-waiting!` | `(std concur deadlock)` |
| `unregister-world!` | `(std image)` |
| `unsafe-deserialize-type-name` | `(std error conditions)` |
| `unsafe-deserialize?` | `(std error conditions)` |
| `unsetenv` | `(std os env)` |
| `unsigned-8*` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `unsub` | `(std csp clj)` |
| `unsub!` | `(std csp ops)` |
| `unsub-all` | `(std csp clj)` |
| `unsub-all!` | `(std csp ops)` |
| `untaint` | `(std security taint)`, `(std taint)` |
| `untaint-with` | `(std taint)` |
| `untap` | `(std csp clj)` |
| `untap!` | `(std csp ops)` |
| `untap-all` | `(std csp clj)` |
| `untap-all!` | `(std csp ops)` |
| `until` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+3) |
| `untrace` | `(std trace)` |
| `untrack-allocation` | `(std debug memleak)` |
| `unwind-protect` | `(jerboa clojure)`, `(jerboa prelude)`, `(std gambit-compat)`, `(std sugar)` |
| `unwrap` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `unwrap-err` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `unwrap-or` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `unwrap-or-else` | `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std result)` |
| `unzip1` | `(std srfi srfi-1)` |
| `unzip2` | `(std srfi srfi-1)` |
| `unzip3` | `(std srfi srfi-1)` |
| `unzip4` | `(std srfi srfi-1)` |
| `unzip5` | `(std srfi srfi-1)` |
| `update` | `(jerboa clojure)`, `(std clojure)` |
| `update-in` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc nested)` |
| `update-in!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc nested)` |
| `upper-case` | `(std clojure string)` |
| `uri->string` | `(std net uri)` |
| `uri-decode` | `(std net uri)` |
| `uri-encode` | `(std net uri)` |
| `uri-fragment` | `(std net uri)` |
| `uri-host` | `(std net uri)` |
| `uri-parse` | `(std net uri)` |
| `uri-path` | `(std net uri)` |
| `uri-port` | `(std net uri)` |
| `uri-query` | `(std net uri)` |
| `uri-scheme` | `(std net uri)` |
| `uri-userinfo` | `(std net uri)` |
| `url-encode` | `(std net request)` |
| `url-parts-host` | `(std net request)` |
| `url-parts-path` | `(std net request)` |
| `url-parts-port` | `(std net request)` |
| `url-parts-scheme` | `(std net request)` |
| `url-scheme-violation?` | `(std security sanitize)` |
| `usb-bulk-read` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-bulk-write` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-claim-interface` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-close` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-control-transfer` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-device` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-device-handle` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-device?` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-display-device-list` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-exit` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-find-vid-pid` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-get-bus-number` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-get-device` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-get-device-descriptor` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-get-device-list` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-get-port-number` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-get-port-numbers` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-init` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-interrupt-read` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-interrupt-write` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-log-level-enum` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-log-level-index` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-log-level-ref` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-open` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-release-interface` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-set-debug` | `(std ffi usb)`, `(thunderchez usb)` |
| `usb-strerror` | `(std ffi usb)`, `(thunderchez usb)` |
| `user-info` | `(jerboa core)`, `(std gambit-compat)` |
| `user-info-home` | `(jerboa core)`, `(std gambit-compat)` |
| `user-input-label` | `(std taint)` |
| `user-name` | `(jerboa core)`, `(std gambit-compat)` |
| `using` | `(jerboa clojure)`, `(jerboa prelude)`, `(std ergo)` |
| `utf16->string` | `(std text utf16)` |
| `utf16-bom?` | `(std text utf16)` |
| `utf16-length` | `(std text utf16)` |
| `utf16be->string` | `(std text utf16)` |
| `utf16le->string` | `(std text utf16)` |
| `utf32->string` | `(std text utf32)` |
| `utf32be->string` | `(std text utf32)` |
| `utf32le->string` | `(std text utf32)` |
| `utf8->string` | `(std text utf8)` |
| `utf8-decode` | `(std text utf8)` |
| `utf8-encode` | `(std text utf8)` |
| `utf8-length` | `(std text utf8)` |
| `uuid-string` | `(std misc uuid)` |

### <a name="idx-v"></a>v

| Symbol | Modules |
| --- | --- |
| `VAL->NIL` | `(std specter)` |
| `VECTOR-HEADER-PAYLOAD` | `(jerboa wasm values)` |
| `v-and` | `(std misc validate)` |
| `v-boolean` | `(std misc validate)` |
| `v-each` | `(std misc validate)` |
| `v-exact-length` | `(std misc validate)` |
| `v-fail` | `(std misc validate)` |
| `v-field` | `(std misc validate)` |
| `v-integer` | `(std misc validate)` |
| `v-list` | `(std misc validate)` |
| `v-max` | `(std misc validate)` |
| `v-max-length` | `(std misc validate)` |
| `v-member` | `(std misc validate)` |
| `v-min` | `(std misc validate)` |
| `v-min-length` | `(std misc validate)` |
| `v-non-negative` | `(std misc validate)` |
| `v-not-empty` | `(std misc validate)` |
| `v-not-member` | `(std misc validate)` |
| `v-number` | `(std misc validate)` |
| `v-ok` | `(std misc validate)` |
| `v-or` | `(std misc validate)` |
| `v-pair` | `(std misc validate)` |
| `v-pattern` | `(std misc validate)` |
| `v-positive` | `(std misc validate)` |
| `v-predicate` | `(std misc validate)` |
| `v-range` | `(std misc validate)` |
| `v-record` | `(std misc validate)` |
| `v-required` | `(std misc validate)` |
| `v-string` | `(std misc validate)` |
| `v-symbol` | `(std misc validate)` |
| `v-type` | `(std misc validate)` |
| `va-list` | `(std ffi sdl2)`, `(thunderchez sdl2)` |
| `validate` | `(std misc validate)` |
| `validate-config` | `(std config)` |
| `validate-json` | `(std text json-schema)` |
| `validate-musl-setup` | `(jerboa build musl)` |
| `validate-superclass` | `(std clos)` |
| `validation-error-message` | `(std schema)` |
| `validation-error-path` | `(std schema)` |
| `validation-error-value` | `(std schema)` |
| `validation-error?` | `(std schema)` |
| `validation-errors` | `(std text json-schema)` |
| `validation-result?` | `(std text json-schema)` |
| `validation-valid?` | `(std text json-schema)` |
| `vals` | `(jerboa clojure)`, `(std clojure)` |
| `value->type-string` | `(std repl)` |
| `value-accessor-forms` | `(jerboa wasm values)` |
| `value-constructor-forms` | `(jerboa wasm values)` |
| `value-global-forms` | `(jerboa wasm values)` |
| `value-memory-forms` | `(jerboa wasm values)` |
| `value-predicate-forms` | `(jerboa wasm values)` |
| `value-tag-forms` | `(jerboa wasm values)` |
| `values->list` | `(std values)` |
| `values-ref` | `(std values)` |
| `variant-tags` | `(std variant)` |
| `variant?` | `(std variant)` |
| `vary-meta` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc meta)` |
| `vclock->alist` | `(std actor crdt)` |
| `vclock-concurrent?` | `(std actor crdt)` |
| `vclock-get` | `(std actor crdt)` |
| `vclock-happens-before?` | `(std actor crdt)` |
| `vclock-increment!` | `(std actor crdt)` |
| `vclock-merge!` | `(std actor crdt)` |
| `vclock?` | `(std actor crdt)` |
| `vderef` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc atom)` |
| `vec` | `(jerboa clojure)`, `(std clojure)` |
| `vector*` | `(jerboa clojure)`, `(std clojure)` |
| `vector->generator` | `(std srfi srfi-121)`, `(std srfi srfi-158)` |
| `vector->ivec` | `(std immutable)` |
| `vector-accumulator` | `(std srfi srfi-158)` |
| `vector-any` | `(std misc vector-more)`, `(std srfi srfi-133)`, `(std srfi srfi-43)` |
| `vector-append` | `(std srfi srfi-133)`, `(std srfi srfi-43)` |
| `vector-concatenate` | `(std srfi srfi-133)`, `(std srfi srfi-43)` |
| `vector-copy` | `(std srfi srfi-133)` |
| `vector-copy!` | `(std srfi srfi-43)` |
| `vector-copy*` | `(std misc vector-more)` |
| `vector-count` | `(std misc vector-more)`, `(std srfi srfi-133)`, `(std srfi srfi-43)` |
| `vector-cumulate` | `(std srfi srfi-133)` |
| `vector-ec` | `(std srfi srfi-42)` |
| `vector-empty?` | `(std srfi srfi-43)` |
| `vector-every` | `(std misc vector-more)`, `(std srfi srfi-133)`, `(std srfi srfi-43)` |
| `vector-filter` | `(std misc vector-more)` |
| `vector-fold` | `(std misc vector-more)`, `(std srfi srfi-133)`, `(std srfi srfi-43)` |
| `vector-fold-right` | `(std srfi srfi-133)`, `(std srfi srfi-43)` |
| `vector-for-each` | `(std srfi srfi-133)`, `(std srfi srfi-43)` |
| `vector-index` | `(std misc vector-more)`, `(std srfi srfi-133)`, `(std srfi srfi-43)` |
| `vector-index-right` | `(std srfi srfi-133)`, `(std srfi srfi-43)` |
| `vector-map` | `(std srfi srfi-133)` |
| `vector-map!` | `(std srfi srfi-43)` |
| `vector-merge` | `(std srfi srfi-132)` |
| `vector-merge!` | `(std srfi srfi-132)` |
| `vector-ref-lens` | `(std lens)` |
| `vector-reverse!` | `(std srfi srfi-133)`, `(std srfi srfi-43)` |
| `vector-reverse-copy` | `(std srfi srfi-133)` |
| `vector-reverse-copy!` | `(std srfi srfi-43)` |
| `vector-skip` | `(std srfi srfi-133)`, `(std srfi srfi-43)` |
| `vector-skip-right` | `(std srfi srfi-133)`, `(std srfi srfi-43)` |
| `vector-sort` | `(std srfi srfi-132)` |
| `vector-sort!` | `(std srfi srfi-132)` |
| `vector-sorted?` | `(std srfi srfi-132)` |
| `vector-stable-sort` | `(std srfi srfi-132)` |
| `vector-swap!` | `(std srfi srfi-133)`, `(std srfi srfi-43)` |
| `vector-unfold` | `(std srfi srfi-133)`, `(std srfi srfi-43)` |
| `vector-unfold-right` | `(std srfi srfi-133)`, `(std srfi srfi-43)` |
| `vector-zipper` | `(std zipper)` |
| `verbosef` | `(std logger)` |
| `verification-result-actual` | `(std build verify)` |
| `verification-result-expected` | `(std build verify)` |
| `verification-result-name` | `(std build verify)` |
| `verification-result-status` | `(std build verify)` |
| `verification-result?` | `(std build verify)` |
| `verify-all-dependencies` | `(std build verify)` |
| `verify-audit-chain` | `(std security audit)` |
| `verify-build` | `(std build reproducible)` |
| `verify-delegation-token` | `(std actor cluster-security)` |
| `verify-dependency` | `(std build verify)` |
| `verify-lockfile!` | `(std build verify)` |
| `verify-message-auth` | `(std actor cluster-security)` |
| `verify-provenance` | `(std build reproducible)` |
| `version->list` | `(jerboa pkg)` |
| `version-compare` | `(jerboa pkg)` |
| `version<?` | `(jerboa pkg)` |
| `version=?` | `(jerboa pkg)` |
| `version>=?` | `(jerboa pkg)` |
| `view` | `(std lens)` |
| `void` | `(jerboa runtime)` |
| `void?` | `(std gambit-compat)` |
| `volatile!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc atom)` |
| `volatile?` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc atom)` |
| `vreset!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc atom)` |
| `vswap!` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc atom)` |

### <a name="idx-w"></a>w

| Symbol | Modules |
| --- | --- |
| `WCONTINUED` | `(std os posix)` |
| `WEXITSTATUS` | `(std os posix)` |
| `WIFEXITED` | `(std os posix)` |
| `WIFSIGNALED` | `(std os posix)` |
| `WIFSTOPPED` | `(std os posix)` |
| `WNOHANG` | `(std os posix)` |
| `WSTOPSIG` | `(std os posix)` |
| `WTERMSIG` | `(std os posix)` |
| `WUNTRACED` | `(std os posix)` |
| `W_OK` | `(std os posix)` |
| `waiter-prompt-and-read` | `(std cafe)` |
| `waiter-prompt-string` | `(std cafe)` |
| `wake-fiber!` | `(std fiber)` |
| `walist->alist` | `(std misc walist)` |
| `walist-delete!` | `(std misc walist)` |
| `walist-keys` | `(std misc walist)` |
| `walist-length` | `(std misc walist)` |
| `walist-ref` | `(std misc walist)` |
| `walist-set!` | `(std misc walist)` |
| `walk-syntax` | `(std match-syntax)` |
| `walker` | `(std specter)` |
| `warn-and-continue` | `(std cli print-exit)` |
| `warnf` | `(std logger)` |
| `warning-prefix` | `(std cli style)` |
| `wasi-args-get` | `(std wasm wasi)` |
| `wasi-args-sizes-get` | `(std wasm wasi)` |
| `wasi-clock-time-get` | `(std wasm wasi)` |
| `wasi-clock/monotonic` | `(std wasm wasi)` |
| `wasi-clock/process-cputime` | `(std wasm wasi)` |
| `wasi-clock/realtime` | `(std wasm wasi)` |
| `wasi-env-args` | `(std wasm wasi)` |
| `wasi-env-env` | `(std wasm wasi)` |
| `wasi-env-preopens` | `(std wasm wasi)` |
| `wasi-env-stderr` | `(std wasm wasi)` |
| `wasi-env-stdin` | `(std wasm wasi)` |
| `wasi-env-stdout` | `(std wasm wasi)` |
| `wasi-env?` | `(std wasm wasi)` |
| `wasi-environ-get` | `(std wasm wasi)` |
| `wasi-errno/badf` | `(std wasm wasi)` |
| `wasi-errno/inval` | `(std wasm wasi)` |
| `wasi-errno/io` | `(std wasm wasi)` |
| `wasi-errno/noent` | `(std wasm wasi)` |
| `wasi-errno/nosys` | `(std wasm wasi)` |
| `wasi-errno/success` | `(std wasm wasi)` |
| `wasi-exit-code` | `(std wasm wasi)` |
| `wasi-exit-condition?` | `(std wasm wasi)` |
| `wasi-fd-close` | `(std wasm wasi)` |
| `wasi-fd-read` | `(std wasm wasi)` |
| `wasi-fd-write` | `(std wasm wasi)` |
| `wasi-import-forms` | `(std secure wasm-target)` |
| `wasi-path-open` | `(std wasm wasi)` |
| `wasi-proc-exit` | `(std wasm wasi)` |
| `wasi-random-get` | `(std wasm wasi)` |
| `wasi-run` | `(std wasm wasi)` |
| `wasm-array-data` | `(jerboa wasm runtime)` |
| `wasm-array-type-idx` | `(jerboa wasm runtime)` |
| `wasm-array?` | `(jerboa wasm runtime)` |
| `wasm-catch-all-kind` | `(jerboa wasm format)` |
| `wasm-catch-all-ref-kind` | `(jerboa wasm format)` |
| `wasm-catch-kind` | `(jerboa wasm format)` |
| `wasm-catch-ref-kind` | `(jerboa wasm format)` |
| `wasm-composite-array` | `(jerboa wasm format)` |
| `wasm-composite-func` | `(jerboa wasm format)` |
| `wasm-composite-struct` | `(jerboa wasm format)` |
| `wasm-decode-module` | `(jerboa wasm runtime)` |
| `wasm-export-func` | `(jerboa wasm codegen)` |
| `wasm-export-global` | `(jerboa wasm codegen)` |
| `wasm-export-index` | `(jerboa wasm codegen)` |
| `wasm-export-kind` | `(jerboa wasm codegen)` |
| `wasm-export-memory` | `(jerboa wasm codegen)` |
| `wasm-export-name` | `(jerboa wasm codegen)` |
| `wasm-export-table` | `(jerboa wasm codegen)` |
| `wasm-fb-array-copy` | `(jerboa wasm format)` |
| `wasm-fb-array-fill` | `(jerboa wasm format)` |
| `wasm-fb-array-get` | `(jerboa wasm format)` |
| `wasm-fb-array-get-s` | `(jerboa wasm format)` |
| `wasm-fb-array-get-u` | `(jerboa wasm format)` |
| `wasm-fb-array-init-data` | `(jerboa wasm format)` |
| `wasm-fb-array-init-elem` | `(jerboa wasm format)` |
| `wasm-fb-array-len` | `(jerboa wasm format)` |
| `wasm-fb-array-new` | `(jerboa wasm format)` |
| `wasm-fb-array-new-data` | `(jerboa wasm format)` |
| `wasm-fb-array-new-default` | `(jerboa wasm format)` |
| `wasm-fb-array-new-elem` | `(jerboa wasm format)` |
| `wasm-fb-array-new-fixed` | `(jerboa wasm format)` |
| `wasm-fb-array-set` | `(jerboa wasm format)` |
| `wasm-fb-br-on-cast` | `(jerboa wasm format)` |
| `wasm-fb-br-on-cast-fail` | `(jerboa wasm format)` |
| `wasm-fb-extern-externalize` | `(jerboa wasm format)` |
| `wasm-fb-extern-internalize` | `(jerboa wasm format)` |
| `wasm-fb-i31-get-s` | `(jerboa wasm format)` |
| `wasm-fb-i31-get-u` | `(jerboa wasm format)` |
| `wasm-fb-ref-cast` | `(jerboa wasm format)` |
| `wasm-fb-ref-cast-null` | `(jerboa wasm format)` |
| `wasm-fb-ref-i31` | `(jerboa wasm format)` |
| `wasm-fb-ref-test` | `(jerboa wasm format)` |
| `wasm-fb-ref-test-null` | `(jerboa wasm format)` |
| `wasm-fb-struct-get` | `(jerboa wasm format)` |
| `wasm-fb-struct-get-s` | `(jerboa wasm format)` |
| `wasm-fb-struct-get-u` | `(jerboa wasm format)` |
| `wasm-fb-struct-new` | `(jerboa wasm format)` |
| `wasm-fb-struct-new-default` | `(jerboa wasm format)` |
| `wasm-fb-struct-set` | `(jerboa wasm format)` |
| `wasm-fc-data-drop` | `(jerboa wasm format)` |
| `wasm-fc-elem-drop` | `(jerboa wasm format)` |
| `wasm-fc-i32-trunc-sat-f32-s` | `(jerboa wasm format)` |
| `wasm-fc-i32-trunc-sat-f32-u` | `(jerboa wasm format)` |
| `wasm-fc-i32-trunc-sat-f64-s` | `(jerboa wasm format)` |
| `wasm-fc-i32-trunc-sat-f64-u` | `(jerboa wasm format)` |
| `wasm-fc-i64-trunc-sat-f32-s` | `(jerboa wasm format)` |
| `wasm-fc-i64-trunc-sat-f32-u` | `(jerboa wasm format)` |
| `wasm-fc-i64-trunc-sat-f64-s` | `(jerboa wasm format)` |
| `wasm-fc-i64-trunc-sat-f64-u` | `(jerboa wasm format)` |
| `wasm-fc-memory-copy` | `(jerboa wasm format)` |
| `wasm-fc-memory-fill` | `(jerboa wasm format)` |
| `wasm-fc-memory-init` | `(jerboa wasm format)` |
| `wasm-fc-table-copy` | `(jerboa wasm format)` |
| `wasm-fc-table-fill` | `(jerboa wasm format)` |
| `wasm-fc-table-grow` | `(jerboa wasm format)` |
| `wasm-fc-table-init` | `(jerboa wasm format)` |
| `wasm-fc-table-size` | `(jerboa wasm format)` |
| `wasm-func-body` | `(jerboa wasm codegen)` |
| `wasm-func-locals` | `(jerboa wasm codegen)` |
| `wasm-func?` | `(jerboa wasm codegen)` |
| `wasm-i31-value` | `(jerboa wasm runtime)` |
| `wasm-i31?` | `(jerboa wasm runtime)` |
| `wasm-import-desc` | `(jerboa wasm codegen)` |
| `wasm-import-module` | `(jerboa wasm codegen)` |
| `wasm-import-name` | `(jerboa wasm codegen)` |
| `wasm-instance-exports` | `(jerboa wasm runtime)` |
| `wasm-instance?` | `(jerboa wasm runtime)` |
| `wasm-magic` | `(jerboa wasm format)` |
| `wasm-module-add-data!` | `(jerboa wasm codegen)` |
| `wasm-module-add-element!` | `(jerboa wasm codegen)` |
| `wasm-module-add-export!` | `(jerboa wasm codegen)` |
| `wasm-module-add-function!` | `(jerboa wasm codegen)` |
| `wasm-module-add-global!` | `(jerboa wasm codegen)` |
| `wasm-module-add-import!` | `(jerboa wasm codegen)` |
| `wasm-module-add-memory!` | `(jerboa wasm codegen)` |
| `wasm-module-add-table!` | `(jerboa wasm codegen)` |
| `wasm-module-add-tag!` | `(jerboa wasm codegen)` |
| `wasm-module-add-type!` | `(jerboa wasm codegen)` |
| `wasm-module-data-segments` | `(jerboa wasm codegen)` |
| `wasm-module-elements` | `(jerboa wasm codegen)` |
| `wasm-module-encode` | `(jerboa wasm codegen)` |
| `wasm-module-exports` | `(jerboa wasm codegen)` |
| `wasm-module-functions` | `(jerboa wasm codegen)` |
| `wasm-module-globals` | `(jerboa wasm codegen)` |
| `wasm-module-imports` | `(jerboa wasm codegen)` |
| `wasm-module-memories` | `(jerboa wasm codegen)` |
| `wasm-module-sections` | `(jerboa wasm runtime)` |
| `wasm-module-set-start!` | `(jerboa wasm codegen)` |
| `wasm-module-start` | `(jerboa wasm codegen)` |
| `wasm-module-tables` | `(jerboa wasm codegen)` |
| `wasm-module-tags` | `(jerboa wasm codegen)` |
| `wasm-module-types` | `(jerboa wasm codegen)` |
| `wasm-module?` | `(jerboa wasm codegen)` |
| `wasm-opcode-block` | `(jerboa wasm format)` |
| `wasm-opcode-br` | `(jerboa wasm format)` |
| `wasm-opcode-br-if` | `(jerboa wasm format)` |
| `wasm-opcode-br-table` | `(jerboa wasm format)` |
| `wasm-opcode-call` | `(jerboa wasm format)` |
| `wasm-opcode-call-indirect` | `(jerboa wasm format)` |
| `wasm-opcode-catch` | `(jerboa wasm format)` |
| `wasm-opcode-catch-all` | `(jerboa wasm format)` |
| `wasm-opcode-delegate` | `(jerboa wasm format)` |
| `wasm-opcode-drop` | `(jerboa wasm format)` |
| `wasm-opcode-else` | `(jerboa wasm format)` |
| `wasm-opcode-end` | `(jerboa wasm format)` |
| `wasm-opcode-f32-abs` | `(jerboa wasm format)` |
| `wasm-opcode-f32-add` | `(jerboa wasm format)` |
| `wasm-opcode-f32-ceil` | `(jerboa wasm format)` |
| `wasm-opcode-f32-const` | `(jerboa wasm format)` |
| `wasm-opcode-f32-convert-i32-s` | `(jerboa wasm format)` |
| `wasm-opcode-f32-convert-i32-u` | `(jerboa wasm format)` |
| `wasm-opcode-f32-convert-i64-s` | `(jerboa wasm format)` |
| `wasm-opcode-f32-convert-i64-u` | `(jerboa wasm format)` |
| `wasm-opcode-f32-copysign` | `(jerboa wasm format)` |
| `wasm-opcode-f32-demote-f64` | `(jerboa wasm format)` |
| `wasm-opcode-f32-div` | `(jerboa wasm format)` |
| `wasm-opcode-f32-eq` | `(jerboa wasm format)` |
| `wasm-opcode-f32-floor` | `(jerboa wasm format)` |
| `wasm-opcode-f32-ge` | `(jerboa wasm format)` |
| `wasm-opcode-f32-gt` | `(jerboa wasm format)` |
| `wasm-opcode-f32-le` | `(jerboa wasm format)` |
| `wasm-opcode-f32-load` | `(jerboa wasm format)` |
| `wasm-opcode-f32-lt` | `(jerboa wasm format)` |
| `wasm-opcode-f32-max` | `(jerboa wasm format)` |
| `wasm-opcode-f32-min` | `(jerboa wasm format)` |
| `wasm-opcode-f32-mul` | `(jerboa wasm format)` |
| `wasm-opcode-f32-ne` | `(jerboa wasm format)` |
| `wasm-opcode-f32-nearest` | `(jerboa wasm format)` |
| `wasm-opcode-f32-neg` | `(jerboa wasm format)` |
| `wasm-opcode-f32-reinterpret-i32` | `(jerboa wasm format)` |
| `wasm-opcode-f32-sqrt` | `(jerboa wasm format)` |
| `wasm-opcode-f32-store` | `(jerboa wasm format)` |
| `wasm-opcode-f32-sub` | `(jerboa wasm format)` |
| `wasm-opcode-f32-trunc` | `(jerboa wasm format)` |
| `wasm-opcode-f64-abs` | `(jerboa wasm format)` |
| `wasm-opcode-f64-add` | `(jerboa wasm format)` |
| `wasm-opcode-f64-ceil` | `(jerboa wasm format)` |
| `wasm-opcode-f64-const` | `(jerboa wasm format)` |
| `wasm-opcode-f64-convert-i32-s` | `(jerboa wasm format)` |
| `wasm-opcode-f64-convert-i32-u` | `(jerboa wasm format)` |
| `wasm-opcode-f64-convert-i64-s` | `(jerboa wasm format)` |
| `wasm-opcode-f64-convert-i64-u` | `(jerboa wasm format)` |
| `wasm-opcode-f64-copysign` | `(jerboa wasm format)` |
| `wasm-opcode-f64-div` | `(jerboa wasm format)` |
| `wasm-opcode-f64-eq` | `(jerboa wasm format)` |
| `wasm-opcode-f64-floor` | `(jerboa wasm format)` |
| `wasm-opcode-f64-ge` | `(jerboa wasm format)` |
| `wasm-opcode-f64-gt` | `(jerboa wasm format)` |
| `wasm-opcode-f64-le` | `(jerboa wasm format)` |
| `wasm-opcode-f64-load` | `(jerboa wasm format)` |
| `wasm-opcode-f64-lt` | `(jerboa wasm format)` |
| `wasm-opcode-f64-max` | `(jerboa wasm format)` |
| `wasm-opcode-f64-min` | `(jerboa wasm format)` |
| `wasm-opcode-f64-mul` | `(jerboa wasm format)` |
| `wasm-opcode-f64-ne` | `(jerboa wasm format)` |
| `wasm-opcode-f64-nearest` | `(jerboa wasm format)` |
| `wasm-opcode-f64-neg` | `(jerboa wasm format)` |
| `wasm-opcode-f64-promote-f32` | `(jerboa wasm format)` |
| `wasm-opcode-f64-reinterpret-i64` | `(jerboa wasm format)` |
| `wasm-opcode-f64-sqrt` | `(jerboa wasm format)` |
| `wasm-opcode-f64-store` | `(jerboa wasm format)` |
| `wasm-opcode-f64-sub` | `(jerboa wasm format)` |
| `wasm-opcode-f64-trunc` | `(jerboa wasm format)` |
| `wasm-opcode-global-get` | `(jerboa wasm format)` |
| `wasm-opcode-global-set` | `(jerboa wasm format)` |
| `wasm-opcode-i32-add` | `(jerboa wasm format)` |
| `wasm-opcode-i32-and` | `(jerboa wasm format)` |
| `wasm-opcode-i32-clz` | `(jerboa wasm format)` |
| `wasm-opcode-i32-const` | `(jerboa wasm format)` |
| `wasm-opcode-i32-ctz` | `(jerboa wasm format)` |
| `wasm-opcode-i32-div-s` | `(jerboa wasm format)` |
| `wasm-opcode-i32-div-u` | `(jerboa wasm format)` |
| `wasm-opcode-i32-eq` | `(jerboa wasm format)` |
| `wasm-opcode-i32-eqz` | `(jerboa wasm format)` |
| `wasm-opcode-i32-extend16-s` | `(jerboa wasm format)` |
| `wasm-opcode-i32-extend8-s` | `(jerboa wasm format)` |
| `wasm-opcode-i32-ge-s` | `(jerboa wasm format)` |
| `wasm-opcode-i32-ge-u` | `(jerboa wasm format)` |
| `wasm-opcode-i32-gt-s` | `(jerboa wasm format)` |
| `wasm-opcode-i32-gt-u` | `(jerboa wasm format)` |
| `wasm-opcode-i32-le-s` | `(jerboa wasm format)` |
| `wasm-opcode-i32-le-u` | `(jerboa wasm format)` |
| `wasm-opcode-i32-load` | `(jerboa wasm format)` |
| `wasm-opcode-i32-load16-s` | `(jerboa wasm format)` |
| `wasm-opcode-i32-load16-u` | `(jerboa wasm format)` |
| `wasm-opcode-i32-load8-s` | `(jerboa wasm format)` |
| `wasm-opcode-i32-load8-u` | `(jerboa wasm format)` |
| `wasm-opcode-i32-lt-s` | `(jerboa wasm format)` |
| `wasm-opcode-i32-lt-u` | `(jerboa wasm format)` |
| `wasm-opcode-i32-mul` | `(jerboa wasm format)` |
| `wasm-opcode-i32-ne` | `(jerboa wasm format)` |
| `wasm-opcode-i32-or` | `(jerboa wasm format)` |
| `wasm-opcode-i32-popcnt` | `(jerboa wasm format)` |
| `wasm-opcode-i32-reinterpret-f32` | `(jerboa wasm format)` |
| `wasm-opcode-i32-rem-s` | `(jerboa wasm format)` |
| `wasm-opcode-i32-rem-u` | `(jerboa wasm format)` |
| `wasm-opcode-i32-rotl` | `(jerboa wasm format)` |
| `wasm-opcode-i32-rotr` | `(jerboa wasm format)` |
| `wasm-opcode-i32-shl` | `(jerboa wasm format)` |
| `wasm-opcode-i32-shr-s` | `(jerboa wasm format)` |
| `wasm-opcode-i32-shr-u` | `(jerboa wasm format)` |
| `wasm-opcode-i32-store` | `(jerboa wasm format)` |
| `wasm-opcode-i32-store16` | `(jerboa wasm format)` |
| `wasm-opcode-i32-store8` | `(jerboa wasm format)` |
| `wasm-opcode-i32-sub` | `(jerboa wasm format)` |
| `wasm-opcode-i32-trunc-f32-s` | `(jerboa wasm format)` |
| `wasm-opcode-i32-trunc-f32-u` | `(jerboa wasm format)` |
| `wasm-opcode-i32-trunc-f64-s` | `(jerboa wasm format)` |
| `wasm-opcode-i32-trunc-f64-u` | `(jerboa wasm format)` |
| `wasm-opcode-i32-wrap-i64` | `(jerboa wasm format)` |
| `wasm-opcode-i32-xor` | `(jerboa wasm format)` |
| `wasm-opcode-i64-add` | `(jerboa wasm format)` |
| `wasm-opcode-i64-and` | `(jerboa wasm format)` |
| `wasm-opcode-i64-clz` | `(jerboa wasm format)` |
| `wasm-opcode-i64-const` | `(jerboa wasm format)` |
| `wasm-opcode-i64-ctz` | `(jerboa wasm format)` |
| `wasm-opcode-i64-div-s` | `(jerboa wasm format)` |
| `wasm-opcode-i64-div-u` | `(jerboa wasm format)` |
| `wasm-opcode-i64-eq` | `(jerboa wasm format)` |
| `wasm-opcode-i64-eqz` | `(jerboa wasm format)` |
| `wasm-opcode-i64-extend-i32-s` | `(jerboa wasm format)` |
| `wasm-opcode-i64-extend-i32-u` | `(jerboa wasm format)` |
| `wasm-opcode-i64-extend16-s` | `(jerboa wasm format)` |
| `wasm-opcode-i64-extend32-s` | `(jerboa wasm format)` |
| `wasm-opcode-i64-extend8-s` | `(jerboa wasm format)` |
| `wasm-opcode-i64-ge-s` | `(jerboa wasm format)` |
| `wasm-opcode-i64-ge-u` | `(jerboa wasm format)` |
| `wasm-opcode-i64-gt-s` | `(jerboa wasm format)` |
| `wasm-opcode-i64-gt-u` | `(jerboa wasm format)` |
| `wasm-opcode-i64-le-s` | `(jerboa wasm format)` |
| `wasm-opcode-i64-le-u` | `(jerboa wasm format)` |
| `wasm-opcode-i64-load` | `(jerboa wasm format)` |
| `wasm-opcode-i64-load16-s` | `(jerboa wasm format)` |
| `wasm-opcode-i64-load16-u` | `(jerboa wasm format)` |
| `wasm-opcode-i64-load32-s` | `(jerboa wasm format)` |
| `wasm-opcode-i64-load32-u` | `(jerboa wasm format)` |
| `wasm-opcode-i64-load8-s` | `(jerboa wasm format)` |
| `wasm-opcode-i64-load8-u` | `(jerboa wasm format)` |
| `wasm-opcode-i64-lt-s` | `(jerboa wasm format)` |
| `wasm-opcode-i64-lt-u` | `(jerboa wasm format)` |
| `wasm-opcode-i64-mul` | `(jerboa wasm format)` |
| `wasm-opcode-i64-ne` | `(jerboa wasm format)` |
| `wasm-opcode-i64-or` | `(jerboa wasm format)` |
| `wasm-opcode-i64-popcnt` | `(jerboa wasm format)` |
| `wasm-opcode-i64-reinterpret-f64` | `(jerboa wasm format)` |
| `wasm-opcode-i64-rem-s` | `(jerboa wasm format)` |
| `wasm-opcode-i64-rem-u` | `(jerboa wasm format)` |
| `wasm-opcode-i64-rotl` | `(jerboa wasm format)` |
| `wasm-opcode-i64-rotr` | `(jerboa wasm format)` |
| `wasm-opcode-i64-shl` | `(jerboa wasm format)` |
| `wasm-opcode-i64-shr-s` | `(jerboa wasm format)` |
| `wasm-opcode-i64-shr-u` | `(jerboa wasm format)` |
| `wasm-opcode-i64-store` | `(jerboa wasm format)` |
| `wasm-opcode-i64-store16` | `(jerboa wasm format)` |
| `wasm-opcode-i64-store32` | `(jerboa wasm format)` |
| `wasm-opcode-i64-store8` | `(jerboa wasm format)` |
| `wasm-opcode-i64-sub` | `(jerboa wasm format)` |
| `wasm-opcode-i64-trunc-f32-s` | `(jerboa wasm format)` |
| `wasm-opcode-i64-trunc-f32-u` | `(jerboa wasm format)` |
| `wasm-opcode-i64-trunc-f64-s` | `(jerboa wasm format)` |
| `wasm-opcode-i64-trunc-f64-u` | `(jerboa wasm format)` |
| `wasm-opcode-i64-xor` | `(jerboa wasm format)` |
| `wasm-opcode-if` | `(jerboa wasm format)` |
| `wasm-opcode-local-get` | `(jerboa wasm format)` |
| `wasm-opcode-local-set` | `(jerboa wasm format)` |
| `wasm-opcode-local-tee` | `(jerboa wasm format)` |
| `wasm-opcode-loop` | `(jerboa wasm format)` |
| `wasm-opcode-memory-grow` | `(jerboa wasm format)` |
| `wasm-opcode-memory-size` | `(jerboa wasm format)` |
| `wasm-opcode-nop` | `(jerboa wasm format)` |
| `wasm-opcode-ref-func` | `(jerboa wasm format)` |
| `wasm-opcode-ref-is-null` | `(jerboa wasm format)` |
| `wasm-opcode-ref-null` | `(jerboa wasm format)` |
| `wasm-opcode-rethrow` | `(jerboa wasm format)` |
| `wasm-opcode-return` | `(jerboa wasm format)` |
| `wasm-opcode-return-call` | `(jerboa wasm format)` |
| `wasm-opcode-return-call-indirect` | `(jerboa wasm format)` |
| `wasm-opcode-select` | `(jerboa wasm format)` |
| `wasm-opcode-select-t` | `(jerboa wasm format)` |
| `wasm-opcode-table-get` | `(jerboa wasm format)` |
| `wasm-opcode-table-set` | `(jerboa wasm format)` |
| `wasm-opcode-throw` | `(jerboa wasm format)` |
| `wasm-opcode-throw-ref` | `(jerboa wasm format)` |
| `wasm-opcode-try` | `(jerboa wasm format)` |
| `wasm-opcode-try-table` | `(jerboa wasm format)` |
| `wasm-opcode-unreachable` | `(jerboa wasm format)` |
| `wasm-prefix-fb` | `(jerboa wasm format)` |
| `wasm-prefix-fc` | `(jerboa wasm format)` |
| `wasm-run-start` | `(jerboa wasm runtime)` |
| `wasm-runtime-call` | `(jerboa wasm runtime)` |
| `wasm-runtime-global-ref` | `(jerboa wasm runtime)` |
| `wasm-runtime-global-set!` | `(jerboa wasm runtime)` |
| `wasm-runtime-load` | `(jerboa wasm runtime)` |
| `wasm-runtime-memory` | `(jerboa wasm runtime)` |
| `wasm-runtime-memory-ref` | `(jerboa wasm runtime)` |
| `wasm-runtime-memory-set!` | `(jerboa wasm runtime)` |
| `wasm-runtime-memory-size` | `(jerboa wasm runtime)` |
| `wasm-runtime-set-fuel!` | `(jerboa wasm runtime)` |
| `wasm-runtime-set-import-validator!` | `(jerboa wasm runtime)` |
| `wasm-runtime-set-max-depth!` | `(jerboa wasm runtime)` |
| `wasm-runtime-set-max-memory-pages!` | `(jerboa wasm runtime)` |
| `wasm-runtime-set-max-module-size!` | `(jerboa wasm runtime)` |
| `wasm-runtime-set-max-stack!` | `(jerboa wasm runtime)` |
| `wasm-runtime?` | `(jerboa wasm runtime)` |
| `wasm-sandbox-add-fuel` | `(std wasm sandbox)` |
| `wasm-sandbox-available?` | `(std wasm sandbox)` |
| `wasm-sandbox-backend` | `(std wasm sandbox)` |
| `wasm-sandbox-call` | `(std wasm sandbox)` |
| `wasm-sandbox-call/i32` | `(std wasm sandbox)` |
| `wasm-sandbox-call/i64` | `(std wasm sandbox)` |
| `wasm-sandbox-free` | `(std wasm sandbox)` |
| `wasm-sandbox-free-module` | `(std wasm sandbox)` |
| `wasm-sandbox-fuel-remaining` | `(std wasm sandbox)` |
| `wasm-sandbox-get-log` | `(std wasm sandbox)` |
| `wasm-sandbox-instantiate` | `(std wasm sandbox)` |
| `wasm-sandbox-instantiate-hosted` | `(std wasm sandbox)` |
| `wasm-sandbox-load` | `(std wasm sandbox)` |
| `wasm-sandbox-memory-read` | `(std wasm sandbox)` |
| `wasm-sandbox-memory-size` | `(std wasm sandbox)` |
| `wasm-sandbox-memory-write` | `(std wasm sandbox)` |
| `wasm-sandbox-spidermonkey-available?` | `(std wasm sandbox)` |
| `wasm-sandbox-use-spidermonkey!` | `(std wasm sandbox)` |
| `wasm-section-code` | `(jerboa wasm format)` |
| `wasm-section-custom` | `(jerboa wasm format)` |
| `wasm-section-data` | `(jerboa wasm format)` |
| `wasm-section-data-count` | `(jerboa wasm format)` |
| `wasm-section-element` | `(jerboa wasm format)` |
| `wasm-section-export` | `(jerboa wasm format)` |
| `wasm-section-function` | `(jerboa wasm format)` |
| `wasm-section-global` | `(jerboa wasm format)` |
| `wasm-section-import` | `(jerboa wasm format)` |
| `wasm-section-memory` | `(jerboa wasm format)` |
| `wasm-section-start` | `(jerboa wasm format)` |
| `wasm-section-table` | `(jerboa wasm format)` |
| `wasm-section-tag` | `(jerboa wasm format)` |
| `wasm-section-type` | `(jerboa wasm format)` |
| `wasm-store-instantiate` | `(jerboa wasm runtime)` |
| `wasm-store?` | `(jerboa wasm runtime)` |
| `wasm-struct-fields` | `(jerboa wasm runtime)` |
| `wasm-struct-type-idx` | `(jerboa wasm runtime)` |
| `wasm-struct?` | `(jerboa wasm runtime)` |
| `wasm-tag-type-idx` | `(jerboa wasm runtime)` |
| `wasm-tag?` | `(jerboa wasm runtime)` |
| `wasm-trap-message` | `(jerboa wasm runtime)` |
| `wasm-trap?` | `(jerboa wasm runtime)` |
| `wasm-type-anyref` | `(jerboa wasm format)` |
| `wasm-type-arrayref` | `(jerboa wasm format)` |
| `wasm-type-eqref` | `(jerboa wasm format)` |
| `wasm-type-externref` | `(jerboa wasm format)` |
| `wasm-type-f32` | `(jerboa wasm format)` |
| `wasm-type-f64` | `(jerboa wasm format)` |
| `wasm-type-funcref` | `(jerboa wasm format)` |
| `wasm-type-i31ref` | `(jerboa wasm format)` |
| `wasm-type-i32` | `(jerboa wasm format)` |
| `wasm-type-i64` | `(jerboa wasm format)` |
| `wasm-type-noneref` | `(jerboa wasm format)` |
| `wasm-type-nullexternref` | `(jerboa wasm format)` |
| `wasm-type-nullfuncref` | `(jerboa wasm format)` |
| `wasm-type-nullref` | `(jerboa wasm format)` |
| `wasm-type-params` | `(jerboa wasm codegen)` |
| `wasm-type-rec` | `(jerboa wasm format)` |
| `wasm-type-results` | `(jerboa wasm codegen)` |
| `wasm-type-structref` | `(jerboa wasm format)` |
| `wasm-type-sub` | `(jerboa wasm format)` |
| `wasm-type-sub-final` | `(jerboa wasm format)` |
| `wasm-type-void` | `(jerboa wasm format)` |
| `wasm-validate-module` | `(jerboa wasm runtime)` |
| `wasm-version` | `(jerboa wasm format)` |
| `watch-and-build!` | `(std build watch)` |
| `watch-and-reload!` | `(std dev reload)` |
| `watch-config!` | `(std config)` |
| `watcher-add!` | `(std build watch)` |
| `watcher-remove!` | `(std build watch)` |
| `watcher-running?` | `(std build watch)` |
| `watcher-start!` | `(std build watch)` |
| `watcher-stop!` | `(std build watch)` |
| `watcher-watched-paths` | `(std build watch)` |
| `watcher?` | `(std build watch)` |
| `weak-car` | `(std misc weak)` |
| `weak-cdr` | `(std misc weak)` |
| `weak-hashtable-delete!` | `(std misc weak)` |
| `weak-hashtable-keys` | `(std misc weak)` |
| `weak-hashtable-ref` | `(std misc weak)` |
| `weak-hashtable-set!` | `(std misc weak)` |
| `weak-list->list` | `(std misc weak)` |
| `weak-list-compact!` | `(std misc weak)` |
| `weak-pair-value` | `(std misc weak)` |
| `weak-pair?` | `(std ephemeron)`, `(std misc weak)` |
| `websocket-response-handler` | `(std net fiber-httpd)` |
| `websocket-response?` | `(std net fiber-httpd)` |
| `wg-add` | `(std misc wg)` |
| `wg-done` | `(std misc wg)` |
| `wg-wait` | `(std misc wg)` |
| `wg?` | `(std misc wg)` |
| `wheel-timeout` | `(std csp select)` |
| `when-let` | `(jerboa clojure)`, `(jerboa prelude)`, `(std gambit-compat)`, `(std prelude)`, ... (+1) |
| `when/list` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list)` |
| `when/t` | `(std typed advanced)` |
| `where` | `(std db query-compile)`, `(std query)` |
| `whereis` | `(std actor registry)`, `(std actor)` |
| `whereis/any` | `(std actor cluster)` |
| `while` | `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, ... (+3) |
| `white` | `(std cli style)` |
| `window-add!` | `(std stream window)` |
| `window-filter` | `(std stream window)` |
| `window-flush!` | `(std stream window)` |
| `window-map` | `(std stream window)` |
| `window-reduce` | `(std stream window)` |
| `window-reset!` | `(std stream window)` |
| `window-results` | `(std stream window)` |
| `window-size` | `(std stream window)` |
| `windowing` | `(std transducer)` |
| `wipe-bytevector!` | `(std security secret)` |
| `with` | `(std srfi srfi-159)` |
| `with-affine` | `(std typed affine)` |
| `with-alternate-screen` | `(std misc terminal)` |
| `with-amb` | `(std misc amb)` |
| `with-arena` | `(std arena)` |
| `with-ask-context` | `(std actor protocol)`, `(std actor)` |
| `with-benchmark` | `(std dev benchmark)` |
| `with-btree-transaction` | `(std mmap-btree)` |
| `with-buffer` | `(std net zero-copy)` |
| `with-byte-order` | `(std binary)` |
| `with-cairo` | `(std ffi cairo)`, `(thunderchez cairo)` |
| `with-capabilities` | `(std security capability)` |
| `with-catch` | `(jerboa clojure)`, `(jerboa prelude)`, `(std gambit-compat)`, `(std sugar)` |
| `with-checked-mutex` | `(std concur deadlock)` |
| `with-class` | `(std typed typeclass)` |
| `with-cleanup` | `(std error recovery)` |
| `with-compilation-cache` | `(jerboa cache)` |
| `with-config` | `(std config)`, `(std misc config)` |
| `with-connection` | `(std db conpool)`, `(std net pool)` |
| `with-context` | `(std error context)` |
| `with-context*` | `(std error context)` |
| `with-continuation-mark` | `(std control marks)`, `(std misc cont-marks)` |
| `with-custodian` | `(std misc custodian)` |
| `with-deadlock-detection` | `(std concur deadlock)` |
| `with-deep-handler` | `(std effect deep)` |
| `with-destroy` | `(std misc with-destroy)` |
| `with-destroys` | `(std misc with-destroy)` |
| `with-diagnostics` | `(std error diagnostics)` |
| `with-dns-resolver` | `(std net resolve)` |
| `with-enhanced-errors` | `(std errors)` |
| `with-errdefer` | `(std errdefer)` |
| `with-error-advice` | `(std error-advice)` |
| `with-exception-catcher` | `(jerboa core)`, `(std gambit-compat)` |
| `with-exception-catcher*` | `(std gambit-compat)` |
| `with-exception-handler` | `(jerboa runtime)`, `(std error)` |
| `with-fallback` | `(std error recovery)` |
| `with-fds` | `(std os fd)` |
| `with-fiber-group` | `(std fiber)` |
| `with-fibers` | `(std fiber)` |
| `with-file-lock` | `(std os flock)` |
| `with-file-pool` | `(std io filepool)` |
| `with-fixnum-ops` | `(std typed)` |
| `with-flonum-ops` | `(std typed)` |
| `with-foreign` | `(std foreign bind)` |
| `with-foreign-resource` | `(std foreign)` |
| `with-fused-handlers` | `(std effect fusion)` |
| `with-gc-stats` | `(std debug heap)` |
| `with-gensyms` | `(std staging)` |
| `with-grpc-client` | `(std net grpc)` |
| `with-guarded-resource` | `(std misc guardian-pool)` |
| `with-guardian` | `(std guardian)` |
| `with-handler` | `(std effect)` |
| `with-id` | `(jerboa clojure)`, `(jerboa prelude)`, `(std gambit-compat)`, `(std sugar)` |
| `with-input` | `(std io)` |
| `with-input-from-string` | `(jerboa clojure)`, `(jerboa prelude safe)`, `(jerboa prelude)`, `(std misc port-utils)`, ... (+2) |
| `with-io-policy` | `(std security io-intercept)` |
| `with-io-poller` | `(std net io)` |
| `with-landlock` | `(std security landlock)` |
| `with-leak-check` | `(std debug memleak)` |
| `with-linear` | `(std typed linear)` |
| `with-linear-handler` | `(std dev cont-mark-opt)` |
| `with-list-builder` | `(jerboa clojure)`, `(jerboa prelude)`, `(std misc list-builder)`, `(std misc list)` |
| `with-lock` | `(jerboa clojure)`, `(jerboa prelude)`, `(std gambit-compat)`, `(std sugar)` |
| `with-logger` | `(std log)` |
| `with-mdb-dbi` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `with-mdb-env` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `with-mdb-txn` | `(std ffi lmdb)`, `(thunderchez lmdb)` |
| `with-meta` | `(jerboa clojure)`, `(jerboa prelude)`, `(std clojure)`, `(std misc meta)` |
| `with-monitoring` | `(std debug contract-monitor)` |
| `with-move` | `(std move)` |
| `with-multishot-handler` | `(std effect multishot)` |
| `with-odb-transaction` | `(std odb)` |
| `with-open` | `(std clojure io)` |
| `with-output` | `(std io)` |
| `with-output-to-string` | `(jerboa clojure)`, `(jerboa prelude safe)`, `(jerboa prelude)`, `(std misc port-utils)`, ... (+2) |
| `with-pgo-file` | `(std dev pgo)` |
| `with-pooled-connection` | `(std net connpool)` |
| `with-pooled-ssh` | `(std net ssh client)`, `(std net ssh)` |
| `with-profile` | `(std debug flamegraph)`, `(std profile)` |
| `with-profile/timed` | `(std debug flamegraph)` |
| `with-profiling` | `(std compiler pgo)`, `(std dev profile)`, `(std misc profile)` |
| `with-python` | `(std python)` |
| `with-rate-limit` | `(std misc rate-limiter)` |
| `with-raw-mode` | `(std misc terminal)`, `(std os tty)` |
| `with-read-lock` | `(std concur util)`, `(std misc rwlock)` |
| `with-real-fs` | `(std effect io)` |
| `with-recording` | `(std debug timetravel)`, `(std dev debug)` |
| `with-refinement-context` | `(std typed refine)` |
| `with-region` | `(std region)` |
| `with-reloader` | `(jerboa hot)` |
| `with-resource` | `(jerboa clojure)`, `(jerboa prelude safe)`, `(jerboa prelude)`, `(std misc pool)`, ... (+4) |
| `with-resource-tracking` | `(std concur)` |
| `with-resource1` | `(jerboa prelude safe)`, `(std resource)`, `(std safe)` |
| `with-resources` | `(std effect resource)` |
| `with-retry` | `(std error recovery)` |
| `with-sandbox` | `(jerboa embed)`, `(std capability sandbox)`, `(std capability)` |
| `with-scheduler` | `(std sched)` |
| `with-scoped-handler` | `(std effect scoped)` |
| `with-secret` | `(std security secret)` |
| `with-secure-region` | `(std crypto secure-mem)` |
| `with-security-headers` | `(std net security-headers)` |
| `with-socks-proxy` | `(std net socks)` |
| `with-solver-context` | `(std typed solver)` |
| `with-span` | `(std span)` |
| `with-spinlock` | `(std misc spinlock)` |
| `with-ssh-connection` | `(std net ssh client)`, `(std net ssh)` |
| `with-stack-inspector` | `(std debug inspector)` |
| `with-stage-env` | `(std staging2)` |
| `with-state` | `(std effect state)` |
| `with-syntax*` | `(std stxutil)` |
| `with-taint-checking` | `(std taint)` |
| `with-task-group` | `(std task)` |
| `with-task-scope` | `(jerboa prelude safe)`, `(std concur structured)` |
| `with-tcp-server` | `(std net tcp)` |
| `with-temp-directory` | `(std os path-util)` |
| `with-temporal-contract` | `(std contract2)` |
| `with-temporary-directory` | `(std os temporaries)` |
| `with-temporary-file` | `(std os temporaries)` |
| `with-test-console` | `(std effect io)` |
| `with-test-fs` | `(std effect io)` |
| `with-test-output` | `(std test framework)` |
| `with-theme` | `(std misc highlight)` |
| `with-thread-monitor` | `(std debug threads)` |
| `with-timeout` | `(jerboa prelude safe)`, `(std error recovery)`, `(std misc timeout)`, `(std net timeout)`, ... (+2) |
| `with-timeout-check` | `(std health)` |
| `with-timing` | `(std profile)` |
| `with-tracked-call` | `(std debug inspector)` |
| `with-tracked-mutex` | `(std concur)` |
| `with-type-checking` | `(std typed check)` |
| `with-type-errors-collected` | `(std typed infer)` |
| `with-unwind-protect` | `(std gambit-compat)` |
| `with-wasi-env` | `(std wasm wasi)` |
| `with-write-lock` | `(std concur util)`, `(std misc rwlock)` |
| `work-deque?` | `(std actor deque)` |
| `work-pool-start!` | `(std net workpool)` |
| `work-pool-stop!` | `(std net workpool)` |
| `work-pool-submit!` | `(std net workpool)` |
| `work-pool?` | `(std net workpool)` |
| `worker-component` | `(std component fiber)` |
| `worker-eval` | `(std distributed)` |
| `worker-loop` | `(std security privsep)` |
| `worker-request` | `(std security privsep)` |
| `worker?` | `(std distributed)` |
| `world-bindings` | `(std image)` |
| `world-snapshot` | `(std image)` |
| `wpo-compile` | `(jerboa build)` |
| `wrap` | `(std event)`, `(std misc event)` |
| `wrap-content-type` | `(std net ring)` |
| `wrap-cookies` | `(std net ring)` |
| `wrap-cors` | `(std net ring)` |
| `wrap-exception` | `(std net ring)` |
| `wrap-head` | `(std net ring)` |
| `wrap-health-check` | `(std net fiber-httpd)` |
| `wrap-json-body` | `(std net ring)` |
| `wrap-json-response` | `(std net ring)` |
| `wrap-metrics-endpoint` | `(std net fiber-httpd)` |
| `wrap-middleware` | `(std web rack)` |
| `wrap-not-modified` | `(std net ring)` |
| `wrap-params` | `(std net ring)` |
| `wrap-ring` | `(std net ring)` |
| `wrap-session` | `(std net ring)` |
| `wrap-static` | `(std net ring)` |
| `write-all` | `(std io)` |
| `write-csv` | `(jerboa clojure)`, `(jerboa prelude)`, `(std csv)`, `(std prelude)`, ... (+1) |
| `write-csv-file` | `(jerboa clojure)`, `(jerboa prelude)`, `(std csv)`, `(std prelude)` |
| `write-csv-record` | `(std text csv)` |
| `write-delimited` | `(std io delimited)` |
| `write-docs` | `(std doc generator)` |
| `write-edn` | `(std text edn)` |
| `write-edn-string` | `(std text edn)` |
| `write-file-string` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `write-json` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+2) |
| `write-lock!` | `(std misc rwlock)` |
| `write-lsp-message` | `(std lsp)` |
| `write-netstring` | `(std ffi netstring)`, `(thunderchez netstring)` |
| `write-sexp-file` | `(std io)` |
| `write-sexp-port` | `(std io)` |
| `write-subu8vector` | `(std gambit-compat)`, `(std os fdio)` |
| `write-u8` | `(jerboa core)`, `(std gambit-compat)` |
| `write-unlock!` | `(std misc rwlock)` |
| `write-with-deadline` | `(std net timeout)` |
| `write-xml` | `(std markup xml)`, `(std text xml)` |
| `writer` | `(std clojure io)` |
| `writer-bind` | `(std typed monad)` |
| `writer-get-string` | `(std io strio)` |
| `writer-listen` | `(std typed monad)` |
| `writer-return` | `(std typed monad)` |
| `writer-tell` | `(std typed monad)` |
| `writer-write-char` | `(std io strio)` |
| `writer-write-string` | `(std io strio)` |
| `written` | `(std srfi srfi-159)` |
| `written-shared` | `(std srfi srfi-159)` |
| `ws-binary-frame` | `(std net websocket)` |
| `ws-close-frame` | `(std net websocket)` |
| `ws-frame-decode` | `(std net websocket)` |
| `ws-frame-encode` | `(std net websocket)` |
| `ws-frame-fin?` | `(std net websocket)` |
| `ws-frame-masked?` | `(std net websocket)` |
| `ws-frame-opcode` | `(std net websocket)` |
| `ws-frame-payload` | `(std net websocket)` |
| `ws-handshake-accept` | `(std net websocket)` |
| `ws-handshake-key` | `(std net websocket)` |
| `ws-handshake-valid?` | `(std net websocket)` |
| `ws-mask-payload` | `(std net websocket)` |
| `ws-opcode-binary` | `(std net websocket)` |
| `ws-opcode-close` | `(std net websocket)` |
| `ws-opcode-continuation` | `(std net websocket)` |
| `ws-opcode-ping` | `(std net websocket)` |
| `ws-opcode-pong` | `(std net websocket)` |
| `ws-opcode-text` | `(std net websocket)` |
| `ws-ping-frame` | `(std net websocket)` |
| `ws-pong-frame` | `(std net websocket)` |
| `ws-text-frame` | `(std net websocket)` |
| `ws-unmask-payload` | `(std net websocket)` |

### <a name="idx-x"></a>x

| Symbol | Modules |
| --- | --- |
| `X_OK` | `(std os posix)` |
| `x>>` | `(std injest)` |
| `xf-compose` | `(std transducer)` |

### <a name="idx-y"></a>y

| Symbol | Modules |
| --- | --- |
| `yaml->scheme` | `(std text yaml)` |
| `yaml-alias-eol-comment` | `(std text yaml nodes)` |
| `yaml-alias-name` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-alias-pre-comments` | `(std text yaml nodes)` |
| `yaml-alias?` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-document-end-comments` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-document-has-end?` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-document-has-start?` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-document-pre-comments` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-document-root` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-document-root-set!` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-document?` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-dump` | `(std text yaml)` |
| `yaml-dump-string` | `(std text yaml)` |
| `yaml-emit-port` | `(std text yaml writer)` |
| `yaml-emit-string` | `(std text yaml writer)` |
| `yaml-key-format` | `(std text yaml)` |
| `yaml-load` | `(std text yaml)` |
| `yaml-load-string` | `(std text yaml)` |
| `yaml-mapping-anchor` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-mapping-delete!` | `(std text yaml)` |
| `yaml-mapping-eol-comment` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-mapping-has-key?` | `(std text yaml)` |
| `yaml-mapping-keys` | `(std text yaml)` |
| `yaml-mapping-pairs` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-mapping-pairs-set!` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-mapping-post-comments` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-mapping-post-comments-set!` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-mapping-pre-comments` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-mapping-ref` | `(std text yaml)` |
| `yaml-mapping-set!` | `(std text yaml)` |
| `yaml-mapping-style` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-mapping-tag` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-mapping?` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-node?` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-parse-port` | `(std text yaml reader)` |
| `yaml-parse-string` | `(std text yaml reader)` |
| `yaml-read` | `(std text yaml)` |
| `yaml-read-string` | `(std text yaml)` |
| `yaml-ref` | `(std text yaml)` |
| `yaml-scalar-anchor` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-scalar-eol-comment` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-scalar-pre-comments` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-scalar-style` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-scalar-tag` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-scalar-value` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-scalar?` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-sequence-anchor` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-sequence-append!` | `(std text yaml)` |
| `yaml-sequence-eol-comment` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-sequence-items` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-sequence-items-set!` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-sequence-length` | `(std text yaml)` |
| `yaml-sequence-post-comments` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-sequence-post-comments-set!` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-sequence-pre-comments` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-sequence-ref` | `(std text yaml)` |
| `yaml-sequence-style` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-sequence-tag` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-sequence?` | `(std text yaml nodes)`, `(std text yaml)` |
| `yaml-set!` | `(std text yaml)` |
| `yaml-write` | `(std text yaml)` |
| `yaml-write-string` | `(std text yaml)` |
| `yellow` | `(std cli style)` |
| `yield` | `(std csp)` |

### <a name="idx-z"></a>z

| Symbol | Modules |
| --- | --- |
| `zip` | `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, ... (+3) |
| `zip-append-child` | `(std zipper)` |
| `zip-branch?` | `(std zipper)` |
| `zip-children` | `(std zipper)` |
| `zip-down` | `(std zipper)` |
| `zip-edit` | `(std zipper)` |
| `zip-end?` | `(std zipper)` |
| `zip-insert-child` | `(std zipper)` |
| `zip-insert-left` | `(std zipper)` |
| `zip-insert-right` | `(std zipper)` |
| `zip-left` | `(std zipper)` |
| `zip-leftmost` | `(std zipper)` |
| `zip-lefts` | `(std zipper)` |
| `zip-next` | `(std zipper)` |
| `zip-node` | `(std zipper)` |
| `zip-path` | `(std zipper)` |
| `zip-prev` | `(std zipper)` |
| `zip-remove` | `(std zipper)` |
| `zip-replace` | `(std zipper)` |
| `zip-right` | `(std zipper)` |
| `zip-rightmost` | `(std zipper)` |
| `zip-rights` | `(std zipper)` |
| `zip-root` | `(std zipper)` |
| `zip-top?` | `(std zipper)` |
| `zip-up` | `(std zipper)` |
| `zip-with` | `(std misc list-more)` |
| `zipmap` | `(jerboa clojure)`, `(std clojure)` |
| `zipper` | `(std zipper)` |
| `zipper?` | `(std zipper)` |

## 3. Module catalog

All 626 modules sorted by name. Export count in parentheses.

| Module | Exports | Source file |
| --- | --- | --- |
| `(jerboa build musl)` | 14 | `lib/jerboa/build/musl.sls` |
| `(jerboa build)` | 27 | `lib/jerboa/build.sls` |
| `(jerboa cache)` | 7 | `lib/jerboa/cache.sls` |
| `(jerboa cloj)` | 3 | `lib/jerboa/cloj.sls` |
| `(jerboa clojure)` | 749 | `lib/jerboa/clojure.sls` |
| `(jerboa core)` | 172 | `lib/jerboa/core.sls` |
| `(jerboa cross)` | 21 | `lib/jerboa/cross.sls` |
| `(jerboa embed)` | 16 | `lib/jerboa/embed.sls` |
| `(jerboa ffi)` | 6 | `lib/jerboa/ffi.sls` |
| `(jerboa hot)` | 17 | `lib/jerboa/hot.sls` |
| `(jerboa lock)` | 19 | `lib/jerboa/lock.sls` |
| `(jerboa pkg)` | 25 | `lib/jerboa/pkg.sls` |
| `(jerboa prelude clean)` | 116 | `lib/jerboa/prelude/clean.sls` |
| `(jerboa prelude safe)` | 200 | `lib/jerboa/prelude/safe.sls` |
| `(jerboa prelude)` | 438 | `lib/jerboa/prelude.sls` |
| `(jerboa reader)` | 21 | `lib/jerboa/reader.sls` |
| `(jerboa registry)` | 9 | `lib/jerboa/registry.sls` |
| `(jerboa runtime)` | 55 | `lib/jerboa/runtime.sls` |
| `(jerboa translator)` | 22 | `lib/jerboa/translator.sls` |
| `(jerboa wasm closure)` | 3 | `lib/jerboa/wasm/closure.sls` |
| `(jerboa wasm codegen)` | 55 | `lib/jerboa/wasm/codegen.sls` |
| `(jerboa wasm format)` | 303 | `lib/jerboa/wasm/format.sls` |
| `(jerboa wasm gc)` | 4 | `lib/jerboa/wasm/gc.sls` |
| `(jerboa wasm runtime)` | 42 | `lib/jerboa/wasm/runtime.sls` |
| `(jerboa wasm scheme-runtime)` | 14 | `lib/jerboa/wasm/scheme-runtime.sls` |
| `(jerboa wasm values)` | 53 | `lib/jerboa/wasm/values.sls` |
| `(std actor bounded)` | 14 | `lib/std/actor/bounded.sls` |
| `(std actor checkpoint)` | 17 | `lib/std/actor/checkpoint.sls` |
| `(std actor cluster)` | 26 | `lib/std/actor/cluster.sls` |
| `(std actor cluster-security)` | 34 | `lib/std/actor/cluster-security.sls` |
| `(std actor core)` | 22 | `lib/std/actor/core.sls` |
| `(std actor crdt)` | 44 | `lib/std/actor/crdt.sls` |
| `(std actor deque)` | 7 | `lib/std/actor/deque.sls` |
| `(std actor distributed)` | 26 | `lib/std/actor/distributed.sls` |
| `(std actor engine)` | 7 | `lib/std/actor/engine.sls` |
| `(std actor mpsc)` | 9 | `lib/std/actor/mpsc.sls` |
| `(std actor protocol)` | 11 | `lib/std/actor/protocol.sls` |
| `(std actor registry)` | 6 | `lib/std/actor/registry.sls` |
| `(std actor scheduler)` | 9 | `lib/std/actor/scheduler.sls` |
| `(std actor supervisor)` | 14 | `lib/std/actor/supervisor.sls` |
| `(std actor transport)` | 9 | `lib/std/actor/transport.sls` |
| `(std actor)` | 57 | `lib/std/actor.sls` |
| `(std agent)` | 10 | `lib/std/agent.sls` |
| `(std amb)` | 5 | `lib/std/amb.sls` |
| `(std app)` | 9 | `lib/std/app.sls` |
| `(std arena)` | 17 | `lib/std/arena.sls` |
| `(std assert)` | 4 | `lib/std/assert.sls` |
| `(std async)` | 14 | `lib/std/async.sls` |
| `(std binary)` | 41 | `lib/std/binary.sls` |
| `(std borrow)` | 9 | `lib/std/borrow.sls` |
| `(std build cross)` | 31 | `lib/std/build/cross.sls` |
| `(std build reproducible)` | 40 | `lib/std/build/reproducible.sls` |
| `(std build sbom)` | 25 | `lib/std/build/sbom.sls` |
| `(std build verify)` | 11 | `lib/std/build/verify.sls` |
| `(std build watch)` | 32 | `lib/std/build/watch.sls` |
| `(std build)` | 9 | `lib/std/build.sls` |
| `(std cafe)` | 5 | `lib/std/cafe.sls` |
| `(std capability sandbox)` | 27 | `lib/std/capability/sandbox.sls` |
| `(std capability)` | 27 | `lib/std/capability.sls` |
| `(std circuit)` | 10 | `lib/std/circuit.sls` |
| `(std cli completion)` | 2 | `lib/std/cli/completion.sls` |
| `(std cli getopt)` | 14 | `lib/std/cli/getopt.sls` |
| `(std cli multicall)` | 8 | `lib/std/cli/multicall.sls` |
| `(std cli print-exit)` | 6 | `lib/std/cli/print-exit.sls` |
| `(std cli style)` | 20 | `lib/std/cli/style.sls` |
| `(std clojure io)` | 13 | `lib/std/clojure/io.sls` |
| `(std clojure reducers)` | 11 | `lib/std/clojure/reducers.sls` |
| `(std clojure seq)` | 39 | `lib/std/clojure/seq.sls` |
| `(std clojure string)` | 20 | `lib/std/clojure/string.sls` |
| `(std clojure)` | 207 | `lib/std/clojure.sls` |
| `(std clos)` | 111 | `lib/std/clos.sls` |
| `(std compat gambit)` | 4 | `lib/std/compat/gambit.sls` |
| `(std compat gerbil-import)` | 2 | `lib/std/compat/gerbil-import.sls` |
| `(std compile)` | 8 | `lib/std/compile.sls` |
| `(std compiler partial-eval)` | 16 | `lib/std/compiler/partial-eval.sls` |
| `(std compiler passes)` | 27 | `lib/std/compiler/passes.sls` |
| `(std compiler pattern)` | 18 | `lib/std/compiler/pattern.sls` |
| `(std compiler pgo)` | 15 | `lib/std/compiler/pgo.sls` |
| `(std component fiber)` | 19 | `lib/std/component/fiber.sls` |
| `(std component)` | 15 | `lib/std/component.sls` |
| `(std compress lz4)` | 4 | `lib/std/compress/lz4.sls` |
| `(std compress native-rust)` | 5 | `lib/std/compress/native-rust.sls` |
| `(std compress zlib)` | 8 | `lib/std/compress/zlib.sls` |
| `(std comptime)` | 6 | `lib/std/comptime.sls` |
| `(std concur async-await)` | 16 | `lib/std/concur/async-await.sls` |
| `(std concur deadlock)` | 17 | `lib/std/concur/deadlock.sls` |
| `(std concur hash)` | 36 | `lib/std/concur/hash.sls` |
| `(std concur stm)` | 7 | `lib/std/concur/stm.sls` |
| `(std concur structured)` | 11 | `lib/std/concur/structured.sls` |
| `(std concur util)` | 32 | `lib/std/concur/util.sls` |
| `(std concur)` | 20 | `lib/std/concur.sls` |
| `(std config)` | 15 | `lib/std/config.sls` |
| `(std content-address)` | 10 | `lib/std/content-address.sls` |
| `(std contract)` | 10 | `lib/std/contract.sls` |
| `(std contract2)` | 10 | `lib/std/contract2.sls` |
| `(std control coroutine)` | 8 | `lib/std/control/coroutine.sls` |
| `(std control delimited)` | 13 | `lib/std/control/delimited.sls` |
| `(std control marks)` | 4 | `lib/std/control/marks.sls` |
| `(std crypto aead)` | 3 | `lib/std/crypto/aead.sls` |
| `(std crypto bn)` | 16 | `lib/std/crypto/bn.sls` |
| `(std crypto cipher)` | 13 | `lib/std/crypto/cipher.sls` |
| `(std crypto compare)` | 2 | `lib/std/crypto/compare.sls` |
| `(std crypto dh)` | 12 | `lib/std/crypto/dh.sls` |
| `(std crypto digest)` | 8 | `lib/std/crypto/digest.sls` |
| `(std crypto etc)` | 3 | `lib/std/crypto/etc.sls` |
| `(std crypto hmac)` | 6 | `lib/std/crypto/hmac.sls` |
| `(std crypto kdf)` | 1 | `lib/std/crypto/kdf.sls` |
| `(std crypto native)` | 10 | `lib/std/crypto/native.sls` |
| `(std crypto native-rust)` | 18 | `lib/std/crypto/native-rust.sls` |
| `(std crypto password)` | 6 | `lib/std/crypto/password.sls` |
| `(std crypto pkey)` | 3 | `lib/std/crypto/pkey.sls` |
| `(std crypto random)` | 5 | `lib/std/crypto/random.sls` |
| `(std crypto secure-mem)` | 8 | `lib/std/crypto/secure-mem.sls` |
| `(std crypto x509)` | 2 | `lib/std/crypto/x509.sls` |
| `(std csp clj)` | 49 | `lib/std/csp/clj.sls` |
| `(std csp fiber-chan)` | 16 | `lib/std/csp/fiber-chan.sls` |
| `(std csp mix)` | 9 | `lib/std/csp/mix.sls` |
| `(std csp ops)` | 41 | `lib/std/csp/ops.sls` |
| `(std csp select)` | 10 | `lib/std/csp/select.sls` |
| `(std csp)` | 26 | `lib/std/csp.sls` |
| `(std csv)` | 8 | `lib/std/csv.sls` |
| `(std data pmap)` | 21 | `lib/std/data/pmap.sls` |
| `(std dataframe)` | 37 | `lib/std/dataframe.sls` |
| `(std datafy)` | 4 | `lib/std/datafy.sls` |
| `(std datalog)` | 8 | `lib/std/datalog.sls` |
| `(std datetime)` | 50 | `lib/std/datetime.sls` |
| `(std db conpool)` | 8 | `lib/std/db/conpool.sls` |
| `(std db dbi)` | 13 | `lib/std/db/dbi.sls` |
| `(std db duckdb)` | 28 | `lib/std/db/duckdb.sls` |
| `(std db duckdb-native)` | 33 | `lib/std/db/duckdb-native.sls` |
| `(std db leveldb)` | 44 | `lib/std/db/leveldb.sls` |
| `(std db postgresql)` | 30 | `lib/std/db/postgresql.sls` |
| `(std db postgresql-native)` | 10 | `lib/std/db/postgresql-native.sls` |
| `(std db query-compile)` | 14 | `lib/std/db/query-compile.sls` |
| `(std db sqlite)` | 28 | `lib/std/db/sqlite.sls` |
| `(std db sqlite-native)` | 33 | `lib/std/db/sqlite-native.sls` |
| `(std debug closure-inspect)` | 8 | `lib/std/debug/closure-inspect.sls` |
| `(std debug contract-monitor)` | 9 | `lib/std/debug/contract-monitor.sls` |
| `(std debug flamegraph)` | 25 | `lib/std/debug/flamegraph.sls` |
| `(std debug heap)` | 7 | `lib/std/debug/heap.sls` |
| `(std debug inspector)` | 9 | `lib/std/debug/inspector.sls` |
| `(std debug memleak)` | 6 | `lib/std/debug/memleak.sls` |
| `(std debug pp)` | 6 | `lib/std/debug/pp.sls` |
| `(std debug record-inspect)` | 9 | `lib/std/debug/record-inspect.sls` |
| `(std debug replay)` | 10 | `lib/std/debug/replay.sls` |
| `(std debug threads)` | 6 | `lib/std/debug/threads.sls` |
| `(std debug timetravel)` | 27 | `lib/std/debug/timetravel.sls` |
| `(std deprecation)` | 4 | `lib/std/deprecation.sls` |
| `(std derive)` | 14 | `lib/std/derive.sls` |
| `(std derive2)` | 13 | `lib/std/derive2.sls` |
| `(std dev benchmark)` | 22 | `lib/std/dev/benchmark.sls` |
| `(std dev cont-mark-opt)` | 10 | `lib/std/dev/cont-mark-opt.sls` |
| `(std dev debug)` | 24 | `lib/std/dev/debug.sls` |
| `(std dev devirt)` | 9 | `lib/std/dev/devirt.sls` |
| `(std dev partial-eval)` | 6 | `lib/std/dev/partial-eval.sls` |
| `(std dev pgo)` | 11 | `lib/std/dev/pgo.sls` |
| `(std dev profile)` | 15 | `lib/std/dev/profile.sls` |
| `(std dev reload)` | 14 | `lib/std/dev/reload.sls` |
| `(std distributed)` | 9 | `lib/std/distributed.sls` |
| `(std doc generator)` | 15 | `lib/std/doc/generator.sls` |
| `(std doc)` | 8 | `lib/std/doc.sls` |
| `(std ds sorted-map)` | 15 | `lib/std/ds/sorted-map.sls` |
| `(std effect deep)` | 2 | `lib/std/effect/deep.sls` |
| `(std effect fusion)` | 4 | `lib/std/effect/fusion.sls` |
| `(std effect io)` | 10 | `lib/std/effect/io.sls` |
| `(std effect multishot)` | 12 | `lib/std/effect/multishot.sls` |
| `(std effect resource)` | 3 | `lib/std/effect/resource.sls` |
| `(std effect scoped)` | 6 | `lib/std/effect/scoped.sls` |
| `(std effect state)` | 5 | `lib/std/effect/state.sls` |
| `(std effect)` | 8 | `lib/std/effect.sls` |
| `(std engine)` | 7 | `lib/std/engine.sls` |
| `(std ephemeron)` | 9 | `lib/std/ephemeron.sls` |
| `(std ergo)` | 4 | `lib/std/ergo.sls` |
| `(std errdefer)` | 3 | `lib/std/errdefer.sls` |
| `(std error conditions)` | 122 | `lib/std/error/conditions.sls` |
| `(std error context)` | 10 | `lib/std/error/context.sls` |
| `(std error diagnostics)` | 10 | `lib/std/error/diagnostics.sls` |
| `(std error recovery)` | 5 | `lib/std/error/recovery.sls` |
| `(std error)` | 11 | `lib/std/error.sls` |
| `(std error-advice)` | 8 | `lib/std/error-advice.sls` |
| `(std errors)` | 27 | `lib/std/errors.sls` |
| `(std event)` | 11 | `lib/std/event.sls` |
| `(std event-source)` | 11 | `lib/std/event-source.sls` |
| `(std fasl)` | 6 | `lib/std/fasl.sls` |
| `(std ffi cairo)` | 425 | `lib/std/ffi/cairo.sls` |
| `(std ffi curl)` | 270 | `lib/std/ffi/curl.sls` |
| `(std ffi gl)` | 1230 | `lib/std/ffi/gl.sls` |
| `(std ffi glu)` | 211 | `lib/std/ffi/glu.sls` |
| `(std ffi glut)` | 169 | `lib/std/ffi/glut.sls` |
| `(std ffi lmdb)` | 143 | `lib/std/ffi/lmdb.sls` |
| `(std ffi nanomsg)` | 174 | `lib/std/ffi/nanomsg.sls` |
| `(std ffi netstring)` | 3 | `lib/std/ffi/netstring.sls` |
| `(std ffi qrencode)` | 9 | `lib/std/ffi/qrencode.sls` |
| `(std ffi redis)` | 2 | `lib/std/ffi/redis.sls` |
| `(std ffi sdl2 image)` | 41 | `lib/std/ffi/sdl2/image.sls` |
| `(std ffi sdl2 mixer)` | 77 | `lib/std/ffi/sdl2/mixer.sls` |
| `(std ffi sdl2 net)` | 51 | `lib/std/ffi/sdl2/net.sls` |
| `(std ffi sdl2 ttf)` | 45 | `lib/std/ffi/sdl2/ttf.sls` |
| `(std ffi sdl2)` | 587 | `lib/std/ffi/sdl2.sls` |
| `(std ffi sql-null)` | 6 | `lib/std/ffi/sql-null.sls` |
| `(std ffi usb)` | 29 | `lib/std/ffi/usb.sls` |
| `(std fiber)` | 59 | `lib/std/fiber.sls` |
| `(std fixnum)` | 36 | `lib/std/fixnum.sls` |
| `(std foreign bind)` | 15 | `lib/std/foreign/bind.sls` |
| `(std foreign)` | 17 | `lib/std/foreign.sls` |
| `(std format)` | 7 | `lib/std/format.sls` |
| `(std frp)` | 13 | `lib/std/frp.sls` |
| `(std ftype)` | 16 | `lib/std/ftype.sls` |
| `(std gambit-compat)` | 218 | `lib/std/gambit-compat.sls` |
| `(std generic)` | 3 | `lib/std/generic.sls` |
| `(std guardian)` | 4 | `lib/std/guardian.sls` |
| `(std health)` | 13 | `lib/std/health.sls` |
| `(std image)` | 9 | `lib/std/image.sls` |
| `(std immutable)` | 49 | `lib/std/immutable.sls` |
| `(std injest)` | 2 | `lib/std/injest.sls` |
| `(std inspect)` | 8 | `lib/std/inspect.sls` |
| `(std interface)` | 7 | `lib/std/interface.sls` |
| `(std interpolate)` | 1 | `lib/std/interpolate.sls` |
| `(std io bio)` | 17 | `lib/std/io/bio.sls` |
| `(std io delimited)` | 7 | `lib/std/io/delimited.sls` |
| `(std io filepool)` | 11 | `lib/std/io/filepool.sls` |
| `(std io raw)` | 9 | `lib/std/io/raw.sls` |
| `(std io strio)` | 16 | `lib/std/io/strio.sls` |
| `(std io)` | 8 | `lib/std/io.sls` |
| `(std iter)` | 19 | `lib/std/iter.sls` |
| `(std lazy)` | 18 | `lib/std/lazy.sls` |
| `(std lens)` | 21 | `lib/std/lens.sls` |
| `(std lint)` | 21 | `lib/std/lint.sls` |
| `(std log)` | 16 | `lib/std/log.sls` |
| `(std logger)` | 12 | `lib/std/logger.sls` |
| `(std logic)` | 20 | `lib/std/logic.sls` |
| `(std lsp server)` | 6 | `lib/std/lsp/server.sls` |
| `(std lsp symbols)` | 4 | `lib/std/lsp/symbols.sls` |
| `(std lsp)` | 40 | `lib/std/lsp.sls` |
| `(std macro-types)` | 9 | `lib/std/macro-types.sls` |
| `(std markup html-parser)` | 3 | `lib/std/markup/html-parser.sls` |
| `(std markup ssax)` | 4 | `lib/std/markup/ssax.sls` |
| `(std markup sxml)` | 11 | `lib/std/markup/sxml.sls` |
| `(std markup sxml-path)` | 7 | `lib/std/markup/sxml-path.sls` |
| `(std markup sxml-print)` | 3 | `lib/std/markup/sxml-print.sls` |
| `(std markup tal)` | 5 | `lib/std/markup/tal.sls` |
| `(std markup xml)` | 6 | `lib/std/markup/xml.sls` |
| `(std match-syntax)` | 36 | `lib/std/match-syntax.sls` |
| `(std match2)` | 10 | `lib/std/match2.sls` |
| `(std metrics)` | 22 | `lib/std/metrics.sls` |
| `(std mime struct)` | 12 | `lib/std/mime/struct.sls` |
| `(std mime types)` | 6 | `lib/std/mime/types.sls` |
| `(std misc advice)` | 7 | `lib/std/misc/advice.sls` |
| `(std misc alist)` | 35 | `lib/std/misc/alist.sls` |
| `(std misc alist-more)` | 8 | `lib/std/misc/alist-more.sls` |
| `(std misc amb)` | 5 | `lib/std/misc/amb.sls` |
| `(std misc atom)` | 17 | `lib/std/misc/atom.sls` |
| `(std misc barrier)` | 6 | `lib/std/misc/barrier.sls` |
| `(std misc binary-type)` | 18 | `lib/std/misc/binary-type.sls` |
| `(std misc bytes)` | 7 | `lib/std/misc/bytes.sls` |
| `(std misc channel)` | 11 | `lib/std/misc/channel.sls` |
| `(std misc chaperone)` | 12 | `lib/std/misc/chaperone.sls` |
| `(std misc ck-macros)` | 13 | `lib/std/misc/ck-macros.sls` |
| `(std misc collection)` | 11 | `lib/std/misc/collection.sls` |
| `(std misc completion)` | 6 | `lib/std/misc/completion.sls` |
| `(std misc config)` | 13 | `lib/std/misc/config.sls` |
| `(std misc cont-marks)` | 6 | `lib/std/misc/cont-marks.sls` |
| `(std misc custodian)` | 9 | `lib/std/misc/custodian.sls` |
| `(std misc dag)` | 13 | `lib/std/misc/dag.sls` |
| `(std misc decimal)` | 19 | `lib/std/misc/decimal.sls` |
| `(std misc delimited)` | 5 | `lib/std/misc/delimited.sls` |
| `(std misc deque)` | 19 | `lib/std/misc/deque.sls` |
| `(std misc diff)` | 6 | `lib/std/misc/diff.sls` |
| `(std misc equiv)` | 2 | `lib/std/misc/equiv.sls` |
| `(std misc evector)` | 10 | `lib/std/misc/evector.sls` |
| `(std misc event)` | 16 | `lib/std/misc/event.sls` |
| `(std misc event-emitter)` | 10 | `lib/std/misc/event-emitter.sls` |
| `(std misc fmt)` | 5 | `lib/std/misc/fmt.sls` |
| `(std misc func)` | 18 | `lib/std/misc/func.sls` |
| `(std misc guardian-pool)` | 10 | `lib/std/misc/guardian-pool.sls` |
| `(std misc hash-more)` | 17 | `lib/std/misc/hash-more.sls` |
| `(std misc heap)` | 11 | `lib/std/misc/heap.sls` |
| `(std misc highlight)` | 7 | `lib/std/misc/highlight.sls` |
| `(std misc lazy-seq)` | 16 | `lib/std/misc/lazy-seq.sls` |
| `(std misc list)` | 61 | `lib/std/misc/list.sls` |
| `(std misc list-builder)` | 1 | `lib/std/misc/list-builder.sls` |
| `(std misc list-more)` | 11 | `lib/std/misc/list-more.sls` |
| `(std misc lru-cache)` | 13 | `lib/std/misc/lru-cache.sls` |
| `(std misc memo)` | 9 | `lib/std/misc/memo.sls` |
| `(std misc memoize)` | 4 | `lib/std/misc/memoize.sls` |
| `(std misc meta)` | 5 | `lib/std/misc/meta.sls` |
| `(std misc nested)` | 7 | `lib/std/misc/nested.sls` |
| `(std misc number)` | 9 | `lib/std/misc/number.sls` |
| `(std misc numeric)` | 7 | `lib/std/misc/numeric.sls` |
| `(std misc path)` | 5 | `lib/std/misc/path.sls` |
| `(std misc persistent)` | 13 | `lib/std/misc/persistent.sls` |
| `(std misc plist)` | 9 | `lib/std/misc/plist.sls` |
| `(std misc pool)` | 7 | `lib/std/misc/pool.sls` |
| `(std misc port-utils)` | 6 | `lib/std/misc/port-utils.sls` |
| `(std misc ports)` | 7 | `lib/std/misc/ports.sls` |
| `(std misc pqueue)` | 10 | `lib/std/misc/pqueue.sls` |
| `(std misc prime)` | 9 | `lib/std/misc/prime.sls` |
| `(std misc process)` | 15 | `lib/std/misc/process.sls` |
| `(std misc profile)` | 7 | `lib/std/misc/profile.sls` |
| `(std misc queue)` | 8 | `lib/std/misc/queue.sls` |
| `(std misc rate-limiter)` | 7 | `lib/std/misc/rate-limiter.sls` |
| `(std misc rbtree)` | 12 | `lib/std/misc/rbtree.sls` |
| `(std misc relation)` | 15 | `lib/std/misc/relation.sls` |
| `(std misc repr)` | 7 | `lib/std/misc/repr.sls` |
| `(std misc result)` | 21 | `lib/std/misc/result.sls` |
| `(std misc retry)` | 15 | `lib/std/misc/retry.sls` |
| `(std misc ringbuf)` | 14 | `lib/std/misc/ringbuf.sls` |
| `(std misc rwlock)` | 8 | `lib/std/misc/rwlock.sls` |
| `(std misc shared)` | 7 | `lib/std/misc/shared.sls` |
| `(std misc shuffle)` | 2 | `lib/std/misc/shuffle.sls` |
| `(std misc spinlock)` | 5 | `lib/std/misc/spinlock.sls` |
| `(std misc state-machine)` | 9 | `lib/std/misc/state-machine.sls` |
| `(std misc string)` | 12 | `lib/std/misc/string.sls` |
| `(std misc string-more)` | 20 | `lib/std/misc/string-more.sls` |
| `(std misc symbol)` | 5 | `lib/std/misc/symbol.sls` |
| `(std misc terminal)` | 26 | `lib/std/misc/terminal.sls` |
| `(std misc thread)` | 31 | `lib/std/misc/thread.sls` |
| `(std misc timeout)` | 6 | `lib/std/misc/timeout.sls` |
| `(std misc trie)` | 11 | `lib/std/misc/trie.sls` |
| `(std misc typeclass)` | 12 | `lib/std/misc/typeclass.sls` |
| `(std misc uuid)` | 2 | `lib/std/misc/uuid.sls` |
| `(std misc validate)` | 30 | `lib/std/misc/validate.sls` |
| `(std misc vector-more)` | 7 | `lib/std/misc/vector-more.sls` |
| `(std misc walist)` | 7 | `lib/std/misc/walist.sls` |
| `(std misc weak)` | 13 | `lib/std/misc/weak.sls` |
| `(std misc wg)` | 5 | `lib/std/misc/wg.sls` |
| `(std misc with-destroy)` | 2 | `lib/std/misc/with-destroy.sls` |
| `(std mmap-btree)` | 19 | `lib/std/mmap-btree.sls` |
| `(std move)` | 7 | `lib/std/move.sls` |
| `(std multi)` | 7 | `lib/std/multi.sls` |
| `(std mvcc)` | 10 | `lib/std/mvcc.sls` |
| `(std native)` | 2 | `lib/std/native.sls` |
| `(std net 9p)` | 103 | `lib/std/net/9p.sls` |
| `(std net address)` | 10 | `lib/std/net/address.sls` |
| `(std net bio)` | 12 | `lib/std/net/bio.sls` |
| `(std net connpool)` | 8 | `lib/std/net/connpool.sls` |
| `(std net dns)` | 21 | `lib/std/net/dns.sls` |
| `(std net fiber-httpd)` | 44 | `lib/std/net/fiber-httpd.sls` |
| `(std net fiber-ws)` | 9 | `lib/std/net/fiber-ws.sls` |
| `(std net grpc)` | 13 | `lib/std/net/grpc.sls` |
| `(std net http2)` | 27 | `lib/std/net/http2.sls` |
| `(std net httpd)` | 28 | `lib/std/net/httpd.sls` |
| `(std net io)` | 16 | `lib/std/net/io.sls` |
| `(std net json-rpc)` | 10 | `lib/std/net/json-rpc.sls` |
| `(std net pool)` | 10 | `lib/std/net/pool.sls` |
| `(std net rate)` | 17 | `lib/std/net/rate.sls` |
| `(std net repl)` | 4 | `lib/std/net/repl.sls` |
| `(std net request)` | 26 | `lib/std/net/request.sls` |
| `(std net resolve)` | 6 | `lib/std/net/resolve.sls` |
| `(std net ring)` | 18 | `lib/std/net/ring.sls` |
| `(std net router)` | 17 | `lib/std/net/router.sls` |
| `(std net s3)` | 7 | `lib/std/net/s3.sls` |
| `(std net sasl)` | 5 | `lib/std/net/sasl.sls` |
| `(std net security-headers)` | 6 | `lib/std/net/security-headers.sls` |
| `(std net sendfile)` | 2 | `lib/std/net/sendfile.sls` |
| `(std net smtp)` | 12 | `lib/std/net/smtp.sls` |
| `(std net socks)` | 4 | `lib/std/net/socks.sls` |
| `(std net socks5-server)` | 6 | `lib/std/net/socks5-server.sls` |
| `(std net ssh auth)` | 4 | `lib/std/net/ssh/auth.sls` |
| `(std net ssh channel)` | 40 | `lib/std/net/ssh/channel.sls` |
| `(std net ssh client)` | 22 | `lib/std/net/ssh/client.sls` |
| `(std net ssh conditions)` | 50 | `lib/std/net/ssh/conditions.sls` |
| `(std net ssh forward)` | 10 | `lib/std/net/ssh/forward.sls` |
| `(std net ssh kex)` | 6 | `lib/std/net/ssh/kex.sls` |
| `(std net ssh known-hosts)` | 4 | `lib/std/net/ssh/known-hosts.sls` |
| `(std net ssh session)` | 5 | `lib/std/net/ssh/session.sls` |
| `(std net ssh sftp)` | 33 | `lib/std/net/ssh/sftp.sls` |
| `(std net ssh transport)` | 60 | `lib/std/net/ssh/transport.sls` |
| `(std net ssh wire)` | 59 | `lib/std/net/ssh/wire.sls` |
| `(std net ssh)` | 81 | `lib/std/net/ssh.sls` |
| `(std net ssl)` | 25 | `lib/std/net/ssl.sls` |
| `(std net tcp)` | 9 | `lib/std/net/tcp.sls` |
| `(std net tcp-raw)` | 9 | `lib/std/net/tcp-raw.sls` |
| `(std net timeout)` | 27 | `lib/std/net/timeout.sls` |
| `(std net tls)` | 21 | `lib/std/net/tls.sls` |
| `(std net tls-rustls)` | 13 | `lib/std/net/tls-rustls.sls` |
| `(std net udp)` | 7 | `lib/std/net/udp.sls` |
| `(std net uri)` | 13 | `lib/std/net/uri.sls` |
| `(std net websocket)` | 24 | `lib/std/net/websocket.sls` |
| `(std net workpool)` | 5 | `lib/std/net/workpool.sls` |
| `(std net zero-copy)` | 13 | `lib/std/net/zero-copy.sls` |
| `(std notebook)` | 11 | `lib/std/notebook.sls` |
| `(std nrepl)` | 4 | `lib/std/nrepl.sls` |
| `(std odb)` | 32 | `lib/std/odb.sls` |
| `(std os antidebug)` | 10 | `lib/std/os/antidebug.sls` |
| `(std os env)` | 3 | `lib/std/os/env.sls` |
| `(std os epoll)` | 22 | `lib/std/os/epoll.sls` |
| `(std os epoll-native)` | 20 | `lib/std/os/epoll-native.sls` |
| `(std os fcntl)` | 15 | `lib/std/os/fcntl.sls` |
| `(std os fd)` | 27 | `lib/std/os/fd.sls` |
| `(std os fdio)` | 6 | `lib/std/os/fdio.sls` |
| `(std os file-info)` | 15 | `lib/std/os/file-info.sls` |
| `(std os flock)` | 10 | `lib/std/os/flock.sls` |
| `(std os inotify)` | 36 | `lib/std/os/inotify.sls` |
| `(std os inotify-native)` | 34 | `lib/std/os/inotify-native.sls` |
| `(std os integrity)` | 9 | `lib/std/os/integrity.sls` |
| `(std os iouring)` | 13 | `lib/std/os/iouring.sls` |
| `(std os kqueue)` | 20 | `lib/std/os/kqueue.sls` |
| `(std os landlock)` | 7 | `lib/std/os/landlock.sls` |
| `(std os landlock-native)` | 28 | `lib/std/os/landlock-native.sls` |
| `(std os mmap)` | 35 | `lib/std/os/mmap.sls` |
| `(std os path)` | 9 | `lib/std/os/path.sls` |
| `(std os path-util)` | 14 | `lib/std/os/path-util.sls` |
| `(std os pipe)` | 2 | `lib/std/os/pipe.sls` |
| `(std os platform)` | 10 | `lib/std/os/platform.sls` |
| `(std os posix)` | 143 | `lib/std/os/posix.sls` |
| `(std os sandbox)` | 6 | `lib/std/os/sandbox.sls` |
| `(std os seccomp)` | 7 | `lib/std/os/seccomp.sls` |
| `(std os shell)` | 14 | `lib/std/os/shell.sls` |
| `(std os signal)` | 32 | `lib/std/os/signal.sls` |
| `(std os signal-channel)` | 9 | `lib/std/os/signal-channel.sls` |
| `(std os signalfd)` | 6 | `lib/std/os/signalfd.sls` |
| `(std os temp)` | 4 | `lib/std/os/temp.sls` |
| `(std os temporaries)` | 5 | `lib/std/os/temporaries.sls` |
| `(std os tty)` | 3 | `lib/std/os/tty.sls` |
| `(std parser deflexer)` | 11 | `lib/std/parser/deflexer.sls` |
| `(std parser defparser)` | 6 | `lib/std/parser/defparser.sls` |
| `(std parser)` | 24 | `lib/std/parser.sls` |
| `(std pcap)` | 5 | `lib/std/pcap.sls` |
| `(std pcre2)` | 35 | `lib/std/pcre2.sls` |
| `(std peg)` | 6 | `lib/std/peg.sls` |
| `(std persist closure)` | 6 | `lib/std/persist/closure.sls` |
| `(std persist image)` | 6 | `lib/std/persist/image.sls` |
| `(std pipeline)` | 21 | `lib/std/pipeline.sls` |
| `(std pmap)` | 32 | `lib/std/pmap.sls` |
| `(std port-position)` | 5 | `lib/std/port-position.sls` |
| `(std pqueue)` | 10 | `lib/std/pqueue.sls` |
| `(std pregexp)` | 8 | `lib/std/pregexp.sls` |
| `(std prelude)` | 300 | `lib/std/prelude.sls` |
| `(std proc supervisor)` | 19 | `lib/std/proc/supervisor.sls` |
| `(std profile)` | 5 | `lib/std/profile.sls` |
| `(std proptest)` | 39 | `lib/std/proptest.sls` |
| `(std protobuf grammar)` | 23 | `lib/std/protobuf/grammar.sls` |
| `(std protobuf macros)` | 3 | `lib/std/protobuf/macros.sls` |
| `(std protobuf)` | 25 | `lib/std/protobuf.sls` |
| `(std protocol)` | 7 | `lib/std/protocol.sls` |
| `(std pset)` | 43 | `lib/std/pset.sls` |
| `(std pvec)` | 22 | `lib/std/pvec.sls` |
| `(std python)` | 20 | `lib/std/python.sls` |
| `(std quasiquote-types)` | 10 | `lib/std/quasiquote-types.sls` |
| `(std query)` | 24 | `lib/std/query.sls` |
| `(std raft)` | 16 | `lib/std/raft.sls` |
| `(std record-meta)` | 13 | `lib/std/record-meta.sls` |
| `(std ref)` | 3 | `lib/std/ref.sls` |
| `(std regex)` | 18 | `lib/std/regex.sls` |
| `(std regex-ct)` | 8 | `lib/std/regex-ct.sls` |
| `(std regex-ct-impl)` | 27 | `lib/std/regex-ct-impl.sls` |
| `(std regex-native)` | 6 | `lib/std/regex-native.sls` |
| `(std region)` | 9 | `lib/std/region.sls` |
| `(std repl middleware)` | 16 | `lib/std/repl/middleware.sls` |
| `(std repl notebook)` | 19 | `lib/std/repl/notebook.sls` |
| `(std repl server)` | 5 | `lib/std/repl/server.sls` |
| `(std repl)` | 19 | `lib/std/repl.sls` |
| `(std resource)` | 4 | `lib/std/resource.sls` |
| `(std result)` | 25 | `lib/std/result.sls` |
| `(std rewrite)` | 20 | `lib/std/rewrite.sls` |
| `(std rx patterns)` | 33 | `lib/std/rx/patterns.sls` |
| `(std rx)` | 2 | `lib/std/rx.sls` |
| `(std safe)` | 32 | `lib/std/safe.sls` |
| `(std safe-fasl)` | 10 | `lib/std/safe-fasl.sls` |
| `(std safe-timeout)` | 5 | `lib/std/safe-timeout.sls` |
| `(std sched)` | 11 | `lib/std/sched.sls` |
| `(std schema)` | 29 | `lib/std/schema.sls` |
| `(std secure compiler)` | 21 | `lib/std/secure/compiler.sls` |
| `(std secure link)` | 14 | `lib/std/secure/link.sls` |
| `(std secure preamble)` | 10 | `lib/std/secure/preamble.sls` |
| `(std secure wasm-target)` | 6 | `lib/std/secure/wasm-target.sls` |
| `(std security audit)` | 7 | `lib/std/security/audit.sls` |
| `(std security auth)` | 19 | `lib/std/security/auth.sls` |
| `(std security cage)` | 18 | `lib/std/security/cage.sls` |
| `(std security capability)` | 27 | `lib/std/security/capability.sls` |
| `(std security capability-typed)` | 4 | `lib/std/security/capability-typed.sls` |
| `(std security capsicum)` | 16 | `lib/std/security/capsicum.sls` |
| `(std security errors)` | 14 | `lib/std/security/errors.sls` |
| `(std security flow)` | 21 | `lib/std/security/flow.sls` |
| `(std security import-audit)` | 8 | `lib/std/security/import-audit.sls` |
| `(std security io-intercept)` | 13 | `lib/std/security/io-intercept.sls` |
| `(std security landlock)` | 10 | `lib/std/security/landlock.sls` |
| `(std security metrics)` | 10 | `lib/std/security/metrics.sls` |
| `(std security privsep)` | 12 | `lib/std/security/privsep.sls` |
| `(std security restrict)` | 4 | `lib/std/security/restrict.sls` |
| `(std security sandbox)` | 21 | `lib/std/security/sandbox.sls` |
| `(std security sanitize)` | 17 | `lib/std/security/sanitize.sls` |
| `(std security seatbelt)` | 7 | `lib/std/security/seatbelt.sls` |
| `(std security seccomp)` | 13 | `lib/std/security/seccomp.sls` |
| `(std security secret)` | 7 | `lib/std/security/secret.sls` |
| `(std security taint)` | 25 | `lib/std/security/taint.sls` |
| `(std select)` | 6 | `lib/std/select.sls` |
| `(std seq)` | 52 | `lib/std/seq.sls` |
| `(std service config)` | 15 | `lib/std/service/config.sls` |
| `(std service control)` | 20 | `lib/std/service/control.sls` |
| `(std service multilog)` | 1 | `lib/std/service/multilog.sls` |
| `(std service supervise)` | 1 | `lib/std/service/supervise.sls` |
| `(std service svscan)` | 1 | `lib/std/service/svscan.sls` |
| `(std sort)` | 4 | `lib/std/sort.sls` |
| `(std sorted-set)` | 13 | `lib/std/sorted-set.sls` |
| `(std source)` | 3 | `lib/std/source.sls` |
| `(std span)` | 15 | `lib/std/span.sls` |
| `(std spec)` | 23 | `lib/std/spec.sls` |
| `(std specialize)` | 8 | `lib/std/specialize.sls` |
| `(std specter)` | 31 | `lib/std/specter.sls` |
| `(std srfi srfi-1)` | 71 | `lib/std/srfi/srfi-1.sls` |
| `(std srfi srfi-101)` | 17 | `lib/std/srfi/srfi-101.sls` |
| `(std srfi srfi-113)` | 26 | `lib/std/srfi/srfi-113.sls` |
| `(std srfi srfi-115)` | 15 | `lib/std/srfi/srfi-115.sls` |
| `(std srfi srfi-116)` | 21 | `lib/std/srfi/srfi-116.sls` |
| `(std srfi srfi-117)` | 15 | `lib/std/srfi/srfi-117.sls` |
| `(std srfi srfi-121)` | 17 | `lib/std/srfi/srfi-121.sls` |
| `(std srfi srfi-124)` | 5 | `lib/std/srfi/srfi-124.sls` |
| `(std srfi srfi-125)` | 21 | `lib/std/srfi/srfi-125.sls` |
| `(std srfi srfi-127)` | 21 | `lib/std/srfi/srfi-127.sls` |
| `(std srfi srfi-128)` | 23 | `lib/std/srfi/srfi-128.sls` |
| `(std srfi srfi-13)` | 30 | `lib/std/srfi/srfi-13.sls` |
| `(std srfi srfi-130)` | 16 | `lib/std/srfi/srfi-130.sls` |
| `(std srfi srfi-132)` | 12 | `lib/std/srfi/srfi-132.sls` |
| `(std srfi srfi-133)` | 20 | `lib/std/srfi/srfi-133.sls` |
| `(std srfi srfi-134)` | 20 | `lib/std/srfi/srfi-134.sls` |
| `(std srfi srfi-135)` | 25 | `lib/std/srfi/srfi-135.sls` |
| `(std srfi srfi-14)` | 48 | `lib/std/srfi/srfi-14.sls` |
| `(std srfi srfi-141)` | 18 | `lib/std/srfi/srfi-141.sls` |
| `(std srfi srfi-143)` | 28 | `lib/std/srfi/srfi-143.sls` |
| `(std srfi srfi-144)` | 37 | `lib/std/srfi/srfi-144.sls` |
| `(std srfi srfi-145)` | 1 | `lib/std/srfi/srfi-145.sls` |
| `(std srfi srfi-146)` | 26 | `lib/std/srfi/srfi-146.sls` |
| `(std srfi srfi-151)` | 21 | `lib/std/srfi/srfi-151.sls` |
| `(std srfi srfi-158)` | 33 | `lib/std/srfi/srfi-158.sls` |
| `(std srfi srfi-159)` | 33 | `lib/std/srfi/srfi-159.sls` |
| `(std srfi srfi-160)` | 100 | `lib/std/srfi/srfi-160.sls` |
| `(std srfi srfi-19)` | 29 | `lib/std/srfi/srfi-19.sls` |
| `(std srfi srfi-212)` | 1 | `lib/std/srfi/srfi-212.sls` |
| `(std srfi srfi-41)` | 21 | `lib/std/srfi/srfi-41.sls` |
| `(std srfi srfi-42)` | 23 | `lib/std/srfi/srfi-42.sls` |
| `(std srfi srfi-43)` | 20 | `lib/std/srfi/srfi-43.sls` |
| `(std srfi srfi-8)` | 1 | `lib/std/srfi/srfi-8.sls` |
| `(std srfi srfi-9)` | 1 | `lib/std/srfi/srfi-9.sls` |
| `(std srfi srfi-95)` | 5 | `lib/std/srfi/srfi-95.sls` |
| `(std staging)` | 12 | `lib/std/staging.sls` |
| `(std staging2)` | 18 | `lib/std/staging2.sls` |
| `(std stm)` | 16 | `lib/std/stm.sls` |
| `(std stream async)` | 10 | `lib/std/stream/async.sls` |
| `(std stream window)` | 26 | `lib/std/stream/window.sls` |
| `(std string)` | 31 | `lib/std/string.sls` |
| `(std stxutil)` | 14 | `lib/std/stxutil.sls` |
| `(std sugar)` | 37 | `lib/std/sugar.sls` |
| `(std symbol-property)` | 4 | `lib/std/symbol-property.sls` |
| `(std table)` | 28 | `lib/std/table.sls` |
| `(std taint)` | 26 | `lib/std/taint.sls` |
| `(std task)` | 16 | `lib/std/task.sls` |
| `(std test check)` | 29 | `lib/std/test/check.sls` |
| `(std test framework)` | 27 | `lib/std/test/framework.sls` |
| `(std test fuzz)` | 22 | `lib/std/test/fuzz.sls` |
| `(std test quickcheck)` | 21 | `lib/std/test/quickcheck.sls` |
| `(std test)` | 18 | `lib/std/test.sls` |
| `(std text base58)` | 4 | `lib/std/text/base58.sls` |
| `(std text base64)` | 4 | `lib/std/text/base64.sls` |
| `(std text cbor)` | 4 | `lib/std/text/cbor.sls` |
| `(std text char-set)` | 20 | `lib/std/text/char-set.sls` |
| `(std text csv)` | 8 | `lib/std/text/csv.sls` |
| `(std text diff)` | 6 | `lib/std/text/diff.sls` |
| `(std text edn)` | 15 | `lib/std/text/edn.sls` |
| `(std text glob)` | 4 | `lib/std/text/glob.sls` |
| `(std text hex)` | 4 | `lib/std/text/hex.sls` |
| `(std text html)` | 5 | `lib/std/text/html.sls` |
| `(std text ini)` | 4 | `lib/std/text/ini.sls` |
| `(std text json)` | 6 | `lib/std/text/json.sls` |
| `(std text json-schema)` | 14 | `lib/std/text/json-schema.sls` |
| `(std text msgpack)` | 4 | `lib/std/text/msgpack.sls` |
| `(std text printf)` | 4 | `lib/std/text/printf.sls` |
| `(std text regex-compile)` | 46 | `lib/std/text/regex-compile.sls` |
| `(std text template)` | 7 | `lib/std/text/template.sls` |
| `(std text toml)` | 3 | `lib/std/text/toml.sls` |
| `(std text utf16)` | 6 | `lib/std/text/utf16.sls` |
| `(std text utf32)` | 4 | `lib/std/text/utf32.sls` |
| `(std text utf8)` | 5 | `lib/std/text/utf8.sls` |
| `(std text xml)` | 8 | `lib/std/text/xml.sls` |
| `(std text yaml nodes)` | 44 | `lib/std/text/yaml/nodes.sls` |
| `(std text yaml reader)` | 2 | `lib/std/text/yaml/reader.sls` |
| `(std text yaml writer)` | 2 | `lib/std/text/yaml/writer.sls` |
| `(std text yaml)` | 66 | `lib/std/text/yaml.sls` |
| `(std time)` | 19 | `lib/std/time.sls` |
| `(std trace)` | 6 | `lib/std/trace.sls` |
| `(std transducer)` | 32 | `lib/std/transducer.sls` |
| `(std transit)` | 16 | `lib/std/transit.sls` |
| `(std typed advanced)` | 18 | `lib/std/typed/advanced.sls` |
| `(std typed affine)` | 8 | `lib/std/typed/affine.sls` |
| `(std typed check)` | 7 | `lib/std/typed/check.sls` |
| `(std typed effect-typing)` | 7 | `lib/std/typed/effect-typing.sls` |
| `(std typed effects)` | 18 | `lib/std/typed/effects.sls` |
| `(std typed env)` | 7 | `lib/std/typed/env.sls` |
| `(std typed gadt)` | 6 | `lib/std/typed/gadt.sls` |
| `(std typed hkt)` | 28 | `lib/std/typed/hkt.sls` |
| `(std typed infer)` | 13 | `lib/std/typed/infer.sls` |
| `(std typed linear)` | 8 | `lib/std/typed/linear.sls` |
| `(std typed monad)` | 33 | `lib/std/typed/monad.sls` |
| `(std typed phantom)` | 9 | `lib/std/typed/phantom.sls` |
| `(std typed refine)` | 20 | `lib/std/typed/refine.sls` |
| `(std typed row2)` | 22 | `lib/std/typed/row2.sls` |
| `(std typed solver)` | 14 | `lib/std/typed/solver.sls` |
| `(std typed typeclass)` | 5 | `lib/std/typed/typeclass.sls` |
| `(std typed)` | 16 | `lib/std/typed.sls` |
| `(std values)` | 3 | `lib/std/values.sls` |
| `(std variant)` | 5 | `lib/std/variant.sls` |
| `(std wasm sandbox)` | 18 | `lib/std/wasm/sandbox.sls` |
| `(std wasm wasi)` | 32 | `lib/std/wasm/wasi.sls` |
| `(std web fastcgi)` | 7 | `lib/std/web/fastcgi.sls` |
| `(std web rack)` | 7 | `lib/std/web/rack.sls` |
| `(std zipper)` | 28 | `lib/std/zipper.sls` |
| `(thunderchez cairo)` | 425 | `lib/thunderchez/cairo.sls` |
| `(thunderchez curl)` | 270 | `lib/thunderchez/curl.sls` |
| `(thunderchez ffi-utils)` | 13 | `lib/thunderchez/ffi-utils.sls` |
| `(thunderchez gl)` | 1230 | `lib/thunderchez/gl.sls` |
| `(thunderchez glu)` | 211 | `lib/thunderchez/glu.sls` |
| `(thunderchez glut)` | 169 | `lib/thunderchez/glut.sls` |
| `(thunderchez lmdb)` | 143 | `lib/thunderchez/lmdb.sls` |
| `(thunderchez nanomsg)` | 174 | `lib/thunderchez/nanomsg.sls` |
| `(thunderchez netstring)` | 3 | `lib/thunderchez/netstring.sls` |
| `(thunderchez qrencode)` | 9 | `lib/thunderchez/qrencode.sls` |
| `(thunderchez redis)` | 2 | `lib/thunderchez/redis.sls` |
| `(thunderchez sdl2 image)` | 41 | `lib/thunderchez/sdl2/image.sls` |
| `(thunderchez sdl2 mixer)` | 77 | `lib/thunderchez/sdl2/mixer.sls` |
| `(thunderchez sdl2 net)` | 51 | `lib/thunderchez/sdl2/net.sls` |
| `(thunderchez sdl2 ttf)` | 45 | `lib/thunderchez/sdl2/ttf.sls` |
| `(thunderchez sdl2)` | 587 | `lib/thunderchez/sdl2.sls` |
| `(thunderchez sql-null)` | 6 | `lib/thunderchez/sql-null.sls` |
| `(thunderchez thunder-utils)` | 17 | `lib/thunderchez/thunder-utils.sls` |
| `(thunderchez usb)` | 29 | `lib/thunderchez/usb.sls` |

