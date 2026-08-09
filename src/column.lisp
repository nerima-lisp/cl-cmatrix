;;;; src/column.lisp
;;;;
;;;; One stream position, modelled exactly the way upstream cmatrix 2.0
;;;; models it: not as a falling head with a trail behind it, but as a column
;;;; of independent CELLS that a scan rewrites in place each advance. There
;;;; is no "head row" to move; a head is wherever the scan decided to plant
;;;; one this frame, recorded in the HEADS bit vector.
;;;;
;;;; CELLS has HEIGHT+1 entries. Index 0 is an OFF-SCREEN staging row -- it
;;;; is never drawn, and exists only so the spawn test has somewhere to hold
;;;; the "a new stream may start here" marker. Internal rows 1..HEIGHT draw
;;;; at screen rows 0..HEIGHT-1 in new style; old style instead draws
;;;; internal rows 0..HEIGHT-1 at screen rows 0..HEIGHT-1, which is why both
;;;; modes share one buffer rather than needing two structures.
;;;;
;;;; A cell holds one of: :EMPTY (upstream -1, "nothing has ever been here"),
;;;; :SPACE (upstream ' ', "a stream passed through and left"), :HEAD-MARKER
;;;; (upstream 0, old style only), :PIPE (upstream 1, old style only), or a
;;;; CHARACTER. :EMPTY and :SPACE are DISTINCT and must stay that way: the
;;;; spawn test is literally `cells[0] == :EMPTY and cells[1] == :SPACE`, so
;;;; collapsing them into a single "blank" would not error anywhere -- it
;;;; would silently arm every column's spawn on the wrong frame.
;;;;
;;;; Every function here is functional: an advance returns a fresh COLUMN and
;;;; never mutates its argument, and randomness always comes from the
;;;; injected RANDOM-STATE, never *RANDOM-STATE*. The deterministic test
;;;; suite depends on both properties.

