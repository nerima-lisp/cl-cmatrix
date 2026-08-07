;;;; t/concurrent-test.lisp

(in-package #:cl-cmatrix/test)

(defun %run-parallel-ticks (width height ticks &key (seed 42) (speed 1)
                                                      (workers 4) (old-style-p nil))
  (with-executor (executor :size workers :name "cl-cmatrix-test")
    (let ((state (make-matrix-state width height :speed speed
                                     :old-style-p old-style-p
                                     :random-state (sb-ext:seed-random-state seed))))
      (dotimes (i ticks state)
        (setf state (matrix-advance state :executor executor
                                    :workers workers))))))

(defun %parallel-column-snapshot (state)
  (map 'list (lambda (column)
               (if (old-style-column-p column)
                   (list :old-style
                         (coerce (old-style-column-glyphs column) 'list)
                         (coerce (old-style-column-glyph-bold-p column) 'list)
                         (old-style-column-spaces column))
                   (list (column-head column)
                         (column-length column)
                         (column-interval column)
                         (column-counter column)
                         (coerce (column-glyphs column) 'list))))
       (matrix-state-columns state)))

(describe "concurrent matrix advance"
  (it "is reproducible across independent executor runs"
    (let ((snapshot-1 (%parallel-column-snapshot
                       (%run-parallel-ticks 2048 12 20)))
          (snapshot-2 (%parallel-column-snapshot
                       (%run-parallel-ticks 2048 12 20))))
      (expect (equal snapshot-1 snapshot-2) :to-be-truthy)))

  (it "is reproducible across independent executor runs in old-style mode"
    (let ((snapshot-1 (%parallel-column-snapshot
                       (%run-parallel-ticks 2048 12 20 :old-style-p t)))
          (snapshot-2 (%parallel-column-snapshot
                       (%run-parallel-ticks 2048 12 20 :old-style-p t))))
      (expect (equal snapshot-1 snapshot-2) :to-be-truthy)))

  (it "does not mutate the input columns in the executor path"
    (with-executor (executor :size 4 :name "cl-cmatrix-test")
      (let* ((state (make-matrix-state 2048 12
                                       :random-state (sb-ext:seed-random-state 9)))
             (columns-before (matrix-state-columns state))
             (advanced (matrix-advance state :executor executor)))
        (expect (eq (matrix-state-columns state) columns-before) :to-be-truthy)
        (expect (= (matrix-state-tick advanced) 1) :to-be-truthy))))

  (it "uses the serial transition for narrow matrices"
    (with-executor (executor :size 4 :name "cl-cmatrix-test")
      (let* ((state (make-matrix-state 8 12
                                       :random-state (sb-ext:seed-random-state 11)))
             (parallel-state (matrix-advance state :executor executor))
             (serial-state (matrix-advance state)))
        (expect (equal (%parallel-column-snapshot parallel-state)
                       (%parallel-column-snapshot serial-state))
                :to-be-truthy))))

  (it "rejects a non-positive worker count before scheduling"
    (expect
     (signals type-error
       (matrix-advance
        (make-matrix-state
         8 12
         :random-state (sb-ext:seed-random-state 15))
        :workers 0))
     :to-be-truthy))

  (it "keeps the executor on run-state for every tick"
    (with-executor (executor :size 4 :name "cl-cmatrix-test")
      (let ((run-state
              (make-run-state
               :matrix (make-matrix-state 2048 12
                                           :random-state (sb-ext:seed-random-state 13))
               :renderer (make-renderer 2048 12)
               :input-poller (lambda (state event) (declare (ignore state event)))
               :workers 2
               :executor executor)))
        (expect (= (run-state-workers run-state) 2) :to-be-truthy)
        (expect (eq (run-state-executor run-state) executor) :to-be-truthy)
        (run-state-advance run-state)
        (expect (= (matrix-state-tick (run-state-matrix run-state)) 1)
                :to-be-truthy)))))
