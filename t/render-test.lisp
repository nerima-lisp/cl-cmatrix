
(in-package #:cl-cmatrix/test)

(defun %style-fg-entry (style)
  "Return the (:FG ...) entry within STYLE, cl-tty-kit's normalized style
list. STYLE mixes bare modifier keywords like :BOLD with (:FG ...)/(:BG ...)
sublists, so ASSOC cannot walk it directly -- ASSOC calls CAR on every
element, including the bare keywords, which are not conses."
  (find-if (lambda (item) (and (consp item) (eq (first item) :fg))) style))

(defun %test-column (cells &key heads (length 3))
  "Return a COLUMN holding CELLS, a list of internal rows whose first element
is the off-screen staging row 0 (see src/column.lisp's header). HEADS lists
the internal rows whose head bit is set. Building a column literally is what
lets a draw's expected screen be written out by hand instead of re-derived."
  (let* ((vector (coerce cells 'simple-vector))
         (bits (make-array (length vector) :element-type 'bit :initial-element 0)))
    (dolist (row heads)
      (setf (sbit bits row) 1))
    (cl-cmatrix::%make-column :cells vector :heads bits :length length)))

(defun %state-with-columns (width height columns &rest options)
  "Return a MATRIX-STATE of WIDTH by HEIGHT whose COLUMNS are exactly the ones
supplied, with OPTIONS passed on to MAKE-MATRIX-STATE. COLUMNS must hold
(MATRIX-STATE-COLUMN-COUNT WIDTH) entries, since column I is drawn at x = 2I."
  (let ((state (apply #'make-matrix-state width height
                      :random-state (sb-ext:seed-random-state 7) options)))
    (setf (matrix-state-columns state) (coerce columns 'simple-vector))
    state))

(defun %draw-state (state)
  "Draw STATE onto a screen of its own dimensions and return that screen."
  (let ((screen (make-screen (matrix-state-width state) (matrix-state-height state))))
    (matrix-draw screen state (make-render-context))
    screen))

(defun %styles (trail-length &optional bold)
  "Return a fresh (uncached) style vector of TRAIL-LENGTH entries, the vector
%DRAW-COLUMN indexes by clamped offset."
  (cl-cmatrix::%matrix-style-vector :green trail-length bold (make-hash-table :test #'eq)))

(defun %screen-char (screen x y)
  (cell-char (screen-cell screen x y)))

(defun %screen-style (screen x y)
  (cell-style (screen-cell screen x y)))

(defun %screen-bold-p (screen x y)
  "True when the cell drawn at X, Y carries :BOLD. Note a head cell reads
bold whatever the bold flags say, because the head style itself is bold --
only a non-head trail cell distinguishes the bold modes."
  (and (member :bold (%screen-style screen x y)) t))

(defun %expected-lambda ()
  "Return U+03BB, the character upstream cmatrix's -m mode draws. Fixed here
independently of CL-CMATRIX::%LAMBDA-GLYPH: a draw spec that compared the
glyph on screen against that function's own return value would run both sides
of the comparison through the same implementation, so any substitute
character -- not just a different lambda -- would satisfy it."
  (code-char #x3bb))


(defun %control-code-p (code)
  "True for the code points a terminal reads as control bytes: C0 (below
#x20), DEL (#x7F), and C1 (#x80..#x9F). Restated here from the Unicode ranges
rather than obtained from cl-tty-kit, so this oracle cannot agree with a
sanitizer that stopped recognising one of them -- a check that asked the
dependency which characters are dangerous would move in lockstep with it."
  (or (< code #x20) (= code #x7f) (<= #x80 code #x9f)))

(defun %control-codes-in (string)
  "Return the ascending set of control code points STRING contains."
  (sort (remove-duplicates
         (loop for character across string
               for code = (char-code character)
               when (%control-code-p code)
                 collect code))
        #'<))

(defun %message-frame (message &key (width 9) (height 5))
  "Return the ANSI frame emitted for a screen carrying only MESSAGE. This is
the byte stream cl-cmatrix hands the terminal, and the only place where a
control character in --message could act as an escape sequence rather than as
inert screen contents."
  (let ((renderer (make-renderer width height)))
    (cl-tty-kit:renderer-clear renderer)
    (cl-cmatrix::matrix-draw-message (cl-tty-kit:renderer-screen renderer)
                                     width height message)
    (cl-tty-kit:renderer-render renderer)))

(defun %repeated-message (code length)
  "Return a message of LENGTH copies of the character at CODE."
  (make-string length :initial-element (code-char code)))

(defun %message-run-state (message &key (width 9) (height 5))
  "Return a RUN-STATE carrying MESSAGE over an unadvanced (all-blank) matrix,
so RUN-STATE-RENDER's frame holds the message and nothing else."
  (let ((run-state (make-run-state
                    :matrix (make-matrix-state
                             width height
                             :random-state (sb-ext:seed-random-state 24))
                    :renderer (make-renderer width height))))
    (setf (run-state-message run-state) message)
    run-state))

(describe "matrix-cell-style"
  (it "renders the head (offset 0) bold in the scheme's head color"
    (let ((style (matrix-cell-style :green 0 5)))
      (with-soft-assertions
        (expect (member :bold style) :to-be-truthy)
        (expect (equal (%style-fg-entry style)
                       (list :fg (apply #'rgb-to-256 (color-scheme-head-rgb :green))))
                :to-be-truthy))))

  (it "renders a non-head row without :bold"
    (let ((style (matrix-cell-style :green 1 5)))
      (with-soft-assertions
        (expect (not (member :bold style)) :to-be-truthy)
        (expect (consp (%style-fg-entry style)) :to-be-truthy))))

  (it "the last lit row (offset = length - 1) blends all the way to the scheme's dark color"
    (let* ((length 6)
           (style (matrix-cell-style :green (1- length) length))
           (expected-rgb (blend-colors (color-scheme-bright-rgb :green)
                                        (color-scheme-dark-rgb :green) 1)))
      (expect (equal (%style-fg-entry style) (list :fg (apply #'rgb-to-256 expected-rgb)))
              :to-be-truthy)))

  (it "every color scheme's head is the same bright white, by design"
    (expect (equal (matrix-cell-style :green 0 5) (matrix-cell-style :cyan 0 5))
            :to-be-truthy))

  (it "different color schemes produce different non-head (trail) styles"
    (expect (not (equal (matrix-cell-style :green 1 5) (matrix-cell-style :cyan 1 5)))
            :to-be-truthy))

  (it "a trail length of 1 does not divide by zero: OFFSET 0 takes the head branch"
    (expect (matrix-cell-style :green 0 1) :to-be-truthy))

  (it "a trail length of 1 does not divide by zero: OFFSET 1 clamps its ratio denominator to 1"
    (let ((style (matrix-cell-style :green 1 1))
          (expected-rgb (blend-colors (color-scheme-bright-rgb :green)
                                       (color-scheme-dark-rgb :green) 1)))
      (expect (equal (%style-fg-entry style) (list :fg (apply #'rgb-to-256 expected-rgb)))
              :to-be-truthy)))

  (it "a non-head row is not bold by default"
    (expect (not (member :bold (matrix-cell-style :green 1 5))) :to-be-truthy))

  (it "a non-head row is bold when BOLD is true"
    (expect (member :bold (matrix-cell-style :green 1 5 t)) :to-be-truthy))

  (it "the head is bold regardless of BOLD, and its color is unaffected by BOLD"
    (expect (equal (matrix-cell-style :green 0 5 nil) (matrix-cell-style :green 0 5 t))
            :to-be-truthy))

  (it "leaves the head unbold when NO-BOLD is requested"
    (expect (not (member :bold (matrix-cell-style :green 0 5 nil t))) :to-be-truthy))

  (it "leaves a bold trail row unbold when NO-BOLD overrides BOLD"
    (expect (not (member :bold (matrix-cell-style :green 1 5 t t))) :to-be-truthy)))

(describe "%matrix-style-vector"
  (it "returns the identical vector object on a repeat call, rather than recomputing it"
    (let ((cache (make-hash-table :test #'eq)))
      (expect (eq (cl-cmatrix::%matrix-style-vector :green 5 nil cache)
                  (cl-cmatrix::%matrix-style-vector :green 5 nil cache))
              :to-be-truthy)))

  (it "keys on BOLD, so a bold request never shares the non-bold entry in one cache"
    (let* ((cache (make-hash-table :test #'eq))
           (plain (cl-cmatrix::%matrix-style-vector :green 5 nil cache))
           (bold (cl-cmatrix::%matrix-style-vector :green 5 t cache)))
      (with-soft-assertions
        (expect (not (eq plain bold)) :to-be-truthy)
        (expect (notevery #'equal plain bold) :to-be-truthy))))

  (it "keys on NO-BOLD too, the fourth and innermost level of the cache"
    (let* ((cache (make-hash-table :test #'eq))
           (plain (cl-cmatrix::%matrix-style-vector :green 5 nil cache))
           (no-bold (cl-cmatrix::%matrix-style-vector :green 5 nil cache t)))
      (with-soft-assertions
        (expect (not (eq plain no-bold)) :to-be-truthy)
        (expect (member :bold (svref plain 0)) :to-be-truthy)
        (expect (not (member :bold (svref no-bold 0))) :to-be-truthy))))

  (it "fills each offset with MATRIX-CELL-STYLE's own result for that offset"
    (let* ((cache (make-hash-table :test #'eq))
           (styles (cl-cmatrix::%matrix-style-vector :green 5 nil cache)))
      (with-soft-assertions
        (expect (= (length styles) 5) :to-be-truthy)
        (loop for offset below 5
              do (expect (equal (svref styles offset)
                                (matrix-cell-style :green offset 5 nil))
                         :to-be-truthy))))))

(describe "%draw-column"
  (it "recovers each cell's offset from its run's bottom row, drawing row R at screen row R - 1"
    (let ((column (%test-column (list :empty #\a #\b #\c :space #\d :empty)
                                :heads '(3 5) :length 4))
          (styles (%styles 4))
          (screen (make-screen 1 6)))
      (cl-cmatrix::%draw-column screen 0 column 1 6 1 styles nil)
      (with-soft-assertions
        (expect (char= (%screen-char screen 0 0) #\a) :to-be-truthy)
        (expect (equal (%screen-style screen 0 0) (svref styles 2)) :to-be-truthy)
        (expect (char= (%screen-char screen 0 1) #\b) :to-be-truthy)
        (expect (equal (%screen-style screen 0 1) (svref styles 1)) :to-be-truthy)
        (expect (char= (%screen-char screen 0 2) #\c) :to-be-truthy)
        (expect (equal (%screen-style screen 0 2) (svref styles 0)) :to-be-truthy)
        (expect (char= (%screen-char screen 0 3) #\Space) :to-be-truthy)
        (expect (char= (%screen-char screen 0 4) #\d) :to-be-truthy)
        (expect (equal (%screen-style screen 0 4) (svref styles 0)) :to-be-truthy)
        (expect (char= (%screen-char screen 0 5) #\Space) :to-be-truthy))))

  (it "clamps a run longer than the style vector to that vector's last index"
    (let ((column (%test-column (list :empty #\a #\b #\c #\d #\e :empty)
                                :heads '(5) :length 3))
          (styles (%styles 3))
          (screen (make-screen 1 6)))
      (cl-cmatrix::%draw-column screen 0 column 1 6 1 styles nil)
      (with-soft-assertions
        (loop for row below 3
              do (expect (equal (%screen-style screen 0 row) (svref styles 2)) :to-be-truthy))
        (expect (equal (%screen-style screen 0 3) (svref styles 1)) :to-be-truthy)
        (expect (equal (%screen-style screen 0 4) (svref styles 0)) :to-be-truthy))))

  (it "gives a head cell index 0 even where its offset would have selected a dimmer style"
    (let ((column (%test-column (list :empty #\a #\b #\c :empty) :heads '(1) :length 4))
          (styles (%styles 4))
          (screen (make-screen 1 4)))
      (cl-cmatrix::%draw-column screen 0 column 1 4 1 styles nil)
      (with-soft-assertions
        (expect (equal (%screen-style screen 0 0) (svref styles 0)) :to-be-truthy)
        (expect (not (equal (svref styles 0) (svref styles 2))) :to-be-truthy))))

  (it "draws :head-marker as & and :pipe as | at the brightest trail index"
    (let ((column (%test-column (list :empty :head-marker :pipe #\z :empty)
                                :heads '(1) :length 4))
          (styles (%styles 4))
          (screen (make-screen 1 4)))
      (cl-cmatrix::%draw-column screen 0 column 1 4 1 styles nil)
      (with-soft-assertions
        (expect (char= (%screen-char screen 0 0) #\&) :to-be-truthy)
        (expect (equal (%screen-style screen 0 0) (svref styles 0)) :to-be-truthy)
        (expect (char= (%screen-char screen 0 1) #\|) :to-be-truthy)
        (expect (equal (%screen-style screen 0 1) (svref styles 1)) :to-be-truthy))))

  (it "clamps :pipe's index to 0 when the style vector holds a single entry"
    (let ((column (%test-column (list :empty :head-marker :pipe :empty)
                                :heads '(1) :length 1))
          (styles (%styles 1))
          (screen (make-screen 1 3)))
      (cl-cmatrix::%draw-column screen 0 column 1 3 1 styles nil)
      (with-soft-assertions
        (expect (= (length styles) 1) :to-be-truthy)
        (expect (char= (%screen-char screen 0 1) #\|) :to-be-truthy)
        (expect (equal (%screen-style screen 0 1) (svref styles 0)) :to-be-truthy))))

  (it "substitutes a lambda for non-head characters only, leaving the head's own character"
    (let ((column (%test-column (list :empty #\a #\b #\c :empty) :heads '(3) :length 3))
          (styles (%styles 3))
          (screen (make-screen 1 4)))
      (cl-cmatrix::%draw-column screen 0 column 1 4 1 styles nil :lambda-p t)
      (with-soft-assertions
        (expect (char= (%screen-char screen 0 0) (%expected-lambda)) :to-be-truthy)
        (expect (char= (%screen-char screen 0 1) (%expected-lambda)) :to-be-truthy)
        (expect (char= (%screen-char screen 0 2) #\c) :to-be-truthy))))

  (it "reads partial-bold parity from the stored character, never from the lambda displayed"
    (let ((column (%test-column (list :empty #\a #\b #\c :empty) :heads '(3) :length 3))
          (styles (%styles 3))
          (bold-styles (%styles 3 t))
          (screen (make-screen 1 4)))
      (cl-cmatrix::%draw-column screen 0 column 1 4 1 styles bold-styles
                                :lambda-p t :partial-bold-p t)
      (with-soft-assertions
        (expect (oddp (char-code (%expected-lambda))) :to-be-truthy)
        (expect (oddp (char-code #\a)) :to-be-truthy)
        (expect (evenp (char-code #\b)) :to-be-truthy)
        (expect (char= (%screen-char screen 0 0) (%expected-lambda)) :to-be-truthy)
        (expect (not (%screen-bold-p screen 0 0)) :to-be-truthy)
        (expect (char= (%screen-char screen 0 1) (%expected-lambda)) :to-be-truthy)
        (expect (%screen-bold-p screen 0 1) :to-be-truthy))))

  (it "draws internal row 0 in old style, and never in new style, from one and the same column"
    (let ((column (%test-column (list #\a :space #\c :empty) :heads '(0) :length 3))
          (styles (%styles 3))
          (old (make-screen 1 3))
          (new (make-screen 1 3)))
      (cl-cmatrix::%draw-column old 0 column 0 2 0 styles nil)
      (cl-cmatrix::%draw-column new 0 column 1 3 1 styles nil)
      (with-soft-assertions
        (expect (char= (%screen-char old 0 0) #\a) :to-be-truthy)
        (expect (char= (%screen-char old 0 1) #\Space) :to-be-truthy)
        (expect (char= (%screen-char old 0 2) #\c) :to-be-truthy)
        (expect (char= (%screen-char new 0 0) #\Space) :to-be-truthy)
        (expect (char= (%screen-char new 0 1) #\c) :to-be-truthy)
        (expect (char= (%screen-char new 0 2) #\Space) :to-be-truthy))))

  (it "leaves the screen untouched for a column holding only :empty and :space"
    (let ((column (%test-column (list :empty :space :empty :space :empty) :length 3))
          (styles (%styles 3))
          (screen (make-screen 1 4)))
      (cl-cmatrix::%draw-column screen 0 column 1 4 1 styles nil)
      (with-soft-assertions
        (loop for row below 4
              do (expect (char= (%screen-char screen 0 row) #\Space) :to-be-truthy))))))

(describe "matrix-draw"
  (it "draws column index I at screen x = 2I and never writes an odd screen column"
    (let* ((columns (loop for glyph in '(#\a #\b #\c)
                          collect (%test-column (list :empty :empty glyph :empty :empty)
                                                :heads '(2) :length 3)))
           (state (%state-with-columns 5 4 columns))
           (screen (%draw-state state)))
      (with-soft-assertions
        (expect (= (length (matrix-state-columns state)) (matrix-state-column-count 5))
                :to-be-truthy)
        (expect (char= (%screen-char screen 0 1) #\a) :to-be-truthy)
        (expect (char= (%screen-char screen 2 1) #\b) :to-be-truthy)
        (expect (char= (%screen-char screen 4 1) #\c) :to-be-truthy)
        (loop for x in '(1 3)
              do (loop for y below 4
                       do (expect (char= (%screen-char screen x y) #\Space) :to-be-truthy))))))

  (it "reproduces every character cell of an advanced frame at x = 2I and blanks the rest"
    (let ((state (make-matrix-state 21 24 :random-state (sb-ext:seed-random-state 30)))
          (checked 0))
      (dotimes (i 60) (setf state (matrix-advance state)))
      (let ((screen (%draw-state state)))
        (with-soft-assertions
          (loop for index below (length (matrix-state-columns state))
                for column = (svref (matrix-state-columns state) index)
                do (loop for row from 1 to 24
                         for cell = (column-cell-at column row)
                         for drawn = (%screen-char screen (* 2 index) (1- row))
                         do (if (characterp cell)
                                (progn (incf checked)
                                       (expect (char= drawn cell) :to-be-truthy))
                                (expect (char= drawn #\Space) :to-be-truthy))))
          (expect (plusp checked) :to-be-truthy)))))

  (it "a :rainbow COLOR draws each column's trail in a different scheme, cycled by index"
    (let* ((schemes (coerce (list-color-schemes) 'simple-vector))
           (columns (loop repeat 3
                          collect (%test-column (list :empty :empty #\a #\b :empty)
                                                :heads '(3) :length 3)))
           (state (%state-with-columns 5 4 columns :color :rainbow))
           (screen (%draw-state state)))
      (with-soft-assertions
        (loop for index below 3
              do (expect (equal (%screen-style screen (* 2 index) 1)
                                (matrix-cell-style (aref schemes (mod index (length schemes)))
                                                   1 3))
                         :to-be-truthy))
        (expect (not (equal (%screen-style screen 0 1) (%screen-style screen 2 1)))
                :to-be-truthy))))

  (it "renders a lit non-head row bold when STATE's BOLD is true, and plain when it is false"
    (flet ((trail-bold-p (&rest options)
             (let* ((columns (loop repeat 2
                                   collect (%test-column (list :empty :empty #\a #\b :empty)
                                                         :heads '(3) :length 3)))
                    (screen (%draw-state (apply #'%state-with-columns 3 4 columns options))))
               (%screen-bold-p screen 0 1))))
      (with-soft-assertions
        (expect (trail-bold-p :bold t) :to-be-truthy)
        (expect (not (trail-bold-p)) :to-be-truthy))))

  (it "leaves even the head unbold when STATE's NO-BOLD-P is set"
    (flet ((head-bold-p (&rest options)
             (let* ((columns (loop repeat 2
                                   collect (%test-column (list :empty :empty #\a #\b :empty)
                                                         :heads '(3) :length 3)))
                    (screen (%draw-state (apply #'%state-with-columns 3 4 columns options))))
               (%screen-bold-p screen 0 2))))
      (with-soft-assertions
        (expect (head-bold-p) :to-be-truthy)
        (expect (not (head-bold-p :no-bold-p t)) :to-be-truthy))))

  (it "feeds random-bold the screen x and the internal row, and varies it with the tick"
    (flet ((drawn (tick)
             (let* ((columns (loop repeat 2
                                   collect (%test-column (list :empty :empty #\a #\b :empty)
                                                         :heads '(3) :length 3)))
                    (state (%state-with-columns 3 4 columns :random-bold-p t)))
               (setf (matrix-state-tick state) tick)
               (%screen-bold-p (%draw-state state) 2 1))))
      (with-soft-assertions
        (loop for tick from 0
              for expected in '(nil t nil t)
              do (expect (eq (drawn tick) expected) :to-be-truthy)))))

  (it "draws an old-style column's markers from internal row 0 down"
    (let* ((columns (list (%test-column (list :head-marker :pipe #\z :empty)
                                        :heads '(0) :length 3)
                          (%test-column (list :empty :empty :empty :empty) :length 3)))
           (state (%state-with-columns 3 3 columns :old-style-p t))
           (screen (%draw-state state)))
      (with-soft-assertions
        (expect (char= (%screen-char screen 0 0) #\&) :to-be-truthy)
        (expect (char= (%screen-char screen 0 1) #\|) :to-be-truthy)
        (expect (char= (%screen-char screen 0 2) #\z) :to-be-truthy)
        (expect (%screen-bold-p screen 0 0) :to-be-truthy)
        (expect (not (%screen-bold-p screen 0 1)) :to-be-truthy)
        (loop for y below 3
              do (expect (char= (%screen-char screen 1 y) #\Space) :to-be-truthy)))))

  (it "centers short messages, clips long messages, and ignores empty messages"
    (let ((short-screen (make-screen 5 4))
          (long-screen (make-screen 5 4))
          (empty-screen (make-screen 5 4)))
      (cl-cmatrix::matrix-draw-message short-screen 5 4 "hi")
      (cl-cmatrix::matrix-draw-message long-screen 5 4 "toolong")
      (cl-cmatrix::matrix-draw-message empty-screen 5 4 nil)
      (cl-cmatrix::matrix-draw-message empty-screen 5 4 "")
      (with-soft-assertions
        (expect (char= (%screen-char short-screen 0 2) #\Space) :to-be-truthy)
        (expect (char= (%screen-char short-screen 1 2) #\h) :to-be-truthy)
        (expect (char= (%screen-char short-screen 2 2) #\i) :to-be-truthy)
        (loop for x below 5
              for expected across "toolo"
              do (expect (char= (%screen-char long-screen x 2) expected) :to-be-truthy))
        (expect (char= (%screen-char empty-screen 0 2) #\Space) :to-be-truthy)))))

(describe "--message control character sanitization"

  (it "puts a control character on the screen verbatim: the substitution is not cl-cmatrix's"
    (let ((screen (make-screen 5 3)))
      (cl-cmatrix::matrix-draw-message screen 5 3 (string (code-char #x1b)))
      (expect (= (char-code (%screen-char screen 2 1)) #x1b) :to-be-truthy)))

  (it "emits a benign message's own characters, and frames it with ESC and LF only"
    (let ((baseline (%message-frame (%repeated-message (char-code #\.) 3))))
      (with-soft-assertions
        (expect (= (count #\. baseline) 3) :to-be-truthy)
        (expect (equal (%control-codes-in baseline) (list #x0a #x1b)) :to-be-truthy))))

  (it-each ((#x00) (#x1b) (#x1f) (#x7f) (#x80) (#x9f))
      "a message of U+~4,'0X leaves no control byte in the emitted frame"
      (code)
    (let ((baseline (%message-frame (%repeated-message (char-code #\.) 3)))
          (probe (%message-frame (%repeated-message code 3))))
      (with-soft-assertions
        (expect (= (count (code-char code) probe)
                   (count (code-char code) baseline))
                :to-be-truthy)
        (expect (equal (%control-codes-in probe) (%control-codes-in baseline))
                :to-be-truthy))))

  (it "passes ordinary characters through untouched: over-sanitizing is a defect too"
    (let* ((codes (list #x21 #x41 #x7e #xa0 #xe9 #x3bb #x3042))
           (frame (%message-frame (coerce (mapcar #'code-char codes) 'string)
                                  :width 15)))
      (with-soft-assertions
        (loop for code in codes
              do (expect (find (code-char code) frame) :to-be-truthy)))))

  (it "draws a space message as a styled region rather than dropping it"
    (let ((spaces (%message-frame "   "))
          (none (%message-frame nil)))
      (with-soft-assertions
        (expect (not (string= spaces none)) :to-be-truthy)
        (expect (equal (%control-codes-in spaces) (%control-codes-in none))
                :to-be-truthy))))

  (it "holds for RUN-STATE-RENDER, the path --message actually travels"
    (let ((probe (run-state-render (%message-run-state (%repeated-message #x1b 3))))
          (baseline (run-state-render (%message-run-state "..."))))
      (with-soft-assertions
        (expect (= (count #\. baseline) 3) :to-be-truthy)
        (expect (= (count (code-char #x1b) probe)
                   (count (code-char #x1b) baseline))
                :to-be-truthy)
        (expect (equal (%control-codes-in probe) (%control-codes-in baseline))
                :to-be-truthy)))))

(describe "%lambda-glyph"
  (it "is upstream's own U+03BB, pinned by code point rather than by identity"
    (expect (= (char-code (cl-cmatrix::%lambda-glyph)) #x3bb) :to-be-truthy)))

(describe "%random-bold-cell-p"
  (it-each ((0 0 0 nil) (1 0 0 t) (0 1 0 t) (0 0 1 t) (1 1 0 nil)
            (2 0 0 nil) (0 2 0 nil) (2 1 0 t) (1 2 0 t)
            (2 2 0 nil) (2 2 1 t) (3 2 1 nil) (1 0 1 nil))
      "x ~A, row ~A, tick ~A is ~A"
      (x row tick expected)
    (expect (cl-cmatrix::%random-bold-cell-p x row tick) :to-equal expected)))

(describe "%column-color"
  (it "returns COLOR unchanged when RAINBOW-SCHEMES is NIL"
    (expect (eq (cl-cmatrix::%column-color 3 :cyan nil) :cyan) :to-be-truthy))

  (it "cycles through RAINBOW-SCHEMES by column index, wrapping at its length"
    (let ((schemes (coerce (list-color-schemes) 'simple-vector)))
      (with-soft-assertions
        (expect (eq (cl-cmatrix::%column-color 0 :rainbow schemes) (aref schemes 0))
                :to-be-truthy)
        (expect (eq (cl-cmatrix::%column-color (length schemes) :rainbow schemes)
                    (aref schemes 0))
                :to-be-truthy)
        (expect (eq (cl-cmatrix::%column-color 1 :rainbow schemes) (aref schemes 1))
                :to-be-truthy)))))
