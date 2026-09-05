
(in-package #:cl-cmatrix/test)

(defun %resized-fixture (width height seed &key old-style-p (ticks 20))
  "Advance a MATRIX-STATE TICKS frames so its columns contain glyphs rather
than the blank buffers of a fresh state. ASYNCP is off so every column advances."
  (let ((state (make-matrix-state width height
                                  :asyncp nil
                                  :old-style-p old-style-p
                                  :random-state (sb-ext:seed-random-state seed))))
    (loop repeat ticks do (setf state (matrix-advance state)))
    state))

(defun %column-has-characters-p (column)
  "True when COLUMN currently shows at least one glyph."
  (some #'characterp (column-cells column)))

(describe "matrix-resize"
  (it "keeps existing columns exactly, growing width by appending fresh ones"
    (let* ((advanced (%resized-fixture 4 10 11))
           (before (matrix-state-columns advanced))
           (resized (matrix-resize advanced 7 10))
           (after (matrix-state-columns resized)))
      (with-soft-assertions
        (expect (= (matrix-state-width resized) 7) :to-be-truthy)
        (expect (= (length after) (matrix-state-column-count 7)) :to-be-truthy)
        (expect (> (length after) (length before)) :to-be-truthy)
        (expect (equalp (subseq after 0 (length before)) before) :to-be-truthy))))

  (it "shrinking width keeps the leftmost columns and drops the rest"
    (let* ((state (%resized-fixture 6 10 12))
           (kept (matrix-state-column-count 3))
           (before (subseq (matrix-state-columns state) 0 kept))
           (resized (matrix-resize state 3 10)))
      (with-soft-assertions
        (expect (= (matrix-state-width resized) 3) :to-be-truthy)
        (expect (< kept (length (matrix-state-columns state))) :to-be-truthy)
        (expect (equalp (matrix-state-columns resized) before) :to-be-truthy))))

  (it "growing the height keeps every visible row and pads the new rows with :EMPTY"
    (let* ((state (%resized-fixture 5 10 13))
           (before (matrix-state-columns state))
           (resized (matrix-resize state 5 20))
           (after (matrix-state-columns resized)))
      (with-soft-assertions
        (expect (= (matrix-state-height resized) 20) :to-be-truthy)
        (expect (= (length after) (length before)) :to-be-truthy)
        (expect (every (lambda (column)
                         (and (= (length (column-cells column)) 21)
                              (= (length (column-heads column)) 21)))
                       after)
                :to-be-truthy)
        (expect (some #'%column-has-characters-p before) :to-be-truthy)
        (expect (every (lambda (old new)
                         (dotimes (row 11 t)
                           (unless (and (eql (column-cell-at old row)
                                             (column-cell-at new row))
                                        (eq (column-head-p old row)
                                            (column-head-p new row)))
                             (return nil))))
                       before after)
                :to-be-truthy)
        (expect (every (lambda (column)
                         (loop for row from 11 to 20
                               always (and (eq (column-cell-at column row) :empty)
                                           (not (column-head-p column row)))))
                       after)
                :to-be-truthy))))

  (it "shrinking the height truncates the buffer and clamps LENGTH and SPACES onto it"
    (let* ((state (%resized-fixture 5 20 14))
           (before (matrix-state-columns state))
           (resized (matrix-resize state 5 4))
           (after (matrix-state-columns resized)))
      (with-soft-assertions
        (expect (= (matrix-state-height resized) 4) :to-be-truthy)
        (expect (every (lambda (column)
                         (and (= (length (column-cells column)) 5)
                              (= (length (column-heads column)) 5)))
                       after)
                :to-be-truthy)
        (expect (every (lambda (old new)
                         (loop for row from 0 to 4
                               always (eql (column-cell-at old row)
                                           (column-cell-at new row))))
                       before after)
                :to-be-truthy)
        (expect (some (lambda (column) (> (column-length column) 4)) before)
                :to-be-truthy)
        (expect (every (lambda (column)
                         (and (<= +min-trail-length+ (column-length column) 4)
                              (<= 0 (column-spaces column) 4)))
                       after)
                :to-be-truthy))))

  (it "clamps LENGTH no lower than +MIN-TRAIL-LENGTH+ on a screen shorter than that"
    (let* ((state (%resized-fixture 5 20 15))
           (resized (matrix-resize state 5 2)))
      (with-soft-assertions
        (expect (= (matrix-state-height resized) 2) :to-be-truthy)
        (expect (every (lambda (column) (= (column-length column) +min-trail-length+))
                       (matrix-state-columns resized))
                :to-be-truthy))))

  (it "reflows old-style columns into HEIGHT+1 buffers with the mode flag intact"
    (let* ((state (%resized-fixture 5 10 63 :old-style-p t))
           (resized (matrix-resize state 7 14)))
      (with-soft-assertions
        (expect (matrix-state-old-style-p resized) :to-be-truthy)
        (expect (= (length (matrix-state-columns resized)) (matrix-state-column-count 7))
                :to-be-truthy)
        (expect (every (lambda (column)
                         (and (column-p column)
                              (= (length (column-cells column)) 15)
                              (= (length (column-heads column)) 15)))
                       (matrix-state-columns resized))
                :to-be-truthy)
        (expect (every (lambda (column) (= (length (column-cells column)) 15))
                       (matrix-state-columns (matrix-advance resized)))
                :to-be-truthy))))

  (it "reflows the running animation instead of re-initialising it, unlike upstream"
    (let* ((state (%resized-fixture 5 10 16))
           (resized (matrix-resize state 9 10)))
      (with-soft-assertions
        (expect (= (matrix-state-tick resized) (matrix-state-tick state)) :to-be-truthy)
        (expect (= (matrix-state-async-count resized) (matrix-state-async-count state))
                :to-be-truthy)
        (expect (some #'%column-has-characters-p (matrix-state-columns state))
                :to-be-truthy)
        (expect (some #'%column-has-characters-p (matrix-state-columns resized))
                :to-be-truthy))))

  (it "reflows reproducibly: growing twice from the same seed yields identical new columns"
    (let* ((state-1 (matrix-resize
                      (make-matrix-state 3 10 :random-state (sb-ext:seed-random-state 21)) 6 10))
           (state-2 (matrix-resize
                      (make-matrix-state 3 10 :random-state (sb-ext:seed-random-state 21)) 6 10)))
      (with-soft-assertions
        (expect (> (length (matrix-state-columns state-1)) (matrix-state-column-count 3))
                :to-be-truthy)
        (expect (equalp (matrix-state-columns state-1) (matrix-state-columns state-2))
                :to-be-truthy))))

  (it-each ((0 4) (4 -1))
      "signals INVALID-DIMENSIONS for a new width ~A height ~A"
      (new-width new-height)
    (let ((state (make-matrix-state 4 4 :random-state (sb-ext:seed-random-state 14))))
      (expect (signals invalid-dimensions (matrix-resize state new-width new-height))
              :to-be-truthy)))

  (it-property "always yields a MATRIX-STATE of exactly the requested new dimensions, with
HEIGHT+1 cell buffers, for any valid starting and target size"
      ((width (gen-integer :min 1 :max 40))
       (height (gen-integer :min 1 :max 40))
       (new-width (gen-integer :min 1 :max 40))
       (new-height (gen-integer :min 1 :max 40)))
    (let* ((state (make-matrix-state width height :random-state (sb-ext:seed-random-state 99)))
           (resized (matrix-resize state new-width new-height)))
      (expect (= (matrix-state-width resized) new-width) :to-be-truthy)
      (expect (= (matrix-state-height resized) new-height) :to-be-truthy)
      (expect (= (length (matrix-state-columns resized))
                 (matrix-state-column-count new-width))
              :to-be-truthy)
      (expect (every (lambda (column)
                       (and (= (length (column-cells column)) (1+ new-height))
                            (= (length (column-heads column)) (1+ new-height))))
                     (matrix-state-columns resized))
              :to-be-truthy))))
