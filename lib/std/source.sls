#!chezscheme
;;; (std source) — Source location tracking macros
;;;
;;; Compile-time macros that expand to source file/line/column info.
;;; Uses Chez Scheme's source annotation system.

(library (std source)
  (export this-source-file this-source-directory this-source-location)

  (import (chezscheme))

  ;; Expand to the file path of the source where this macro appears
  (define-syntax this-source-file
    (lambda (stx)
      (syntax-case stx ()
        [(k)
         (let ([src (syntax->annotation #'k)])
           (if src
               (let ([sfd (source-object-sfd (annotation-source src))])
                 (datum->syntax #'k (source-file-descriptor-path sfd)))
               (datum->syntax #'k "<unknown>")))])))

  ;; Expand to the directory containing the source file
  (define-syntax this-source-directory
    (lambda (stx)
      (syntax-case stx ()
        [(k)
         (let ([src (syntax->annotation #'k)])
           (if src
               (let* ([sfd (source-object-sfd (annotation-source src))]
                      [path (source-file-descriptor-path sfd)]
                      [dir (path-parent path)])
                 (datum->syntax #'k dir))
               (datum->syntax #'k ".")))])))

  ;; Expand to (list file bfp 0) — bfp is byte file position
  (define-syntax this-source-location
    (lambda (stx)
      (syntax-case stx ()
        [(k)
         (let ([src (syntax->annotation #'k)])
           (if src
               (let* ([so (annotation-source src)]
                      [sfd (source-object-sfd so)]
                      [path (source-file-descriptor-path sfd)]
                      [bfp (source-object-bfp so)])
                 #`(list #,(datum->syntax #'k path)
                         #,(datum->syntax #'k bfp)
                         0))
               #'(list "<unknown>" 0 0)))])))

) ;; end library
