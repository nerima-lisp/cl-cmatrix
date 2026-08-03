;;;; t/loop-test.lisp
;;;;
;;;; RUN-MATRIX itself takes over a real terminal (raw mode, alternate
;;;; screen) and is not exercised here -- there is no real tty in CI. What is
;;;; tested is everything RUN-MATRIX is built from: quit-key detection
;;;; against any character stream, RUN-STATE-POLL's resize/quit wiring
;;;; against a stubbed terminal-size function and a STRING-INPUT-STREAM
;;;; (exactly the injection pattern MATRIX-STATE uses for its RANDOM-STATE),
;;;; and RUN-STATE-ADVANCE's own tick-only step.

(in-package #:cl-cmatrix/test)

(defvar *run-state* nil
  "The RUN-STATE under test in the \"run-state-poll\"/\"run-state-advance\"
suites below, rebuilt fresh by each BEFORE-EACH so no case can see another's
mutations.")

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

(describe "poll-quit-key-cps"
  (it "calls ON-QUIT with the offending character when one is buffered"
    (with-continuation-result (character on-quit calledp)
        (with-input-from-string (stream "xyq")
          (poll-quit-key-cps stream #'on-quit (lambda () :not-found)))
      (with-soft-assertions
        (expect calledp :to-be-truthy)
        (expect (char= character #\q) :to-be-truthy))))

  (it "calls ON-CONTINUE, and never ON-QUIT, when no quit key is buffered"
    (with-continuation-result (result on-continue calledp)
        (with-input-from-string (stream "xyz")
          (poll-quit-key-cps stream
                              (lambda (character)
                                (declare (ignore character))
                                (error "ON-QUIT must not run when no quit key is buffered"))
                              #'on-continue))
      (declare (ignore result))
      (expect calledp :to-be-truthy))))

(describe "run-state-poll"
  (describe "terminal resize wiring"
    (before-each
      (setf *run-state*
            (make-run-state
             :matrix (make-matrix-state 5 5 :random-state (sb-ext:seed-random-state 40))
             :renderer (make-renderer 5 5)
             :quitp nil
             :input-stream (make-string-input-stream ""))))

    (it-each ((9 7 9 7)
              (5 5 5 5)
              (nil nil 5 5))
        "reflows to ~A x ~A when the stubbed terminal reports it, else stays ~A x ~A"
        (stub-columns stub-rows expected-width expected-height)
      (run-state-poll *run-state*
                       :terminal-size-fn (lambda (fd)
                                            (declare (ignore fd))
                                            (values stub-columns stub-rows)))
      (with-soft-assertions
        (expect (= (matrix-state-width (run-state-matrix *run-state*)) expected-width)
                :to-be-truthy)
        (expect (= (matrix-state-height (run-state-matrix *run-state*)) expected-height)
                :to-be-truthy)
        (expect (= (renderer-width (run-state-renderer *run-state*)) expected-width)
                :to-be-truthy)
        (expect (= (renderer-height (run-state-renderer *run-state*)) expected-height)
                :to-be-truthy))))

  (describe "FD/TERMINAL-SIZE-FN defaults"
    (before-each
      (setf *run-state*
            (make-run-state
             :matrix (make-matrix-state 5 5 :random-state (sb-ext:seed-random-state 41))
             :renderer (make-renderer 5 5)
             :quitp nil
             :input-stream (make-string-input-stream ""))))

    (it "defaults FD to 0 and TERMINAL-SIZE-FN to CL-TTY-KIT:TERMINAL-SIZE, leaving an
already-matching MATRIX-STATE unchanged when FD 0 is not a real terminal (as in this test
runner)"
      (run-state-poll *run-state*)
      (with-soft-assertions
        (expect (= (matrix-state-width (run-state-matrix *run-state*)) 5) :to-be-truthy)
        (expect (= (matrix-state-height (run-state-matrix *run-state*)) 5) :to-be-truthy))))

  (describe "quit key wiring"
    (before-each
      (setf *run-state*
            (make-run-state
             :matrix (make-matrix-state 5 5 :random-state (sb-ext:seed-random-state 44))
             :renderer (make-renderer 5 5)
             :quitp nil
             :input-stream (make-string-input-stream ""))))

    (it "sets QUITP once a quit key is read from INPUT-STREAM"
      (setf (run-state-input-stream *run-state*) (make-string-input-stream "q"))
      (run-state-poll *run-state*
                       :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 5 5)))
      (expect (run-state-quitp *run-state*) :to-be-truthy))

    (it "leaves QUITP false when no quit key is buffered"
      (run-state-poll *run-state*
                       :terminal-size-fn (lambda (fd) (declare (ignore fd)) (values 5 5)))
      (expect (not (run-state-quitp *run-state*)) :to-be-truthy))))

(describe "run-state-advance"
  (before-each
    (setf *run-state*
          (make-run-state
           :matrix (make-matrix-state 5 5 :random-state (sb-ext:seed-random-state 44))
           :renderer (make-renderer 5 5)
           :quitp nil
           :input-stream (make-string-input-stream ""))))

  (it "advances the underlying matrix's tick counter by one"
    (run-state-advance *run-state*)
    (expect (= (matrix-state-tick (run-state-matrix *run-state*)) 1) :to-be-truthy))

  (it "does not touch QUITP or the renderer's dimensions"
    (run-state-advance *run-state*)
    (with-soft-assertions
      (expect (not (run-state-quitp *run-state*)) :to-be-truthy)
      (expect (= (renderer-width (run-state-renderer *run-state*)) 5) :to-be-truthy)
      (expect (= (renderer-height (run-state-renderer *run-state*)) 5) :to-be-truthy))))

(describe "run-state-render"
  (before-each
    (setf *run-state*
          (make-run-state
           :matrix (make-matrix-state 5 5 :random-state (sb-ext:seed-random-state 60))
           :renderer (make-renderer 5 5)
           :quitp nil
           :input-stream (make-string-input-stream ""))))

  (it "redraws the renderer and returns the diffed ANSI frame as a string"
    (expect (stringp (run-state-render *run-state*)) :to-be-truthy))

  (it "keeps returning a string across repeated renders, advanced or not"
    (run-state-render *run-state*)
    (run-state-advance *run-state*)
    (expect (stringp (run-state-render *run-state*)) :to-be-truthy)))

(describe "%terminal-dimensions"
  (it-each ((80 24 80 24) (120 40 120 40) (nil nil 80 24) (80 nil 80 24) (nil 24 80 24))
      "resolves columns ~A rows ~A to width ~A height ~A"
      (columns rows expected-width expected-height)
    (with-soft-assertions
      (multiple-value-bind (width height) (cl-cmatrix::%terminal-dimensions columns rows)
        (expect (= width expected-width) :to-be-truthy)
        (expect (= height expected-height) :to-be-truthy)))))

(describe "%make-initial-run-state"
  (it "builds a run-state around a matrix and renderer of the given dimensions"
    (let ((run-state (cl-cmatrix::%make-initial-run-state
                       10 5 1.5 :cyan +default-glyphs+ nil (sb-ext:seed-random-state 70)
                       (make-string-input-stream ""))))
      (with-soft-assertions
        (expect (= (matrix-state-width (run-state-matrix run-state)) 10) :to-be-truthy)
        (expect (= (matrix-state-height (run-state-matrix run-state)) 5) :to-be-truthy)
        (expect (= (matrix-state-speed (run-state-matrix run-state)) 1.5) :to-be-truthy)
        (expect (eq (matrix-state-color (run-state-matrix run-state)) :cyan) :to-be-truthy)
        (expect (= (renderer-width (run-state-renderer run-state)) 10) :to-be-truthy)
        (expect (= (renderer-height (run-state-renderer run-state)) 5) :to-be-truthy)
        (expect (not (run-state-quitp run-state)) :to-be-truthy))))

  (it "threads GLYPHS and BOLD through to the underlying matrix-state"
    (let* ((glyphs (coerce '(#\X #\Y) 'simple-vector))
           (run-state (cl-cmatrix::%make-initial-run-state
                       4 4 1 :green glyphs t (sb-ext:seed-random-state 71)
                       (make-string-input-stream ""))))
      (with-soft-assertions
        (expect (eq (matrix-state-glyphs (run-state-matrix run-state)) glyphs) :to-be-truthy)
        (expect (matrix-state-bold (run-state-matrix run-state)) :to-be-truthy)))))
