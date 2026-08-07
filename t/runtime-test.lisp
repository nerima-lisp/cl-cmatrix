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

  (it "uses update delay when supplied, including zero"
    (expect (= (cl-cmatrix::%tick-interval nil 0) 0.0d0)
            :to-be-truthy)
    (expect (= (cl-cmatrix::%tick-interval nil 4) 0.04d0)
            :to-be-truthy))

  (it "uses FPS for the long-form extension when no update delay is supplied"
    (expect (= (cl-cmatrix::%tick-interval 60 nil) (/ 1 60))
            :to-be-truthy)))

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
      (expect executor :to-be-truthy))))
