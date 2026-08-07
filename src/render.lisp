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

(defun matrix-cell-style (color offset trail-length &optional bold no-bold)
  "Return the CL-TTY-KIT style for a cell OFFSET rows behind its column's
head (0 = the head itself) out of TRAIL-LENGTH total lit rows, under the
named color scheme COLOR (a real registered scheme, never :RAINBOW -- see
MATRIX-DRAW for that resolution). The head (OFFSET 0) is bold in COLOR's
head RGB unless NO-BOLD is true; every other row blends COLOR's bright RGB
toward its dark RGB by OFFSET / (TRAIL-LENGTH - 1), mapped to the nearest
xterm 256-color index via CL-TTY-KIT:RGB-TO-256. BOLD, when true, renders
that trail row bold too, unless NO-BOLD is true."
  (if (zerop offset)
      (let ((fg (style-fg (apply #'rgb-to-256 (color-scheme-head-rgb color)))))
        (if no-bold (make-style fg) (make-style :bold fg)))
      (let* ((ratio (/ offset (max 1 (1- trail-length))))
             (rgb (blend-colors (color-scheme-bright-rgb color)
                                 (color-scheme-dark-rgb color)
                                 ratio))
             (fg (style-fg (apply #'rgb-to-256 rgb))))
        (if (and bold (not no-bold))
            (make-style :bold fg)
            (make-style fg)))))

(defun %matrix-style-vector (color trail-length bold cache &optional no-bold)
  "Return the memoized vector of TRAIL-LENGTH styles a column of that length
draws with under COLOR and BOLD, computing it via MATRIX-CELL-STYLE on the
first request. CACHE is a RENDER-CONTEXT's STYLE-CACHE slot, so entries
persist for that renderer's whole lifetime rather than only the current frame.
BOLD and NO-BOLD are part of the key (color -> trail-length -> bold ->
no-bold -> styles) because the cache outlives individual frames and both
flags affect MATRIX-CELL-STYLE."
  (let* ((length-cache (or (gethash color cache)
                           (setf (gethash color cache)
                                 (make-hash-table))))
         (bold-cache (or (gethash trail-length length-cache)
                         (setf (gethash trail-length length-cache)
                               (make-hash-table))))
         (no-bold-cache (or (gethash bold bold-cache)
                            (setf (gethash bold bold-cache)
                                  (make-hash-table)))))
    (or (gethash no-bold no-bold-cache)
        (setf (gethash no-bold no-bold-cache)
              (let ((styles (make-array trail-length)))
                (dotimes (offset trail-length styles)
                  (setf (svref styles offset)
                        (matrix-cell-style color offset trail-length bold
                                           no-bold))))))))

(defun %random-bold-cell-p (x row tick)
  "Return a deterministic, frame-varying bold decision for a trail cell."
  (oddp (+ (* 3 x) (* 5 row) tick)))

(defun %matrix-draw-column (screen x column height styles
                            &key bold-styles random-bold-p tick
                              all-bold-p partial-bold-p no-bold-p
                              glyph-bold-p)
  (let* ((head (column-head column))
         (length (column-length column))
         (glyphs (column-glyphs column))
         (glyph-bold-p (or glyph-bold-p (column-glyph-bold-p column))))
    (declare (type fixnum head length height))
    (loop for offset fixnum from 0 below length
          for row fixnum = head then (1- row)
          for glyph-index fixnum = (mod head length)
            then (if (zerop glyph-index) (1- length) (1- glyph-index))
          while (>= row 0)
            when (< row height)
            do (let* ((partial-bold-cell-p
                        (and partial-bold-p
                             (if (< glyph-index (length glyph-bold-p))
                                 (svref glyph-bold-p glyph-index)
                                 (evenp (char-code
                                         (svref glyphs glyph-index))))))
                      (bold-cell-p
                        (and (not no-bold-p)
                             (or all-bold-p
                                 partial-bold-cell-p
                                 (and random-bold-p
                                      (or (zerop offset)
                                          (%random-bold-cell-p x row tick)))))))
                 (screen-put-cell
                  screen x row (svref glyphs glyph-index)
                  :style (if bold-cell-p
                             (svref bold-styles offset)
                             (svref styles offset)))))))

(defun %column-color (x color rainbow-schemes)
  "Resolve the real color scheme column X draws with. Branches on
RAINBOW-SCHEMES, not on COLOR: when RAINBOW-SCHEMES is non-NIL, column index
X cycles through it (in LIST-COLOR-SCHEMES' own order) so adjacent columns
fall in visibly different colors; when it is NIL, COLOR is returned as-is.
Callers are expected to pass a non-NIL RAINBOW-SCHEMES only when COLOR is
:RAINBOW -- MATRIX-DRAW, the sole caller, does exactly that."
  (if rainbow-schemes
      (nth (mod x (length rainbow-schemes)) rainbow-schemes)
      color))

(defun matrix-draw (screen state context)
  "Draw STATE on SCREEN using CONTEXT's cached terminal styles."
  (declare)
  (let* ((height (matrix-state-height state))
         (color (matrix-state-color state))
         (no-bold-p (matrix-state-no-bold-p state))
         (all-bold-p
           (and (matrix-state-bold state)
                (not (matrix-state-partial-bold-p state))))
         (partial-bold-p (matrix-state-partial-bold-p state))
         (random-bold-p (matrix-state-random-bold-p state))
         (tick (matrix-state-tick state))
         (rainbow-schemes (matrix-state-rainbow-schemes state))
         (style-cache (render-context-style-cache context)))
    (labels ((draw-old-style-column
                 (screen x column height styles bold-styles random-bold-p tick
                         all-bold-p partial-bold-p no-bold-p)
               (let* ((glyphs (old-style-column-glyphs column))
                      (glyph-bold-p (old-style-column-glyph-bold-p column))
                      (limit (min height (length glyphs))))
                 (declare (type fixnum height limit))
                 (loop for row fixnum from 0 below limit
                       for glyph = (svref glyphs row)
                       when glyph
                       do (let* ((partial-bold-cell-p
                                   (and partial-bold-p
                                        (svref glyph-bold-p row)))
                                 (bold-cell-p
                                   (and (not no-bold-p)
                                        (or all-bold-p
                                            partial-bold-cell-p
                                            (and random-bold-p
                                                 (%random-bold-cell-p
                                                  x row tick))))))
                            (screen-put-cell
                             screen x row glyph
                             :style (if bold-cell-p
                                        (svref bold-styles row)
                                        (svref styles row))))))))
      (with-screen-batch (screen)
        (loop for x fixnum below (matrix-state-width state)
              for column = (aref (matrix-state-columns state) x)
              for column-color =
                (if (and rainbow-schemes
                         (plusp (length rainbow-schemes)))
                    (aref rainbow-schemes
                          (mod x (length rainbow-schemes)))
                    color)
              do (let* ((old-style-column-mode-p
                           (old-style-column-p column))
                        (trail-length
                          (if old-style-column-mode-p
                              height
                              (column-length column)))
                        (styles
                          (%matrix-style-vector column-color trail-length
                                                all-bold-p style-cache
                                                no-bold-p))
                        (bold-styles
                          (when (or all-bold-p partial-bold-p random-bold-p)
                            (%matrix-style-vector column-color trail-length t
                                                  style-cache))))
                   (if old-style-column-mode-p
                       (draw-old-style-column
                        screen x column height styles bold-styles random-bold-p
                        tick all-bold-p partial-bold-p no-bold-p)
                       (%matrix-draw-column
                        screen x column height styles
                        :bold-styles bold-styles
                        :all-bold-p all-bold-p
                        :partial-bold-p partial-bold-p
                        :no-bold-p no-bold-p
                        :glyph-bold-p (column-glyph-bold-p column)
                        :random-bold-p random-bold-p
                        :tick tick))))
      screen))))

(defun matrix-draw-message (screen width height message)
  "Draw MESSAGE centered on SCREEN and clipped to WIDTH."
  (when (and message (plusp (length message)))
    (let* ((text (if (> (length message) width)
                     (subseq message 0 width)
                     message))
           (x (max 0 (floor (- width (length text)) 2)))
           (y (floor height 2))
           (style (make-style :bold (style-fg (rgb-to-256 255 255 255)))))
      (loop for index fixnum below (length text)
            do (screen-put-cell screen (+ x index) y (char text index)
                                :style style))))
  screen)
