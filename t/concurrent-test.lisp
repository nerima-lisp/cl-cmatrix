;;;; t/concurrent-test.lisp
;;;;
;;;; The executor path (src/concurrent.lisp) is deterministic but NOT
;;;; stream-identical to the serial one: each chunk draws from its own child
;;;; random state, so the two paths disagree about which glyphs a moving
;;;; column ends up showing. What they must agree about is WHICH columns move,
;;;; because both apply the same %COLUMN-ADVANCES-P gate to the same cycling
;;;; ASYNC-COUNT. That agreement is the central property here, and it is
;;;; checked against a gate these specs derive themselves from the exported
;;;; COLUMN-UPDATE thresholds -- never against whatever either path happened
;;;; to do, which would make the two implementations each other's oracle.
;;;;
;;;; Two traps everything below is built around. A column the gate holds back
;;;; is carried over by identity, and an advance always allocates a fresh
;;;; COLUMN, so EQ is an exact test of "did this column advance this frame".
;;;; And a freshly spawned column's first advances consume no randomness at
;;;; all -- nothing has spawned yet, so the scan finds only blank cells --
;;;; which means a cold comparison of the two paths passes without either path
;;;; drawing a single number. Every spec here warms its state up first.

(in-package #:cl-cmatrix/test)

(defparameter +parallel-test-width+ cl-cmatrix::+parallel-column-threshold+
  "The narrowest matrix MATRIX-ADVANCE will hand to an executor. Taken from
the threshold itself so these specs cannot drift onto the serial path if it
is ever retuned; the width is halved into columns, since column I draws at
screen x = 2I.")

(defun %parallel-column-snapshot (column)
  "Every field a COLUMN carries, in a form EQUAL can compare."
  (list (coerce (column-cells column) 'list)
        (coerce (column-heads column) 'list)
        (column-length column)
        (column-spaces column)
        (column-update column)))

(defun %parallel-state-snapshot (state)
  (map 'list #'%parallel-column-snapshot (matrix-state-columns state)))

(defun %parallel-warm-state (&key (seed 42) (ticks 8) (async-count 2)
                                  (asyncp t) (old-style-p nil)
                                  (width +parallel-test-width+))
  "A MATRIX-STATE advanced serially TICKS times, then parked at ASYNC-COUNT.

The warm-up is load-bearing: a column that has not spawned a stream yet draws
no randomness when it advances, so a cold state compares two frames in which
neither path touched its random state. Parking ASYNC-COUNT fixes which gate
the next frame runs -- the default 2 cycles to 3, admitting the columns whose
UPDATE threshold is 1 or 2 and holding back the threshold-3 ones, so the next
frame moves a proper, non-empty subset."
  (let ((state (make-matrix-state width 12
                                  :asyncp asyncp
                                  :old-style-p old-style-p
                                  :random-state (sb-ext:seed-random-state seed))))
    (dotimes (tick ticks)
      (setf state (matrix-advance state)))
    (setf (matrix-state-async-count state) async-count)
    state))

(defun %parallel-advanced-indices (before after)
  "The column indices that actually moved between BEFORE and AFTER.

A gated-out column is carried over by identity and an advance always
allocates, so EQ decides this exactly -- see this file's header."
  (let ((old (matrix-state-columns before))
        (new (matrix-state-columns after)))
    (loop for index below (length old)
          unless (eq (svref old index) (svref new index))
            collect index)))

(defun %parallel-gated-indices (state)
  "The column indices STATE's async gate admits on its next frame.

Derived from the exported UPDATE thresholds and +ASYNC-COUNT-CYCLE+ rather
than from either transition path, so it is an independent reference for what
both paths have to do."
  (let* ((columns (matrix-state-columns state))
         (next-count (1+ (mod (matrix-state-async-count state)
                              +async-count-cycle+))))
    (loop for index below (length columns)
          when (or (not (matrix-state-asyncp state))
                   (> next-count (column-update (svref columns index))))
            collect index)))

(defun %parallel-differing-columns (left right)
  "How many column positions hold structurally different COLUMNs."
  (count nil (map 'list #'equal
                  (%parallel-state-snapshot left)
                  (%parallel-state-snapshot right))))

(defun %run-parallel-ticks (ticks &key (seed 42) (workers 4) (old-style-p nil))
  (with-executor (executor :size 4 :name "cl-cmatrix-test")
    (let ((state (make-matrix-state +parallel-test-width+ 12
                                    :old-style-p old-style-p
                                    :random-state (sb-ext:seed-random-state seed))))
      (dotimes (tick ticks state)
        (setf state (matrix-advance state :executor executor :workers workers))))))

(describe "concurrent matrix advance"
  (it "moves exactly the columns the async gate admits, as the serial path does"
    (let* ((state (%parallel-warm-state))
           (expected (%parallel-gated-indices state))
           (column-count (length (matrix-state-columns state))))
      (with-executor (executor :size 4 :name "cl-cmatrix-test")
        (let ((parallel (matrix-advance state :executor executor :workers 4))
              (serial (matrix-advance state)))
          ;; Non-vacuity first: agreeing on the moved set proves nothing on a
          ;; frame that moves everything or nothing, so pin that this frame
          ;; holds some columns back and lets others through.
          (expect (plusp (length expected)) :to-be-truthy)
          (expect (< (length expected) column-count) :to-be-truthy)
          (expect (%parallel-advanced-indices state parallel) :to-equal expected)
          (expect (%parallel-advanced-indices state serial) :to-equal expected)))))

  (it "moves every column with ASYNCP off, in both paths"
    ;; Proves the EQ oracle above can report a full set as well as a partial
    ;; one -- without this the 'proper subset' result could be a constant.
    (let* ((state (%parallel-warm-state :seed 7 :asyncp nil))
           (column-count (length (matrix-state-columns state))))
      (with-executor (executor :size 4 :name "cl-cmatrix-test")
        (let ((parallel (matrix-advance state :executor executor :workers 4))
              (serial (matrix-advance state)))
          (expect (length (%parallel-advanced-indices state parallel))
                  :to-equal column-count)
          (expect (length (%parallel-advanced-indices state serial))
                  :to-equal column-count)))))

  (it "draws from different random streams than the serial path"
    ;; The gate agreeing would agree just as well if MATRIX-ADVANCE had
    ;; quietly fallen back to serial, so this is what proves the executor
    ;; path ran: the chunk-local child states make the moved columns diverge.
    (let ((state (%parallel-warm-state :seed 3)))
      (with-executor (executor :size 4 :name "cl-cmatrix-test")
        (let* ((parallel (matrix-advance state :executor executor :workers 4))
               (serial (matrix-advance state))
               (differing (%parallel-differing-columns parallel serial)))
          (expect (plusp differing) :to-be-truthy)
          (expect (<= differing (length (%parallel-gated-indices state)))
                  :to-be-truthy)))))

  (it-each ((1) (3) (4) (7))
      "reassembles every chunk into one full column vector with ~A workers"
      (workers)
    (let ((state (%parallel-warm-state :seed 5)))
      (with-executor (executor :size 4 :name "cl-cmatrix-test")
        (let* ((advanced (matrix-advance state :executor executor :workers workers))
               (columns (matrix-state-columns advanced)))
          ;; A chunk boundary that drops or overlaps a range leaves an unset
          ;; slot here, and a misplaced chunk shifts the moved set.
          (expect (length columns)
                  :to-equal (matrix-state-column-count (matrix-state-width state)))
          (expect (every #'column-p columns) :to-be-truthy)
          (expect (%parallel-advanced-indices state advanced)
                  :to-equal (%parallel-gated-indices state))))))

  (it "advances ASYNC-COUNT once, to the value the serial path reaches"
    (let ((state (%parallel-warm-state :seed 21)))
      (with-executor (executor :size 4 :name "cl-cmatrix-test")
        (let ((parallel (matrix-advance state :executor executor :workers 4))
              (serial (matrix-advance state)))
          ;; The parked 2 cycles to 3, once, and the input keeps its own.
          (expect (matrix-state-async-count state) :to-equal 2)
          (expect (matrix-state-async-count parallel) :to-equal 3)
          (expect (matrix-state-async-count serial) :to-equal 3)))))

  (it "leaves the input state and its columns untouched"
    (let* ((state (%parallel-warm-state :seed 9))
           (columns-before (matrix-state-columns state))
           (snapshot-before (%parallel-state-snapshot state)))
      (with-executor (executor :size 4 :name "cl-cmatrix-test")
        (let ((advanced (matrix-advance state :executor executor :workers 4)))
          (expect (eq (matrix-state-columns state) columns-before) :to-be-truthy)
          (expect (%parallel-state-snapshot state) :to-equal snapshot-before)
          (expect (matrix-state-tick advanced)
                  :to-equal (1+ (matrix-state-tick state)))))))

  (it "is reproducible across independent executor runs"
    (let ((snapshot-1 (%parallel-state-snapshot (%run-parallel-ticks 12)))
          (snapshot-2 (%parallel-state-snapshot (%run-parallel-ticks 12))))
      (expect snapshot-1 :to-equal snapshot-2)))

  (it "is reproducible across independent executor runs in old-style mode"
    (let ((snapshot-1 (%parallel-state-snapshot
                       (%run-parallel-ticks 12 :old-style-p t)))
          (snapshot-2 (%parallel-state-snapshot
                       (%run-parallel-ticks 12 :old-style-p t))))
      (expect snapshot-1 :to-equal snapshot-2)))

  (it "separates two seeds, so reproducibility is not a constant snapshot"
    (let ((snapshot-1 (%parallel-state-snapshot (%run-parallel-ticks 12 :seed 1)))
          (snapshot-2 (%parallel-state-snapshot (%run-parallel-ticks 12 :seed 2))))
      (expect (equal snapshot-1 snapshot-2) :to-be-falsy)))

  (it "uses the serial transition below the parallel width threshold"
    ;; Parked at 3 so the next gate is 4 and every column moves: a frame in
    ;; which nothing moved would make the two paths agree for free.
    (let* ((state (%parallel-warm-state :seed 11 :width 8 :async-count 3))
           (before (%parallel-state-snapshot state)))
      (with-executor (executor :size 4 :name "cl-cmatrix-test")
        (let ((parallel (matrix-advance state :executor executor :workers 4))
              (serial (matrix-advance state)))
          (expect (< (matrix-state-width state) +parallel-test-width+) :to-be-truthy)
          (expect (length (%parallel-advanced-indices state parallel))
                  :to-equal (length (matrix-state-columns state)))
          (expect (equal (%parallel-state-snapshot parallel) before) :to-be-falsy)
          (expect (%parallel-state-snapshot parallel)
                  :to-equal (%parallel-state-snapshot serial))))))

  (it "rejects a non-positive worker count before scheduling any work"
    (expect
     (signals type-error
       (matrix-advance
        (make-matrix-state 8 12 :random-state (sb-ext:seed-random-state 15))
        :workers 0))
     :to-be-truthy))

  (it "keeps the executor and worker count on RUN-STATE and advances through them"
    (with-executor (executor :size 4 :name "cl-cmatrix-test")
      (let ((run-state
              (make-run-state
               :matrix (make-matrix-state +parallel-test-width+ 12
                                          :random-state (sb-ext:seed-random-state 13))
               :renderer (make-renderer +parallel-test-width+ 12)
               :input-poller (lambda (state event) (declare (ignore state event)))
               :workers 2
               :executor executor)))
        (expect (run-state-workers run-state) :to-equal 2)
        (expect (eq (run-state-executor run-state) executor) :to-be-truthy)
        (run-state-advance run-state)
        (expect (matrix-state-tick (run-state-matrix run-state)) :to-equal 1)
        (expect (matrix-state-async-count (run-state-matrix run-state))
                :to-equal 1)))))
