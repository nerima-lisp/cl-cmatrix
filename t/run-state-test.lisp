;;;; t/run-state-test.lisp
;;;;
;;;; RUN-STATE owns the animation's pace, which MATRIX-STATE no longer does,
;;;; so every pace test lives here rather than in state-test.lisp. Three
;;;; things are easy to get silently wrong, and each is pinned deliberately:
;;;;
;;;; The tick model. The driver loop's sleep is fixed at +BASE-TICK-SECONDS+,
;;;; so pace is a COUNT of base ticks (UPDATE-TICKS) that BASE-TICK counts
;;;; off, never an interval. RUN-STATE-DUE-P compares with >= rather than =,
;;;; which only ever matters once UPDATE-TICKS drops below a counter already
;;;; in flight -- an = would satisfy every other test in this file and freeze
;;;; the animation permanently in exactly that one case, so it is tested on
;;;; its own.
;;;;
;;;; The direction of the 0-9 keys. They set upstream's `update` delay, so a
;;;; LARGER digit is SLOWER. A test asserting only that the digit changed the
;;;; pace would accept an inversion, so the ordering is asserted too.
;;;;
;;;; What `m` does. It is upstream's -m, a LAMBDA-P render mode rather than a
;;;; glyph set -- there is no lambda charset to swap in any more -- so the
;;;; test asserts both that the flag toggles and that GLYPHS is left alone.

