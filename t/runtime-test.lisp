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
            :to-be-truthy)))
