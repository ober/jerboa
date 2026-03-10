#!chezscheme
;;; :std/text/yaml -- YAML parsing and emitting (wraps chez-yaml)
;;; Pure Scheme, no external dependencies.

(library (std text yaml)
  (export
    yaml-load yaml-load-string
    yaml-dump yaml-dump-string
    yaml-key-format)

  (import (yaml))

  ) ;; end library
