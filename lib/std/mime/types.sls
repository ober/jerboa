#!chezscheme
;;; :std/mime/types -- MIME type database
;;;
;;; Provides a comprehensive built-in database of common MIME types
;;; with lookup by extension or by MIME type string. Supports
;;; custom type registration.

(library (std mime types)
  (export
    extension->mime-type
    mime-type->extensions
    mime-type?
    mime-type-category
    common-mime-types
    register-mime-type!)

  (import (chezscheme))

  ;; Internal mutable database: extension -> mime-type
  ;; and mime-type -> list of extensions
  (define *ext->type* (make-hashtable string-hash string=?))
  (define *type->exts* (make-hashtable string-hash string=?))

  ;; Register a single mapping
  (define (register-one! ext type)
    (hashtable-set! *ext->type* ext type)
    (let ((existing (hashtable-ref *type->exts* type '())))
      (unless (member ext existing)
        (hashtable-set! *type->exts* type (cons ext existing)))))

  ;; Initialize the built-in database
  (define (init-database!)
    (for-each
      (lambda (entry)
        (let ((type (car entry))
              (exts (cdr entry)))
          (for-each (lambda (ext) (register-one! ext type)) exts)))
      *built-in-types*))

  ;; Built-in type database: (mime-type ext ...)
  (define *built-in-types*
    '(;; Text types
      ("text/plain"                          ".txt" ".text" ".log")
      ("text/html"                           ".html" ".htm")
      ("text/css"                            ".css")
      ("text/javascript"                     ".js" ".mjs")
      ("text/xml"                            ".xml")
      ("text/csv"                            ".csv")
      ("text/markdown"                       ".md" ".markdown")
      ("text/rtf"                            ".rtf")
      ("text/tab-separated-values"           ".tsv")
      ("text/calendar"                       ".ics")
      ("text/vcard"                          ".vcf" ".vcard")
      ("text/x-python"                       ".py")
      ("text/x-java-source"                  ".java")
      ("text/x-c"                            ".c" ".h")
      ("text/x-c++"                          ".cpp" ".cxx" ".cc" ".hpp")
      ("text/x-shellscript"                  ".sh" ".bash")
      ("text/x-yaml"                         ".yaml" ".yml")
      ("text/x-toml"                         ".toml")
      ("text/x-ini"                          ".ini" ".cfg")

      ;; Image types
      ("image/png"                           ".png")
      ("image/jpeg"                          ".jpg" ".jpeg" ".jpe")
      ("image/gif"                           ".gif")
      ("image/svg+xml"                       ".svg" ".svgz")
      ("image/webp"                          ".webp")
      ("image/x-icon"                        ".ico")
      ("image/bmp"                           ".bmp")
      ("image/tiff"                          ".tiff" ".tif")
      ("image/avif"                          ".avif")
      ("image/apng"                          ".apng")
      ("image/heic"                          ".heic" ".heif")
      ("image/jxl"                           ".jxl")

      ;; Audio types
      ("audio/mpeg"                          ".mp3")
      ("audio/wav"                           ".wav")
      ("audio/ogg"                           ".ogg" ".oga")
      ("audio/flac"                          ".flac")
      ("audio/aac"                           ".aac")
      ("audio/mp4"                           ".m4a")
      ("audio/webm"                          ".weba")
      ("audio/midi"                          ".midi" ".mid")
      ("audio/x-aiff"                        ".aiff" ".aif")
      ("audio/opus"                          ".opus")

      ;; Video types
      ("video/mp4"                           ".mp4" ".m4v")
      ("video/webm"                          ".webm")
      ("video/x-msvideo"                     ".avi")
      ("video/x-matroska"                    ".mkv")
      ("video/quicktime"                     ".mov")
      ("video/x-flv"                         ".flv")
      ("video/mpeg"                          ".mpeg" ".mpg")
      ("video/ogg"                           ".ogv")
      ("video/x-ms-wmv"                      ".wmv")
      ("video/3gpp"                          ".3gp")

      ;; Application types
      ("application/pdf"                     ".pdf")
      ("application/zip"                     ".zip")
      ("application/gzip"                    ".gz" ".gzip")
      ("application/x-tar"                   ".tar")
      ("application/x-7z-compressed"         ".7z")
      ("application/x-bzip2"                 ".bz2")
      ("application/x-xz"                    ".xz")
      ("application/x-zstd"                  ".zst")
      ("application/wasm"                    ".wasm")
      ("application/octet-stream"            ".bin" ".exe" ".dll" ".so")
      ("application/json"                    ".json")
      ("application/ld+json"                 ".jsonld")
      ("application/xml"                     ".xsl" ".xslt")
      ("application/javascript"              ".cjs")
      ("application/typescript"              ".ts" ".tsx")
      ("application/x-httpd-php"             ".php")
      ("application/x-ruby"                  ".rb")
      ("application/x-perl"                  ".pl" ".pm")
      ("application/sql"                     ".sql")
      ("application/graphql"                 ".graphql")
      ("application/msword"                  ".doc")
      ("application/vnd.openxmlformats-officedocument.wordprocessingml.document" ".docx")
      ("application/vnd.ms-excel"            ".xls")
      ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ".xlsx")
      ("application/vnd.ms-powerpoint"       ".ppt")
      ("application/vnd.openxmlformats-officedocument.presentationml.presentation" ".pptx")
      ("application/rtf"                     ".rtf")
      ("application/epub+zip"                ".epub")
      ("application/x-shockwave-flash"       ".swf")
      ("application/java-archive"            ".jar")
      ("application/x-rar-compressed"        ".rar")
      ("application/vnd.apple.installer+xml" ".mpkg")
      ("application/x-apple-diskimage"       ".dmg")
      ("application/x-deb"                   ".deb")
      ("application/x-rpm"                   ".rpm")
      ("application/x-iso9660-image"         ".iso")
      ("application/atom+xml"                ".atom")
      ("application/rss+xml"                 ".rss")
      ("application/x-latex"                 ".latex" ".tex")
      ("application/postscript"              ".ps" ".eps")
      ("application/x-sqlite3"              ".sqlite" ".db")
      ("application/protobuf"                ".proto")
      ("application/msgpack"                 ".msgpack")

      ;; Font types
      ("font/woff"                           ".woff")
      ("font/woff2"                          ".woff2")
      ("font/ttf"                            ".ttf")
      ("font/otf"                            ".otf")
      ("font/eot"                            ".eot")

      ;; Multipart
      ("multipart/form-data"                 )
      ("multipart/mixed"                     )))

  ;; Normalize extension: ensure leading dot, lowercase
  (define (normalize-ext ext)
    (let ((s (string-downcase ext)))
      (if (and (> (string-length s) 0)
               (char=? (string-ref s 0) #\.))
          s
          (string-append "." s))))

  ;; Look up MIME type by file extension.
  ;; ext can be ".html" or "html".
  ;; Returns MIME type string or #f.
  (define (extension->mime-type ext)
    (hashtable-ref *ext->type* (normalize-ext ext) #f))

  ;; Look up extensions for a MIME type.
  ;; Returns list of extension strings (with leading dot) or empty list.
  (define (mime-type->extensions type)
    (hashtable-ref *type->exts* type '()))

  ;; Check if a string looks like a valid MIME type (category/subtype).
  (define (mime-type? str)
    (and (string? str)
         (let ((slash-pos (string-index str #\/)))
           (and slash-pos
                (> slash-pos 0)
                (< slash-pos (- (string-length str) 1))))))

  ;; Helper: find index of char in string
  (define (string-index str ch)
    (let ((len (string-length str)))
      (let lp ((i 0))
        (cond
          ((>= i len) #f)
          ((char=? (string-ref str i) ch) i)
          (else (lp (+ i 1)))))))

  ;; Extract the category (top-level type) from a MIME type string.
  ;; e.g. "text/html" -> "text"
  (define (mime-type-category type)
    (let ((pos (string-index type #\/)))
      (if pos
          (substring type 0 pos)
          #f)))

  ;; Return the full built-in database as an alist: ((ext . type) ...)
  (define (common-mime-types)
    (let-values (((keys vals) (hashtable-entries *ext->type*)))
      (let ((kv (vector->list keys))
            (vv (vector->list vals)))
        (map cons kv vv))))

  ;; Register a custom MIME type mapping.
  ;; ext should be like ".foo" or "foo".
  (define (register-mime-type! ext type)
    (unless (string? ext)
      (error 'register-mime-type! "extension must be a string" ext))
    (unless (and (string? type) (mime-type? type))
      (error 'register-mime-type! "type must be a valid MIME type string" type))
    (register-one! (normalize-ext ext) type))

  ;; Initialize on load
  (init-database!)

  ) ;; end library
