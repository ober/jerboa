#!chezscheme
;;; :std/markup/xml -- alias for (std text xml)

(library (std markup xml)
  (export
    write-xml print-sxml->xml
    sxml-e sxml-attributes sxml-attribute-e sxml-children)

  (import (std text xml))

  ) ;; end library
