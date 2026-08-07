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
   (make-option :name "speed" :short #\s :kind :value :type :float
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
   (make-option :name "workers" :kind :value :type :integer
                :min 1 :default +default-workers+
                :description
                "Maximum number of concurrent column workers (default 4).")
   (make-option :name "seed" :kind :value :type :integer
                :min 0
                :description
                "Random seed for a reproducible run (default: a new
random run every time).")))
