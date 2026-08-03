;;;; t/render-test.lisp

(in-package #:cl-cmatrix/test)

(defun %style-fg-entry (style)
  "Return the (:FG ...) entry within STYLE, cl-tty-kit's normalized style
list. STYLE mixes bare modifier keywords like :BOLD with (:FG ...)/(:BG ...)
sublists, so ASSOC cannot walk it directly -- ASSOC calls CAR on every
element, including the bare keywords, which are not conses."
  (find-if (lambda (item) (and (consp item) (eq (first item) :fg))) style))

(describe "matrix-cell-style"
  (it "renders the head (offset 0) bold in the scheme's head color"
    (let ((style (matrix-cell-style :green 0 5)))
      (with-soft-assertions
        (expect (member :bold style) :to-be-truthy)
        (expect (equal (%style-fg-entry style)
                       (list :fg (apply #'rgb-to-256 (color-scheme-head-rgb :green))))
                :to-be-truthy))))

  (it "renders a non-head row without :bold"
    (let ((style (matrix-cell-style :green 1 5)))
      (with-soft-assertions
        (expect (not (member :bold style)) :to-be-truthy)
        (expect (consp (%style-fg-entry style)) :to-be-truthy))))

  (it "the last lit row (offset = length - 1) blends all the way to the scheme's dark color"
    (let* ((length 6)
           (style (matrix-cell-style :green (1- length) length))
           (expected-rgb (blend-colors (color-scheme-bright-rgb :green)
                                        (color-scheme-dark-rgb :green) 1)))
      (expect (equal (%style-fg-entry style) (list :fg (apply #'rgb-to-256 expected-rgb)))
              :to-be-truthy)))

  (it "every color scheme's head is the same bright white, by design"
    (expect (equal (matrix-cell-style :green 0 5) (matrix-cell-style :cyan 0 5))
            :to-be-truthy))

  (it "different color schemes produce different non-head (trail) styles"
    (expect (not (equal (matrix-cell-style :green 1 5) (matrix-cell-style :cyan 1 5)))
            :to-be-truthy))

  (it "a trail length of 1 does not divide by zero: OFFSET 0 takes the head branch"
    (expect (matrix-cell-style :green 0 1) :to-be-truthy))

  (it "a trail length of 1 does not divide by zero: OFFSET 1 clamps its ratio denominator to 1"
    (let ((style (matrix-cell-style :green 1 1))
          (expected-rgb (blend-colors (color-scheme-bright-rgb :green)
                                       (color-scheme-dark-rgb :green) 1)))
      (expect (equal (%style-fg-entry style) (list :fg (apply #'rgb-to-256 expected-rgb)))
              :to-be-truthy)))

  (it "a non-head row is not bold by default"
    (expect (not (member :bold (matrix-cell-style :green 1 5))) :to-be-truthy))

  (it "a non-head row is bold when BOLD is true"
    (expect (member :bold (matrix-cell-style :green 1 5 t)) :to-be-truthy))

  (it "the head is bold regardless of BOLD, and its color is unaffected by BOLD"
    (expect (equal (matrix-cell-style :green 0 5 nil) (matrix-cell-style :green 0 5 t))
            :to-be-truthy)))

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
                               :to-be-truthy)))))))

  (it "a :rainbow COLOR draws each column's trail in a different scheme, cycled by index"
    (let* ((width 3)
           (state (make-matrix-state width 24 :color :rainbow
                                      :random-state (sb-ext:seed-random-state 33)))
           (schemes (list-color-schemes)))
      (dotimes (i 40) (setf state (matrix-advance state)))
      (let ((screen (make-screen width 24)))
        (matrix-draw screen state)
        (with-soft-assertions
          (loop for x below width
                for column = (aref (matrix-state-columns state) x)
                for trail-row = (1- (column-head column))
                when (and (>= trail-row 0) (< trail-row 24) (column-row-lit-p column trail-row))
                  do (expect
                      (equal (cell-style (screen-cell screen x trail-row))
                             (matrix-cell-style (nth (mod x (length schemes)) schemes) 1
                                                 (column-length column)))
                      :to-be-truthy)))))))

(describe "%column-color"
  (it "returns COLOR unchanged when RAINBOW-SCHEMES is NIL"
    (expect (eq (cl-cmatrix::%column-color 3 :cyan nil) :cyan) :to-be-truthy))

  (it "cycles through RAINBOW-SCHEMES by column index, wrapping at its length"
    (let ((schemes (list-color-schemes)))
      (with-soft-assertions
        (expect (eq (cl-cmatrix::%column-color 0 :rainbow schemes) (first schemes)) :to-be-truthy)
        (expect (eq (cl-cmatrix::%column-color (length schemes) :rainbow schemes) (first schemes))
                :to-be-truthy)))))
