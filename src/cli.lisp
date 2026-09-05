
(in-package #:cl-cmatrix/cli)

(defun %cmatrix-random-state (seed)
  "Return a fresh random state for RUN-MATRIX's :RANDOM-STATE: seeded from
SEED (an integer, for a reproducible run identical across invocations) when
supplied, else a nondeterministic one -- the same default RUN-MATRIX itself
uses."
  (if seed (sb-ext:seed-random-state seed) (make-random-state t)))

(defun %option-keyword (invocation option-name)
  "Convert a validated finite-choice option value to a keyword."
  (intern (string-upcase (option-value invocation option-name)) :keyword))

(defun %cmatrix-run-matrix-args (invocation)
  "Return INVOCATION's RUN-MATRIX keyword arguments, including resolved color,
glyph, seed, and mode options. --classic/--japanese selects the classic glyph
set, while --lambda remains an independent render mode."
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
          :glyphs (if japanese-p
                      (charset-glyphs :classic)
                      (charset-glyphs (%option-keyword invocation :charset)))
          :bold (and all-bold-p
                     (not no-bold-p)
                     (not random-bold-p))
          :partial-bold-p (and partial-bold-p
                               (not all-bold-p)
                               (not no-bold-p)
                               (not random-bold-p))
          :no-bold-p no-bold-p
          :old-style-p old-style-p
          :lambda-p lambda-p
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

(defun %cmatrix-run-with-terminal (args &key (run-matrix-fn #'run-matrix))
  "Apply RUN-MATRIX ARGS, optionally using a named terminal stream.

The TTY stream remains open for the complete RUN-MATRIX call, so raw-mode
restoration and the realtime poller both address the same descriptor.

RUN-MATRIX-FN is injectable for tests. Non-terminal paths are rejected before
RUN-MATRIX writes to them. The stream is closed explicitly so non-local exits
do not use WITH-OPEN-FILE's aborting close for a bidirectional stream."
  (let ((tty (getf args :tty)))
    (remf args :tty)
    (if tty
        (let ((terminal (open tty
                              :direction :io
                              :element-type 'character
                              :if-does-not-exist nil)))
          (unless terminal
            (error "Cannot open tty ~A." tty))
          (unwind-protect
               (progn
                 (unless (interactive-stream-p terminal)
                   (error "Cannot use tty ~A: it is not a terminal." tty))
                 (let ((fd (stream-fd terminal)))
                   (unless fd
                     (error "Cannot determine the file descriptor for tty ~A." tty))
                   (apply run-matrix-fn
                          (list* :stream terminal
                                 :input-stream terminal
                                 :fd fd
                                 args))))
            (close terminal)))
        (apply run-matrix-fn args))))

(defun %cmatrix-handler (invocation &key (run-matrix-fn #'run-matrix))
  "Run the animation described by INVOCATION and return the process exit code.
RUN-MATRIX-FN defaults to #'RUN-MATRIX and is injectable for tests."
  (let* ((args (%cmatrix-run-matrix-args invocation))
         (force-linux-term (getf args :force-linux-term)))
    (remf args :force-linux-term)
    (if force-linux-term
        (with-environment-variables (("TERM" "linux"))
          (%cmatrix-run-with-terminal args :run-matrix-fn run-matrix-fn))
        (%cmatrix-run-with-terminal args :run-matrix-fn run-matrix-fn)))
  0)

(defun make-cmatrix-app ()
  "Build a fresh CL-CLI app spec for `cl-cmatrix`. A function rather than a
constant so tests can build an independent instance per run."
  (make-app
   :name "cl-cmatrix"
   :version (%cmatrix-version)
   :summary "A Matrix-style digital rain terminal screensaver."
   :description
   "Full-screen falling-character animation. Like upstream cmatrix it
animates every other terminal column, leaving the odd ones blank, and gives
each stream a bright head over a color-graded dimming trail. Reflows
automatically on terminal resize.

Runtime keys: q, Escape or Ctrl-C quits. 0 through 9 set the update delay,
where a LARGER digit is SLOWER, exactly as -u does. b, B and n select
partial, full and no bold; a toggles asynchronous column timing; m toggles
lambda mode; k toggles glyph churn; p pauses; L locks; ! @ # $ % ^ & and r
change color."
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
