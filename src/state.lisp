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
SIMPLE-VECTOR of WIDTH COLUMN structures, one per screen column."
  (width 0 :type fixnum)
  (height 0 :type fixnum)
  (columns #() :type simple-vector)
  (random-state nil :type random-state)
  (speed 1 :type real)
  (color :green :type keyword)
  (glyphs +default-glyphs+ :type simple-vector)
  (tick 0 :type fixnum))

(defun %assert-dimensions (width height)
  (unless (and (typep width '(integer 1 *)) (typep height '(integer 1 *)))
    (error 'invalid-dimensions :width width :height height)))

(defun %assert-speed (speed)
  (unless (and (realp speed) (plusp speed))
    (error 'invalid-speed :speed speed)))

(defun make-matrix-state (width height &key (speed 1) (color :green)
                                             (glyphs +default-glyphs+)
                                             (random-state (make-random-state t)))
  "Create a MATRIX-STATE of WIDTH by HEIGHT columns, each independently
spawned from RANDOM-STATE (an actual CL random state object -- inject one
built by, e.g., SB-EXT:SEED-RANDOM-STATE for a reproducible run; the default
is a nondeterministic one, matching CL:MAKE-RANDOM-STATE's own T argument).

SPEED is a positive real fall-speed multiplier (default 1; larger values
fall faster) and COLOR names one of LIST-COLOR-SCHEMES (default :GREEN).
GLYPHS is the non-empty character set columns draw from (default
+DEFAULT-GLYPHS+).

Signals INVALID-DIMENSIONS when WIDTH or HEIGHT is not a positive integer,
INVALID-SPEED when SPEED is not a positive real, and UNKNOWN-COLOR-SCHEME
when COLOR names no registered scheme."
  (%assert-dimensions width height)
  (%assert-speed speed)
  (%color-scheme-rgbs color) ; signals UNKNOWN-COLOR-SCHEME up front, before spawning columns
  (%make-matrix-state
    :width width :height height :random-state random-state :speed speed
    :color color :glyphs glyphs :tick 0
    :columns (coerce (loop repeat width
                            collect (%spawn-column glyphs random-state speed))
                      'simple-vector)))

(defun matrix-advance (state)
  "Advance every column of STATE by one tick, returning a new MATRIX-STATE.
Pure given an already-positioned RANDOM-STATE: calling this TICKS times
against a MATRIX-STATE built with a fixed seed produces byte-identical
output on every run, which is what the deterministic tests in t/ pin down.
Does not mutate STATE's COLUMNS vector; STATE's RANDOM-STATE object is
mutated in place by the random draws, as every CL random-state normally is."
  (let* ((glyphs (matrix-state-glyphs state))
         (random-state (matrix-state-random-state state))
         (speed (matrix-state-speed state))
         (height (matrix-state-height state))
         (new-columns (map 'simple-vector
                            (lambda (column)
                              (%advance-column column glyphs random-state speed height))
                            (matrix-state-columns state)))
         (new-state (%copy-matrix-state state)))
    (setf (matrix-state-columns new-state) new-columns
          (matrix-state-tick new-state) (1+ (matrix-state-tick state)))
    new-state))

(defun matrix-resize (state new-width new-height)
  "Return a new MATRIX-STATE reflowed to NEW-WIDTH by NEW-HEIGHT. Columns
[0, MIN(NEW-WIDTH, old width)) are kept exactly as they were; a widened
matrix spawns fresh columns -- drawn from STATE's own RANDOM-STATE, so a
resize mid-run is exactly as reproducible as everything else -- for the
newly exposed ones, and a narrowed matrix simply drops the rightmost
columns. A height change touches no column: MATRIX-DRAW already clips rows
outside [0, NEW-HEIGHT), and a column whose head has scrolled past the new,
shorter height respawns on its own next advance, the same as it would from
reaching the old height.

Signals INVALID-DIMENSIONS when NEW-WIDTH or NEW-HEIGHT is not a positive
integer."
  (%assert-dimensions new-width new-height)
  (let* ((old-columns (matrix-state-columns state))
         (old-width (length old-columns))
         (glyphs (matrix-state-glyphs state))
         (random-state (matrix-state-random-state state))
         (speed (matrix-state-speed state))
         (new-columns
           (cond
             ((= new-width old-width) old-columns)
             ((< new-width old-width) (subseq old-columns 0 new-width))
             (t (concatenate 'simple-vector
                              old-columns
                              (loop repeat (- new-width old-width)
                                    collect (%spawn-column glyphs random-state speed))))))
         (new-state (%copy-matrix-state state)))
    (setf (matrix-state-width new-state) new-width
          (matrix-state-height new-state) new-height
          (matrix-state-columns new-state) new-columns)
    new-state))
