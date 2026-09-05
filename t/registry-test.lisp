
(in-package #:cl-cmatrix/test)

(defparameter +registry-test-entries+ '((:a . 1) (:b . 2) (:c . 3)))

(cl-cmatrix::define-registry-queries %list-registry-test-keys %registry-test-key-p
  +registry-test-entries+)

(describe "define-registry-queries"
  (it "LIST-NAME returns every key of the registry, in its definition order"
    (expect (equal (%list-registry-test-keys) '(:a :b :c)) :to-be-truthy))

  (it "PREDICATE-NAME is true for a registered key and false for an unregistered one"
    (with-soft-assertions
      (expect (%registry-test-key-p :b) :to-be-truthy)
      (expect (not (%registry-test-key-p :not-a-key)) :to-be-truthy))))
