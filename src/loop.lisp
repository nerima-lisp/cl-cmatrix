;;;; src/loop.lisp
;;;;
;;;; The real-IO half of the tick-loop split cl-tty-kit's own
;;;; examples/renderer-loop.lisp and examples/event-loop.lisp establish: a
;;;; pure state-advance function (MATRIX-ADVANCE, in state.lisp) stays
;;;; entirely separate from the thin loop that touches a real terminal. This
;;;; file is that thin loop -- polling the terminal size, polling for a quit
;;;; key, and driving CL-TTY-KIT:TICK-LOOP-RUN-REALTIME -- plus the small
;;;; pieces of it (QUIT-KEY-CHARACTER-P, POLL-QUIT-KEY, RUN-STATE-ADVANCE)
;;;; that take their I/O as parameters rather than reaching for a live
;;;; terminal, so tests can drive them against a STRING-INPUT-STREAM and a
;;;; stubbed terminal-size function instead of a real tty.

(in-package #:cl-cmatrix)

(defparameter +default-fps+ 30
  "Default tick rate, in ticks per second, for RUN-MATRIX.")

(defparameter +quit-characters+ (list #\q #\Q #\Escape)
  "Raw characters that stop RUN-MATRIX by cmatrix convention (q/Q) or
terminal convention (Escape). Ctrl-C is matched separately, by character
code: raw mode clears ISIG (see cl-tty-kit's raw-mode-sbcl.lisp), so it
arrives as the raw ETX byte rather than as a SIGINT.")

(defun quit-key-character-p (character)
  "True when CHARACTER should stop RUN-MATRIX: a member of
+QUIT-CHARACTERS+, or the raw Ctrl-C byte (character code 3)."
  (or (member character +quit-characters+ :test #'char=)
      (= (char-code character) 3)))

(defun poll-quit-key (stream)
  "Consume every character currently available on STREAM without blocking,
returning true as soon as one of them satisfies QUIT-KEY-CHARACTER-P (the
rest, if any, are still consumed, since none of them will be looked at
again). Used instead of a blocking read because a real-time animation loop
cannot afford to wait on a key that may never come. Works against any
character stream -- including a STRING-INPUT-STREAM in a test -- not only a
live terminal."
  (loop while (listen stream)
        thereis (quit-key-character-p (read-char stream))))

(defstruct (run-state (:constructor make-run-state))
  "The mutable driver state RUN-MATRIX threads through
CL-TTY-KIT:TICK-LOOP-RUN-REALTIME. MATRIX is the animation state proper (see
state.lisp); RENDERER is the double-buffered CL-TTY-KIT repaint helper;
QUITP is set once a quit key has been seen; INPUT-STREAM is where
POLL-QUIT-KEY looks for one. Kept separate from MATRIX-STATE so that struct
stays free of I/O and can go on being used by the pure, deterministic tests
in t/."
  matrix
  renderer
  (quitp nil :type boolean)
  input-stream)

(defun %sync-renderer-size (run-state)
  (let ((renderer (run-state-renderer run-state))
        (matrix (run-state-matrix run-state)))
    (when (or (/= (renderer-width renderer) (matrix-state-width matrix))
              (/= (renderer-height renderer) (matrix-state-height matrix)))
      (renderer-resize renderer (matrix-state-width matrix) (matrix-state-height matrix)))))

(defun %poll-resize (matrix fd terminal-size-fn)
  "Return MATRIX reflowed to the terminal size TERMINAL-SIZE-FN reports for
FD, or MATRIX unchanged when the size is unavailable (both values NIL, cl-
tty-kit's convention for \"could not be determined\") or already matches.
TERMINAL-SIZE-FN defaults to CL-TTY-KIT:TERMINAL-SIZE and is injectable so
tests can stub a resize without a real terminal, the same reason
MATRIX-STATE's randomness is injected rather than read from a global."
  (multiple-value-bind (columns rows) (funcall terminal-size-fn fd)
    (if (and columns rows
             (or (/= columns (matrix-state-width matrix))
                 (/= rows (matrix-state-height matrix))))
        (matrix-resize matrix columns rows)
        matrix)))

(defun run-state-advance (run-state &key (fd 0) (terminal-size-fn #'terminal-size))
  "Advance RUN-STATE by one tick: reflow for the current terminal size (via
TERMINAL-SIZE-FN), advance the underlying MATRIX-STATE, resize the renderer
to match, and record whether a quit key has arrived on INPUT-STREAM. Returns
RUN-STATE, mutated in place -- this function, unlike MATRIX-ADVANCE, is the
impure side of the split and is never used by the deterministic bounded-tick
tests."
  (setf (run-state-matrix run-state)
        (%poll-resize (run-state-matrix run-state) fd terminal-size-fn))
  (setf (run-state-matrix run-state) (matrix-advance (run-state-matrix run-state)))
  (%sync-renderer-size run-state)
  (when (poll-quit-key (run-state-input-stream run-state))
    (setf (run-state-quitp run-state) t))
  run-state)

(defun run-state-render (run-state)
  "Redraw RUN-STATE's renderer back buffer from its current MATRIX-STATE and
return the diffed ANSI frame string for this tick."
  (let ((renderer (run-state-renderer run-state)))
    (renderer-clear renderer)
    (matrix-draw (renderer-screen renderer) (run-state-matrix run-state))
    (renderer-render renderer)))

(defun run-matrix (&key (speed 1) (color :green) (stream *standard-output*)
                        (input-stream *standard-input*) (fd 0)
                        (fps +default-fps+) (random-state (make-random-state t)))
  "Run the full-screen matrix-rain animation on STREAM until a quit key (q,
Q, Escape, or Ctrl-C) is read from INPUT-STREAM. Enters raw mode and the
terminal's alternate screen for the duration and always restores both --
CL-TTY-KIT:WITH-TERMINAL-SESSION wraps the whole run in UNWIND-PROTECT, so a
signaled condition or an interactive interrupt cannot strand the caller's
terminal in a broken state. A stray SB-SYS:INTERACTIVE-INTERRUPT (Ctrl-C
arriving before raw mode has taken effect, or delivered as a real signal
rather than a raw byte) is treated the same as any other quit: caught here
so the run ends cleanly rather than dropping into the debugger.

SPEED and COLOR are as in MAKE-MATRIX-STATE. FPS is the target tick rate
(default 30). RANDOM-STATE seeds the fall-timing and glyph randomness;
supply a fixed seed (e.g. one built by SB-EXT:SEED-RANDOM-STATE) for a
reproducible run. Returns the final MATRIX-STATE."
  (multiple-value-bind (columns rows) (terminal-size fd)
    (let* ((width (or columns 80))
           (height (or rows 24))
           (matrix (make-matrix-state width height :speed speed :color color
                                       :random-state random-state))
           (renderer (make-renderer width height))
           (run-state (make-run-state :matrix matrix :renderer renderer
                                       :quitp nil :input-stream input-stream)))
      (with-terminal-session (out :stream stream :fd fd :raw-mode t
                                   :alternate-screen t :hide-cursor t)
        (handler-case
            (tick-loop-run-realtime
             run-state
             (lambda (state) (run-state-advance state :fd fd))
             #'run-state-render
             #'run-state-quitp
             :stream out :interval (/ 1 fps))
          (sb-sys:interactive-interrupt () nil)))
      (run-state-matrix run-state))))
