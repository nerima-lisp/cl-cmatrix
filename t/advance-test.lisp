;;;; t/advance-test.lisp
;;;;
;;;; The determinism guarantee this project is built around: a MATRIX-STATE
;;;; seeded from a fixed RANDOM-STATE produces byte-identical output, tick
;;;; for tick, on every run.

(in-package #:cl-cmatrix/test)

(defun %run-ticks (width height ticks &key (seed 42) (speed 1))
  (let ((state (make-matrix-state width height :speed speed
                                   :random-state (sb-ext:seed-random-state seed))))
    (dotimes (i ticks state)
      (setf state (matrix-advance state)))))

(defun %column-snapshot (state)
  (map 'list (lambda (c) (list (column-head c) (column-length c) (column-interval c)
                                (column-counter c) (coerce (column-glyphs c) 'list)))
       (matrix-state-columns state)))

(describe "matrix-advance"
  (it "advances the tick counter by exactly one per call"
    (let ((state (make-matrix-state 3 5 :random-state (sb-ext:seed-random-state 1))))
      (dotimes (i 5)
        (expect (= (matrix-state-tick state) i) :to-be-truthy)
        (setf state (matrix-advance state)))
      (expect (= (matrix-state-tick state) 5) :to-be-truthy)))

  (it "is reproducible: two independent runs from the same seed reach identical column state"
    (let ((snapshot-1 (%column-snapshot (%run-ticks 8 12 60)))
          (snapshot-2 (%column-snapshot (%run-ticks 8 12 60))))
      (expect (equal snapshot-1 snapshot-2) :to-be-truthy)))

  (it "a different seed reaches different column state (the seed is actually the source of
the randomness)"
    (let ((snapshot-1 (%column-snapshot (%run-ticks 8 12 60 :seed 1)))
          (snapshot-2 (%column-snapshot (%run-ticks 8 12 60 :seed 2))))
      (expect (not (equal snapshot-1 snapshot-2)) :to-be-truthy)))

  (it "a SPEED high enough forces a one-tick-per-row interval on every column, deterministically"
    ;; %spawn-column always draws a raw interval in [1, 3] before SPEED
    ;; scaling. At SPEED 4, MAX(1, ROUND(raw/4)) is 1 for every value of raw
    ;; in that range (ROUND(1/4)=0, ROUND(2/4)=0 by round-to-even,
    ;; ROUND(3/4)=1), so every column advances on every tick -- an exact
    ;; invariant, not a statistical tendency, so this test needs no
    ;; particular seed to hold.
    (let* ((before (make-matrix-state 6 100 :speed 4 :random-state (sb-ext:seed-random-state 5)))
           (initial-heads (map 'list #'column-head (matrix-state-columns before)))
           (after (matrix-advance before))
           (advanced-heads (map 'list #'column-head (matrix-state-columns after))))
      (expect (equal advanced-heads (mapcar #'1+ initial-heads)) :to-be-truthy)))

  (it "never mutates its argument's COLUMNS vector"
    (let* ((state (make-matrix-state 4 6 :random-state (sb-ext:seed-random-state 9)))
           (columns-before (matrix-state-columns state)))
      (matrix-advance state)
      (expect (eq (matrix-state-columns state) columns-before) :to-be-truthy)))

  (it "shifts old-style rows downward while preserving glyph metadata"
    (let* ((column (cl-cmatrix::%make-old-style-column
                     :interval 1 :counter 0
                     :glyphs (vector #\a #\b #\c)
                     :glyph-bold-p (vector t nil t)
                     :spaces 1))
           (advanced (cl-cmatrix::%old-style-column-fall-one-row
                      column (coerce '(#\X #\Y) 'simple-vector)
                      (sb-ext:seed-random-state 62)
                      :interval 1)))
      (expect (equal (coerce (old-style-column-glyphs advanced) 'list)
                     '(nil #\a #\b))
              :to-be-truthy)
      (expect (equal (coerce (old-style-column-glyph-bold-p advanced) 'list)
                     '(nil t nil))
              :to-be-truthy)
      (expect (= (old-style-column-spaces advanced) 0) :to-be-truthy)))

  (it "looks up old-style glyphs only inside the visible row vector"
    (let ((column (cl-cmatrix::%make-old-style-column
                    :glyphs (vector #\a nil #\c)
                    :glyph-bold-p (vector nil nil nil))))
      (with-soft-assertions
        (expect (null (old-style-column-glyph-at-row column -1)) :to-be-truthy)
        (expect (char= (old-style-column-glyph-at-row column 0) #\a) :to-be-truthy)
        (expect (null (old-style-column-glyph-at-row column 1)) :to-be-truthy)
        (expect (char= (old-style-column-glyph-at-row column 2) #\c) :to-be-truthy)
        (expect (null (old-style-column-glyph-at-row column 3)) :to-be-truthy))))

  (it "fills missing normal-column bold metadata from glyph parity"
    (let* ((column (cl-cmatrix::%make-column
                     :length 4
                     :glyphs (vector #\a #\b #\c)))
           (bold-p (cl-cmatrix::%copy-glyph-bold-p column)))
      (expect (equal (coerce bold-p 'list) '(nil t nil nil))
              :to-be-truthy)))

  (it "replaces every existing old-style glyph while preserving column metadata"
    (let* ((column (cl-cmatrix::%make-old-style-column
                     :interval 2 :counter 1
                     :glyphs (vector #\a nil #\c)
                     :glyph-bold-p (vector nil t nil)
                     :spaces 4))
           (replaced (cl-cmatrix::%old-style-column-with-glyphs
                      column (coerce '(#\X #\Y) 'simple-vector)
                      (sb-ext:seed-random-state 17))))
      (with-soft-assertions
        (expect (member (svref (old-style-column-glyphs replaced) 0) '(#\X #\Y))
                :to-be-truthy)
        (expect (null (svref (old-style-column-glyphs replaced) 1)) :to-be-truthy)
        (expect (member (svref (old-style-column-glyphs replaced) 2) '(#\X #\Y))
                :to-be-truthy)
        (expect (= (old-style-column-interval replaced) 2) :to-be-truthy)
        (expect (= (old-style-column-counter replaced) 1) :to-be-truthy)
        (expect (= (old-style-column-spaces replaced) 4) :to-be-truthy))))

  (it "repaints shifted old-style glyphs when CHANGE-GLYPHS-P is enabled"
    (let* ((column (cl-cmatrix::%make-old-style-column
                     :glyphs (vector #\a #\b #\c)
                     :glyph-bold-p (vector nil nil nil)
                     :spaces 1))
           (advanced (cl-cmatrix::%old-style-column-fall-one-row
                      column (coerce '(#\X #\Y) 'simple-vector)
                      (sb-ext:seed-random-state 62)
                      :interval 1 :change-glyphs-p t)))
      (with-soft-assertions
        (expect (null (svref (old-style-column-glyphs advanced) 0)) :to-be-truthy)
        (expect (member (svref (old-style-column-glyphs advanced) 1) '(#\X #\Y))
                :to-be-truthy)
        (expect (member (svref (old-style-column-glyphs advanced) 2) '(#\X #\Y))
                :to-be-truthy))))

  (it "takes both old-style respawn paths when there are no visible spaces"
    (let ((saw-space nil)
          (saw-glyph nil))
      (loop for seed from 1 to 64
            for advanced = (cl-cmatrix::%old-style-column-fall-one-row
                            (cl-cmatrix::%make-old-style-column
                             :glyphs (vector nil nil)
                             :glyph-bold-p (vector nil nil)
                             :spaces 0)
                            (coerce '(#\X #\Y) 'simple-vector)
                            (sb-ext:seed-random-state seed)
                            :interval 1)
            do (if (plusp (old-style-column-spaces advanced))
                   (setf saw-space t)
                   (setf saw-glyph (or saw-glyph
                                       (not (null (svref (old-style-column-glyphs advanced) 0)))))))
      (expect (and saw-space saw-glyph) :to-be-truthy)))

  (it "uses the synchronous interval when advancing an old-style column"
    (let* ((column (cl-cmatrix::%make-old-style-column
                     :interval 10 :counter 0
                     :glyphs (vector #\a)
                     :glyph-bold-p (vector nil)
                     :spaces 1))
           (advanced (cl-cmatrix::%advance-old-style-column
                      column (coerce '(#\X #\Y) 'simple-vector)
                      (sb-ext:seed-random-state 19)
                      4 3 :asyncp nil)))
      (with-soft-assertions
        (expect (= (old-style-column-interval advanced) 1) :to-be-truthy)
        (expect (= (old-style-column-counter advanced) 0) :to-be-truthy))))

  (it "waits for an asynchronous old-style interval before falling"
    (let* ((column (cl-cmatrix::%make-old-style-column
                     :interval 3 :counter 0
                     :glyphs (vector #\a)
                     :glyph-bold-p (vector nil)
                     :spaces 1))
           (advanced (cl-cmatrix::%advance-old-style-column
                      column (coerce '(#\X #\Y) 'simple-vector)
                      (sb-ext:seed-random-state 19)
                      1 3 :asyncp t)))
      (with-soft-assertions
        (expect (= (old-style-column-interval advanced) 3) :to-be-truthy)
        (expect (= (old-style-column-counter advanced) 1) :to-be-truthy))))

  (it "resizes old-style glyph and bold metadata vectors without changing other fields"
    (let* ((column (cl-cmatrix::%make-old-style-column
                     :interval 2 :counter 1 :spaces 3
                     :glyphs (vector #\a #\b #\c)
                     :glyph-bold-p (vector t nil t)))
           (short (cl-cmatrix::%resize-old-style-column column 2))
           (long (cl-cmatrix::%resize-old-style-column column 5)))
      (with-soft-assertions
        (expect (equal (coerce (old-style-column-glyphs short) 'list)
                       '(#\a #\b))
                :to-be-truthy)
        (expect (equal (coerce (old-style-column-glyph-bold-p short) 'list)
                       '(t nil))
                :to-be-truthy)
        (expect (equal (coerce (old-style-column-glyphs long) 'list)
                       '(#\a #\b #\c nil nil))
                :to-be-truthy)
        (expect (equal (coerce (old-style-column-glyph-bold-p long) 'list)
                       '(t nil t nil nil))
                :to-be-truthy)
        (expect (= (old-style-column-interval long) 2) :to-be-truthy)
        (expect (= (old-style-column-counter long) 1) :to-be-truthy)
        (expect (= (old-style-column-spaces long) 3) :to-be-truthy))))

  (it "respawns a column once its whole trail has scrolled past the visible height"
    ;; height 1, trail length at least +MIN-TRAIL-LENGTH+ (3): after enough
    ;; ticks the single column must have wrapped around at least once, so
    ;; its head must have come back up near the top rather than growing
    ;; without bound.
    (let ((state (%run-ticks 1 1 500 :seed 3)))
      (expect (< (column-head (aref (matrix-state-columns state) 0)) 20) :to-be-truthy))))
