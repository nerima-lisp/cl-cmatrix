(in-package #:cl-cmatrix/test)

(defun %test-input-poller (events)
  (lambda (state timeout)
    (declare (ignore state timeout))
    events))

(defun %test-run-state (&key (width 5) (height 5) (events nil))
  (make-run-state
   :matrix (make-matrix-state
            width height
            :random-state (sb-ext:seed-random-state 24))
   :renderer (make-renderer width height)
   :input-poller (%test-input-poller events)))

(describe "run-state-poll"
  (it "resizes the matrix and renderer from terminal dimensions"
    (let ((run-state (%test-run-state)))
      (run-state-poll
       run-state
       :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 9 7)))
      (expect (matrix-state-width (run-state-matrix run-state)) :to-equal 9)
      (expect (matrix-state-height (run-state-matrix run-state)) :to-equal 7)
      (expect (renderer-width (run-state-renderer run-state)) :to-equal 9)
      (expect (renderer-height (run-state-renderer run-state)) :to-equal 7)))

  (it "resizes when only the terminal height changes"
    (let ((run-state (%test-run-state)))
      (run-state-poll
       run-state
       :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 5 7)))
      (expect (matrix-state-width (run-state-matrix run-state)) :to-equal 5)
      (expect (matrix-state-height (run-state-matrix run-state)) :to-equal 7)
      (expect (renderer-width (run-state-renderer run-state)) :to-equal 5)
      (expect (renderer-height (run-state-renderer run-state)) :to-equal 7)))

  (it "keeps dimensions when the terminal size is unchanged"
    (let ((run-state (%test-run-state :width 8 :height 6)))
      (run-state-poll
       run-state
       :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 8 6)))
      (expect (matrix-state-width (run-state-matrix run-state)) :to-equal 8)
      (expect (matrix-state-height (run-state-matrix run-state)) :to-equal 6)))

  (it "sets the quit flag after polling a quit event"
    (let ((run-state
            (%test-run-state
             :events (list (%test-key-event :character #\q)))))
      (run-state-poll
       run-state
       :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 5 5)))
      (expect (run-state-quitp run-state) :to-be-truthy))))

  (it "keeps running after polling a non-quit event"
    (let ((run-state
            (%test-run-state
             :events (list (%test-key-event :character #\x)))))
      (run-state-poll
       run-state
       :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 5 5)))
      (expect (not (run-state-quitp run-state)) :to-be-truthy)))

  (it "returns the quit continuation result and marks state through CPS"
    (let ((run-state
            (%test-run-state
             :events (list (%test-key-event :character #\q))))
          (seen-event nil))
      (let ((result
              (run-state-poll-cps
               run-state
               (lambda (state event)
                 (setf seen-event event)
                 (list :quit state))
               (lambda (state) (list :continue state))
               :terminal-size-fn
               (lambda (fd) (declare (ignore fd)) (values 5 5)))))
        (expect (eq (first result) :quit) :to-be-truthy)
        (expect seen-event :to-be-truthy)
        (expect (run-state-quitp run-state) :to-be-truthy))))

  (it "returns the continue continuation result when no quit event is polled"
    (let ((run-state (%test-run-state)))
      (let ((result
              (run-state-poll-cps
               run-state
               (lambda (state event)
                 (declare (ignore state event))
                 :quit)
               (lambda (state) (list :continue state))
               :terminal-size-fn
               (lambda (fd) (declare (ignore fd)) (values 5 5)))))
        (expect (eq (first result) :continue) :to-be-truthy)
        (expect (not (run-state-quitp run-state)) :to-be-truthy))))

(describe "run-state-advance"
  (it "replaces the matrix with the next animation state"
    (let* ((run-state (%test-run-state))
           (before (run-state-matrix run-state))
           (after (run-state-advance run-state)))
      (expect (eq after run-state) :to-be-truthy)
      (expect (not (eq (run-state-matrix run-state) before)) :to-be-truthy)
      (expect (matrix-state-tick (run-state-matrix run-state)) :to-equal 1))))

(describe "run-state-apply-key-event"
  (it "maps classic bold keys to partial, all-bold, and no-bold states"
    (let ((run-state (%test-run-state)))
      (run-state-apply-key-event run-state (%test-key-event :character #\b))
      (expect (matrix-state-partial-bold-p (run-state-matrix run-state)) :to-be-truthy)
      (expect (not (matrix-state-bold (run-state-matrix run-state))) :to-be-truthy)
      (expect (not (matrix-state-no-bold-p (run-state-matrix run-state))) :to-be-truthy)
      (expect (not (matrix-state-random-bold-p (run-state-matrix run-state)))
              :to-be-truthy)
      (run-state-apply-key-event run-state (%test-key-event :character #\n))
      (expect (not (matrix-state-partial-bold-p (run-state-matrix run-state))) :to-be-truthy)
      (expect (not (matrix-state-bold (run-state-matrix run-state))) :to-be-truthy)
      (expect (matrix-state-no-bold-p (run-state-matrix run-state)) :to-be-truthy)
      (expect (not (matrix-state-random-bold-p (run-state-matrix run-state)))
              :to-be-truthy)
      (run-state-apply-key-event run-state (%test-key-event :character #\B))
      (expect (matrix-state-bold (run-state-matrix run-state)) :to-be-truthy)
      (expect (not (matrix-state-partial-bold-p (run-state-matrix run-state))) :to-be-truthy)
      (expect (not (matrix-state-no-bold-p (run-state-matrix run-state))) :to-be-truthy)))

  (it "toggles asynchronous timing and glyph repainting"
    (let ((run-state (%test-run-state)))
      (run-state-apply-key-event run-state (%test-key-event :character #\a))
      (expect (not (matrix-state-asyncp (run-state-matrix run-state))) :to-be-truthy)
      (run-state-apply-key-event run-state (%test-key-event :character #\a))
      (expect (matrix-state-asyncp (run-state-matrix run-state)) :to-be-truthy)
      (run-state-apply-key-event run-state (%test-key-event :character #\k))
      (expect (matrix-state-change-glyphs-p (run-state-matrix run-state))
              :to-be-truthy)
      (run-state-apply-key-event run-state (%test-key-event :character #\k))
      (expect (not (matrix-state-change-glyphs-p (run-state-matrix run-state)))
              :to-be-truthy)))

  (it "maps official rainbow and speed keys"
    (let ((run-state (%test-run-state)))
      (run-state-apply-key-event run-state (%test-key-event :character #\r))
      (expect (eq (matrix-state-color (run-state-matrix run-state)) :rainbow)
              :to-be-truthy)
      (run-state-apply-key-event run-state (%test-key-event :character #\9))
      (expect (= (matrix-state-speed (run-state-matrix run-state)) 4.0d0)
              :to-be-truthy)))

  (it "toggles lambda glyphs without resetting the column positions"
    (let* ((run-state (%test-run-state))
           (before (run-state-matrix run-state)))
      (run-state-apply-key-event run-state (%test-key-event :character #\m))
      (let ((matrix (run-state-matrix run-state)))
        (expect (eq (matrix-state-glyphs matrix) +lambda-glyphs+) :to-be-truthy)
        (expect (equal (mapcar #'column-head (coerce (matrix-state-columns before) 'list))
                       (mapcar #'column-head (coerce (matrix-state-columns matrix) 'list)))
                :to-be-truthy)
        (expect (every (lambda (column)
                         (every (lambda (glyph)
                                  (find glyph +lambda-glyphs+ :test #'char=))
                                (column-glyphs column)))
                       (coerce (matrix-state-columns matrix) 'list))
                :to-be-truthy))
      (run-state-apply-key-event run-state (%test-key-event :character #\m))
      (expect (eq (matrix-state-glyphs (run-state-matrix run-state))
                  +default-glyphs+)
              :to-be-truthy)))

  (it "locks on L and ignores quit keys while preserving a lock message"
    (let ((run-state (%test-run-state)))
      (expect (eq (run-state-apply-key-event
                   run-state
                   (%test-key-event :character #\L))
                  :changed)
              :to-be-truthy)
      (expect (run-state-lockp run-state) :to-be-truthy)
      (expect (string= (run-state-message run-state) "Computer locked.")
              :to-be-truthy)
      (expect (null (run-state-apply-key-event
                     run-state
                     (%test-key-event :character #\q)))
              :to-be-truthy)
      (expect (not (run-state-quitp run-state)) :to-be-truthy)))

  (it "pauses and resumes animation with p and P"
    (let ((run-state (%test-run-state)))
      (run-state-apply-key-event run-state (%test-key-event :character #\p))
      (expect (run-state-pausedp run-state) :to-be-truthy)
      (let ((paused-matrix (run-state-matrix run-state)))
        (run-state-advance run-state)
        (expect (eq (run-state-matrix run-state) paused-matrix) :to-be-truthy)
        (expect (= (matrix-state-tick paused-matrix) 0) :to-be-truthy))
      (run-state-apply-key-event run-state (%test-key-event :character #\P))
      (expect (not (run-state-pausedp run-state)) :to-be-truthy)
      (run-state-advance run-state)
      (expect (= (matrix-state-tick (run-state-matrix run-state)) 1)
              :to-be-truthy))))

  (it "exits immediately when a key is polled in screensaver mode"
    (let ((run-state (%test-run-state)))
      (setf (cl-cmatrix::run-state-screensaverp run-state) t)
      (expect (eq (run-state-apply-key-event
                   run-state
                   (%test-key-event :character #\x))
                  :quit)
              :to-be-truthy)
      (expect (run-state-quitp run-state) :to-be-truthy)))

  (it "ignores special and unknown non-quit key events"
    (let ((run-state (%test-run-state)))
      (expect (not (run-state-apply-key-event
                    run-state
                    (%test-key-event :special :enter)))
              :to-be-truthy)
      (expect (not (run-state-apply-key-event
                    run-state
                    (%test-key-event :character #\x)))
              :to-be-truthy)))

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
      (expect (functionp (run-state-input-poller run-state))
              :to-be-truthy)
      (expect (typep (run-state-render-context run-state)
                     'render-context)
              :to-be-truthy)))

  (it "initializes lock mode with the default message"
    (let ((run-state
            (cl-cmatrix::%make-initial-run-state
             5 4 1 :green +default-glyphs+ nil
             (sb-ext:seed-random-state 44)
             (make-string-input-stream "")
             :lockp t)))
      (expect (run-state-lockp run-state) :to-be-truthy)
      (expect (string= (run-state-message run-state) "Computer locked.")
              :to-be-truthy)))

  (it "normalizes the base glyph set for initial lambda mode"
    (let ((run-state
            (cl-cmatrix::%make-initial-run-state
             5 4 1 :green +lambda-glyphs+ nil
             (sb-ext:seed-random-state 43)
             (make-string-input-stream ""))))
      (expect (eq (matrix-state-glyphs (run-state-matrix run-state))
                  +lambda-glyphs+)
              :to-be-truthy)
      (expect (eq (cl-cmatrix::run-state-base-glyphs run-state)
                  +default-glyphs+)
              :to-be-truthy)
      (run-state-apply-key-event run-state (%test-key-event :character #\m))
      (expect (eq (matrix-state-glyphs (run-state-matrix run-state))
                  +default-glyphs+)
              :to-be-truthy)))

  (it "returns supplied terminal dimensions"
    (multiple-value-bind (width height)
        (cl-cmatrix::%terminal-dimensions
         12 8)
      (expect width :to-equal 12)
      (expect height :to-equal 8)))

  (it "falls back to the classic terminal dimensions when unavailable"
    (multiple-value-bind (width height)
        (cl-cmatrix::%terminal-dimensions nil nil)
      (expect width :to-equal 80)
      (expect height :to-equal 24))))
