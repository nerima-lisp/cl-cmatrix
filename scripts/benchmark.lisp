;;;; Reproducible, informational microbenchmarks for cl-cmatrix.
(require "asdf")

(defconstant +benchmark-seed+ 20260805)

(defconstant +nanoseconds-per-second+ 1000000000d0)

(defun project-root ()
  (merge-pathnames "../" *load-truename*))

(asdf:load-asd (merge-pathnames "cl-cmatrix.asd" (project-root)))

(asdf:load-system "cl-cmatrix")

(defstruct (options (:constructor make-options)) (width 80 :type fixnum)
  (height 24 :type fixnum)
  (ticks 2000 :type fixnum)
  (warmup 250 :type fixnum)
  (samples 7 :type fixnum))

(defun print-usage (&optional (stream *standard-output*))
  (format
    stream
    "Usage: sbcl --script scripts/benchmark.lisp [OPTIONS]~%\
~%\
Informational benchmark; it does not enforce a performance threshold.~%\
~%\
Options:~%\
  --width N    Matrix width (1..1000, default 80)~%\
  --height N   Matrix height (1..500, default 24)~%\
  --ticks N    Measured ticks per sample (1..1000000, default 2000)~%\
  --warmup N   Warmup ticks per workload (0..100000, default 250)~%\
  --samples N  Number of samples (2..101, default 7)~%\
  --help       Show this help~%"))

(defun parse-bounded-integer (text option minimum maximum)
  (let ((value
        (handler-case (parse-integer text :junk-allowed nil)
          (error ()
            (error "~A requires an integer, got ~S" option text)))))
    (unless (<= minimum value maximum)
      (error "~A must be between ~:D and ~:D, got ~:D" option minimum maximum value))
    value))

(defun require-option-value (arguments option)
  (unless (rest arguments)
    (error "~A requires a value" option))
  (second arguments))

(defun parse-options (arguments)
  (let ((options (make-options)))
    (loop while arguments
          for option = (first arguments)
          do (cond
        ((string= option "--help")
          (print-usage)
          (sb-ext:exit :code 0))
        ((string= option "--width")
          (setf (options-width options) (parse-bounded-integer (require-option-value arguments option) option 1 1000))
          (setf arguments (rest arguments)))
        ((string= option "--height")
          (setf (options-height options) (parse-bounded-integer (require-option-value arguments option) option 1 500))
          (setf arguments (rest arguments)))
        ((string= option "--ticks")
          (setf (options-ticks options) (parse-bounded-integer (require-option-value arguments option) option 1 1000000))
          (setf arguments (rest arguments)))
        ((string= option "--warmup")
          (setf (options-warmup options) (parse-bounded-integer (require-option-value arguments option) option 0 100000))
          (setf arguments (rest arguments)))
        ((string= option "--samples")
          (setf (options-samples options) (parse-bounded-integer (require-option-value arguments option) option 2 101))
          (setf arguments (rest arguments)))
        (t (error "Unknown option ~S" option))) (setf arguments (rest arguments)))
    options))

(defun make-benchmark-state (options)
  (cl-cmatrix:make-matrix-state
    (options-width options)
    (options-height options)
    :random-state
    (sb-ext:seed-random-state +benchmark-seed+)))

(defun make-runner (workload options)
  (let ((state (make-benchmark-state options)))
    (ecase workload
      (:advance
       (lambda (ticks)
         (dotimes (index ticks)
           (declare (ignore index))
           (setf state (cl-cmatrix:matrix-advance state)))
         (values state nil)))
      (:advance-and-dirty-render
       (let* ((renderer
                (cl-tty-kit:make-renderer
                 (options-width options)
                 (options-height options)))
              (context (cl-cmatrix:make-render-context)))
         (lambda (ticks)
           (dotimes (index ticks)
             (declare (ignore index))
             (setf state (cl-cmatrix:matrix-advance state))
             (cl-tty-kit:renderer-clear renderer)
             (cl-cmatrix:matrix-draw
              (cl-tty-kit:renderer-screen renderer)
              state
              context))
           (values state (cl-tty-kit:renderer-screen renderer)))))
      (:advance-dirty-render-and-ansi-encode
       (let* ((renderer
                (cl-tty-kit:make-renderer
                 (options-width options)
                 (options-height options)))
              (run-state
                (cl-cmatrix:make-run-state
                 :matrix state
                 :renderer renderer)))
         (lambda (ticks)
           (dotimes (index ticks)
             (declare (ignore index))
             (cl-cmatrix:run-state-advance run-state)
             (cl-cmatrix:run-state-render run-state))
           (values
            (cl-cmatrix:run-state-matrix run-state)
            (cl-tty-kit:renderer-screen renderer))))))))

