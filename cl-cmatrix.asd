;;;; cl-cmatrix.asd

;;; This form comes FIRST, before any defsystem. ASDF binds *package* to
;;; ASDF-USER only for a file it loads itself; read any other way -- a REPL
;;; `load`, an editor evaluating the buffer, flake.nix parsing :version -- the
;;; file is read in whatever package happens to be current. Saying it makes
;;; the file self-contained. Package definitions belong in src/package.lisp,
;;; not here.
(in-package #:asdf-user)

(defsystem "cl-cmatrix"
  ;; All eight metadata fields are mandatory. :homepage, :bug-tracker and
  ;; :source-control are what let a consumer find the project from a
  ;; Quicklisp or ASDF listing alone.
  :description "A Matrix-style digital rain terminal screensaver for SBCL."
  :long-description "Full-screen falling-character animation: one independently falling stream per
terminal column, each with a bright head and a color-graded 256-color dimming trail. Reflows on
terminal resize (polled, not a SIGWINCH handler) and quits cleanly on q/Escape/Ctrl-C, always
restoring the terminal's prior state. Fall speed, glyph choice, and reset timing all route through
an injectable random state, so a run started from a fixed seed is exactly reproducible."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  ;; Single source of truth for the version. flake.nix reads this form, and
  ;; release.yml refuses to publish a tag that disagrees with it.
  :version "0.1.0"
  :homepage "https://github.com/nerima-lisp/cl-cmatrix"
  :bug-tracker "https://github.com/nerima-lisp/cl-cmatrix/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-cmatrix.git")
  ;; How the `cl-cmatrix` executable is delivered belongs here, not in a
  ;; build system: `(asdf:operate 'asdf:program-op "cl-cmatrix")` and `nix
  ;; build` must produce the same binary. See cl-weave.asd and
  ;; cl-cowsay.asd for the pattern this follows.
  :build-operation "program-op"
  :build-pathname "cl-cmatrix"
  :entry-point "cl-cmatrix/cli::image-entry-point"
  ;; cl-tty-kit supplies raw mode, the alternate screen, 256-color styling,
  ;; the double-buffered renderer, and the real-time tick loop; cl-cli
  ;; supplies the argument parser and --help/--version scaffolding. Both are
  ;; dependency-free L1 utilities within this org.
  :depends-on ("cl-tty-kit" ; terminal session, renderer, 256-color styling, tick loop
               "cl-cli")    ; declarative CLI parsing, --help/--version
  :pathname "src"
  :serial t
  :components
  ;; src/ is flat and every defpackage lives in src/package.lisp.
  ((:file "package")
   (:file "conditions")
   (:file "glyphs")
   (:file "color-scheme")
   (:file "column")
   (:file "state")
   (:file "render")
   (:file "loop")
   (:file "cli"))
  ;; Mandatory. Without it `asdf:test-system "cl-cmatrix"` succeeds while
  ;; running zero tests.
  :in-order-to ((test-op (test-op "cl-cmatrix/test"))))

;;; The test system is `cl-cmatrix/test` (singular, slash-separated) with
;;; :pathname "t". It is NOT `cl-cmatrix-test` and NOT `cl-cmatrix/tests`.
(defsystem "cl-cmatrix/test"
  :description "Test system for cl-cmatrix."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :homepage "https://github.com/nerima-lisp/cl-cmatrix"
  :bug-tracker "https://github.com/nerima-lisp/cl-cmatrix/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-cmatrix.git")
  ;; cl-weave is the org's test framework everywhere. Do not introduce
  ;; FiveAM, parachute, rove or prove.
  :depends-on ("cl-cmatrix" "cl-weave")
  :pathname "t"
  :serial t
  :components
  ((:file "package")
   (:file "glyphs-test")
   (:file "color-scheme-test")
   (:file "state-test")
   (:file "advance-test")
   (:file "resize-test")
   (:file "render-test")
   (:file "loop-test")
   (:file "cli-test"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (funcall (symbol-function (find-symbol "RUN-TESTS" "CL-CMATRIX/TEST")))
               (error "cl-cmatrix test suite failed"))))
