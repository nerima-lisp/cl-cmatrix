;;;; src/render.lisp
;;;;
;;;; Draws a MATRIX-STATE's current frame onto a CL-TTY-KIT screen: the head
;;;; of each column is bold in its color scheme's head color, and every row
;;;; behind it fades from the scheme's bright color toward its dark color as
;;;; it gets further from the head. MATRIX-CELL-STYLE computes that per-cell
;;;; style in isolation (so it is directly unit-testable); MATRIX-DRAW walks
;;;; every column and calls it.

(in-package #:cl-cmatrix)

(defun matrix-cell-style (color offset trail-length)
  "Return the CL-TTY-KIT style for a cell OFFSET rows behind its column's
head (0 = the head itself) out of TRAIL-LENGTH total lit rows, under the
named color scheme COLOR. The head (OFFSET 0) is bold in COLOR's head RGB;
every other row blends COLOR's bright RGB toward its dark RGB by
OFFSET / (TRAIL-LENGTH - 1), mapped to the nearest xterm 256-color index via
CL-TTY-KIT:RGB-TO-256 -- the bright-head/dimming-trail effect the terminal's
256-color palette makes possible without true-color support."
  (if (zerop offset)
      (make-style :bold (style-fg (apply #'rgb-to-256 (color-scheme-head-rgb color))))
      (let* ((ratio (/ offset (max 1 (1- trail-length))))
             (rgb (blend-colors (color-scheme-bright-rgb color)
                                 (color-scheme-dark-rgb color)
                                 ratio)))
        (make-style (style-fg (apply #'rgb-to-256 rgb))))))

(defun %matrix-draw-column (screen x column height color)
  (let ((head (column-head column))
        (length (column-length column))
        (glyphs (column-glyphs column)))
    (loop for offset fixnum from 0 below length
          for row = (- head offset)
          while (>= row 0)
          when (< row height)
            do (screen-put-cell screen x row (svref glyphs (mod row length))
                                 :style (matrix-cell-style color offset length)))))

(defun matrix-draw (screen state)
  "Draw every column of STATE's current frame onto SCREEN, a CL-TTY-KIT
SCREEN at least STATE's WIDTH by HEIGHT. Cells outside every column's
currently lit trail are left untouched, so callers that want a clean frame
each tick should SCREEN-CLEAR (or CL-TTY-KIT:RENDERER-CLEAR) first. Returns
SCREEN."
  (let ((height (matrix-state-height state))
        (color (matrix-state-color state)))
    (loop for x fixnum below (matrix-state-width state)
          for column = (svref (matrix-state-columns state) x)
          do (%matrix-draw-column screen x column height color)))
  screen)
