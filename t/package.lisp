;;;; t/package.lisp
(defpackage #:cl-cmatrix/test
  (:use #:cl #:cl-cmatrix)
  ;; DESCRIBE clashes with CL:DESCRIBE, so shadow-import cl-weave's.
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave
   ;; Registration and assertions
   #:it #:expect #:signals #:run-all
   ;; Soft (all-failures-collected) assertions
   #:with-soft-assertions)
  (:import-from #:cl-cmatrix/cli
   #:make-cmatrix-app)
  (:import-from #:cl-cli
   #:parse-argv
   #:run-app
   #:option-value
   #:cli-invalid-option-value)
  (:import-from #:cl-tty-kit
   #:rgb-to-256
   #:blend-colors
   #:color-luminance
   #:make-screen
   #:screen-cell
   #:cell-char
   #:make-renderer
   #:renderer-width
   #:renderer-height)
  (:export #:run-tests))

(in-package #:cl-cmatrix/test)

(defun run-tests ()
  "Run every registered spec, signalling on any failure so ASDF's TEST-OP
fails."
  (unless (run-all :reporter :spec :timeout-ms 20000)
    (error "cl-cmatrix test suite failed"))
  (format t "~&cl-cmatrix/test: successful completion with 0 failures~%")
  t)
