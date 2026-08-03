;;;; t/mutation-test.lisp
;;;;
;;;; Mutation testing, per nerima-lisp/.github's TEST_STANDARD.md: SB-COVER's
;;;; line/branch coverage proves a line executed, not that a wrong result
;;;; there would be caught. RUN-MUTATIONS mutates a pure function's body
;;;; (flipping comparison/arithmetic operators and boolean literals) and
;;;; re-checks each variant against the same case battery a unit test would
;;;; use; a mutation the battery fails to notice ("survived") marks exactly
;;;; that gap. The body is read live from src/column.lisp on every run (never
;;;; copied into this file), so there is nothing here to fall out of sync
;;;; with the real implementation. Follows nerima-lisp/cl-tty-kit's
;;;; contrib/weave-mutation-tests.lisp pattern, folded into the main suite
;;;; rather than kept opt-in, since TEST_STANDARD.md gates this in CI.

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

(defun %eval-with-bindings (form lambda-list argument-forms)
  (eval `(let ,(mapcar #'list lambda-list argument-forms) ,form)))

(defun %mutation-oracle (lambda-list cases)
  "Return a CL-WEAVE:RUN-MUTATIONS test function asserting MUTATED-FORM still
satisfies every (ARGUMENT-FORMS EXPECTED) entry in CASES. A mismatch signals
an assertion failure via EXPECT, which RUN-MUTATIONS reports as a killed
mutation; matching every case leaves the mutation looking survived."
  (lambda (mutated-form mutation)
    (declare (ignore mutation))
    (dolist (case cases t)
      (destructuring-bind (argument-forms expected) case
        (expect (%eval-with-bindings mutated-form lambda-list argument-forms)
                :to-equal expected)))))

(defun %assert-full-mutation-kill (relative-path name cases)
  "Mutate the DEFUN named NAME in RELATIVE-PATH and assert CASES kills every
mutation (a mutation score of 1.0), i.e. the case battery is strong enough to
notice every one-operator change to the real implementation."
  (let* ((defun-form (%find-defun-form relative-path name))
         (lambda-list (%defun-lambda-list defun-form))
         (body (%defun-body-form defun-form))
         (results (run-mutations body (%mutation-oracle lambda-list cases))))
    (expect (plusp (length results)) :to-be-truthy)
    (assert-mutation-score results 1.0)))

(defparameter +column-row-lit-p-cases+
  '((((cl-cmatrix::%make-column :head 10 :length 4) 10) t)
    (((cl-cmatrix::%make-column :head 10 :length 4) 7) t)
    (((cl-cmatrix::%make-column :head 10 :length 4) 8) t)
    (((cl-cmatrix::%make-column :head 10 :length 4) 6) nil)
    (((cl-cmatrix::%make-column :head 10 :length 4) 11) nil)
    (((cl-cmatrix::%make-column :head 10 :length 4) -100) nil)
    (((cl-cmatrix::%make-column :head 10 :length 4) 100) nil)
    (((cl-cmatrix::%make-column :head 0 :length 1) 0) t)
    (((cl-cmatrix::%make-column :head 0 :length 1) -1) nil)
    (((cl-cmatrix::%make-column :head 0 :length 1) 1) nil))
  "Cases for COLUMN-ROW-LIT-P's mutation coverage below: (ARGUMENT-FORMS
EXPECTED) pairs spanning both inclusive boundaries of a lit trail (HEAD
itself and HEAD - LENGTH + 1), one row just past each boundary, and rows far
outside the trail in both directions.")

(describe "src/column.lisp: COLUMN-ROW-LIT-P mutation coverage"
  (it "the case battery matches the live function on every case"
    (with-soft-assertions
      (dolist (case +column-row-lit-p-cases+)
        (destructuring-bind (argument-forms expected) case
          (expect (apply #'column-row-lit-p (mapcar #'eval argument-forms))
                  :to-equal expected)))))

  (it "every mutation of COLUMN-ROW-LIT-P's body is killed by the case battery"
    (%assert-full-mutation-kill
     "src/column.lisp" 'cl-cmatrix::column-row-lit-p
     +column-row-lit-p-cases+)))
