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

(defstruct (column (:constructor %make-column))
  "One falling character stream. HEAD is the row of its brightest character;
LENGTH is how many rows behind it (inclusive of HEAD itself) are lit; GLYPHS
is a ring buffer of LENGTH characters described above; GLYPH-BOLD-P records
the upstream partial-bold selection for each ring position; INTERVAL is the
number of ticks between one-row advances (larger is slower); COUNTER is the
number of ticks elapsed since the last advance."
  (interval 1 :type fixnum)
  (counter 0 :type fixnum)
  (head 0 :type fixnum)
  (length 1 :type fixnum)
  (glyphs #() :type simple-vector)
  (glyph-bold-p #() :type simple-vector))

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

(defun %synchronous-interval-for-speed (speed)
  "Return the common row interval used by synchronous scrolling."
  (%interval-for-speed 1 speed))

(defun %make-glyph-ring (length glyphs random-state)
  (let ((ring (make-array length))
        (glyph-bold-p (make-array length)))
    (dotimes (index length (values ring glyph-bold-p))
      (multiple-value-bind (glyph partial-bold-p)
          (%random-glyph-with-parity glyphs random-state)
        (setf (svref ring index) glyph
              (svref glyph-bold-p index) partial-bold-p)))))

(defun %copy-glyph-bold-p (column)
  "Return COLUMN's partial-bold metadata, filling legacy columns by glyph."
  (let ((result (make-array (column-length column)))
        (old (column-glyph-bold-p column))
        (glyphs (column-glyphs column)))
    (dotimes (index (column-length column) result)
      (setf (svref result index)
            (if (< index (length old))
                (svref old index)
                (and (< index (length glyphs))
                     (evenp (char-code (svref glyphs index)))))))))

(defun %spawn-column (glyphs random-state speed &key start-row interval)
  "Return a freshly spawned COLUMN, drawing its interval, trail length,
glyphs, and (unless START-ROW is supplied) its initial head position from
RANDOM-STATE. START-ROW is used by MATRIX-RESIZE, which gives new columns
the same head as their neighbors rather than staggering them; the default
(NIL) staggers a spawn's head somewhere in [-LENGTH, 0] so a batch of new
drops does not all break the top edge in lockstep."
  (let* ((column-interval (or interval
                             (%interval-for-speed
                              (1+ (random +max-raw-interval+ random-state))
                              speed)))
         (length (+ +min-trail-length+
                    (random (1+ (- +max-trail-length+ +min-trail-length+)) random-state)))
         (head (or start-row (- (random (1+ length) random-state)))))
    (multiple-value-bind (glyphs glyph-bold-p)
        (%make-glyph-ring length glyphs random-state)
      (%make-column :interval column-interval :counter 0 :head head :length length
                    :glyphs glyphs :glyph-bold-p glyph-bold-p))))

(defun %column-fall-one-row (column glyphs random-state new-head
                             &key interval change-glyphs-p)
  "Return a new COLUMN with its head advanced to NEW-HEAD, painting a freshly
drawn glyph into the ring-buffer row NEW-HEAD now occupies. The counter reset
to 0 alongside HEAD is what starts the next INTERVAL-tick wait for the row
after NEW-HEAD."
  (let ((new-glyphs (copy-seq (column-glyphs column)))
        (new-glyph-bold-p (%copy-glyph-bold-p column)))
    (flet ((paint (index)
             (multiple-value-bind (glyph partial-bold-p)
                 (%random-glyph-with-parity glyphs random-state)
               (setf (svref new-glyphs index) glyph
                     (svref new-glyph-bold-p index) partial-bold-p))))
      (if change-glyphs-p
          (dotimes (index (column-length column))
            (paint index))
          (paint (mod new-head (column-length column)))))
    (%make-column :interval (or interval (column-interval column)) :counter 0
                  :head new-head :length (column-length column)
                  :glyphs new-glyphs :glyph-bold-p new-glyph-bold-p)))

(defun %advance-column (column glyphs random-state speed height
                        &key (asyncp t) change-glyphs-p)
  "Advance COLUMN by one tick, returning a new COLUMN. Every HEIGHT+LENGTH
rows-worth of ticks the column's whole trail has scrolled past the visible
HEIGHT rows, and it respawns at the top via %SPAWN-COLUMN. The three cases
below are, in order: not yet time for this tick to move a row (just count
it), time to move but the whole trail has now scrolled off HEIGHT (respawn),
and time to move with the column still on screen (paint the new head row)."
  (let* ((interval (if asyncp
                      (column-interval column)
                      (%synchronous-interval-for-speed speed)))
         (counter (1+ (column-counter column))))
    (cond
      ((< counter interval)
       (%make-column :interval interval :counter counter
                     :head (column-head column) :length (column-length column)
                     :glyphs (column-glyphs column)
                     :glyph-bold-p (column-glyph-bold-p column)))
      ((>= (1+ (column-head column)) (+ height (column-length column)))
       (%spawn-column glyphs random-state speed
                      :interval (unless asyncp interval)))
      (t
       (%column-fall-one-row column glyphs random-state (1+ (column-head column))
                             :interval interval
                             :change-glyphs-p change-glyphs-p)))))

(defstruct (old-style-column (:constructor %make-old-style-column))
  "A fixed-height visible buffer used by upstream cmatrix's old-style mode.
GLYPHS and GLYPH-BOLD-P are indexed by screen row; NIL GLYPHS are blank cells.
SPACES is the number of blank cells still to emit before the next new glyph."
  (interval 1 :type fixnum)
  (counter 0 :type fixnum)
  (glyphs #() :type simple-vector)
  (glyph-bold-p #() :type simple-vector)
  (spaces 0 :type fixnum))

(defun old-style-column-glyph-at-row (column row)
  "Return the glyph in old-style COLUMN at ROW, or NIL for a blank cell."
  (let ((glyphs (old-style-column-glyphs column)))
    (and (<= 0 row)
         (< row (length glyphs))
         (svref glyphs row))))

(defun %spawn-old-style-column (glyphs random-state speed height &key interval)
  "Return an empty fixed-height column for upstream cmatrix old-style scrolling."
  (declare (ignore glyphs))
  (%make-old-style-column
   :interval (or interval (%interval-for-speed
                           (1+ (random +max-raw-interval+ random-state))
                           speed))
   :counter 0
   :glyphs (make-array height :initial-element nil)
   :glyph-bold-p (make-array height :initial-element nil)
   :spaces (1+ (random height random-state))))

(defun %old-style-column-with-glyphs (column glyphs random-state)
  "Return COLUMN with each existing visible glyph repainted from GLYPHS."
  (let* ((old-glyphs (old-style-column-glyphs column))
         (new-glyphs (copy-seq old-glyphs))
         (new-glyph-bold-p (copy-seq (old-style-column-glyph-bold-p column))))
    (dotimes (index (length new-glyphs))
      (when (svref new-glyphs index)
        (multiple-value-bind (glyph partial-bold-p)
            (%random-glyph-with-parity glyphs random-state)
          (setf (svref new-glyphs index) glyph
                (svref new-glyph-bold-p index) partial-bold-p))))
    (%make-old-style-column
     :interval (old-style-column-interval column)
     :counter (old-style-column-counter column)
     :glyphs new-glyphs
     :glyph-bold-p new-glyph-bold-p
     :spaces (old-style-column-spaces column))))

(defun %old-style-column-fall-one-row (column glyphs random-state
                                       &key interval change-glyphs-p)
  "Shift the visible buffer down and generate the next top cell."
  (let* ((old-glyphs (old-style-column-glyphs column))
         (old-glyph-bold-p (old-style-column-glyph-bold-p column))
         (height (length old-glyphs))
         (new-glyphs (make-array height :initial-element nil))
         (new-glyph-bold-p (make-array height :initial-element nil))
         (spaces (old-style-column-spaces column)))
    (loop for row from 1 below height
          do (setf (svref new-glyphs row) (svref old-glyphs (1- row))
                   (svref new-glyph-bold-p row)
                   (svref old-glyph-bold-p (1- row))))
    (if (plusp spaces)
        (decf spaces)
        (if (= (random 3 random-state) 1)
            (setf spaces (1+ (random height random-state)))
            (multiple-value-bind (glyph partial-bold-p)
                (%random-glyph-with-parity glyphs random-state)
              (setf (svref new-glyphs 0) glyph
                    (svref new-glyph-bold-p 0) partial-bold-p))))
    (when change-glyphs-p
      (dotimes (index height)
        (when (svref new-glyphs index)
          (multiple-value-bind (glyph partial-bold-p)
              (%random-glyph-with-parity glyphs random-state)
            (setf (svref new-glyphs index) glyph
                  (svref new-glyph-bold-p index) partial-bold-p)))))
    (%make-old-style-column
     :interval (or interval (old-style-column-interval column))
     :counter 0
     :glyphs new-glyphs
     :glyph-bold-p new-glyph-bold-p
     :spaces spaces)))

(defun %advance-old-style-column (column glyphs random-state speed height
                                  &key (asyncp t) change-glyphs-p)
  "Advance an old-style visible buffer by one tick."
  (declare (ignore height))
  (let* ((interval (if asyncp
                      (old-style-column-interval column)
                      (%synchronous-interval-for-speed speed)))
         (counter (1+ (old-style-column-counter column))))
    (if (< counter interval)
        (%make-old-style-column
         :interval interval
         :counter counter
         :glyphs (old-style-column-glyphs column)
         :glyph-bold-p (old-style-column-glyph-bold-p column)
         :spaces (old-style-column-spaces column))
        (%old-style-column-fall-one-row column glyphs random-state
                                        :interval interval
                                        :change-glyphs-p change-glyphs-p))))

(defun %resize-old-style-column (column height)
  "Resize COLUMN's visible buffer while preserving rows that remain visible."
  (let* ((old-glyphs (old-style-column-glyphs column))
         (old-glyph-bold-p (old-style-column-glyph-bold-p column))
         (new-glyphs (make-array height :initial-element nil))
         (new-glyph-bold-p (make-array height :initial-element nil)))
    (dotimes (row (min height (length old-glyphs)))
      (setf (svref new-glyphs row) (svref old-glyphs row)
            (svref new-glyph-bold-p row) (svref old-glyph-bold-p row)))
    (%make-old-style-column
     :interval (old-style-column-interval column)
     :counter (old-style-column-counter column)
     :glyphs new-glyphs
     :glyph-bold-p new-glyph-bold-p
     :spaces (old-style-column-spaces column))))

(defun %advance-matrix-column (column glyphs random-state speed height
                               &key (asyncp t) change-glyphs-p)
  "Advance either the normal ring COLUMN or an old-style visible buffer."
  (if (old-style-column-p column)
      (%advance-old-style-column column glyphs random-state speed height
                                 :asyncp asyncp
                                 :change-glyphs-p change-glyphs-p)
      (%advance-column column glyphs random-state speed height
                       :asyncp asyncp
                       :change-glyphs-p change-glyphs-p)))
