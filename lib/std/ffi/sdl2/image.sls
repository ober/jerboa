#!chezscheme
;;; (std ffi sdl2 image) -- Re-export of (thunderchez sdl2 image) bindings
(library (std ffi sdl2 image)
  (export
    img-init
    img-linked-version
    img-quit
    img-load-typed-rw
    img-load
    img-load-rw
    img-load-texture
    img-load-texture-rw
    img-load-texture-typed-rw
    img-is-ico
    img-is-cur
    img-is-bmp
    img-is-gif
    img-is-jpg
    img-is-lbm
    img-is-pcx
    img-is-png
    img-is-tif
    img-is-xcf
    img-is-xpm
    img-is-xv
    img-is-webp
    img-load-ico-rw
    img-load-cur-rw
    img-load-bmp-rw
    img-load-gif-rw
    img-load-jpg-rw
    img-load-lbm-rw
    img-load-pcx-rw
    img-load-png-rw
    img-load-pnm-rw
    img-load-tga-rw
    img-load-tif-rw
    img-load-xcf-rw
    img-load-xpm-rw
    img-load-xv-rw
    img-load-webp-rw
    img-read-xpm-from-array
    img-save-png
    img-save-png-rw
    sdl-image-library-init)
  (import (thunderchez sdl2 image))
) ;; end library
