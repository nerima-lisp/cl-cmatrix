
(in-package #:cl-cmatrix)

(defmacro define-registry-queries (list-name predicate-name registry-var)
  "Define LIST-NAME as a function of no arguments returning every key of
REGISTRY-VAR (a DEFPARAMETER alist of (KEY . VALUE) conses, defined earlier
in the same file) in REGISTRY-VAR's own definition order, and PREDICATE-NAME
as a function of one argument, NAME, true when NAME is one of those keys.
LIST-NAME, PREDICATE-NAME, and REGISTRY-VAR are all read as literal syntax --
symbols naming the functions and the registry to define over -- never
evaluated as forms, so there is nothing here for evaluation order or
multiple-evaluation to disturb."
  `(progn
     (defun ,list-name ()
       ,(format nil "Return every registered name in ~A, in its definition order." registry-var)
       (mapcar #'car ,registry-var))
     (defun ,predicate-name (name)
       ,(format nil "True when NAME is a registered entry of ~A." registry-var)
       (and (assoc name ,registry-var) t))))
