;;;; src/cli-options.lisp
;;;;
;;;; Declarative command-line metadata kept separate from the process and
;;;; terminal entry points in cli.lisp.

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
  (append (mapcar (lambda (name) (string-downcase (symbol-name name)))
                  (list-color-schemes))
          (list "rainbow")))

(defun %cmatrix-charset-choices ()
  "Every --charset choice: the downcased name of each registered glyph set
(see LIST-CHARSETS in glyphs.lisp)."
  (mapcar (lambda (name) (string-downcase (symbol-name name)))
          (list-charsets)))

(defun make-cmatrix-options ()
  "Build the validated, declarative option set for the CL-CMATRIX app."
  (list
   (make-option :name "speed" :kind :value :type :float
                :min 0.1d0 :default 1.0d0
                :description "Fall speed multiplier; larger falls faster (default 1.0).")
   (make-option :name "color" :short #\C :kind :value
                :choices (%cmatrix-color-choices)
                :default "green"
                :description
                "Trail color scheme, or \"rainbow\" for a different
scheme per column (default green).")
   (make-option :name "charset" :short #\g :kind :value
                :choices (%cmatrix-charset-choices)
                :default "ascii"
                :description
                "Falling glyph set: ascii, katakana (half-width), binary
(0/1), or lambda (default ascii).")
   (make-option :name "bold" :short #\b :kind :flag
                :description "Render selected trail glyphs bold (default off).")
   (make-option :name "all-bold" :short #\B :aliases '("B") :kind :flag
                :description "Render the whole trail bold, overriding -b.")
   (make-option :name "no-bold" :short #\n :kind :flag
                :description "Disable bold rendering, overriding bold flags.")
   (make-option :name "random-bold" :kind :flag
                :description "Vary bold cells deterministically as the trail falls.")
   (make-option :name "async" :short #\a :kind :flag
                :description "Use asynchronous per-column timing.")
   (make-option :name "old-style" :short #\o
                :aliases '("sync" "oldstyle" "force-old-style") :kind :flag
                :description "Use old-style scrolling.")

   (make-option :name "lock" :short #\L :kind :flag
                :description "Lock the animation; quit keys are ignored.")
   (make-option :name "force-linux-term" :short #\f :kind :flag
                :description "Set TERM=linux for this invocation.")
   (make-option :name "tty" :short #\t :kind :value :type :string
                :description "Use TTY for terminal input and output.")
   (make-option :name "change-glyphs" :short #\k
                :aliases '("change-characters") :kind :flag
                :description "Change every trail glyph when a column advances.")
   (make-option :name "rainbow" :short #\r :kind :flag
                :description "Use a different color scheme for each column.")
   (make-option :name "japanese" :short #\c
                :aliases '("katakana" "classic") :kind :flag
                :description "Use the half-width katakana glyph set.")
   (make-option :name "lambda" :short #\m :kind :flag
                :description "Use the lambda glyph set.")
   (make-option :name "screensaver" :short #\s
                :aliases '("S" "screen-saver") :kind :flag
                :description "Exit on the first input event.")
   (make-option :name "message" :short #\M :kind :value :type :string
                :description "Display a centered message over the animation.")
   (make-option :name "fps" :kind :value :type :integer
                :min 1 :max 240
                :description "Ticks per second (long-form extension; default follows -u).")
   (make-option :name "update-delay" :short #\u :aliases '("delay")
                :kind :value :type :integer
                :min 0 :max 10 :default +default-update-delay+
                :description
                "Upstream update delay in 10 millisecond units (default 4).")
   (make-option :name "workers" :kind :value :type :integer
                :min 1 :default +default-workers+
                :description
                "Maximum number of concurrent column workers (default 4).")
   (make-option :name "seed" :kind :value :type :integer
                :min 0
                :description
                "Random seed for a reproducible run (default: a new
random run every time).")))
