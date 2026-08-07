(in-package #:cl-cmatrix/test)

(defun %test-key-event (type code &optional (kind :press))
  (make-key-event :type type :code code :kind kind))

(describe "quit-key-event-p"
  (it "recognizes typed quit events"
    (with-soft-assertions
      (expect (quit-key-event-p (%test-key-event :character #\q))
              :to-be-truthy)
      (expect (quit-key-event-p (%test-key-event :character #\Q))
              :to-be-truthy)
      (expect (quit-key-event-p
               (%test-key-event :character (code-char 3)))
              :to-be-truthy)
      (expect (quit-key-event-p (%test-key-event :special :escape))
              :to-be-truthy)))

  (it "rejects non-quit and non-pressed events"
    (with-soft-assertions
      (expect (not (quit-key-event-p nil)) :to-be-truthy)
      (expect (not (quit-key-event-p (%test-key-event :character #\a)))
              :to-be-truthy)
      (expect (not (quit-key-event-p (%test-key-event :character #\q :repeat)))
              :to-be-truthy)
      (expect (not (quit-key-event-p (%test-key-event :character #\q :release)))
              :to-be-truthy)
      (expect (not (cl-cmatrix::%quit-character-p 3))
              :to-be-truthy)
      (expect (not (quit-key-event-p (%test-key-event :special :enter)))
              :to-be-truthy))))

(describe "poll-quit-events"
  (it "finds a quit event in a decoded event batch"
    (expect (poll-quit-events
             (list (%test-key-event :character #\a)
                   (%test-key-event :special :escape)))
            :to-be-truthy))

  (it "returns false when an event batch has no quit event"
    (expect (poll-quit-events
             (list (%test-key-event :character #\a)
                   (%test-key-event :special :enter)))
            :to-be-falsy))

  (it "routes quit and continue branches through CPS callbacks"
    (with-continuation-result (result on-quit calledp)
      (poll-quit-events-cps
       (list (%test-key-event :character #\q))
       #'on-quit
       (lambda () :continue))
      (expect calledp :to-be-truthy)
      (expect (key-event-code result) :to-equal #\q)))

  (it "routes non-quit batches through the continuation branch"
    (with-continuation-result (result on-continue calledp)
      (poll-quit-events-cps
       (list (%test-key-event :character #\a))
       (lambda (event) (declare (ignore event)) :quit)
       #'on-continue)
      (expect calledp :to-be-truthy)
      (expect result :to-be-falsy)
      (expect
       (poll-quit-events-cps
        (list (%test-key-event :character #\a))
        (lambda (event) (declare (ignore event)) :quit)
        (lambda () :continue))
       :to-equal :continue)))

  (it "recognizes quit events from the stream poller"
    (let* ((state (make-matrix-state
                   4 3
                   :random-state (sb-ext:seed-random-state 12)))
           (renderer (make-renderer 4 3))
           (run-state (make-run-state
                       :matrix state
                       :renderer renderer
                       :input-poller
                       (make-stream-input-poller
                        (make-string-input-stream "q")))))
      (run-state-poll
       run-state
       :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 4 3)))
      (expect (run-state-quitp run-state) :to-be-truthy))))
