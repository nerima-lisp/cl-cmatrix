;;;; t/render-test.lisp

(in-package #:cl-cmatrix/test)

(describe "matrix-cell-style"
  (it "renders the head (offset 0) bold in the scheme's head color"
    (let ((style (matrix-cell-style :green 0 5)))
      (with-soft-assertions
        (expect (member :bold style) :to-be-truthy)
        (expect (equal (assoc :fg style)
                       (list :fg (apply #'rgb-to-256 (color-scheme-head-rgb :green))))
                :to-be-truthy))))

  (it "renders a non-head row without :bold"
    (let ((style (matrix-cell-style :green 1 5)))
      (with-soft-assertions
        (expect (not (member :bold style)) :to-be-truthy)
        (expect (consp (assoc :fg style)) :to-be-truthy))))

  (it "the last lit row (offset = length - 1) blends all the way to the scheme's dark color"
    (let* ((length 6)
           (style (matrix-cell-style :green (1- length) length))
           (expected-rgb (blend-colors (color-scheme-bright-rgb :green)
                                        (color-scheme-dark-rgb :green) 1)))
      (expect (equal (assoc :fg style) (list :fg (apply #'rgb-to-256 expected-rgb)))
              :to-be-truthy)))

  (it "different color schemes produce different head styles"
    (expect (not (equal (matrix-cell-style :green 0 5) (matrix-cell-style :cyan 0 5)))
            :to-be-truthy))

  (it "a trail length of 1 does not divide by zero: OFFSET 0 takes the head branch"
    (expect (matrix-cell-style :green 0 1) :to-be-truthy))

  (it "a trail length of 1 does not divide by zero: OFFSET 1 clamps its ratio denominator to 1"
    (let ((style (matrix-cell-style :green 1 1))
          (expected-rgb (blend-colors (color-scheme-bright-rgb :green)
                                       (color-scheme-dark-rgb :green) 1)))
      (expect (equal (assoc :fg style) (list :fg (apply #'rgb-to-256 expected-rgb)))
              :to-be-truthy))))

(describe "matrix-draw"
  (it "writes each column's currently lit glyphs at their rows, and leaves unlit rows blank"
    (let ((state (make-matrix-state 3 24 :random-state (sb-ext:seed-random-state 30))))
      (dotimes (i 30) (setf state (matrix-advance state)))
      (let ((screen (make-screen 3 24))
            (column (aref (matrix-state-columns state) 0)))
        (matrix-draw screen state)
        (with-soft-assertions
          (loop for row below 24
                do (if (column-row-lit-p column row)
                       (expect (char= (cell-char (screen-cell screen 0 row))
                                      (column-glyph-at-row column row))
                               :to-be-truthy)
                       (expect (char= (cell-char (screen-cell screen 0 row)) #\Space)
                               :to-be-truthy))))))))
