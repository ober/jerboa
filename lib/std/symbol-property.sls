#!chezscheme
;;; (std symbol-property) — Symbol property lists
;;;
;;; Re-exports Chez's per-symbol key-value property system.
;;; Unique to Chez: attach metadata to symbols without external tables.

(library (std symbol-property)
  (export putprop getprop remprop property-list)

  (import (chezscheme))

  ;; All exports are Chez built-ins:
  ;;   (putprop 'sym 'key value) — attach property
  ;;   (getprop 'sym 'key) — retrieve property (or #f)
  ;;   (remprop 'sym 'key) — remove property
  ;;   (property-list 'sym) — get all properties as plist

) ;; end library
