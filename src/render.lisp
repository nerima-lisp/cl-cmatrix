;;;; src/render.lisp
;;;;
;;;; Draws a MATRIX-STATE's current frame onto a CL-TTY-KIT screen: the head
;;;; of each column is bold in its color scheme's head color, and every row
;;;; behind it fades from the scheme's bright color toward its dark color as
;;;; it gets further from the head. MATRIX-CELL-STYLE computes that per-cell
;;;; style in isolation (so it is directly unit-testable); MATRIX-DRAW walks
;;;; every column and calls it, all of them inside one CL-TTY-KIT:
;;;; WITH-SCREEN-BATCH so the many per-cell writes a full frame makes coalesce
;;;; into a single dirty-tracking generation instead of one per cell.
;;;; MATRIX-DRAW is also where a MATRIX-STATE COLOR of :RAINBOW gets resolved
;;;; to a real per-column scheme -- MATRIX-CELL-STYLE itself never sees
;;;; :RAINBOW, only a concrete name.

(in-package #:cl-cmatrix)

(defun matrix-cell-style (color offset trail-length &optional bold)
  "Return the CL-TTY-KIT style for a cell OFFSET rows behind its column's
head (0 = the head itself) out of TRAIL-LENGTH total lit rows, under the
named color scheme COLOR (a real registered scheme, never :RAINBOW -- see
MATRIX-DRAW for that resolution). The head (OFFSET 0) is always bold in
COLOR's head RGB; every other row blends COLOR's bright RGB toward its dark
RGB by OFFSET / (TRAIL-LENGTH - 1), mapped to the nearest xterm 256-color
index via CL-TTY-KIT:RGB-TO-256 -- the bright-head/dimming-trail effect the
terminal's 256-color palette makes possible without true-color support. BOLD,
when true, renders that trail row bold too, not only the head."
  (if (zerop offset)
      (make-style :bold (style-fg (apply #'rgb-to-256 (color-scheme-head-rgb color))))
      (let* ((ratio (/ offset (max 1 (1- trail-length))))
             (rgb (blend-colors (color-scheme-bright-rgb color)
                                 (color-scheme-dark-rgb color)
                                 ratio))
             (fg (style-fg (apply #'rgb-to-256 rgb))))
        (if bold (make-style :bold fg) (make-style fg)))))

(defun %matrix-style-vector (color trail-length bold cache)
  (let ((length-cache (or (gethash color cache)
                          (setf (gethash color cache)
                                (make-hash-table)))))
    (or (gethash trail-length length-cache)
        (setf (gethash trail-length length-cache)
              (let ((styles (make-array trail-length)))
                (dotimes (offset trail-length styles)
                  (setf (svref styles offset)
                        (matrix-cell-style color offset trail-length bold))))))))

(defun %matrix-draw-column (screen x column height styles)
  (let ((head (column-head column))
        (length (column-length column))
        (glyphs (column-glyphs column)))
    (declare (type fixnum head length height))
    (loop for offset fixnum from 0 below length
          for row fixnum = head then (1- row)
          for glyph-index fixnum = (mod head length)
            then (if (zerop glyph-index) (1- length) (1- glyph-index))
          while (>= row 0)
            when (< row height)
            do (screen-put-cell screen x row (svref glyphs glyph-index)
                                 :style (svref styles offset)))))

(defun %column-color (x color rainbow-schemes)
  "Resolve the real color scheme column X draws with: COLOR itself, unless
COLOR is :RAINBOW, in which case each column index cycles through
RAINBOW-SCHEMES (LIST-COLOR-SCHEMES' own order) so adjacent columns fall in
visibly different colors."
  (if rainbow-schemes
      (nth (mod x (length rainbow-schemes)) rainbow-schemes)
      color))

(defun matrix-draw (screen state)
  "Draw every column of STATE's current frame onto SCREEN, a CL-TTY-KIT
SCREEN at least STATE's WIDTH by HEIGHT. Cells outside every column's
currently lit trail are left untouched, so callers that want a clean frame
each tick should SCREEN-CLEAR (or CL-TTY-KIT:RENDERER-CLEAR) first. When
STATE's COLOR is :RAINBOW, each column is resolved to a different real
scheme by column index rather than all sharing one. Returns SCREEN."
  (let* ((height (matrix-state-height state))
         (color (matrix-state-color state))
         (bold (matrix-state-bold state))
         (rainbow-schemes (when (eq color :rainbow) (list-color-schemes)))
         (style-cache (make-hash-table :test #'eq)))
    (with-screen-batch (screen)
      (loop for x fixnum below (matrix-state-width state)
            for column = (svref (matrix-state-columns state) x)
            for column-color = (%column-color x color rainbow-schemes)
            do (%matrix-draw-column
                screen x column height
                (%matrix-style-vector column-color (column-length column)
                                      bold style-cache))))))
