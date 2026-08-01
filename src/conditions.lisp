;;;; src/conditions.lisp
;;;;
;;;; A single package-specific base condition, with every condition
;;;; CL-CMATRIX signals deriving from it, so a caller can catch every failure
;;;; this library raises with one HANDLER-CASE clause on CL-CMATRIX-ERROR.

(in-package #:cl-cmatrix)

(define-condition cl-cmatrix-error (error)
  ()
  (:documentation "Base condition for every error CL-CMATRIX signals."))

(define-condition invalid-dimensions (cl-cmatrix-error)
  ((width :initarg :width :reader invalid-dimensions-width)
   (height :initarg :height :reader invalid-dimensions-height))
  (:report (lambda (condition stream)
             (format stream "Matrix WIDTH and HEIGHT must be positive integers, got width ~S height ~S."
                     (invalid-dimensions-width condition) (invalid-dimensions-height condition))))
  (:documentation "Signaled by MAKE-MATRIX-STATE or MATRIX-RESIZE when WIDTH or
HEIGHT is not a positive integer."))

(define-condition invalid-speed (cl-cmatrix-error)
  ((speed :initarg :speed :reader invalid-speed-speed))
  (:report (lambda (condition stream)
             (format stream "Fall SPEED must be a positive real number, got ~S."
                     (invalid-speed-speed condition))))
  (:documentation "Signaled by MAKE-MATRIX-STATE when SPEED is not a positive
real number."))

(define-condition unknown-color-scheme (cl-cmatrix-error)
  ((name :initarg :name :reader unknown-color-scheme-name))
  (:report (lambda (condition stream)
             (format stream "Unknown color scheme ~S. Known schemes: ~{~A~^, ~}."
                     (unknown-color-scheme-name condition) (list-color-schemes))))
  (:documentation "Signaled by MAKE-MATRIX-STATE when COLOR names no scheme
registered in +COLOR-SCHEMES+. LIST-COLOR-SCHEMES names every valid choice."))