(in-package #:cl-cmatrix/test)

(defun %test-input-poller (events)
  (lambda (state timeout)
    (declare (ignore state timeout))
    events))

(defun %test-run-state (&key (width 5) (height 5) (events nil)
                          (speed cl-cmatrix::+default-speed+)
                          (update-ticks 1))
  "Build a RUN-STATE over a seeded matrix. SPEED and UPDATE-TICKS are the tick
model RUN-STATE now owns; the MATRIX-STATE it wraps carries no pace at all."
  (make-run-state
   :matrix (make-matrix-state
            width height
            :random-state (sb-ext:seed-random-state 24))
   :renderer (make-renderer width height)
   :input-poller (%test-input-poller events)
   :speed speed
   :update-ticks update-ticks))

(defun %press (run-state character)
  "Apply one pressed character key and return RUN-STATE-APPLY-KEY-EVENT's action."
  (run-state-apply-key-event run-state (%test-key-event :character character)))

(describe "run-state-poll"
  (it "resizes the matrix and renderer from terminal dimensions"
    (let ((run-state (%test-run-state)))
      (run-state-poll
       run-state
       :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 9 7)))
      (with-soft-assertions
        (expect (matrix-state-width (run-state-matrix run-state)) :to-equal 9)
        (expect (matrix-state-height (run-state-matrix run-state)) :to-equal 7)
        (expect (renderer-width (run-state-renderer run-state)) :to-equal 9)
        (expect (renderer-height (run-state-renderer run-state)) :to-equal 7)
        ;; Nine screen columns wide is five animated columns, not nine:
        ;; upstream draws only the even screen positions.
        (expect (length (matrix-state-columns (run-state-matrix run-state)))
                :to-equal (matrix-state-column-count 9)))))

  (it "resizes when only the terminal height changes"
    (let ((run-state (%test-run-state)))
      (run-state-poll
       run-state
       :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 5 7)))
      (with-soft-assertions
        (expect (matrix-state-width (run-state-matrix run-state)) :to-equal 5)
        (expect (matrix-state-height (run-state-matrix run-state)) :to-equal 7)
        (expect (renderer-width (run-state-renderer run-state)) :to-equal 5)
        (expect (renderer-height (run-state-renderer run-state)) :to-equal 7))))

  (it "keeps dimensions when the terminal size is unchanged"
    (let ((run-state (%test-run-state :width 8 :height 6)))
      (run-state-poll
       run-state
       :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 8 6)))
      (with-soft-assertions
        (expect (matrix-state-width (run-state-matrix run-state)) :to-equal 8)
        (expect (matrix-state-height (run-state-matrix run-state)) :to-equal 6))))

  (it "sets the quit flag after polling a quit event"
    (let ((run-state
            (%test-run-state
             :events (list (%test-key-event :character #\q)))))
      (run-state-poll
       run-state
       :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 5 5)))
      (expect (run-state-quitp run-state) :to-be-truthy)))

  (it "keeps running after polling a non-quit event"
    (let ((run-state
            (%test-run-state
             :events (list (%test-key-event :character #\x)))))
      (run-state-poll
       run-state
       :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 5 5)))
      (expect (run-state-quitp run-state) :to-be-falsy)))

  (it "hands the quit continuation the run-state and the event that ended it"
    (let ((run-state
            (%test-run-state
             :events (list (%test-key-event :character #\q))))
          (seen-event nil))
      ;; WITH-CONTINUATION-RESULT fails the test if ON-QUIT is never reached,
      ;; so routing is asserted rather than merely the flag it sets.
      (with-continuation-result (quit-state on-quit)
          (run-state-poll-cps
           run-state
           (lambda (state event) (setf seen-event event) (on-quit state))
           (lambda (state) (declare (ignore state)) :continue)
           :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 5 5)))
        (with-soft-assertions
          (expect (eq quit-state run-state) :to-be-truthy)
          (expect (quit-key-event-p seen-event) :to-be-truthy)
          (expect (run-state-quitp run-state) :to-be-truthy)))))

  (it "reaches the continue continuation when no quit event is polled"
    (let ((run-state (%test-run-state)))
      (with-continuation-result (continued on-continue)
          (run-state-poll-cps
           run-state
           (lambda (state event) (declare (ignore state event)) :quit)
           #'on-continue
           :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 5 5)))
        (with-soft-assertions
          (expect (eq continued run-state) :to-be-truthy)
          (expect (run-state-quitp run-state) :to-be-falsy)))))

  (it "returns whatever the continuation it took returned, unchanged"
    (let ((quitting
            (%test-run-state
             :events (list (%test-key-event :character #\q))))
          (continuing (%test-run-state))
          (size (lambda (fd) (declare (ignore fd)) (values 5 5))))
      (with-soft-assertions
        (expect (run-state-poll-cps
                 quitting
                 (lambda (state event) (declare (ignore state event)) :from-quit)
                 (lambda (state) (declare (ignore state)) :from-continue)
                 :terminal-size-fn size)
                :to-equal :from-quit)
        (expect (run-state-poll-cps
                 continuing
                 (lambda (state event) (declare (ignore state event)) :from-quit)
                 (lambda (state) (declare (ignore state)) :from-continue)
                 :terminal-size-fn size)
                :to-equal :from-continue)))))

(describe "%update-ticks-for-delay"
  ;; The speed-2 rows are not decoration: 3/2, 5/2 and 9/2 all land on a half,
  ;; and CL:ROUND breaks a tie to the EVEN value, so they pin 2, 2 and 4
  ;; rather than the 2, 3 and 5 a round-half-up would give.
  (it-each ((0 1 1) (1 1 1) (3 1 3) (4 1 4) (9 1 9) (10 1 10)
            (3 2 2) (4 2 2) (5 2 2) (9 2 4) (9 3 3) (9 4 2) (1 4 1))
      "an upstream delay of ~A at speed ~A is ~A base ticks"
      (delay speed ticks)
    (expect (cl-cmatrix::%update-ticks-for-delay delay speed) :to-equal ticks))

  (it "floors at one base tick, since the matrix cannot advance twice in one"
    ;; Upstream's -u 0 busy-loops; we cap it at one advance per base tick, and
    ;; a large --speed must not be able to push the count below that either.
    (with-soft-assertions
      (expect (cl-cmatrix::%update-ticks-for-delay 0 1) :to-equal 1)
      (expect (cl-cmatrix::%update-ticks-for-delay 1 100) :to-equal 1)))

  (it-property "never yields fewer than one base tick, for any delay and speed"
      ((delay (gen-integer :min 0 :max 10))
       (speed (gen-integer :min 1 :max 20)))
    (expect (>= (cl-cmatrix::%update-ticks-for-delay delay speed) 1) :to-be-truthy))

  (it-property "is monotone in the delay, so a larger upstream `update` is never faster"
      ((delay (gen-integer :min 0 :max 9)))
    ;; The direction, not just the dependence: an inverted mapping would still
    ;; satisfy every fixed row in the table above if the rows were reordered.
    (expect (<= (cl-cmatrix::%update-ticks-for-delay delay 1)
                (cl-cmatrix::%update-ticks-for-delay (1+ delay) 1))
            :to-be-truthy)))

(describe "run-state-due-p"
  (it "fires on every base tick when UPDATE-TICKS is one"
    (let ((run-state (%test-run-state :update-ticks 1)))
      (expect (loop repeat 4 collect (cl-cmatrix::run-state-due-p run-state))
              :to-equal '(t t t t))))

  (it "fires once every UPDATE-TICKS base ticks and resets the counter"
    (let ((run-state (%test-run-state :update-ticks 3)))
      (with-soft-assertions
        (expect (loop repeat 6 collect (cl-cmatrix::run-state-due-p run-state))
                :to-equal '(nil nil t nil nil t))
        ;; The counter is reset by the firing tick, not left to keep climbing.
        (expect (cl-cmatrix::run-state-base-tick run-state) :to-equal 0))))

  (it "counts the intervening ticks up rather than discarding them"
    (let ((run-state (%test-run-state :update-ticks 3)))
      (cl-cmatrix::run-state-due-p run-state)
      (cl-cmatrix::run-state-due-p run-state)
      (expect (cl-cmatrix::run-state-base-tick run-state) :to-equal 2)))

  (it "recovers when UPDATE-TICKS drops below a counter already in flight"
    ;; This is the whole reason the comparison is >= and not =. Something
    ;; other than a 0-9 key press -- a resize, a future caller -- may lower
    ;; UPDATE-TICKS without resetting BASE-TICK, parking the counter above the
    ;; new threshold. Under an = the counter would climb past it forever and
    ;; the animation would never advance again; under >= the next tick fires
    ;; and the normal cadence resumes.
    (let ((run-state (%test-run-state :update-ticks 9)))
      (loop repeat 5 do (cl-cmatrix::run-state-due-p run-state))
      ;; Non-vacuity: the counter really is parked above the new threshold.
      (expect (cl-cmatrix::run-state-base-tick run-state) :to-equal 5)
      (setf (cl-cmatrix::run-state-update-ticks run-state) 2)
      (with-soft-assertions
        (expect (cl-cmatrix::run-state-due-p run-state) :to-be-truthy)
        (expect (cl-cmatrix::run-state-base-tick run-state) :to-equal 0)
        (expect (loop repeat 4 collect (cl-cmatrix::run-state-due-p run-state))
                :to-equal '(nil t nil t))))))

(describe "run-state-advance"
  (it "replaces the matrix with the next animation state"
    (let* ((run-state (%test-run-state))
           (before (run-state-matrix run-state))
           (after (run-state-advance run-state)))
      (with-soft-assertions
        (expect (eq after run-state) :to-be-truthy)
        (expect (eq (run-state-matrix run-state) before) :to-be-falsy)
        (expect (matrix-state-tick (run-state-matrix run-state)) :to-equal 1))))

  (it "moves the matrix only on the base ticks the tick model says are due"
    (let ((run-state (%test-run-state :update-ticks 3)))
      ;; Seven base ticks at one advance every three is two advances, and the
      ;; matrix tick is what proves the skipped ticks were genuinely no-ops.
      (expect (loop repeat 7
                    collect (matrix-state-tick
                             (run-state-matrix (run-state-advance run-state))))
              :to-equal '(0 0 1 1 1 2 2))))

  (it "leaves the matrix object itself untouched on a tick that is not due"
    (let* ((run-state (%test-run-state :update-ticks 3))
           (before (run-state-matrix run-state)))
      (run-state-advance run-state)
      (with-soft-assertions
        (expect (eq (run-state-matrix run-state) before) :to-be-truthy)
        ;; Non-vacuity: the counter advanced even though the matrix did not.
        (expect (cl-cmatrix::run-state-base-tick run-state) :to-equal 1)))))

(describe "run-state-apply-key-event"
  (it "maps classic bold keys to partial, all-bold, and no-bold states"
    (let ((run-state (%test-run-state)))
      (%press run-state #\b)
      (with-soft-assertions
        (expect (matrix-state-partial-bold-p (run-state-matrix run-state)) :to-be-truthy)
        (expect (matrix-state-bold (run-state-matrix run-state)) :to-be-falsy)
        (expect (matrix-state-no-bold-p (run-state-matrix run-state)) :to-be-falsy)
        (expect (matrix-state-random-bold-p (run-state-matrix run-state)) :to-be-falsy))
      (%press run-state #\n)
      (with-soft-assertions
        (expect (matrix-state-partial-bold-p (run-state-matrix run-state)) :to-be-falsy)
        (expect (matrix-state-bold (run-state-matrix run-state)) :to-be-falsy)
        (expect (matrix-state-no-bold-p (run-state-matrix run-state)) :to-be-truthy)
        (expect (matrix-state-random-bold-p (run-state-matrix run-state)) :to-be-falsy))
      (%press run-state #\B)
      (with-soft-assertions
        (expect (matrix-state-bold (run-state-matrix run-state)) :to-be-truthy)
        (expect (matrix-state-partial-bold-p (run-state-matrix run-state)) :to-be-falsy)
        (expect (matrix-state-no-bold-p (run-state-matrix run-state)) :to-be-falsy))))

  (it "toggles asynchronous timing and glyph repainting"
    (let ((run-state (%test-run-state)))
      ;; ASYNCP defaults on, CHANGE-GLYPHS-P off, so each key is observed
      ;; moving its flag in both directions.
      (%press run-state #\a)
      (expect (matrix-state-asyncp (run-state-matrix run-state)) :to-be-falsy)
      (%press run-state #\a)
      (expect (matrix-state-asyncp (run-state-matrix run-state)) :to-be-truthy)
      (%press run-state #\k)
      (expect (matrix-state-change-glyphs-p (run-state-matrix run-state)) :to-be-truthy)
      (%press run-state #\k)
      (expect (matrix-state-change-glyphs-p (run-state-matrix run-state)) :to-be-falsy)))

  (it "toggles the lambda RENDER MODE without touching the glyph set"
    ;; Upstream's -m draws a lambda in place of every non-head character; it
    ;; is not a charset, and +LAMBDA-GLYPHS+ no longer exists. So `m` must
    ;; move LAMBDA-P and leave GLYPHS exactly as it found them -- a
    ;; reintroduced charset swap would fail here rather than pass quietly.
    (let* ((run-state (%test-run-state))
           (before (run-state-matrix run-state)))
      (expect (matrix-state-lambda-p before) :to-be-falsy)
      (%press run-state #\m)
      (let ((after (run-state-matrix run-state)))
        (with-soft-assertions
          (expect (matrix-state-lambda-p after) :to-be-truthy)
          (expect (eq (matrix-state-glyphs after) +default-glyphs+) :to-be-truthy)
          ;; Nothing about where the animation is may be reset by the toggle,
          ;; and sharing the column vector outright is the strongest form of
          ;; that: not merely equal columns, the same ones.
          (expect (eq (matrix-state-columns after) (matrix-state-columns before))
                  :to-be-truthy)
          (expect (matrix-state-tick after) :to-equal (matrix-state-tick before))))
      (%press run-state #\m)
      (expect (matrix-state-lambda-p (run-state-matrix run-state)) :to-be-falsy)))

  (it-each ((#\! :red) (#\@ :green) (#\# :yellow) (#\$ :blue) (#\% :magenta)
            (#\^ :cyan) (#\& :white) (#\r :rainbow) (#\) :rainbow))
      "maps the color key ~S to ~S"
      (character color)
    (let ((run-state (%test-run-state)))
      (%press run-state character)
      (expect (matrix-state-color (run-state-matrix run-state)) :to-equal color)))

  (it "binds every character in +RUN-STATE-COLOR-KEYS+ and nothing else to a color"
    ;; Guards the table itself: a key added to the source without a case here
    ;; would otherwise go untested.
    (expect (mapcar #'car cl-cmatrix::+run-state-color-keys+)
            :to-equal '(#\! #\@ #\# #\$ #\% #\^ #\& #\r #\))))

  (it-each ((#\0 1) (#\1 1) (#\4 4) (#\9 9))
      "sets the update delay from key ~S to ~A base ticks"
      (character ticks)
    (let ((run-state (%test-run-state :update-ticks 5)))
      (expect (%press run-state character) :to-equal :changed)
      (expect (cl-cmatrix::run-state-update-ticks run-state) :to-equal ticks)))

  (it "makes a larger digit slower, which is the direction upstream's `update` runs"
    ;; `update = keypress - 48` and the delay is then slept on, so 0 is the
    ;; fastest setting and 9 the slowest. An inverted mapping would still
    ;; change the pace on every key press.
    (let ((run-state (%test-run-state)))
      (expect (loop for character across "0123456789"
                    collect (progn (%press run-state character)
                                   (cl-cmatrix::run-state-update-ticks run-state)))
              :to-equal '(1 1 2 3 4 5 6 7 8 9))))

  (it "resets the base tick so a new pace takes effect from this tick"
    (let ((run-state (%test-run-state :update-ticks 9)))
      (loop repeat 4 do (cl-cmatrix::run-state-due-p run-state))
      ;; Non-vacuity: there is a non-zero counter for the key press to clear.
      (expect (cl-cmatrix::run-state-base-tick run-state) :to-equal 4)
      (%press run-state #\2)
      (with-soft-assertions
        (expect (cl-cmatrix::run-state-base-tick run-state) :to-equal 0)
        (expect (cl-cmatrix::run-state-update-ticks run-state) :to-equal 2))))

  (it "re-scales the new delay by the retained --speed rather than ignoring it"
    ;; SPEED is kept on the RUN-STATE precisely so a runtime 0-9 key can be
    ;; divided by it; at speed 2 the same key must land on half the ticks.
    (let ((run-state (%test-run-state :speed 2 :update-ticks 1)))
      (%press run-state #\4)
      (expect (cl-cmatrix::run-state-update-ticks run-state) :to-equal 2)
      (%press run-state #\9)
      (expect (cl-cmatrix::run-state-update-ticks run-state) :to-equal 4)))

  (it "locks on L and ignores quit keys while preserving a lock message"
    (let ((run-state (%test-run-state)))
      (with-soft-assertions
        (expect (%press run-state #\L) :to-equal :changed)
        (expect (run-state-lockp run-state) :to-be-truthy)
        (expect (run-state-message run-state) :to-equal "Computer locked.")
        (expect (%press run-state #\q) :to-be-falsy)
        (expect (run-state-quitp run-state) :to-be-falsy))))

  (it "pauses and resumes animation with p and P"
    (let ((run-state (%test-run-state)))
      (%press run-state #\p)
      (expect (run-state-pausedp run-state) :to-be-truthy)
      (let ((paused-matrix (run-state-matrix run-state)))
        (run-state-advance run-state)
        (with-soft-assertions
          (expect (eq (run-state-matrix run-state) paused-matrix) :to-be-truthy)
          (expect (matrix-state-tick paused-matrix) :to-equal 0)))
      (%press run-state #\P)
      (expect (run-state-pausedp run-state) :to-be-falsy)
      (run-state-advance run-state)
      (expect (matrix-state-tick (run-state-matrix run-state)) :to-equal 1)))

  (it "exits immediately when a key is polled in screensaver mode"
    (let ((run-state (%test-run-state)))
      (setf (run-state-screensaverp run-state) t)
      (with-soft-assertions
        (expect (%press run-state #\x) :to-equal :quit)
        (expect (run-state-quitp run-state) :to-be-truthy))))

  (it "ignores special and unknown non-quit key events"
    (let ((run-state (%test-run-state)))
      (with-soft-assertions
        (expect (run-state-apply-key-event run-state (%test-key-event :special :enter))
                :to-be-falsy)
        (expect (%press run-state #\x) :to-be-falsy)
        (expect (%press run-state #\z) :to-be-falsy)))))

(describe "run-state-render"
  (it "renders through the context-owned style cache"
    (let ((run-state (%test-run-state)))
      (run-state-render run-state)
      (expect (hash-table-p
               (render-context-style-cache
                (run-state-render-context run-state)))
              :to-be-truthy))))

(describe "run-state construction"
  (it "builds an input poller and a render context"
    (let ((run-state
            (cl-cmatrix::%make-initial-run-state
             5 4 1 :green +default-glyphs+ nil
             (sb-ext:seed-random-state 42)
             (make-string-input-stream ""))))
      (with-soft-assertions
        (expect (functionp (run-state-input-poller run-state)) :to-be-truthy)
        (expect (typep (run-state-render-context run-state) 'render-context)
                :to-be-truthy))))

  (it "initializes lock mode with the default message"
    (let ((run-state
            (cl-cmatrix::%make-initial-run-state
             5 4 1 :green +default-glyphs+ nil
             (sb-ext:seed-random-state 44)
             (make-string-input-stream "")
             :lockp t)))
      (with-soft-assertions
        (expect (run-state-lockp run-state) :to-be-truthy)
        (expect (run-state-message run-state) :to-equal "Computer locked."))))

  (it "starts the tick model at the resolved UPDATE-TICKS with an un-advanced counter"
    ;; RUN-MATRIX resolves --fps against --update-delay and hands the winner
    ;; down already converted, so this constructor stores it rather than
    ;; deriving it a second time.
    (let ((run-state
            (cl-cmatrix::%make-initial-run-state
             5 4 2 :green +default-glyphs+ nil
             (sb-ext:seed-random-state 45)
             (make-string-input-stream "")
             :update-ticks 7)))
      (with-soft-assertions
        (expect (cl-cmatrix::run-state-update-ticks run-state) :to-equal 7)
        (expect (cl-cmatrix::run-state-base-tick run-state) :to-equal 0)
        ;; SPEED is retained only so a runtime 0-9 key can be re-scaled by it.
        (expect (cl-cmatrix::run-state-speed run-state) :to-equal 2))))

  (it "retains SPEED so a runtime digit key is scaled by it after construction"
    (let ((run-state
            (cl-cmatrix::%make-initial-run-state
             5 4 2 :green +default-glyphs+ nil
             (sb-ext:seed-random-state 46)
             (make-string-input-stream "")
             :update-ticks 7)))
      (%press run-state #\9)
      (expect (cl-cmatrix::run-state-update-ticks run-state) :to-equal 4)))

  (it "carries initial lambda mode as a render flag, leaving GLYPHS the base set"
    ;; The -m command line flag and the `m` key now agree: both move LAMBDA-P
    ;; and neither substitutes a charset, so a state built with :LAMBDA-P T
    ;; still draws from the glyph set it was handed, and `m` turns the mode
    ;; back off rather than restoring some remembered base set.
    (let ((run-state
            (cl-cmatrix::%make-initial-run-state
             5 4 1 :green +default-glyphs+ nil
             (sb-ext:seed-random-state 43)
             (make-string-input-stream "")
             :lambda-p t)))
      (with-soft-assertions
        (expect (matrix-state-lambda-p (run-state-matrix run-state)) :to-be-truthy)
        (expect (eq (matrix-state-glyphs (run-state-matrix run-state)) +default-glyphs+)
                :to-be-truthy))
      (%press run-state #\m)
      (with-soft-assertions
        (expect (matrix-state-lambda-p (run-state-matrix run-state)) :to-be-falsy)
        (expect (eq (matrix-state-glyphs (run-state-matrix run-state)) +default-glyphs+)
                :to-be-truthy))))

  (it "keeps a non-default charset when lambda mode is on, since the two are orthogonal"
    (let ((run-state
            (cl-cmatrix::%make-initial-run-state
             5 4 1 :green +katakana-glyphs+ nil
             (sb-ext:seed-random-state 47)
             (make-string-input-stream "")
             :lambda-p t)))
      (with-soft-assertions
        (expect (matrix-state-lambda-p (run-state-matrix run-state)) :to-be-truthy)
        (expect (eq (matrix-state-glyphs (run-state-matrix run-state)) +katakana-glyphs+)
                :to-be-truthy))))

  (it "returns supplied terminal dimensions"
    (multiple-value-bind (width height)
        (cl-cmatrix::%terminal-dimensions 12 8)
      (with-soft-assertions
        (expect width :to-equal 12)
        (expect height :to-equal 8))))

  (it "falls back to the classic terminal dimensions when unavailable"
    (multiple-value-bind (width height)
        (cl-cmatrix::%terminal-dimensions nil nil)
      (with-soft-assertions
        (expect width :to-equal 80)
        (expect height :to-equal 24)))))
