;;;; src/column.lisp
;;;;
;;;; One falling character stream. A COLUMN tracks only its own vertical
;;;; position and timing; it knows nothing about its x coordinate or the
;;;; screen it will eventually be drawn onto (that is MATRIX-STATE's and
;;;; render.lisp's job). GLYPHS is a fixed-size ring buffer: index (MOD row
;;;; LENGTH) holds the character that was chosen when the head last visited
;;;; ROW, so the LENGTH rows behind the head are always exactly the ones
;;;; still lit, and a row falls out of the trail (gets overwritten by a
;;;; different row's glyph) at the same moment it falls out of the visible
;;;; window.

(in-package #:cl-cmatrix)

(defun %min-trail-length () 3)

(defparameter +min-trail-length+ (%min-trail-length)
  "The shortest trail a freshly spawned COLUMN may have.")

(defun %max-trail-length () 12)

(defparameter +max-trail-length+ (%max-trail-length)
  "The longest trail a freshly spawned COLUMN may have.")

(defun %max-raw-interval () 3)

(defparameter +max-raw-interval+ (%max-raw-interval)
  "The upper bound (inclusive) of the ticks-per-row-advance a freshly spawned
COLUMN draws before SPEED scaling is applied to it.")

(defstruct (column (:constructor %make-column))
  "One falling character stream. HEAD is the row of its brightest character;
LENGTH is how many rows behind it (inclusive of HEAD itself) are lit; GLYPHS
is a ring buffer of LENGTH characters described above; INTERVAL is the
number of ticks between one-row advances (larger is slower); COUNTER is the
number of ticks elapsed since the last advance."
  (interval 1 :type fixnum)
  (counter 0 :type fixnum)
  (head 0 :type fixnum)
  (length 1 :type fixnum)
  (glyphs #() :type simple-vector))

(defun column-glyph-at-row (column row)
  "Return the glyph COLUMN shows at ROW. Only meaningful when ROW is within
COLUMN's currently lit trail; see COLUMN-ROW-LIT-P."
  (svref (column-glyphs column) (mod row (column-length column))))

(defun column-row-lit-p (column row)
  "True when ROW is within COLUMN's currently lit trail, i.e. in
[HEAD - LENGTH + 1, HEAD]."
  (and (<= (- (column-head column) (column-length column) -1) row)
       (<= row (column-head column))))

(defun %interval-for-speed (raw-interval speed)
  "Scale a raw 1..+MAX-RAW-INTERVAL+ ticks-per-row draw by SPEED (larger
SPEED means fewer ticks per row, i.e. a faster fall), clamped to a minimum
of 1 tick."
  (max 1 (round (/ raw-interval speed))))

(defun %make-glyph-ring (length glyphs random-state)
  (let ((ring (make-array length)))
    (dotimes (index length ring)
      (setf (svref ring index) (random-glyph glyphs random-state)))))

(defun %spawn-column (glyphs random-state speed &key start-row)
  "Return a freshly spawned COLUMN, drawing its interval, trail length,
glyphs, and (unless START-ROW is supplied) its initial head position from
RANDOM-STATE. START-ROW is used by MATRIX-RESIZE, which gives new columns
the same head as their neighbors rather than staggering them; the default
(NIL) staggers a spawn's head somewhere in [-LENGTH, 0] so a batch of new
drops does not all break the top edge in lockstep."
  (let* ((interval (%interval-for-speed (1+ (random +max-raw-interval+ random-state)) speed))
         (length (+ +min-trail-length+
                    (random (1+ (- +max-trail-length+ +min-trail-length+)) random-state)))
         (head (or start-row (- (random (1+ length) random-state)))))
    (%make-column :interval interval :counter 0 :head head :length length
                  :glyphs (%make-glyph-ring length glyphs random-state))))

(defun %column-fall-one-row (column glyphs random-state new-head)
  "Return a new COLUMN with its head advanced to NEW-HEAD, painting a freshly
drawn glyph into the ring-buffer row NEW-HEAD now occupies. The counter reset
to 0 alongside HEAD is what starts the next INTERVAL-tick wait for the row
after NEW-HEAD."
  (let ((new-glyphs (copy-seq (column-glyphs column))))
    (setf (svref new-glyphs (mod new-head (column-length column)))
          (random-glyph glyphs random-state))
    (%make-column :interval (column-interval column) :counter 0
                  :head new-head :length (column-length column)
                  :glyphs new-glyphs)))

(defun %advance-column (column glyphs random-state speed height)
  "Advance COLUMN by one tick, returning a new COLUMN. Every HEIGHT+LENGTH
rows-worth of ticks the column's whole trail has scrolled past the visible
HEIGHT rows, and it respawns at the top via %SPAWN-COLUMN. The three cases
below are, in order: not yet time for this tick to move a row (just count
it), time to move but the whole trail has now scrolled off HEIGHT (respawn),
and time to move with the column still on screen (paint the new head row)."
  (let ((counter (1+ (column-counter column))))
    (cond
      ((< counter (column-interval column))
       (%make-column :interval (column-interval column) :counter counter
                     :head (column-head column) :length (column-length column)
                     :glyphs (column-glyphs column)))
      ((>= (1+ (column-head column)) (+ height (column-length column)))
       (%spawn-column glyphs random-state speed))
      (t
       (%column-fall-one-row column glyphs random-state (1+ (column-head column)))))))
