;;;; t/resize-test.lisp
;;;;
;;;; MATRIX-RESIZE is what a real run calls mid-loop when the polled
;;;; terminal size changes (see run-state.lisp's %POLL-RESIZE); these tests drive
;;;; it directly against a MATRIX-STATE that has already advanced a few
;;;; ticks, which is what "mid-run" means for a pure function.

(in-package #:cl-cmatrix/test)

(describe "matrix-resize"
  (it "keeps existing columns exactly, growing width by appending fresh ones"
    (let* ((state (make-matrix-state 4 10 :random-state (sb-ext:seed-random-state 11)))
           (advanced (matrix-advance (matrix-advance state)))
           (before-columns (matrix-state-columns advanced))
           (resized (matrix-resize advanced 7 10)))
      (with-soft-assertions
        (expect (= (matrix-state-width resized) 7) :to-be-truthy)
        (expect (= (length (matrix-state-columns resized)) 7) :to-be-truthy)
        (expect (equalp (subseq (matrix-state-columns resized) 0 4) before-columns)
                :to-be-truthy))))

  (it "shrinking width keeps the leftmost columns and drops the rest"
    (let* ((state (make-matrix-state 6 10 :random-state (sb-ext:seed-random-state 12)))
           (before (subseq (matrix-state-columns state) 0 3))
           (resized (matrix-resize state 3 10)))
      (with-soft-assertions
        (expect (= (matrix-state-width resized) 3) :to-be-truthy)
        (expect (equalp (matrix-state-columns resized) before) :to-be-truthy))))

  (it "changing only the height leaves every column's fields untouched"
    (let* ((state (make-matrix-state 5 10 :random-state (sb-ext:seed-random-state 13)))
           (before (matrix-state-columns state))
           (resized (matrix-resize state 5 20)))
      (with-soft-assertions
        (expect (= (matrix-state-height resized) 20) :to-be-truthy)
        (expect (equalp (matrix-state-columns resized) before) :to-be-truthy))))

  (it "resizes fixed-height old-style buffers with their mode intact"
    (let* ((state (make-matrix-state 5 10 :old-style-p t
                                     :random-state (sb-ext:seed-random-state 63)))
           (resized (matrix-resize state 7 14)))
      (expect (matrix-state-old-style-p resized) :to-be-truthy)
      (expect (every (lambda (column)
                       (and (old-style-column-p column)
                            (= (length (old-style-column-glyphs column)) 14)
                            (= (length (old-style-column-glyph-bold-p column)) 14)))
                     (matrix-state-columns resized))
              :to-be-truthy)))

  (it "reflows reproducibly: growing twice from the same seed yields identical new columns"
    (let* ((state-1 (matrix-resize
                      (make-matrix-state 3 10 :random-state (sb-ext:seed-random-state 21)) 6 10))
           (state-2 (matrix-resize
                      (make-matrix-state 3 10 :random-state (sb-ext:seed-random-state 21)) 6 10)))
      (expect (equalp (matrix-state-columns state-1) (matrix-state-columns state-2))
              :to-be-truthy)))

  (it-each ((0 4) (4 -1))
      "signals INVALID-DIMENSIONS for a new width ~A height ~A"
      (new-width new-height)
    (let ((state (make-matrix-state 4 4 :random-state (sb-ext:seed-random-state 14))))
      (expect (signals invalid-dimensions (matrix-resize state new-width new-height))
              :to-be-truthy)))

  (it-property "always yields a MATRIX-STATE of exactly the requested new dimensions, for any
valid starting and target size"
      ((width (gen-integer :min 1 :max 40))
       (height (gen-integer :min 1 :max 40))
       (new-width (gen-integer :min 1 :max 40))
       (new-height (gen-integer :min 1 :max 40)))
    (let* ((state (make-matrix-state width height :random-state (sb-ext:seed-random-state 99)))
           (resized (matrix-resize state new-width new-height)))
      (expect (= (matrix-state-width resized) new-width) :to-be-truthy)
      (expect (= (matrix-state-height resized) new-height) :to-be-truthy)
      (expect (= (length (matrix-state-columns resized)) new-width) :to-be-truthy))))
