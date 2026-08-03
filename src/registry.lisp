;;;; src/registry.lisp
;;;;
;;;; DEFINE-REGISTRY-QUERIES: the two lookup functions every named registry in
;;;; this codebase provides identically -- LIST-<name>S enumerating every
;;;; registered key, and <name>-P testing membership. +COLOR-SCHEMES+
;;;; (color-scheme.lisp) and +CHARSETS+ (glyphs.lisp) are both a DEFPARAMETER
;;;; alist of (KEYWORD . VALUE) conses with exactly this pair of readers
;;;; hand-written the same way; this macro is the single declarative
;;;; definition form both now expand into instead. The third lookup shape --
;;;; an actual value fetch that signals a condition when the key is
;;;; unregistered -- stays hand-written at each call site: its name and
;;;; visibility differ too much between registries (public CHARSET-GLYPHS
;;;; returning the looked-up value directly, vs. private %COLOR-SCHEME-RGBS
;;;; feeding three further DEFINE-COLOR-SCHEME-ACCESSOR-generated readers) for
;;;; folding it in here to read as anything but a forced abstraction.

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
