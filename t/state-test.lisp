;;;; t/state-test.lisp

(in-package #:cl-cmatrix/test)

(describe "make-matrix-state"
  (it "builds WIDTH columns, remembers the dimensions, and starts at tick 0"
    (let ((state (make-matrix-state 6 10 :random-state (sb-ext:seed-random-state 1))))
      (with-soft-assertions
        (expect (= (matrix-state-width state) 6) :to-be-truthy)
        (expect (= (matrix-state-height state) 10) :to-be-truthy)
        (expect (= (length (matrix-state-columns state)) 6) :to-be-truthy)
        (expect (= (matrix-state-tick state) 0) :to-be-truthy))))

  (it "spawns every column with its head at or above row 0"
    (let ((state (make-matrix-state 20 24 :random-state (sb-ext:seed-random-state 2))))
      (expect (every (lambda (column) (<= (column-head column) 0))
                     (matrix-state-columns state))
              :to-be-truthy)))

  (it "defaults SPEED to 1 and COLOR to :green"
    (let ((state (make-matrix-state 4 4 :random-state (sb-ext:seed-random-state 3))))
      (with-soft-assertions
        (expect (= (matrix-state-speed state) 1) :to-be-truthy)
        (expect (eq (matrix-state-color state) :green) :to-be-truthy))))

  (it "signals INVALID-DIMENSIONS for a non-positive width or height"
    (with-soft-assertions
      (expect (signals (make-matrix-state 0 10) 'invalid-dimensions) :to-be-truthy)
      (expect (signals (make-matrix-state 10 -1) 'invalid-dimensions) :to-be-truthy)))

  (it "signals INVALID-SPEED for a non-positive speed"
    (expect (signals (make-matrix-state 4 4 :speed 0) 'invalid-speed) :to-be-truthy))

  (it "signals UNKNOWN-COLOR-SCHEME for an unregistered color, before spawning any column"
    (expect (signals (make-matrix-state 4 4 :color :not-a-scheme) 'unknown-color-scheme)
            :to-be-truthy)))
