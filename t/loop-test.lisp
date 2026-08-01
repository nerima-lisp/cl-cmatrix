;;;; t/loop-test.lisp
;;;;
;;;; RUN-MATRIX itself takes over a real terminal (raw mode, alternate
;;;; screen) and is not exercised here -- there is no real tty in CI. What is
;;;; tested is everything RUN-MATRIX is built from: quit-key detection
;;;; against any character stream, and RUN-STATE-ADVANCE's resize/quit
;;;; wiring against a stubbed terminal-size function and a
;;;; STRING-INPUT-STREAM, exactly the injection pattern MATRIX-STATE uses
;;;; for its RANDOM-STATE.

(in-package #:cl-cmatrix/test)

(describe "quit-key-character-p"
  (it "matches q, Q, and Escape"
    (with-soft-assertions
      (expect (quit-key-character-p #\q) :to-be-truthy)
      (expect (quit-key-character-p #\Q) :to-be-truthy)
      (expect (quit-key-character-p #\Escape) :to-be-truthy)))

  (it "matches the raw Ctrl-C byte (character code 3)"
    (expect (quit-key-character-p (code-char 3)) :to-be-truthy))

  (it "does not match an ordinary character"
    (with-soft-assertions
      (expect (not (quit-key-character-p #\a)) :to-be-truthy)
      (expect (not (quit-key-character-p #\Space)) :to-be-truthy))))

(describe "poll-quit-key"
  (it "returns true when a quit key is buffered on the stream"
    (with-input-from-string (stream "xyq")
      (expect (poll-quit-key stream) :to-be-truthy)))

  (it "returns false, and leaves nothing unread, when no quit key is buffered"
    (with-input-from-string (stream "xyz")
      (with-soft-assertions
        (expect (not (poll-quit-key stream)) :to-be-truthy)
        (expect (not (listen stream)) :to-be-truthy))))

  (it "returns false on an empty stream"
    (with-input-from-string (stream "")
      (expect (not (poll-quit-key stream)) :to-be-truthy))))

(describe "run-state-advance"
  (it "reflows the matrix and renderer when the stubbed terminal size changes"
    (let ((run-state (make-run-state
                       :matrix (make-matrix-state 5 5 :random-state (sb-ext:seed-random-state 40))
                       :renderer (make-renderer 5 5)
                       :quitp nil
                       :input-stream (make-string-input-stream ""))))
      (run-state-advance run-state
                          :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 9 7)))
      (with-soft-assertions
        (expect (= (matrix-state-width (run-state-matrix run-state)) 9) :to-be-truthy)
        (expect (= (matrix-state-height (run-state-matrix run-state)) 7) :to-be-truthy)
        (expect (= (renderer-width (run-state-renderer run-state)) 9) :to-be-truthy)
        (expect (= (renderer-height (run-state-renderer run-state)) 7) :to-be-truthy))))

  (it "does not resize when the stubbed terminal size is unchanged"
    (let ((run-state (make-run-state
                       :matrix (make-matrix-state 5 5 :random-state (sb-ext:seed-random-state 41))
                       :renderer (make-renderer 5 5)
                       :quitp nil
                       :input-stream (make-string-input-stream ""))))
      (run-state-advance run-state
                          :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 5 5)))
      (with-soft-assertions
        (expect (= (matrix-state-width (run-state-matrix run-state)) 5) :to-be-truthy)
        (expect (= (matrix-state-height (run-state-matrix run-state)) 5) :to-be-truthy))))

  (it "does not resize when the stubbed terminal size is unavailable"
    (let ((run-state (make-run-state
                       :matrix (make-matrix-state 5 5 :random-state (sb-ext:seed-random-state 42))
                       :renderer (make-renderer 5 5)
                       :quitp nil
                       :input-stream (make-string-input-stream ""))))
      (run-state-advance run-state
                          :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values nil nil)))
      (with-soft-assertions
        (expect (= (matrix-state-width (run-state-matrix run-state)) 5) :to-be-truthy)
        (expect (= (matrix-state-height (run-state-matrix run-state)) 5) :to-be-truthy))))

  (it "sets QUITP once a quit key is read from INPUT-STREAM"
    (let ((run-state (make-run-state
                       :matrix (make-matrix-state 5 5 :random-state (sb-ext:seed-random-state 43))
                       :renderer (make-renderer 5 5)
                       :quitp nil
                       :input-stream (make-string-input-stream "q"))))
      (run-state-advance run-state
                          :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 5 5)))
      (expect (run-state-quitp run-state) :to-be-truthy)))

  (it "leaves QUITP false when no quit key is buffered"
    (let ((run-state (make-run-state
                       :matrix (make-matrix-state 5 5 :random-state (sb-ext:seed-random-state 46))
                       :renderer (make-renderer 5 5)
                       :quitp nil
                       :input-stream (make-string-input-stream ""))))
      (run-state-advance run-state
                          :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 5 5)))
      (expect (not (run-state-quitp run-state)) :to-be-truthy)))

  (it "advances the underlying matrix's tick counter by one"
    (let ((run-state (make-run-state
                       :matrix (make-matrix-state 5 5 :random-state (sb-ext:seed-random-state 44))
                       :renderer (make-renderer 5 5)
                       :quitp nil
                       :input-stream (make-string-input-stream ""))))
      (run-state-advance run-state
                          :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 5 5)))
      (expect (= (matrix-state-tick (run-state-matrix run-state)) 1) :to-be-truthy))))
