
(in-package #:cl-cmatrix/test)

(describe "run-matrix argument validation"
  (it-each ((0) (-1) (:not-a-number))
      "signals INVALID-FPS for ~S before terminal setup"
      (fps)
    (expect (signals invalid-fps (cl-cmatrix::%assert-fps fps))
            :to-be-truthy))

  (it "accepts a positive real FPS value unchanged"
    (expect (= (cl-cmatrix::%assert-fps 60.0d0) 60.0d0)
            :to-be-truthy))

  (it-each ((-1) (11) (1.0d0))
      "signals INVALID-UPDATE-DELAY for ~S"
      (delay)
    (expect (signals invalid-update-delay
                     (cl-cmatrix::%assert-update-delay delay))
            :to-be-truthy))

  (it-each ((0) (4) (10))
      "accepts upstream update delay ~S"
      (delay)
    (expect (= (cl-cmatrix::%assert-update-delay delay) delay)
            :to-be-truthy))

  (it-each ((0) (-1) (:fast) ("2"))
      "RUN-MATRIX itself signals INVALID-SPEED for :SPEED ~S"
      (speed)
    (expect (signals invalid-speed
                     (run-matrix :speed speed :fd -1
                                 :stream (make-string-output-stream)))
            :to-be-truthy))

  (it "validates SPEED before it reaches the terminal, not after"
    (let ((sink (make-string-output-stream)))
      (with-soft-assertions
        (expect (handler-case (progn (run-matrix :speed 1 :fd -1 :stream sink)
                                     :returned)
                  (invalid-speed () :stopped-at-validation)
                  (error () :reached-terminal-size))
                :to-equal :reached-terminal-size)
        (expect (string= "" (get-output-stream-string sink)) :to-be-truthy)))))

(describe "%update-ticks pace resolution"
  (it-each ((nil 0 1) (nil 4 4) (nil 10 10))
      "with FPS ~S and upstream delay ~A, resolves to ~A base ticks"
      (fps delay ticks)
    (expect (cl-cmatrix::%update-ticks fps delay 1) :to-equal ticks))

  (it-each ((60 2) (100 1) (1 100))
      "resolves ~A FPS with no update delay to ~A base ticks"
      (fps ticks)
    (expect (cl-cmatrix::%update-ticks fps nil 1) :to-equal ticks))

  (it "falls back to +DEFAULT-FPS+ when neither FPS nor a delay is supplied"
    (expect (cl-cmatrix::%update-ticks nil nil 1) :to-equal 3))

  (it "lets a supplied update delay override FPS rather than combining them"
    (with-soft-assertions
      (expect (cl-cmatrix::%update-ticks 60 4 1) :to-equal 4)
      (expect (cl-cmatrix::%update-ticks 1 10 1) :to-equal 10)))

  (it "treats a zero update delay as supplied, not as absent"
    (expect (cl-cmatrix::%update-ticks 1 0 1) :to-equal 1))

  (it "floors -u 0 at one base tick"
    (expect (cl-cmatrix::%update-ticks nil 0 1) :to-equal 1))

  (it-each ((8 1 8) (8 2 4) (8 4 2) (8 8 1) (8 16 1))
      "divides an update delay of ~A by speed ~A to give ~A base ticks"
      (delay speed ticks)
    (expect (cl-cmatrix::%update-ticks nil delay speed) :to-equal ticks))

  (it-property "never speeds up as --speed falls, for any delay in range"
      ((delay (gen-integer :min 0 :max 10))
       (speed (gen-integer :min 1 :max 19)))
    (expect (<= (cl-cmatrix::%update-ticks nil delay (1+ speed))
                (cl-cmatrix::%update-ticks nil delay speed))
            :to-be-truthy))

  (it-property "resolves to a positive integer count for every input in range"
      ((fps (gen-integer :min 1 :max 200))
       (delay (gen-integer :min 0 :max 10))
       (speed (gen-integer :min 1 :max 20)))
    (with-soft-assertions
      (expect (typep (cl-cmatrix::%update-ticks fps nil speed) '(integer 1 *))
              :to-be-truthy)
      (expect (typep (cl-cmatrix::%update-ticks fps delay speed) '(integer 1 *))
              :to-be-truthy))))

(describe "executor lifetime policy"
  (it "does not create an executor for narrow matrices"
    (let ((executor :unset))
      (cl-cmatrix::%with-matrix-executor (candidate 80 2)
        (setf executor candidate))
      (expect (null executor) :to-be-truthy)))

  (it "creates one executor for wide matrices"
    (let ((executor nil))
      (cl-cmatrix::%with-matrix-executor
          (candidate cl-cmatrix::+parallel-column-threshold+ 2)
        (setf executor candidate))
      (expect executor :to-be-truthy)))

  (it "does not create an executor for a wide matrix when ASYNCP is off"
    (let ((executor :unset))
      (cl-cmatrix::%with-matrix-executor
          (candidate cl-cmatrix::+parallel-column-threshold+ 2 nil)
        (setf executor candidate))
      (expect (null executor) :to-be-truthy))))
