#!/usr/bin/env -S scheme --libdirs lib --script
;;; jerboa-lsp.ss -- LSP server entry point
;;;
;;; Launch: bin/jerboa run tools/jerboa-lsp.ss
;;; Or:     scheme --libdirs lib --script tools/jerboa-lsp.ss

(import (std lsp server) (std lsp symbols))

(symbol-db-init!)
(start-lsp-server)
