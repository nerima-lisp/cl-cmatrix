;;;; t/advance-test.lisp
;;;;
;;;; The determinism guarantee this project is built around: a MATRIX-STATE
;;;; seeded from a fixed RANDOM-STATE produces byte-identical output, tick
;;;; for tick, on every run.
;;;;
;;;; Timing is upstream cmatrix's, not a per-column tick interval: ASYNC-COUNT
;;;; cycles 1..+ASYNC-COUNT-CYCLE+ and a column advances only on a frame where
;;;; that count exceeds its own UPDATE threshold. A column whose threshold is
;;;; not met is carried over as the very same object and draws no randomness,
;;;; so the gate is checked here both by object identity and by the position
;;;; of the state's random stream.

(in-package #:cl-cmatrix/test)

(defun %run-ticks (width height ticks &key (seed 42) (asyncp t) (old-style-p nil))
  (let ((state (make-matrix-state width height :asyncp asyncp :old-style-p old-style-p
                                   :random-state (sb-ext:seed-random-state seed))))
    (dotimes (i ticks state)
      (setf state (matrix-advance state)))))

(defun %column-snapshot (state)
  "Everything a COLUMN carries, in a form EQUAL can compare: the cell buffer,
the head bits, and the three timing fields."
  (map 'list (lambda (c) (list (coerce (column-cells c) 'list)
                                (coerce (column-heads c) 'list)
                                (column-length c) (column-spaces c) (column-update c)))
       (matrix-state-columns state)))

(defun %random-position (state)
  "Where STATE's random stream currently sits, observed without disturbing it:
one draw from a COPY. Two states agree here exactly when the same number of
values has been consumed from the same seed."
  (random 1000000 (make-random-state (matrix-state-random-state state))))

(defun %xy-glyphs ()
  (coerce '(#\X #\Y) 'simple-vector))

