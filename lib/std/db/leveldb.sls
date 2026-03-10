#!chezscheme
;;; :std/db/leveldb -- Key-value store (wraps chez-leveldb)
;;; Requires: leveldb_shim.so, libleveldb.so

(library (std db leveldb)
  (export
    ;; Core operations
    leveldb-open leveldb-close
    leveldb-put leveldb-get leveldb-delete leveldb-key?
    leveldb-write
    ;; Write batches
    leveldb-writebatch
    leveldb-writebatch-put leveldb-writebatch-delete
    leveldb-writebatch-clear leveldb-writebatch-append
    leveldb-writebatch-destroy
    ;; Iterators
    leveldb-iterator leveldb-iterator-close
    leveldb-iterator-valid? leveldb-iterator-seek-first
    leveldb-iterator-seek-last leveldb-iterator-seek
    leveldb-iterator-next leveldb-iterator-prev
    leveldb-iterator-key leveldb-iterator-value
    leveldb-iterator-error
    ;; Convenience iteration
    leveldb-fold leveldb-for-each
    leveldb-fold-keys leveldb-for-each-keys
    ;; Snapshots
    leveldb-snapshot leveldb-snapshot-release
    ;; Options
    leveldb-options leveldb-default-options
    leveldb-read-options leveldb-default-read-options
    leveldb-write-options leveldb-default-write-options
    ;; Database management
    leveldb-compact-range leveldb-destroy-db leveldb-repair-db
    leveldb-property leveldb-approximate-size
    ;; Misc
    leveldb-version leveldb? leveldb-error?)

  (import (leveldb))

  ) ;; end library
