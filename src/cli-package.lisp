;;;; src/cli-package.lisp
;;;;
;;;; Package definition for the optional cl-cmatrix/cli ASDF system.
(defpackage #:cl-cmatrix/cli (:documentation "The `cl-cmatrix` command-line front end over CL-CMATRIX.")
  (:use #:cl)
  (:import-from
    #:cl-cmatrix
    #:run-matrix
    #:list-color-schemes
    #:list-charsets
    #:charset-glyphs
    #:+default-fps+)
  (:import-from
    #:cl-cli
    #:make-app
    #:make-option
    #:run-app
    #:option-value
    #:current-process-argv)
  (:import-from #:host-kit #:quit #:getcwd)
  (:export #:make-cmatrix-app #:main #:image-entry-point))
