(in-package #:cl-cmatrix)

(defstruct (run-state (:constructor make-run-state))
  "Mutable driver state for CL-TTY-KIT's realtime tick loop.

MATRIX is the animation state, RENDERER owns terminal output, INPUT-POLLER
turns the input stream into typed key events, and RENDER-CONTEXT owns drawing
memoization. WORKERS configures the persistent cl-concurrent-kit worker pool;
EXECUTOR is that pool, used by wide matrix transitions. Keeping these
responsibilities here leaves
MATRIX-STATE free of terminal, renderer, and executor concerns."
  matrix
  renderer
  (quitp nil :type boolean)
  (lockp nil :type boolean)
  input-poller
  (workers +default-workers+ :type (integer 1 *))
  executor
  (render-context (make-render-context) :type render-context)
  (screensaverp nil :type boolean)
  (pausedp nil :type boolean)
  base-glyphs
  message)

(defparameter +run-state-speed-levels+
  #(0.1d0 0.25d0 0.5d0 0.75d0 1.0d0 1.25d0 1.5d0 2.0d0 3.0d0 4.0d0)
  "Speed multipliers selected by the runtime 0-9 key bindings.")

(defparameter +run-state-color-keys+
  '((#\! . :red)
    (#\@ . :green)
    (#\# . :yellow)
    (#\$ . :blue)
    (#\% . :magenta)
    (#\^ . :cyan)
    (#\& . :white)
    (#\r . :rainbow)
    (#\) . :rainbow))
  "Runtime color-key bindings inherited from the classic cmatrix UI.")

(defun %run-state-key-character (event)
  (when (and (typep event 'key-event)
             (eq (key-event-type event) :character)
             (eq (key-event-kind event) :press)
             (characterp (key-event-code event)))
    (key-event-code event)))

(defun %run-state-base-glyphs (run-state)
  "Return the non-lambda glyph set used when toggling lambda mode off."
  (or (run-state-base-glyphs run-state)
      (setf (run-state-base-glyphs run-state)
            (let ((glyphs (matrix-state-glyphs (run-state-matrix run-state))))
              (if (eq glyphs +lambda-glyphs+)
                  +default-glyphs+
                  glyphs)))))

(defun %run-state-change-matrix (run-state &key
                                             (speed nil speed-p)
                                             (color nil color-p)
                                             (bold nil bold-p)
                                             (partial-bold-p nil partial-bold-p-p)
                                             (no-bold-p nil no-bold-p-p)
                                             (asyncp nil asyncp-p)
                                             (random-bold-p nil random-bold-p-p)
                                             (change-glyphs-p nil change-glyphs-p-p)
                                             (glyphs nil glyphs-p))
  "Apply supplied animation options as one immutable matrix-state update."
  (let ((matrix (if glyphs-p
                   (%matrix-state-with-glyphs (run-state-matrix run-state) glyphs)
                   (%copy-matrix-state (run-state-matrix run-state)))))
    (when speed-p
      (setf (matrix-state-speed matrix) speed))
    (when color-p
      (setf (matrix-state-color matrix) color))
    (when bold-p
      (setf (matrix-state-bold matrix) bold))
    (when partial-bold-p-p
      (setf (matrix-state-partial-bold-p matrix) partial-bold-p))
    (when no-bold-p-p
      (setf (matrix-state-no-bold-p matrix) no-bold-p))
    (when asyncp-p
      (setf (matrix-state-asyncp matrix) asyncp))
    (when random-bold-p-p
      (setf (matrix-state-random-bold-p matrix) random-bold-p))
    (when change-glyphs-p-p
      (setf (matrix-state-change-glyphs-p matrix) change-glyphs-p))
    (setf (run-state-matrix run-state) matrix)))

(defun %run-state-toggle-lambda (run-state)
  "Toggle the runtime lambda glyph set without resetting column positions."
  (let* ((current (matrix-state-glyphs (run-state-matrix run-state)))
         (glyphs (if (eq current +lambda-glyphs+)
                     (%run-state-base-glyphs run-state)
                     +lambda-glyphs+)))
    (%run-state-change-matrix run-state :glyphs glyphs)
    :changed))

(defun run-state-apply-key-event (run-state event)
  "Apply one pressed runtime command and return its action keyword.

The action is :QUIT for a terminal event, :CHANGED for an animation option
change, or NIL when EVENT is not a command understood by CL-CMATRIX."
  (let ((character (%run-state-key-character event)))
    (cond
      ((and (quit-key-event-p event)
            (not (run-state-lockp run-state)))
       (setf (run-state-quitp run-state) t)
       :quit)
      ((run-state-screensaverp run-state)
       (setf (run-state-quitp run-state) t)
       :quit)
      ((null character) nil)
      ((char= character #\L)
       (setf (run-state-lockp run-state) t)
       (unless (run-state-message run-state)
         (setf (run-state-message run-state) "Computer locked."))
       :changed)
      ((char= character #\a)
       (%run-state-change-matrix
        run-state :asyncp (not (matrix-state-asyncp (run-state-matrix run-state))))
       :changed)
      ((char= character #\b)
       (%run-state-change-matrix
        run-state
        :bold nil
        :partial-bold-p t
        :no-bold-p nil
        :random-bold-p nil)
       :changed)
      ((char= character #\B)
       (%run-state-change-matrix
        run-state
        :bold t
        :partial-bold-p nil
        :no-bold-p nil
        :random-bold-p nil)
       :changed)
      ((char= character #\n)
       (%run-state-change-matrix
        run-state
        :bold nil
        :partial-bold-p nil
        :no-bold-p t
        :random-bold-p nil)
       :changed)
      ((char= character #\k)
       (%run-state-change-matrix
        run-state
        :change-glyphs-p (not (matrix-state-change-glyphs-p (run-state-matrix run-state))))
       :changed)
      ((char= character #\m)
       (%run-state-toggle-lambda run-state))
      ((or (char= character #\p) (char= character #\P))
       (setf (run-state-pausedp run-state) (not (run-state-pausedp run-state)))
       :changed)
      ((digit-char-p character)
       (let ((level (digit-char-p character)))
         (%run-state-change-matrix run-state :speed (aref +run-state-speed-levels+ level)))
       :changed)
      ((assoc character +run-state-color-keys+ :test #'char=)
       (%run-state-change-matrix
        run-state :color (cdr (assoc character +run-state-color-keys+ :test #'char=)))
       :changed)
      (t nil))))

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

(defun run-state-poll-cps (run-state on-quit on-continue
                           &key
                             (fd +default-fd+)
                             (terminal-size-fn #'terminal-size))
  "Poll RUN-STATE and continue through ON-QUIT or ON-CONTINUE.

ON-QUIT receives RUN-STATE and the quit event. ON-CONTINUE receives
RUN-STATE. The callback result is returned unchanged."
  (check-type on-quit function)
  (check-type on-continue function)
  (setf (run-state-matrix run-state)
        (%poll-resize (run-state-matrix run-state) fd terminal-size-fn))
  (%sync-renderer-size run-state)
  (let ((quit-event nil))
    (dolist (event (funcall (run-state-input-poller run-state) run-state nil))
      (when (eq (run-state-apply-key-event run-state event) :quit)
        (setf quit-event event)
        (return)))
    (if quit-event
        (funcall on-quit run-state quit-event)
        (funcall on-continue run-state))))

(defun run-state-poll (run-state &key (fd +default-fd+) (terminal-size-fn #'terminal-size))
  "Observe terminal size and input events before RUN-STATE's next tick."
  (run-state-poll-cps
   run-state
   (lambda (state event)
     (declare (ignore event))
     state)
   (lambda (state) state)
   :fd fd
   :terminal-size-fn terminal-size-fn)
  run-state)

(defun run-state-advance (run-state)
  "Advance RUN-STATE's animation state by one tick unless it is paused."
  (unless (run-state-pausedp run-state)
    (setf (run-state-matrix run-state)
          (matrix-advance (run-state-matrix run-state)
                          :executor (run-state-executor run-state)
                          :workers (run-state-workers run-state))))
  run-state)

(defun run-state-render (run-state)
  "Redraw RUN-STATE and return the diffed ANSI frame for this tick."
  (let ((renderer (run-state-renderer run-state)))
    (renderer-clear renderer)
    (matrix-draw (renderer-screen renderer)
                 (run-state-matrix run-state)
                 (run-state-render-context run-state))
    (matrix-draw-message (renderer-screen renderer)
                         (matrix-state-width (run-state-matrix run-state))
                         (matrix-state-height (run-state-matrix run-state))
                         (run-state-message run-state))
    (renderer-render renderer)))

(defun %terminal-dimensions (columns rows)
  "Return terminal dimensions, falling back to the classic 80x24 size."
  (values (or columns 80) (or rows 24)))

(defun %make-initial-run-state (width height speed color glyphs bold random-state input-stream
                                &key executor (workers +default-workers+)
                                  (partial-bold-p nil) (no-bold-p nil)
                                  (old-style-p nil) (asyncp t)
                                  (random-bold-p nil)
                                  (change-glyphs-p nil) (screensaverp nil)
                                  (lockp nil) message)
  "Build the animation, renderer, input poller, and render context."
  (let ((matrix (make-matrix-state width height :speed speed :color color
                                    :glyphs glyphs :bold bold
                                    :partial-bold-p partial-bold-p
                                    :no-bold-p no-bold-p
                                    :old-style-p old-style-p
                                    :asyncp asyncp
                                    :random-bold-p random-bold-p
                                    :change-glyphs-p change-glyphs-p
                                    :random-state random-state))
        (renderer (make-renderer width height)))
    (make-run-state :matrix matrix
                    :renderer renderer
                    :quitp nil
                    :lockp lockp
                    :input-poller (make-stream-input-poller input-stream)
                    :workers workers
                    :executor executor
                    :render-context (make-render-context)
                    :screensaverp screensaverp
                    :pausedp nil
                    :base-glyphs (if (eq glyphs +lambda-glyphs+)
                                     +default-glyphs+
                                     glyphs)
                    :message (if (and lockp (null message))
                                 "Computer locked."
                                 message))))
