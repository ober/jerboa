#!chezscheme
;;; :std/os/inotify -- Linux filesystem event monitoring (wraps chez-inotify)
;;; Requires: chez_inotify_shim.so

(library (std os inotify)
  (export
    inotify-init inotify-close
    inotify-add-watch inotify-rm-watch
    inotify-read-events inotify-poll
    make-inotify-event inotify-event?
    inotify-event-wd inotify-event-mask
    inotify-event-cookie inotify-event-name
    IN_ACCESS IN_ATTRIB IN_CLOSE_WRITE IN_CLOSE_NOWRITE
    IN_CREATE IN_DELETE IN_DELETE_SELF IN_MODIFY
    IN_MOVE_SELF IN_MOVED_FROM IN_MOVED_TO IN_OPEN
    IN_ALL_EVENTS IN_MOVE IN_CLOSE
    IN_DONT_FOLLOW IN_EXCL_UNLINK IN_MASK_ADD IN_ONESHOT IN_ONLYDIR
    IN_IGNORED IN_ISDIR IN_Q_OVERFLOW IN_UNMOUNT)

  (import (chez-inotify))

  ) ;; end library
