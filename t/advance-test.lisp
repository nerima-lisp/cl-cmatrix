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

  (it "respawns a column once its whole trail has scrolled past the visible height"
    ;; height 1, trail length at least +MIN-TRAIL-LENGTH+ (3): after enough
    ;; ticks the single column must have wrapped around at least once, so
    ;; its head must have come back up near the top rather than growing
    ;; without bound.
    (let ((state (%run-ticks 1 1 500 :seed 3)))
      (expect (< (column-head (aref (matrix-state-columns state) 0)) 20) :to-be-truthy))))
