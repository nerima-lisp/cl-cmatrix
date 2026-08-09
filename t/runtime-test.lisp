;;;; t/runtime-test.lisp

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

  ;; %ASSERT-SPEED's own rows live in t/state-test.lisp, beside the source file
  ;; that defines it. What is pinned here is the one property those rows cannot
  ;; reach: that RUN-MATRIX still calls it. Delete the (%ASSERT-SPEED SPEED)
  ;; form from src/runtime.lisp and every spec in state-test.lisp stays green --
  ;; these are the ones that go red.
  ;;
  ;; :FD -1 is what makes calling RUN-MATRIX from a spec safe rather than
  ;; reckless. TERMINAL-SIZE rejects a negative fd outright, before any syscall,
  ;; so no ordering bug can put this suite into raw mode or the alternate screen
  ;; and no spec can be left waiting on a keypress. :STREAM sinks the escape
  ;; sequences such a bug would emit, keeping them out of the spec report.
  (it-each ((0) (-1) (:fast) ("2"))
      "RUN-MATRIX itself signals INVALID-SPEED for :SPEED ~S"
      (speed)
    (expect (signals invalid-speed
                     (run-matrix :speed speed :fd -1
                                 :stream (make-string-output-stream)))
            :to-be-truthy))

  (it "validates SPEED before it reaches the terminal, not after"
    ;; The control the rows above need. On their own they are equally satisfied
    ;; by a RUN-MATRIX that validates only after taking the terminal, and by one
    ;; that cannot get anywhere at all in this environment. The identical call
    ;; with a valid speed gets strictly further -- past the validators and into
    ;; TERMINAL-SIZE, which is the form that rejects the -1 -- so the bad-speed
    ;; runs demonstrably stopped short of the terminal rather than at it.
    (let ((sink (make-string-output-stream)))
      (with-soft-assertions
        (expect (handler-case (progn (run-matrix :speed 1 :fd -1 :stream sink)
                                     :returned)
                  (invalid-speed () :stopped-at-validation)
                  (error () :reached-terminal-size))
                :to-equal :reached-terminal-size)
        ;; And nothing was written on the way in: no alternate screen, no
        ;; hidden cursor, hence nothing this suite would have to restore.
        (expect (string= "" (get-output-stream-string sink)) :to-be-truthy)))))

;;; %UPDATE-TICKS resolves --fps / --update-delay / --speed into the tick count
;;; the driver loop runs on. It replaced the older %TICK-INTERVAL, which
;;; returned seconds; the unit is now +BASE-TICK-SECONDS+ ticks, so what used
;;; to be an interval of 0.04 seconds is now a count of 4. The per-delay
;;; arithmetic itself belongs to %UPDATE-TICKS-FOR-DELAY and is covered in
;;; t/run-state-test.lisp; what is covered here is which input wins.
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
    ;; 3, not a re-derivation of the same expression the function evaluates:
    ;; +DEFAULT-FPS+ is 30 and +BASE-TICK-SECONDS+ is the rational 1/100, so a
    ;; frame is 10/3 base ticks and CL:ROUND takes that to 3. Recomputing the
    ;; formula here would agree with the implementation even if both were wrong.
    (expect (cl-cmatrix::%update-ticks nil nil 1) :to-equal 3))

  (it "lets a supplied update delay override FPS rather than combining them"
    ;; Each row's FPS resolves to a different count on its own -- 60 to 2 and 1
    ;; to 100 above -- so a result equal to the delay can only come from the
    ;; delay branch having won outright.
    (with-soft-assertions
      (expect (cl-cmatrix::%update-ticks 60 4 1) :to-equal 4)
      (expect (cl-cmatrix::%update-ticks 1 10 1) :to-equal 10)))

  (it "treats a zero update delay as supplied, not as absent"
    ;; The trap this pins: 0 is falsy nowhere in CL, but it is the value most
    ;; easily conflated with "unset". If the branch tested the delay for
    ;; nonzero rather than non-NIL, -u 0 would silently fall through to FPS and
    ;; yield 100 here instead of 1.
    (expect (cl-cmatrix::%update-ticks 1 0 1) :to-equal 1))

  (it "floors -u 0 at one base tick, a deliberate deviation from upstream"
    ;; src/runtime.lisp:39-45: upstream calls napms(0) at -u 0 and busy-loops.
    ;; We cap it at one advance per base tick, i.e. 100 FPS. The 1 below is the
    ;; intended value and not a rounding leftover -- a screensaver that pins a
    ;; core is worse than one imperceptibly slower than upstream's fastest.
    (expect (cl-cmatrix::%update-ticks nil 0 1) :to-equal 1))

  (it-each ((8 1 8) (8 2 4) (8 4 2) (8 8 1) (8 16 1))
      "divides an update delay of ~A by speed ~A to give ~A base ticks"
      (delay speed ticks)
    (expect (cl-cmatrix::%update-ticks nil delay speed) :to-equal ticks))

  (it-property "never speeds up as --speed falls, for any delay in range"
      ((delay (gen-integer :min 0 :max 10))
       (speed (gen-integer :min 1 :max 19)))
    ;; The direction of the extension, which the fixed rows above would still
    ;; satisfy if the division were inverted and the rows reordered: a larger
    ;; --speed means fewer ticks between advances, hence a faster matrix.
    (expect (<= (cl-cmatrix::%update-ticks nil delay (1+ speed))
                (cl-cmatrix::%update-ticks nil delay speed))
            :to-be-truthy))

  (it-property "resolves to a positive integer count for every input in range"
      ((fps (gen-integer :min 1 :max 200))
       (delay (gen-integer :min 0 :max 10))
       (speed (gen-integer :min 1 :max 20)))
    ;; RUN-STATE's UPDATE-TICKS slot is typed (INTEGER 1 *), so a resolution
    ;; that produced 0 or a ratio would signal at MAKE-RUN-STATE, not here.
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
    ;; Same width as the spec above, which is what makes this the ASYNCP
    ;; conjunct's own test rather than a second width test: -a off must keep
    ;; the pool down however wide the terminal is. Without it, the ASYNCP
    ;; conjunct is never evaluated false anywhere in the suite, so dropping it
    ;; would stay green.
    (let ((executor :unset))
      (cl-cmatrix::%with-matrix-executor
          (candidate cl-cmatrix::+parallel-column-threshold+ 2 nil)
        (setf executor candidate))
      (expect (null executor) :to-be-truthy))))
