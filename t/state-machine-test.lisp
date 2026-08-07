(in-package #:cl-cmatrix/test)

(defun %state-machine-step (state event)
  (ecase (first event)
    (:advance (matrix-advance state))
    (:resize (matrix-resize state (second event) (third event)))))

(defun %valid-matrix-state-p (state)
  (and (typep state 'cl-cmatrix::matrix-state)
       (plusp (matrix-state-width state))
       (plusp (matrix-state-height state))
       (= (length (matrix-state-columns state))
          (matrix-state-width state))))

(describe "matrix state machine"
  (it-property "keeps every reachable state valid"
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
