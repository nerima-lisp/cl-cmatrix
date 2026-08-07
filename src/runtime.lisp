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

(defun %tick-interval (fps update-delay)
  "Return the animation interval for FPS or an upstream UPDATE-DELAY."
  (if update-delay
      (/ (float update-delay 1.0d0) 100.0d0)
      (/ 1 (%assert-fps (or fps +default-fps+)))))

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
                        (old-style-p nil) (asyncp t) (random-bold-p nil)
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

SPEED, COLOR, GLYPHS, BOLD, PARTIAL-BOLD-P, NO-BOLD-P, OLD-STYLE-P, ASYNCP,
RANDOM-BOLD-P, and CHANGE-GLYPHS-P are as in MAKE-MATRIX-STATE. OLD-STYLE-P
uses a fixed-height visible buffer and the upstream old-style shift algorithm.
SCREENSAVERP makes any key exit after the first frame; MESSAGE is centered over
the animation when non-NIL. FPS is the target tick rate unless UPDATE-DELAY is
non-NIL, in which case it uses upstream's 10ms delay units (including zero).
WORKERS is the size of the persistent cl-concurrent-kit executor used for wide
asynchronous matrices; narrow or synchronous matrices do not start worker
threads. RANDOM-STATE seeds the fall timing and glyph randomness; supply a
fixed seed for reproducible runs. LOCKP starts in lock mode, where quit keys
and interactive interrupts are ignored. Returns the final MATRIX-STATE."
  (when fps
    (%assert-fps fps))
  (when update-delay
    (%assert-update-delay update-delay))
  (check-type workers (integer 1 *))
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
                                          :random-bold-p random-bold-p
                                          :change-glyphs-p change-glyphs-p
                                          :screensaverp screensaverp
                                          :lockp lockp
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
                     :stream out :interval (%tick-interval fps update-delay)
                     :poll (lambda (state) (run-state-poll state :fd fd))))
                (sb-sys:interactive-interrupt ()
                  (unless (run-state-lockp run-state)
                    (return nil))))))
          (run-state-matrix run-state))))))
