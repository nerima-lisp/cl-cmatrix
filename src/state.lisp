
(in-package #:cl-cmatrix)

(defstruct (matrix-state (:constructor %make-matrix-state) (:copier %copy-matrix-state))
  "The full state of a matrix-rain animation at one frame. COLUMNS is a
SIMPLE-VECTOR of (CEILING WIDTH 2) COLUMN structures; column I occupies
screen x = 2I and odd screen columns are never drawn. BOLD, when true,
renders every lit row bold; PARTIAL-BOLD-P selects the upstream
character-parity subset, and NO-BOLD-P disables bold styling. OLD-STYLE-P
selects upstream's old-style scrolling. LAMBDA-P is upstream's -m: a render
mode that draws every non-head character as a lambda, not a charset choice.
ASYNCP enables per-column update thresholds, gated by ASYNC-COUNT.
RANDOM-BOLD-P and CHANGE-GLYPHS-P enable the corresponding runtime effects.
RAINBOW-SCHEMES caches the color registry as a simple vector when COLOR is
:RAINBOW."
  (width 0 :type fixnum)
  (height 0 :type fixnum)
  (columns #() :type simple-vector)
  (random-state nil :type random-state)
  (color +default-color+ :type keyword)
  (rainbow-schemes nil :type (or null simple-vector))
  (glyphs +default-glyphs+ :type simple-vector)
  (bold +default-bold+ :type boolean)
  (partial-bold-p nil :type boolean)
  (no-bold-p nil :type boolean)
  (old-style-p nil :type boolean)
  (lambda-p nil :type boolean)
  (asyncp t :type boolean)
  (async-count 0 :type fixnum)
  (random-bold-p nil :type boolean)
  (change-glyphs-p nil :type boolean)
  (tick 0 :type fixnum))

(defun %assert-dimensions (width height)
  (unless (and (typep width '(integer 1 *)) (typep height '(integer 1 *)))
    (error 'invalid-dimensions :width width :height height)))

(defun %assert-glyphs (glyphs)
  "Signal INVALID-GLYPHS unless GLYPHS is a non-empty SIMPLE-VECTOR whose
every element is a CHARACTER."
  (unless (and (typep glyphs 'simple-vector)
               (plusp (length glyphs))
               (every #'characterp glyphs))
    (error 'invalid-glyphs :glyphs glyphs)))

(defun %assert-speed (speed)
  "Signal INVALID-SPEED unless SPEED is a positive real. RUN-MATRIX is the
only caller: speed is the driver loop's concern, not a MATRIX-STATE slot."
  (unless (and (realp speed) (plusp speed))
    (error 'invalid-speed :speed speed)))

(defun %copy-random-state (random-state)
  (check-type random-state random-state)
  (make-random-state random-state))

(defun matrix-state-column-count (width)
  "Return how many COLUMN structures a matrix WIDTH screen columns wide
holds. Upstream animates every other screen column, so this is half the
width rounded up, and column I renders at screen x = 2I."
  (ceiling width 2))

(defun make-matrix-state (width height &key (color +default-color+)
                                            (glyphs +default-glyphs+)
                                            (bold +default-bold+)
                                            (partial-bold-p nil)
                                            (no-bold-p nil)
                                            (old-style-p nil)
                                            (lambda-p nil)
                                            (asyncp t)
                                            (random-bold-p nil)
                                            (change-glyphs-p nil)
                                            (random-state (make-random-state t)))
  "Create a MATRIX-STATE covering WIDTH by HEIGHT screen cells. It holds
(MATRIX-STATE-COLUMN-COUNT WIDTH) columns, each independently spawned from
RANDOM-STATE (an actual CL random state object -- inject one built by, e.g.,
SB-EXT:SEED-RANDOM-STATE for a reproducible run; the default is a
nondeterministic one, matching CL:MAKE-RANDOM-STATE's own T argument). The
supplied random state is copied, so constructing a state never mutates
caller-owned randomness.

Fall speed is controlled by RUN-MATRIX, which advances the state at
+BASE-TICK-SECONDS+. RUN-MATRIX still takes :SPEED and signals INVALID-SPEED
for a bad value.

COLOR names one of LIST-COLOR-SCHEMES, or :RAINBOW to draw each column from a
different scheme (default :GREEN). GLYPHS is the non-empty character set
columns draw from (default +DEFAULT-GLYPHS+). BOLD enables all-bold mode,
PARTIAL-BOLD-P enables upstream-compatible partial bolding, and NO-BOLD-P
disables bold styling. OLD-STYLE-P selects upstream's old-style scrolling and
LAMBDA-P its lambda render mode. ASYNCP, when false, advances every column on
every frame. RANDOM-BOLD-P changes the bold cells deterministically from the
matrix tick, and CHANGE-GLYPHS-P repaints every character cell whenever a
column advances.

Signals INVALID-DIMENSIONS when WIDTH or HEIGHT is not a positive integer,
UNKNOWN-COLOR-SCHEME when COLOR is neither a registered scheme nor :RAINBOW,
and INVALID-GLYPHS when GLYPHS is not a non-empty SIMPLE-VECTOR of
characters. All three are checked before a single column is spawned, so a
rejected call allocates nothing."
  (%assert-dimensions width height)
  (unless (color-choice-p color) (error 'unknown-color-scheme :name color))
  (%assert-glyphs glyphs)
  (let ((random-state (%copy-random-state random-state)))
    (%make-matrix-state
     :width width :height height :random-state random-state
     :color color
     :rainbow-schemes (and (eq color :rainbow)
                           (coerce (list-color-schemes) 'simple-vector))
     :glyphs glyphs :bold bold
     :partial-bold-p partial-bold-p :no-bold-p no-bold-p
     :old-style-p old-style-p :lambda-p lambda-p
     :asyncp asyncp :async-count 0
     :random-bold-p random-bold-p :change-glyphs-p change-glyphs-p :tick 0
     :columns (coerce (loop repeat (matrix-state-column-count width)
                            collect (%spawn-column glyphs random-state height))
                      'simple-vector))))

(defun %matrix-state-with-glyphs (state glyphs)
  "Return STATE with every existing column painted from GLYPHS.

The copied random state is advanced while repainting, leaving the
caller-owned state immutable and keeping the next transition reproducible."
  (let* ((random-state (%copy-random-state (matrix-state-random-state state)))
         (old-columns (matrix-state-columns state))
         (new-columns (make-array (length old-columns)))
         (new-state (%copy-matrix-state state)))
    (dotimes (index (length old-columns))
      (setf (svref new-columns index)
            (%column-with-glyphs (svref old-columns index) glyphs random-state)))
    (setf (matrix-state-columns new-state) new-columns
          (matrix-state-glyphs new-state) glyphs
          (matrix-state-random-state new-state) random-state)
    new-state))

(defun %next-async-count (async-count)
  "Return the next value of upstream's cycling `count`, which runs 1..4.
Column UPDATE thresholds are drawn from 1..3, so every column advances on at
least one frame of each cycle and the luckiest advances on three of four."
  (1+ (mod async-count +async-count-cycle+)))

(defun %column-advances-p (column asyncp async-count)
  "True when COLUMN advances on this frame. Upstream's
`count > updates[j] || asynch == 0`: with -a off every column advances every
frame, and with it on a column waits until the cycling count passes its own
threshold."
  (or (not asyncp) (> async-count (column-update column))))

(defun %matrix-advance-serial (state)
  "Advance STATE by one frame, returning a new MATRIX-STATE. Pure given an
already-positioned RANDOM-STATE: calling this TICKS times against a
MATRIX-STATE built with a fixed seed produces byte-identical output on every
run, which is what the deterministic tests in t/ pin down. A column whose
async threshold is not met this frame is carried over unchanged, consuming no
randomness at all -- that is what makes -a's stagger visible. Does not mutate
STATE or its RANDOM-STATE object; the returned state owns the advanced copy."
  (let* ((glyphs (matrix-state-glyphs state))
         (random-state (%copy-random-state (matrix-state-random-state state)))
         (height (matrix-state-height state))
         (asyncp (matrix-state-asyncp state))
         (async-count (%next-async-count (matrix-state-async-count state)))
         (old-style-p (matrix-state-old-style-p state))
         (change-glyphs-p (matrix-state-change-glyphs-p state))
         (old-columns (matrix-state-columns state))
         (new-columns (make-array (length old-columns))))
    (dotimes (index (length old-columns))
      (let ((column (svref old-columns index)))
        (setf (svref new-columns index)
              (if (%column-advances-p column asyncp async-count)
                  (%advance-matrix-column column glyphs random-state height
                                          :old-style-p old-style-p
                                          :change-glyphs-p change-glyphs-p)
                  column))))
    (let ((new-state (%copy-matrix-state state)))
      (setf (matrix-state-columns new-state) new-columns
            (matrix-state-random-state new-state) random-state
            (matrix-state-async-count new-state) async-count
            (matrix-state-tick new-state) (1+ (matrix-state-tick state)))
      new-state)))

(defun matrix-resize (state new-width new-height)
  "Return a new MATRIX-STATE reflowed to NEW-WIDTH by NEW-HEIGHT screen
cells. A height change reflows every column's buffer, preserving the rows
that remain visible (see %RESIZE-COLUMN). A width change keeps the surviving
columns as they were, spawns fresh ones -- drawn from a copy of STATE's
RANDOM-STATE, so a resize mid-run is exactly as reproducible as everything
else -- for newly exposed ones, and drops the rightmost ones when narrowing.

Signals INVALID-DIMENSIONS when NEW-WIDTH or NEW-HEIGHT is not a positive
integer."
  (%assert-dimensions new-width new-height)
  (let* ((old-columns (matrix-state-columns state))
         (old-count (length old-columns))
         (new-count (matrix-state-column-count new-width))
         (glyphs (matrix-state-glyphs state))
         (random-state (%copy-random-state (matrix-state-random-state state)))
         (base-columns
           (if (= new-height (matrix-state-height state))
               old-columns
               (map 'simple-vector
                    (lambda (column) (%resize-column column new-height))
                    old-columns)))
         (new-columns
           (cond
             ((= new-count old-count) base-columns)
             ((< new-count old-count) (subseq base-columns 0 new-count))
             (t (concatenate 'simple-vector
                             base-columns
                             (loop repeat (- new-count old-count)
                                   collect (%spawn-column glyphs random-state
                                                          new-height))))))
         (new-state (%copy-matrix-state state)))
    (setf (matrix-state-width new-state) new-width
          (matrix-state-height new-state) new-height
          (matrix-state-columns new-state) new-columns
          (matrix-state-random-state new-state) random-state)
    new-state))
