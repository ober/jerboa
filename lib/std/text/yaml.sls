#!chezscheme
;;; :std/text/yaml -- YAML parsing and emitting (wraps chez-yaml)
;;; Pure Scheme, no external dependencies.

(library (std text yaml)
  (export
    yaml-load yaml-load-string
    yaml-dump yaml-dump-string
    yaml-key-format
    safe-yaml-load-string
    *yaml-max-input-size*)

  (import (chezscheme) (yaml))

  (define *yaml-max-input-size* (make-parameter (* 10 1024 1024)))  ;; 10MB

  (define (safe-yaml-load-string str)
    (when (> (string-length str) (*yaml-max-input-size*))
      (error 'safe-yaml-load-string "YAML input exceeds maximum size"
             (string-length str) (*yaml-max-input-size*)))
    (yaml-load-string str))

  ) ;; end library
