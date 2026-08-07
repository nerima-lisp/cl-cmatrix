;;;; src/cli.lisp
;;;;
;;;; The `cl-cmatrix` command line: a single root command (no subcommands)
;;;; exposing the classic cmatrix controls plus --speed, --color, --charset,
;;;; --bold, --fps, --workers, and --seed over RUN-MATRIX, with
;;;; --help/--version scaffolding free from cl-cli. Unlike
;;;; cl-cowsay this is a persistent, full-screen, raw-mode loop rather than a
;;;; one-shot print, so the handler has no output to print itself:
;;;; RUN-MATRIX writes directly to the terminal and returns only once the
;;;; user quits.

(in-package #:cl-cmatrix/cli)

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
  (let* ((all-bold-p (option-value invocation :all-bold))
         (partial-bold-p (option-value invocation :bold))
         (no-bold-p (option-value invocation :no-bold))
         (random-bold-p (option-value invocation :random-bold))
         (rainbow-p (option-value invocation :rainbow))
         (japanese-p (option-value invocation :japanese))
         (lambda-p (option-value invocation :lambda))
         (async-p (option-value invocation :async))
         (old-style-p (option-value invocation :old-style))
         (fps-p (eq (option-value-source invocation :fps) :command-line)))
    (list :speed (option-value invocation :speed)
          :color (if rainbow-p :rainbow
                     (%option-keyword invocation :color))
          :glyphs (cond
                    (lambda-p (charset-glyphs :lambda))
                    (japanese-p (charset-glyphs :katakana))
                    (t (charset-glyphs (%option-keyword invocation :charset))))
          :bold (and all-bold-p
                     (not no-bold-p)
                     (not random-bold-p))
          :partial-bold-p (and partial-bold-p
                               (not all-bold-p)
                               (not no-bold-p)
                               (not random-bold-p))
          :no-bold-p no-bold-p
          :old-style-p old-style-p
          :asyncp async-p
          :random-bold-p (and random-bold-p (not all-bold-p)
                              (not partial-bold-p) (not no-bold-p))
          :change-glyphs-p (option-value invocation :change-glyphs)
          :screensaverp (option-value invocation :screensaver)
          :lockp (option-value invocation :lock)
          :message (option-value invocation :message)
          :tty (option-value invocation :tty)
          :force-linux-term (option-value invocation :force-linux-term)
          :fps (when fps-p (option-value invocation :fps))
          :update-delay (unless fps-p
                          (option-value invocation :update-delay))
          :workers (option-value invocation :workers)
          :random-state (%cmatrix-random-state (option-value invocation :seed)))))

(defun %cmatrix-run-with-terminal (args)
  "Apply RUN-MATRIX ARGS, optionally using a named terminal stream.

The TTY stream remains open for the complete RUN-MATRIX call, so raw-mode
restoration and the realtime poller both address the same descriptor."
  (let ((tty (getf args :tty)))
    (remf args :tty)
    (if tty
        (with-open-file (terminal tty
                                 :direction :io
                                 :element-type 'character
                                 :if-does-not-exist nil)
          (unless terminal
            (error "Cannot open tty ~A." tty))
          (let ((fd (stream-fd terminal)))
            (unless fd
              (error "Cannot determine the file descriptor for tty ~A." tty))
            (apply #'run-matrix
                   (list* :stream terminal
                          :input-stream terminal
                          :fd fd
                          args))))
        (apply #'run-matrix args))))

(defun %cmatrix-handler (invocation)
  (let* ((args (%cmatrix-run-matrix-args invocation))
         (force-linux-term (getf args :force-linux-term)))
    (remf args :force-linux-term)
    (if force-linux-term
        (with-environment-variables (("TERM" "linux"))
          (%cmatrix-run-with-terminal args))
        (%cmatrix-run-with-terminal args)))
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
   (make-cmatrix-options)
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
