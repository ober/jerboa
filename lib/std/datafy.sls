#!chezscheme
;;; (std datafy) — Clojure's datafy/nav protocols
;;;
;;; Provides programmable data navigation:
;;;   (datafy x)       — turn any value into navigable data
;;;   (nav coll k v)   — navigate into a datum
;;;
;;; Default implementations return the value unchanged (datafy)
;;; or the value at the key (nav). Types opt in by extending
;;; the protocols:
;;;
;;;   (extend-type my-type::t Datafiable
;;;     (datafy (x) (my-type->hash x)))
;;;
;;;   (extend-type my-type::t Navigable
;;;     (nav (coll k v) (load-detail coll k)))
;;;
;;; This powers rich REPL inspection: any value can describe itself
;;; as a map/list of navigable entries, and tooling can drill into
;;; any entry to get more detail.

(library (std datafy)
  (export
    Datafiable Navigable
    datafy nav)

  (import (chezscheme)
          (std protocol))

  ;; The Datafiable protocol: one method, `datafy`.
  ;; Default: return the value as-is (identity). Lists, vectors,
  ;; hash tables, etc. are already data — no conversion needed.
  (defprotocol Datafiable
    (datafy (x)))

  ;; The Navigable protocol: one method, `nav`.
  ;; Given a collection, a key, and the value at that key,
  ;; return a "deeper" view. Default: return v unchanged.
  (defprotocol Navigable
    (nav (coll k v)))

  ;; Default implementations for common types — identity behavior.
  ;; Users extend these for their own types to provide rich navigation.

  ;; Pairs (lists) — already data
  (extend-type 'pair Datafiable
    (datafy (x) x))
  (extend-type 'pair Navigable
    (nav (coll k v) v))

  ;; Null — already data
  (extend-type 'null Datafiable
    (datafy (x) x))
  (extend-type 'null Navigable
    (nav (coll k v) v))

  ;; Vectors — already data
  (extend-type 'vector Datafiable
    (datafy (x) x))
  (extend-type 'vector Navigable
    (nav (coll k v) v))

  ;; Hash tables — already data
  (extend-type 'hashtable Datafiable
    (datafy (x) x))
  (extend-type 'hashtable Navigable
    (nav (coll k v) v))

  ;; Strings — already data
  (extend-type 'string Datafiable
    (datafy (x) x))

  ;; Numbers — already data
  (extend-type 'number Datafiable
    (datafy (x) x))

  ;; Symbols — already data
  (extend-type 'symbol Datafiable
    (datafy (x) x))

  ;; Booleans — already data
  (extend-type 'boolean Datafiable
    (datafy (x) x))

  ;; Universal fallback for anything not yet extended
  (extend-type 'any Datafiable
    (datafy (x) x))
  (extend-type 'any Navigable
    (nav (coll k v) v))

) ;; end library
