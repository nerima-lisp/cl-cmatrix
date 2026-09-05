
(in-package #:cl-cmatrix)

(define-condition cl-cmatrix-error (error)
  ()
  (:documentation "Base condition for every error CL-CMATRIX signals."))

(defmacro define-cl-cmatrix-condition (name (&rest slot-specs)
                                        (report-control &rest report-arg-forms) documentation)
  "Define NAME as a CL-CMATRIX-ERROR subclass. Each element of SLOT-SPECS is
(SLOT-NAME READER-NAME); SLOT-NAME becomes both the slot and its keyword
:INITARG, and READER-NAME its :READER. REPORT-CONTROL and REPORT-ARG-FORMS
build the :REPORT clause's FORMAT call, with CONDITION bound to the signaled
condition. DOCUMENTATION becomes the condition's :DOCUMENTATION.

Every condition CL-CMATRIX signals besides the CL-CMATRIX-ERROR base itself
is defined through this macro, so adding one is a single form rather than
hand-written :REPORT boilerplate."
  `(define-condition ,name (cl-cmatrix-error)
     (,@(loop for (slot reader) in slot-specs
              collect `(,slot :initarg ,(intern (symbol-name slot) :keyword) :reader ,reader)))
     (:report (lambda (condition stream)
                (declare (ignorable condition))
                (format stream ,report-control ,@report-arg-forms)))
     (:documentation ,documentation)))

(define-cl-cmatrix-condition invalid-dimensions
    ((width invalid-dimensions-width) (height invalid-dimensions-height))
    ("Matrix WIDTH and HEIGHT must be positive integers, got width ~S height ~S."
     (invalid-dimensions-width condition) (invalid-dimensions-height condition))
  "Signaled by MAKE-MATRIX-STATE or MATRIX-RESIZE when WIDTH or
HEIGHT is not a positive integer.")

(define-cl-cmatrix-condition invalid-glyphs
    ((glyphs invalid-glyphs-glyphs))
    ("GLYPHS must be a non-empty SIMPLE-VECTOR of characters, got ~S."
     (invalid-glyphs-glyphs condition))
  "Signaled by MAKE-MATRIX-STATE when GLYPHS is not a non-empty
SIMPLE-VECTOR every element of which is a CHARACTER. CHARSET-GLYPHS returns a
vector that always satisfies this, so a caller reaching a glyph set by name
can never see it.")

(define-cl-cmatrix-condition invalid-speed
    ((speed invalid-speed-speed))
    ("Fall SPEED must be a positive real number, got ~S." (invalid-speed-speed condition))
  "Signaled by MAKE-MATRIX-STATE when SPEED is not a positive
real number.")

(define-cl-cmatrix-condition invalid-fps
    ((fps invalid-fps-fps))
    ("FPS must be a positive real number, got ~S." (invalid-fps-fps condition))
  "Signaled by RUN-MATRIX when FPS is not a positive real number.")

(define-cl-cmatrix-condition invalid-update-delay
    ((delay invalid-update-delay-delay))
    ("Update delay must be an integer from 0 through 10, got ~S."
     (invalid-update-delay-delay condition))
  "Signaled by RUN-MATRIX when the upstream-compatible update delay is
outside the inclusive 0 through 10 range.")

(define-cl-cmatrix-condition unknown-color-scheme
    ((name unknown-color-scheme-name))
    ("Unknown color scheme ~S. Known schemes: ~{~A~^, ~}."
     (unknown-color-scheme-name condition) (list-color-schemes))
  "Signaled by MAKE-MATRIX-STATE when COLOR names no scheme
registered in +COLOR-SCHEMES+, and is not :RAINBOW. LIST-COLOR-SCHEMES names
every valid registered scheme.")

(define-cl-cmatrix-condition unknown-charset
    ((name unknown-charset-name))
    ("Unknown charset ~S. Known charsets: ~{~A~^, ~}."
     (unknown-charset-name condition) (list-charsets))
  "Signaled by CHARSET-GLYPHS when NAME names no charset registered
in +CHARSETS+. LIST-CHARSETS names every valid choice.")