(in-package #:cl-cmatrix)

(defstruct (column (:constructor %make-column))
  "One column of upstream cmatrix's character matrix. CELLS and HEADS are
parallel HEIGHT+1 element buffers indexed by internal row (see this file's
header for the row mapping and the cell vocabulary); HEADS bit I is 1 when
CELLS I is the bright head of a stream. LENGTH is the stream length this
column's scan is currently growing toward, SPACES is how many blank advances
remain before the next stream may spawn, and UPDATE is the async threshold
the shared cycling counter must exceed for this column to advance at all."
  (cells #() :type simple-vector)
  (heads #* :type simple-bit-vector)
  (length +min-trail-length+ :type fixnum)
  (spaces 0 :type fixnum)
  (update 1 :type fixnum))

(defun column-cell-at (column row)
  "Return the cell COLUMN holds at internal ROW, or :EMPTY when ROW is
outside the buffer. See this file's header for what a cell value may be and
how internal rows map onto screen rows."
  (let ((cells (column-cells column)))
    (if (and (<= 0 row) (< row (length cells)))
        (svref cells row)
        :empty)))

(defun column-head-p (column row)
  "True when COLUMN's cell at internal ROW is the bright head of a stream.
Rows outside the buffer are never heads."
  (let ((heads (column-heads column)))
    (and (<= 0 row) (< row (length heads)) (= 1 (sbit heads row)))))

(defun %blank-cell-p (cell)
  "True for the two blank cell states, :EMPTY and :SPACE. Upstream's own
scan tests `val == ' ' || val == -1` in exactly these places; the two remain
distinct everywhere else because only :SPACE arms a spawn."
  (or (eq cell :empty) (eq cell :space)))

(defun %random-trail-length (height random-state)
  "Draw a stream length, upstream's `rand() % (LINES - 3) + 3`. The MAX
guards the degenerate case where HEIGHT is at or below +MIN-TRAIL-LENGTH+,
which upstream cannot reach on a real terminal but the unit tests do."
  (+ +min-trail-length+
     (random (max 1 (- height +min-trail-length+)) random-state)))

(defun %repaint-character-cells (cells glyphs random-state)
  "Return a copy of CELLS with every CHARACTER cell redrawn from GLYPHS.
The keyword cell states are left alone, so repainting never disturbs which
rows are lit -- only which character each lit row shows."
  (let ((result (copy-seq cells)))
    (dotimes (row (length result) result)
      (when (characterp (svref result row))
        (setf (svref result row) (random-glyph glyphs random-state))))))

(defun %spawn-column (glyphs random-state height)
  "Return a freshly initialised COLUMN, upstream's `var_init` for one column.
Every cell starts :EMPTY except internal row 1, which starts :SPACE: that is
upstream's explicitly commented \"sentinel value for creation of new
objects\", and it is what lets the very first advance spawn a stream. GLYPHS
is accepted for signature symmetry with the advance functions; upstream
plants no characters at init either."
  (declare (ignore glyphs))
  (let ((cells (make-array (1+ height) :initial-element :empty))
        (heads (make-array (1+ height) :element-type 'bit :initial-element 0)))
    (setf (svref cells 1) :space)
    (%make-column :cells cells
                  :heads heads
                  :length (%random-trail-length height random-state)
                  :spaces (1+ (random height random-state))
                  :update (1+ (random +max-update-threshold+ random-state)))))

(defun %advance-column (column glyphs random-state height &key change-glyphs-p)
  "Advance COLUMN one frame under upstream's new-style scrolling, returning a
new COLUMN. Two phases, matching cmatrix.c 601-656 exactly.

First the spawn test. When the staging row is :EMPTY and the row below it is
:SPACE, either one more blank frame is consumed (SPACES counts down) or a new
stream is planted in the staging row with a freshly drawn LENGTH and SPACES.

Then the segment scan. Each maximal run of non-blank cells is a stream: the
scan clears the run's head bits, plants a new character with a head bit one
row past the run's bottom (which is how a stream appears to fall without
anything being shifted), and blanks the run's top row once the stream has
reached its full LENGTH -- or immediately, for every stream after the first
in this column, which is what stops already-settled segments from growing.
A run that reaches the bottom of the buffer loses its top row and the scan
stops.

CHANGE-GLYPHS-P is ours, not upstream's: it repaints every character cell
after the scan, so the whole column shimmers instead of only its heads."
  (let ((cells (copy-seq (column-cells column)))
        (heads (copy-seq (column-heads column)))
        (length (column-length column))
        (spaces (column-spaces column)))
    (when (and (eq (svref cells 0) :empty) (eq (svref cells 1) :space))
      (if (plusp spaces)
          (decf spaces)
          (setf length (%random-trail-length height random-state)
                (svref cells 0) (random-glyph glyphs random-state)
                spaces (1+ (random height random-state)))))
    (let ((row 0)
          (first-segment-done nil))
      (block scan
        (loop
          (loop while (and (<= row height) (%blank-cell-p (svref cells row)))
                do (incf row))
          (when (> row height) (return-from scan))
          (let ((top row)
                (run 0))
            (loop while (and (<= row height)
                             (not (%blank-cell-p (svref cells row))))
                  do (setf (sbit heads row) 0)
                     (incf row)
                     (incf run))
            (when (> row height)
              (setf (svref cells top) :space)
              (return-from scan))
            (setf (svref cells row) (random-glyph glyphs random-state)
                  (sbit heads row) 1)
            (when (or (> run length) first-segment-done)
              (setf (svref cells top) :space
                    (svref cells 0) :empty))
            (setf first-segment-done t)
            (incf row)))))
    (%make-column :cells (if change-glyphs-p
                            (%repaint-character-cells cells glyphs random-state)
                            cells)
                  :heads heads
                  :length length
                  :spaces spaces
                  :update (column-update column))))

(defun %advance-old-style-column (column glyphs random-state height
                                  &key change-glyphs-p)
  "Advance COLUMN one frame under upstream's old-style scrolling (cmatrix.c
569-598), returning a new COLUMN. Here the whole buffer really is shifted
down one row and only the top row is generated, so the character that decides
the new top row is the one that just moved out of it -- upstream reads it as
`matrix[1][j]` AFTER the shift, which is the same cell.

The roll is drawn unconditionally before the branch, exactly as upstream
does, so the random stream advances the same amount on every frame regardless
of which branch is taken.

DELIBERATE DIVERGENCE FROM UPSTREAM, and a bug fix rather than a style
choice: upstream never assigns `is_head` anywhere in old-style mode, so its
head-rendering branch reads whichever bytes `malloc` happened to return.
Its own comment at the `matrix[0][j].val = 0` line -- \"whether head of next
collumn of chars has a white 'head' on it\" -- says what was intended, so we
set the head bit when we plant a :HEAD-MARKER and clear it otherwise."
  (let* ((cells (copy-seq (column-cells column)))
         (heads (copy-seq (column-heads column)))
         (spaces (column-spaces column))
         (glyph-count (length glyphs))
         (roll (random (+ glyph-count 8) random-state))
         (previous nil))
    (loop for row from (1- height) downto 1
          do (setf (svref cells row) (svref cells (1- row))
                   (sbit heads row) (sbit heads (1- row))))
    ;; Read the deciding cell AFTER the shift and at index 1, exactly where
    ;; upstream reads it. For any HEIGHT above 1 that is the cell which just
    ;; left the top row; at HEIGHT 1 the shift is a no-op and upstream reads
    ;; the untouched row, so deferring the read keeps even that degenerate
    ;; case faithful.
    (setf previous (svref cells 1)
          (sbit heads 0) 0)
    (cond
      ((eq previous :head-marker)
       (setf (svref cells 0) :pipe))
      ((%blank-cell-p previous)
       (if (plusp spaces)
           (setf (svref cells 0) :space
                 spaces (1- spaces))
           (progn
             (if (= 1 (random 3 random-state))
                 (setf (svref cells 0) :head-marker
                       (sbit heads 0) 1)
                 (setf (svref cells 0) (random-glyph glyphs random-state)))
             (setf spaces (1+ (random height random-state))))))
      ((and (> roll glyph-count) (not (eq previous :pipe)))
       (setf (svref cells 0) :space))
      (t
       (setf (svref cells 0) (random-glyph glyphs random-state))))
    (%make-column :cells (if change-glyphs-p
                            (%repaint-character-cells cells glyphs random-state)
                            cells)
                  :heads heads
                  :length (column-length column)
                  :spaces spaces
                  :update (column-update column))))

(defun %advance-matrix-column (column glyphs random-state height
                               &key old-style-p change-glyphs-p)
  "Advance COLUMN by one frame in whichever scrolling mode OLD-STYLE-P
selects. Both modes operate on the same COLUMN structure -- upstream keeps
one matrix for both, and so do we -- so this is a dispatch on the requested
mode, never on the shape of the data."
  (if old-style-p
      (%advance-old-style-column column glyphs random-state height
                                 :change-glyphs-p change-glyphs-p)
      (%advance-column column glyphs random-state height
                       :change-glyphs-p change-glyphs-p)))

(defun %column-with-glyphs (column glyphs random-state)
  "Return COLUMN with every character cell redrawn from GLYPHS. Positions,
head bits and timing are preserved, so a runtime charset toggle changes what
the animation shows without resetting where it is."
  (%make-column :cells (%repaint-character-cells (column-cells column)
                                                 glyphs random-state)
                :heads (copy-seq (column-heads column))
                :length (column-length column)
                :spaces (column-spaces column)
                :update (column-update column)))

(defun %resize-column (column height)
  "Return COLUMN reflowed to a HEIGHT+1 element buffer, keeping the rows that
remain visible and padding newly exposed rows with :EMPTY.

This deliberately does NOT do what upstream does. Upstream calls `var_init()`
on resize, wiping every column back to its initial state; we keep the running
animation and only reflow it, because a terminal resize that blanks the
screen is worse than one that reflows. LENGTH and SPACES are re-derived by
clamping rather than redrawing, since this function takes no random state and
must stay pure -- a stream longer than the new screen would otherwise never
finish growing."
  (let* ((old-cells (column-cells column))
         (old-heads (column-heads column))
         (size (1+ height))
         (cells (make-array size :initial-element :empty))
         (heads (make-array size :element-type 'bit :initial-element 0)))
    (dotimes (row (min size (length old-cells)))
      (setf (svref cells row) (svref old-cells row)
            (sbit heads row) (sbit old-heads row)))
    (%make-column :cells cells
                  :heads heads
                  :length (max +min-trail-length+
                               (min (column-length column) height))
                  :spaces (min (column-spaces column) height)
                  :update (column-update column))))
