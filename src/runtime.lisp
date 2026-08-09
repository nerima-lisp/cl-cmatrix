;;;; src/runtime.lisp
;;;;
;;;; RUN-MATRIX: the real-time driver that owns the terminal session, the
;;;; optional worker pool, and the resolution of --fps / --update-delay /
;;;; --speed into the one number the tick model actually runs on.
;;;;
;;;; The loop's own sleep is fixed. CL-TTY-KIT:TICK-LOOP-RUN-REALTIME binds
;;;; :INTERVAL once, before its loop (cl-tty-kit src/tick-loop.lisp:117-118),
;;;; so pace cannot be expressed as an interval that runtime keys change.
;;;; It is expressed as a tick count instead: the loop always sleeps
;;;; +BASE-TICK-SECONDS+ and RUN-STATE-ADVANCE moves the matrix once every
;;;; %UPDATE-TICKS of those, which reproduces upstream cmatrix's
;;;; `napms(update * 10)` while leaving the delay adjustable mid-run.

(in-package #:cl-cmatrix)

(defun %assert-fps (fps)
  "Signal INVALID-FPS unless FPS is a positive real number."
  (unless (and (realp fps) (plusp fps))
    (error 'invalid-fps :fps fps))
  fps)

(defun %assert-update-delay (delay)
  "Signal INVALID-UPDATE-DELAY unless DELAY is in the upstream range."
  (unless (and (integerp delay) (<= 0 delay 10))
    (error 'invalid-update-delay :delay delay))
  delay)

(defun %update-ticks (fps update-delay speed)
  "Return how many +BASE-TICK-SECONDS+ ticks separate two matrix advances.

UPDATE-DELAY, when non-NIL, wins and is scaled by SPEED through
%UPDATE-TICKS-FOR-DELAY: it is upstream's `update`, in the same 10
millisecond units +BASE-TICK-SECONDS+ is, so at SPEED 1 a delay of 4 is 4
ticks. --speed is ours and divides the delay, so SPEED 2 runs twice as fast.
Otherwise FPS (or +DEFAULT-FPS+) is converted to the nearest whole number of
base ticks per frame.

DELIBERATE DEVIATION FROM UPSTREAM, chosen rather than overlooked: at `-u 0`
upstream busy-loops, calling `napms(0)` and redrawing as fast as the terminal
will take it. We floor at one base tick instead, capping `-u 0` at 100
frames per second. The animation is indistinguishable at that rate on a real
terminal, and the alternative is a driver loop that pins a core for as long
as the screensaver is up -- which is a worse thing for a screensaver to do
than to be imperceptibly slower than upstream's fastest setting."
  (if update-delay
      (%update-ticks-for-delay update-delay speed)
      (max 1 (round (/ 1 (* (%assert-fps (or fps +default-fps+))
                            +base-tick-seconds+))))))

(defmacro %with-matrix-executor ((executor width workers &optional (asyncp t)) &body body)
  "Bind EXECUTOR only when ASYNCP is enabled and WIDTH can amortize a worker pool.

Wide matrices get one persistent CL-CONCURRENT-KIT executor for BODY. Narrow
matrices and synchronous runs bind EXECUTOR to NIL, so their serial transition
does not pay for worker-thread creation and teardown."
  (let ((width-var (gensym "WIDTH-"))
        (workers-var (gensym "WORKERS-"))
        (async-var (gensym "ASYNC-")))
    `(let ((,width-var ,width)
           (,workers-var ,workers)
           (,async-var ,asyncp))
       (if (and ,async-var (>= ,width-var +parallel-column-threshold+))
           (with-executor (,executor
                           :size ,workers-var
                           :name "cl-cmatrix"
                           :queue-capacity (* 4 ,workers-var))
             ,@body)
           (let ((,executor nil))
             ,@body)))))

(defun run-matrix (&key (speed +default-speed+) (color +default-color+)
                        (glyphs +default-glyphs+) (bold +default-bold+)
                        (partial-bold-p nil) (no-bold-p nil)
                        (old-style-p nil) (lambda-p nil) (asyncp t)
                        (random-bold-p nil)
                        (change-glyphs-p nil)
                        (screensaverp nil) (lockp nil) message
                        (stream *standard-output*)
                        (input-stream *standard-input*) (fd +default-fd+)
                        (fps +default-fps+) update-delay
                        (workers +default-workers+)
                        (random-state (make-random-state t)))
  "Run the full-screen matrix-rain animation on STREAM until a quit event is
read from INPUT-STREAM. q, Q, Escape, and Ctrl-C are recognized by the typed
CL-TTY-KIT input poller. The terminal session is always restored after a
condition or interrupt.

COLOR, GLYPHS, BOLD, PARTIAL-BOLD-P, NO-BOLD-P, OLD-STYLE-P, LAMBDA-P,
ASYNCP, RANDOM-BOLD-P, and CHANGE-GLYPHS-P are as in MAKE-MATRIX-STATE.
OLD-STYLE-P selects upstream's old-style shift algorithm and LAMBDA-P its -m
render mode, which draws every non-head character as a lambda.

SPEED, FPS and UPDATE-DELAY together set the pace. The loop itself always
runs at +BASE-TICK-SECONDS+, polling input and rendering at that rate; the
animation advances once every %UPDATE-TICKS of those ticks. UPDATE-DELAY is
upstream's 10 millisecond delay unit (0 through 10) and, when supplied, wins
over FPS; SPEED divides it, so 2 is twice as fast. The runtime 0-9 keys reset
the delay the same way -- upstream's `update = keypress - 48`, where a larger
digit is slower.

SCREENSAVERP makes any key exit after the first frame; MESSAGE is centered
over the animation when non-NIL. WORKERS is the size of the persistent
cl-concurrent-kit executor used for wide asynchronous matrices; narrow or
synchronous matrices do not start worker threads. RANDOM-STATE seeds the
glyph and timing randomness; supply a fixed seed for reproducible runs. LOCKP
starts in lock mode, where quit keys and interactive interrupts are ignored.
Returns the final MATRIX-STATE."
  (%assert-speed speed)
  (when fps
    (%assert-fps fps))
  (when update-delay
    (%assert-update-delay update-delay))
  (check-type workers (integer 1 *))
  (let ((update-ticks (%update-ticks fps update-delay speed)))
    (multiple-value-bind (columns rows) (terminal-size fd)
      (multiple-value-bind (width height) (%terminal-dimensions columns rows)
        (%with-matrix-executor (executor width workers asyncp)
          (let ((run-state
                  (%make-initial-run-state width height speed color glyphs bold
                                            random-state input-stream
                                            :executor executor
                                            :workers workers
                                            :asyncp asyncp
                                            :partial-bold-p partial-bold-p
                                            :no-bold-p no-bold-p
                                            :old-style-p old-style-p
                                            :lambda-p lambda-p
                                            :random-bold-p random-bold-p
                                            :change-glyphs-p change-glyphs-p
                                            :screensaverp screensaverp
                                            :lockp lockp
                                            :update-ticks update-ticks
                                            :message message)))
            (with-terminal-session (out :stream stream :fd fd
                                        :raw-mode t :alternate-screen t
                                        :hide-cursor t)
              (loop
                (handler-case
                    (return
                      (tick-loop-run-realtime
                       run-state
                       #'run-state-advance
                       #'run-state-render
                       #'run-state-quitp
                       :stream out :interval +base-tick-seconds+
                       :poll (lambda (state) (run-state-poll state :fd fd))))
                  (sb-sys:interactive-interrupt ()
                    (unless (run-state-lockp run-state)
                      (return nil))))))
            (run-state-matrix run-state)))))))
