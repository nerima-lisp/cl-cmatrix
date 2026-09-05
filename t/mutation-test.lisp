
(in-package #:cl-cmatrix/test)

(defun %read-defun-forms (pathname)
  "Return every top-level DEFUN form read from PATHNAME. Read with *PACKAGE*
bound to CL-CMATRIX so every symbol in the returned forms -- the function
name, parameters, and any CL-CMATRIX function it calls -- resolves to the
same symbol the real, loaded definition uses."
  (let ((*package* (find-package "CL-CMATRIX")))
    (with-open-file (stream pathname)
      (loop for form = (read stream nil :eof)
            until (eq form :eof)
            when (and (consp form) (eq (first form) 'cl:defun))
              collect form))))

(defun %find-defun-form (relative-path name)
  "Read RELATIVE-PATH's DEFUN named NAME, matching by symbol name (not
identity) since READ interns the file's symbols into *PACKAGE* at read time,
not the target file's own package."
  (let ((pathname (asdf:system-relative-pathname "cl-cmatrix" relative-path))
        (target-name (string name)))
    (or (find target-name (%read-defun-forms pathname)
              :key (lambda (form) (string (second form)))
              :test #'string=)
        (error "No DEFUN ~A found in ~A." name pathname))))

(defun %defun-lambda-list (defun-form)
  (third defun-form))

(defun %defun-body-form (defun-form)
  "Return DEFUN-FORM's body as a single form, skipping a leading docstring
and wrapping multiple body forms in a PROGN."
  (let ((body (cdddr defun-form)))
    (when (and (stringp (first body)) (rest body))
      (setf body (rest body)))
    (if (rest body) (cons 'cl:progn body) (first body))))

(defun %muffle-if-possible (condition)
  "Invoke CONDITION's MUFFLE-WARNING restart when it has one. Conditional
because a WARNING signalled outside the compiler need not offer the restart,
and calling MUFFLE-WARNING without one signals a CONTROL-ERROR of its own."
  (let ((restart (find-restart 'muffle-warning condition)))
    (when restart (invoke-restart restart))))

(defun %eval-with-bindings (form lambda-list argument-forms)
  "Evaluate FORM with LAMBDA-LIST bound to ARGUMENT-FORMS, muffling compiler
warnings from invalid mutants."
  (handler-bind ((warning #'%muffle-if-possible))
    (eval `(let ,(mapcar #'list lambda-list argument-forms) ,form))))

(defun %mutation-oracle (lambda-list cases)
  "Return a CL-WEAVE:RUN-MUTATIONS test function asserting MUTATED-FORM still
satisfies every (ARGUMENT-FORMS EXPECTED) entry in CASES. A mismatch signals
an assertion failure via EXPECT, which RUN-MUTATIONS reports as a killed
mutation; matching every case leaves the mutation looking survived.

Cases are checked in order and the first mismatch aborts the rest, which is
what lets a battery hold arguments that only the real bounds checks make
safe. See the case tables below."
  (lambda (mutated-form mutation)
    (declare (ignore mutation))
    (dolist (case cases t)
      (destructuring-bind (argument-forms expected) case
        (expect (%eval-with-bindings mutated-form lambda-list argument-forms)
                :to-equal expected)))))

(defun %assert-full-mutation-kill (relative-path name cases)
  "Mutate the DEFUN named NAME in RELATIVE-PATH and assert CASES kills every
mutation (a mutation score of 1.0), i.e. the case battery is strong enough to
notice every one-operator change to the real implementation.

The non-empty check is not a formality: CL-WEAVE scores a function it could
not mutate as a perfect 1.0, so without it a target built from operators
outside the mutation tables would pass this assertion while proving nothing.
ASSERT-MUTATION-SCORE separately refuses any run with an ERRORED mutation, so
a mutated bounds check that runs off the end of a buffer fails here too."
  (let* ((defun-form (%find-defun-form relative-path name))
         (lambda-list (%defun-lambda-list defun-form))
         (body (%defun-body-form defun-form))
         (results (run-mutations body (%mutation-oracle lambda-list cases))))
    (expect (plusp (length results)) :to-be-truthy)
    (assert-mutation-score results 1.0)))

(defun %expect-battery-matches (function cases)
  "Assert CASES describes the real, loaded FUNCTION. The mutation run reaches
a score of 1.0 whenever the battery distinguishes the unmutated body from
every mutant -- including when the battery's EXPECTED values are wrong in a
way the mutants happen not to reproduce. Pinning the battery against the live
function first is what rules that out."
  (dolist (case cases)
    (destructuring-bind (argument-forms expected) case
      (expect (apply function (mapcar #'eval argument-forms))
              :to-equal expected))))


(defparameter +column-advances-p-cases+
  '((((cl-cmatrix::%make-column :update 2) t 3) t)
    (((cl-cmatrix::%make-column :update 2) t 2) nil)
    (((cl-cmatrix::%make-column :update 2) t 1) nil)
    (((cl-cmatrix::%make-column :update 1) t 2) t)
    (((cl-cmatrix::%make-column :update 1) t 1) nil)
    (((cl-cmatrix::%make-column :update 3) t 4) t)
    (((cl-cmatrix::%make-column :update 3) t 3) nil)
    (((cl-cmatrix::%make-column :update 3) nil 1) t)
    (((cl-cmatrix::%make-column :update 1) nil 1) t))
  "Cases for %COLUMN-ADVANCES-P: (ARGUMENT-FORMS EXPECTED) pairs. UPDATE runs
over the whole range %SPAWN-COLUMN draws from (1..+MAX-UPDATE-THRESHOLD+) and
ASYNC-COUNT straddles each threshold on both sides -- one below, exactly on
it, and one above -- so the strict > is pinned rather than merely exercised.
The last two cases hold ASYNCP false with an ASYNC-COUNT that would otherwise
block the column, pinning upstream's -a-off shortcut where every column
advances on every frame regardless of its threshold.")


(defparameter +column-head-p-cases+
  '((((cl-cmatrix::%make-column :heads #*01100) 1) t)
    (((cl-cmatrix::%make-column :heads #*01100) 2) t)
    (((cl-cmatrix::%make-column :heads #*01100) 0) nil)
    (((cl-cmatrix::%make-column :heads #*01100) 3) nil)
    (((cl-cmatrix::%make-column :heads #*01100) 4) nil)
    (((cl-cmatrix::%make-column :heads #*01100) 5) nil)
    (((cl-cmatrix::%make-column :heads #*01100) -1) nil)
    (((cl-cmatrix::%make-column :heads #*11111) 0) t)
    (((cl-cmatrix::%make-column :heads #*00001) 4) t))
  "Cases for COLUMN-HEAD-P: (ARGUMENT-FORMS EXPECTED) pairs. The first case is
an in-bounds head row and must stay first (see the commentary above). The rest
straddle both ends of the HEIGHT+1 element buffer: the lowest and highest
valid indices, one index past each of them, and -- via the all-ones and
last-bit-set columns -- proof that index 0 and index (1- (LENGTH HEADS)) are
both genuinely inside the range rather than rejected by an off-by-one guard.")


(defparameter +column-cell-at-cases+
  '((((cl-cmatrix::%make-column :cells #(:empty #\a :space)) 1) #\a)
    (((cl-cmatrix::%make-column :cells #(:empty #\a :space)) 2) :space)
    (((cl-cmatrix::%make-column :cells #(:empty #\a :space)) 0) :empty)
    (((cl-cmatrix::%make-column :cells #(:empty #\a :space)) 3) :empty)
    (((cl-cmatrix::%make-column :cells #(:empty #\a :space)) -1) :empty)
    (((cl-cmatrix::%make-column :cells #(#\z :head-marker :pipe)) 0) #\z)
    (((cl-cmatrix::%make-column :cells #(#\z :head-marker :pipe)) 2) :pipe))
  "Cases for COLUMN-CELL-AT: (ARGUMENT-FORMS EXPECTED) pairs. The first case
is an in-bounds non-:EMPTY cell and must stay first (see the commentary
above). The table spans the whole cell vocabulary this accessor has to return
unchanged -- a CHARACTER, :SPACE, :HEAD-MARKER's neighbours, :PIPE, and a
stored :EMPTY -- and both buffer ends, including a stored :EMPTY at a valid
index next to the synthesised :EMPTY at an invalid one. Those two must agree,
which is what makes the out-of-range answer indistinguishable from a real
cell and therefore worth pinning.")


(describe "src/state.lisp: %COLUMN-ADVANCES-P mutation coverage"
  (it "the case battery matches the live function on every case"
    (with-soft-assertions
      (%expect-battery-matches #'cl-cmatrix::%column-advances-p
                               +column-advances-p-cases+)))

  (it "every mutation of %COLUMN-ADVANCES-P's body is killed by the battery"
    (%assert-full-mutation-kill
     "src/state.lisp" 'cl-cmatrix::%column-advances-p
     +column-advances-p-cases+)))

(describe "src/column.lisp: COLUMN-HEAD-P mutation coverage"
  (it "the case battery matches the live function on every case"
    (with-soft-assertions
      (%expect-battery-matches #'column-head-p +column-head-p-cases+)))

  (it "every mutation of COLUMN-HEAD-P's body is killed by the battery"
    (%assert-full-mutation-kill
     "src/column.lisp" 'cl-cmatrix::column-head-p
     +column-head-p-cases+)))

(describe "src/column.lisp: COLUMN-CELL-AT mutation coverage"
  (it "the case battery matches the live function on every case"
    (with-soft-assertions
      (%expect-battery-matches #'column-cell-at +column-cell-at-cases+)))

  (it "every mutation of COLUMN-CELL-AT's body is killed by the battery"
    (%assert-full-mutation-kill
     "src/column.lisp" 'cl-cmatrix::column-cell-at
     +column-cell-at-cases+)))
