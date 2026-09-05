

(defconstant +minimum-expression-percent+ 86)
(defconstant +minimum-branch-percent+ 93)

(defun script-directory ()
  (make-pathname :name nil
                 :type nil
                 :defaults (or *load-truename*
                               *compile-file-truename*
                               (error "Unable to determine the script location"))))

(let* ((root
        (host-kit:truenamize (merge-pathnames #P"../" (script-directory))))
       (src (merge-pathnames #P"src/" root))
       (tests-passed (cl-weave:run-all :reporter :spec))
       (statistics (cl-weave:coverage-statistics :include-pathnames (list src)))
       (expression-percent (* 100.0 (/ (getf statistics :expression-covered)
                                        (max 1 (getf statistics :expression-total)))))
       (branch-percent (* 100.0 (/ (getf statistics :branch-covered)
                                    (max 1 (getf statistics :branch-total))))))
  (format t "~&cl-cmatrix coverage: ~,2F% expression (floor ~D%), ~,2F% branch (floor ~D%).~%"
          expression-percent +minimum-expression-percent+
          branch-percent +minimum-branch-percent+)
  (finish-output *standard-output*)
  (if (and tests-passed
           (>= expression-percent +minimum-expression-percent+)
           (>= branch-percent +minimum-branch-percent+))
      (host-kit:quit 0)
      (progn
        (format *error-output*
                "~&cl-cmatrix coverage/test gate failed (tests-passed=~A).~%"
                tests-passed)
        (finish-output *error-output*)
        (host-kit:quit 1))))
