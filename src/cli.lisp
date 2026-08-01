;;;; src/cli.lisp
;;;;
;;;; The `cl-cmatrix` command line: a single root command (no subcommands)
;;;; exposing --speed and --color over RUN-MATRIX, with --help/--version
;;;; scaffolding free from cl-cli. Unlike cl-cowsay this is a persistent,
;;;; full-screen, raw-mode loop rather than a one-shot print, so the handler
;;;; has no output to print itself: RUN-MATRIX writes directly to the
;;;; terminal and returns only once the user quits.

(in-package #:cl-cmatrix/cli)

(defun %cmatrix-version ()
  "The running CL-CMATRIX system's :VERSION, the single source of truth also
read by flake.nix and enforced by release.yml against the git tag."
  (let ((system (asdf:find-system "cl-cmatrix" nil)))
    (if system (asdf:component-version system) "0.0.0")))

(defun %cmatrix-color-choices ()
  (mapcar (lambda (name) (string-downcase (symbol-name name))) (list-color-schemes)))

(defun %cmatrix-handler (invocation)
  (run-matrix :speed (option-value invocation :speed)
              :color (intern (string-upcase (option-value invocation :color)) :keyword))
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
                       :description "Trail color scheme (default green)."))
   :handler #'%cmatrix-handler))

(defun main (&optional (argv (current-process-argv)))
  "Parse ARGV against MAKE-CMATRIX-APP and exit the process with the
resulting code. The default ARGV is the live process argv, so this is safe
to call directly from a toplevel form."
  (uiop:quit (run-app (make-cmatrix-app) :argv argv)))

(defun image-entry-point ()
  "Toplevel of the delivered `cl-cmatrix` executable, named by :ENTRY-POINT
in cl-cmatrix.asd. A dumped image comes back with the state it was dumped
with, which for a packaged build is a build sandbox that no longer exists;
this puts the process back in touch with the machine it is actually running
on before the CLI sees an argument."
  (setf *default-pathname-defaults* (uiop:getcwd))
  (uiop:setup-temporary-directory)
  (main))
