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
terminal column, each with a bright head and a color-graded 256-color dimming trail. Eleven color
schemes plus rainbow (a different scheme per column), three glyph sets (ASCII, half-width
katakana, binary), and an optional bold trail. Reflows on terminal resize (polled, not a SIGWINCH
handler) and quits cleanly on q/Escape/Ctrl-C, always restoring the terminal's prior state. Fall
speed, glyph choice, and reset timing all route through an injectable random state, so a run
started from a fixed seed (or --seed on the command line) is exactly reproducible."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  ;; Single source of truth for the version. flake.nix reads this form, and
  ;; release.yml refuses to publish a tag that disagrees with it.
  :version "0.2.0"
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
  ;;
  ;; cl-host-kit supplies QUIT, GETCWD and TRUENAMIZE. This system does have
  ;; a "filesystem paths" problem after all: IMAGE-ENTRY-POINT (src/cli.lisp)
  ;; must reorient a dumped image's *DEFAULT-PATHNAME-DEFAULTS* to the
  ;; machine it is actually running on, and calling ASDF's own bundled UIOP
  ;; directly for that -- or for the process exit MAIN needs -- would be
  ;; exactly the unacknowledged, unaudited dependency this org's standards
  ;; warn against: present in every image because ASDF happens to need it,
  ;; used without ever being declared. cl-host-kit is the named, versioned,
  ;; :DEPENDS-ON'd package for host-system interaction the rest of this
  ;; system's dependencies already model, so it replaces UIOP rather than
  ;; sitting alongside it.
  ;;
  ;; Every other nerima-lisp org package was surveyed against this system and
  ;; deliberately left out, not overlooked: cl-dataflow's "state machine"
  ;; pulls in cl-prolog and cl-concurrent-kit as hard runtime dependencies to
  ;; execute a graph, which is strictly more machinery than MATRIX-STATE's
  ;; two pure DEFSTRUCT-transition functions need. cl-boundary-kit targets
  ;; multi-effect application boundaries (filesystem, network, clock, ...);
  ;; this system already has exactly two DOMAIN effects, and both are already
  ;; injected directly (RANDOM-STATE, TERMINAL-SIZE-FN) with no framework
  ;; around them -- cl-host-kit's own host-system calls are process
  ;; bootstrap, not part of that injectable surface. cl-log-kit would add
  ;; three more transitive dependencies (cl-date-kit, cl-concurrent-kit,
  ;; cl-host-kit) for a diagnostic feature nothing here asks for. The rest
  ;; (cl-json-kit, cl-regex-kit, cl-parser-kit, cl-codec-kit, cl-date-kit,
  ;; cl-concurrent-kit, cl-history-kit, cl-process-kit) solve problems --
  ;; JSON, regex, parsing, encoding, calendars, threading, shell history,
  ;; subprocesses -- this system does not have. Adding any of them would be
  ;; exactly the "変にAdapter" this org's standards warn against: a
  ;; dependency justified by its existence rather than by a need.
  ;;
  ;; Re-checked against `gh api orgs/nerima-lisp/repos` directly (not just
  ;; this comment's own history) on 2026-08-03: the only org repos not
  ;; already named above or below are the cl-cc-* compiler-construction
  ;; family (cl-cc, cl-cc-ast, cl-cc-binary, cl-cc-bootstrap, cl-cc-bytecode,
  ;; cl-cc-codegen-native, cl-cc-cps, cl-cc-expand, cl-cc-ir,
  ;; cl-cc-javascript, cl-cc-mir, cl-cc-optimize, cl-cc-parse, cl-cc-php,
  ;; cl-cc-prolog-tools, cl-cc-runtime, cl-cc-target, cl-cc-type, cl-cc-vm --
  ;; none of which this terminal animation compiles or interprets anything
  ;; to need -- and four sibling terminal APPLICATIONS, not libraries:
  ;; cl-nyancat and cl-sl (other cmatrix-shaped terminal animations, peers of
  ;; this system rather than dependencies of it), loom (a text editor), and
  ;; nshell (an interactive shell). cl-tmux is a terminal multiplexer, also
  ;; an application. None are import candidates for a library.
  :depends-on ("cl-tty-kit"  ; terminal session, renderer, 256-color styling, tick loop
               "cl-cli"      ; declarative CLI parsing, --help/--version
               "cl-host-kit") ; QUIT, GETCWD, TRUENAMIZE -- host-system interaction, not UIOP
  :pathname "src"
  :serial t
  :components
  ;; src/ is flat and every defpackage lives in src/package.lisp.
  ((:file "package")
   (:file "conditions")
   (:file "registry")
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
  :version "0.2.0"
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
   (:file "registry-test")
   (:file "glyphs-test")
   (:file "color-scheme-test")
   (:file "state-test")
   (:file "advance-test")
   (:file "resize-test")
   (:file "render-test")
   (:file "loop-test")
   (:file "cli-test")
   (:file "mutation-test"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (funcall (symbol-function (find-symbol "RUN-TESTS" "CL-CMATRIX/TEST")))
               (error "cl-cmatrix test suite failed"))))
