(in-package #:cl-cmatrix)

(defun %default-fps () 30)

(defparameter +default-fps+ (%default-fps)
  "Default tick rate, in ticks per second, for RUN-MATRIX.")

(defun run-matrix (&key (speed (%default-speed)) (color (%default-color))
                        (glyphs +default-glyphs+) (bold (%default-bold))
                        (stream *standard-output*)
                        (input-stream *standard-input*) (fd 0)
                        (fps +default-fps+) (random-state (make-random-state t)))
  "Run the full-screen matrix-rain animation on STREAM until a quit event is
read from INPUT-STREAM. q, Q, Escape, and Ctrl-C are recognized by the typed
CL-TTY-KIT input poller. The terminal session is always restored after a
condition or interrupt.

SPEED, COLOR, GLYPHS, and BOLD are as in MAKE-MATRIX-STATE. FPS is the target
tick rate. RANDOM-STATE seeds the fall timing and glyph randomness; supply a
fixed seed for reproducible runs. Returns the final MATRIX-STATE."
  (multiple-value-bind (columns rows) (terminal-size fd)
    (multiple-value-bind (width height) (%terminal-dimensions columns rows)
      (let ((run-state (%make-initial-run-state width height speed color glyphs bold
                                                  random-state input-stream)))
        (with-terminal-session (out :stream stream :fd fd
                                     :raw-mode t :alternate-screen t :hide-cursor t)
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
