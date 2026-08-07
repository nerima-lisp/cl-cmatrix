;;;; t/state-test.lisp

(in-package #:cl-cmatrix/test)

(describe "make-matrix-state"
  (it "builds WIDTH columns, copies RANDOM-STATE, and starts at tick 0"
    (let* ((random-state (sb-ext:seed-random-state 1))
           (state (make-matrix-state 6 10 :random-state random-state)))
      (with-soft-assertions
        (expect (= (matrix-state-width state) 6) :to-be-truthy)
        (expect (= (matrix-state-height state) 10) :to-be-truthy)
        (expect (= (length (matrix-state-columns state)) 6) :to-be-truthy)
        (expect (= (matrix-state-tick state) 0) :to-be-truthy)
        (expect (not (eq (matrix-state-random-state state) random-state))
                :to-be-truthy))))

  (it "spawns every column with its head at or above row 0"
    (let ((state (make-matrix-state 20 24 :random-state (sb-ext:seed-random-state 2))))
      (expect (every (lambda (column) (<= (column-head column) 0))
                     (matrix-state-columns state))
              :to-be-truthy)))

  (it "defaults SPEED to 1, COLOR to :green, and BOLD to false"
    (let ((state (make-matrix-state 4 4 :random-state (sb-ext:seed-random-state 3))))
      (with-soft-assertions
        (expect (= (matrix-state-speed state) 1) :to-be-truthy)
        (expect (eq (matrix-state-color state) :green) :to-be-truthy)
        (expect (not (matrix-state-bold state)) :to-be-truthy))))

  (it "stores BOLD when supplied"
    (let ((state (make-matrix-state 4 4 :bold t :random-state (sb-ext:seed-random-state 51))))
      (expect (matrix-state-bold state) :to-be-truthy)))

  (it "accepts :rainbow as a COLOR, even though it names no single scheme"
    (let ((state (make-matrix-state 4 4 :color :rainbow
                                     :random-state (sb-ext:seed-random-state 52))))
      (expect (eq (matrix-state-color state) :rainbow) :to-be-truthy)))

  (it "stores a custom GLYPHS set and makes it readable back via MATRIX-STATE-GLYPHS"
    (let* ((glyphs (coerce '(#\X #\Y) 'simple-vector))
           (state (make-matrix-state 4 4 :glyphs glyphs
                                      :random-state (sb-ext:seed-random-state 50))))
      (expect (eq (matrix-state-glyphs state) glyphs) :to-be-truthy)))

  (it "builds fixed-height old-style columns"
    (let ((state (make-matrix-state 7 9 :old-style-p t
                                     :random-state (sb-ext:seed-random-state 61))))
      (expect (matrix-state-old-style-p state) :to-be-truthy)
      (expect (every (lambda (column)
                       (and (old-style-column-p column)
                            (= (length (old-style-column-glyphs column)) 9)
                            (= (length (old-style-column-glyph-bold-p column)) 9)))
                     (matrix-state-columns state))
              :to-be-truthy)))

  (it-each ((0 10) (10 -1))
      "signals INVALID-DIMENSIONS for width ~A height ~A"
      (width height)
    (expect (signals invalid-dimensions (make-matrix-state width height)) :to-be-truthy))

  (it "signals INVALID-SPEED for a non-positive speed"
    (expect (signals invalid-speed (make-matrix-state 4 4 :speed 0)) :to-be-truthy))

  (it "signals INVALID-SPEED for a non-real speed"
    (expect (signals invalid-speed (make-matrix-state 4 4 :speed :fast))
            :to-be-truthy))

  (it "signals UNKNOWN-COLOR-SCHEME for an unregistered color, before spawning any column"
    (expect (signals unknown-color-scheme (make-matrix-state 4 4 :color :not-a-scheme))
            :to-be-truthy)))
