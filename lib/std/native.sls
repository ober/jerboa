#!chezscheme
;;; (std native) — Load the unified Rust native library (libjerboa_native.so)

(library (std native)
  (export jerboa-native-available? jerboa-native-load!)

  (import (chezscheme))

  ;; Try multiple paths to find the library
  (define _loaded
    (or (guard (e [#t #f])
          (load-shared-object "libjerboa_native.so")
          #t)
        (guard (e [#t #f])
          (load-shared-object "./lib/libjerboa_native.so")
          #t)
        (guard (e [#t #f])
          (load-shared-object "lib/libjerboa_native.so")
          #t)
        #f))

  (define (jerboa-native-available?) _loaded)

  ;; Call this in a define form in consuming libraries to ensure
  ;; the .so is loaded before foreign-procedure declarations.
  (define (jerboa-native-load!)
    (unless _loaded
      (error 'jerboa-native-load! "libjerboa_native.so not available"))
    #t)

  ) ;; end library
