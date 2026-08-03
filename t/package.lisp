;;;; t/package.lisp
(defpackage #:cl-cmatrix/test
  (:use #:cl #:cl-cmatrix)
  ;; DESCRIBE clashes with CL:DESCRIBE, so shadow-import cl-weave's.
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave
   ;; Registration and assertions
   #:it #:expect #:signals #:run-all
   ;; Table tests and fixtures
   #:it-each #:before-each
   ;; Soft (all-failures-collected) assertions
   #:with-soft-assertions
   ;; CPS continuation helpers
   #:with-continuation-result
   ;; Mutation testing
   #:run-mutations #:assert-mutation-score
   ;; Subprocess isolation, for code that really exits the process
   #:it-isolated
   ;; Property-based testing: generated cases plus automatic shrinking on
   ;; failure, for invariants that must hold across a whole input space
   ;; rather than only the hand-picked examples the other IT cases cover.
   #:it-property #:gen-integer #:gen-member)
  (:import-from #:cl-cmatrix/cli
   #:make-cmatrix-app
   #:main
   #:image-entry-point)
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
   #:cell-style
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
