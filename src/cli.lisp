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
plist, which is what actually takes over the terminal.

-c/--classic/--japanese overrides --charset with :CLASSIC, the CJK Symbols
and Punctuation set upstream's own -c draws. -m/--lambda is NOT a charset
override: it is upstream's render mode, passed straight through as
:LAMBDA-P, so it composes with whichever glyph set is in force."
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

RUN-MATRIX-FN is the seam that lets this function be executed at all from a
test. RUN-MATRIX takes over the terminal and does not return until the user
quits, so a spec that reached the real one would hang the suite behind a
keypress -- which is why, before this parameter existed, this function, its
caller, the :TTY removal below and the whole --tty branch were unreachable
from the suite and permanently unverified. It follows the shape
RUN-STATE-POLL and RUN-STATE-POLL-CPS already use for TERMINAL-SIZE-FN in
run-state.lisp: a keyword whose default is the production function, so every
production caller passes nothing and gets the real behaviour, and only t/
supplies anything else. A keyword rather than a special variable also keeps
the injection lexical: an SBCL special is bound per thread, so a worker
thread calling RUN-MATRIX under a spec's dynamic binding would reach the real
one and seize the terminal, and an argument cannot fail that way.

A --tty argument only means anything when it names a terminal, so a path that
opens to anything else is refused here, after the open and before the
descriptor is taken -- early enough that RUN-MATRIX never writes a frame into
it. INTERACTIVE-STREAM-P is the discriminator because it is the one that was
measured to work: on SBCL 2.6.0/darwin it returns NIL for a regular file, NIL
for a FIFO, NIL for /dev/null and T only for a pty slave. SB-UNIX:UNIX-ISATTY
does not substitute for it as written -- it returns the C int, and the 0 it
returns for a non-terminal is true in Lisp, so a naive test on it accepts
every path. Opening first is safe for a FIFO despite the usual blocking rule:
:DIRECTION :IO opens O_RDWR, which was measured to return immediately rather
than wait for a peer.

OPEN with an explicit CLOSE, rather than WITH-OPEN-FILE, because
WITH-OPEN-FILE closes with :ABORT T when its body exits non-locally, and an
aborted close of a :DIRECTION :IO stream DELETES the file: measured on SBCL
2.6.0, signalling from inside the macro left the named path gone. Every exit
from this branch other than a clean RUN-MATRIX return is non-local -- the
rejection below, a descriptor failure, an error out of the animation, a
Ctrl-C -- so under WITH-OPEN-FILE the very check meant to protect a
mistakenly-named file is what would destroy it. CLOSE defaults to :ABORT NIL
and leaves the file alone."
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
  "Run the animation INVOCATION describes and return the process exit code.

MAKE-CMATRIX-APP installs this as the app's :HANDLER, and cl-cli calls a
handler with the invocation alone, so RUN-MATRIX-FN defaults to #'RUN-MATRIX
and the delivered CLI never mentions it. It is threaded through to
%CMATRIX-RUN-WITH-TERMINAL purely so a spec can call this function directly
-- which is how the suite reaches it, never through RUN-APP -- without the
animation seizing the terminal. See %CMATRIX-RUN-WITH-TERMINAL for why the
seam is a defaulted keyword rather than a special variable."
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
