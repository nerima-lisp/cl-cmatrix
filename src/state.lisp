;;;; src/state.lisp
;;;;
;;;; MATRIX-STATE bundles a WIDTH x HEIGHT grid of COLUMNs with the shared
;;;; inputs that govern how they fall: the injected RANDOM-STATE (see
;;;; glyphs.lisp and column.lisp -- this is the single source of randomness
;;;; every column's timing and glyph choice is drawn from, which is what
;;;; makes a whole run reproducible from a fixed seed), the fall SPEED
;;;; multiplier, the COLOR scheme name, and the GLYPHS set columns draw from.

(in-package #:cl-cmatrix)

(defstruct (matrix-state (:constructor %make-matrix-state) (:copier %copy-matrix-state))
  "The full state of a matrix-rain animation at one tick. COLUMNS is a
SIMPLE-VECTOR of WIDTH COLUMN structures, one per screen column. BOLD, when
true, renders every lit row bold; PARTIAL-BOLD-P selects the upstream
character-parity subset, and NO-BOLD-P disables bold styling. OLD-STYLE-P
selects the fixed-height visible-buffer scrolling mode. ASYNCP controls
whether each column keeps its own fall interval; RANDOM-BOLD-P and
CHANGE-GLYPHS-P enable the corresponding runtime effects. RAINBOW-SCHEMES
caches the color registry as a simple vector when COLOR is :RAINBOW."
  (width 0 :type fixnum)
  (height 0 :type fixnum)
  (columns #() :type simple-vector)
  (random-state nil :type random-state)
  (speed +default-speed+ :type real)
  (color +default-color+ :type keyword)
  (rainbow-schemes nil :type (or null simple-vector))
  (glyphs +default-glyphs+ :type simple-vector)
  (bold +default-bold+ :type boolean)
  (partial-bold-p nil :type boolean)
  (no-bold-p nil :type boolean)
  (old-style-p nil :type boolean)
  (asyncp t :type boolean)
  (random-bold-p nil :type boolean)
  (change-glyphs-p nil :type boolean)
  (tick 0 :type fixnum))

(defun %assert-dimensions (width height)
  (unless (and (typep width '(integer 1 *)) (typep height '(integer 1 *)))
    (error 'invalid-dimensions :width width :height height)))

(defun %assert-speed (speed)
  (unless (and (realp speed) (plusp speed))
    (error 'invalid-speed :speed speed)))

(defun %copy-random-state (random-state)
  (check-type random-state random-state)
  (make-random-state random-state))

(defun make-matrix-state (width height &key (speed +default-speed+) (color +default-color+)
                                             (glyphs +default-glyphs+)
                                             (bold +default-bold+)
                                             (partial-bold-p nil)
                                             (no-bold-p nil)
                                             (old-style-p nil)
                                             (asyncp t)
                                             (random-bold-p nil)
                                             (change-glyphs-p nil)
                                             (random-state (make-random-state t)))
  "Create a MATRIX-STATE of WIDTH by HEIGHT columns, each independently
spawned from RANDOM-STATE (an actual CL random state object -- inject one
built by, e.g., SB-EXT:SEED-RANDOM-STATE for a reproducible run; the default
is a nondeterministic one, matching CL:MAKE-RANDOM-STATE's own T argument).
The supplied random state is copied, so constructing a state never mutates
caller-owned randomness.

SPEED is a positive real fall-speed multiplier (default 1; larger values
fall faster) and COLOR names one of LIST-COLOR-SCHEMES, or :RAINBOW to draw
each column from a different scheme (default :GREEN). GLYPHS is the
non-empty character set columns draw from (default +DEFAULT-GLYPHS+). BOLD
enables all-bold mode, PARTIAL-BOLD-P enables upstream-compatible partial
bolding, and NO-BOLD-P disables bold styling. OLD-STYLE-P selects the
fixed-height visible-buffer scrolling mode. ASYNCP, when false, gives every
column the same fall interval. RANDOM-BOLD-P changes the bold cells
deterministically from the matrix tick, and CHANGE-GLYPHS-P repaints each
trail ring whenever a column advances.

Signals INVALID-DIMENSIONS when WIDTH or HEIGHT is not a positive integer,
INVALID-SPEED when SPEED is not a positive real, and UNKNOWN-COLOR-SCHEME
when COLOR is neither a registered scheme nor :RAINBOW."
  (%assert-dimensions width height)
  (%assert-speed speed)
  ;; Signals UNKNOWN-COLOR-SCHEME up front, before spawning columns.
  (unless (color-choice-p color) (error 'unknown-color-scheme :name color))
  (let ((random-state (%copy-random-state random-state)))
    (%make-matrix-state
      :width width :height height :random-state random-state :speed speed
      :color color
      :rainbow-schemes (and (eq color :rainbow)
                            (coerce (list-color-schemes) 'simple-vector))
      :glyphs glyphs :bold bold
      :partial-bold-p partial-bold-p :no-bold-p no-bold-p
      :old-style-p old-style-p :asyncp asyncp
      :random-bold-p random-bold-p :change-glyphs-p change-glyphs-p :tick 0
      :columns (coerce (loop repeat width
                              collect (if old-style-p
                                          (%spawn-old-style-column
                                           glyphs random-state speed height
                                           :interval
                                           (unless asyncp
                                             (%synchronous-interval-for-speed
                                              speed)))
                                          (%spawn-column
                                           glyphs random-state speed
                                           :interval
                                           (unless asyncp
                                             (%synchronous-interval-for-speed
                                              speed)))))
                        'simple-vector))))

(defun %column-with-glyphs (column glyphs random-state)
  "Return COLUMN with its visible glyphs freshly painted from GLYPHS.

The positional and timing fields are preserved so a runtime charset toggle
does not reset the animation; only the characters already held by the trail
change."
  (if (old-style-column-p column)
      (%old-style-column-with-glyphs column glyphs random-state)
      (multiple-value-bind (new-glyphs new-glyph-bold-p)
          (%make-glyph-ring (column-length column) glyphs random-state)
        (%make-column :interval (column-interval column)
                      :counter (column-counter column)
                      :head (column-head column)
                      :length (column-length column)
                      :glyphs new-glyphs
                      :glyph-bold-p new-glyph-bold-p))))

(defun %matrix-state-with-glyphs (state glyphs)
  "Return STATE with every existing column painted from GLYPHS.

The copied random state is advanced while painting the new rings, leaving
the caller-owned state immutable and keeping the next transition
reproducible."
  (let* ((random-state (%copy-random-state (matrix-state-random-state state)))
         (old-columns (matrix-state-columns state))
         (new-columns (make-array (length old-columns)))
         (new-state (%copy-matrix-state state)))
    (dotimes (index (length old-columns))
      (setf (svref new-columns index)
            (%column-with-glyphs (svref old-columns index)
                                 glyphs random-state)))
    (setf (matrix-state-columns new-state) new-columns
          (matrix-state-glyphs new-state) glyphs
          (matrix-state-random-state new-state) random-state)
    new-state))

(defun %matrix-advance-serial (state)
  "Advance every column of STATE by one tick, returning a new MATRIX-STATE.
Pure given an already-positioned RANDOM-STATE: calling this TICKS times
against a MATRIX-STATE built with a fixed seed produces byte-identical
output on every run, which is what the deterministic tests in t/ pin down.
Does not mutate STATE or its RANDOM-STATE object; the returned state owns the
advanced copy of the random state."
  (let* ((glyphs (matrix-state-glyphs state))
         (random-state (%copy-random-state (matrix-state-random-state state)))
         (speed (matrix-state-speed state))
         (height (matrix-state-height state))
         (asyncp (matrix-state-asyncp state))
         (change-glyphs-p (matrix-state-change-glyphs-p state))
         (old-columns (matrix-state-columns state))
         (new-columns (make-array (length old-columns))))
    (dotimes (index (length old-columns))
      (setf (svref new-columns index)
            (%advance-matrix-column (svref old-columns index)
                                    glyphs random-state speed height
                                    :asyncp asyncp
                                    :change-glyphs-p change-glyphs-p)))
    (let ((new-state (%copy-matrix-state state)))
      (setf (matrix-state-columns new-state) new-columns
            (matrix-state-random-state new-state) random-state
            (matrix-state-tick new-state) (1+ (matrix-state-tick state)))
      new-state)))

(defun matrix-resize (state new-width new-height)
  "Return a new MATRIX-STATE reflowed to NEW-WIDTH by NEW-HEIGHT. Columns
[0, MIN(NEW-WIDTH, old width)) are kept exactly as they were in normal mode;
a widened matrix spawns fresh columns -- drawn from a copy of STATE's
RANDOM-STATE, so a resize mid-run is exactly as reproducible as everything
else -- for newly exposed columns, and a narrowed matrix drops the rightmost
columns. OLD-STYLE-P columns are resized to the new visible height while
preserving rows that remain visible.

Signals INVALID-DIMENSIONS when NEW-WIDTH or NEW-HEIGHT is not a positive
integer."
  (%assert-dimensions new-width new-height)
  (let* ((old-columns (matrix-state-columns state))
         (old-width (length old-columns))
         (old-height (matrix-state-height state))
         (glyphs (matrix-state-glyphs state))
         (random-state (%copy-random-state (matrix-state-random-state state)))
         (speed (matrix-state-speed state))
         (asyncp (matrix-state-asyncp state))
         (old-style-p (matrix-state-old-style-p state))
         (base-columns
           (if (and old-style-p (/= old-height new-height))
               (map 'simple-vector
                    (lambda (column)
                      (%resize-old-style-column column new-height))
                    old-columns)
               old-columns))
         (new-columns
           (cond
             ((= new-width old-width) base-columns)
             ((< new-width old-width) (subseq base-columns 0 new-width))
             (t (concatenate 'simple-vector
                             base-columns
                             (loop repeat (- new-width old-width)
                                   collect (if old-style-p
                                               (%spawn-old-style-column
                                                glyphs random-state speed new-height
                                                :interval
                                                (unless asyncp
                                                  (%synchronous-interval-for-speed
                                                   speed)))
                                               (%spawn-column
                                                glyphs random-state speed
                                                :interval
                                                (unless asyncp
                                                  (%synchronous-interval-for-speed
                                                   speed)))))))))
         (new-state (%copy-matrix-state state)))
    (setf (matrix-state-width new-state) new-width
          (matrix-state-height new-state) new-height
          (matrix-state-columns new-state) new-columns
          (matrix-state-random-state new-state) random-state)
    new-state))
