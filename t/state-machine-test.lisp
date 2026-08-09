(in-package #:cl-cmatrix/test)

(defun %state-machine-step (state event)
  (ecase (first event)
    (:advance (matrix-advance state))
    (:resize (matrix-resize state (second event) (third event)))))

(defun %valid-column-p (column height)
  "True when COLUMN is shaped for a HEIGHT-row matrix: parallel HEIGHT+1
buffers -- internal row 0 is the off-screen staging row, so a column carries
one more cell than the screen shows (src/column.lisp:9-14) -- and a stream
LENGTH no shorter than the floor every spawn and every reflow keeps it above."
  (let ((cells (column-cells column))
        (heads (column-heads column)))
    (and (= (length cells) (1+ height))
         (= (length heads) (length cells))
         (>= (column-length column) +min-trail-length+))))

(defun %valid-matrix-state-p (state)
  "True when STATE is internally consistent. The column count is
(MATRIX-STATE-COLUMN-COUNT WIDTH) and deliberately not WIDTH: upstream scans
`for (j = 0; j <= COLS - 1; j += 2)`, so we hold one COLUMN per animated
screen column and draw column I at screen x = 2I (src/state.lisp:10-14)."
  (and (typep state 'cl-cmatrix::matrix-state)
       (plusp (matrix-state-width state))
       (plusp (matrix-state-height state))
       (= (length (matrix-state-columns state))
          (matrix-state-column-count (matrix-state-width state)))
       (every (lambda (column)
                (%valid-column-p column (matrix-state-height state)))
              (matrix-state-columns state))))

(describe "matrix state machine"
  (it-property "keeps every reachable state valid: (CEILING WIDTH 2) columns over HEIGHT+1 rows"
      ((trace (gen-state-machine
               (make-matrix-state
                4 3
                :random-state (sb-ext:seed-random-state 90))
               #'%state-machine-step
               (gen-member '((:advance)
                             (:resize 2 2)
                             (:resize 5 4)
                             (:resize 1 3)))
               :min-length 1
               :max-length 12)))
    (expect (every #'%valid-matrix-state-p (getf trace :states))
     :to-be-truthy)))
