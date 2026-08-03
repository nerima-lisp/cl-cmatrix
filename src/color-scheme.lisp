;;;; src/color-scheme.lisp
;;;;
;;;; Named color schemes for the --color CLI flag and MAKE-MATRIX-STATE.
;;;; Each scheme is three RGB triples: the head character's color (bright
;;;; white in every scheme, the classic look), the color the trail is
;;;; brightest at just behind the head, and the color it dims toward at its
;;;; tail (black in every scheme, so a trail fades into the terminal
;;;; background). MATRIX-CELL-STYLE in render.lisp maps these through
;;;; CL-TTY-KIT:RGB-TO-256 to actual xterm 256-color indices.
;;;;
;;;; :RAINBOW is a further --color choice, but deliberately not an entry in
;;;; +COLOR-SCHEMES+: it has no RGB triples of its own, and instead means
;;;; "resolve a real registered scheme per column" -- see MATRIX-DRAW in
;;;; render.lisp, the only place that resolution happens. COLOR-CHOICE-P is
;;;; the predicate that accepts both a real scheme name and :RAINBOW; use it,
;;;; not COLOR-SCHEME-P, to validate anything read from --color.

(in-package #:cl-cmatrix)

(defun %build-color-schemes ()
  (list (list :green '(255 255 255) '(0 255 70) '(0 0 0))
        (list :cyan '(255 255 255) '(0 230 230) '(0 0 0))
        (list :red '(255 255 255) '(230 40 40) '(0 0 0))
        (list :blue '(255 255 255) '(70 130 230) '(0 0 0))
        (list :magenta '(255 255 255) '(230 70 230) '(0 0 0))
        (list :yellow '(255 255 255) '(220 220 40) '(0 0 0))
        (list :white '(255 255 255) '(190 190 190) '(0 0 0))
        (list :purple '(255 255 255) '(150 60 230) '(0 0 0))
        (list :orange '(255 255 255) '(230 130 30) '(0 0 0))
        (list :amber '(255 255 255) '(230 180 20) '(0 0 0))
        (list :pink '(255 255 255) '(230 90 160) '(0 0 0))))

(defparameter +color-schemes+ (%build-color-schemes)
  "Maps a color scheme name to a (HEAD-RGB BRIGHT-RGB DARK-RGB) list of three
RGB triples. :GREEN is the classic look and the default.")

(define-registry-queries list-color-schemes color-scheme-p +color-schemes+)

(defun color-choice-p (name)
  "True when NAME is a valid --color value: a registered color scheme, or
:RAINBOW."
  (or (eq name :rainbow) (color-scheme-p name)))

(defun %color-scheme-rgbs (name)
  (or (cdr (assoc name +color-schemes+))
      (error 'unknown-color-scheme :name name)))

(defmacro define-color-scheme-accessor (name accessor summary)
  "Define NAME as a function of one argument NAME-ARG returning ACCESSOR
(FIRST, SECOND, or THIRD) applied to %COLOR-SCHEME-RGBS of NAME-ARG, with a
docstring built from SUMMARY (a string completing \"Return ~A.\"). Every
COLOR-SCHEME-*-RGB reader is defined through this macro, since the three
differ only in SUMMARY and which of the three RGB triples ACCESSOR selects."
  `(defun ,name (name)
     ,(format nil "Return ~A. Signals UNKNOWN-COLOR-SCHEME when NAME is not registered." summary)
     (,accessor (%color-scheme-rgbs name))))

(define-color-scheme-accessor color-scheme-head-rgb first
  "NAME's head-character RGB triple")

(define-color-scheme-accessor color-scheme-bright-rgb second
  "NAME's trail RGB triple at its brightest, just behind the head")

(define-color-scheme-accessor color-scheme-dark-rgb third
  "the RGB triple NAME's trail dims toward at its tail")
