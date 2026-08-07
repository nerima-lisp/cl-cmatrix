;;;; src/cli.lisp
;;;;
;;;; The `cl-cmatrix` command line: a single root command (no subcommands)
;;;; exposing --speed, --color, --charset, --bold, --fps, and --seed over
;;;; RUN-MATRIX, with --help/--version scaffolding free from cl-cli. Unlike
;;;; cl-cowsay this is a persistent, full-screen, raw-mode loop rather than a
;;;; one-shot print, so the handler has no output to print itself:
;;;; RUN-MATRIX writes directly to the terminal and returns only once the
;;;; user quits.

(in-package #:cl-cmatrix/cli)

(defun %cmatrix-version ()
  "The running CL-CMATRIX system's :VERSION, the single source of truth also
read by flake.nix and enforced by release.yml against the git tag."
  (let ((system (asdf:find-system "cl-cmatrix" nil)))
    (if system (asdf:component-version system) "0.0.0")))

(defun %cmatrix-color-choices ()
  "Every --color choice: each registered scheme name plus \"rainbow\", the
one --color value RUN-MATRIX accepts that names no single scheme (see
COLOR-CHOICE-P in color-scheme.lisp)."
  (append (mapcar (lambda (name) (string-downcase (symbol-name name))) (list-color-schemes))
          (list "rainbow")))

(defun %cmatrix-charset-choices ()
  "Every --charset choice: the downcased name of each registered glyph set
(see LIST-CHARSETS in glyphs.lisp)."
  (mapcar (lambda (name) (string-downcase (symbol-name name))) (list-charsets)))

(defun %cmatrix-random-state (seed)
  "Return a fresh random state for RUN-MATRIX's :RANDOM-STATE: seeded from
SEED (an integer, for a reproducible run identical across invocations) when
supplied, else a nondeterministic one -- the same default RUN-MATRIX itself
uses."
  (if seed (sb-ext:seed-random-state seed) (make-random-state t)))

(defun %option-keyword (invocation option-name)
  "Return the value cl-cli parsed for OPTION-NAME out of INVOCATION -- a
string, by every :CHOICES-constrained option's own contract -- upcased and
interned into the keyword package. Both --color and --charset resolve their
raw string through this same conversion before handing it to RUN-MATRIX.
Interning a value derived from process input is a real footgun in general
(unbounded strings can grow the keyword package without limit); it is safe
here specifically because OPTION-VALUE can only ever return one of the fixed
strings MAKE-OPTION's own :CHOICES already validated invocation against --
cl-cli rejects any other value before %CMATRIX-HANDLER runs at all, and this
function is never called with any other OPTION-NAME."
  (intern (string-upcase (option-value invocation option-name)) :keyword))

(defun %cmatrix-run-matrix-args (invocation)
  "Return the full RUN-MATRIX keyword-argument plist INVOCATION resolves to:
every cl-cli option read back through OPTION-VALUE, with --color/--charset
interned via %OPTION-KEYWORD, --charset further resolved to its glyph vector,
and --seed threaded through %CMATRIX-RANDOM-STATE. Pure given INVOCATION,
like %TERMINAL-DIMENSIONS and %MAKE-INITIAL-RUN-STATE in run-state.lisp -- the
only impure step left in %CMATRIX-HANDLER is applying RUN-MATRIX to this
plist, which is what actually takes over the terminal."
  (list :speed (option-value invocation :speed)
        :color (%option-keyword invocation :color)
        :glyphs (charset-glyphs (%option-keyword invocation :charset))
        :bold (option-value invocation :bold)
        :fps (option-value invocation :fps)
        :random-state (%cmatrix-random-state (option-value invocation :seed))))

(defun %cmatrix-handler (invocation)
  (apply #'run-matrix (%cmatrix-run-matrix-args invocation))
  0)

(defun make-cmatrix-app ()
  "Build a fresh CL-CLI app spec for `cl-cmatrix`. A function rather than a
constant so tests can build an independent instance per run."
  (make-app
   :name "cl-cmatrix"
   :version (%cmatrix-version)
   :summary "A Matrix-style digital rain terminal screensaver."
   :description
   "Full-screen falling-character animation: one independently falling
stream per terminal column, each with a bright head and a color-graded
dimming trail. Reflows automatically on terminal resize. Press q, Escape, or
Ctrl-C to quit."
   :global-options
   (list (make-option :name "speed" :short #\s :kind :value :type :float
                       :min 0.1d0 :default 1.0d0
                       :description "Fall speed multiplier; larger falls faster (default 1.0).")
         (make-option :name "color" :short #\c :kind :value
                       :choices (%cmatrix-color-choices)
                       :default "green"
                       :description
                       "Trail color scheme, or \"rainbow\" for a different
scheme per column (default green).")
         (make-option :name "charset" :short #\g :kind :value
                       :choices (%cmatrix-charset-choices)
                       :default "ascii"
                       :description
                       "Falling glyph set: ascii, katakana (half-width), or
binary (0/1) (default ascii).")
         (make-option :name "bold" :short #\b :kind :flag
                      :description "Render the whole trail bold, not only the head (default off).")
         (make-option :name "fps" :short #\u :kind :value :type :integer
                      :min 1 :max 240 :default +default-fps+
                      :description "Ticks per second (default 30).")
         (make-option :name "seed" :kind :value :type :integer
                      :min 0
                      :description
                      "Random seed for a reproducible run (default: a new
random run every time)."))
   :handler #'%cmatrix-handler))

(defun main (&optional (argv (current-process-argv)))
  "Parse ARGV against MAKE-CMATRIX-APP and exit the process with the
resulting code. The default ARGV is the live process argv, so this is safe
to call directly from a toplevel form."
  (quit (run-app (make-cmatrix-app) :argv argv)))

(defun image-entry-point ()
  "Toplevel of the delivered `cl-cmatrix` executable, named by :ENTRY-POINT
in cl-cmatrix.asd. A dumped image comes back with the state it was dumped
with, which for a packaged build is a build sandbox that no longer exists;
this puts the process back in touch with the machine it is actually running
on before the CLI sees an argument."
  (setf *default-pathname-defaults* (getcwd))
  (main))
