
(in-package #:asdf-user)

(defsystem "cl-cmatrix"
  :description "A Matrix-style digital rain terminal screensaver for SBCL."
  :long-description "A full-screen falling-character animation modelled on cmatrix 2.0.
Provides configurable color schemes, glyph sets, scrolling modes, resize support,
reproducible random streams, and a public state and rendering API."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "1.0.0"
  :homepage "https://github.com/nerima-lisp/cl-cmatrix"
  :bug-tracker "https://github.com/nerima-lisp/cl-cmatrix/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-cmatrix.git")
  :build-operation "program-op"
  :build-pathname "cl-cmatrix"
  :entry-point "cl-cmatrix/cli::image-entry-point"
  :depends-on ("cl-tty-kit"
               "cl-concurrent-kit"
               "cl-cli"
               "cl-host-kit")
  :pathname "src"
  :serial t
  :components
  ((:file "package")
   (:file "config")
   (:file "conditions")
   (:file "registry")
   (:file "glyphs")
   (:file "color-scheme")
   (:file "column")
   (:file "state")
   (:file "concurrent")
   (:file "render-context")
   (:file "render")
   (:file "input")
   (:file "run-state")
   (:file "runtime")
   (:file "cli-options")
   (:file "cli"))
  :in-order-to ((test-op (test-op "cl-cmatrix/test"))))

(defsystem "cl-cmatrix/test"
  :description "Test system for cl-cmatrix."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "1.0.0"
  :homepage "https://github.com/nerima-lisp/cl-cmatrix"
  :bug-tracker "https://github.com/nerima-lisp/cl-cmatrix/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-cmatrix.git")
  :depends-on ("cl-cmatrix" "cl-weave")
  :pathname "t"
  :serial t
  :components
  ((:file "package")
   (:file "registry-test")
   (:file "glyphs-test")
   (:file "color-scheme-test")
   (:file "state-test")
   (:file "advance-test")
   (:file "concurrent-test")
   (:file "resize-test")
   (:file "render-test")
   (:file "input-test")
   (:file "run-state-test")
   (:file "runtime-test")
   (:file "state-machine-test")
   (:file "cli-test")
   (:file "mutation-test")
   (:file "docs-test"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (funcall (symbol-function (find-symbol "RUN-TESTS" "CL-CMATRIX/TEST")))
               (error "cl-cmatrix test suite failed"))))
