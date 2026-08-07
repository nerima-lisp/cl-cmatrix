;;;; t/render-test.lisp

(in-package #:cl-cmatrix/test)

(defun %style-fg-entry (style)
  "Return the (:FG ...) entry within STYLE, cl-tty-kit's normalized style
list. STYLE mixes bare modifier keywords like :BOLD with (:FG ...)/(:BG ...)
sublists, so ASSOC cannot walk it directly -- ASSOC calls CAR on every
element, including the bare keywords, which are not conses."
  (find-if (lambda (item) (and (consp item) (eq (first item) :fg))) style))

(defun %non-head-lit-cell (state)
  "Return (VALUES X ROW) locating the first on-screen lit cell of STATE that
is not its column's head, or (VALUES NIL NIL) when STATE has none. Only a
non-head cell distinguishes BOLD from the default, since the head is bold
either way -- so callers must also assert that they actually got one, or a
state whose columns happened to show nothing but heads would let the whole
assertion pass without ever running."
  (loop for x below (matrix-state-width state)
        for column = (aref (matrix-state-columns state) x)
        do (loop for row below (matrix-state-height state)
                 when (and (column-row-lit-p column row)
                           (/= row (column-head column)))
                   do (return-from %non-head-lit-cell (values x row))))
  (values nil nil))

(defun %drawn-trail-frame (bold)
  "Advance a fixed-seed 3x24 state 30 ticks under BOLD, draw it, and return
(VALUES SCREEN X ROW) with X/ROW from %NON-HEAD-LIT-CELL. BOLD feeds no
random draw, so both BOLD values yield identical columns and therefore the
same X/ROW -- the two frames differ only in the style at that cell."
  (let ((state (make-matrix-state 3 24 :bold bold
                                        :random-state (sb-ext:seed-random-state 30))))
    (dotimes (i 30) (setf state (matrix-advance state)))
    (let ((screen (make-screen 3 24)))
      (matrix-draw screen state (make-render-context))
      (multiple-value-bind (x row) (%non-head-lit-cell state)
        (values screen x row)))))

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

  (it "leaves the head unbold when NO-BOLD is requested"
    (expect (not (member :bold (matrix-cell-style :green 0 5 nil t))) :to-be-truthy))

(describe "matrix-draw"
  (it "writes each column's currently lit glyphs at their rows, and leaves unlit rows blank"
    (let ((state (make-matrix-state 3 24 :random-state (sb-ext:seed-random-state 30))))
      (dotimes (i 30) (setf state (matrix-advance state)))
      (let ((screen (make-screen 3 24))
            (column (aref (matrix-state-columns state) 0)))
        (matrix-draw screen state (make-render-context))
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
           (schemes (list-color-schemes))
           (checked 0))
      (dotimes (i 40) (setf state (matrix-advance state)))
      (let ((screen (make-screen width 24)))
        (matrix-draw screen state (make-render-context))
        (with-soft-assertions
          (loop for x below width
                for column = (aref (matrix-state-columns state) x)
                for trail-row = (1- (column-head column))
                when (and (>= trail-row 0) (< trail-row 24) (column-row-lit-p column trail-row))
                  do (incf checked)
                     (expect
                      (equal (cell-style (screen-cell screen x trail-row))
                             (matrix-cell-style (nth (mod x (length schemes)) schemes) 1
                                                 (column-length column)))
                      :to-be-truthy))
          ;; Every assertion above sits behind a WHEN, so without this the
          ;; whole IT reports green on any state where no column happens to
          ;; show an on-screen trail row -- a hazard of the shape of the
          ;; loop, not of this particular seed.
          (expect (plusp checked) :to-be-truthy)))))

  (it "renders a lit non-head row bold when STATE's BOLD is true"
    (multiple-value-bind (screen x row) (%drawn-trail-frame t)
      (with-soft-assertions
        (expect (and x row) :to-be-truthy)
        (expect (and x row (member :bold (cell-style (screen-cell screen x row))))
                :to-be-truthy))))

  (it "leaves that same lit non-head row unbold when STATE's BOLD is false"
    (multiple-value-bind (screen x row) (%drawn-trail-frame nil)
      (with-soft-assertions
        (expect (and x row) :to-be-truthy)
        (expect (and x row (not (member :bold (cell-style (screen-cell screen x row)))))
                :to-be-truthy))))

  (it "uses STATE's random-bold setting for deterministic trail styles"
    (let ((state (make-matrix-state 3 24 :random-bold-p t
                                    :random-state (sb-ext:seed-random-state 31))))
      (dotimes (i 30) (setf state (matrix-advance state)))
      (let ((screen (make-screen 3 24)))
        (matrix-draw screen state (make-render-context))
        (multiple-value-bind (x row) (%non-head-lit-cell state)
          (with-soft-assertions
            (expect (matrix-state-random-bold-p state) :to-be-truthy)
            (expect (and x row) :to-be-truthy)
            (expect
             (eq (not (null (member :bold (cell-style (screen-cell screen x row)))))
                 (cl-cmatrix::%random-bold-cell-p
                  x row (matrix-state-tick state)))
             :to-be-truthy))))))

  (it "selects both plain and bold styles for random-bold cells"
    (let* ((column (cl-cmatrix::%make-column
                    :head 3 :length 3 :glyphs #(#\a #\b #\c)))
           (cache (make-hash-table :test #'eq))
           (styles (cl-cmatrix::%matrix-style-vector :green 3 nil cache))
           (bold-styles (cl-cmatrix::%matrix-style-vector :green 3 t cache))
           (screen (make-screen 1 6)))
      (cl-cmatrix::%matrix-draw-column
       screen 0 column 6 styles
       :bold-styles bold-styles
       :random-bold-p t
       :tick 0)
      (with-soft-assertions
        (expect (member :bold (cell-style (screen-cell screen 0 3)))
                :to-be-truthy)
        (expect (not (member :bold (cell-style (screen-cell screen 0 2))))
                :to-be-truthy)
        (expect (member :bold (cell-style (screen-cell screen 0 1)))
                :to-be-truthy))))

  (it "draws old-style rows with their stored per-glyph bold metadata"
    (let* ((state (make-matrix-state 1 3 :old-style-p t :partial-bold-p t
                                     :random-state (sb-ext:seed-random-state 41)))
           (column (cl-cmatrix::%make-old-style-column
                    :glyphs (vector #\a nil #\c)
                    :glyph-bold-p (vector t nil t)
                    :spaces 0))
           (screen (make-screen 1 3)))
      (setf (aref (matrix-state-columns state) 0) column)
      (matrix-draw screen state (make-render-context))
      (with-soft-assertions
        (expect (char= (cell-char (screen-cell screen 0 0)) #\a) :to-be-truthy)
        (expect (char= (cell-char (screen-cell screen 0 2)) #\c) :to-be-truthy)
        (expect (member :bold (cell-style (screen-cell screen 0 0))) :to-be-truthy)
        (expect (member :bold (cell-style (screen-cell screen 0 2)))
                :to-be-truthy))))

  (it "centers short messages, clips long messages, and ignores empty messages"
    (let ((short-screen (make-screen 5 4))
          (long-screen (make-screen 5 4))
          (empty-screen (make-screen 5 4)))
      (cl-cmatrix::matrix-draw-message short-screen 5 4 "hi")
      (cl-cmatrix::matrix-draw-message long-screen 5 4 "toolong")
      (cl-cmatrix::matrix-draw-message empty-screen 5 4 nil)
      (cl-cmatrix::matrix-draw-message empty-screen 5 4 "")
      (with-soft-assertions
        (expect (char= (cell-char (screen-cell short-screen 0 2)) #\Space)
                :to-be-truthy)
        (expect (char= (cell-char (screen-cell short-screen 1 2)) #\h)
                :to-be-truthy)
        (expect (char= (cell-char (screen-cell short-screen 2 2)) #\i)
                :to-be-truthy)
        (loop for x below 5
              for expected across "toolo"
              do (expect (char= (cell-char (screen-cell long-screen x 2)) expected)
                         :to-be-truthy))
        (expect (char= (cell-char (screen-cell empty-screen 0 2)) #\Space)
                :to-be-truthy)))))

(describe "%matrix-style-vector"
  (it "returns the identical vector object on a repeat call, rather than recomputing it"
    (let ((cache (make-hash-table :test #'eq)))
      (expect (eq (cl-cmatrix::%matrix-style-vector :green 5 nil cache)
                  (cl-cmatrix::%matrix-style-vector :green 5 nil cache))
              :to-be-truthy)))

  (it "keys on BOLD, so a bold request never shares the non-bold entry in one cache"
    (let* ((cache (make-hash-table :test #'eq))
           (plain (cl-cmatrix::%matrix-style-vector :green 5 nil cache))
           (bold (cl-cmatrix::%matrix-style-vector :green 5 t cache)))
      (with-soft-assertions
        (expect (not (eq plain bold)) :to-be-truthy)
        (expect (notevery #'equal plain bold) :to-be-truthy))))

  (it "fills each offset with MATRIX-CELL-STYLE's own result for that offset"
    (let* ((cache (make-hash-table :test #'eq))
           (styles (cl-cmatrix::%matrix-style-vector :green 5 nil cache)))
      (with-soft-assertions
        (expect (= (length styles) 5) :to-be-truthy)
        (loop for offset below 5
              do (expect (equal (svref styles offset)
                                (matrix-cell-style :green offset 5 nil))
                         :to-be-truthy))))))

(describe "%matrix-draw-column"
  (it "draws nothing at all when the whole column still sits above row 0"
    (let ((column (cl-cmatrix::%make-column :head -1 :length 4 :glyphs #(#\a #\b #\c #\d)))
          (styles (cl-cmatrix::%matrix-style-vector :green 4 nil (make-hash-table :test #'eq)))
          (screen (make-screen 1 6)))
      (cl-cmatrix::%matrix-draw-column screen 0 column 6 styles)
      (with-soft-assertions
        (loop for row below 6
              do (expect (char= (cell-char (screen-cell screen 0 row)) #\Space)
                         :to-be-truthy)))))

  (it "stops at row 0 rather than walking the rest of the trail off the top edge"
    (let ((column (cl-cmatrix::%make-column :head 1 :length 4 :glyphs #(#\a #\b #\c #\d)))
          (styles (cl-cmatrix::%matrix-style-vector :green 4 nil (make-hash-table :test #'eq)))
          (screen (make-screen 1 6)))
      (cl-cmatrix::%matrix-draw-column screen 0 column 6 styles)
      (with-soft-assertions
        (expect (char= (cell-char (screen-cell screen 0 1)) (column-glyph-at-row column 1))
                :to-be-truthy)
        (expect (char= (cell-char (screen-cell screen 0 0)) (column-glyph-at-row column 0))
                :to-be-truthy)
        (loop for row from 2 below 6
              do (expect (char= (cell-char (screen-cell screen 0 row)) #\Space)
                         :to-be-truthy)))))

  (it "skips the rows at or past HEIGHT while still drawing the ones below it"
    (let ((column (cl-cmatrix::%make-column :head 5 :length 4 :glyphs #(#\a #\b #\c #\d)))
          (styles (cl-cmatrix::%matrix-style-vector :green 4 nil (make-hash-table :test #'eq)))
          (screen (make-screen 1 6)))
      (cl-cmatrix::%matrix-draw-column screen 0 column 4 styles)
      (with-soft-assertions
        (expect (char= (cell-char (screen-cell screen 0 5)) #\Space) :to-be-truthy)
        (expect (char= (cell-char (screen-cell screen 0 4)) #\Space) :to-be-truthy)
        (expect (char= (cell-char (screen-cell screen 0 3)) (column-glyph-at-row column 3))
                :to-be-truthy)
        (expect (char= (cell-char (screen-cell screen 0 2)) (column-glyph-at-row column 2))
                :to-be-truthy)
        ;; Row 3 is OFFSET 2: the clipped rows above still consumed their
        ;; offsets, so the visible trail keeps fading from where the
        ;; off-screen head left off instead of restarting at offset 0.
        (expect (equal (cell-style (screen-cell screen 0 3)) (svref styles 2))
                :to-be-truthy)))))

  (it "uses character parity when partial-bold metadata is shorter than the glyph vector"
    (let* ((column (cl-cmatrix::%make-column
                    :head 3 :length 3
                    :glyphs (vector #\a #\b #\c)
                    :glyph-bold-p #()))
           (cache (make-hash-table :test #'eq))
           (styles (cl-cmatrix::%matrix-style-vector :green 3 nil cache))
           (bold-styles (cl-cmatrix::%matrix-style-vector :green 3 t cache))
           (screen (make-screen 1 4)))
      (cl-cmatrix::%matrix-draw-column
       screen 0 column 4 styles
       :bold-styles bold-styles
       :partial-bold-p t
       :glyph-bold-p #())
      (with-soft-assertions
        (expect (not (member :bold (cell-style (screen-cell screen 0 2))))
                :to-be-truthy)
        (expect (member :bold (cell-style (screen-cell screen 0 1)))
                :to-be-truthy))))

(describe "%column-color"
  (it "returns COLOR unchanged when RAINBOW-SCHEMES is NIL"
    (expect (eq (cl-cmatrix::%column-color 3 :cyan nil) :cyan) :to-be-truthy))

  (it "cycles through RAINBOW-SCHEMES by column index, wrapping at its length"
    (let ((schemes (list-color-schemes)))
      (with-soft-assertions
        (expect (eq (cl-cmatrix::%column-color 0 :rainbow schemes) (first schemes)) :to-be-truthy)
        (expect (eq (cl-cmatrix::%column-color (length schemes) :rainbow schemes) (first schemes))
                :to-be-truthy)))))