(defun measure-sample (workload options)
  (let ((runner (make-runner workload options))
        (ticks (options-ticks options)))
    (funcall runner (options-warmup options))
    (sb-ext:gc :full t)
    (let ((bytes-before (sb-ext:get-bytes-consed))
          (time-before (get-internal-real-time)))
      (multiple-value-bind (state screen)
          (funcall runner ticks)
        (let ((time-after (get-internal-real-time))
              (bytes-after (sb-ext:get-bytes-consed)))
          (assert
           (= (cl-cmatrix:matrix-state-tick state)
              (+ (options-warmup options) ticks))
           ()
           "Benchmark runner completed an unexpected number of ticks.")
          (when screen
            (assert
             (loop for x below (options-width options)
                   thereis
                   (loop for y below (options-height options)
                         thereis
                         (not (char= (cl-tty-kit:cell-char
                                     (cl-tty-kit:screen-cell screen x y))
                                    #\Space))))
             ()
             "Dirty-render benchmark produced an empty screen."))
          (cons
           (/ (* (- time-after time-before) +nanoseconds-per-second+)
              internal-time-units-per-second
              ticks)
           (/ (- bytes-after bytes-before) (float ticks 1d0))))))))

(defun median (values)
  (let* ((sorted (sort (copy-list values) #'<))
         (count (length sorted))
         (middle (floor count 2)))
    (if (oddp count) (nth middle sorted)
      (/ (+ (nth (1- middle) sorted) (nth middle sorted)) 2d0))))



(defun report-workload (label workload options)
  (let* ((results
          (loop repeat (options-samples options)
                collect (measure-sample workload options)))
         (nanoseconds (mapcar #'car results))
         (bytes-consed (mapcar #'cdr results))
         (median-nanoseconds (median nanoseconds))
         (median-bytes-consed (median bytes-consed)))
    (flet ((relative-spread (values median)
             (if (zerop median)
                 0d0
                 (* 100d0
                    (/ (- (reduce #'max values) (reduce #'min values))
                       median)))))
      (format t "~&~A~%" label)
      (loop for result in results
            for sample from 1
            do (format
                t
                "  sample ~2D: ~12:D ns/tick, ~12:D bytes-consed/tick~%"
                sample
                (round (car result))
                (round (cdr result))))
      (format
       t
       "  median:    ~12:D ns/tick, ~12:D bytes-consed/tick~%"
       (round median-nanoseconds)
       (round median-bytes-consed))
      (format
       t
       "  min/max:   ~12:D/~:D ns/tick, ~12:D/~:D bytes-consed/tick~%"
       (round (reduce #'min nanoseconds))
       (round (reduce #'max nanoseconds))
       (round (reduce #'min bytes-consed))
       (round (reduce #'max bytes-consed)))
      (format
       t
       "  spread:    ~12,2F% ns/tick, ~12,2F% bytes-consed/tick~%"
       (relative-spread nanoseconds median-nanoseconds)
       (relative-spread bytes-consed median-bytes-consed)))))
(defun main ()
  (let ((options (parse-options (rest sb-ext:*posix-argv*))))
    (format
      t
      "cl-cmatrix reproducible benchmark (SBCL ~A)~%"
      (lisp-implementation-version))
    (format
      t
      "seed=~:D, matrix=~:Dx~:D, warmup=~:D ticks, ~:D samples x ~:D ticks~%"
      +benchmark-seed+
      (options-width options)
      (options-height options)
      (options-warmup options)
      (options-samples options)
      (options-ticks options))
    (format t "Results are informational; no pass/fail threshold is applied.~%")
    (report-workload "matrix advance" :advance options)
    (report-workload
      "matrix advance + dirty render"
      :advance-and-dirty-render
      options)
    (report-workload
      "matrix advance + dirty render + ANSI encode"
      :advance-dirty-render-and-ansi-encode
      options)))

(handler-case (main)
  (error (condition)
    (format *error-output* "benchmark: ~A~%~%" condition)
    (print-usage *error-output*)
    (sb-ext:exit :code 2)))
