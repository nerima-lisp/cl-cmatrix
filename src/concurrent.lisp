(in-package #:cl-cmatrix)

(defun %parallel-random-states (random-state count)
  "Create one deterministic child RANDOM-STATE for each work chunk.

RANDOM-STATE is advanced in chunk order before any work is submitted, so
worker completion order cannot affect the next MATRIX-STATE."
  (let ((random-states (make-array count)))
    (dotimes (index count random-states)
      (setf (svref random-states index)
            (sb-ext:seed-random-state
             (random most-positive-fixnum random-state))))))

(defun %column-ranges (count worker-count)
  "Partition COUNT columns into at most WORKER-COUNT ranges."
  (let* ((chunk-count (min worker-count count))
         (chunk-size (ceiling count chunk-count)))
    (loop for start below count by chunk-size
          for index from 0
          collect (list index start (min count (+ start chunk-size))))))

(defun %matrix-advance-with-executor (state executor workers)
  "Advance STATE's columns concurrently through EXECUTOR."
  (let* ((glyphs (matrix-state-glyphs state))
         (random-state (%copy-random-state (matrix-state-random-state state)))
         (speed (matrix-state-speed state))
         (height (matrix-state-height state))
         (old-columns (matrix-state-columns state))
         (count (length old-columns))
         (ranges (%column-ranges count workers))
         (random-states (%parallel-random-states random-state (length ranges)))
         (chunks
           (executor-map
            executor
            (lambda (range)
              (let* ((chunk-index (first range))
                     (start (second range))
                     (end (third range))
                     (random-state (svref random-states chunk-index))
                     (columns (make-array (- end start))))
                (loop for index from start below end
                      for output-index from 0
                      do (setf (svref columns output-index)
                               (%advance-column (svref old-columns index)
                                                glyphs
                                                random-state
                                                speed
                                                height)))
                columns))
            ranges
            :max-in-flight (length ranges)))
         (new-columns (make-array count)))
    (loop for range in ranges
          for chunk in chunks
          do (replace new-columns chunk :start1 (second range)))
    (let ((new-state (%copy-matrix-state state)))
      (setf (matrix-state-columns new-state) new-columns
            (matrix-state-random-state new-state) random-state
            (matrix-state-tick new-state) (1+ (matrix-state-tick state)))
      new-state)))

(defun matrix-advance (state &key executor (workers +default-workers+))
  "Advance STATE, using EXECUTOR when the matrix is sufficiently wide.

When EXECUTOR is absent or STATE is narrow, preserve the serial transition
path. The parallel path is pure with respect to STATE and deterministic for a
fixed initial RANDOM-STATE. WORKERS controls the number of deterministic
column chunks; its child random streams are intentionally independent of the
serial path's random-number consumption."
  (check-type workers (integer 1 *))
  (if (and executor
           (>= (matrix-state-width state) +parallel-column-threshold+))
      (%matrix-advance-with-executor state executor workers)
      (%matrix-advance-serial state)))
