#!chezscheme
;;; (std ffi usb) -- Re-export of (thunderchez usb) bindings
(library (std ffi usb)
  (export
    c-usb-device-descriptor
    c-usb-device
    usb-device
    usb-device-handle
    usb-device?
    usb-init
    usb-exit
    usb-get-device-list
    usb-get-device-descriptor
    usb-get-port-number
    usb-get-port-numbers
    usb-get-bus-number
    usb-get-device
    usb-find-vid-pid
    usb-display-device-list
    usb-strerror
    usb-open
    usb-close
    usb-claim-interface
    usb-release-interface
    usb-log-level-enum
    usb-log-level-index
    usb-log-level-ref
    usb-set-debug
    usb-control-transfer
    usb-bulk-read
    usb-bulk-write
    usb-interrupt-write
    usb-interrupt-read)
  (import (thunderchez usb))
) ;; end library
