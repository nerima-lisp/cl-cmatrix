
(in-package #:cl-cmatrix/test)

(defun %spawn-sentinel-p (column height)
  "True when COLUMN is exactly as %SPAWN-COLUMN leaves it: parallel HEIGHT+1
cell and head buffers, :EMPTY everywhere except internal row 1, which holds
the :SPACE sentinel upstream uses to arm the column's first spawn, and not a
single head bit set anywhere."
  (and (= (length (column-cells column)) (1+ height))
       (= (length (column-heads column)) (1+ height))
       (eq (column-cell-at column 1) :space)
       (loop for row from 0 to height
             always (and (or (= row 1) (eq (column-cell-at column row) :empty))
                         (not (column-head-p column row))))))

(describe "matrix-state-column-count"
  (it-each ((1 1) (2 1) (3 2) (4 2) (6 3) (7 4) (8 4) (20 10) (40 20))
      "a screen ~A cells wide holds ~A animated columns"
      (width expected)
    (expect (matrix-state-column-count width) :to-equal expected))

  (it-property "counts the even screen positions below WIDTH, since column I draws at x = 2I"
      ((width (gen-integer :min 1 :max 200)))
    (expect (matrix-state-column-count width)
            :to-equal (count-if #'evenp (loop for x below width collect x)))))

(describe "%assert-speed"
  (it "returns without signalling for a positive real"
    (expect (progn (cl-cmatrix::%assert-speed 1) :accepted) :to-equal :accepted))

  (it-each ((0) (-1) (:fast) ("2"))
      "signals INVALID-SPEED for ~S"
      (speed)
    (expect (signals invalid-speed (cl-cmatrix::%assert-speed speed)) :to-be-truthy)))

(describe "make-matrix-state"
  (it "builds one column per EVEN screen column, copies RANDOM-STATE, and starts at tick 0"
    (let* ((random-state (sb-ext:seed-random-state 1))
           (state (make-matrix-state 6 10 :random-state random-state)))
      (with-soft-assertions
        (expect (matrix-state-width state) :to-equal 6)
        (expect (matrix-state-height state) :to-equal 10)
        (expect (length (matrix-state-columns state)) :to-equal 3)
        (expect (matrix-state-tick state) :to-equal 0)
        (expect (eq (matrix-state-random-state state) random-state) :to-be-falsy))))

  (it "rounds an odd WIDTH up, so the last even screen column still gets a stream"
    (let ((state (make-matrix-state 7 10 :random-state (sb-ext:seed-random-state 4))))
      (expect (length (matrix-state-columns state)) :to-equal 4)))

  (it "spawns every column at upstream's creation sentinel, with no head lit yet"
    (let ((state (make-matrix-state 20 24 :random-state (sb-ext:seed-random-state 2))))
      (expect (every (lambda (column) (%spawn-sentinel-p column 24))
                     (matrix-state-columns state))
              :to-be-truthy)))

  (it "draws every column's LENGTH, SPACES and UPDATE inside upstream's ranges"
    (let* ((height 30)
           (state (make-matrix-state 40 height :random-state (sb-ext:seed-random-state 77))))
      (expect (every (lambda (column)
                       (and (<= +min-trail-length+
                                (column-length column)
                                (+ +min-trail-length+
                                   (max 1 (- height +min-trail-length+)) -1))
                            (<= 1 (column-spaces column) height)
                            (<= 1 (column-update column) +max-update-threshold+)))
                     (matrix-state-columns state))
              :to-be-truthy)))

  (it "keeps every UPDATE threshold beatable by the shared async cycle"
    (let ((state (make-matrix-state 60 20 :random-state (sb-ext:seed-random-state 78))))
      (expect (every (lambda (column) (< (column-update column) +async-count-cycle+))
                     (matrix-state-columns state))
              :to-be-truthy)))

  (it "spawns reproducibly from a fixed seed, down to each column's timing draws"
    (let* ((state (make-matrix-state 8 5 :random-state (sb-ext:seed-random-state 42)))
           (columns (matrix-state-columns state)))
      (with-soft-assertions
        (expect (map 'list #'column-length columns) :to-equal '(3 3 3 3))
        (expect (map 'list #'column-spaces columns) :to-equal '(4 3 2 3))
        (expect (map 'list #'column-update columns) :to-equal '(1 1 3 3))
        (expect (every (lambda (column)
                         (equalp (column-cells column)
                                 #(:empty :space :empty :empty :empty :empty)))
                       columns)
                :to-be-truthy))))

  (it "defaults COLOR to :green, BOLD off, ASYNCP on, and every other flag off"
    (let ((state (make-matrix-state 4 4 :random-state (sb-ext:seed-random-state 3))))
      (with-soft-assertions
        (expect (matrix-state-color state) :to-equal :green)
        (expect (matrix-state-bold state) :to-be-falsy)
        (expect (matrix-state-partial-bold-p state) :to-be-falsy)
        (expect (matrix-state-no-bold-p state) :to-be-falsy)
        (expect (matrix-state-old-style-p state) :to-be-falsy)
        (expect (matrix-state-lambda-p state) :to-be-falsy)
        (expect (matrix-state-random-bold-p state) :to-be-falsy)
        (expect (matrix-state-change-glyphs-p state) :to-be-falsy)
        (expect (matrix-state-asyncp state) :to-be-truthy)
        (expect (matrix-state-async-count state) :to-equal 0))))

  (it "stores BOLD when supplied"
    (let ((state (make-matrix-state 4 4 :bold t :random-state (sb-ext:seed-random-state 51))))
      (expect (matrix-state-bold state) :to-be-truthy)))

  (it-each ((:partial-bold-p matrix-state-partial-bold-p)
            (:no-bold-p matrix-state-no-bold-p)
            (:lambda-p matrix-state-lambda-p)
            (:random-bold-p matrix-state-random-bold-p)
            (:change-glyphs-p matrix-state-change-glyphs-p))
      "stores the ~A render flag when supplied"
      (key reader)
    (let ((state (apply #'make-matrix-state 4 4 :random-state (sb-ext:seed-random-state 53)
                        (list key t))))
      (expect (funcall reader state) :to-be-truthy)))

  (it "stores ASYNCP nil, which is what turns off the per-column update thresholds"
    (let ((state (make-matrix-state 4 4 :asyncp nil
                                     :random-state (sb-ext:seed-random-state 54))))
      (expect (matrix-state-asyncp state) :to-be-falsy)))

  (it "accepts :rainbow as a COLOR, even though it names no single scheme"
    (let ((state (make-matrix-state 4 4 :color :rainbow
                                     :random-state (sb-ext:seed-random-state 52))))
      (expect (matrix-state-color state) :to-equal :rainbow)))

  (it "caches the scheme registry as a simple vector only for :rainbow"
    (let ((rainbow (make-matrix-state 4 4 :color :rainbow
                                       :random-state (sb-ext:seed-random-state 55)))
          (plain (make-matrix-state 4 4 :color :cyan
                                    :random-state (sb-ext:seed-random-state 55))))
      (with-soft-assertions
        (expect (coerce (cl-cmatrix::matrix-state-rainbow-schemes rainbow) 'list)
                :to-equal (list-color-schemes))
        (expect (typep (cl-cmatrix::matrix-state-rainbow-schemes rainbow) 'simple-vector)
                :to-be-truthy)
        (expect (cl-cmatrix::matrix-state-rainbow-schemes plain) :to-be-falsy))))

  (it "stores a custom GLYPHS set and makes it readable back via MATRIX-STATE-GLYPHS"
    (let* ((glyphs (coerce '(#\X #\Y) 'simple-vector))
           (state (make-matrix-state 4 4 :glyphs glyphs
                                      :random-state (sb-ext:seed-random-state 50))))
      (expect (eq (matrix-state-glyphs state) glyphs) :to-be-truthy)))

  (it "treats OLD-STYLE-P as a render flag, not a second column representation"
    (let ((old-style (make-matrix-state 7 9 :old-style-p t
                                        :random-state (sb-ext:seed-random-state 61)))
          (new-style (make-matrix-state 7 9 :random-state (sb-ext:seed-random-state 61))))
      (with-soft-assertions
        (expect (matrix-state-old-style-p old-style) :to-be-truthy)
        (expect (matrix-state-old-style-p new-style) :to-be-falsy)
        (expect (every #'column-p (matrix-state-columns old-style)) :to-be-truthy)
        (expect (every (lambda (column) (%spawn-sentinel-p column 9))
                       (matrix-state-columns old-style))
                :to-be-truthy)
        (expect (equalp (matrix-state-columns old-style) (matrix-state-columns new-style))
                :to-be-truthy))))

  (it-each ((0 10) (10 -1))
      "signals INVALID-DIMENSIONS for width ~A height ~A"
      (width height)
    (expect (signals invalid-dimensions (make-matrix-state width height)) :to-be-truthy))

  (it "rejects a SPEED argument outright"
    (expect (signals program-error (apply #'make-matrix-state 4 4 (list :speed 1)))
            :to-be-truthy))

  (it "signals UNKNOWN-COLOR-SCHEME for an unregistered color, before spawning any column"
    (expect (signals unknown-color-scheme (make-matrix-state 4 4 :color :not-a-scheme))
            :to-be-truthy))

  (it-each ((#()) (#(1 2 3)) ((#\a 7 #\c)) ("ab") (:ascii) (nil))
      "signals INVALID-GLYPHS for ~S"
      (glyphs)
    (expect (signals invalid-glyphs (make-matrix-state 4 4 :glyphs glyphs))
            :to-be-truthy))

  (it "rejects a non-empty character vector that is merely not SIMPLE"
    (let ((adjustable (make-array 2 :adjustable t :initial-element #\a)))
      (expect (signals invalid-glyphs (make-matrix-state 4 4 :glyphs adjustable))
              :to-be-truthy)))

  (it "rejects an empty GLYPHS at construction, not partway through the advance loop"
    (expect (signals invalid-glyphs
              (let ((state (make-matrix-state 10 10 :glyphs #()
                                              :random-state (sb-ext:seed-random-state 91))))
                (dotimes (advance 12) (setf state (matrix-advance state)))
                state))
            :to-be-truthy))

  (it "signals INVALID-GLYPHS as a CL-CMATRIX-ERROR, catchable with the one base clause"
    (expect (handler-case (progn (make-matrix-state 10 10 :glyphs #()) :not-signalled)
              (cl-cmatrix-error () :caught))
            :to-equal :caught))

  (it "the condition's GLYPHS reader returns the offending value"
    (let* ((offender #(1 2 3))
           (reported (handler-case (progn (make-matrix-state 4 4 :glyphs offender) nil)
                       (invalid-glyphs (c) (invalid-glyphs-glyphs c)))))
      (expect (eq reported offender) :to-be-truthy))))