(describe "matrix-advance"
  (it "advances the tick counter by exactly one per call"
    (let ((state (make-matrix-state 3 5 :random-state (sb-ext:seed-random-state 1))))
      (dotimes (i 5)
        (expect (= (matrix-state-tick state) i) :to-be-truthy)
        (setf state (matrix-advance state)))
      (expect (= (matrix-state-tick state) 5) :to-be-truthy)))

  (it "is reproducible: two independent runs from the same seed reach identical column state"
    (let ((snapshot-1 (%column-snapshot (%run-ticks 8 12 60)))
          (snapshot-2 (%column-snapshot (%run-ticks 8 12 60))))
      (expect (equal snapshot-1 snapshot-2) :to-be-truthy)))

  (it "a different seed reaches different column state (the seed is actually the source of
the randomness)"
    (let ((snapshot-1 (%column-snapshot (%run-ticks 8 12 60 :seed 1)))
          (snapshot-2 (%column-snapshot (%run-ticks 8 12 60 :seed 2))))
      (expect (not (equal snapshot-1 snapshot-2)) :to-be-truthy)))

  (it "old-style mode is reproducible too, and is the only mode that plants upstream's
:HEAD-MARKER and :PIPE sentinels"
    ;; The two modes share one COLUMN structure, so "old style ran" cannot be
    ;; read off the shape of the data. What distinguishes it is the cell
    ;; vocabulary: upstream's 0 and 1 sentinels exist only in the old-style
    ;; scan, so finding them under -o and never without it is what proves
    ;; OLD-STYLE-P reached the column functions rather than being ignored.
    (flet ((sentinel-p (state)
             (some (lambda (column) (or (find :head-marker (column-cells column))
                                        (find :pipe (column-cells column))))
                   (matrix-state-columns state))))
      (with-soft-assertions
        (expect (equal (%column-snapshot (%run-ticks 8 12 60 :old-style-p t))
                       (%column-snapshot (%run-ticks 8 12 60 :old-style-p t)))
                :to-be-truthy)
        (expect (not (equal (%column-snapshot (%run-ticks 8 12 60 :old-style-p t))
                            (%column-snapshot (%run-ticks 8 12 60))))
                :to-be-truthy)
        (expect (sentinel-p (%run-ticks 8 12 60 :old-style-p t)) :to-be-truthy)
        (expect (not (sentinel-p (%run-ticks 8 12 60))) :to-be-truthy))))

  (it "holds (CEILING WIDTH 2) columns, because upstream animates every other screen column"
    (let ((state (%run-ticks 9 6 3)))
      (with-soft-assertions
        (expect (= (length (matrix-state-columns state)) 5) :to-be-truthy)
        (expect (= (length (matrix-state-columns state)) (matrix-state-column-count 9))
                :to-be-truthy))))

  (it "carries every column over untouched on the first tick, and none of them with -a off"
    ;; An exact invariant rather than a statistical one, so it needs no
    ;; particular seed: ASYNC-COUNT is 1 on the first advance and %SPAWN-COLUMN
    ;; draws every UPDATE threshold from 1..+MAX-UPDATE-THRESHOLD+, so
    ;; `count > update` is false for every column. With ASYNCP false the gate
    ;; is bypassed and every column is rebuilt.
    (let* ((state (make-matrix-state 8 4 :random-state (sb-ext:seed-random-state 9)))
           (async (matrix-advance state))
           (synchronous (matrix-advance
                         (make-matrix-state 8 4 :asyncp nil
                                              :random-state (sb-ext:seed-random-state 9)))))
      (with-soft-assertions
        (expect (= (matrix-state-async-count async) 1) :to-be-truthy)
        (expect (every (lambda (c) (<= 1 (column-update c) +max-update-threshold+))
                       (matrix-state-columns state))
                :to-be-truthy)
        (expect (every #'eq (matrix-state-columns state) (matrix-state-columns async))
                :to-be-truthy)
        (expect (notany #'eq (matrix-state-columns state) (matrix-state-columns synchronous))
                :to-be-truthy))))

  (it "draws no randomness at all for the columns its async gate holds back"
    ;; Measured, not assumed: from seed 9 at 8x4 the first randomness a column
    ;; consumes is the glyph its spawn plants once SPACES has counted down, and
    ;; with -a on no column has reached that frame after four ticks while with
    ;; -a off one has. Both arms run the same four ticks from the same seed, so
    ;; the only difference is the gate.
    (let ((base (make-matrix-state 8 4 :random-state (sb-ext:seed-random-state 9))))
      (with-soft-assertions
        (expect (= (%random-position (%run-ticks 8 4 4 :seed 9))
                   (%random-position base))
                :to-be-truthy)
        (expect (/= (%random-position (%run-ticks 8 4 4 :seed 9 :asyncp nil))
                    (%random-position base))
                :to-be-truthy))))

  (it "never mutates its argument's COLUMNS vector, its columns, or their cell buffers"
    (let* ((state (make-matrix-state 4 6 :random-state (sb-ext:seed-random-state 9)))
           (columns-before (matrix-state-columns state))
           (column-before (aref columns-before 0))
           (cells-before (column-cells column-before)))
      (matrix-advance state)
      (with-soft-assertions
        (expect (eq (matrix-state-columns state) columns-before) :to-be-truthy)
        (expect (eq (aref columns-before 0) column-before) :to-be-truthy)
        (expect (eq (column-cells column-before) cells-before) :to-be-truthy)
        (expect (= (matrix-state-tick state) 0) :to-be-truthy))))

  (it "keeps a column's trail bounded: some cell stays blank on every frame of a long run"
    ;; What the old "respawns once the trail has scrolled past" case pinned,
    ;; restated for a model with no falling head to watch. A stream that never
    ;; gave its top row back would fill the buffer and stay filled, so a blank
    ;; cell on every single frame is the bound; seeing internal row 1 (screen
    ;; row 0) both lit and blank across the run is the recycling.
    (let ((state (make-matrix-state 1 6 :random-state (sb-ext:seed-random-state 3)))
          (always-blank-somewhere t)
          (saw-character nil)
          (saw-space nil))
      (dotimes (i 500)
        (setf state (matrix-advance state))
        (let* ((cells (column-cells (aref (matrix-state-columns state) 0)))
               (top (svref cells 1)))
          (unless (some #'cl-cmatrix::%blank-cell-p cells)
            (setf always-blank-somewhere nil))
          (cond ((characterp top) (setf saw-character t))
                ((eq top :space) (setf saw-space t)))))
      (with-soft-assertions
        (expect always-blank-somewhere :to-be-truthy)
        (expect saw-character :to-be-truthy)
        (expect saw-space :to-be-truthy)
        (expect (= (length (column-cells (aref (matrix-state-columns state) 0))) 7)
                :to-be-truthy)))))

(describe "%column-advances-p"
  (it-each ((1 (nil t t t)) (2 (nil nil t t)) (3 (nil nil nil t)))
      "an UPDATE threshold of ~A advances on exactly the frames ~A of a 1..4 cycle"
      (update expected)
    (let ((column (cl-cmatrix::%make-column :update update)))
      (expect (equal (loop for count from 1 to +async-count-cycle+
                           collect (and (cl-cmatrix::%column-advances-p column t count) t))
                     expected)
              :to-be-truthy)))

  (it "with -a off, advances on every frame of the cycle whatever the threshold"
    (expect (loop for update from 1 to +max-update-threshold+
                  always (loop for count from 1 to +async-count-cycle+
                               always (cl-cmatrix::%column-advances-p
                                       (cl-cmatrix::%make-column :update update) nil count)))
            :to-be-truthy)))

(describe "%spawn-column"
  (it "plants upstream's :SPACE sentinel at internal row 1 and leaves every other cell :EMPTY"
    ;; :EMPTY and :SPACE are distinct on purpose (src/column.lisp:16-22): the
    ;; spawn test is literally `cells[0] == :EMPTY and cells[1] == :SPACE`, so
    ;; a column that started all-:EMPTY would never spawn at all.
    (let ((column (cl-cmatrix::%spawn-column +default-glyphs+
                                             (sb-ext:seed-random-state 7) 8)))
      (with-soft-assertions
        (expect (equal (coerce (column-cells column) 'list)
                       '(:empty :space :empty :empty :empty :empty :empty :empty :empty))
                :to-be-truthy)
        (expect (every #'zerop (column-heads column)) :to-be-truthy))))

  (it-property "always yields parallel HEIGHT+1 buffers and in-range timing fields"
               ((height (gen-integer :min 1 :max 40))
                (seed (gen-integer :min 1 :max 1000)))
               (let ((column (cl-cmatrix::%spawn-column +default-glyphs+
                                                        (sb-ext:seed-random-state seed) height)))
                 (expect (= (length (column-cells column)) (1+ height)) :to-be-truthy)
                 (expect (= (length (column-heads column)) (1+ height)) :to-be-truthy)
                 (expect (<= +min-trail-length+ (column-length column)
                             (max +min-trail-length+ (1- height)))
                         :to-be-truthy)
                 (expect (<= 1 (column-spaces column) height) :to-be-truthy)
                 (expect (<= 1 (column-update column) +max-update-threshold+)
                         :to-be-truthy))))

(describe "column-cell-at and column-head-p"
  (it "reads the stored cell inside the buffer and reports :EMPTY outside it"
    (let ((column (cl-cmatrix::%make-column :cells (vector :empty #\a :space #\c)
                                            :heads (copy-seq #*0110))))
      (expect (equal (loop for row from -1 to 4 collect (column-cell-at column row))
                     '(:empty :empty #\a :space #\c :empty))
              :to-be-truthy)))

  (it "reports a head only for a row inside the buffer whose bit is set"
    (let ((column (cl-cmatrix::%make-column :cells (vector :empty #\a :space #\c)
                                            :heads (copy-seq #*0110))))
      (expect (equal (loop for row from -1 to 4
                           collect (and (column-head-p column row) t))
                     '(nil nil t t nil nil))
              :to-be-truthy))))

(describe "%advance-old-style-column"
  (it "shifts every visible row down one and carries each head bit with its cell"
    ;; Upstream never assigns is_head in old style at all, so the head bits
    ;; riding along with their cells is our deliberate divergence
    ;; (src/column.lisp:172-177) and needs pinning. Internal row HEIGHT is
    ;; outside old style's visible range and is left alone, which is why #\c
    ;; survives at the end.
    (let* ((column (cl-cmatrix::%make-column :cells (vector :empty #\a #\b :space #\c)
                                             :heads (copy-seq #*01001)
                                             :length 3 :spaces 1 :update 2))
           (advanced (cl-cmatrix::%advance-old-style-column
                      column (%xy-glyphs) (sb-ext:seed-random-state 62) 4)))
      (with-soft-assertions
        (expect (equal (coerce (column-cells advanced) 'list)
                       '(:space :empty #\a #\b #\c))
                :to-be-truthy)
        (expect (equal (coerce (column-heads advanced) 'list) '(0 0 1 0 1)) :to-be-truthy)
        (expect (= (column-spaces advanced) 0) :to-be-truthy)
        (expect (= (column-length advanced) 3) :to-be-truthy)
        (expect (= (column-update advanced) 2) :to-be-truthy)
        ;; Functional, as the whole engine is: the argument is untouched.
        (expect (equal (coerce (column-cells column) 'list)
                       '(:empty #\a #\b :space #\c))
                :to-be-truthy))))

  (it "repaints every character cell when CHANGE-GLYPHS-P is enabled, leaving blanks alone"
    (let* ((column (cl-cmatrix::%make-column :cells (vector :empty #\a #\b :space #\c)
                                             :heads (copy-seq #*01001)
                                             :length 3 :spaces 1 :update 2))
           (advanced (cl-cmatrix::%advance-old-style-column
                      column (%xy-glyphs) (sb-ext:seed-random-state 62) 4
                      :change-glyphs-p t))
           (cells (column-cells advanced)))
      (with-soft-assertions
        ;; Same shift as above -- repainting must not move anything.
        (expect (eq (svref cells 0) :space) :to-be-truthy)
        (expect (eq (svref cells 1) :empty) :to-be-truthy)
        (expect (equal (coerce (column-heads advanced) 'list) '(0 0 1 0 1)) :to-be-truthy)
        ;; #\a #\b #\c are not in the glyph set, so finding X or Y in all three
        ;; positions is proof the repaint ran rather than a coincidence.
        (expect (every (lambda (row) (member (svref cells row) '(#\X #\Y))) '(2 3 4))
                :to-be-truthy))))

  (it "takes both respawn paths, and sets the head bit exactly when it plants a :HEAD-MARKER"
    (let ((outcomes '()))
      (loop for seed from 1 to 64
            for advanced = (cl-cmatrix::%advance-old-style-column
                            (cl-cmatrix::%make-column
                             :cells (vector :space :space :space)
                             :heads (copy-seq #*000) :length 3 :spaces 0 :update 1)
                            (%xy-glyphs) (sb-ext:seed-random-state seed) 2)
            do (push (list (svref (column-cells advanced) 0)
                           (sbit (column-heads advanced) 0)
                           (column-spaces advanced))
                     outcomes))
      (with-soft-assertions
        (expect (find :head-marker outcomes :key #'first) :to-be-truthy)
        (expect (find-if #'characterp outcomes :key #'first) :to-be-truthy)
        (expect (every (lambda (outcome)
                         (destructuring-bind (cell head spaces) outcome
                           (and (= head (if (eq cell :head-marker) 1 0))
                                (<= 1 spaces 2))))
                       outcomes)
                :to-be-truthy)))))

(describe "%advance-matrix-column"
  (it "dispatches on the requested mode, not on the shape of the column"
    ;; Both modes share one COLUMN structure, so the only thing that can pick
    ;; between them is OLD-STYLE-P. Same column, same seed, same height: the
    ;; dispatcher must reproduce each mode's own result exactly.
    (let ((column (cl-cmatrix::%spawn-column (%xy-glyphs) (sb-ext:seed-random-state 11) 6)))
      (flet ((cells (c) (coerce (column-cells c) 'list)))
        (with-soft-assertions
          (expect (equal (cells (cl-cmatrix::%advance-matrix-column
                                 column (%xy-glyphs) (sb-ext:seed-random-state 4) 6))
                         (cells (cl-cmatrix::%advance-column
                                 column (%xy-glyphs) (sb-ext:seed-random-state 4) 6)))
                  :to-be-truthy)
          (expect (equal (cells (cl-cmatrix::%advance-matrix-column
                                 column (%xy-glyphs) (sb-ext:seed-random-state 4) 6
                                 :old-style-p t))
                         (cells (cl-cmatrix::%advance-old-style-column
                                 column (%xy-glyphs) (sb-ext:seed-random-state 4) 6)))
                  :to-be-truthy))))))

(describe "%column-with-glyphs"
  (it "redraws every character cell while preserving heads, length, spaces and update"
    ;; A runtime charset toggle must change what the animation shows without
    ;; resetting where it is, so the keyword cells and all three timing fields
    ;; have to survive untouched.
    (let* ((column (cl-cmatrix::%make-column :cells (vector :empty #\a :space #\c)
                                             :heads (copy-seq #*0101)
                                             :length 5 :spaces 4 :update 3))
           (repainted (cl-cmatrix::%column-with-glyphs
                       column (%xy-glyphs) (sb-ext:seed-random-state 17)))
           (cells (column-cells repainted)))
      (with-soft-assertions
        (expect (eq (svref cells 0) :empty) :to-be-truthy)
        (expect (eq (svref cells 2) :space) :to-be-truthy)
        (expect (member (svref cells 1) '(#\X #\Y)) :to-be-truthy)
        (expect (member (svref cells 3) '(#\X #\Y)) :to-be-truthy)
        (expect (equal (coerce (column-heads repainted) 'list) '(0 1 0 1)) :to-be-truthy)
        (expect (= (column-length repainted) 5) :to-be-truthy)
        (expect (= (column-spaces repainted) 4) :to-be-truthy)
        (expect (= (column-update repainted) 3) :to-be-truthy)))))

(defun %resize-fixture ()
  (cl-cmatrix::%make-column :cells (vector :empty #\a :space #\c)
                            :heads (copy-seq #*0101)
                            :length 5 :spaces 4 :update 3))

(describe "%resize-column"
  (it "shrinking keeps the rows that remain visible and clamps LENGTH and SPACES"
    (let ((short (cl-cmatrix::%resize-column (%resize-fixture) 2)))
      (with-soft-assertions
        (expect (equal (coerce (column-cells short) 'list) '(:empty #\a :space)) :to-be-truthy)
        (expect (equal (coerce (column-heads short) 'list) '(0 1 0)) :to-be-truthy)
        ;; LENGTH clamps to the new height but never below +MIN-TRAIL-LENGTH+,
        ;; or a stream taller than the screen would never finish growing.
        (expect (= (column-length short) +min-trail-length+) :to-be-truthy)
        (expect (= (column-spaces short) 2) :to-be-truthy)
        (expect (= (column-update short) 3) :to-be-truthy))))

  (it "growing pads the newly exposed rows with :EMPTY and unset head bits"
    (let ((long (cl-cmatrix::%resize-column (%resize-fixture) 6)))
      (with-soft-assertions
        (expect (equal (coerce (column-cells long) 'list)
                       '(:empty #\a :space #\c :empty :empty :empty))
                :to-be-truthy)
        (expect (equal (coerce (column-heads long) 'list) '(0 1 0 1 0 0 0)) :to-be-truthy)
        (expect (= (column-length long) 5) :to-be-truthy)
        (expect (= (column-spaces long) 4) :to-be-truthy)
        (expect (= (column-update long) 3) :to-be-truthy)))))

(describe "column buffer invariants"
  (it "CELLS and HEADS stay parallel at HEIGHT+1 entries through every transition"
    ;; The old suite pinned that a column's glyph vector and its bold-metadata
    ;; vector were kept in step. There is no second metadata vector any more --
    ;; HEADS is that parallel buffer now -- and every constructor in
    ;; src/column.lisp has to keep it exactly as long as CELLS, or
    ;; COLUMN-HEAD-P would silently read a row that COLUMN-CELL-AT can reach.
    (let ((glyphs (%xy-glyphs))
          (violations 0))
      (flet ((check (column height)
               (unless (and (= (length (column-cells column)) (1+ height))
                            (= (length (column-heads column)) (1+ height)))
                 (incf violations))
               column))
        (loop for height from 1 to 12
              do (let ((column (check (cl-cmatrix::%spawn-column
                                       glyphs (sb-ext:seed-random-state height) height)
                                      height)))
                   (dotimes (i 30)
                     (setf column (check (cl-cmatrix::%advance-column
                                          column glyphs (sb-ext:seed-random-state 5) height)
                                         height)))
                   (dotimes (i 30)
                     (setf column (check (cl-cmatrix::%advance-old-style-column
                                          column glyphs (sb-ext:seed-random-state 5) height)
                                         height)))
                   (check (cl-cmatrix::%column-with-glyphs
                           column glyphs (sb-ext:seed-random-state 5))
                          height)
                   (check (cl-cmatrix::%resize-column column (+ height 3)) (+ height 3)))))
      (expect (zerop violations) :to-be-truthy))))
