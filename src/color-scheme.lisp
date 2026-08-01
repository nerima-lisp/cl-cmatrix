;;;; src/color-scheme.lisp
;;;;
;;;; Named color schemes for the --color CLI flag and MAKE-MATRIX-STATE.
;;;; Each scheme is three RGB triples: the head character's color (bright
;;;; white in every scheme, the classic look), the color the trail is
;;;; brightest at just behind the head, and the color it dims toward at its
;;;; tail (black in every scheme, so a trail fades into the terminal
;;;; background). MATRIX-CELL-STYLE in render.lisp maps these through
;;;; CL-TTY-KIT:RGB-TO-256 to actual xterm 256-color indices.

(in-package #:cl-cmatrix)

(defparameter +color-schemes+
  (list (cons :green (list '(255 255 255) '(0 255 70) '(0 0 0)))
        (cons :cyan (list '(255 255 255) '(0 230 230) '(0 0 0)))
        (cons :red (list '(255 255 255) '(230 40 40) '(0 0 0)))
        (cons :blue (list '(255 255 255) '(70 130 230) '(0 0 0)))
        (cons :magenta (list '(255 255 255) '(230 70 230) '(0 0 0)))
        (cons :yellow (list '(255 255 255) '(220 220 40) '(0 0 0)))
        (cons :white (list '(255 255 255) '(190 190 190) '(0 0 0))))
  "Maps a color scheme name to a (HEAD-RGB BRIGHT-RGB DARK-RGB) list of three
RGB triples. :GREEN is the classic look and the default.")

(defun list-color-schemes ()
  "Return every registered color scheme name, in +COLOR-SCHEMES+'s definition
order."
  (mapcar #'car +color-schemes+))

(defun color-scheme-p (name)
  "True when NAME is a registered color scheme."
  (and (assoc name +color-schemes+) t))

(defun %color-scheme-rgbs (name)
  (or (cdr (assoc name +color-schemes+))
      (error 'unknown-color-scheme :name name)))

(defun color-scheme-head-rgb (name)
  "Return NAME's head-character RGB triple. Signals UNKNOWN-COLOR-SCHEME when
NAME is not registered."
  (first (%color-scheme-rgbs name)))

(defun color-scheme-bright-rgb (name)
  "Return NAME's trail RGB triple at its brightest (just behind the head).
Signals UNKNOWN-COLOR-SCHEME when NAME is not registered."
  (second (%color-scheme-rgbs name)))

(defun color-scheme-dark-rgb (name)
  "Return the RGB triple NAME's trail dims toward at its tail. Signals
UNKNOWN-COLOR-SCHEME when NAME is not registered."
  (third (%color-scheme-rgbs name)))
