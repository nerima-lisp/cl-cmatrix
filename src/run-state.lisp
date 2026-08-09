;;;; src/run-state.lisp
;;;;
;;;; The mutable driver state CL-TTY-KIT's realtime tick loop threads through
;;;; poll -> advance -> render, and the runtime key bindings that mutate it.
;;;; MATRIX-STATE stays free of terminal, renderer, executor and timing
;;;; concerns; all four live here.
;;;;
;;;; RUN-STATE owns the animation's PACE, which MATRIX-STATE no longer does.
;;;; CL-TTY-KIT:TICK-LOOP-RUN-REALTIME binds its :INTERVAL once for the whole
;;;; loop (cl-tty-kit src/tick-loop.lisp:117-118), so nothing pressed at
;;;; runtime can change how long it sleeps. The loop therefore always runs at
;;;; the fixed +BASE-TICK-SECONDS+ and RUN-STATE-ADVANCE counts base ticks,
;;;; touching the matrix only once every UPDATE-TICKS of them. That is how
;;;; upstream cmatrix's `napms(update * 10)` -- and its runtime-adjustable
;;;; `update` -- are reproduced through a loop that cannot re-read its own
;;;; interval.

(in-package #:cl-cmatrix)

(defstruct (run-state (:constructor make-run-state))
  "Mutable driver state for CL-TTY-KIT's realtime tick loop.

MATRIX is the animation state, RENDERER owns terminal output, INPUT-POLLER
turns the input stream into typed key events, and RENDER-CONTEXT owns drawing
memoization. WORKERS configures the persistent cl-concurrent-kit worker pool;
EXECUTOR is that pool, used by wide matrix transitions.

UPDATE-TICKS, BASE-TICK and SPEED are the tick model (see this file's
header). UPDATE-TICKS is how many base ticks pass between matrix advances --
the effective delay, never below 1 -- and BASE-TICK counts them off, firing
an advance and resetting when it reaches UPDATE-TICKS. SPEED is retained
rather than folded into UPDATE-TICKS because the runtime 0-9 keys set a raw
upstream update delay, which has to be re-scaled by SPEED to become a new
UPDATE-TICKS."
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
  (update-ticks 1 :type (integer 1 *))
  (base-tick 0 :type fixnum)
  (speed +default-speed+)
  message)

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

(defun %update-ticks-for-delay (update-delay speed)
  "Return how many +BASE-TICK-SECONDS+ ticks separate two matrix advances
when the upstream update delay is UPDATE-DELAY and our --speed extension is
SPEED.

UPDATE-DELAY is upstream's `update`, in the same 10 millisecond units its
`napms(update * 10)` uses, which +BASE-TICK-SECONDS+ is deliberately equal
to -- so at SPEED 1 the tick count and the delay are the same number. SPEED
divides it, so SPEED 2 advances twice as often. The floor of 1 covers both
UPDATE-DELAY 0 and any SPEED large enough to round the quotient to zero: the
matrix can advance at most once per base tick."
  (max 1 (round (/ update-delay speed))))

(defun %run-state-key-character (event)
  (when (and (typep event 'key-event)
             (eq (key-event-type event) :character)
             (eq (key-event-kind event) :press)
             (characterp (key-event-code event)))
    (key-event-code event)))

(defun %run-state-change-matrix (run-state &key
                                             (color nil color-p)
                                             (bold nil bold-p)
                                             (partial-bold-p nil partial-bold-p-p)
                                             (no-bold-p nil no-bold-p-p)
                                             (lambda-p nil lambda-p-p)
                                             (asyncp nil asyncp-p)
                                             (random-bold-p nil random-bold-p-p)
                                             (change-glyphs-p nil change-glyphs-p-p)
                                             (glyphs nil glyphs-p))
  "Apply supplied animation options as one immutable matrix-state update.

There is no :SPEED here any more: pace is RUN-STATE's, not MATRIX-STATE's
(see this file's header), and is changed through %RUN-STATE-SET-UPDATE-DELAY
instead."
  (let ((matrix (if glyphs-p
                   (%matrix-state-with-glyphs (run-state-matrix run-state) glyphs)
                   (%copy-matrix-state (run-state-matrix run-state)))))
    (when color-p
      (setf (matrix-state-color matrix) color))
    (when bold-p
      (setf (matrix-state-bold matrix) bold))
    (when partial-bold-p-p
      (setf (matrix-state-partial-bold-p matrix) partial-bold-p))
    (when no-bold-p-p
      (setf (matrix-state-no-bold-p matrix) no-bold-p))
    (when lambda-p-p
      (setf (matrix-state-lambda-p matrix) lambda-p))
    (when asyncp-p
      (setf (matrix-state-asyncp matrix) asyncp))
    (when random-bold-p-p
      (setf (matrix-state-random-bold-p matrix) random-bold-p))
    (when change-glyphs-p-p
      (setf (matrix-state-change-glyphs-p matrix) change-glyphs-p))
    (setf (run-state-matrix run-state) matrix)))

(defun %run-state-set-update-delay (run-state update-delay)
  "Set RUN-STATE's pace from a raw upstream update delay, upstream's
`update = keypress - 48` for the 0-9 keys. A LARGER delay is SLOWER: 0 is
the fastest the loop can go and 9 the slowest. The base-tick counter is reset
so the new pace takes effect from this tick rather than from wherever the old
count happened to be."
  (setf (run-state-update-ticks run-state)
        (%update-ticks-for-delay update-delay (run-state-speed run-state))
        (run-state-base-tick run-state) 0))

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
       (%run-state-change-matrix
        run-state
        :lambda-p (not (matrix-state-lambda-p (run-state-matrix run-state))))
       :changed)
      ((or (char= character #\p) (char= character #\P))
       (setf (run-state-pausedp run-state) (not (run-state-pausedp run-state)))
       :changed)
      ((digit-char-p character)
       (%run-state-set-update-delay run-state (digit-char-p character))
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

(defun run-state-due-p (run-state)
  "True when this base tick is the one RUN-STATE's animation advances on.

Called once per base tick by RUN-STATE-ADVANCE, and it mutates: the counter
is bumped and, on the tick it fires, reset. The comparison is >= rather than
= so that lowering UPDATE-TICKS at runtime -- a 0-9 key press resets the
counter, but a resize or a future caller need not -- can never leave the
counter parked above the threshold with the animation frozen."
  (let ((base-tick (1+ (run-state-base-tick run-state))))
    (cond
      ((>= base-tick (run-state-update-ticks run-state))
       (setf (run-state-base-tick run-state) 0)
       t)
      (t
       (setf (run-state-base-tick run-state) base-tick)
       nil))))

(defun run-state-advance (run-state)
  "Advance RUN-STATE's animation by one frame, but only on the base ticks the
tick model says are due (RUN-STATE-DUE-P) and only when not paused.

The realtime loop calls this every +BASE-TICK-SECONDS+ so that input polling
and rendering stay responsive at 100 Hz regardless of how slow the animation
itself is running; a tick that is not due is a no-op on the matrix."
  (when (and (run-state-due-p run-state)
             (not (run-state-pausedp run-state)))
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
                                  (old-style-p nil) (lambda-p nil) (asyncp t)
                                  (random-bold-p nil)
                                  (change-glyphs-p nil) (screensaverp nil)
                                  (lockp nil) (update-ticks 1) message)
  "Build the animation, renderer, input poller, render context and tick model.

SPEED reaches no further than the RUN-STATE it is stored on: MAKE-MATRIX-STATE
has no speed of its own, and RUN-MATRIX has already validated this one. It is
retained here so the 0-9 keys can re-scale a new update delay by it.
UPDATE-TICKS is the already-resolved effective delay in base ticks; RUN-MATRIX
computes it, since only it knows whether --fps or --update-delay won."
  (let ((matrix (make-matrix-state width height :color color
                                    :glyphs glyphs :bold bold
                                    :partial-bold-p partial-bold-p
                                    :no-bold-p no-bold-p
                                    :old-style-p old-style-p
                                    :lambda-p lambda-p
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
                    :update-ticks update-ticks
                    :base-tick 0
                    :speed speed
                    :message (if (and lockp (null message))
                                 "Computer locked."
                                 message))))
