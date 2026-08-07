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

(describe "run-state-advance"
  (it "replaces the matrix with the next animation state"
    (let* ((run-state (%test-run-state))
           (before (run-state-matrix run-state))
           (after (run-state-advance run-state)))
      (expect (eq after run-state) :to-be-truthy)
      (expect (not (eq (run-state-matrix run-state) before)) :to-be-truthy)
      (expect (matrix-state-tick (run-state-matrix run-state)) :to-equal 1))))

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

  (it "reports terminal dimensions"
    (multiple-value-bind (width height)
        (cl-cmatrix::%terminal-dimensions
         0
         (lambda (fd) (declare (ignore fd)) (values 12 8)))
      (expect width :to-equal 12)
      (expect height :to-equal 8))))
