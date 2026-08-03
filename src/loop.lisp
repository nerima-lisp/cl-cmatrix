;;;; src/loop.lisp
;;;;
;;;; The real-IO half of the tick-loop split cl-tty-kit's own
;;;; examples/renderer-loop.lisp and examples/event-loop.lisp establish: a
;;;; pure state-advance function (MATRIX-ADVANCE, in state.lisp) stays
;;;; entirely separate from the thin loop that touches a real terminal. This
;;;; file is that thin loop, split the same way CL-TTY-KIT:
;;;; TICK-LOOP-RUN-REALTIME's own :POLL argument (added in cl-tty-kit v1.4.0)
;;;; now expects it to be: RUN-STATE-POLL observes the terminal (size, quit
;;;; key) ahead of every tick, and RUN-STATE-ADVANCE only steps
;;;; MATRIX-ADVANCE. QUIT-KEY-CHARACTER-P, POLL-QUIT-KEY and POLL-QUIT-KEY-CPS
;;;; take their I/O as parameters rather than reaching for a live terminal, so
;;;; tests can drive them against a STRING-INPUT-STREAM and a stubbed
;;;; terminal-size function instead of a real tty.

(in-package #:cl-cmatrix)

(defun %default-fps () 30)

(defparameter +default-fps+ (%default-fps)
  "Default tick rate, in ticks per second, for RUN-MATRIX.")

(defun %build-quit-characters ()
  (list #\q #\Q #\Escape))

(defparameter +quit-characters+ (%build-quit-characters)
  "Raw characters that stop RUN-MATRIX by cmatrix convention (q/Q) or
terminal convention (Escape). Ctrl-C is matched separately, by character
code: raw mode clears ISIG (see cl-tty-kit's raw-mode-sbcl.lisp), so it
arrives as the raw ETX byte rather than as a SIGINT.")

(defun quit-key-character-p (character)
  "True when CHARACTER should stop RUN-MATRIX: a member of
+QUIT-CHARACTERS+, or the raw Ctrl-C byte (character code 3)."
  (or (member character +quit-characters+ :test #'char=)
      (= (char-code character) 3)))

(defun poll-quit-key-cps (stream on-quit on-continue)
  "Consume every character currently available on STREAM without blocking, in
continuation-passing style: call ON-QUIT with the offending character the
moment one satisfies QUIT-KEY-CHARACTER-P (the rest of STREAM's buffered
input, if any, is left consumed either way, since none of it is looked at
again), or call ON-CONTINUE with no arguments once STREAM is exhausted
without one. This is POLL-QUIT-KEY's own implementation; it is exposed
directly for callers that want the actual quit character rather than only a
boolean -- for example to log which of q/Q/Escape/Ctrl-C ended a run -- and
for CL-WEAVE's WITH-CONTINUATION-RESULT, which drives a CPS function exactly
this shape."
  (loop while (listen stream)
        do (let ((character (read-char stream)))
             (when (quit-key-character-p character)
               (return-from poll-quit-key-cps (funcall on-quit character)))))
  (funcall on-continue))

(defun poll-quit-key (stream)
  "Consume every character currently available on STREAM without blocking,
returning true as soon as one of them satisfies QUIT-KEY-CHARACTER-P (the
rest, if any, are still consumed, since none of them will be looked at
again). Used instead of a blocking read because a real-time animation loop
cannot afford to wait on a key that may never come. Works against any
character stream -- including a STRING-INPUT-STREAM in a test -- not only a
live terminal. A thin direct-style wrapper over POLL-QUIT-KEY-CPS for every
caller that only needs the yes/no answer."
  (poll-quit-key-cps stream (constantly t) (constantly nil)))

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

(defun %default-fd () 0)

(defun run-state-poll (run-state &key (fd (%default-fd)) (terminal-size-fn #'terminal-size))
  "Observe the real terminal ahead of RUN-STATE's next tick: reflow for the
current size (via TERMINAL-SIZE-FN), resize the renderer to match, and record
whether a quit key has arrived on INPUT-STREAM. Returns RUN-STATE, mutated in
place -- this is the POLL half of the poll/advance split
CL-TTY-KIT:TICK-LOOP-RUN-REALTIME's :POLL argument drives, called once before
each tick's RUN-STATE-ADVANCE; never used by the deterministic bounded-tick
tests, which only exercise RUN-STATE-ADVANCE."
  (setf (run-state-matrix run-state)
        (%poll-resize (run-state-matrix run-state) fd terminal-size-fn))
  (%sync-renderer-size run-state)
  (when (poll-quit-key (run-state-input-stream run-state))
    (setf (run-state-quitp run-state) t))
  run-state)

(defun run-state-advance (run-state)
  "Advance RUN-STATE's underlying MATRIX-STATE by one tick, returning
RUN-STATE mutated in place. The pure-given-RANDOM-STATE half of the
poll/advance split: terminal observation (resize, quit-key) is
RUN-STATE-POLL's job instead, run ahead of this one every tick by
CL-TTY-KIT:TICK-LOOP-RUN-REALTIME's :POLL argument."
  (setf (run-state-matrix run-state) (matrix-advance (run-state-matrix run-state)))
  run-state)

(defun run-state-render (run-state)
  "Redraw RUN-STATE's renderer back buffer from its current MATRIX-STATE and
return the diffed ANSI frame string for this tick."
  (let ((renderer (run-state-renderer run-state)))
    (renderer-clear renderer)
    (matrix-draw (renderer-screen renderer) (run-state-matrix run-state))
    (renderer-render renderer)))

(defun %terminal-dimensions (columns rows)
  "Return the WIDTH and HEIGHT RUN-MATRIX should build its MATRIX-STATE at,
given the two values CL-TTY-KIT:TERMINAL-SIZE reports (each NIL when the
size could not be determined): COLUMNS/ROWS themselves when both are
present, else the classic 80x24 fallback."
  (values (or columns 80) (or rows 24)))

(defun %make-initial-run-state (width height speed color glyphs bold random-state input-stream)
  "Return the RUN-STATE RUN-MATRIX drives: a WIDTH by HEIGHT MATRIX-STATE
paired with a matching CL-TTY-KIT renderer, not yet advanced or rendered.
Pure given RANDOM-STATE, like MAKE-MATRIX-STATE itself -- the only impure
piece of RUN-MATRIX's setup is polling the terminal size for WIDTH/HEIGHT in
the first place (see %TERMINAL-DIMENSIONS), which this function takes
already resolved rather than reaching for itself."
  (let ((matrix (make-matrix-state width height :speed speed :color color
                                    :glyphs glyphs :bold bold
                                    :random-state random-state))
        (renderer (make-renderer width height)))
    (make-run-state :matrix matrix :renderer renderer
                     :quitp nil :input-stream input-stream)))

(defun run-matrix (&key (speed 1) (color :green) (glyphs +default-glyphs+) (bold nil)
                        (stream *standard-output*)
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

SPEED, COLOR, GLYPHS, and BOLD are as in MAKE-MATRIX-STATE. FPS is the
target tick rate (default 30). RANDOM-STATE seeds the fall-timing and glyph
randomness; supply a fixed seed (e.g. one built by SB-EXT:SEED-RANDOM-STATE)
for a reproducible run. Returns the final MATRIX-STATE."
  (multiple-value-bind (columns rows) (terminal-size fd)
    (multiple-value-bind (width height) (%terminal-dimensions columns rows)
      (let ((run-state (%make-initial-run-state width height speed color glyphs bold
                                                  random-state input-stream)))
        (with-terminal-session (out :stream stream :fd fd :raw-mode t
                                     :alternate-screen t :hide-cursor t)
          (handler-case
              (tick-loop-run-realtime
               run-state
               #'run-state-advance
               #'run-state-render
               #'run-state-quitp
               :stream out :interval (/ 1 fps)
               :poll (lambda (state) (run-state-poll state :fd fd)))
            (sb-sys:interactive-interrupt () nil)))
        (run-state-matrix run-state)))))
