(in-package #:cl-cmatrix)

(defstruct (run-state (:constructor make-run-state))
  "Mutable driver state for CL-TTY-KIT's realtime tick loop.

MATRIX is the animation state, RENDERER owns terminal output, INPUT-POLLER
turns the input stream into typed key events, and RENDER-CONTEXT owns drawing
memoization. Keeping all four responsibilities here leaves MATRIX-STATE free
of terminal and renderer concerns."
  matrix
  renderer
  (quitp nil :type boolean)
  input-poller
  (render-context (make-render-context) :type render-context))

(defun %sync-renderer-size (run-state)
  (let ((renderer (run-state-renderer run-state))
        (matrix (run-state-matrix run-state)))
    (when (or (/= (renderer-width renderer) (matrix-state-width matrix))
              (/= (renderer-height renderer) (matrix-state-height matrix)))
      (renderer-resize renderer (matrix-state-width matrix) (matrix-state-height matrix)))))

(defun %poll-resize (matrix fd terminal-size-fn)
  "Return MATRIX reflowed to the terminal size TERMINAL-SIZE-FN reports for
FD, or MATRIX unchanged when the size is unavailable or already matches."
  (multiple-value-bind (columns rows) (funcall terminal-size-fn fd)
    (if (and columns rows
             (or (/= columns (matrix-state-width matrix))
                 (/= rows (matrix-state-height matrix))))
        (matrix-resize matrix columns rows)
        matrix)))

(defun %default-fd () 0)

(defun run-state-poll (run-state &key (fd (%default-fd)) (terminal-size-fn #'terminal-size))
  "Observe terminal size and input events before RUN-STATE's next tick."
  (setf (run-state-matrix run-state)
        (%poll-resize (run-state-matrix run-state) fd terminal-size-fn))
  (%sync-renderer-size run-state)
  (let ((events (funcall (run-state-input-poller run-state) run-state nil)))
    (when (poll-quit-events events)
      (setf (run-state-quitp run-state) t)))
  run-state)

(defun run-state-advance (run-state)
  "Advance RUN-STATE's animation state by one tick."
  (setf (run-state-matrix run-state) (matrix-advance (run-state-matrix run-state)))
  run-state)

(defun run-state-render (run-state)
  "Redraw RUN-STATE and return the diffed ANSI frame for this tick."
  (let ((renderer (run-state-renderer run-state)))
    (renderer-clear renderer)
    (matrix-draw (renderer-screen renderer)
                 (run-state-matrix run-state)
                 (run-state-render-context run-state))
    (renderer-render renderer)))

(defun %terminal-dimensions (columns rows)
  "Return terminal dimensions, falling back to the classic 80x24 size."
  (values (or columns 80) (or rows 24)))

(defun %make-initial-run-state (width height speed color glyphs bold random-state input-stream)
  "Build the animation, renderer, input poller, and render context."
  (let ((matrix (make-matrix-state width height :speed speed :color color
                                    :glyphs glyphs :bold bold
                                    :random-state random-state))
        (renderer (make-renderer width height)))
    (make-run-state :matrix matrix
                    :renderer renderer
                    :quitp nil
                    :input-poller (make-stream-input-poller input-stream)
                    :render-context (make-render-context))))
