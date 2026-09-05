
(in-package #:cl-cmatrix)

(defun matrix-cell-style (color offset trail-length &optional bold no-bold)
  "Return the CL-TTY-KIT style for a cell OFFSET rows behind its stream's
head (0 = the head itself) out of TRAIL-LENGTH total graded rows, under the
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
  "Return the memoized vector of TRAIL-LENGTH styles a stream of that length
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

(defun %lambda-glyph ()
  "Return the character upstream's -m mode substitutes for every non-head
trail character."
  (code-char #x3bb))

(defun %column-color (index color rainbow-schemes)
  "Resolve the real color scheme the column at INDEX draws with. Branches on
RAINBOW-SCHEMES, not on COLOR: when RAINBOW-SCHEMES is non-empty, INDEX
cycles through it (in LIST-COLOR-SCHEMES' own order) so adjacent columns fall
in visibly different colors; otherwise COLOR is returned as-is. MATRIX-DRAW,
the sole caller, passes a non-empty RAINBOW-SCHEMES only when COLOR is
:RAINBOW."
  (if (and rainbow-schemes (plusp (length rainbow-schemes)))
      (aref rainbow-schemes (mod index (length rainbow-schemes)))
      color))

(defun %draw-column (screen x column start end origin styles bold-styles
                     &key lambda-p all-bold-p partial-bold-p no-bold-p
                       random-bold-p tick)
  "Draw COLUMN's internal rows START..END (inclusive) at screen x, placing
internal row R at screen row R - ORIGIN. New style passes 1, HEIGHT, 1; old
style passes 0, HEIGHT-1, 0.

Cells are drawn a maximal non-blank run at a time so each cell's distance
from its stream's head end is known. A cell whose head bit is set takes
STYLES index 0 (the head style); :PIPE takes the brightest trail index;
everything else takes its clamped offset. LAMBDA-P substitutes a lambda for
non-head characters only -- upstream's is_head branch runs before its lambda
branch, so a head always shows its real character -- and partial-bold parity
always reads the STORED character's code, never the lambda's."
  (let* ((cells (column-cells column))
         (max-offset (1- (length styles)))
         (pipe-offset (min 1 max-offset))
         (lambda-glyph (and lambda-p (%lambda-glyph)))
         (row start))
    (declare (type fixnum max-offset pipe-offset row))
    (flet ((draw-cell (lit offset)
             (declare (type fixnum lit offset))
             (let* ((cell (svref cells lit))
                    (headp (column-head-p column lit))
                    (index (cond (headp 0)
                                 ((eq cell :pipe) pipe-offset)
                                 (t (min offset max-offset))))
                    (glyph (cond ((eq cell :head-marker) #\&)
                                 ((eq cell :pipe) #\|)
                                 ((and lambda-glyph (not headp)) lambda-glyph)
                                 (t cell)))
                    (boldp (and (not no-bold-p)
                                (not headp)
                                bold-styles
                                (or all-bold-p
                                    (and partial-bold-p
                                         (characterp cell)
                                         (evenp (char-code cell)))
                                    (and random-bold-p
                                         (%random-bold-cell-p x lit tick))))))
               (screen-put-cell screen x (- lit origin) glyph
                                :style (if boldp
                                           (svref bold-styles index)
                                           (svref styles index))))))
      (loop while (<= row end)
            do (if (%blank-cell-p (svref cells row))
                   (incf row)
                   (let ((bottom row))
                     (loop while (and (< bottom end)
                                      (not (%blank-cell-p
                                            (svref cells (1+ bottom)))))
                           do (incf bottom))
                     (loop for lit from row to bottom
                           do (draw-cell lit (- bottom lit)))
                     (setf row (1+ bottom))))))
    screen))

(defun matrix-draw (screen state context)
  "Draw STATE on SCREEN using CONTEXT's cached terminal styles. Column index
I is drawn at screen x = 2I; odd screen columns are left untouched, which is
upstream cmatrix's own `j += 2` scan and the largest single difference in how
the animation reads."
  (let* ((height (matrix-state-height state))
         (color (matrix-state-color state))
         (no-bold-p (matrix-state-no-bold-p state))
         (partial-bold-p (matrix-state-partial-bold-p state))
         (all-bold-p (and (matrix-state-bold state) (not partial-bold-p)))
         (random-bold-p (matrix-state-random-bold-p state))
         (old-style-p (matrix-state-old-style-p state))
         (lambda-p (matrix-state-lambda-p state))
         (tick (matrix-state-tick state))
         (rainbow-schemes (matrix-state-rainbow-schemes state))
         (style-cache (render-context-style-cache context))
         (start (if old-style-p 0 1))
         (end (if old-style-p (1- height) height))
         (origin start))
    (with-screen-batch (screen)
      (loop for index fixnum below (length (matrix-state-columns state))
            for column = (svref (matrix-state-columns state) index)
            for column-color = (%column-color index color rainbow-schemes)
            for trail-length = (max 1 (column-length column))
            do (let ((styles (%matrix-style-vector column-color trail-length
                                                   all-bold-p style-cache
                                                   no-bold-p))
                     (bold-styles
                       (when (or all-bold-p partial-bold-p random-bold-p)
                         (%matrix-style-vector column-color trail-length t
                                               style-cache))))
                 (%draw-column screen (* 2 index) column start end origin
                               styles bold-styles
                               :lambda-p lambda-p
                               :all-bold-p all-bold-p
                               :partial-bold-p partial-bold-p
                               :no-bold-p no-bold-p
                               :random-bold-p random-bold-p
                               :tick tick)))
      screen)))

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
